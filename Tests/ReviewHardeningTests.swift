import XCTest
@testable import SessionPresentation

final class ReviewHardeningTests: XCTestCase {
    func testGPXIgnoresForeignNamespacesAndExtensionCoordinates() throws {
        let data = Data("""
        <gpx xmlns="http://www.topografix.com/GPX/1/1" xmlns:x="urn:other"><trk><trkseg>
        <trkpt lat="1" lon="2"/><x:trkpt lat="90" lon="90"/>
        <extensions><trkpt lat="40" lon="40"/></extensions><trkpt lat="2" lon="3"/>
        </trkseg><trkpt lat="30" lon="30"/></trk></gpx>
        """.utf8)
        XCTAssertEqual(try GPXDocument.parse(data).points, [.init(latitude: 1, longitude: 2), .init(latitude: 2, longitude: 3)])
        XCTAssertThrowsError(try GPXDocument.parse(Data("<other><trk><trkseg><trkpt lat='1' lon='2'/></trkseg></trk></other>".utf8)))
    }
    func testGPX10AndCommentsRemainSupported() throws {
        let text = "<gpx xmlns='http://www.topografix.com/GPX/1/0'><!-- <!DOCTYPE ignored> --><trk><name><![CDATA[<!ENTITY harmless>]]></name><trkseg><trkpt lat='1' lon='2'/></trkseg></trk></gpx>"
        XCTAssertEqual(try GPXDocument.parse(Data(text.utf8)).points.count, 1)
    }
    func testEncodedDeclarationsRejected() throws {
        for encoding in [String.Encoding.utf8, .utf16, .utf16BigEndian, .utf16LittleEndian, .utf32, .utf32BigEndian, .utf32LittleEndian] {
            let text = "<?xml version='1.0'?><!DOCTYPE gpx [<!ENTITY payload SYSTEM 'file:///etc/passwd'>]><gpx/>"
            XCTAssertThrowsError(try GPXDocument.parse(text.data(using: encoding)!)) {
                XCTAssertEqual($0 as? GPXImportError, .forbiddenDeclaration)
            }
        }
    }
    func testMaximumSavedRouteRoundTrips() throws {
        let points = (0..<100_000).map { RoutePoint(latitude: 1, longitude: Double($0) / 1_000_000) }
        let data = Data(GPXDocument.export(points).utf8)
        XCTAssertLessThan(data.count, GPXDocument.maximumBytes)
        XCTAssertEqual(try GPXDocument.parse(data).points.count, points.count)
    }
    func testCancellationReachesDetachedWorker() async throws {
        let started = expectation(description: "worker started")
        let cancelled = expectation(description: "worker observes cancellation")
        let gate = DispatchSemaphore(value: 0)
        let task = Task {
            try await GPXImporter.runCancellable {
                started.fulfill()
                _ = gate.wait(timeout: .now() + 5)
                if Task.isCancelled { cancelled.fulfill() }
                try Task.checkCancellation()
                return 42
            }
        }
        await fulfillment(of: [started], timeout: 3)
        task.cancel(); gate.signal()
        do { _ = try await task.value; XCTFail("Cancelled import returned data") }
        catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [cancelled], timeout: 3)
    }
    func testRecoveryPreservesSuccessiveCorruptionAndDiscardSurvivesReload() throws {
        let suite = "ReviewHardening." + UUID().uuidString
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        let list = RecoverableJSONList<String>(key: "pins", store: store)
        let a = Data("broken A".utf8), b = Data("broken B".utf8)
        store.set(a, forKey: "pins")
        XCTAssertTrue(list.save(["New pin"])) // No preceding load.
        store.set(b, forKey: "pins")
        XCTAssertTrue(list.save(["Another pin"]))
        XCTAssertEqual(list.recoveryCopies, [a,b])
        let exported = try XCTUnwrap(list.exportRecovery())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: exported) as? [String:Any])
        XCTAssertEqual(json["copiesBase64"] as? [String], [a,b].map { $0.base64EncodedString() })
        list.discardRecovery()
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: store.data(forKey:"pins")!), ["Another pin"])
        store.set(a, forKey:"pins"); _ = list.load(); list.discardRecovery()
        let reopened = RecoverableJSONList<String>(key:"pins", store:store)
        if case .missing = reopened.load() {} else { XCTFail("Discard recreated corrupt live data") }
        XCTAssertFalse(reopened.hasRecovery)
    }
    @MainActor func testMonitorLifecycleStopsOnceAndRejectsOldCallbacks() {
        let lifecycle = DiagnosticMonitorLifecycle()
        var starts = 0, stops = 0
        var tokens: [UUID] = []
        func update(_ value: Bool) {
            lifecycle.update(enabled: value, start: { tokens.append($0); starts += 1 }, stop: { stops += 1 })
        }
        update(false); update(true); update(true)
        XCTAssertEqual(starts, 1); XCTAssertEqual(stops, 0)
        let old = tokens[0]; XCTAssertTrue(lifecycle.accepts(old))
        update(false); update(false)
        XCTAssertEqual(stops, 1); XCTAssertFalse(lifecycle.accepts(old))
        update(true)
        XCTAssertFalse(lifecycle.accepts(old)); XCTAssertTrue(lifecycle.accepts(tokens[1]))
    }
}

private actor ControlledGPXLoader {
    var waiting: [String: CheckedContinuation<GPXImport, Error>] = [:]
    func load(_ url: URL) async throws -> GPXImport {
        try await withCheckedThrowingContinuation { waiting[url.lastPathComponent] = $0 }
    }
    func contains(_ key: String) -> Bool { waiting[key] != nil }
    func finish(_ key: String, result: Result<GPXImport, Error>) { waiting.removeValue(forKey:key)?.resume(with: result) }
}
@MainActor final class GPXImportReviewModelTests: XCTestCase {
    private let document = GPXImport(paths: [.init(id: 0, name: "Path", kind: .track,
        segments: [[.init(latitude:1,longitude:1),.init(latitude:2,longitude:2)]])], waypointCount:0)
    private func wait(_ loader: ControlledGPXLoader, _ key: String) async {
        for _ in 0..<200 { if await loader.contains(key) { return }; try? await Task.sleep(for:.milliseconds(5)) }
        XCTFail("Loader did not start")
    }
    private func settle(_ model: GPXImportReviewModel) async {
        for _ in 0..<200 { if !model.loading { return }; try? await Task.sleep(for:.milliseconds(5)) }
        XCTFail("Import did not finish")
    }
    func testLateErrorCannotOverwriteNewPreviewAndCancelCannotApply() async {
        let loader = ControlledGPXLoader()
        let model = GPXImportReviewModel(loader: { try await loader.load($0) })
        model.start(URL(fileURLWithPath:"/old")); await wait(loader,"old")
        model.start(URL(fileURLWithPath:"/new")); await wait(loader,"new")
        await loader.finish("new",result:.success(document)); await settle(model)
        await loader.finish("old",result:.failure(GPXImportError.malformedXML))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(model.error); XCTAssertEqual(model.document, document)
        model.cancel(); XCTAssertNil(model.takePoints())
    }
    func testWorkspaceChangeAndInterruptionRejectPendingCompletion() async {
        let loader = ControlledGPXLoader()
        var workspace = UUID()
        let model = GPXImportReviewModel(loader: { try await loader.load($0) }, currentWorkspace: { workspace })
        model.start(URL(fileURLWithPath:"/first")); await wait(loader,"first")
        workspace = UUID()
        await loader.finish("first",result:.success(document))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(model.document); XCTAssertNil(model.takePoints())
        model.start(URL(fileURLWithPath:"/second")); await wait(loader,"second")
        model.interrupt()
        await loader.finish("second",result:.success(document))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(model.document); XCTAssertNotNil(model.error)
        model.retry(); await wait(loader,"second")
        await loader.finish("second",result:.success(document)); await settle(model)
        XCTAssertEqual(model.takePoints(),document.points)
    }
    func testGapSelectionDefaultsToOneSectionButExplicitJoinRemainsAvailable() async {
        let doc = GPXImport(paths:[.init(id:0,name:"Separated",kind:.track,segments:[document.points,
            [.init(latitude:20,longitude:20),.init(latitude:21,longitude:21)]])],waypointCount:0)
        let model = GPXImportReviewModel(loader: { _ in doc })
        model.start(URL(fileURLWithPath:"/test")); await settle(model)
        XCTAssertEqual(model.selectedPoints.count,2)
        model.segmentIndex = -1
        XCTAssertEqual(model.takePoints()?.count,4)
    }
}
