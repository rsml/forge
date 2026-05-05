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

run: tmux icon
	swift build -c release && \
	cp -f Resources/tmux .build/release/ 2>/dev/null || true && \
	cp -f Resources/forge-tmux.conf .build/release/ 2>/dev/null || true && \
	cp -f Resources/AppIcon.icns .build/release/ 2>/dev/null || true && \
	cp -f Assets/appicon-transparent.png .build/release/ 2>/dev/null || true && \
	codesign --force --sign - .build/release/tmux 2>/dev/null || true && \
	open .build/release/Forge

dev: icon
	swift build && \
	cp -f Resources/tmux .build/debug/ 2>/dev/null || true && \
	cp -f Resources/forge-tmux.conf .build/debug/ 2>/dev/null || true && \
	cp -f Resources/AppIcon.icns .build/debug/ 2>/dev/null || true && \
	cp -f Assets/appicon-transparent.png .build/debug/ 2>/dev/null || true && \
	codesign --force --sign - .build/debug/tmux 2>/dev/null || true && \
	open .build/debug/Forge

build:
	swift build -c release

clean:
	swift package clean
	rm -rf .tmux-build
