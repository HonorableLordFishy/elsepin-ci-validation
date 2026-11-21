#if !ELSEPIN_UI_TESTING || !targetEnvironment(simulator)
#error("Validation fixtures must never compile into a device app")
#endif
import SwiftUI
import MapKit

enum ValidationFixture {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--elsepin-ui-test")
    static var scenario: String { ProcessInfo.processInfo.environment["ELSEPIN_TEST_SCENARIO"] ?? "idle" }
    static var largeText: Bool { ProcessInfo.processInfo.arguments.contains("--large-text") }
    static var dark: Bool { ProcessInfo.processInfo.arguments.contains("--dark") }
    static var fallback: Bool { ProcessInfo.processInfo.arguments.contains("--accessibility-fallback") }
    static let longName = "Test botanical garden walking route beside the riverside observatory and community orchard"
    static let points = [CLLocationCoordinate2D(latitude: 40.768, longitude: -73.981),
                         CLLocationCoordinate2D(latitude: 40.770, longitude: -73.975),
                         CLLocationCoordinate2D(latitude: 40.779, longitude: -73.970)]
    static var route: PlannedRoute {
        let track = RouteTrack(points.map { RoutePoint($0) })!
        return PlannedRoute(name: longName,
            origin: RoutePlace(name: "Test garden entrance", coordinate: points[0]),
            destination: RoutePlace(name: longName, coordinate: points[2]),
            coordinates: points, track: track, source: .drawn, distance: track.length,
            notices: ["Synthetic test path only. These are not verified walking directions."],
            appleTravelTime: nil, instructions: [], calculatedAt: Date())
    }
    @MainActor static func prepare() {
        guard enabled, Bundle.main.bundleIdentifier == "com.n3mostudio.elsepin.validation" else {
            preconditionFailure("Disposable validation app must be launched explicitly by UI tests")
        }
        if scenario == "backup-settings", ProcessInfo.processInfo.arguments.contains("--preserve-backup-test-data") { return }
        // The validation bundle has its own sandbox and no App Group entitlement.
        // Every launch clears only that disposable sandbox, never the shipping app.
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: support.appendingPathComponent("Locus"))
        UserDefaults.standard.set(false, forKey: "locus.liveActivities")
        UserDefaults.standard.set(false, forKey: "locus.connectionAlerts")
        if scenario == "deleted-selection" {
            for index in (1...40).reversed() {
                _ = RecentlyDeletedStore.shared.keep(.place(BackupPlace(name: String(format: "Test deleted pin %02d", index),
                    latitude: points[1].latitude, longitude: points[1].longitude)))
            }
        }
        if scenario != "empty" {
            SavedPlace.save([SavedPlace(name: longName, latitude: points[1].latitude,
                longitude: points[1].longitude, favorite: true)], key: "locus.favorites")
            _ = TripLibrary().save(route: route, name: longName, mode: .walk,
                speed: 1.4, smooth: false, favorite: true)
        }
        if scenario == "import-review" { AppDataWorkspace.defaults.set(Data("corrupt disposable pins".utf8),forKey:"locus.favorites") }
    }
}

@main struct ValidationApp: App {
    init() { ValidationFixture.prepare() }
    var body: some Scene { WindowGroup { ValidationHost() } }
}

private struct ValidationHost: View {
    @StateObject private var session = SpoofSession()
    @StateObject private var pairing = PairingStore()
    @StateObject private var preferences = SessionPreferences.shared
    @StateObject private var privacy = AppPrivacyController()
    @StateObject private var updates = AppUpdateController()
    @StateObject private var reset = AppResetController()
    @StateObject private var library = TripLibrary()
    @State private var shortcut: LocusShortcut?
    @State private var details = false
    @State private var showSearch = false
    @State private var started = false
    @State private var runSession = false
    @State private var permissionsReady = false
    private var sessionScenario: Bool { ["moving", "paused", "connecting", "failed", "map-pins"].contains(ValidationFixture.scenario) }
    var body: some View {
        Group {
            if ValidationFixture.scenario == "route-editing" { ValidationRouteHarness() }
            else if ValidationFixture.scenario == "import-review" { ValidationImportHarness() }
            else if ValidationFixture.scenario == "backup-settings" { ValidationBackupHarness() }
            else if ValidationFixture.scenario == "deleted-selection" { NavigationStack { RecentlyDeletedView() } }
            else { RootView(incomingShortcut: $shortcut, incomingSessionDetails: $details) }
        }
            .modifier(AppearancePresentation())
            .frame(maxWidth: ProcessInfo.processInfo.arguments.contains("--narrow") ? 320 : .infinity)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                Text("SIMULATOR TEST DATA")
                    .accessibilityIdentifier("validation.banner")
                if ValidationFixture.scenario == "import-root" {
                    Button("Open validation GPX") {
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("root-flow.gpx")
                        try? Data(ValidationImportHarness.valid.utf8).write(to:url)
                        NotificationCenter.default.post(name:.locusImportGPX,object:url)
                    }.accessibilityIdentifier("validation.openGPX")
                }
                if sessionScenario && !runSession {
                    Button("Start validation session") { runSession = true }
                        .accessibilityIdentifier("validation.start")
                        .disabled(!permissionsReady)
                        .frame(minHeight: 44)
                }
                }.font(.system(size: 9, weight: .bold))
                    .padding(2).background(.yellow).foregroundStyle(.black)
            }
            .sheet(isPresented: $showSearch) {
                RoutePlaceSearchSheet(title: "Test search", onChoose: { _ in showSearch = false })
                    .environmentObject(library)
            }
            .environmentObject(session).environmentObject(session.recovery)
            .environmentObject(session.reliability).environmentObject(pairing)
            .environmentObject(preferences).environmentObject(privacy)
            .environmentObject(updates).environmentObject(reset)
            .environmentObject(library)
            .environment(\.shiftVisualStyle, preferences.visualStyle)
            .environment(\.shiftIconDesign, preferences.iconSelection.design)
            .environment(\.dynamicTypeSize, ValidationFixture.largeText ? .accessibility5 : .large)
            .preferredColorScheme(ValidationFixture.dark ? .dark : .light)
            .tint(ShiftPalette.color(.accent, style: preferences.visualStyle))
            .task {
                guard !started else { return }; started = true
                preferences.liveActivities = false; preferences.connectionAlerts = false
                // XCTest changes the simulator's real Accessibility settings.
                // Keep glass requested so Reduce Transparency must supply the fallback.
                preferences.glassPanel = ValidationFixture.scenario != "home-solid"
                // Settle the real system permission before timing the synthetic
                // connecting state. This never changes production permission flow.
                if sessionScenario {
                    _ = await SessionNotifications.shared.requestPermission()
                    permissionsReady = true
                }
                if !sessionScenario && !ValidationFixture.scenario.hasPrefix("home-") {
                    session.selectPin(ValidationFixture.points[0], name: "Test garden entrance")
                }
                if ValidationFixture.scenario == "pin-adjustment" {
                    preferences.mapPinSize = 48
                    preferences.mapPinVisibilityMiles = 20
                    session.selectPin(ValidationFixture.points[1], name: ValidationFixture.longName)
                }
                if ValidationFixture.scenario == "search" { showSearch = true }
            }
            .task(id: runSession) {
                guard runSession else { return }
                    _ = session.followRoute(ValidationFixture.route, pairing: pairing, smoothing: false)
                    if ValidationFixture.scenario == "paused" {
                        for _ in 0..<50 where session.effectivePhase != .active {
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                        session.toggleRoutePause()
                    }
            }
    }
}
