import AppKit
import AVFoundation
import Foundation

final class DesktopWallpaperBackup {
    private struct Entry: Codable {
        let displayID: UInt32
        let imagePath: String
    }

    private var savedEntries: [Entry] = []
    private var originalOptions: [UInt32: [NSWorkspace.DesktopImageOptionKey: Any]] = [:]
    private var currentPosterURL: URL?
    private var posterURLs: Set<URL> = []
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

    func captureAndApplyPoster(from videoURL: URL) {
        guard savedEntries.isEmpty else {
            applyPoster(from: videoURL)
            return
        }

        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        savedEntries = NSScreen.screens.compactMap { screen in
            guard let displayID = Self.displayID(for: screen),
                  let imageURL = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
            originalOptions[displayID] = NSWorkspace.shared.desktopImageOptions(for: screen)
            return Entry(displayID: displayID, imagePath: imageURL.path)
        }
        saveBackup()
        applyPoster(from: videoURL)
    }

    func applyPoster(from videoURL: URL) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        generator.appliesPreferredTrackTransform = true
        generator.generateCGImageAsynchronously(for: .zero) { [weak self] image, _, _ in
            guard let self, let image else { return }
            DispatchQueue.main.async {
                self.storeAndApplyPoster(image)
            }
        }
    }

    private func storeAndApplyPoster(_ image: CGImage) {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else { return }
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let newPosterURL = directoryURL.appendingPathComponent("wallpaper-poster-\(UUID().uuidString).jpg")
        do {
            try data.write(to: newPosterURL, options: .atomic)
            var appliedToScreen = false
            for screen in NSScreen.screens {
                let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                    .allowClipping: true
                ]
                do {
                    try NSWorkspace.shared.setDesktopImageURL(newPosterURL, for: screen, options: options)
                    appliedToScreen = true
                } catch {
                    continue
                }
            }
            guard appliedToScreen else {
                try? fileManager.removeItem(at: newPosterURL)
                return
            }
            let previousPosterURL = currentPosterURL
            currentPosterURL = newPosterURL
            posterURLs.insert(newPosterURL)
            if let previousPosterURL {
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                    self?.removePoster(previousPosterURL)
                }
            }
        } catch {
            return
        }
    }

    func reapplyCurrentPoster() {
        guard let currentPosterURL else { return }
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true
        ]
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(currentPosterURL, for: screen, options: options)
        }
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
            for posterURL in posterURLs {
                try? fileManager.removeItem(at: posterURL)
            }
            posterURLs.removeAll()
            currentPosterURL = nil
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

    private func removePoster(_ url: URL) {
        try? fileManager.removeItem(at: url)
        posterURLs.remove(url)
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
