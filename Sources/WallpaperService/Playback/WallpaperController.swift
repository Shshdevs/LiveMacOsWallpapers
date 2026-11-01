import AppKit
import AVFoundation
import AVKit
import Foundation

final class WallpaperController {
    private let supportedExtensions: Set<String> = ["mov", "mp4", "m4v"]
    private var windows: [NSWindow] = []
    private var player: AVPlayer?
    private var files: [URL] = []
    private var playbackMode: PlaylistPlaybackMode = .advanceAtEnd
    private var timerDurationMinutes = 30
    private var hotkeyEnabled = false
    private var currentIndex = 0
    private var completionObserver: NSObjectProtocol?
    private var itemStatusObservation: NSKeyValueObservation?
    private var playlistCatalog: [ServicePlaylist] = []
    private var activePlaylistID: UUID?
    private var timer: Timer?
    private var timerDeadline: Date?
    private var remainingTimerInterval: TimeInterval?
    private var spaceChangeObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private let desktopWallpaperBackup = DesktopWallpaperBackup()

    init() {
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.desktopWallpaperBackup.reapplyCurrentPoster()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resumeAfterWake()
        }
    }

    deinit {
        if let spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    private func resumeAfterWake() {
        guard !files.isEmpty else { return }
        if windows.isEmpty {
            createWallpaperWindows()
        } else {
            windows.forEach { $0.orderFrontRegardless() }
        }
        player?.play()
        desktopWallpaperBackup.reapplyCurrentPoster()
        if playbackMode == .loopForDuration, timer == nil {
            resetTimer()
        }
    }

    func start(playlist: ServicePlaylist, catalog: [ServicePlaylist]) {
        playlistCatalog = catalog
        start(
            folderURL: URL(fileURLWithPath: playlist.folderPath),
            playbackMode: playlist.playbackMode,
            timerDurationMinutes: playlist.timerDurationMinutes,
            hotkeyEnabled: playlist.hotkeyEnabled,
            videoOrder: playlist.videoOrder ?? [],
            animated: player != nil
        )
        activePlaylistID = playlist.id
    }

    func updatePlaylistCatalog(_ catalog: [ServicePlaylist]) {
        playlistCatalog = catalog
        guard let activePlaylistID,
              let playlist = catalog.first(where: { $0.id == activePlaylistID }) else { return }
        updateActivePlaylist(playlist)
    }

    private func updateActivePlaylist(_ playlist: ServicePlaylist) {
        let previousMode = playbackMode
        let previousTimerDuration = timerDurationMinutes
        let previousTimerDeadline = timerDeadline
        let wasPaused = player?.timeControlStatus == .paused
        let currentFile = files.indices.contains(currentIndex) ? files[currentIndex] : nil
        let availableFiles = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: playlist.folderPath),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ))?.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending } ?? []
        let filesByName = Dictionary(uniqueKeysWithValues: availableFiles.map { ($0.lastPathComponent, $0) })
        let orderedFiles = (playlist.videoOrder ?? []).compactMap { filesByName[$0] }
        let orderedNames = Set(orderedFiles.map(\.lastPathComponent))
        let updatedFiles = orderedFiles + availableFiles.filter { !orderedNames.contains($0.lastPathComponent) }

        playlistCatalog = playlistCatalog.map { $0.id == playlist.id ? playlist : $0 }
        playbackMode = playlist.playbackMode
        timerDurationMinutes = max(1, playlist.timerDurationMinutes)
        hotkeyEnabled = playlist.hotkeyEnabled

        guard !updatedFiles.isEmpty else {
            stop()
            return
        }

        let currentName = currentFile?.lastPathComponent
        files = updatedFiles
        if let currentName, let updatedIndex = files.firstIndex(where: { $0.lastPathComponent == currentName }) {
            currentIndex = updatedIndex
        } else {
            currentIndex = 0
            desktopWallpaperBackup.applyPoster(from: files[currentIndex])
            playCurrentFile(animatedTransition: true)
            if wasPaused { player?.pause() }
        }

        updateTimerAfterSettingsChange(previousMode: previousMode, previousTimerDuration: previousTimerDuration, previousTimerDeadline: previousTimerDeadline)
    }

    private func updateTimerAfterSettingsChange(previousMode: PlaylistPlaybackMode, previousTimerDuration: Int, previousTimerDeadline: Date?) {
        guard playbackMode == .loopForDuration, !files.isEmpty else {
            timer?.invalidate()
            timer = nil
            timerDeadline = nil
            remainingTimerInterval = nil
            return
        }

        if previousMode != .loopForDuration || timer == nil {
            resetTimer()
        } else if previousTimerDuration != timerDurationMinutes {
            let remaining = previousTimerDeadline.map { max(1, $0.timeIntervalSinceNow) } ?? TimeInterval(timerDurationMinutes * 60)
            scheduleTimer(after: min(remaining, TimeInterval(timerDurationMinutes * 60)))
        }
    }

    func switchPlaylist(direction: Int) {
        guard !playlistCatalog.isEmpty else { return }
        let currentIndex = playlistCatalog.firstIndex(where: { $0.id == activePlaylistID }) ?? 0
        let nextIndex = (currentIndex + direction + playlistCatalog.count) % playlistCatalog.count
        start(playlist: playlistCatalog[nextIndex], catalog: playlistCatalog)
    }

    private func start(folderURL: URL, playbackMode: PlaylistPlaybackMode, timerDurationMinutes: Int, hotkeyEnabled: Bool, videoOrder: [String], animated: Bool = false) {
        if animated {
            timer?.invalidate()
            timer = nil
            timerDeadline = nil
            remainingTimerInterval = nil
            if let completionObserver {
                NotificationCenter.default.removeObserver(completionObserver)
                self.completionObserver = nil
            }
            files.removeAll()
        } else {
            stop()
        }
        self.playbackMode = playbackMode
        self.timerDurationMinutes = max(1, timerDurationMinutes)
        self.hotkeyEnabled = hotkeyEnabled
        let availableFiles = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ))?.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending } ?? []
        let filesByName = Dictionary(uniqueKeysWithValues: availableFiles.map { ($0.lastPathComponent, $0) })
        let orderedFiles = videoOrder.compactMap { filesByName[$0] }
        let orderedNames = Set(orderedFiles.map(\.lastPathComponent))
        files = orderedFiles + availableFiles.filter { !orderedNames.contains($0.lastPathComponent) }

        guard !files.isEmpty else { return }
        currentIndex = 0
        desktopWallpaperBackup.captureAndApplyPoster(from: files[currentIndex])
        if windows.isEmpty {
            createWallpaperWindows()
        }
        playCurrentFile(animatedTransition: animated)
        resetTimer()
    }

    func pause() {
        player?.pause()
        if playbackMode == .loopForDuration, let timerDeadline {
            remainingTimerInterval = max(0, timerDeadline.timeIntervalSinceNow)
            timer?.invalidate()
            timer = nil
            self.timerDeadline = nil
        }
    }

    func resume() {
        player?.play()
        if playbackMode == .loopForDuration, timer == nil {
            scheduleTimer(after: remainingTimerInterval ?? TimeInterval(timerDurationMinutes * 60))
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        timerDeadline = nil
        remainingTimerInterval = nil
        stopPlayback()
        files.removeAll()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        desktopWallpaperBackup.restore()
    }

    private func stopPlayback() {
        itemStatusObservation = nil
        if let completionObserver {
            NotificationCenter.default.removeObserver(completionObserver)
            self.completionObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        files.removeAll()
    }

    private func createWallpaperWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.backgroundColor = .black
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.setFrame(screen.frame, display: true)

            let playerView = AVPlayerView(frame: window.contentView?.bounds ?? .zero)
            playerView.controlsStyle = .none
            playerView.videoGravity = .resizeAspectFill
            playerView.updatesNowPlayingInfoCenter = false
            playerView.autoresizingMask = [.width, .height]
            window.contentView = playerView
            window.orderFrontRegardless()
            windows.append(window)
        }

        let player = AVPlayer()
        self.player = player
        windows.compactMap { $0.contentView as? AVPlayerView }.forEach { $0.player = player }
    }

    private func playCurrentFile(animatedTransition: Bool = false) {
        guard !files.isEmpty, let player else { return }
        let overlays = animatedTransition ? transitionOverlays() : []
        itemStatusObservation = nil
        if let completionObserver {
            NotificationCenter.default.removeObserver(completionObserver)
        }

        let item = AVPlayerItem(url: files[currentIndex])
        player.replaceCurrentItem(with: item)
        if !overlays.isEmpty {
            itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard item.status == .readyToPlay else { return }
                DispatchQueue.main.async {
                    self?.fadeOut(overlays)
                }
            }
        }
        completionObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.playNextFile()
        }
        player.play()
    }

    private func transitionOverlays() -> [NSView] {
        windows.compactMap { window in
            guard let contentView = window.contentView,
                  let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else { return nil }
            contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
            let imageView = NSImageView(frame: contentView.bounds)
            imageView.image = NSImage(size: bitmap.size)
            imageView.image?.addRepresentation(bitmap)
            imageView.imageScaling = .scaleAxesIndependently
            imageView.autoresizingMask = [.width, .height]
            contentView.addSubview(imageView, positioned: .above, relativeTo: nil)
            return imageView
        }
    }

    private func fadeOut(_ overlays: [NSView]) {
        guard !overlays.isEmpty else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.65
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            overlays.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            overlays.forEach { $0.removeFromSuperview() }
        }
    }

    private func playNextFile() {
        guard !files.isEmpty else { return }
        if playbackMode != .advanceAtEnd {
            player?.seek(to: .zero) { [weak self] _ in
                self?.player?.play()
            }
            return
        }
        currentIndex = (currentIndex + 1) % files.count
        desktopWallpaperBackup.applyPoster(from: files[currentIndex])
        playCurrentFile(animatedTransition: true)
    }

    func hotkeyPressed() {
        guard !files.isEmpty else { return }
        guard playbackMode == .loopUntilHotkey || (playbackMode == .loopForDuration && hotkeyEnabled) else { return }
        advanceToNextFile()
        if playbackMode == .loopForDuration {
            resetTimer()
        }
    }

    private func advanceToNextFile() {
        guard !files.isEmpty else { return }
        currentIndex = (currentIndex + 1) % files.count
        desktopWallpaperBackup.applyPoster(from: files[currentIndex])
        playCurrentFile(animatedTransition: true)
    }

    private func resetTimer() {
        guard playbackMode == .loopForDuration, !files.isEmpty else { return }
        remainingTimerInterval = nil
        scheduleTimer(after: TimeInterval(timerDurationMinutes * 60))
    }

    private func scheduleTimer(after interval: TimeInterval) {
        timer?.invalidate()
        let interval = max(1, interval)
        timerDeadline = Date().addingTimeInterval(interval)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.timer = nil
            self.timerDeadline = nil
            self.advanceToNextFile()
            self.scheduleTimer(after: TimeInterval(self.timerDurationMinutes * 60))
        }
    }
}
