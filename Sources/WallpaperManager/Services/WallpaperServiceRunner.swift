import Foundation

final class WallpaperServiceRunner {
    private var process: Process?
    var onTermination: (() -> Void)?

    func isAvailable() -> Bool {
        ServiceSocket.send(ServiceCommand(.ping))
    }

    func start(
        helperURL: URL,
        playlist: WallpaperPlaylist,
        playlists: [ServicePlaylist],
        hotkeys: PlaylistHotkeys,
        completion: @escaping (Bool) -> Void
    ) {
        let command = ServiceCommand(
            .start,
            folderPath: playlist.folderPath,
            playbackMode: playlist.playbackMode,
            timerDurationMinutes: playlist.timerDurationMinutes,
            hotkeyEnabled: playlist.hotkeyEnabled,
            hotkeys: hotkeys,
            playlists: playlists,
            activePlaylistID: playlist.id
        )

        if isAvailable() || process?.isRunning == true {
            send(command, attempts: 40, completion: completion)
            return
        }

        let service = Process()
        service.executableURL = helperURL
        service.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.process = nil
                self?.onTermination?()
            }
        }

        do {
            try service.run()
            process = service
            send(command, attempts: 40, completion: completion)
        } catch {
            completion(false)
        }
    }

    func send(_ command: ServiceCommand, completion: @escaping (Bool) -> Void) {
        send(command, attempts: 1, completion: completion)
    }

    private func send(_ command: ServiceCommand, attempts: Int, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let sent = ServiceSocket.send(command, attempts: attempts)
            DispatchQueue.main.async {
                completion(sent)
            }
        }
    }
}
