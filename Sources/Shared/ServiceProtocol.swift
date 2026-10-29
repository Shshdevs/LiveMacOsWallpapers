import Foundation
import Darwin

enum ServiceAction: String, Codable {
    case ping
    case start
    case pause
    case resume
    case stop
    case nextVideo
    case configureHotkey
    case suspendHotkey
    case updatePlaylists
}

enum PlaylistPlaybackMode: String, Codable {
    case advanceAtEnd
    case loopUntilHotkey
    case loopForDuration
}

struct GlobalHotkey: Codable, Equatable {
    var keyCode: UInt16
    var modifierMask: UInt8

    static let `default` = GlobalHotkey(keyCode: 35, modifierMask: 6)
}

struct PlaylistHotkeys: Codable, Equatable {
    var playback: GlobalHotkey
    var nextPlaylist: GlobalHotkey
    var previousPlaylist: GlobalHotkey

    static let `default` = PlaylistHotkeys(
        playback: .default,
        nextPlaylist: GlobalHotkey(keyCode: 45, modifierMask: 9),
        previousPlaylist: GlobalHotkey(keyCode: 35, modifierMask: 9)
    )
}

struct ServicePlaylist: Codable, Equatable {
    let id: UUID
    let folderPath: String
    let playbackMode: PlaylistPlaybackMode
    let timerDurationMinutes: Int
    let hotkeyEnabled: Bool
    var videoOrder: [String]? = nil
}

enum HotkeyPurpose {
    case playback
    case nextPlaylist
    case previousPlaylist
}

struct ServiceCommand: Codable {
    let action: ServiceAction
    var folderPath: String?
    var repeatCurrentVideo: Bool?
    var playbackMode: PlaylistPlaybackMode?
    var timerDurationMinutes: Int?
    var hotkeyEnabled: Bool?
    var hotkey: GlobalHotkey?
    var hotkeys: PlaylistHotkeys?
    var playlists: [ServicePlaylist]?
    var activePlaylistID: UUID?

    init(
        _ action: ServiceAction,
        folderPath: String? = nil,
        repeatCurrentVideo: Bool? = nil,
        playbackMode: PlaylistPlaybackMode? = nil,
        timerDurationMinutes: Int? = nil,
        hotkeyEnabled: Bool? = nil,
        hotkey: GlobalHotkey? = nil,
        hotkeys: PlaylistHotkeys? = nil,
        playlists: [ServicePlaylist]? = nil,
        activePlaylistID: UUID? = nil
    ) {
        self.action = action
        self.folderPath = folderPath
        self.repeatCurrentVideo = repeatCurrentVideo
        self.playbackMode = playbackMode
        self.timerDurationMinutes = timerDurationMinutes
        self.hotkeyEnabled = hotkeyEnabled
        self.hotkey = hotkey
        self.hotkeys = hotkeys
        self.playlists = playlists
        self.activePlaylistID = activePlaylistID
    }
}

enum ServiceSocket {
    static var path: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LiveMacOsWallpapers/control.sock")
            .path
    }

    static func send(_ command: ServiceCommand, attempts: Int = 1) -> Bool {
        guard let data = try? JSONEncoder().encode(command) else { return false }
        var payload = data
        payload.append(10)

        for attempt in 0..<attempts {
            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            if descriptor >= 0 {
                var address = sockaddr_un()
                address.sun_family = sa_family_t(AF_UNIX)
                let pathBytes = Array(path.utf8) + [0]
                let copied = withUnsafeMutableBytes(of: &address.sun_path) { destination in
                    pathBytes.withUnsafeBytes { source in
                        guard source.count <= destination.count else { return false }
                        destination.copyBytes(from: source)
                        return true
                    }
                }

                if copied {
                    let result = withUnsafePointer(to: &address) { pointer in
                        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                        }
                    }

                    if result == 0 {
                        let sent = payload.withUnsafeBytes { bytes in
                            Darwin.write(descriptor, bytes.baseAddress, bytes.count)
                        }
                        Darwin.close(descriptor)
                        if sent == payload.count { return true }
                    } else {
                        Darwin.close(descriptor)
                    }
                } else {
                    Darwin.close(descriptor)
                }
            }

            if attempt + 1 < attempts {
                Thread.sleep(forTimeInterval: 0.1)
            }
        }

        return false
    }
}

final class ServiceSocketServer {
    private let onCommand: (ServiceCommand) -> Void
    private var descriptor: Int32 = -1

    init(onCommand: @escaping (ServiceCommand) -> Void) {
        self.onCommand = onCommand
    }

    func start() {
        let socketURL = URL(fileURLWithPath: ServiceSocket.path)
        try? FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        unlink(ServiceSocket.path)

        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(ServiceSocket.path.utf8) + [0]
        let copied = withUnsafeMutableBytes(of: &address.sun_path) { destination in
            pathBytes.withUnsafeBytes { source in
                guard source.count <= destination.count else { return false }
                destination.copyBytes(from: source)
                return true
            }
        }
        guard copied else {
            Darwin.close(descriptor)
            descriptor = -1
            return
        }

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(descriptor, 8) == 0 else {
            Darwin.close(descriptor)
            descriptor = -1
            return
        }
        chmod(ServiceSocket.path, mode_t(S_IRUSR | S_IWUSR))

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.acceptConnections()
        }
    }

    private func acceptConnections() {
        while descriptor >= 0 {
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else { continue }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)

            while true {
                let count = recv(client, &buffer, buffer.count, 0)
                if count <= 0 { break }
                if let newline = buffer[..<count].firstIndex(of: 10) {
                    data.append(contentsOf: buffer[..<newline])
                    break
                }
                data.append(contentsOf: buffer[..<count])
            }

            Darwin.close(client)
            if let command = try? JSONDecoder().decode(ServiceCommand.self, from: data) {
                onCommand(command)
            }
        }
    }
}
