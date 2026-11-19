// Battery levels of the Corne over Bluetooth on macOS, both halves.
//
//   swift scripts/battery-mac.swift            # print the levels once (scripts/battery.sh)
//   corne-battery --watch                      # stream, for the SwiftBar plugin
//
// --watch prints "levels <left> <right>" at once and again on every change,
// then "disconnected" and exits when the left half goes away. The levels come
// as GATT notifications: the left half (central) notifies its own level and,
// as a proxy, the right half's one, also when the right half connects to it
// after sleep. "-" = the right half is not connected to the left one (asleep):
// ZMK reports 0 for it then. "alive" every 60 s: if nobody reads the output
// any more, the write fails (SIGPIPE) and the process ends.
//
// macOS shows the battery of a keyboard only from HID reports and ignores
// the GATT Battery Service, which ZMK uses: the central's own level, plus one
// Battery Level characteristic per peripheral with
// CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY. This reads the service
// directly. The keyboard must be connected; the first run asks for Bluetooth
// access for the terminal app (System Settings → Privacy & Security →
// Bluetooth).
import CoreBluetooth
import Foundation

let batteryService = CBUUID(string: "180F")
let batteryLevel = CBUUID(string: "2A19")
let userDescription = CBUUID(string: "2901")
// Over Bluetooth only the no-dongle setup talks to the computer: the left
// half is the central, the right half is its only peripheral.
let half = ["central": "left half ", "Peripheral 0": "right half"]
let watch = CommandLine.arguments.contains("--watch")
setvbuf(stdout, nil, _IOLBF, 0)

final class Reader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var central: CBCentralManager!
    var peripheral: CBPeripheral?
    var pending = 0                       // requests without an answer yet
    var stage = "waiting for Bluetooth (state unknown: no access yet?)"
    var chars: [CBCharacteristic] = []    // battery levels, in discovery order
    var values: [ObjectIdentifier: Int] = [:]
    var labels: [ObjectIdentifier: String] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    var ready = false                     // first values read (watch mode)
    var readOnce = Set<ObjectIdentifier>()

    // The central's own level comes first; proxied peripherals follow,
    // usually with a user description (descriptor 2901).
    func name(_ i: Int, _ ch: CBCharacteristic) -> String {
        labels[ObjectIdentifier(ch)] ?? (i == 0 ? "central" : "Peripheral \(i - 1)")
    }

    func level(_ name: String) -> String {
        guard let i = chars.indices.first(where: { self.name($0, chars[$0]) == name }),
              let v = values[ObjectIdentifier(chars[i])] else { return "-" }
        // A peripheral that is not connected to the central is reported as 0.
        return name != "central" && v == 0 ? "-" : String(v)
    }

    func report() {
        if watch {
            ready = true
            print("levels \(level("central")) \(level("Peripheral 0"))")
            return
        }
        if chars.isEmpty { print("Corne: no Battery Level characteristics") }
        for (i, ch) in chars.enumerated() {
            let n = name(i, ch)
            let v = values[ObjectIdentifier(ch)]
            let text = v == nil ? "no value"
                : (n != "central" && v == 0 ? "not connected (asleep)" : "\(v!)%")
            print("\(half[n] ?? n): " + text)
        }
        exit(0)
    }

    func answered() {
        pending -= 1
        if pending == 0 { report() }
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            let found = c.retrieveConnectedPeripherals(withServices: [batteryService])
                .filter { ($0.name ?? "").lowercased().contains("corne") }
            guard let p = found.first else {
                print(watch ? "disconnected" : "Corne is not connected over Bluetooth (with the dongle it is on USB)")
                exit(watch ? 0 : 1)
            }
            peripheral = p
            p.delegate = self
            stage = "connecting to \(p.name ?? "Corne")"
            c.connect(p)
        case .unauthorized:
            print("no Bluetooth access: allow it for this terminal app in System Settings → Privacy & Security → Bluetooth")
            exit(1)
        case .poweredOff:
            print("Bluetooth is off")
            exit(1)
        default:
            break
        }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        if watch {
            print("disconnected")
            exit(0)
        }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        stage = "reading the Battery Service"
        p.discoverServices([batteryService])
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        let services = p.services ?? []
        if services.isEmpty { report() }
        pending = services.count
        for s in services { p.discoverCharacteristics([batteryLevel], for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in (s.characteristics ?? []) where ch.uuid == batteryLevel {
            chars.append(ch)
            pending += 2
            if watch { p.setNotifyValue(true, for: ch) }
            p.readValue(for: ch)
            p.discoverDescriptors(for: ch)
        }
        answered()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        let id = ObjectIdentifier(ch)
        let first = !readOnce.contains(id)
        readOnce.insert(id)
        if let v = ch.value?.first { values[id] = Int(v) }
        if ready {          // a notification after the first read
            report()
            return
        }
        if first { answered() }   // a notification before the read answered: not a reply
    }

    func peripheral(_ p: CBPeripheral, didDiscoverDescriptorsFor ch: CBCharacteristic, error: Error?) {
        if let d = ch.descriptors?.first(where: { $0.uuid == userDescription }) {
            pending += 1
            p.readValue(for: d)
        }
        answered()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor d: CBDescriptor, error: Error?) {
        if let ch = d.characteristic, let text = d.value as? String {
            labels[ObjectIdentifier(ch)] = text
        }
        answered()
    }
}

let reader = Reader()
DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
    if reader.ready { return }
    print("timeout after 15 s, stage: \(reader.stage)")
    exit(1)
}
if watch {
    Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in print("alive") }
}
RunLoop.main.run()
