import AppKit
import Foundation
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let selectedPlaylistKey = "selectedWallpaperPlaylist"
    private let activePlaylistKey = "activeWallpaperPlaylist"
    private let hotkeyKey = "wallpaperPlaybackHotkey"
    private let launchAtLoginKey = "launchWallpaperManagerAtLogin"
    private let library = PlaylistLibrary()
    private lazy var thumbnails = VideoThumbnailProvider(library: library)
    private let serviceRunner = WallpaperServiceRunner()
    private var statusItem: NSStatusItem?

    private var managerWindow: ManagerWindowController?
    private var playlists: [WallpaperPlaylist] = []
    private var selectedPlaylistID: UUID?
    private var activePlaylistID: UUID?
    private var serviceStatus = "Служба остановлена"
    private var hotkeys = PlaylistHotkeys.default
    private var language = AppLanguage.current
    private var appearanceObservation: NSKeyValueObservation?
    private var wakeObserver: NSObjectProtocol?
    private var shouldResumePlayback = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        playlists = library.load()
        selectedPlaylistID = storedUUID(forKey: selectedPlaylistKey) ?? playlists.first?.id
        language = AppLanguage.current
        let storedActivePlaylistID = storedUUID(forKey: activePlaylistKey)
        let launchesAtLogin = UserDefaults.standard.bool(forKey: launchAtLoginKey)
        activePlaylistID = storedActivePlaylistID ?? (launchesAtLogin ? selectedPlaylistID : nil)
        if let data = UserDefaults.standard.data(forKey: hotkeyKey),
           let storedHotkeys = try? JSONDecoder().decode(PlaylistHotkeys.self, from: data) {
            hotkeys = storedHotkeys
        } else if let data = UserDefaults.standard.data(forKey: hotkeyKey),
                  let playbackHotkey = try? JSONDecoder().decode(GlobalHotkey.self, from: data) {
            hotkeys.playback = playbackHotkey
        }

        if serviceRunner.isAvailable() {
            serviceStatus = "Служба запущена"
            shouldResumePlayback = true
            refreshServiceCatalog()
            serviceRunner.send(ServiceCommand(.configureHotkey, hotkeys: hotkeys)) { _ in }
        } else {
            activePlaylistID = storedActivePlaylistID ?? (launchesAtLogin ? selectedPlaylistID : nil)
            shouldResumePlayback = activePlaylistID != nil
        }

        let windowController = ManagerWindowController(library: library, thumbnails: thumbnails)
        managerWindow = windowController
        connect(windowController)
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.renderWindow()
            }
        }
        serviceRunner.onTermination = { [weak self] in
            guard let self else { return }
            self.serviceStatus = "Служба остановлена"
            if self.shouldResumePlayback, let id = self.activePlaylistID, self.playlist(for: id) != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    guard self.shouldResumePlayback else { return }
                    self.startPlaylist(id)
                }
            } else {
                self.activePlaylistID = nil
                UserDefaults.standard.removeObject(forKey: self.activePlaylistKey)
            }
            self.renderWindow()
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.shouldResumePlayback,
                  let id = self.activePlaylistID ?? self.selectedPlaylistID,
                  self.playlist(for: id) != nil else { return }
            self.startPlaylist(id)
        }

        if launchesAtLogin {
            setLaunchAtLogin(true)
        }

        buildMenu()
        renderWindow()
        if !serviceRunner.isAvailable(), shouldResumePlayback,
           let id = activePlaylistID, playlist(for: id) != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.shouldResumePlayback else { return }
                self.startPlaylist(id)
            }
        }
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    private func connect(_ windowController: ManagerWindowController) {
        windowController.onCreatePlaylist = { [weak self] name in
            self?.createPlaylist(named: name)
        }
        windowController.onShowCreatePlaylist = { [weak self] in
            self?.managerWindow?.showCreatePlaylist()
        }
        windowController.onAddVideos = { [weak self] id, urls in
            self?.addVideos(urls, to: id)
        }
        windowController.onReorderVideo = { [weak self] id, url, direction in
            self?.reorderVideo(url, in: id, direction: direction)
        }
        windowController.onRemoveVideo = { [weak self] id, url in
            self?.removeVideo(url, from: id)
        }
        windowController.onDeletePlaylist = { [weak self] id in
            self?.deletePlaylist(id)
        }
        windowController.onStartPlaylist = { [weak self] id in
            self?.startPlaylist(id)
        }
        windowController.onStartSelectedPlaylist = { [weak self] id in
            guard let id else {
                self?.managerWindow?.showError("Сначала выберите плейлист в списке.")
                return
            }
            self?.startPlaylist(id)
        }
        windowController.onPauseService = { [weak self] in
            self?.sendServiceCommand(.pause, status: "Воспроизведение приостановлено")
        }
        windowController.onResumeService = { [weak self] in
            self?.sendServiceCommand(.resume, status: "Служба запущена")
        }
        windowController.onStopService = { [weak self] in
            self?.stopService()
        }
        windowController.onChangePlaybackSettings = { [weak self] id, mode, minutes, hotkeyEnabled in
            self?.changePlaybackSettings(for: id, mode: mode, minutes: minutes, hotkeyEnabled: hotkeyEnabled)
        }
        windowController.onChangeHotkey = { [weak self] hotkey in
            self?.changeHotkey(hotkey, purpose: .playback)
        }
        windowController.onChangePlaylistHotkey = { [weak self] hotkey, purpose in
            self?.changeHotkey(hotkey, purpose: purpose)
        }
        windowController.onBeginHotkeyCapture = { [weak self] in
            self?.serviceRunner.send(ServiceCommand(.suspendHotkey)) { _ in }
        }
        windowController.onCancelHotkeyCapture = { [weak self] in
            guard let self else { return }
            self.serviceRunner.send(ServiceCommand(.configureHotkey, hotkeys: self.hotkeys)) { _ in }
        }
        windowController.onSelectedPlaylistChanged = { [weak self] id in
            guard let self else { return }
            self.selectedPlaylistID = id
            UserDefaults.standard.set(id.uuidString, forKey: self.selectedPlaylistKey)
        }
        windowController.onLaunchAtLoginChanged = { [weak self] enabled in
            self?.setLaunchAtLogin(enabled)
        }
        windowController.onLanguageChanged = { [weak self] language in
            guard let self else { return }
            self.language = language
            UserDefaults.standard.set(language.rawValue, forKey: "interfaceLanguage")
            self.buildMenu()
            self.renderWindow()
        }
    }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.title = Localization.text("Живые обои", language: language)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: Localization.text("Скрыть «Живые обои»", language: language), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: Localization.text("Завершить работу «Живые обои»", language: language), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let playbackItem = NSMenuItem(title: Localization.text("Воспроизведение", language: language), action: nil, keyEquivalent: "")
        let playbackMenu = NSMenu()
        playbackMenu.addItem(withTitle: Localization.text("Запустить выбранный плейлист", language: language), action: #selector(startSelectedPlaylist), keyEquivalent: "")
        playbackMenu.addItem(withTitle: Localization.text("Пауза", language: language), action: #selector(pauseService), keyEquivalent: "")
        playbackMenu.addItem(withTitle: Localization.text("Продолжить", language: language), action: #selector(resumeService), keyEquivalent: "")
        playbackMenu.addItem(withTitle: Localization.text("Остановить службу", language: language), action: #selector(stopService), keyEquivalent: "")
        playbackMenu.addItem(NSMenuItem.separator())
        playbackMenu.addItem(withTitle: Localization.text("Следующий плейлист", language: language), action: #selector(nextPlaylist), keyEquivalent: "")
        playbackMenu.addItem(withTitle: Localization.text("Предыдущий плейлист", language: language), action: #selector(previousPlaylist), keyEquivalent: "")
        playbackMenu.items.forEach { $0.target = self }
        playbackItem.submenu = playbackMenu
        mainMenu.addItem(playbackItem)
        NSApp.mainMenu = mainMenu
        updateStatusItemMenu()
    }

    private func updateStatusItemMenu() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            statusItem?.button?.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "Live Wallpapers")
        }
        let currentName = playlists.first(where: { $0.id == activePlaylistID })?.name ?? "Нет активного плейлиста"
        let menu = NSMenu()
        let current = NSMenuItem(title: currentName, action: nil, keyEquivalent: "")
        current.isEnabled = false
        menu.addItem(current)
        menu.addItem(NSMenuItem.separator())
        let openItem = NSMenuItem(title: Localization.text("Открыть «Живые обои»", language: language), action: #selector(openManager), keyEquivalent: "")
        let startItem = NSMenuItem(title: Localization.text("Запустить выбранный плейлист", language: language), action: #selector(startSelectedPlaylist), keyEquivalent: "")
        let pauseItem = NSMenuItem(title: Localization.text("Пауза", language: language), action: #selector(pauseService), keyEquivalent: "")
        let resumeItem = NSMenuItem(title: Localization.text("Продолжить", language: language), action: #selector(resumeService), keyEquivalent: "")
        let nextItem = NSMenuItem(title: Localization.text("Следующий плейлист", language: language), action: #selector(nextPlaylist), keyEquivalent: "")
        let previousItem = NSMenuItem(title: Localization.text("Предыдущий плейлист", language: language), action: #selector(previousPlaylist), keyEquivalent: "")
        let stopItem = NSMenuItem(title: Localization.text("Остановить службу", language: language), action: #selector(stopService), keyEquivalent: "")
        [openItem, startItem, pauseItem, resumeItem, nextItem, previousItem, stopItem].forEach { $0.target = self }
        [openItem, startItem, pauseItem, resumeItem, nextItem, previousItem, stopItem].forEach(menu.addItem)
        statusItem?.button?.toolTip = "\(Localization.text("Живые обои", language: language)) — \(Localization.text(serviceStatus, language: language))"
        statusItem?.button?.setAccessibilityLabel(Localization.text("Живые обои", language: language))
        statusItem?.menu = menu
    }

    private func createPlaylist(named name: String) {
        do {
            let playlist = try library.createPlaylist(named: name)
            playlists.append(playlist)
            library.save(playlists)
            selectedPlaylistID = playlist.id
            UserDefaults.standard.set(playlist.id.uuidString, forKey: selectedPlaylistKey)
            refreshServiceCatalog()
            renderWindow()
            managerWindow?.showPlaylist(playlist.id)
        } catch {
            managerWindow?.showError(error.localizedDescription)
        }
    }

    private func addVideos(_ urls: [URL], to playlistID: UUID) {
        guard let playlist = playlist(for: playlistID) else { return }
        let count = library.addVideos(urls, to: playlist)
        guard count > 0 else {
            managerWindow?.showError("Не удалось добавить выбранные видео. Проверьте формат и доступ к файлам.")
            return
        }
        if let index = playlists.firstIndex(where: { $0.id == playlistID }) {
            playlists[index].videoOrder = library.videos(in: playlists[index]).map(\.lastPathComponent)
            library.save(playlists)
        }
        managerWindow?.invalidateThumbnail(for: playlistID)
        serviceStatus = count == urls.count ? "Добавлено видео: \(count)" : "Добавлено видео: \(count) из \(urls.count)"
        if activePlaylistID == playlistID {
            startPlaylist(playlistID)
        } else {
            refreshServiceCatalog()
            renderWindow()
        }
    }

    private func reorderVideo(_ videoURL: URL, in playlistID: UUID, direction: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        var videos = library.videos(in: playlists[index])
        guard let sourceIndex = videos.firstIndex(of: videoURL) else { return }
        let destinationIndex = sourceIndex + direction
        guard videos.indices.contains(destinationIndex) else { return }
        videos.swapAt(sourceIndex, destinationIndex)
        playlists[index].videoOrder = videos.map(\.lastPathComponent)
        library.save(playlists)
        if activePlaylistID == playlistID {
            startPlaylist(playlistID)
        } else {
            refreshServiceCatalog()
            renderWindow()
        }
    }

    private func removeVideo(_ videoURL: URL, from playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        do {
            try library.removeVideo(videoURL, from: playlists[index])
            playlists[index].videoOrder = library.videos(in: playlists[index]).map(\.lastPathComponent)
            library.save(playlists)
            managerWindow?.invalidateThumbnail(for: playlistID)
            if activePlaylistID == playlistID {
                if library.videos(in: playlists[index]).isEmpty {
                    performStopService()
                } else {
                    startPlaylist(playlistID)
                }
            } else {
                refreshServiceCatalog()
                renderWindow()
            }
        } catch {
            managerWindow?.showError("Не удалось удалить видео: \(error.localizedDescription)")
        }
    }

    private func deletePlaylist(_ id: UUID) {
        guard let playlist = playlist(for: id) else { return }
        if activePlaylistID == id {
            serviceRunner.send(ServiceCommand(.stop)) { _ in }
            activePlaylistID = nil
            UserDefaults.standard.removeObject(forKey: activePlaylistKey)
            serviceStatus = "Служба остановлена"
        }

        do {
            try library.delete(playlist)
            playlists.removeAll { $0.id == id }
            managerWindow?.invalidateThumbnail(for: id)
            selectedPlaylistID = playlists.first?.id
            if let selectedPlaylistID {
                UserDefaults.standard.set(selectedPlaylistID.uuidString, forKey: selectedPlaylistKey)
            } else {
                UserDefaults.standard.removeObject(forKey: selectedPlaylistKey)
            }
            library.save(playlists)
            refreshServiceCatalog()
            managerWindow?.showHome()
            renderWindow()
        } catch {
            managerWindow?.showError("Не удалось удалить папку плейлиста.")
        }
    }

    private func changePlaybackSettings(for id: UUID, mode: PlaylistPlaybackMode, minutes: Int, hotkeyEnabled: Bool) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].playbackMode = mode
        playlists[index].timerDurationMinutes = max(1, min(minutes, 1440))
        playlists[index].hotkeyEnabled = hotkeyEnabled
        library.save(playlists)
        if activePlaylistID == id {
            startPlaylist(id)
        } else {
            refreshServiceCatalog()
            renderWindow()
        }
    }

    private func changeHotkey(_ hotkey: GlobalHotkey, purpose: HotkeyPurpose) {
        var updatedHotkeys = hotkeys
        switch purpose {
        case .playback:
            updatedHotkeys.playback = hotkey
        case .nextPlaylist:
            updatedHotkeys.nextPlaylist = hotkey
        case .previousPlaylist:
            updatedHotkeys.previousPlaylist = hotkey
        }
        let otherHotkeys: [GlobalHotkey]
        switch purpose {
        case .playback:
            otherHotkeys = [hotkeys.nextPlaylist, hotkeys.previousPlaylist]
        case .nextPlaylist:
            otherHotkeys = [hotkeys.playback, hotkeys.previousPlaylist]
        case .previousPlaylist:
            otherHotkeys = [hotkeys.playback, hotkeys.nextPlaylist]
        }
        guard !otherHotkeys.contains(hotkey) else {
            serviceRunner.send(ServiceCommand(.configureHotkey, hotkeys: hotkeys)) { _ in }
            managerWindow?.showError("Все глобальные сочетания клавиш должны отличаться.")
            renderWindow()
            return
        }
        hotkeys = updatedHotkeys
        if let data = try? JSONEncoder().encode(hotkeys) {
            UserDefaults.standard.set(data, forKey: hotkeyKey)
        }
        if serviceRunner.isAvailable() {
            serviceRunner.send(ServiceCommand(.configureHotkey, hotkeys: hotkeys)) { [weak self] _ in
                self?.renderWindow()
            }
        }
        renderWindow()
    }

    private func startPlaylist(_ id: UUID) {
        guard let playlist = playlist(for: id) else { return }
        guard !library.videos(in: playlist).isEmpty else {
            serviceStatus = "Перед запуском добавьте видео в плейлист"
            renderWindow()
            return
        }

        selectedPlaylistID = id
        activePlaylistID = id
        shouldResumePlayback = true
        UserDefaults.standard.set(id.uuidString, forKey: selectedPlaylistKey)
        UserDefaults.standard.set(id.uuidString, forKey: activePlaylistKey)
        serviceStatus = "Запуск службы…"
        renderWindow()

        let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/WallpaperService")
        let servicePlaylists = playlists
            .filter { !library.videos(in: $0).isEmpty }
            .map(servicePlaylist(for:))
        serviceRunner.start(
            helperURL: helperURL,
            playlist: playlist,
            playlists: servicePlaylists,
            hotkeys: hotkeys
        ) { [weak self] started in
            guard let self else { return }
            if started {
                self.serviceStatus = "Служба запущена"
            } else {
                self.activePlaylistID = nil
                UserDefaults.standard.removeObject(forKey: self.activePlaylistKey)
                self.serviceStatus = "Служба недоступна"
            }
            self.renderWindow()
        }
    }

    private func refreshServiceCatalog() {
        guard serviceRunner.isAvailable() else { return }
        serviceRunner.send(ServiceCommand(
            .updatePlaylists,
            playlists: playlists
                .filter { !library.videos(in: $0).isEmpty }
                .map(servicePlaylist(for:)),
            activePlaylistID: activePlaylistID
        )) { _ in }
    }

    private func servicePlaylist(for playlist: WallpaperPlaylist) -> ServicePlaylist {
        ServicePlaylist(
            id: playlist.id,
            folderPath: playlist.folderPath,
            playbackMode: playlist.playbackMode,
            timerDurationMinutes: playlist.timerDurationMinutes,
            hotkeyEnabled: playlist.hotkeyEnabled,
            videoOrder: library.videos(in: playlist).map(\.lastPathComponent)
        )
    }

    private func sendServiceCommand(_ action: ServiceAction, status: String) {
        serviceRunner.send(ServiceCommand(action)) { [weak self] sent in
            guard let self else { return }
            self.serviceStatus = sent ? status : "Служба недоступна"
            self.renderWindow()
        }
    }

    private func performStopService() {
        shouldResumePlayback = false
        serviceRunner.send(ServiceCommand(.stop)) { [weak self] sent in
            guard let self else { return }
            self.serviceStatus = sent ? "Служба остановлена" : "Служба недоступна"
            if sent {
                self.activePlaylistID = nil
                UserDefaults.standard.removeObject(forKey: self.activePlaylistKey)
            }
            self.renderWindow()
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            UserDefaults.standard.set(enabled, forKey: launchAtLoginKey)
            renderWindow()
        } catch {
            managerWindow?.showError("Не удалось изменить настройку запуска при входе: \(error.localizedDescription)")
            renderWindow()
        }
    }

    private func changePlaylist(direction: Int) {
        guard !playlists.isEmpty else { return }
        let currentID = selectedPlaylistID ?? activePlaylistID
        let currentIndex = playlists.firstIndex { $0.id == currentID } ?? 0
        let nextIndex = (currentIndex + direction + playlists.count) % playlists.count
        managerWindow?.showHome()
        startPlaylist(playlists[nextIndex].id)
    }

    @objc private func startSelectedPlaylist() {
        guard let id = selectedPlaylistID else {
            managerWindow?.showError("Сначала выберите плейлист в списке.")
            return
        }
        startPlaylist(id)
    }

    @objc private func openManager() {
        managerWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func pauseService() {
        sendServiceCommand(.pause, status: "Воспроизведение приостановлено")
    }

    @objc private func resumeService() {
        sendServiceCommand(.resume, status: "Служба запущена")
    }

    @objc private func stopService() {
        performStopService()
    }

    @objc private func nextPlaylist() {
        changePlaylist(direction: 1)
    }

    @objc private func previousPlaylist() {
        changePlaylist(direction: -1)
    }

    private func playlist(for id: UUID) -> WallpaperPlaylist? {
        playlists.first { $0.id == id }
    }

    private func storedUUID(forKey key: String) -> UUID? {
        guard let value = UserDefaults.standard.string(forKey: key) else { return nil }
        return UUID(uuidString: value)
    }

    private func renderWindow() {
        updateStatusItemMenu()
        managerWindow?.update(
            playlists: playlists,
            selectedPlaylistID: selectedPlaylistID,
            activePlaylistID: activePlaylistID,
            serviceStatus: serviceStatus,
            hotkeys: hotkeys,
            launchAtLogin: UserDefaults.standard.bool(forKey: launchAtLoginKey),
            language: language
        )
    }
}
