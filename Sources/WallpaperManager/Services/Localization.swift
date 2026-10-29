import AppKit
import Foundation

enum AppLanguage: String {
    case russian = "ru"
    case english = "en"

    static var current: AppLanguage {
        if let stored = UserDefaults.standard.string(forKey: "interfaceLanguage"),
           let language = AppLanguage(rawValue: stored) {
            return language
        }
        return Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") == true ? .russian : .english
    }
}

enum Localization {
    private static let english: [String: String] = [
        "Живые обои": "Live Wallpapers",
        "Главная": "Home",
        "Создать плейлист": "Create Playlist",
        "Плейлисты": "Playlists",
        "Пока нет плейлистов": "No playlists yet",
        "Обложка плейлиста": "Playlist cover",
        "Управление воспроизведением и обоями.": "Manage wallpaper playback.",
        "Создайте первый плейлист и добавьте в него видео, чтобы включить обои.": "Create your first playlist and add videos to enable wallpaper playback.",
        "Медиатека пока пуста": "Your library is empty",
        "Создать первый плейлист": "Create Your First Playlist",
        "Текущее воспроизведение": "Current playback",
        "Нет активного плейлиста": "No active playlist",
        "Запустить выбранный": "Start Selected",
        "Запустить выбранный плейлист": "Start Selected Playlist",
        "Пауза": "Pause",
        "Продолжить": "Resume",
        "Остановить службу": "Stop Service",
        "Медиатека": "Library",
        "плейлист": "playlist",
        "плейлиста": "playlists",
        "плейлистов": "playlists",
        "Сочетания клавиш": "Keyboard Shortcuts",
        "Следующий плейлист": "Next Playlist",
        "Предыдущий плейлист": "Previous Playlist",
        "Нажмите на поле и введите сочетание клавиш. Они работают, пока запущена служба обоев.": "Click a shortcut field and press the key combination. Shortcuts work while the wallpaper service is running.",
        "Разрешения и запуск": "Permissions and Startup",
        "Дополнительные разрешения macOS не нужны. Видео хранятся в медиатеке приложения. Сочетания клавиш не требуют доступа к Универсальному доступу.": "No extra macOS permissions are required. Videos are stored in the app library. Shortcuts don’t require Accessibility access.",
        "Запускать при входе и включать выбранный плейлист": "Launch at login and start the selected playlist",
        "Создайте папку плейлиста и добавьте в неё видео.": "Create a playlist folder and add videos to it.",
        "Название плейлиста": "Playlist Name",
        "Например, Природа": "For example, Nature",
        "Отдельная папка будет создана в медиатеке приложения.": "A separate folder will be created in the app library.",
        "Настройки плейлиста и список видео.": "Playlist settings and video library.",
        "Папка плейлиста": "Playlist Folder",
        "Папка находится в медиатеке приложения. Добавленные видео копируются в неё.": "The folder is in the app library. Added videos are copied here.",
        "Видео в плейлисте": "Playlist Videos",
        "В плейлисте пока нет видео. Добавьте ролики, чтобы начать воспроизведение.": "This playlist has no videos yet. Add videos to start playback.",
        "Переместить видео выше": "Move video up",
        "Переместить видео ниже": "Move video down",
        "Удалить видео из плейлиста": "Remove video from playlist",
        "Видео будет удалено из папки этого плейлиста.": "The video will be deleted from this playlist’s folder.",
        "Не удалось добавить выбранные видео. Проверьте формат и доступ к файлам.": "Could not add the selected videos. Check the file formats and access permissions.",
        "Добавить видео…": "Add Videos…",
        "Режим смены обоев": "Wallpaper Switching Mode",
        "Следующее по окончании": "Next at End",
        "Повтор + клавиша": "Loop + Hotkey",
        "Повтор + таймер": "Loop + Timer",
        "Менять через (минут)": "Switch After (Minutes)",
        "Также менять видео горячей клавишей": "Also switch videos with the hotkey",
        "Горячая клавиша смены видео": "Global Playback Hotkey",
        "Нажмите на поле и введите сочетание. По умолчанию: Control + Option + P.": "Click the shortcut field and press a key combination. Default: Control + Option + P.",
        "Запустить плейлист": "Start Playlist",
        "Удалить плейлист": "Delete Playlist",
        "Удалить видео": "Delete Video",
        "Включить следующее видео после завершения текущего": "Play the next video when the current one ends",
        "Повторять видео, пока не нажата горячая клавиша": "Loop the current video until the hotkey is pressed",
        "Нажмите, чтобы записать сочетание.": "Click to record a new shortcut.",
        "Горячая клавиша. Нажмите, чтобы записать сочетание.": "Hotkey. Click to record a new shortcut.",
        "Нажмите сочетание…": "Press a shortcut…",
        "Пробел": "Space",
        "Удалить": "Delete",
        "Домой": "Home key",
        "Удалить вперёд": "Forward Delete",
        "Конец": "End",
        "Введите название плейлиста.": "Enter a playlist name.",
        "Плейлист с таким названием уже существует.": "A playlist with that name already exists.",
        "ОК": "OK",
        "Добавить в плейлист": "Add to Playlist",
        "Папка плейлиста и все видео в ней будут удалены без возможности восстановления.": "The playlist folder and all videos inside it will be permanently deleted.",
        "Отмена": "Cancel",
        "Служба остановлена": "Service stopped",
        "Служба запущена": "Service running",
        "Воспроизведение приостановлено": "Playback paused",
        "Служба недоступна": "Service is not available",
        "Запуск службы…": "Starting service…",
        "Перед запуском добавьте видео в плейлист": "Add a video before starting this playlist",
        "Сначала выберите плейлист в списке.": "Choose a playlist from the list first.",
        "Не удалось удалить папку плейлиста.": "Could not delete the playlist folder.",
        "Все глобальные сочетания клавиш должны отличаться.": "Each global shortcut must be different.",
        "Воспроизведение": "Playback",
        "Открыть «Живые обои»": "Open Live Wallpapers",
        "Скрыть «Живые обои»": "Hide Live Wallpapers",
        "Завершить работу «Живые обои»": "Quit Live Wallpapers",
        "Менять каждые ": "Switch every ",
        " мин.": " min.",
        " или по горячей клавише": " or with the hotkey",
        "Добавлено видео: ": "Videos added: ",
        " из ": " of ",
        "Не удалось удалить видео: ": "Could not remove video: ",
        "Страница вверх": "Page Up",
        "Страница вниз": "Page Down"
    ]

    static func text(_ value: String, language: AppLanguage = .current) -> String {
        guard language == .english else {
            return english.first(where: { $0.value == value })?.key ?? value
        }
        if let translation = english[value] { return translation }
        if value.hasPrefix("Менять каждые ") {
            return value.replacingOccurrences(of: "Менять каждые ", with: "Switch every ")
                .replacingOccurrences(of: " мин.", with: " min.")
                .replacingOccurrences(of: " или по горячей клавише", with: " or with the hotkey")
        }
        if value.hasPrefix("Добавлено видео: ") {
            return value.replacingOccurrences(of: "Добавлено видео: ", with: "Videos added: ")
                .replacingOccurrences(of: " из ", with: " of ")
        }
        if value.hasPrefix("Не удалось удалить видео: ") {
            return value.replacingOccurrences(of: "Не удалось удалить видео: ", with: "Could not remove video: ")
        }
        if value.hasPrefix("Удалить видео «"), value.hasSuffix("»?") {
            let name = value.dropFirst("Удалить видео «".count).dropLast(2)
            return "Delete video ‘\(name)’?"
        }
        if value.hasPrefix("Could not remove video: ") {
            return value.replacingOccurrences(of: "Could not remove video: ", with: "Не удалось удалить видео: ")
        }
        if value.hasPrefix("Удалить плейлист «"), value.hasSuffix("»?") {
            let name = value.dropFirst("Удалить плейлист «".count).dropLast(2)
            return "Delete playlist ‘\(name)’?"
        }
        if value.hasPrefix("Удалить видео «"), value.hasSuffix("»?") {
            let name = value.dropFirst("Удалить видео «".count).dropLast(2)
            return "Delete video ‘\(name)’?"
        }
        if value.hasPrefix("Не удалось изменить настройку запуска при входе: ") {
            return value.replacingOccurrences(of: "Не удалось изменить настройку запуска при входе: ", with: "Could not update launch-at-login setting: ")
        }
        if value.hasSuffix(" видео"), let count = value.split(separator: " ").first {
            return count == "1" ? "1 video" : "\(count) videos"
        }
        if value.hasPrefix("Videos added: ") {
            return value.replacingOccurrences(of: "Videos added: ", with: "Добавлено видео: ")
        }
        if value.hasPrefix("Switch every ") {
            return value.replacingOccurrences(of: "Switch every ", with: "Менять каждые ")
                .replacingOccurrences(of: " min.", with: " мин.")
                .replacingOccurrences(of: " or with the hotkey", with: " или по горячей клавише")
        }
        if value.hasPrefix("Delete playlist ‘"), value.hasSuffix("’?") {
            let name = value.dropFirst("Delete playlist ‘".count).dropLast(2)
            return "Удалить плейлист «\(name)»?"
        }
        if value.hasPrefix("Delete video ‘"), value.hasSuffix("’?") {
            let name = value.dropFirst("Delete video ‘".count).dropLast(2)
            return "Удалить видео «\(name)»?"
        }
        if value.hasPrefix("Could not update launch-at-login setting: ") {
            return value.replacingOccurrences(of: "Could not update launch-at-login setting: ", with: "Не удалось изменить настройку запуска при входе: ")
        }
        return value
    }

    static func apply(to view: NSView, language: AppLanguage) {
        if let field = view as? NSTextField {
            field.stringValue = text(field.stringValue, language: language)
            if let placeholder = field.placeholderString {
                field.placeholderString = text(placeholder, language: language)
            }
            if let label = field.accessibilityLabel() {
                field.setAccessibilityLabel(text(label, language: language))
            }
        }
        if let button = view as? NSButton {
            button.title = text(button.title, language: language)
            if let label = button.accessibilityLabel() {
                button.setAccessibilityLabel(text(label, language: language))
            }
        }
        if let segmented = view as? NSSegmentedControl {
            for index in 0..<segmented.segmentCount {
                if let label = segmented.label(forSegment: index) {
                    segmented.setLabel(text(label, language: language), forSegment: index)
                }
            }
        }
        for child in view.subviews {
            apply(to: child, language: language)
        }
    }
}
