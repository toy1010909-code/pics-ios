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

// MARK: - BLEスキャナ
final class PICSScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    static let manufacturerID: UInt16 = 0x01CE

    @Published var isScanning = false
    @Published var status = "停止中"
    @Published var packets: [PICSPacket] = []
    @Published var totalCount = 0

    private var central: CBCentralManager!

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func start() {
        guard central.state == .poweredOn else { status = "Bluetoothをオンにしてください"; return }
        // 重複アドバタイズも受け取る（信号の状態更新を逃さないため）
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
        guard let md = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              md.count >= 2 else { return }
        let company = UInt16(md[md.startIndex]) | (UInt16(md[md.startIndex + 1]) << 8) // little endian
        guard company == Self.manufacturerID else { return }

        let payload = md.dropFirst(2)
        let p = PICSPacket(time: Date(), rssi: RSSI.intValue,
                           peripheral: peripheral.identifier, payload: Data(payload))
        totalCount += 1
        packets.insert(p, at: 0)
        if packets.count > 50 { packets.removeLast() }
        // TODO: ここで payload を既存JS版と同じ仕様でパース（Type 2: 信号状態 など）
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
                    Text("受信数: \(scanner.totalCount)")
                    Button(scanner.isScanning ? "停止" : "スキャン開始") {
                        scanner.isScanning ? scanner.stop() : scanner.start()
                    }
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
            }
            .navigationTitle("PICS Viewer")
        }
    }
}

@main
struct PICSViewerApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}
