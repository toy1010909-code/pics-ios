import SwiftUI
import MapKit
import CoreLocation

// MARK: - 交差点データ
struct Intersection: Identifiable, Decodable {
    let id = UUID()
    let p: String   // 都道府県
    let c: String   // 市町村
    let n: String   // 交差点名称
    let a: String   // 所在地
    let la: Double
    let lo: Double
    enum CodingKeys: String, CodingKey { case p, c, n, a, la, lo }
    var coordinate: CLLocationCoordinate2D { .init(latitude: la, longitude: lo) }
}

struct NearItem: Identifiable {
    let item: Intersection
    let dist: Double
    var id: UUID { item.id }
}

// MARK: - 現在地
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var denied = false
    private let mgr = CLLocationManager()

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyHundredMeters
        mgr.distanceFilter = 50
    }

    func start() {
        mgr.requestWhenInUseAuthorization()
        mgr.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .denied, .restricted: denied = true
        case .authorizedWhenInUse, .authorizedAlways:
            denied = false
            manager.startUpdatingLocation()
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }
}

// MARK: - 画面
struct NearbyView: View {
    @StateObject private var loc = LocationProvider()
    @State private var all: [Intersection] = []
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.0, longitude: 135.5),
        span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3))
    @State private var didCenter = false

    private var nearby: [NearItem] {
        guard let l = loc.location else { return [] }
        return all
            .map { NearItem(item: $0, dist: l.distance(from: CLLocation(latitude: $0.la, longitude: $0.lo))) }
            .sorted { $0.dist < $1.dist }
            .prefix(30)
            .map { $0 }
    }

    var body: some View {
        let list = nearby
        VStack(spacing: 0) {
            Map(coordinateRegion: $region,
                showsUserLocation: true,
                annotationItems: list.map { $0.item }) { it in
                MapMarker(coordinate: it.coordinate, tint: .green)
            }
            .frame(height: 300)

            if loc.denied {
                Text("位置情報が許可されていません。設定アプリから許可してください。")
                    .font(.footnote).foregroundStyle(.secondary).padding()
            } else if loc.location == nil {
                Text("現在地を取得中…").font(.footnote).foregroundStyle(.secondary).padding()
            }

            List(list) { n in
                Button {
                    withAnimation {
                        region = MKCoordinateRegion(center: n.item.coordinate,
                                                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(n.item.n).font(.subheadline).foregroundStyle(.primary)
                            Spacer()
                            Text(format(n.dist)).font(.subheadline).foregroundStyle(.blue)
                        }
                        Text("\(n.item.p) \(n.item.a)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("マップで開く") { openInMaps(n.item) }.tint(.green)
                }
            }
            .listStyle(.plain)
        }
        .onAppear {
            if all.isEmpty { all = Self.load() }
            loc.start()
        }
        .onChange(of: loc.location) { new in
            guard !didCenter, let new = new else { return }
            didCenter = true
            region = MKCoordinateRegion(center: new.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))
        }
    }

    private func format(_ m: Double) -> String {
        m < 1000 ? "\(Int(m)) m" : String(format: "%.1f km", m / 1000)
    }

    private func openInMaps(_ it: Intersection) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: it.coordinate))
        item.name = it.n
        item.openInMaps()
    }

    private static func load() -> [Intersection] {
        guard let url = Bundle.main.url(forResource: "intersections", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([Intersection].self, from: data) else { return [] }
        return arr
    }
}
