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

.PHONY: goldens goldens-check test
