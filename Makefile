PACK ?= Packs/klien
PY   ?= python3

.PHONY: help validate validate-dev test audit sketches engine engine-test build-fixture soak proof bench app run all

help:
	@echo "make validate      strict pack validation (release gate)"
	@echo "make validate-dev  validation with missing art as warnings"
	@echo "make test          negative tests proving each lint check fires"
	@echo "make sketches      palette + tracing sketches from the raw reference"
	@echo "make engine        build the engine (debug)"
	@echo "make engine-test   engine self-tests (no Xcode needed)"
	@echo "make build-fixture packtool build over the synthetic source pack"
	@echo "make soak          100s CPU soak per state, release build"
	@echo "make bench         per-mouse-move hit test cost"
	@echo "make app           assemble build/Lodger.app (no Xcode needed)"
	@echo "make run           build and launch the app"
	@echo "make proof         SIGSTOP proof that animation is render-server resident"
	@echo "make audit         re-measure the raw reference art"
	@echo "                   override the pack with PACK=Packs/other"

validate:
	$(PY) Tools/packtool/packtool.py validate $(PACK)

validate-dev:
	$(PY) Tools/packtool/packtool.py validate $(PACK) --no-assets

test:
	$(PY) Tools/packtool/test_packtool.py
	$(PY) Tools/packtool/packtool.py validate Tests/Fixtures/test.solidsquare --no-assets

REF ?= Packs/klien/reference/klien.png

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
	cd Engine && swift build
	./Engine/.build/debug/lodger-selftest

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

app:
	./Scripts/bundle.sh

run: app
	./build/Lodger.app/Contents/MacOS/Lodger

bench:
	cd Engine && swift build -c release
	./Engine/.build/release/lodger-selftest --bench

proof:
	@echo "needs Screen Recording permission; see Docs/energy-protocol.md"
	cd Engine && swift build -c release

all: test engine-test validate-dev
