import SwiftUI
import CoreBluetooth

// MARK: - 受信モデル
struct PICSPacket: Identifiable {
    let id = UUID()
    let time: Date
    let rssi: Int
    let peripheral: UUID
    let payload: Data          // メーカーID(2byte)を除いた部分
    var hex: String { payload.map { String(format: "%02X", $0) }.joined(separator: " ") }
}

struct DebugAd: Identifiable {
    let id = UUID()
    let time: Date
    let rssi: Int
    let name: String
    let company: String
    let length: Int
}

// MARK: - BLEスキャナ
final class PICSScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    static let manufacturerID: UInt16 = 0x01CE

    @Published var isScanning = false
    @Published var status = "停止中"
    @Published var packets: [PICSPacket] = []
    @Published var totalCount = 0
    @Published var debugMode = false
    @Published var allAdCount = 0          // 全BLE広告の受信数（デバッグ用）
    @Published var debugAds: [DebugAd] = []

    private var central: CBCentralManager!

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func start() {
        guard central.state == .poweredOn else { status = "Bluetoothをオンにしてください"; return }
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        status = "スキャン中"
    }

    func stop() {
        central.stopScan()
        isScanning = false
        status = "停止中"
    }

    func clear() {
        packets = []; totalCount = 0; allAdCount = 0; debugAds = []
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: status = isScanning ? "スキャン中" : "停止中"
        case .unauthorized: status = "Bluetooth権限がありません（設定から許可）"
        case .poweredOff: status = "Bluetoothがオフです"
        default: status = "利用できません"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let md = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data

        // デバッグ：全広告を数えて、直近30件を表示
        if debugMode {
            allAdCount += 1
            var company = "なし"
            if let md = md, md.count >= 2 {
                let c = UInt16(md[md.startIndex]) | (UInt16(md[md.startIndex + 1]) << 8)
                company = String(format: "0x%04X", c)
            }
            let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
                ?? peripheral.name ?? "(名前なし)"
            debugAds.insert(DebugAd(time: Date(), rssi: RSSI.intValue, name: name,
                                    company: company, length: md?.count ?? 0), at: 0)
            if debugAds.count > 30 { debugAds.removeLast() }
        }

        guard let md = md, md.count >= 2 else { return }
        let company = UInt16(md[md.startIndex]) | (UInt16(md[md.startIndex + 1]) << 8) // little endian
        guard company == Self.manufacturerID else { return }

        let payload = md.dropFirst(2)
        let p = PICSPacket(time: Date(), rssi: RSSI.intValue,
                           peripheral: peripheral.identifier, payload: Data(payload))
        totalCount += 1
        packets.insert(p, at: 0)
        if packets.count > 50 { packets.removeLast() }
        // TODO: ここで payload を既存JS版と同じ仕様でパース
    }
}

// MARK: - UI
struct ContentView: View {
    @StateObject private var scanner = PICSScanner()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(scanner.status)
                    Text("PICS受信数: \(scanner.totalCount)")
                    Button(scanner.isScanning ? "停止" : "スキャン開始") {
                        scanner.isScanning ? scanner.stop() : scanner.start()
                    }
                    Button("クリア") { scanner.clear() }
                    Toggle("デバッグモード（全BLE広告を表示）", isOn: $scanner.debugMode)
                }
                Section("受信パケット（0x01CE）") {
                    if scanner.packets.isEmpty { Text("パケット未受信").foregroundStyle(.secondary) }
                    ForEach(scanner.packets) { p in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(p.time.formatted(date: .omitted, time: .standard))  RSSI \(p.rssi)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(p.hex).font(.system(.footnote, design: .monospaced))
                        }
                    }
                }
                if scanner.debugMode {
                    Section("デバッグ：全広告 \(scanner.allAdCount)件（直近30件）") {
                        if scanner.debugAds.isEmpty { Text("広告未受信").foregroundStyle(.secondary) }
                        ForEach(scanner.debugAds) { a in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(a.name)").font(.footnote)
                                Text("\(a.time.formatted(date: .omitted, time: .standard))  RSSI \(a.rssi)  メーカー \(a.company)  \(a.length)B")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("PICS Viewer")
        }
    }
}

@main
struct PICSViewerApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem { Label("受信", systemImage: "dot.radiowaves.left.and.right") }
                NearbyView()
                    .tabItem { Label("近くの信号機", systemImage: "map") }
            }
        }
    }
}
