.PHONY: pigeon
pigeon:
	dart run pigeon --input pigeon/layrz_push.dart

.PHONY: lint
lint:
	dart fix --dry-run

.PHONY: test
test:
	flutter test

.PHONY: clean
clean:
	flutter clean
	cd example && flutter clean
	flutter pub get

.PHONY: run
run:
	$(MAKE) -C example run

.PHONY: tui
tui:
	cd tools/push-secrets && go run .

.PHONY: send
send:
	cd tools/push-sender && go run .

# Local lint tooling — pinned to the same versions CI uses (.tools is gitignored)
KTLINT_VERSION := 1.4.1
SWIFTLINT_VERSION := 0.57.0
TOOLS_DIR := .tools

.PHONY: install-tools
install-tools:
	mkdir -p $(TOOLS_DIR)
	curl -sL https://github.com/pinterest/ktlint/releases/download/$(KTLINT_VERSION)/ktlint -o $(TOOLS_DIR)/ktlint
	chmod +x $(TOOLS_DIR)/ktlint

# Mirrors the exact CI lint invocations (checks.yaml / layrz-actions)
.PHONY: lint-kotlin
lint-kotlin:
	cd android && ../$(TOOLS_DIR)/ktlint "**/src/**/*.kt" "!**/*.g.kt" --reporter=plain

# SwiftLint's linux binary needs a Swift toolchain (sourcekit), so it runs
# in the official container instead — same pinned version as CI.
.PHONY: lint-swift
lint-swift:
	podman run --rm -v $(CURDIR):/repo:z -w /repo ghcr.io/realm/swiftlint:$(SWIFTLINT_VERSION) swiftlint lint --strict --force-exclude ios/layrz_push/Sources

# Autocorrect what the linters can fix themselves
.PHONY: format
format:
	cd android && ../$(TOOLS_DIR)/ktlint "**/src/**/*.kt" "!**/*.g.kt" --format
	podman run --rm -v $(CURDIR):/repo:z -w /repo ghcr.io/realm/swiftlint:$(SWIFTLINT_VERSION) swiftlint lint --fix --force-exclude ios/layrz_push/Sources || true

# Run everything CI runs (except the macOS xcodebuild tests) before pushing
.PHONY: checks
checks: lint-kotlin lint-swift
	flutter analyze
	flutter test
