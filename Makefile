.PHONY: test test-static test-wake

test: test-static test-wake

test-static:
	./tests/installer-static.sh

test-wake:
	./tests/wake-helper.sh
