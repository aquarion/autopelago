#!/bin/bash
# Tests certbot-renew-group.sh with a fake certbot.
# Run from the repo root: roles/certbot/tests/renew-group.sh [path/to/certbot-renew-group.sh]
helper=${1:-roles/certbot/files/certbot-renew-group.sh}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/certbot" <<'EOF'
#!/bin/sh
echo "$*" >>"$FAKE_CERTBOT_LOG"
while [ $# -gt 0 ]; do
	if [ "$1" = "--cert-name" ] && [ "$2" = "fail.example" ]; then
		exit 1
	fi
	shift
done
exit 0
EOF
chmod +x "$tmp/certbot"

failures=0

# run_case NAME EXPECTED_RC CERT...
run_case() {
	local name=$1 want_rc=$2 rc rc_class want_class cert expected=""
	shift 2
	: >"$tmp/log"
	CERTBOT="$tmp/certbot" FAKE_CERTBOT_LOG="$tmp/log" "$helper" "$@"
	rc=$?
	for cert in "$@"; do
		expected+="renew --quiet --no-random-sleep-on-renew --cert-name $cert"$'\n'
	done
	[ "$rc" -ne 0 ] && rc_class=nonzero || rc_class=0
	[ "$want_rc" -ne 0 ] && want_class=nonzero || want_class=0
	if [ "$(cat "$tmp/log")"$'\n' = "$expected" ] && [ "$rc_class" = "$want_class" ]; then
		echo "PASS: $name"
	else
		echo "FAIL: $name (rc=$rc, want rc $want_rc)"
		echo "expected invocations:"
		printf '%s' "$expected"
		echo "actual invocations:"
		cat "$tmp/log"
		failures=1
	fi
}

run_case "continues after a failure and exits non-zero" 1 a.example fail.example c.example
run_case "all succeed and exit zero" 0 a.example b.example

exit "$failures"
