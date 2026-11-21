import XCTest
@testable import SessionPresentation

final class Build92RegressionTests: XCTestCase {
    struct Record: Codable, Equatable { let id: Int }
    final class Store: PersistedDataStore {
        var values: [String: Data] = [:]
        func data(forKey key: String) -> Data? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value as? Data }
        func removeObject(forKey key: String) { values[key] = nil }
    }
    func testNearLimitDenseTrackWithGapKeepsEveryVertexWithinBudget() {
        let distances = Array(repeating: 0.011, count: 99_998) + [556_000.0]
        let steps = RouteSamplingBudget.steps(distances: distances, spacing: 11.2)
        XCTAssertEqual(steps.count, 99_999)
        XCTAssertTrue(steps.allSatisfy { $0 >= 1 })
        XCTAssertEqual(1 + steps.reduce(0,+), 100_000)
    }
    func testBudgetReducesOnlyInterpolationForMixedSegments() {
        let distances = Array(repeating: 1.0, count: 89_999) + [150_000.0]
        let steps = RouteSamplingBudget.steps(distances: distances, spacing: 10)
        XCTAssertLessThanOrEqual(1 + steps.reduce(0,+), 100_000)
        XCTAssertEqual(Array(steps.prefix(89_999)), Array(repeating:1,count:89_999))
        XCTAssertGreaterThan(steps.last!,1)
    }
    func testNormalSamplingUnchangedAndTinySpacingDoesNotOverflow() {
        XCTAssertEqual(RouteSamplingBudget.steps(distances:[0,1,10,25],spacing:10),[1,1,1,3])
        let steps = RouteSamplingBudget.steps(distances:[1e300],spacing:1e-300)
        XCTAssertLessThanOrEqual(steps[0]+1,100_000)
    }
    func testDamagedHistoryWithoutPrimaryIsVisibleAndExportable() throws {
        let store=Store(), bytes=Data("damaged history".utf8)
        store.values["list.recovery.history"]=bytes
        let list=RecoverableJSONList<Record>(key:"list",store:store)
        XCTAssertTrue(list.hasRecovery)
        XCTAssertEqual(list.recoveryCopies,[bytes])
        let json=try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(list.exportRecovery())) as? [String:Any])
        XCTAssertEqual(json["copiesBase64"] as? [String],[bytes.base64EncodedString()])
        XCTAssertEqual(store.values["list.recovery.history"],bytes)
    }
    func testRestorePreservesOtherCopiesAndUnreadableLiveOriginal() throws {
        let store=Store()
        let recovered=[Record(id:1)], primary=try JSONEncoder().encode(recovered)
        store.values["list.recovery"]=primary
        let history=Data("broken envelope".utf8), live=Data("broken live".utf8)
        store.values["list.recovery.history"]=history; store.values["list"]=live
        let archive=RecoverableJSONList<Record>(key:"list",store:store)
        XCTAssertEqual(archive.restoreRecovery(),recovered)
        XCTAssertEqual(Set(archive.recoveryCopies),Set([history,live]))
        XCTAssertEqual(try JSONDecoder().decode([Record].self,from:XCTUnwrap(store.values["list"])),recovered)
    }
    func testRejectedRestoreDoesNotWriteOrDropRecovery() throws {
        let store=Store()
        store.values["list"]=try JSONEncoder().encode([Record(id:2)])
        store.values["list.recovery"]=try JSONEncoder().encode([Record(id:1)])
        let before=store.values
        XCTAssertNil(RecoverableJSONList<Record>(key:"list",store:store).restoreRecovery { _ in nil })
        XCTAssertEqual(store.values,before)
    }
    func testFilteredRestoreKeepsFullOriginalAndAllDistinctCorruptions() throws {
        let store=Store(); let list=RecoverableJSONList<Record>(key:"list",store:store)
        let records=(0..<30).map { Record(id:$0) }
        let original=try JSONEncoder().encode(records)
        store.values["list.recovery"]=original
        XCTAssertEqual(list.restoreRecovery(keepingOriginal:true) { Array($0.prefix(20)) }?.count,20)
        XCTAssertEqual(list.recoveryCopies,[original])
        for n in 0..<25 { store.values["list"]=Data("bad \(n)".utf8); XCTAssertTrue(list.save([])) }
        XCTAssertEqual(list.recoveryCopies.count,26,"Never silently cap away recovery originals")
        XCTAssertEqual(list.recoveryCopies.first,original)
    }
    func testCDATANameAndIgnoredLargeTextDoNotBecomeCoordinates() throws {
        let xml="<gpx><extensions><![CDATA[" + String(repeating:"x",count:100_000) + "]]></extensions><trk><name><![CDATA[Garden & lake]]></name><trkseg><trkpt lat='1' lon='2'/><trkpt lat='2' lon='3'/></trkseg></trk></gpx>"
        let result=try GPXDocument.parse(Data(xml.utf8))
        XCTAssertEqual(result.paths[0].name,"Garden & lake")
        XCTAssertEqual(result.points.count,2)
    }
    @MainActor func testCachedSelectionChangesAndClearsAcrossPathsAndCancel() async {
        let a=[RoutePoint(latitude:1,longitude:2),RoutePoint(latitude:2,longitude:3)]
        let b=[RoutePoint(latitude:20,longitude:20),RoutePoint(latitude:21,longitude:21)]
        let doc=GPXImport(paths:[GPXPath(id:0,name:"One",kind:.track,segments:[a,b]),GPXPath(id:1,name:"Two",kind:.route,segments:[b])],waypointCount:0)
        let model=GPXImportReviewModel(loader:{ _ in doc })
        model.start(URL(fileURLWithPath:"/synthetic"))
        for _ in 0..<100 where model.loading { await Task.yield() }
        XCTAssertFalse(model.loading); XCTAssertEqual(model.selectedPoints,a)
        model.segmentIndex = -1; XCTAssertEqual(model.selectedPoints,a+b)
        model.pathIndex=1; XCTAssertEqual(model.selectedPoints,b); XCTAssertTrue(model.canImport)
        model.pathIndex=99; XCTAssertTrue(model.selectedPoints.isEmpty); XCTAssertFalse(model.canImport)
        model.cancel(); XCTAssertTrue(model.selectedPoints.isEmpty); XCTAssertFalse(model.canImport)
    }
}
