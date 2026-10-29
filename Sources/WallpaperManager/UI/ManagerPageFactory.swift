import AppKit

struct ManagerPageActions {
    var startSelected: () -> Void
    var pause: () -> Void
    var resume: () -> Void
    var stop: () -> Void
    var createPlaylist: (String) -> Void
    var showCreatePlaylist: () -> Void
    var addVideos: (UUID) -> Void
    var reorderVideo: (UUID, URL, Int) -> Void
    var removeVideo: (UUID, URL) -> Void
    var changePlaybackSettings: (UUID, PlaylistPlaybackMode, Int, Bool) -> Void
    var changeHotkey: (GlobalHotkey) -> Void
    var changePlaylistHotkey: (GlobalHotkey, HotkeyPurpose) -> Void
    var beginHotkeyCapture: () -> Void
    var cancelHotkeyCapture: () -> Void
    var setLaunchAtLogin: (Bool) -> Void
    var startPlaylist: (UUID) -> Void
    var deletePlaylist: (UUID) -> Void
}

final class ManagerPageFactory {
    private let library: PlaylistLibrary
    private let thumbnails: VideoThumbnailProvider
    private var relays: [ActionRelay] = []
    private(set) var createNameField: NSTextField?

    init(library: PlaylistLibrary, thumbnails: VideoThumbnailProvider) {
        self.library = library
        self.thumbnails = thumbnails
    }

    func makePage(
        _ page: ManagerPage,
        playlists: [WallpaperPlaylist],
        activePlaylistID: UUID?,
        serviceStatus: String,
        hotkeys: PlaylistHotkeys,
        launchAtLogin: Bool,
        actions: ManagerPageActions
    ) -> NSView {
        relays.removeAll()
        createNameField = nil
        switch page {
        case .home:
            return makeHomePage(playlists: playlists, activePlaylistID: activePlaylistID, serviceStatus: serviceStatus, hotkeys: hotkeys, launchAtLogin: launchAtLogin, actions: actions)
        case .createPlaylist:
            return makeCreatePlaylistPage(actions: actions)
        case .playlistDetail(let id):
            guard let playlist = playlists.first(where: { $0.id == id }) else {
                return makeHomePage(playlists: playlists, activePlaylistID: activePlaylistID, serviceStatus: serviceStatus, hotkeys: hotkeys, launchAtLogin: launchAtLogin, actions: actions)
            }
            return makePlaylistDetailPage(playlist, playbackHotkey: hotkeys.playback, actions: actions)
        }
    }

    private func makeHomePage(
        playlists: [WallpaperPlaylist],
        activePlaylistID: UUID?,
        serviceStatus: String,
        hotkeys: PlaylistHotkeys,
        launchAtLogin: Bool,
        actions: ManagerPageActions
    ) -> NSView {
        let title = pageTitle("Главная", subtitle: "Управление воспроизведением и обоями.")

        let currentTitle = sectionTitle("Текущее воспроизведение")
        let activeName = playlists.first(where: { $0.id == activePlaylistID })?.name ?? "Нет активного плейлиста"
        let currentValue = NSTextField(labelWithString: activeName)
        currentValue.font = .boldSystemFont(ofSize: 19)
        let status = NSTextField(labelWithString: serviceStatus)
        status.textColor = .secondaryLabelColor
        let controls = NSStackView(views: [
            button("Запустить выбранный", action: actions.startSelected),
            button("Пауза", action: actions.pause),
            button("Продолжить", action: actions.resume),
            button("Остановить службу", action: actions.stop)
        ])
        controls.orientation = .horizontal
        controls.distribution = .fillEqually
        controls.spacing = 8
        let playbackCard = card([currentTitle, currentValue, status, controls])

        let libraryTitle = sectionTitle("Медиатека")
        let playlistCount = NSTextField(labelWithString: "\(playlists.count)")
        playlistCount.font = .boldSystemFont(ofSize: 29)
        let playlistCaption = NSTextField(labelWithString: playlistNoun(playlists.count))
        playlistCaption.textColor = .secondaryLabelColor
        let libraryCard = card([libraryTitle, playlistCount, playlistCaption])

        let shortcutTitle = sectionTitle("Сочетания клавиш")
        let nextHotkey = hotkeyRecorderRow("Следующий плейлист", hotkey: hotkeys.nextPlaylist, purpose: .nextPlaylist, actions: actions)
        let previousHotkey = hotkeyRecorderRow("Предыдущий плейлист", hotkey: hotkeys.previousPlaylist, purpose: .previousPlaylist, actions: actions)
        let shortcutHint = NSTextField(wrappingLabelWithString: "Нажмите на поле и введите сочетание клавиш. Они работают, пока запущена служба обоев.")
        shortcutHint.textColor = .secondaryLabelColor
        let shortcutCard = card([shortcutTitle, nextHotkey, previousHotkey, shortcutHint])

        let permissionTitle = sectionTitle("Разрешения и запуск")
        let permissionText = NSTextField(wrappingLabelWithString: "Дополнительные разрешения macOS не нужны. Видео хранятся в медиатеке приложения. Сочетания клавиш не требуют доступа к Универсальному доступу.")
        let launchToggle = NSButton(checkboxWithTitle: "Запускать при входе и включать выбранный плейлист", target: nil, action: nil)
        launchToggle.state = launchAtLogin ? .on : .off
        let launchRelay = ActionRelay { sender in
            guard let toggle = sender as? NSButton else { return }
            actions.setLaunchAtLogin(toggle.state == .on)
        }
        relays.append(launchRelay)
        launchToggle.target = launchRelay
        launchToggle.action = #selector(ActionRelay.invoke(_:))
        let permissionCard = card([permissionTitle, permissionText, launchToggle])

        var sections = [playbackCard, libraryCard, shortcutCard, permissionCard]
        if playlists.isEmpty {
            let emptyDescription = NSTextField(wrappingLabelWithString: "Создайте первый плейлист и добавьте в него видео, чтобы включить обои.")
            emptyDescription.textColor = .secondaryLabelColor
            let emptyCard = card([
                sectionTitle("Медиатека пока пуста"),
                emptyDescription,
                button("Создать первый плейлист", action: actions.showCreatePlaylist)
            ])
            sections.insert(emptyCard, at: 0)
        }
        return pageScrollView(title: title, sections: sections)
    }

    private func makeCreatePlaylistPage(actions: ManagerPageActions) -> NSView {
        let title = pageTitle("Создать плейлист", subtitle: "Создайте папку плейлиста и добавьте в неё видео.")
        let nameCaption = sectionTitle("Название плейлиста")
        let nameField = NSTextField(string: "")
        nameField.frame = NSRect(x: 0, y: 0, width: 360, height: 30)
        nameField.placeholderString = "Например, Природа"
        nameField.font = .systemFont(ofSize: 15)
        createNameField = nameField
        let locationText = NSTextField(wrappingLabelWithString: "Отдельная папка будет создана в медиатеке приложения.")
        locationText.textColor = .secondaryLabelColor
        let createButton = button("Создать плейлист") {
            actions.createPlaylist(nameField.stringValue)
        }
        let form = card([nameCaption, nameField, locationText, createButton])
        return pageScrollView(title: title, sections: [form])
    }

    private func makePlaylistDetailPage(_ playlist: WallpaperPlaylist, playbackHotkey: GlobalHotkey, actions: ManagerPageActions) -> NSView {
        let title = pageTitle(playlist.name, subtitle: "Настройки плейлиста и список видео.")
        let cover = coverView(for: playlist, size: NSSize(width: 300, height: 169))
        let count = library.videos(in: playlist).count
        let repeatDescription = playbackModeDescription(playlist)
        let coverInfo = NSStackView(views: [
            NSTextField(labelWithString: "\(count) видео"),
            NSTextField(labelWithString: repeatDescription)
        ])
        coverInfo.orientation = .vertical
        coverInfo.alignment = .leading
        coverInfo.distribution = .fill
        coverInfo.spacing = 8
        let coverRow = NSStackView(views: [cover, coverInfo])
        coverRow.orientation = .horizontal
        coverRow.alignment = .centerY
        coverRow.spacing = 18
        let coverCard = card([coverRow])

        let videos = library.videos(in: playlist)
        let overviewTitle = sectionTitle("Папка плейлиста")
        let folderDescription = NSTextField(wrappingLabelWithString: "Папка находится в медиатеке приложения. Добавленные видео копируются в неё.")
        folderDescription.textColor = .secondaryLabelColor
        let countLabel = NSTextField(labelWithString: "\(count) видео")
        let addButton = button("Добавить видео…") {
            actions.addVideos(playlist.id)
        }
        let overviewCard = card([overviewTitle, folderDescription, countLabel, addButton])

        let videoSection: NSView
        if videos.isEmpty {
            let emptyDescription = NSTextField(wrappingLabelWithString: "В плейлисте пока нет видео. Добавьте ролики, чтобы начать воспроизведение.")
            emptyDescription.textColor = .secondaryLabelColor
            videoSection = card([
                sectionTitle("Видео в плейлисте"),
                emptyDescription,
                button("Добавить видео…") { actions.addVideos(playlist.id) }
            ])
        } else {
            let rows = NSStackView()
            rows.orientation = .vertical
            rows.alignment = .leading
            rows.distribution = .fill
            rows.spacing = 7
            for (index, videoURL) in videos.enumerated() {
                let name = NSTextField(labelWithString: videoURL.lastPathComponent)
                name.lineBreakMode = .byTruncatingMiddle
                name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                let moveUp = button("↑") { actions.reorderVideo(playlist.id, videoURL, -1) }
                styleReorderButton(moveUp, symbol: "chevron.up")
                moveUp.setAccessibilityLabel("Переместить видео выше")
                moveUp.isEnabled = index > 0
                let moveDown = button("↓") { actions.reorderVideo(playlist.id, videoURL, 1) }
                styleReorderButton(moveDown, symbol: "chevron.down")
                moveDown.setAccessibilityLabel("Переместить видео ниже")
                moveDown.isEnabled = index < videos.count - 1
                let remove = button("Удалить") { actions.removeVideo(playlist.id, videoURL) }
                remove.controlSize = .small
                remove.widthAnchor.constraint(equalToConstant: 84).isActive = true
                remove.heightAnchor.constraint(equalToConstant: 30).isActive = true
                remove.setAccessibilityLabel("Удалить видео из плейлиста")
                let row = NSStackView(views: [name, moveUp, moveDown, remove])
                row.orientation = .horizontal
                row.alignment = .centerY
                row.distribution = .fill
                row.spacing = 8
                rows.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            }
            videoSection = card([sectionTitle("Видео в плейлисте"), rows])
        }

        let ruleTitle = sectionTitle("Режим смены обоев")
        let modeControl = segmentedControl(
            labels: ["Следующее по окончании", "Повтор + клавиша", "Повтор + таймер"],
            selected: modeIndex(playlist.playbackMode)
        ) { selectedSegment in
            let mode = self.playbackMode(for: selectedSegment)
            actions.changePlaybackSettings(playlist.id, mode, playlist.timerDurationMinutes, playlist.hotkeyEnabled)
        }
        let timerCaption = NSTextField(labelWithString: "Менять через (минут)")
        let timerField = NSTextField(string: "\(playlist.timerDurationMinutes)")
        timerField.alignment = .center
        timerField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        timerField.isEnabled = playlist.playbackMode == .loopForDuration
        let timerRelay = ActionRelay { sender in
            guard let field = sender as? NSTextField else { return }
            actions.changePlaybackSettings(playlist.id, playlist.playbackMode, max(1, field.integerValue), playlist.hotkeyEnabled)
        }
        relays.append(timerRelay)
        timerField.target = timerRelay
        timerField.action = #selector(ActionRelay.invoke(_:))
        let timerRow = NSStackView(views: [timerCaption, timerField])
        timerRow.orientation = .horizontal
        timerRow.alignment = .centerY
        timerRow.spacing = 10

        let allowHotkey = NSButton(checkboxWithTitle: "Также менять видео горячей клавишей", target: nil, action: nil)
        allowHotkey.state = playlist.hotkeyEnabled ? .on : .off
        allowHotkey.isEnabled = playlist.playbackMode == .loopForDuration
        let hotkeyRelay = ActionRelay { sender in
            guard let checkbox = sender as? NSButton else { return }
            actions.changePlaybackSettings(playlist.id, playlist.playbackMode, playlist.timerDurationMinutes, checkbox.state == .on)
        }
        relays.append(hotkeyRelay)
        allowHotkey.target = hotkeyRelay
        allowHotkey.action = #selector(ActionRelay.invoke(_:))

        let hotkeyTitle = NSTextField(labelWithString: "Горячая клавиша смены видео")
        let hotkeyField = HotkeyRecorderButton(hotkey: playbackHotkey)
        hotkeyField.widthAnchor.constraint(equalToConstant: 190).isActive = true
        hotkeyField.onChange = actions.changeHotkey
        hotkeyField.onBeginRecording = actions.beginHotkeyCapture
        hotkeyField.onCancelRecording = actions.cancelHotkeyCapture
        let hotkeyRow = NSStackView(views: [hotkeyTitle, hotkeyField])
        hotkeyRow.orientation = .horizontal
        hotkeyRow.alignment = .centerY
        hotkeyRow.spacing = 10
        let hotkeyHint = NSTextField(wrappingLabelWithString: "Нажмите на поле и введите сочетание. По умолчанию: Control + Option + P.")
        hotkeyHint.textColor = .secondaryLabelColor

        let ruleCard = card([ruleTitle, modeControl, timerRow, allowHotkey, hotkeyRow, hotkeyHint])

        let startButton = button("Запустить плейлист") {
            actions.startPlaylist(playlist.id)
        }
        let deleteButton = button("Удалить плейлист") {
            actions.deletePlaylist(playlist.id)
        }
        let controls = NSStackView(views: [startButton, deleteButton])
        controls.orientation = .horizontal
        controls.distribution = .fillEqually
        controls.spacing = 8
        let actionCard = card([controls])

        return pageScrollView(title: title, sections: [coverCard, overviewCard, videoSection, ruleCard, actionCard])
    }

    private func hotkeyRecorderRow(
        _ label: String,
        hotkey: GlobalHotkey,
        purpose: HotkeyPurpose,
        actions: ManagerPageActions
    ) -> NSStackView {
        let title = NSTextField(labelWithString: label)
        let recorder = HotkeyRecorderButton(hotkey: hotkey)
        recorder.widthAnchor.constraint(equalToConstant: 190).isActive = true
        recorder.onChange = { actions.changePlaylistHotkey($0, purpose) }
        recorder.onBeginRecording = actions.beginHotkeyCapture
        recorder.onCancelRecording = actions.cancelHotkeyCapture
        let row = NSStackView(views: [title, recorder])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func playbackModeDescription(_ playlist: WallpaperPlaylist) -> String {
        switch playlist.playbackMode {
        case .advanceAtEnd:
            return "Включить следующее видео после завершения текущего"
        case .loopUntilHotkey:
            return "Повторять видео, пока не нажата горячая клавиша"
        case .loopForDuration:
            return "Менять каждые \(playlist.timerDurationMinutes) мин.\(playlist.hotkeyEnabled ? " или по горячей клавише" : "")"
        }
    }

    private func modeIndex(_ mode: PlaylistPlaybackMode) -> Int {
        switch mode {
        case .advanceAtEnd: return 0
        case .loopUntilHotkey: return 1
        case .loopForDuration: return 2
        }
    }

    private func playbackMode(for index: Int) -> PlaylistPlaybackMode {
        switch index {
        case 1: return .loopUntilHotkey
        case 2: return .loopForDuration
        default: return .advanceAtEnd
        }
    }

    private func pageTitle(_ title: String, subtitle: String) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .boldSystemFont(ofSize: 26)
        let description = NSTextField(wrappingLabelWithString: subtitle)
        description.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [heading, description])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        return stack
    }

    private func pageScrollView(title: NSView, sections: [NSView]) -> NSView {
        let stack = NSStackView(views: [title] + sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let documentView = FlippedDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = documentView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -20)
        ])
        sections.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return scrollView
    }

    private func card(_ arrangedViews: [NSView]) -> NSView {
        let card = AppearanceAwareBackgroundView(fillColor: .controlBackgroundColor, cornerRadius: 10)

        let stack = NSStackView(views: arrangedViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 13),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -13)
        ])
        arrangedViews.compactMap { $0 as? NSStackView }
            .forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return card
    }

    private func coverView(for playlist: WallpaperPlaylist, size: NSSize) -> NSImageView {
        let imageView = NSImageView()
        imageView.image = thumbnails.cachedImage(for: playlist)
            ?? NSImage(systemSymbolName: "film", accessibilityDescription: "Обложка плейлиста")
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: size.width),
            imageView.heightAnchor.constraint(equalToConstant: size.height)
        ])
        thumbnails.loadImage(for: playlist) { [weak imageView] image in
            if let image {
                imageView?.image = image
            }
        }
        return imageView
    }

    func invalidateThumbnail(for playlistID: UUID) {
        thumbnails.invalidate(playlistID)
    }

    private func playlistNoun(_ count: Int) -> String {
        let lastTwo = count % 100
        if (11...14).contains(lastTwo) { return "плейлистов" }
        switch count % 10 {
        case 1: return "плейлист"
        case 2...4: return "плейлиста"
        default: return "плейлистов"
        }
    }

    private func styleReorderButton(_ button: NSButton, symbol: String) {
        button.title = ""
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.controlSize = .small
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func button(_ title: String, action: @escaping () -> Void) -> NSButton {
        let relay = ActionRelay { _ in action() }
        relays.append(relay)
        let button = NSButton(title: title, target: relay, action: #selector(ActionRelay.invoke(_:)))
        button.bezelStyle = .rounded
        return button
    }

    private func segmentedControl(
        labels: [String],
        selected: Int,
        action: @escaping (Int) -> Void
    ) -> NSSegmentedControl {
        let relay = ActionRelay { sender in
            guard let control = sender as? NSSegmentedControl else { return }
            action(control.selectedSegment)
        }
        relays.append(relay)
        let control = NSSegmentedControl(
            labels: labels,
            trackingMode: .selectOne,
            target: relay,
            action: #selector(ActionRelay.invoke(_:))
        )
        control.segmentStyle = .rounded
        labels.indices.forEach { control.setWidth(180, forSegment: $0) }
        control.selectedSegment = selected
        return control
    }
}
