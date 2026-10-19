# Regenerate the conformance goldens from the pinned upstream packages.
goldens:
	pnpm --dir Conformance install --frozen-lockfile
	pnpm --dir Conformance run generate

# Fail if any golden differs from what the pinned upstream packages produce.
goldens-check:
	pnpm --dir Conformance install --frozen-lockfile
	pnpm --dir Conformance run check

# Run every Swift test, including the conformance tests against the goldens.
test:
	swift test

# Run every Swift test on an iOS simulator. Override IOS_DESTINATION to pick another.
IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17
test-ios:
	xcodebuild test -scheme JSONRender-Package -destination '$(IOS_DESTINATION)' -quiet

.PHONY: goldens goldens-check test test-ios
