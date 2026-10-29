import AppKit
import Foundation

final class WallpaperPlaybackService: NSObject, NSApplicationDelegate {
    private var server: ServiceSocketServer?
    private let wallpaperController = WallpaperController()
    private lazy var hotkeyMonitor = GlobalHotkeyMonitor { [weak self] id in
        switch id {
        case 1: self?.wallpaperController.hotkeyPressed()
        case 2: self?.wallpaperController.switchPlaylist(direction: 1)
        case 3: self?.wallpaperController.switchPlaylist(direction: -1)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let server = ServiceSocketServer { [weak self] command in
            DispatchQueue.main.async {
                self?.handle(command)
            }
        }
        self.server = server
        server.start()
        hotkeyMonitor.register(.default)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func handle(_ command: ServiceCommand) {
        switch command.action {
        case .ping:
            break
        case .start:
            guard let folderPath = command.folderPath else { return }
            let mode = command.playbackMode ?? ((command.repeatCurrentVideo ?? false) ? .loopUntilHotkey : .advanceAtEnd)
            let playlist = command.playlists?.first(where: { $0.id == command.activePlaylistID }) ?? ServicePlaylist(
                id: command.activePlaylistID ?? UUID(),
                folderPath: folderPath,
                playbackMode: mode,
                timerDurationMinutes: command.timerDurationMinutes ?? 30,
                hotkeyEnabled: command.hotkeyEnabled ?? false
            )
            wallpaperController.start(playlist: playlist, catalog: command.playlists ?? [playlist])
            hotkeyMonitor.register(command.hotkeys ?? .default)
        case .pause:
            wallpaperController.pause()
        case .resume:
            wallpaperController.resume()
        case .stop:
            wallpaperController.stop()
            NSApp.terminate(nil)
        case .nextVideo:
            wallpaperController.hotkeyPressed()
        case .configureHotkey:
            if let hotkeys = command.hotkeys {
                hotkeyMonitor.register(hotkeys)
            } else if let hotkey = command.hotkey {
                var hotkeys = PlaylistHotkeys.default
                hotkeys.playback = hotkey
                hotkeyMonitor.register(hotkeys)
            }
        case .suspendHotkey:
            hotkeyMonitor.unregister()
        case .updatePlaylists:
            wallpaperController.updatePlaylistCatalog(command.playlists ?? [])
        }
    }
}
