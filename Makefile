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

.PHONY: android
android:
	$(MAKE) -C example android

.PHONY: ios
ios:
	$(MAKE) -C example ios

.PHONY: tui
tui:
	cd tools/push-secrets && go run .
