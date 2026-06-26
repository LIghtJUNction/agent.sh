#!/usr/bin/env bash
set -euo pipefail

ROOT=$(mktemp -d)
BIN=$(cd "$(dirname "$0")" && pwd)/agent.sh
FAKE_CTX="$ROOT/ctx"
LOG="$ROOT/ctx.log"

cleanup(){ rm -rf "$ROOT"; }
trap cleanup EXIT

assert_contains(){ case "$1" in *"$2"*) ;; *) printf 'missing %s in %s\n' "$2" "$1" >&2; exit 1 ;; esac; }
last_call(){ tail -n 1 "$LOG"; }

cat >"$FAKE_CTX" <<'EOF_CTX'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$CTX_FAKE_LOG"
case "$*" in
  "agent send coder --session default hello socket") printf 'sent\n' ;;
  "agent send coder --session default help") printf 'help sent\n' ;;
  "agent send coder --session focus use focus") printf 'sent focus\n' ;;
  "agent attach coder --session default") printf 'tsh>\n' ;;
  *) printf 'unexpected ctx args: %s\n' "$*" >&2; exit 64 ;;
esac
EOF_CTX
chmod +x "$FAKE_CTX"

bash -n "$BIN"

export CTX_BIN="$FAKE_CTX"
export CTX_FAKE_LOG="$LOG"
: >"$LOG"

out=$("$BIN" coder "hello socket")
assert_contains "$out" 'sent'
assert_contains "$(last_call)" 'agent send coder --session default hello socket'

out=$("$BIN" coder help)
assert_contains "$out" 'help sent'
assert_contains "$(last_call)" 'agent send coder --session default help'

out=$("$BIN" --session focus coder "use focus")
assert_contains "$out" 'sent focus'
assert_contains "$(last_call)" 'agent send coder --session focus use focus'

out=$("$BIN" --attach coder)
assert_contains "$out" 'tsh>'
assert_contains "$(last_call)" 'agent attach coder --session default'

help=$("$BIN" --help)
assert_contains "$help" 'usage'
