APP_BUNDLE = .build/LiveWallpapersManager.app
APP_EXECUTABLE = $(APP_BUNDLE)/Contents/MacOS/LiveWallpapersManager
MANAGER_SOURCES = $(shell find Sources/WallpaperManager -name '*.swift' -print | sort)
SERVICE_SOURCES = $(shell find Sources/WallpaperService -name '*.swift' -print | sort)
SHARED_SOURCES = $(shell find Sources/Shared -name '*.swift' -print | sort)
INFO_PLIST = Resources/Info.plist
APP_ICON = Resources/AppIcon.icns
VERSION = 0.1.0
ARCHITECTURE = $(shell uname -m)
PACKAGE_DIRECTORY = .build/packages
COMPONENT_PACKAGE = $(PACKAGE_DIRECTORY)/LiveWallpapersComponent.pkg
INSTALLER_PACKAGE = .build/LiveWallpapers-Installer.pkg
DISTRIBUTION = .build/Distribution.xml

.PHONY: all run installer clean

all: $(APP_EXECUTABLE)

$(APP_EXECUTABLE): $(SHARED_SOURCES) $(MANAGER_SOURCES) $(SERVICE_SOURCES) $(INFO_PLIST) $(APP_ICON)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Helpers
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	mkdir -p .build/ModuleCache
	swiftc -module-cache-path .build/ModuleCache -framework AppKit -framework AVKit -framework Carbon $(SHARED_SOURCES) $(SERVICE_SOURCES) -o $(APP_BUNDLE)/Contents/Helpers/WallpaperService
	swiftc -module-cache-path .build/ModuleCache -framework AppKit -framework AVFoundation -framework UniformTypeIdentifiers $(SHARED_SOURCES) $(MANAGER_SOURCES) -o $(APP_BUNDLE)/Contents/MacOS/LiveWallpapersManager
	cp $(INFO_PLIST) $(APP_BUNDLE)/Contents/Info.plist
	cp $(APP_ICON) $(APP_BUNDLE)/Contents/Resources/AppIcon.icns

run: all
	open $(APP_BUNDLE)

$(COMPONENT_PACKAGE): all
	mkdir -p $(PACKAGE_DIRECTORY)
	pkgbuild --component $(APP_BUNDLE) --install-location /Applications --identifier local.livemacoswallpapers.manager --version $(VERSION) $(COMPONENT_PACKAGE)

$(DISTRIBUTION): Packaging/Distribution.xml
	mkdir -p .build
	sed -e 's/@HOST_ARCHITECTURE@/$(ARCHITECTURE)/g' -e 's/@VERSION@/$(VERSION)/g' Packaging/Distribution.xml > $(DISTRIBUTION)

$(INSTALLER_PACKAGE): $(COMPONENT_PACKAGE) $(DISTRIBUTION) Packaging/Resources/welcome.html Packaging/Resources/conclusion.html
	productbuild --distribution $(DISTRIBUTION) --package-path $(PACKAGE_DIRECTORY) --resources Packaging/Resources $(INSTALLER_PACKAGE)

installer: $(INSTALLER_PACKAGE)

clean:
	rm -rf .build
