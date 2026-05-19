tmux:
	scripts/build-tmux.sh

icon: Resources/AppIcon.icns

Resources/AppIcon.icns: Assets/appicon.icon/icon.json Assets/appicon.icon/Assets/*
	mkdir -p /tmp/forge-icon-build && \
	xcrun actool Assets/appicon.icon --app-icon appicon \
		--compile /tmp/forge-icon-build \
		--output-partial-info-plist /dev/null \
		--minimum-deployment-target 14.0 --platform macosx --target-device mac && \
	mv /tmp/forge-icon-build/appicon.icns Resources/AppIcon.icns && \
	rm -rf /tmp/forge-icon-build

ghosttykit:
	PATH="/opt/homebrew/opt/zig@0.15/bin:$$PATH" scripts/build-ghosttykit.sh

# All external dependencies (GhosttyKit, tmux, icon).
# swift build handles SPM targets (Forge, forged, ForgeCore).
prerequisites: ghosttykit tmux icon

run: prerequisites
	swift build -c release && \
	$(MAKE) bundle BUILD=.build/release && \
	open .build/release/Forge.app

dev: prerequisites
	swift build && \
	$(MAKE) bundle BUILD=.build/debug && \
	open .build/debug/Forge.app

bundle:
	@rm -rf $(BUILD)/Forge.app
	@mkdir -p $(BUILD)/Forge.app/Contents/MacOS
	@mkdir -p $(BUILD)/Forge.app/Contents/Resources
	@cp $(BUILD)/Forge $(BUILD)/Forge.app/Contents/MacOS/Forge
	@cp $(BUILD)/forged $(BUILD)/Forge.app/Contents/MacOS/forged
	@cp Resources/Info.plist $(BUILD)/Forge.app/Contents/
	@cp -f Resources/tmux $(BUILD)/Forge.app/Contents/MacOS/ 2>/dev/null || true
	@cp -f Resources/forge-tmux.conf $(BUILD)/Forge.app/Contents/Resources/ 2>/dev/null || true
	@cp -f Resources/AppIcon.icns $(BUILD)/Forge.app/Contents/Resources/ 2>/dev/null || true
	@cp -f Assets/appicon-transparent.png $(BUILD)/Forge.app/Contents/Resources/ 2>/dev/null || true
	@mkdir -p $(BUILD)/Forge.app/Contents/Resources/themes
	@cp -R Resources/themes/. $(BUILD)/Forge.app/Contents/Resources/themes/
	@codesign --force --sign - $(BUILD)/Forge.app/Contents/MacOS/tmux 2>/dev/null || true
	@codesign --force --sign - $(BUILD)/Forge.app/Contents/MacOS/forged
	@codesign --force --sign - $(BUILD)/Forge.app

build: prerequisites
	swift build -c release

clean:
	swift package clean
	rm -rf .tmux-build

test:
	swift test

restart:
	@killall Forge 2>/dev/null || true
	@$(MAKE) dev

logs:
	tail -f /tmp/forge.log

.PHONY: tmux icon ghosttykit prerequisites run dev bundle build clean test restart logs
