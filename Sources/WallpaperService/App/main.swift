import AppKit

let application = NSApplication.shared
let service = WallpaperPlaybackService()
application.setActivationPolicy(.accessory)
application.delegate = service
application.run()
