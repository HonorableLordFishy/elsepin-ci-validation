#if !ELSEPIN_UI_TESTING || !targetEnvironment(simulator)
#error("Validation search adapter must never compile into a device app")
#endif
import MapKit
import Combine

struct PlaceSearchResponse { let mapItems: [MKMapItem] }
@MainActor final class PlaceSearchRequest {
    private let query: String
    private var cancelled = false
    private var pendingSlowResponse: CheckedContinuation<Void, Never>?
    private static var retryAttempts = 0
    init(_ request: MKLocalSearch.Request) { query = request.naturalLanguageQuery ?? "" }
    init(pointsOfInterest request: MKLocalPointsOfInterestRequest) { query = "poi" }
    func cancel() {
        cancelled = true
        // Release only after the real view cancels/replaces the request. A timer
        // could finish while XCTest was locating Cancel, moving the target away.
        let pending = pendingSlowResponse
        pendingSlowResponse = nil
        pending?.resume()
    }
    func start(seconds: Double = 7) async throws -> PlaceSearchResponse {
        guard ValidationFixture.enabled else { throw URLError(.unsupportedURL) }
        // 'retry' fails both normal and broader lookup once, then succeeds.
        if query == "retry" {
            Self.retryAttempts += 1
            if Self.retryAttempts <= 2 { throw URLError(.notConnectedToInternet) }
        }
        // Deliberately return a stale response after cancellation. The production
        // view must reject it using its task/generation guards, not fixture timing.
        if query == "slow" {
            await withCheckedContinuation { continuation in
                if cancelled { continuation.resume() }
                else { pendingSlowResponse = continuation }
            }
        } else { try await Task.sleep(for: .milliseconds(150)) }
        // Keep search results away from named fixture pins: the real search flow
        // deliberately substitutes a saved name at matching coordinates.
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 40.772, longitude: -73.973)))
        item.name = query == "slow" ? "OBSOLETE TEST RESULT" : "Test cafe result for \(query)"
        return PlaceSearchResponse(mapItems: [item])
    }
    static func configure(_ request: MKLocalSearch.Request, query: String) { request.naturalLanguageQuery = query }
    static func message(for error: Error) -> String {
        "You're offline. Reconnect and try again; saved pins still work."
    }
}
extension PlaceSearchIntent {
    var mapCategories: [MKPointOfInterestCategory] { [.restaurant] }
}
@MainActor final class PlaceSearchCompleter: ObservableObject {
    @Published var results: [MKLocalSearchCompletion] = []
    var query = ""
    func setRegion(_ region: MKCoordinateRegion?) {}
}
