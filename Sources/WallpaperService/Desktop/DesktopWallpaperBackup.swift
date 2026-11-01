import AppKit
import Foundation

final class DesktopWallpaperBackup {
    private struct Entry: Codable {
        let displayID: UInt32
        let imagePath: String
    }

    private var savedEntries: [Entry] = []
    private var originalOptions: [UInt32: [NSWorkspace.DesktopImageOptionKey: Any]] = [:]
    private let fileManager = FileManager.default
    private let directoryURL: URL
    private let backupURL: URL
    private let legacyPosterURL: URL

    init() {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directoryURL = applicationSupport.appendingPathComponent("LiveMacOsWallpapers", isDirectory: true)
        backupURL = directoryURL.appendingPathComponent("desktop-wallpaper-backup.json")
        legacyPosterURL = directoryURL.appendingPathComponent("current-wallpaper-poster.jpg")
        restoreStaleBackup()
    }

    func restore() {
        let screensByID = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            Self.displayID(for: screen).map { ($0, screen) }
        })
        var remaining: [Entry] = []
        for entry in savedEntries {
            guard let screen = screensByID[entry.displayID] else {
                remaining.append(entry)
                continue
            }
            let options = originalOptions[entry.displayID] ?? NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
            do {
                try NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: entry.imagePath), for: screen, options: options)
            } catch {
                remaining.append(entry)
            }
        }
        savedEntries = remaining
        originalOptions.removeAll()
        saveBackup()
        if savedEntries.isEmpty {
            try? fileManager.removeItem(at: legacyPosterURL)
            removeOrphanedPosters()
            try? fileManager.removeItem(at: backupURL)
        }
    }

    private func restoreStaleBackup() {
        guard let data = try? Data(contentsOf: backupURL),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        savedEntries = entries
        restore()
    }

    private func saveBackup() {
        guard let data = try? JSONEncoder().encode(savedEntries) else { return }
        try? data.write(to: backupURL, options: .atomic)
    }

    private func removeOrphanedPosters() {
        guard let contents = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else { return }
        for url in contents where url.lastPathComponent.hasPrefix("wallpaper-poster-") {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func displayID(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[ NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

}
