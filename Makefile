run:
	swift build -c release && open .build/release/Forge

dev:
	swift build && open .build/debug/Forge

build:
	swift build -c release
