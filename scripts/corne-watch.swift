// Print a line when the Corne connects or disconnects, plus timer ticks (macOS).
//
//   corne-watch [connected_s] [asleep_s]     (built by scripts/swiftbar.sh)
//
// The Corne (VID 0x1D50, PID 0x615E) shows up in the IOKit registry as a HID
// device when it connects, over Bluetooth or USB, and goes away when it
// disconnects: in the no-dongle setup the left half disconnects when it falls
// asleep and connects again when a key wakes it. IOKit match / terminate
// notifications report this at once, with no permission needed (nothing is
// opened or read).
//
// Output, one word per line, for the SwiftBar plugin to react to:
//   connected      the first Corne HID device appeared (also at start)
//   disconnected   the last one went away (also at start, if none)
//   tick           time to re-read the battery: every connected_s (default
//                  120) while connected, every asleep_s (default 300) while not
import Foundation
import IOKit

setvbuf(stdout, nil, _IOLBF, 0)

let vendorID = 0x1D50
let productID = 0x615E
let args = CommandLine.arguments
let connectedInterval = args.count > 1 ? Double(args[1]) ?? 120 : 120
let asleepInterval = args.count > 2 ? Double(args[2]) ?? 300 : 300

var devices = 0
var lastTick = Date()

func emit(_ line: String) {
    print(line)
    lastTick = Date()   // any event re-reads the battery: restart the timer
}

func drain(_ iterator: io_iterator_t) -> Int {
    var n = 0
    while case let service = IOIteratorNext(iterator), service != 0 {
        IOObjectRelease(service)
        n += 1
    }
    return n
}

func matching() -> CFDictionary {
    let dict = IOServiceMatching("IOHIDDevice") as NSMutableDictionary
    dict["VendorID"] = vendorID
    dict["ProductID"] = productID
    return dict
}

let port = IONotificationPortCreate(kIOMainPortDefault)
CFRunLoopAddSource(CFRunLoopGetMain(),
                   IONotificationPortGetRunLoopSource(port).takeUnretainedValue(),
                   .defaultMode)

var added: io_iterator_t = 0
var removed: io_iterator_t = 0

IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, matching(), { _, it in
    let was = devices
    devices += drain(it)
    if was == 0 && devices > 0 { emit("connected") }
}, nil, &added)

IOServiceAddMatchingNotification(port, kIOTerminatedNotification, matching(), { _, it in
    devices = max(0, devices - drain(it))
    if devices == 0 { emit("disconnected") }
}, nil, &removed)

// Arm the notifications and report the state at start.
devices = drain(added)
_ = drain(removed)
emit(devices > 0 ? "connected" : "disconnected")

Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
    let interval = devices > 0 ? connectedInterval : asleepInterval
    if Date().timeIntervalSince(lastTick) >= interval { emit("tick") }
}

RunLoop.main.run()
