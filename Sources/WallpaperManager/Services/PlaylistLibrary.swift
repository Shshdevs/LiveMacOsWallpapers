import Foundation

enum PlaylistLibraryError: LocalizedError {
    case emptyName
    case duplicateName

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Введите название плейлиста."
        case .duplicateName:
            return "Плейлист с таким названием уже существует."
        }
    }
}

final class PlaylistLibrary {
    private let playlistsKey = "wallpaperPlaylists"
    private let defaults: UserDefaults
    let rootURL: URL

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rootURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LiveMacOsWallpapers/Playlists", isDirectory: true)
    }

    func load() -> [WallpaperPlaylist] {
        guard let data = defaults.data(forKey: playlistsKey),
              let stored = try? JSONDecoder().decode([WallpaperPlaylist].self, from: data) else { return [] }
        let available = stored.filter { FileManager.default.fileExists(atPath: $0.folderPath) }
        if available != stored {
            save(available)
        }
        return available
    }

    func save(_ playlists: [WallpaperPlaylist]) {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        defaults.set(data, forKey: playlistsKey)
    }

    func createPlaylist(named rawName: String) throws -> WallpaperPlaylist {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        guard !name.isEmpty, name != ".", name != ".." else {
            throw PlaylistLibraryError.emptyName
        }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let folderURL = rootURL.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: folderURL.path) else {
            throw PlaylistLibraryError.duplicateName
        }
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        return WallpaperPlaylist(id: UUID(), name: name, folderPath: folderURL.path)
    }

    func delete(_ playlist: WallpaperPlaylist) throws {
        try FileManager.default.removeItem(atPath: playlist.folderPath)
    }

    func addVideos(_ sourceURLs: [URL], to playlist: WallpaperPlaylist) -> Int {
        let folderURL = URL(fileURLWithPath: playlist.folderPath, isDirectory: true)
        var added = 0

        for sourceURL in sourceURLs {
            let destinationURL = uniqueDestination(for: sourceURL, in: folderURL)
            if (try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)) != nil {
                added += 1
            }
        }

        return added
    }

    func videos(in playlist: WallpaperPlaylist) -> [URL] {
        let available = videos(in: URL(fileURLWithPath: playlist.folderPath, isDirectory: true))
        guard !playlist.videoOrder.isEmpty else { return available }
        let byName = Dictionary(uniqueKeysWithValues: available.map { ($0.lastPathComponent, $0) })
        let ordered = playlist.videoOrder.compactMap { byName[$0] }
        let included = Set(ordered.map(\.lastPathComponent))
        return ordered + available.filter { !included.contains($0.lastPathComponent) }
    }

    func removeVideo(_ videoURL: URL, from playlist: WallpaperPlaylist) throws {
        let folderURL = URL(fileURLWithPath: playlist.folderPath, isDirectory: true).standardizedFileURL
        guard videoURL.deletingLastPathComponent().standardizedFileURL == folderURL else { return }
        try FileManager.default.removeItem(at: videoURL)
    }

    func videos(in folderURL: URL) -> [URL] {
        let extensions: Set<String> = ["mov", "mp4", "m4v"]
        return (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ))?.filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending } ?? []
    }

    private func uniqueDestination(for sourceURL: URL, in folderURL: URL) -> URL {
        var candidate = folderURL.appendingPathComponent(sourceURL.lastPathComponent)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = sourceURL.deletingPathExtension().lastPathComponent
            candidate = folderURL.appendingPathComponent("\(name) \(suffix).\(sourceURL.pathExtension)")
            suffix += 1
        }
        return candidate
    }
}
