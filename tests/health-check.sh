#!/usr/bin/env bash
set -euo pipefail

checker="$(cd "$(dirname "$0")/.." >/dev/null && pwd)/system_files/usr/libexec/bazzite-sunshine/health-check"
fixture=$(mktemp -d)
trap 'find "$fixture" -depth -delete' EXIT
mkdir -p "$fixture/bin"
export LOG="$fixture/sunshine.log" STATE_DIR="$fixture/state"
export CALLS="$fixture/calls" PROBES="$fixture/probes"
export PATH="$fixture/bin:$PATH" CURL=curl SYSTEMCTL=systemctl
export ACTIVE=1 CURL_EXIT=28 CONNECT_DURING_PROBE=0
export ENTERED=0

cat > "$fixture/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ $1 == --user ]]
case $2 in
    is-active) [[ $ACTIVE == 1 ]] ;;
    show)
        echo "$ENTERED"
        ;;
    restart)
        [[ $3 == app-dev.lizardbyte.app.Sunshine.service ]]
        echo restart >> "$CALLS"
        ;;
    *) exit 1 ;;
esac
STUB
cat > "$fixture/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ $* == '-sk --max-time 5 -o /dev/null https://127.0.0.1:47984/serverinfo' ]]
echo probe >> "$PROBES"
if [[ $CONNECT_DURING_PROBE == 1 ]]; then
    echo 'CLIENT CONNECTED' >> "$LOG"
fi
exit "$CURL_EXIT"
STUB
chmod +x "$fixture/bin/"*

reset_case() {
    if [[ -d $STATE_DIR ]]; then
        find "$STATE_DIR" -depth -delete
    fi
    : > "$LOG"
    : > "$CALLS"
    : > "$PROBES"
    ACTIVE=1
    CURL_EXIT=28
    CONNECT_DURING_PROBE=0
    read -r uptime _ < /proc/uptime
    ENTERED=$(( (${uptime%%.*} - 180) * 1000000 ))
}

check() {
    timeout 10 bash "$checker" > "$fixture/output"
}

assert_lines() {
    local actual
    actual=$(wc -l < "$1")
    if [[ $actual != "$2" ]]; then
        echo "FAIL: $1 expected $2 lines, got $actual" >&2
        exit 1
    fi
}

reset_case
ACTIVE=0
check
assert_lines "$PROBES" 0
assert_lines "$CALLS" 0
echo 'PASS: inactive unit does nothing'

reset_case
ENTERED=$(( (${uptime%%.*} - 60) * 1000000 ))
check
assert_lines "$PROBES" 0
assert_lines "$CALLS" 0
echo 'PASS: active less than 120 seconds does nothing'

reset_case
printf 'CLIENT CONNECTED\nCLIENT CONNECTED\nCLIENT DISCONNECTED\n' > "$LOG"
for _ in {1..4}; do check; done
assert_lines "$PROBES" 0
assert_lines "$CALLS" 0
echo 'PASS: live stream prevents probes and restarts'

for failed in 7 28; do
    reset_case
    CURL_EXIT=$failed
    check
    check
    assert_lines "$CALLS" 0
    echo "PASS: two failed probes (exit $CURL_EXIT) do not restart"
    check
    assert_lines "$CALLS" 1
    [[ ! -f $STATE_DIR/failures ]]
    echo "PASS: three failed probes (exit $CURL_EXIT) restart exactly once"
done

for healthy in 0 35 56; do
    reset_case
    check
    check
    CURL_EXIT=$healthy
    check
    CURL_EXIT=28
    check
    check
    assert_lines "$CALLS" 0
    check
    assert_lines "$CALLS" 1
    echo "PASS: healthy exit $healthy resets consecutive failures"
done

reset_case
for _ in {1..12}; do check; done
assert_lines "$CALLS" 3
grep -q rate-limited "$fixture/output"
echo 'PASS: fourth restart within one hour is rate-limited'
printf '%s\n' "$(( ${uptime%%.*} - 3601 ))" > "$STATE_DIR/restarts"
check
assert_lines "$CALLS" 4
echo 'PASS: expired restarts leave the rolling window'

reset_case
check
check
CONNECT_DURING_PROBE=1
check
assert_lines "$CALLS" 0
echo 'PASS: connection during probe prevents restart'

reset_case
check
check
ENTERED=$((ENTERED - 1))
check
assert_lines "$CALLS" 0
echo 'PASS: a new activation resets consecutive failures'
