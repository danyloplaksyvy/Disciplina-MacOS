#!/bin/bash
# Wrap the xcodebuild invocation containing the external full-screen test.
set -eu
key_dir=$(mktemp -d)
driver_pid=""
cleanup() {
    if [ -n "$driver_pid" ]; then
        kill "$driver_pid" 2>/dev/null || true
        wait "$driver_pid" 2>/dev/null || true
    fi
    rm -rf "$key_dir"
}
trap cleanup EXIT
xcrun swiftc "$(dirname "$0")/full-screen-test-keys.swift" -o "$key_dir/keys"
"$key_dir/keys" "$key_dir" &
driver_pid=$!
for ((i=0; i<150; i++)); do
    [ -f "$key_dir/ready" ] && break
    kill -0 "$driver_pid" || exit 1
    sleep 0.1
done
test -f "$key_dir/ready"
export TEST_RUNNER_DISCIPLINA_UI_KEY_DIR="$key_dir"
"$@"
