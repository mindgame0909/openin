APP       := OpenIn
BUNDLE_ID := com.personal.openin
BUILD     := .build/release
BUNDLE    := $(BUILD)/$(APP).app
MACOS     := $(BUNDLE)/Contents/MacOS
RESOURCES := $(BUNDLE)/Contents/Resources
SOURCES   := $(wildcard Sources/*.swift)
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
ICON_VARIANT ?= 1

.PHONY: all build icon icons install run dist clean

# ── Default ──────────────────────────────────────────────────────────────────
all: build

# ── Icon (generated from compass_source.png) ────────────────────────────────
icon: Resources/AppIcon.icns

Resources/AppIcon.icns: Scripts/make_icon_from_png.swift Resources/compass_source.png
	@echo "► Generating icon from compass PNG…"
	@swift Scripts/make_icon_from_png.swift Resources/compass_source.png /tmp/$(APP).iconset
	@iconutil -c icns /tmp/$(APP).iconset -o Resources/AppIcon.icns
	@rm -rf /tmp/$(APP).iconset
	@echo "✓ Resources/AppIcon.icns"

# ── Preview all icon variants ─────────────────────────────────────────────────
icons:
	@echo "► Generating icon previews…"
	@mkdir -p .build/icon-previews
	@for v in 1 2 3 4 5; do \
		swift Scripts/make_icon.swift /tmp/icon-preview-$$v $$v 2>/dev/null; \
		cp /tmp/icon-preview-$$v/icon_256x256.png .build/icon-previews/variant-$$v.png; \
		rm -rf /tmp/icon-preview-$$v; \
	done
	@echo "✓ Previews saved to .build/icon-previews/"
	@open .build/icon-previews/

# ── Build ─────────────────────────────────────────────────────────────────────
build: $(BUNDLE)

$(BUNDLE): $(SOURCES) Resources/Info.plist Resources/AppIcon.icns
	@mkdir -p "$(MACOS)" "$(RESOURCES)"
	@echo "► Compiling $(APP)…"
	swiftc \
		-O \
		-framework Cocoa \
		-framework Carbon \
		-module-name $(APP) \
		$(SOURCES) \
		-o "$(MACOS)/$(APP)"
	@cp Resources/Info.plist   "$(BUNDLE)/Contents/Info.plist"
	@cp Resources/AppIcon.icns "$(RESOURCES)/AppIcon.icns"
	@echo "► Ad-hoc signing…"
	codesign --force --deep --sign - "$(BUNDLE)"
	@echo "✓ Built: $(BUNDLE)"

# ── Install ───────────────────────────────────────────────────────────────────
install: build
	@echo "► Installing to /Applications/…"
	@rm -rf "/Applications/$(APP).app"
	@cp -r "$(BUNDLE)" /Applications/
	@xattr -cr "/Applications/$(APP).app"
	@echo "► Registering with LaunchServices…"
	@$(LSREGISTER) -f -R -trusted "/Applications/$(APP).app"
	@echo "✓ Installed /Applications/$(APP).app"
	@echo ""
	@echo "  Next: System Settings → Desktop & Dock → Default web browser → OpenIn"

# ── Run ───────────────────────────────────────────────────────────────────────
run: build
	@pkill $(APP) 2>/dev/null; sleep 0.5; open "$(BUNDLE)"

# ── Distributable DMG (drag-to-install layout) ───────────────────────────────
dist: build
	@echo "► Creating distributable DMG…"
	@rm -rf /tmp/$(APP)_dmg_stage && mkdir /tmp/$(APP)_dmg_stage
	@cp -r "$(BUNDLE)" /tmp/$(APP)_dmg_stage/
	@ln -s /Applications /tmp/$(APP)_dmg_stage/Applications
	@rm -f $(APP).dmg
	@hdiutil create \
		-volname "$(APP)" \
		-srcfolder /tmp/$(APP)_dmg_stage \
		-ov -format UDZO \
		$(APP).dmg
	@rm -rf /tmp/$(APP)_dmg_stage
	@echo "✓ $(APP).dmg — drag OpenIn → Applications to install"
	@echo ""
	@echo "  To publish an update:"
	@echo "  1. Bump CFBundleShortVersionString in Resources/Info.plist"
	@echo "  2. Run: make dist"
	@echo "  3. Upload $(APP).dmg to GitHub Releases"
	@echo "  4. Update latest.json with new version + URL and push to main branch"

# ── Clean ─────────────────────────────────────────────────────────────────────
clean:
	@rm -rf .build $(APP).dmg
	@echo "✓ Cleaned"
