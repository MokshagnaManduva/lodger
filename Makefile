PACK ?= Packs/klien
PY   ?= python3

.PHONY: help validate validate-dev test audit sketches engine engine-test app-test build-fixture klien-idle klien-animations klien-test looks norn-animations norn-pack norn-test norn-energy soak proof bench app archive run separation release-check release-test sign notarize appcast all

help:
	@echo "make validate      strict pack validation (release gate)"
	@echo "make validate-dev  validation with missing art as warnings"
	@echo "make test          negative tests proving each lint check fires"
	@echo "make sketches      palette + tracing sketches from the raw reference"
	@echo "make klien-idle    rebuild the archived approved idle artwork"
	@echo "make klien-animations build all Klien scenarios and animation previews"
	@echo "make looks         render every selectable look of both characters to build/"
	@echo "make klien-test    check Klien artwork and Director behaviour, including Settings controls"
	@echo "make norn-animations build Norn's local runtime pack and clip preview"
	@echo "make norn-pack     export Norn without source sheets or gallery files"
	@echo "make norn-test     check Norn artwork, masks and Director transitions"
	@echo "make norn-energy   sequential visible idle/read/sleep CPU diagnostics (about 21 min)"
	@echo "make engine        build the engine (debug)"
	@echo "make engine-test   engine self-tests (no Xcode needed)"
	@echo "make build-fixture packtool build over the synthetic source pack"
	@echo "make soak          100s CPU soak per state, release build"
	@echo "make bench         per-mouse-move hit test cost"
	@echo "make app           assemble build/Lodger.app (no Xcode needed)"
	@echo "make separation    enforce engine/pack and CI boundary checks"
	@echo "make release-check validate the app bundle and release metadata"
	@echo "make sign          Developer ID sign an app (IDENTITY=... required)"
	@echo "make archive       zip the already-signed app for distribution"
	@echo "make notarize      submit, staple and rearchive (NOTARY_PROFILE required)"
	@echo "make appcast       generate a Sparkle appcast entry (URL/SIGNATURE required)"
	@echo "make run           build and launch the app"
	@echo "make proof         SIGSTOP proof that animation is render-server resident"
	@echo "make audit         re-measure the raw reference art"
	@echo "                   override the pack with PACK=Packs/other"

validate:
	$(PY) Tools/packtool/packtool.py validate $(PACK)

validate-dev:
	$(PY) Tools/packtool/packtool.py validate $(PACK) --no-assets

test:
	$(PY) Scripts/embed-pack-schema.py --check
	$(PY) Tools/packtool/test_packtool.py
	$(PY) Tools/packtool/test_controls.py
	$(PY) Tools/packtool/test_klien_idle.py
	$(PY) Tools/packtool/test_klien_scenarios.py
	$(PY) Tools/packtool/test_norn.py
	$(PY) Tools/packtool/packtool.py validate Tests/Fixtures/test.solidsquare --no-assets

klien-idle:
	$(PY) Tools/packtool/build_klien_idle.py
	$(PY) Tools/packtool/packtool.py validate Packs/klien
	$(PY) Tools/packtool/test_klien_idle.py

REF ?= Packs/klien/reference/klien.png

klien-animations:
	$(PY) Tools/packtool/animate_klien.py --install
	$(PY) Tools/packtool/packtool.py validate Packs/klien
	$(PY) Tools/packtool/test_klien_idle.py
	$(PY) Tools/packtool/test_klien_scenarios.py

# Every selectable look of the bundled characters, for art review.
looks:
	$(PY) Tools/packtool/looks.py Packs/klien build/looks-klien.png
	$(PY) Tools/packtool/looks.py Packs/Norn build/looks-norn.png

klien-test:
	$(PY) Tools/packtool/test_klien_idle.py
	$(PY) Tools/packtool/test_klien_scenarios.py
	@mkdir -p build/klien-verification
	swiftc Engine/Sources/LodgerEngine/Pack.swift Engine/Sources/LodgerEngine/Guard.swift Engine/Sources/LodgerEngine/Director.swift Tools/packtool/test_klien_director.swift -o build/klien-verification/test-director
	./build/klien-verification/test-director Packs/klien/pack.json

norn-animations:
	$(PY) Tools/packtool/build_norn.py
	$(PY) Tools/packtool/test_norn.py

norn-pack: norn-animations
	$(PY) Tools/packtool/packtool.py build Packs/Norn --out build/Norn.pack

norn-test:
	$(PY) Tools/packtool/test_norn.py
	@mkdir -p build/norn-verification
	swiftc Engine/Sources/LodgerEngine/Pack.swift Engine/Sources/LodgerEngine/Guard.swift Engine/Sources/LodgerEngine/Director.swift Tools/packtool/test_norn_director.swift -o build/norn-verification/test-director
	./build/norn-verification/test-director Packs/Norn/pack.json

# Diagnostic defaults. One protocol-length idle sample:
# make norn-energy ENERGY_SECONDS=3600 ENERGY_RUNS=1 ENERGY_STATES=idle
# This measures the Pet CLI host, not the menu/settings shell or system power.
ENERGY_SECONDS ?= 120
ENERGY_RUNS ?= 3
ENERGY_STATES ?= idle reading asleep
ENERGY_OUT ?= build/norn-energy-$(shell date +%Y%m%d-%H%M%S)
norn-energy:
	cd Engine && swift build -c release
	$(PY) Tools/packtool/measure_energy.py --seconds $(ENERGY_SECONDS) --runs $(ENERGY_RUNS) \
		--states $(ENERGY_STATES) --out $(ENERGY_OUT)

sketches:
	$(PY) Tools/packtool/packtool.py palette $(REF) --colors 26
	@for c in r0c0 r0c1 r0c2 r1c0 r1c1 r1c2; do \
		$(PY) Tools/packtool/packtool.py pixelize $(REF) --cell $$c | tail -2; \
	done
	$(PY) Tools/packtool/packtool.py pixelize $(REF) --cell r1c0 --component 1 \
		--height 22 --cell-size 32 --ground 26 --out Packs/klien/reference/sketches/item | tail -1

audit:
	$(PY) Tools/packtool/audit_reference.py Packs/klien/reference/klien.png
	$(PY) Tools/packtool/audit_cells.py     Packs/klien/reference/klien.png

engine:
	cd Engine && swift build

engine-test: build-fixture
	$(PY) Scripts/embed-pack-schema.py --check
	cd Engine && swift build
	./Engine/.build/debug/lodger-selftest

app-test:
	cd Engine && swift build
	bash Scripts/check-app.sh

build-fixture:
	$(PY) Tools/packtool/make_fixtures.py
	$(PY) Tools/packtool/packtool.py build Tests/Fixtures/src.socketed \
		--out Tests/Fixtures/build/socketed.pack

# Repeated runs, median reported. A single soak measures the machine's mood: our
# process uses 20-40 ms of CPU per minute, and outliers of 15x show up on any
# configuration. See Docs/energy-protocol.md.
RUNS ?= 5
SECS ?= 60

soak:
	cd Engine && swift build -c release
	@for pk in Tests/Fixtures/test.blinker Tests/Fixtures/build/socketed.pack; do \
		printf '%-38s ' "$$(basename $$pk)"; \
		for i in $$(seq 1 $(RUNS)); do \
			./Engine/.build/release/lodger --pack $$pk --soak $(SECS) 2>&1 \
			| awk '/projected/ {printf "%s ", $$2}'; \
		done; echo "s/hr  ($(RUNS) runs of $(SECS)s)"; \
	done

# Characters shipped inside the app; the first is the first-run default.
BUNDLED_PACKS ?= Packs/klien Packs/Norn
export BUNDLED_PACKS

app:
	./Scripts/bundle.sh

separation:
	./Scripts/check-separation.sh

release-test:
	$(PY) Scripts/test_release.py
	@mkdir -p build
	swiftc Engine/Sources/lodger/UpdateFeed.swift Tests/UpdateFeedChecks.swift -o build/update-feed-checks
	./build/update-feed-checks

release-check: app separation validate
	@test -f Assets/Branding/lodger-icon.png
	@test -f build/Lodger.app/Contents/Resources/AppIcon.icns
	$(PY) Scripts/bundle-pack.py check build/Lodger.app $(BUNDLED_PACKS)
	@for pack in build/Lodger.app/Contents/Resources/Packs/*/; do \
		./build/Lodger.app/Contents/MacOS/Lodger --pack "$$pack" --headless >/dev/null \
			|| { echo "bundled pack does not load: $$pack"; exit 1; }; \
	done
	@echo "release checks passed; distribution signing and notarization remain credentialed steps"

IDENTITY ?=
sign:
	@test -n "$(IDENTITY)" || (echo "set IDENTITY='Developer ID Application: ...'"; exit 2)
	@test -d build/Lodger.app || $(MAKE) app
	codesign --force --options runtime --timestamp --sign "$(IDENTITY)" build/Lodger.app

archive:
	$(PY) Scripts/release.py archive

NOTARY_PROFILE ?=
export NOTARY_PROFILE
notarize:
	$(PY) Scripts/release.py notarize

APPCAST_VERSION ?= $(shell tr -d '\n' < VERSION)
APPCAST_URL ?=
APPCAST_SIGNATURE ?=
APPCAST_PUBLIC_KEY ?=
appcast:
	@test -n "$(APPCAST_URL)" || (echo "set APPCAST_URL=https://.../Lodger.zip"; exit 2)
	@test -n "$(APPCAST_SIGNATURE)" || (echo "set APPCAST_SIGNATURE='Sparkle EdDSA signature'"; exit 2)
	@test -n "$(APPCAST_PUBLIC_KEY)" || (echo "set APPCAST_PUBLIC_KEY='base64 public key'"; exit 2)
	$(PY) Scripts/build-appcast.py build/Lodger.zip --version "$(APPCAST_VERSION)" --url "$(APPCAST_URL)" --signature "$(APPCAST_SIGNATURE)" --public-key "$(APPCAST_PUBLIC_KEY)"

run: app
	./build/Lodger.app/Contents/MacOS/Lodger

bench:
	cd Engine && swift build -c release
	./Engine/.build/release/lodger-selftest --bench

proof:
	@echo "needs Screen Recording permission; see Docs/energy-protocol.md"
	cd Engine && swift build -c release

all: test engine-test validate-dev
