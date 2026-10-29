import AppKit

final class ManagerSidebarView: NSView {
    var onHome: (() -> Void)?
    var onCreatePlaylist: (() -> Void)?
    var onSelectPlaylist: ((UUID) -> Void)?
    var onLanguageChanged: ((AppLanguage) -> Void)?

    private let thumbnailProvider: VideoThumbnailProvider
    private let playlistButtons = NSStackView()
    private let languagePicker = NSPopUpButton(frame: .zero, pullsDown: false)

    init(thumbnailProvider: VideoThumbnailProvider) {
        self.thumbnailProvider = thumbnailProvider
        super.init(frame: .zero)
        buildView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSidebarBackground()
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        updateSidebarBackground()
    }

    private func updateSidebarBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [weak self] in
            self?.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }

    func update(playlists: [WallpaperPlaylist], page: ManagerPage, language: AppLanguage) {
        updateSidebarBackground()
        languagePicker.selectItem(at: language == .russian ? 0 : 1)
        for view in playlistButtons.arrangedSubviews {
            playlistButtons.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard !playlists.isEmpty else {
            let label = NSTextField(labelWithString: "Пока нет плейлистов")
            label.textColor = .secondaryLabelColor
            playlistButtons.addArrangedSubview(label)
            Localization.apply(to: self, language: language)
            return
        }

        for playlist in playlists {
            let button = ActionButton(title: playlist.name) { [weak self] in
                self?.onSelectPlaylist?(playlist.id)
            }
            button.alignment = .left
            button.setButtonType(.pushOnPushOff)
            if case .playlistDetail(let id) = page, id == playlist.id {
                button.state = .on
            }

            let imageView = thumbnailView(for: playlist, size: NSSize(width: 42, height: 24))
            let row = NSStackView(views: [imageView, button])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false
            playlistButtons.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: playlistButtons.widthAnchor).isActive = true
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true
        }
        Localization.apply(to: self, language: language)
    }

    private func buildView() {
        wantsLayer = true
        updateSidebarBackground()

        let title = NSTextField(labelWithString: "Живые обои")
        title.font = .boldSystemFont(ofSize: 17)
        languagePicker.addItems(withTitles: ["Русский", "English"])
        languagePicker.target = self
        languagePicker.action = #selector(languageSelectionChanged(_:))
        let homeButton = ActionButton(title: "Главная") { [weak self] in self?.onHome?() }
        let createButton = ActionButton(title: "Создать плейлист") { [weak self] in self?.onCreatePlaylist?() }
        let playlistTitle = NSTextField(labelWithString: "Плейлисты")
        playlistTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        playlistTitle.textColor = .secondaryLabelColor

        playlistButtons.orientation = .vertical
        playlistButtons.alignment = .leading
        playlistButtons.distribution = .fill
        playlistButtons.spacing = 6
        playlistButtons.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(playlistButtons)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = document
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [title, languagePicker, homeButton, createButton, playlistTitle, scrollView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            homeButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            createButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            playlistButtons.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            playlistButtons.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            playlistButtons.topAnchor.constraint(equalTo: document.topAnchor),
            document.bottomAnchor.constraint(greaterThanOrEqualTo: playlistButtons.bottomAnchor, constant: 8)
        ])
    }

    @objc private func languageSelectionChanged(_ sender: NSPopUpButton) {
        onLanguageChanged?(sender.indexOfSelectedItem == 0 ? .russian : .english)
    }

    private func thumbnailView(for playlist: WallpaperPlaylist, size: NSSize) -> NSImageView {
        let imageView = NSImageView()
        imageView.image = thumbnailProvider.cachedImage(for: playlist)
            ?? NSImage(systemSymbolName: "film", accessibilityDescription: "Обложка плейлиста")
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: size.width),
            imageView.heightAnchor.constraint(equalToConstant: size.height)
        ])
        thumbnailProvider.loadImage(for: playlist) { [weak imageView] image in
            if let image {
                imageView?.image = image
            }
        }
        return imageView
    }
}
