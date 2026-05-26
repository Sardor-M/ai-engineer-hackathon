# DesktopCat — convenience targets.
#
#   make build       — debug swift build
#   make release     — release build
#   make run         — debug build + launch
#   make bundle      — wrap the release binary in a proper .app at build/DesktopCat.app
#                      with a stable bundle id so TCC permissions persist
#   make open-bundle — run the bundled .app (use this once you need
#                      Accessibility / Screen Recording grants to stick)
#   make clean

APP_NAME    := DesktopCat
BUNDLE_ID   := com.amelia.desktopcat
RELEASE_DIR := .build/release
APP_BUNDLE  := build/$(APP_NAME).app
RES_BUNDLE  := $(RELEASE_DIR)/$(APP_NAME)_$(APP_NAME).bundle

.PHONY: build release run bundle open-bundle clean

build:
	swift build

release:
	swift build -c release

run:
	swift run

bundle: release
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(RELEASE_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@if [ -d "$(RES_BUNDLE)" ]; then \
		cp -R $(RES_BUNDLE) $(APP_BUNDLE)/Contents/MacOS/ ; \
	fi
	@printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'  <key>CFBundleIdentifier</key><string>$(BUNDLE_ID)</string>' \
		'  <key>CFBundleName</key><string>$(APP_NAME)</string>' \
		'  <key>CFBundleExecutable</key><string>$(APP_NAME)</string>' \
		'  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>' \
		'  <key>CFBundlePackageType</key><string>APPL</string>' \
		'  <key>CFBundleShortVersionString</key><string>0.2.0</string>' \
		'  <key>CFBundleVersion</key><string>1</string>' \
		'  <key>LSMinimumSystemVersion</key><string>13.0</string>' \
		'  <key>LSUIElement</key><true/>' \
		'  <key>NSAppleEventsUsageDescription</key>' \
		'  <string>The cat reads what is in front of you (Mail messages, frontmost app) so she can offer relevant help.</string>' \
		'</dict>' \
		'</plist>' \
		> $(APP_BUNDLE)/Contents/Info.plist
	@echo "→ bundled $(APP_BUNDLE)"

open-bundle: bundle
	@open $(APP_BUNDLE)

clean:
	rm -rf .build build
