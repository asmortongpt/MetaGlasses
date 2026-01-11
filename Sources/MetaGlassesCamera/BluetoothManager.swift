import Foundation
import CoreBluetooth
import Combine

/// Manages Bluetooth connection to Meta Ray-Ban smart glasses
@MainActor
public class BluetoothManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published public var isScanning: Bool = false
    @Published public var isConnected: Bool = false
    @Published public var connectionStatus: String = "Not Connected"
    @Published public var discoveredDevices: [CBPeripheral] = []
    @Published public var connectedDevice: CBPeripheral?
    @Published public var errorMessage: String?

    // MARK: - Private Properties

    private var centralManager: CBCentralManager!
    private var targetPeripheral: CBPeripheral?
    private let metaGlassesServiceUUID = CBUUID(string: "0000FE00-0000-1000-8000-00805F9B34FB") // Meta specific UUID (placeholder)

    // MARK: - Initialization

    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
        print("🔵 BluetoothManager initialized")
    }

    // MARK: - Public Methods

    /// Start scanning for Meta Ray-Ban glasses
    public func startScanning() {
        guard centralManager.state == .poweredOn else {
            errorMessage = "Bluetooth is not available. Please enable Bluetooth."
            print("❌ Bluetooth not powered on")
            return
        }

        isScanning = true
        connectionStatus = "Scanning for Meta Ray-Ban..."
        discoveredDevices.removeAll()

        // Scan for peripherals with Meta service UUID
        centralManager.scanForPeripherals(
            withServices: nil, // Scan for all devices, filter by name
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        print("🔍 Started scanning for Meta Ray-Ban glasses")

        // Auto-stop scanning after 10 seconds
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if isScanning {
                stopScanning()
            }
        }
    }

    /// Stop scanning for devices
    public func stopScanning() {
        guard isScanning else { return }

        centralManager.stopScan()
        isScanning = false

        if !isConnected {
            connectionStatus = "Scan complete"
        }

        print("⏹ Stopped scanning")
    }

    /// Connect to a specific peripheral
    public func connect(to peripheral: CBPeripheral) {
        stopScanning()
        targetPeripheral = peripheral
        connectionStatus = "Connecting to \(peripheral.name ?? "Meta Ray-Ban")..."

        centralManager.connect(peripheral, options: nil)
        print("🔗 Attempting to connect to \(peripheral.name ?? "Unknown")")
    }

    /// Disconnect from current device
    public func disconnect() {
        guard let peripheral = connectedDevice else {
            print("⚠️ No device connected")
            return
        }

        centralManager.cancelPeripheralConnection(peripheral)
        print("🔌 Disconnecting from \(peripheral.name ?? "device")")
    }

    /// Auto-connect to Meta Ray-Ban glasses if found
    public func autoConnect() async throws {
        guard !isConnected else {
            print("✅ Already connected")
            return
        }

        startScanning()

        // Wait for device to be discovered
        for _ in 0..<20 { // Check for 10 seconds (20 * 0.5s)
            if let metaDevice = discoveredDevices.first(where: { device in
                device.name?.lowercased().contains("meta") == true ||
                device.name?.lowercased().contains("ray-ban") == true ||
                device.name?.lowercased().contains("stories") == true
            }) {
                connect(to: metaDevice)

                // Wait for connection
                for _ in 0..<10 { // Wait up to 5 seconds
                    if isConnected {
                        return
                    }
                    try await Task.sleep(nanoseconds: 500_000_000)
                }

                throw BluetoothError.connectionTimeout
            }

            try await Task.sleep(nanoseconds: 500_000_000)
        }

        stopScanning()
        throw BluetoothError.deviceNotFound
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            connectionStatus = "Bluetooth state unknown"
        case .resetting:
            connectionStatus = "Bluetooth resetting..."
        case .unsupported:
            connectionStatus = "Bluetooth not supported"
            errorMessage = "This device does not support Bluetooth"
        case .unauthorized:
            connectionStatus = "Bluetooth not authorized"
            errorMessage = "Please enable Bluetooth permissions in Settings"
        case .poweredOff:
            connectionStatus = "Bluetooth is off"
            errorMessage = "Please turn on Bluetooth"
        case .poweredOn:
            connectionStatus = "Bluetooth ready"
            print("✅ Bluetooth powered on and ready")
        @unknown default:
            connectionStatus = "Unknown Bluetooth state"
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {

        // Filter for Meta Ray-Ban devices (or any device for testing)
        let deviceName = peripheral.name ?? "Unknown"

        // Add to discovered devices if not already present
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredDevices.append(peripheral)
            print("📱 Discovered: \(deviceName) (RSSI: \(RSSI))")

            // Auto-connect to Meta devices
            if deviceName.lowercased().contains("meta") ||
               deviceName.lowercased().contains("ray-ban") ||
               deviceName.lowercased().contains("stories") {
                print("🎯 Found Meta device: \(deviceName)")
                connect(to: peripheral)
            }
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        connectedDevice = peripheral
        connectionStatus = "Connected to \(peripheral.name ?? "Meta Ray-Ban")"
        stopScanning()

        // Discover services
        peripheral.delegate = self
        peripheral.discoverServices(nil)

        print("✅ Connected to \(peripheral.name ?? "device")")
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectionStatus = "Failed to connect"

        if let error = error {
            errorMessage = "Connection failed: \(error.localizedDescription)"
            print("❌ Connection failed: \(error.localizedDescription)")
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectedDevice = nil
        connectionStatus = "Disconnected"

        if let error = error {
            errorMessage = "Disconnected due to error: \(error.localizedDescription)"
            print("❌ Disconnected with error: \(error.localizedDescription)")
        } else {
            print("🔌 Disconnected from \(peripheral.name ?? "device")")
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("❌ Error discovering services: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else {
            print("⚠️ No services found")
            return
        }

        print("📋 Discovered \(services.count) services")

        // Discover characteristics for each service
        for service in services {
            print("  Service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("❌ Error discovering characteristics: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else {
            print("⚠️ No characteristics found for service \(service.uuid)")
            return
        }

        print("📋 Service \(service.uuid) has \(characteristics.count) characteristics")

        for characteristic in characteristics {
            print("  Characteristic: \(characteristic.uuid)")
        }
    }
}

// MARK: - Error Types

public enum BluetoothError: LocalizedError {
    case notPoweredOn
    case deviceNotFound
    case connectionTimeout
    case connectionFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .notPoweredOn:
            return "Bluetooth is not powered on"
        case .deviceNotFound:
            return "Meta Ray-Ban glasses not found. Make sure they are powered on and in pairing mode."
        case .connectionTimeout:
            return "Connection timed out. Please try again."
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        }
    }
}
