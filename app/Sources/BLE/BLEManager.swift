import CoreBluetooth
import UIKit
import CarKit

/// The devices heard while scanning, published twice a second so a busy room does not redraw the lists constantly.
final class ScanStore: ObservableObject {
    @Published var adverts: [Advert] = []
}

/// The car (or any device, from the debug screen) the app is connected to.
final class LinkStore: ObservableObject {
    @Published var state: LinkState = .idle
    @Published var peripheralID: UUID?
    @Published var name: String?
    @Published var services: [GattService] = []
    @Published var detected: CarProtocol?
    @Published var controlUUID: String?
    @Published var rssi: Int?
    @Published var battery: Int?
    @Published var lastFrame: [UInt8] = []
    @Published var maxWrite: Int?
    @Published var writeError: String?

    func reset(id: UUID?, name: String?) {
        peripheralID = id
        self.name = name
        services = []
        detected = nil
        controlUUID = nil
        rssi = nil
        battery = nil
        lastFrame = []
        maxWrite = nil
        writeError = nil
    }
}

/// CoreBluetooth for the whole app: scanning, one connection at a time, reading what the car offers, and writes.
/// Everything runs on the main queue.
final class BLEManager: NSObject, ObservableObject {
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var isScanning = false

    let scan = ScanStore()
    let link = LinkStore()
    let log = LogStore()

    /// The driver's hooks: the car can take the next frame, the car is ready to drive, the car is gone.
    var onWriteReady: (() -> Void)?
    var onReady: (() -> Void)?
    var onDisconnect: (() -> Void)?

    private var central: CBCentralManager!
    private var known: [UUID: CBPeripheral] = [:]
    private var adverts: [UUID: Advert] = [:]
    private var advertsChanged = false
    private var scanRequests = 0
    private var timers: [Timer] = []
    private(set) var peripheral: CBPeripheral?
    /// The device to stay connected to: connected again after a drop, until the driver disconnects.
    private var wanted: UUID?
    /// The car dropped when the app went to the background, taken back when it returns.
    private var pausedCar: UUID?
    private var pendingServices = 0
    private var gattRefreshQueued = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        schedule(every: 0.5) { [weak self] in self?.publishAdverts() }
        schedule(every: 2) { [weak self] in
            guard let p = self?.peripheral, p.state == .connected else { return }
            p.readRSSI()
        }
    }

    private func schedule(every interval: TimeInterval, _ block: @escaping () -> Void) {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in block() }
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    // MARK: Scanning

    /// Lists of devices ask for scanning while they are on screen; without a car the app scans anyway.
    func beginScan() {
        scanRequests += 1
        updateScanning()
    }

    func endScan() {
        scanRequests = max(0, scanRequests - 1)
        updateScanning()
    }

    private func updateScanning() {
        let busy = link.state == .ready || link.state == .discovering
        let should = central.state == .poweredOn && (scanRequests > 0 || !busy)
        guard should != isScanning else { return }
        if should {
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            log.add(.info, "Scanning")
        } else {
            if central.state == .poweredOn { central.stopScan() }
            log.add(.info, "Scan stopped")
        }
        isScanning = should
    }

    private func publishAdverts() {
        let now = Date()
        let before = adverts.count
        let current = peripheral?.identifier
        adverts = adverts.filter { $0.key == current || now.timeIntervalSince($0.value.lastSeen) < 60 }
        guard advertsChanged || adverts.count != before else { return }
        advertsChanged = false
        scan.adverts = adverts.values.sorted(by: BLEManager.listOrder)
    }

    /// Cars first, then named devices, then by name: a stable order, rows do not jump as signals vary.
    private static func listOrder(_ a: Advert, _ b: Advert) -> Bool {
        if a.isCar != b.isCar { return a.isCar }
        if (a.name == nil) != (b.name == nil) { return a.name != nil }
        let order = a.title.localizedCaseInsensitiveCompare(b.title)
        if order != .orderedSame { return order == .orderedAscending }
        return a.id.uuidString < b.id.uuidString
    }

    func advert(_ id: UUID) -> Advert? {
        adverts[id]
    }

    // MARK: Connection

    func connect(_ id: UUID) {
        wanted = id
        guard central.state == .poweredOn else { return } // connected when Bluetooth comes on
        if let current = peripheral, current.identifier == id, current.state != .disconnected { return }
        guard let p = known[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first else {
            log.add(.error, "Unknown device \(id.uuidString)")
            return
        }
        if let current = peripheral, current.identifier != id {
            central.cancelPeripheralConnection(current)
            onDisconnect?()
        }
        known[id] = p
        peripheral = p
        p.delegate = self
        let name = adverts[id]?.name ?? p.name ?? (id == Prefs.lastCarID ? Prefs.lastCarName : nil)
        link.reset(id: id, name: name)
        link.state = .connecting
        log.add(.info, "Connecting to \(name ?? id.uuidString)")
        central.connect(p, options: nil)
        updateScanning()
    }

    func disconnect() {
        wanted = nil
        pausedCar = nil
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
            log.add(.info, "Disconnected by the driver")
        }
        peripheral = nil
        link.reset(id: nil, name: nil)
        link.state = .idle
        onDisconnect?()
        updateScanning()
    }

    /// Drops the car when the app leaves the screen, once the driver's stop frame has gone; taken back on return.
    func pauseForBackground() {
        guard let p = peripheral else { return }
        pausedCar = p.identifier
        wanted = nil
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "Stop the car") {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            if let self, let p = self.peripheral, p.identifier == self.pausedCar {
                self.central.cancelPeripheralConnection(p)
                self.peripheral = nil
                self.link.state = .idle
                self.onDisconnect?()
                self.log.add(.info, "Disconnected: the app went to the background")
            }
            if task != .invalid {
                UIApplication.shared.endBackgroundTask(task)
                task = .invalid
            }
        }
    }

    func resumeFromBackground() {
        guard let id = pausedCar else { return }
        pausedCar = nil
        connect(id)
    }

    // MARK: Reading and writing

    private func allCharacteristics() -> [CBCharacteristic] {
        (peripheral?.services ?? []).flatMap { $0.characteristics ?? [] }
    }

    /// A characteristic by UUID, the cars' service FFF0 first when the UUID appears in more than one service.
    func characteristic(_ uuid: String) -> CBCharacteristic? {
        let target = uuid.uppercased()
        let matches = allCharacteristics().filter { $0.uuid.uuidString.uppercased() == target }
        return matches.first { $0.service?.uuid.uuidString.uppercased() == SLProtocol.service } ?? matches.first
    }

    func characteristic(service: String, uuid: String) -> CBCharacteristic? {
        let s = (peripheral?.services ?? []).first { $0.uuid.uuidString == service }
        return s?.characteristics?.first { $0.uuid.uuidString == uuid }
    }

    func writeType(for c: CBCharacteristic, preference: WritePreference) -> CBCharacteristicWriteType {
        let withResponse = c.properties.contains(.write)
        let without = c.properties.contains(.writeWithoutResponse)
        switch preference {
        case .withResponse: return withResponse || !without ? .withResponse : .withoutResponse
        case .withoutResponse: return without || !withResponse ? .withoutResponse : .withResponse
        case .auto: return without ? .withoutResponse : .withResponse
        }
    }

    /// Writes the bytes; false when they could not leave now (no connection, or the radio's queue is full).
    @discardableResult
    func write(_ bytes: [UInt8], to c: CBCharacteristic, type: CBCharacteristicWriteType, logged: Bool) -> Bool {
        guard let p = peripheral, p.state == .connected else { return false }
        if type == .withoutResponse && !p.canSendWriteWithoutResponse { return false }
        p.writeValue(Data(bytes), for: c, type: type)
        if logged {
            log.add(.tx, "\(c.uuid.uuidString) \(Hex.string(bytes))" + (type == .withResponse ? " (with response)" : ""))
        }
        return true
    }

    func read(_ c: CBCharacteristic) {
        peripheral?.readValue(for: c)
    }

    func setNotify(_ on: Bool, for c: CBCharacteristic) {
        peripheral?.setNotifyValue(on, for: c)
    }

    /// Picks the protocol and the characteristic to drive with: the one forced in the settings, else the one found.
    func chooseControl() {
        guard peripheral != nil else { return }
        let uuids = allCharacteristics().map { $0.uuid.uuidString }
        if let forced = Prefs.protocolChoice {
            link.detected = forced
            link.controlUUID = CarCatalog.control(for: forced, characteristics: uuids)
        } else if let found = CarCatalog.detect(characteristics: uuids, name: link.name) {
            link.detected = found.0
            link.controlUUID = found.1
        } else {
            link.detected = nil
            link.controlUUID = nil
        }
        if let proto = link.detected, let uuid = link.controlUUID {
            log.add(.info, "Driving with \(proto.title) on \(uuid)")
        } else {
            log.add(.error, "No known control characteristic: open the debug screen and share the services report")
        }
        onReady?()
    }

    private func finishDiscovery(_ p: CBPeripheral) {
        guard p.identifier == peripheral?.identifier else { return }
        link.maxWrite = p.maximumWriteValueLength(for: .withoutResponse)
        link.state = .ready
        refreshGatt()
        chooseControl()
        if link.controlUUID != nil { Prefs.remember(car: p.identifier, name: link.name) }
        updateScanning()
    }

    // MARK: The debug screen's view of the services

    private func queueGattRefresh() {
        guard !gattRefreshQueued else { return }
        gattRefreshQueued = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.gattRefreshQueued = false
            self?.refreshGatt()
        }
    }

    private func refreshGatt() {
        guard let p = peripheral else {
            link.services = []
            return
        }
        var services: [GattService] = []
        for (si, s) in (p.services ?? []).enumerated() {
            var characteristics: [GattCharacteristic] = []
            for (ci, c) in (s.characteristics ?? []).enumerated() {
                characteristics.append(BLEManager.snapshot(c, service: s, id: "\(si)-\(ci)"))
            }
            services.append(GattService(id: "\(si)", uuid: s.uuid.uuidString, isPrimary: s.isPrimary,
                                        characteristics: characteristics))
        }
        link.services = services
    }

    private static func snapshot(_ c: CBCharacteristic, service: CBService, id: String) -> GattCharacteristic {
        let descriptors = c.descriptors ?? []
        let user = descriptors.first { $0.uuid.uuidString == CBUUIDCharacteristicUserDescriptionString }
        return GattCharacteristic(
            id: id,
            serviceUUID: service.uuid.uuidString,
            uuid: c.uuid.uuidString,
            properties: c.properties,
            value: c.value,
            isNotifying: c.isNotifying,
            descriptors: descriptors.map { $0.uuid.uuidString },
            userDescription: user?.value as? String
        )
    }

    /// The connected device in text: what to paste or screenshot to work out an unknown car.
    func servicesReport() -> String {
        var lines = [AppInfo.summary]
        lines.append("Device: \(link.name ?? "unnamed") \(link.peripheralID?.uuidString ?? "")")
        let rssi = link.rssi.map { String($0) + " dBm" } ?? "?"
        let battery = link.battery.map { String($0) + "%" } ?? "?"
        let maxWrite = link.maxWrite.map { String($0) } ?? "?"
        let proto = link.detected?.title ?? "none found"
        lines.append("State: \(link.state.label), RSSI \(rssi), battery \(battery)")
        lines.append("Protocol: \(proto) on \(link.controlUUID ?? "-"), max write \(maxWrite) bytes")
        if let id = link.peripheralID, let ad = adverts[id] {
            lines.append("Advertisement: " + ad.details.joined(separator: "; "))
        }
        for s in link.services {
            lines.append("")
            lines.append("Service \(s.title)" + (s.isPrimary ? "" : " (secondary)"))
            for c in s.characteristics {
                var line = "  \(c.uuid)"
                if let name = CarCatalog.name(ofUUID: c.uuid) ?? c.userDescription { line += " \(name)" }
                line += " [\(c.properties.labels.joined(separator: ", "))]"
                if let value = c.value {
                    let bytes = [UInt8](value)
                    line += " = \(Hex.string(bytes))"
                    if let text = Hex.ascii(bytes) { line += " \"\(text)\"" }
                }
                if c.isNotifying { line += " (notifying)" }
                lines.append(line)
                if !c.descriptors.isEmpty { lines.append("    descriptors " + c.descriptors.joined(separator: ", ")) }
            }
        }
        return lines.joined(separator: "\n")
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        log.add(.info, "Bluetooth: \(central.state.label)")
        guard central.state == .poweredOn else {
            isScanning = false
            if peripheral != nil { link.state = .failed(central.state.problem ?? "Bluetooth is unavailable") }
            return
        }
        if let p = peripheral {
            if p.state != .connected {
                link.state = .connecting
                central.connect(p, options: nil)
            }
        } else if let id = wanted ?? Prefs.lastCarID {
            // the last car: a pending connection, made as soon as it is switched on and in range
            connect(id)
        }
        updateScanning()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let id = peripheral.identifier
        known[id] = peripheral
        let isNew = adverts[id] == nil
        var ad = adverts[id] ?? Advert(id: id, name: nil, rssi: RSSI.intValue, lastSeen: Date())
        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            ad.name = name
        } else if ad.name == nil {
            ad.name = peripheral.name
        }
        if RSSI.intValue != 127 { ad.rssi = RSSI.intValue } // 127: not available
        var uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        uuids += advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []
        if !uuids.isEmpty {
            ad.services = Array(Set(ad.services + uuids.map { $0.uuidString })).sorted()
        }
        if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            ad.manufacturerData = data
        }
        if let data = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            for (uuid, value) in data { ad.serviceData[uuid.uuidString] = value }
        }
        if let power = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber {
            ad.txPower = power.intValue
        }
        if let connectable = advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber {
            ad.connectable = connectable.boolValue
        }
        ad.lastSeen = Date()
        adverts[id] = ad
        advertsChanged = true
        if isNew && ad.isCar {
            log.add(.info, "Found \(ad.title): " + ad.details.dropFirst().joined(separator: ", "))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == self.peripheral?.identifier else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        link.state = .discovering
        if link.name == nil { link.name = peripheral.name }
        log.add(.info, "Connected to \(link.name ?? "the device"), reading its services")
        pendingServices = 0
        peripheral.discoverServices(nil)
        updateScanning()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        let reason = error?.localizedDescription ?? "Could not connect"
        log.add(.error, "Connection failed: \(reason)")
        link.state = .failed(reason)
        guard wanted == peripheral.identifier else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.wanted == peripheral.identifier, self.peripheral?.identifier == peripheral.identifier else {
                return
            }
            self.link.state = .connecting
            self.central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        onDisconnect?()
        if let error {
            log.add(.error, "Disconnected: \(error.localizedDescription)")
        } else {
            log.add(.info, "Disconnected")
        }
        if wanted == peripheral.identifier {
            link.state = .connecting
            log.add(.info, "Waiting for the car to come back")
            central.connect(peripheral, options: nil)
        } else {
            self.peripheral = nil
            link.state = .idle
        }
        updateScanning()
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { log.add(.error, "Services: \(error.localizedDescription)") }
        let services = peripheral.services ?? []
        log.add(.info, "Services: " + (services.isEmpty ? "none" : services.map { $0.uuid.uuidString }.joined(separator: ", ")))
        pendingServices = services.count
        if services.isEmpty { finishDiscovery(peripheral) }
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { log.add(.error, "Characteristics of \(service.uuid.uuidString): \(error.localizedDescription)") }
        for c in service.characteristics ?? [] {
            log.add(.info, "\(service.uuid.uuidString) › \(c.uuid.uuidString): " + c.properties.labels.joined(separator: ", "))
            peripheral.discoverDescriptors(for: c)
            if c.properties.contains(.read) { peripheral.readValue(for: c) }
            // everything the car says goes to the log
            if c.properties.contains(.notify) || c.properties.contains(.indicate) { peripheral.setNotifyValue(true, for: c) }
        }
        pendingServices -= 1
        if pendingServices == 0 {
            finishDiscovery(peripheral)
        } else {
            queueGattRefresh()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let uuid = characteristic.uuid.uuidString
        if let error {
            log.add(.error, "Read \(uuid): \(error.localizedDescription)")
            return
        }
        let bytes = [UInt8](characteristic.value ?? Data())
        var text = "\(uuid) \(Hex.string(bytes))"
        if let ascii = Hex.ascii(bytes) { text += " \"\(ascii)\"" }
        if uuid.uppercased() == QCARProtocol.status, let status = QCARProtocol.status(bytes) {
            link.battery = status.battery
            text += " (battery \(status.battery)%)"
        } else if uuid == "2A19", let level = bytes.first {
            link.battery = Int(level)
            text += " (battery \(level)%)"
        }
        log.add(.rx, text)
        queueGattRefresh()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let uuid = characteristic.uuid.uuidString
        if let error {
            log.add(.error, "Write \(uuid): \(error.localizedDescription)")
            link.writeError = error.localizedDescription
        }
        if uuid.uppercased() == link.controlUUID?.uppercased() {
            onWriteReady?()
        } else if error == nil {
            log.add(.info, "\(uuid) write acknowledged")
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        onWriteReady?()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let uuid = characteristic.uuid.uuidString
        if let error {
            log.add(.error, "Notifications of \(uuid): \(error.localizedDescription)")
        } else {
            log.add(.info, "\(uuid) notifications \(characteristic.isNotifying ? "on" : "off")")
        }
        queueGattRefresh()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        for d in characteristic.descriptors ?? [] where d.uuid.uuidString == CBUUIDCharacteristicUserDescriptionString {
            peripheral.readValue(for: d)
        }
        queueGattRefresh()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        if let text = descriptor.value as? String {
            log.add(.info, "\(descriptor.characteristic?.uuid.uuidString ?? "?") is called \"\(text)\"")
        }
        queueGattRefresh()
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if error == nil { link.rssi = RSSI.intValue }
    }

    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        if let name = peripheral.name { link.name = name }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        log.add(.info, "The device changed its services; reading them again")
        peripheral.discoverServices(nil)
    }
}
