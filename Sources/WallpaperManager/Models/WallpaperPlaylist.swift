import AppKit
import Foundation

struct WallpaperPlaylist: Codable, Equatable {
    let id: UUID
    var name: String
    var folderPath: String
    var playbackMode: PlaylistPlaybackMode
    var timerDurationMinutes: Int
    var hotkeyEnabled: Bool
    var videoOrder: [String]

    init(
        id: UUID,
        name: String,
        folderPath: String,
        playbackMode: PlaylistPlaybackMode = .advanceAtEnd,
        timerDurationMinutes: Int = 30,
        hotkeyEnabled: Bool = false,
        videoOrder: [String] = []
    ) {
        self.id = id
        self.name = name
        self.folderPath = folderPath
        self.playbackMode = playbackMode
        self.timerDurationMinutes = timerDurationMinutes
        self.hotkeyEnabled = hotkeyEnabled
        self.videoOrder = videoOrder
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case folderPath
        case playbackMode
        case timerDurationMinutes
        case hotkeyEnabled
        case videoOrder
        case repeatsCurrentVideo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        folderPath = try container.decode(String.self, forKey: .folderPath)
        if let mode = try container.decodeIfPresent(PlaylistPlaybackMode.self, forKey: .playbackMode) {
            playbackMode = mode
        } else {
            playbackMode = try container.decodeIfPresent(Bool.self, forKey: .repeatsCurrentVideo) == true ? .loopUntilHotkey : .advanceAtEnd
        }
        timerDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .timerDurationMinutes) ?? 30
        hotkeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .hotkeyEnabled) ?? false
        videoOrder = try container.decodeIfPresent([String].self, forKey: .videoOrder) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(folderPath, forKey: .folderPath)
        try container.encode(playbackMode, forKey: .playbackMode)
        try container.encode(timerDurationMinutes, forKey: .timerDurationMinutes)
        try container.encode(hotkeyEnabled, forKey: .hotkeyEnabled)
        try container.encode(videoOrder, forKey: .videoOrder)
    }
}

enum ManagerPage: Equatable {
    case home
    case createPlaylist
    case playlistDetail(UUID)
}

final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
