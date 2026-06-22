#!/usr/bin/env bash
set -euo pipefail

ROOT=$(mktemp -d)
BIN=$(cd "$(dirname "$0")" && pwd)/agent.sh
FAKE_BIN="$ROOT/bin"
CTX="$ROOT/ctx"
HOME_DIR="$CTX/home/1000"
SESSION_DIR="$HOME_DIR/agent/coder/session/default"

mkdir -p "$FAKE_BIN" "$CTX/agent" "$CTX/tool/fs.read.d" "$CTX/tool/shell.exec.d"
mkdir -p "$HOME_DIR/tool/project.test.d" "$SESSION_DIR/context/child/rev-1"
printf 'ready\n' >"$CTX/status"
printf '# latest\nok\n' >"$SESSION_DIR/latest.md"
printf '{"role":"user","content":"hello"}\n' >"$SESSION_DIR/messages.jsonl"
printf '{"type":"start","run":"run-1"}\n{"type":"done","run":"run-1","status":"ok"}\n' >"$SESSION_DIR/events.jsonl"
printf 'default\n' >"$HOME_DIR/agent/coder/session/index.current.tmp"
mkdir -p "$HOME_DIR/agent/coder/session/index"
mv "$HOME_DIR/agent/coder/session/index.current.tmp" "$HOME_DIR/agent/coder/session/index/current"
printf '# pack\nfacts\n' >"$SESSION_DIR/context/pack.md"
printf 'reviewer\n' >"$SESSION_DIR/context/child/rev-1/agent"
printf 'done\n' >"$SESSION_DIR/context/child/rev-1/status"
printf 'ready\n' >"$CTX/tool/fs.read.d/status"
printf 'denied EACCES\n' >"$CTX/tool/fs.read.d/log"
printf 'ready\n' >"$CTX/tool/shell.exec.d/status"
printf 'ready\n' >"$HOME_DIR/tool/project.test.d/status"
touch "$CTX/agent/coder" "$CTX/tool/fs.read" "$CTX/tool/shell.exec" "$HOME_DIR/tool/project.test"
chmod +x "$CTX/agent/coder" "$CTX/tool/fs.read" "$CTX/tool/shell.exec" "$HOME_DIR/tool/project.test"

cat >"$FAKE_BIN/nc" <<'EOF_NC'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NC_ARGS_FILE"
cat >>"$NC_STDIN_FILE"
printf '\n---\n' >>"$NC_STDIN_FILE"
case "$(cat "$NC_MODE_FILE" 2>/dev/null || printf send)" in
  resume) printf '{"type":"delta","text":"resumed"}\n{"type":"done","status":"ok"}\n' ;;
  cancel) printf '{"type":"done","status":"cancelled"}\n' ;;
  raw) printf '{"type":"delta","text":"raw-ok"}\n{"type":"done","status":"ok"}\n' ;;
  error) printf '{"type":"error","code":"EACCES","message":"permission denied"}\n{"type":"done","status":"error"}\n' ;;
  fail) exit 111 ;;
  *) printf '{"type":"start","run":"run-2"}\n{"type":"delta","text":"socket-ok"}\n{"type":"message","role":"assistant","text":"done"}\n{"type":"done","status":"ok"}\n' ;;
esac
EOF_NC
chmod +x "$FAKE_BIN/nc"

cleanup(){ rm -rf "$ROOT"; }
trap cleanup EXIT

assert_contains(){ case "$1" in *"$2"*) ;; *) printf 'missing %s in %s\n' "$2" "$1" >&2; exit 1 ;; esac; }
assert_not_contains(){ case "$1" in *"$2"*) printf 'unexpected %s in %s\n' "$2" "$1" >&2; exit 1 ;; *) ;; esac; }

bash -n "$BIN"

sock="$CTX/agent/coder.sock"
/usr/bin/nc -lU "$sock" >/dev/null 2>&1 &
listener=$!
for _ in 1 2 3 4 5; do [[ -S "$sock" ]] && break; sleep 0.1; done
kill "$listener" 2>/dev/null || true
[[ -S "$sock" ]] || { printf 'failed to create test socket\n' >&2; exit 1; }
chmod 666 "$sock"

export NC_ARGS_FILE="$ROOT/nc.args" NC_STDIN_FILE="$ROOT/nc.stdin" NC_MODE_FILE="$ROOT/nc.mode"

out=$(PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" coder "hello socket")
assert_contains "$out" 'socket-ok'
assert_contains "$(cat "$ROOT/nc.args")" "$CTX/agent/coder.sock"
stdin=$(cat "$ROOT/nc.stdin")
assert_contains "$stdin" '"op":"send"'
assert_contains "$stdin" '"session":"default"'
assert_contains "$stdin" '"input":"hello socket"'

printf 'fail\n' >"$ROOT/nc.mode"
if PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" coder "fail socket"; then
  printf 'send failure unexpectedly succeeded\n' >&2
  exit 1
fi
printf 'send\n' >"$ROOT/nc.mode"

: >"$ROOT/nc.stdin"
out=$(PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" --session focus coder "use focus")
assert_contains "$out" 'socket-ok'
assert_contains "$(cat "$ROOT/nc.stdin")" '"session":"focus"'

printf 'resume\n' >"$ROOT/nc.mode"
: >"$ROOT/nc.stdin"
out=$(PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" --resume coder)
assert_contains "$out" 'resumed'
assert_contains "$(cat "$ROOT/nc.stdin")" '"op":"resume"'

out=$(PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" --history coder)
assert_contains "$out" '"role":"user"'

out=$(PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" --latest coder)
assert_contains "$out" '# latest'

out=$(PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" --pack coder)
assert_contains "$out" '# pack'

out=$(PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" CTX_PATH="$CTX/tool:$HOME_DIR/tool" "$BIN" --tools coder)
assert_contains "$out" 'fs.read'
assert_contains "$out" 'project.test'
assert_not_contains "$out" 'coder'

out=$(PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" --children coder)
assert_contains "$out" 'rev-1'
assert_contains "$out" 'done'

printf 'cancel\n' >"$ROOT/nc.mode"
: >"$ROOT/nc.stdin"
PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" --cancel coder >/dev/null
assert_contains "$(cat "$ROOT/nc.stdin")" '"op":"cancel"'
assert_contains "$(cat "$ROOT/nc.stdin")" '"id":"run-1"'

printf 'raw\n' >"$ROOT/nc.mode"
out=$(PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" --raw coder raw)
assert_contains "$out" '"type":"delta"'

printf 'send\n' >"$ROOT/nc.mode"
: >"$ROOT/nc.stdin"
printf 'one\n\n/two\n/status\n/exit\n' | PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" coder >/dev/null 2>/dev/null || true
assert_contains "$(cat "$ROOT/nc.stdin")" '"input":"one"'
assert_not_contains "$(cat "$ROOT/nc.stdin")" '"input":"/status"'

out=$(PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" --status coder)
assert_contains "$out" 'agent=coder'
assert_contains "$out" 'session=default'

out=$(PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" CTX_PATH="$CTX/tool" "$BIN" --tool-log coder fs.read)
assert_contains "$out" 'EACCES'

printf 'agent.sh tests passed\n'
