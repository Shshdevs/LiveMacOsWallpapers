# LiveMacOsWallpapers

Приложение для управления видеообоями macOS. Состоит из менеджера и отдельного процесса воспроизведения.

## Сборка и запуск

Нужны macOS 13+ и Xcode Command Line Tools.

```sh
make run
```

## Установка

Соберите установочный пакет командой:

```sh
make installer
```

Готовый `LiveWallpapers-Installer.pkg` появится в `.build`. Откройте его и пройдите шаги установщика. Приложение и служба воспроизведения будут установлены в `/Applications`. Пакет собирается для архитектуры Mac, на котором запущена команда `make installer`.

Пакет не подписан сертификатом Developer ID и не нотарифицирован Apple. На другом Mac Gatekeeper может запросить ручное подтверждение запуска; для распространения без такого предупреждения нужны сертификат Apple Developer и нотарификация.

Для удаления остановите воспроизведение и переместите приложение из `/Applications` в Корзину. Плейлисты остаются в `~/Library/Application Support/LiveMacOsWallpapers/Playlists`, пока вы не удалите эту папку отдельно.

Плейлисты хранятся в `~/Library/Application Support/LiveMacOsWallpapers/Playlists`. Видео копируются в папку плейлиста. Поддерживаются `.mov`, `.mp4` и `.m4v`.

## Структура проекта

```text
Resources/
  Info.plist
Sources/
  Shared/
    ServiceProtocol.swift
  WallpaperManager/
    App/
      main.swift
      AppDelegate.swift
    Models/
      WallpaperPlaylist.swift
    Services/
      Localization.swift
      PlaylistLibrary.swift
      VideoThumbnailProvider.swift
      WallpaperServiceRunner.swift
    UI/
      ActionRelay.swift
      HotkeyRecorderField.swift
      ManagerPageFactory.swift
      ManagerSidebarView.swift
      ManagerWindowController.swift
  WallpaperService/
    App/
      main.swift
      WallpaperPlaybackService.swift
    Desktop/
      DesktopWallpaperBackup.swift
    Input/
      GlobalHotkeyMonitor.swift
    Playback/
      WallpaperController.swift
```

`Shared` содержит протокол обмена между процессами. `WallpaperManager` отвечает за интерфейс, библиотеку и запуск службы. `WallpaperService` управляет воспроизведением, горячими клавишами и системным постером рабочего стола.

Язык интерфейса выбирается в боковой панели. Доступны русский и английский; первоначально используется язык macOS, а выбор сохраняется.

## Возможности

- Отдельные плейлисты с видеообложками.
- Импорт видео, изменение их порядка и удаление из плейлиста.
- Пустые состояния и сообщения об ошибках импорта и удаления.
- Три режима: следующее видео по окончании, повтор с переключением горячей клавишей, повтор с таймером.
- Настраиваемые сочетания клавиш для видео и переключения плейлистов.
- Команды воспроизведения и переключения плейлистов в строке меню macOS.
- Автозапуск при входе в систему и возобновление после пробуждения.
- Установка кадра видео как статичного постера рабочего стола.
