import AppKit

final class ManagerWindowController: NSWindowController {
    var onCreatePlaylist: ((String) -> Void)?
    var onShowCreatePlaylist: (() -> Void)?
    var onAddVideos: ((UUID, [URL]) -> Void)?
    var onReorderVideo: ((UUID, URL, Int) -> Void)?
    var onRemoveVideo: ((UUID, URL) -> Void)?
    var onDeletePlaylist: ((UUID) -> Void)?
    var onStartPlaylist: ((UUID) -> Void)?
    var onPauseService: (() -> Void)?
    var onResumeService: (() -> Void)?
    var onStopService: (() -> Void)?
    var onStartSelectedPlaylist: ((UUID?) -> Void)?
    var onChangePlaybackSettings: ((UUID, PlaylistPlaybackMode, Int, Bool) -> Void)?
    var onChangeHotkey: ((GlobalHotkey) -> Void)?
    var onChangePlaylistHotkey: ((GlobalHotkey, HotkeyPurpose) -> Void)?
    var onBeginHotkeyCapture: (() -> Void)?
    var onCancelHotkeyCapture: (() -> Void)?
    var onSelectedPlaylistChanged: ((UUID) -> Void)?
    var onLaunchAtLoginChanged: ((Bool) -> Void)?
    var onLanguageChanged: ((AppLanguage) -> Void)?

    private let sidebar: ManagerSidebarView
    private let pageFactory: ManagerPageFactory
    private var mainContent = NSView()
    private var playlists: [WallpaperPlaylist] = []
    private var selectedPlaylistID: UUID?
    private var activePlaylistID: UUID?
    private var serviceStatus = "Служба остановлена"
    private var hotkeys = PlaylistHotkeys.default
    private var launchAtLogin = false
    private var language = AppLanguage.current
    private var page: ManagerPage = .home

    init(library: PlaylistLibrary, thumbnails: VideoThumbnailProvider) {
        sidebar = ManagerSidebarView(thumbnailProvider: thumbnails)
        pageFactory = ManagerPageFactory(library: library, thumbnails: thumbnails)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Живые обои"
        super.init(window: window)
        buildWindow()
        connectSidebar()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        playlists: [WallpaperPlaylist],
        selectedPlaylistID: UUID?,
        activePlaylistID: UUID?,
        serviceStatus: String,
        hotkeys: PlaylistHotkeys,
        launchAtLogin: Bool,
        language: AppLanguage
    ) {
        self.playlists = playlists
        self.selectedPlaylistID = selectedPlaylistID
        self.activePlaylistID = activePlaylistID
        self.serviceStatus = serviceStatus
        self.hotkeys = hotkeys
        self.launchAtLogin = launchAtLogin
        self.language = language
        window?.title = Localization.text("Живые обои", language: language)
        if case .playlistDetail(let id) = page, !playlists.contains(where: { $0.id == id }) {
            page = .home
        }
        renderPage()
    }

    func showHome() {
        page = .home
        renderPage()
    }

    func showCreatePlaylist() {
        page = .createPlaylist
        renderPage()
        if let field = pageFactory.createNameField {
            window?.makeFirstResponder(field)
        }
    }

    func showPlaylist(_ id: UUID) {
        selectedPlaylistID = id
        page = .playlistDetail(id)
        renderPage()
    }

    func invalidateThumbnail(for playlistID: UUID) {
        pageFactory.invalidateThumbnail(for: playlistID)
    }

    func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = Localization.text(message, language: language)
        alert.addButton(withTitle: Localization.text("ОК", language: language))
        alert.runModal()
    }

    private func buildWindow() {
        guard let contentView = window?.contentView else { return }
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        mainContent.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sidebar)
        contentView.addSubview(mainContent)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: contentView.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 220),
            mainContent.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            mainContent.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainContent.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainContent.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func connectSidebar() {
        sidebar.onLanguageChanged = { [weak self] language in
            self?.onLanguageChanged?(language)
        }
        sidebar.onHome = { [weak self] in
            self?.page = .home
            self?.renderPage()
        }
        sidebar.onCreatePlaylist = { [weak self] in
            self?.page = .createPlaylist
            self?.renderPage()
            if let field = self?.pageFactory.createNameField {
                self?.window?.makeFirstResponder(field)
            }
        }
        sidebar.onSelectPlaylist = { [weak self] id in
            guard let self else { return }
            self.selectedPlaylistID = id
            self.page = .playlistDetail(id)
            self.onSelectedPlaylistChanged?(id)
            self.renderPage()
        }
    }

    private func renderPage() {
        sidebar.update(playlists: playlists, page: page, language: language)
        mainContent.subviews.forEach { $0.removeFromSuperview() }

        let actions = ManagerPageActions(
            startSelected: { [weak self] in self?.onStartSelectedPlaylist?(self?.selectedPlaylistID) },
            pause: { [weak self] in self?.onPauseService?() },
            resume: { [weak self] in self?.onResumeService?() },
            stop: { [weak self] in self?.onStopService?() },
            createPlaylist: { [weak self] name in self?.onCreatePlaylist?(name) },
            showCreatePlaylist: { [weak self] in self?.showCreatePlaylist() },
            addVideos: { [weak self] id in self?.chooseVideos(for: id) },
            reorderVideo: { [weak self] id, url, direction in self?.onReorderVideo?(id, url, direction) },
            removeVideo: { [weak self] id, url in self?.confirmRemoveVideo(url, playlistID: id) },
            changePlaybackSettings: { [weak self] id, mode, minutes, enabled in
                self?.onChangePlaybackSettings?(id, mode, minutes, enabled)
            },
            changeHotkey: { [weak self] hotkey in self?.onChangeHotkey?(hotkey) },
            changePlaylistHotkey: { [weak self] hotkey, purpose in
                self?.onChangePlaylistHotkey?(hotkey, purpose)
            },
            beginHotkeyCapture: { [weak self] in self?.onBeginHotkeyCapture?() },
            cancelHotkeyCapture: { [weak self] in self?.onCancelHotkeyCapture?() },
            setLaunchAtLogin: { [weak self] enabled in self?.onLaunchAtLoginChanged?(enabled) },
            startPlaylist: { [weak self] id in self?.onStartPlaylist?(id) },
            deletePlaylist: { [weak self] id in self?.confirmDeletePlaylist(id) }
        )

        let content = pageFactory.makePage(
            page,
            playlists: playlists,
            activePlaylistID: activePlaylistID,
            serviceStatus: serviceStatus,
            hotkeys: hotkeys,
            launchAtLogin: launchAtLogin,
            actions: actions
        )
        Localization.apply(to: content, language: language)
        content.translatesAutoresizingMaskIntoConstraints = false
        mainContent.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: mainContent.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: mainContent.trailingAnchor),
            content.topAnchor.constraint(equalTo: mainContent.topAnchor),
            content.bottomAnchor.constraint(equalTo: mainContent.bottomAnchor)
        ])
    }

    private func chooseVideos(for playlistID: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = Localization.text("Добавить в плейлист", language: language)
        guard panel.runModal() == .OK else { return }
        onAddVideos?(playlistID, panel.urls)
    }

    private func confirmRemoveVideo(_ videoURL: URL, playlistID: UUID) {
        let alert = NSAlert()
        alert.messageText = Localization.text("Удалить видео «\(videoURL.lastPathComponent)»?", language: language)
        alert.informativeText = Localization.text("Видео будет удалено из папки этого плейлиста.", language: language)
        alert.alertStyle = .warning
        alert.addButton(withTitle: Localization.text("Удалить видео", language: language))
        alert.addButton(withTitle: Localization.text("Отмена", language: language))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        onRemoveVideo?(playlistID, videoURL)
    }

    private func confirmDeletePlaylist(_ playlistID: UUID) {
        guard let playlist = playlists.first(where: { $0.id == playlistID }) else { return }
        let alert = NSAlert()
        alert.messageText = Localization.text("Удалить плейлист «\(playlist.name)»?", language: language)
        alert.informativeText = Localization.text("Папка плейлиста и все видео в ней будут удалены без возможности восстановления.", language: language)
        alert.alertStyle = .warning
        alert.addButton(withTitle: Localization.text("Удалить плейлист", language: language))
        alert.addButton(withTitle: Localization.text("Отмена", language: language))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        onDeletePlaylist?(playlistID)
    }
}
