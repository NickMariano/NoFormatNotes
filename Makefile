# NoFormatNotes
#
# Builds without Xcode: only Command Line Tools are required.

APP_BUNDLE := build/NoFormatNotes.app

SIGN_ID     := $(shell security find-identity -v -p codesigning 2>/dev/null \
                 | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')
CODESIGN_ID := $(if $(SIGN_ID),$(SIGN_ID),-)
CODESIGN_OPTS := $(if $(SIGN_ID),--options runtime --timestamp,--timestamp=none)

.PHONY: all app icon dmg test run clean

all: app

app: $(APP_BUNDLE)

$(APP_BUNDLE): $(wildcard Sources/NoFormatNotesApp/*.swift) $(wildcard Sources/NoFormatNotesCore/*.swift) Resources/App-Info.plist $(wildcard Resources/NoFormatNotes.icns)
	@# Universal, so the app runs on Intel Macs too. Each slice is built separately and merged with
	@# lipo, because SwiftPM's --arch needs xcbuild from a full Xcode install.
	swift build -c release --product NoFormatNotesApp --scratch-path .build-arm64 \
		-Xswiftc -target -Xswiftc arm64-apple-macos15.0
	swift build -c release --product NoFormatNotesApp --scratch-path .build-x86_64 \
		-Xswiftc -target -Xswiftc x86_64-apple-macos15.0
	@mkdir -p build
	lipo -create -output build/NoFormatNotesApp-universal \
		.build-arm64/release/NoFormatNotesApp .build-x86_64/release/NoFormatNotesApp
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp Resources/App-Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp build/NoFormatNotesApp-universal $(APP_BUNDLE)/Contents/MacOS/NoFormatNotes
	@if [ -f Resources/NoFormatNotes.icns ]; then cp Resources/NoFormatNotes.icns $(APP_BUNDLE)/Contents/Resources/; \
	 else echo "note: no icon; app will use the generic one"; fi
	codesign --force --sign "$(CODESIGN_ID)" $(CODESIGN_OPTS) \
		--entitlements Resources/NoFormatNotes.entitlements $(APP_BUNDLE)
	@echo "signed with: $(CODESIGN_ID)"
	@echo "built $(APP_BUNDLE)"

# Regenerate the icon from a square PNG: make icon SRC=path/to/icon.png
icon:
	./Scripts/make-icon.sh $(SRC)

dmg: app
	./Scripts/make-dmg.sh

test:
	swift run NoFormatNotesTests

# Build and launch, replacing any running copy.
run: app
	@pkill -f "NoFormatNotes.app/Contents/MacOS/NoFormatNotes" 2>/dev/null || true
	@sleep 1
	open $(APP_BUNDLE)

clean:
	rm -rf build .build .build-arm64 .build-x86_64
