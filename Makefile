# Silt — build automation
#
# Local dev is unsigned (`make build`). Distribution builds sign with the
# Developer ID Application identity for team $(TEAM_ID) — found in the login
# keychain — then optionally notarize.
#
# One-time setup for `make notarize`:
#   xcrun notarytool store-credentials $(NOTARY_PROFILE) \
#     --apple-id you@example.com --team-id $(TEAM_ID)

APP        := Silt
SCHEME     := Silt
TESTSCHEME := SiltTests
PROJECT    := $(APP).xcodeproj
DERIVED    := build
RELEASE    := $(DERIVED)/Build/Products/Release
DIST       := dist

# Signing — override on the command line if ever needed:
#   make signed TEAM_ID=XXXXXXXXXX
TEAM_ID        ?= N762FB52VL
IDENTITY       ?= Developer ID Application
NOTARY_PROFILE ?= silt-notary

VERSION := $(shell grep -m1 'MARKETING_VERSION' project.yml | awk '{print $$2}' | tr -d '"')
DMG     := $(DIST)/$(APP)-$(VERSION).dmg

.PHONY: all generate build run test signed verify dmg notarize staple release docs icon clean help

all: build

help: ## List targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

$(PROJECT): project.yml
	xcodegen generate

generate: ## Regenerate Silt.xcodeproj from project.yml
	xcodegen generate

build: $(PROJECT) ## Unsigned Release build (local dev)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
	           -derivedDataPath $(DERIVED) build

run: build ## Build and launch
	open $(RELEASE)/$(APP).app

test: $(PROJECT) ## Run the test suite
	xcodebuild -project $(PROJECT) -scheme $(TESTSCHEME) -configuration Debug \
	           -derivedDataPath $(DERIVED) test

signed: $(PROJECT) ## Developer ID build: signed + hardened runtime (notarization-ready)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
	           -derivedDataPath $(DERIVED) build \
	           DEVELOPMENT_TEAM=$(TEAM_ID) \
	           CODE_SIGN_IDENTITY="$(IDENTITY)" \
	           CODE_SIGN_STYLE=Manual \
	           ENABLE_HARDENED_RUNTIME=YES \
	           OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime"
	$(MAKE) verify

verify: ## Check the signature on the built app
	codesign --verify --deep --strict --verbose=2 $(RELEASE)/$(APP).app
	codesign -dv $(RELEASE)/$(APP).app 2>&1 | grep -E 'Authority|TeamIdentifier|flags'

dmg: signed ## Signed .dmg in dist/
	mkdir -p $(DIST)
	rm -f $(DMG)
	hdiutil create -volname $(APP) -srcfolder $(RELEASE)/$(APP).app -ov -format UDZO $(DMG)
	codesign --sign "$(IDENTITY)" --timestamp $(DMG)
	@echo "→ $(DMG)"

notarize: dmg ## Submit the dmg to Apple and wait (needs stored credentials, see header)
	xcrun notarytool submit $(DMG) --keychain-profile $(NOTARY_PROFILE) --wait
	$(MAKE) staple

staple: ## Staple the notarization ticket
	xcrun stapler staple $(DMG)
	xcrun stapler validate $(DMG)

release: notarize ## Full distribution pipeline: sign → dmg → notarize → staple
	@echo "Done: $(DMG) is signed, notarized and stapled."

docs: ## Regenerate docs/catalog.md from Catalog.swift
	swiftc -O -o /tmp/silt-dumpcat Sources/$(APP)/Models/CleanTarget.swift \
	  Sources/$(APP)/Models/Catalog.swift docs/tools/dump-catalog/main.swift
	/tmp/silt-dumpcat > docs/catalog.md
	@echo "→ docs/catalog.md"

icon: ## Regenerate app icon PNGs from Icon/appicon-source.png
	swift Icon/generate-appicon.swift Icon/appicon-source.png /tmp/silt-icons
	@echo "→ /tmp/silt-icons — copy into Sources/$(APP)/Assets.xcassets/AppIcon.appiconset/ per Contents.json"

clean: ## Remove build products and the generated project
	rm -rf $(DERIVED) $(DIST) $(PROJECT)
