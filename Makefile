tmux:
	scripts/build-tmux.sh

run: tmux
	swift build -c release && \
	cp -f Resources/tmux .build/release/ 2>/dev/null || true && \
	cp -f Resources/forge-tmux.conf .build/release/ 2>/dev/null || true && \
	codesign --force --sign - .build/release/tmux 2>/dev/null || true && \
	open .build/release/Forge

dev:
	swift build && \
	cp -f Resources/tmux .build/debug/ 2>/dev/null || true && \
	cp -f Resources/forge-tmux.conf .build/debug/ 2>/dev/null || true && \
	codesign --force --sign - .build/debug/tmux 2>/dev/null || true && \
	open .build/debug/Forge

build:
	swift build -c release

clean:
	swift package clean
	rm -rf .tmux-build
