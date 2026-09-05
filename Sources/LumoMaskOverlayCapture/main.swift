import AppKit
import LumoKit

guard ProcessInfo.processInfo.environment["LUMO_MASK_OVERLAY_PROTOTYPE"] == "1" else {
    fputs("Set LUMO_MASK_OVERLAY_PROTOTYPE=1 to run the LUMO-227 capture host.\n", stderr)
    exit(2)
}

let application = NSApplication.shared
let controller = MaskOverlayCaptureController()
controller.start()
application.run()
