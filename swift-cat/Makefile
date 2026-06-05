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
	@# Single source of truth: the same Info.plist the executable embeds via
	@# the linker (see Package.swift) becomes the bundle's Contents/Info.plist.
	@cp Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@echo "→ bundled $(APP_BUNDLE)"

open-bundle: bundle
	@open $(APP_BUNDLE)

clean:
	rm -rf .build build
