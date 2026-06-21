#!/usr/bin/env bash
set -euo pipefail

ROOT=$(mktemp -d)
BIN=$(cd "$(dirname "$0")" && pwd)/agent.sh
FAKE_BIN="$ROOT/bin"
CTX="$ROOT/ctx"
HOME_DIR="$CTX/home/1000"
mkdir -p "$FAKE_BIN" "$HOME_DIR/route/openai.chat" "$HOME_DIR/thread/demo" "$CTX/control"
mkdir -p "$CTX/provider/p1/enabled" "$CTX/provider/p1/secrets" "$CTX/provider/p1/health" "$CTX/provider/p1/model"
mkdir -p "$CTX/tool/filesystem.read/invoke/inbox" "$CTX/tool/filesystem.read/invoke/outbox"
mkdir -p "$CTX/tool/shell.exec/invoke/inbox" "$CTX/tool/shell.exec/invoke/outbox"
mkdir -p "$CTX/agent/helper/inbox" "$CTX/agent/helper/outbox" "$CTX/cluster/local/queue/default/pending"
printf 'ready\n' >"$CTX/status"
printf '0\n' >"$CTX/control/queue_depth"
printf 'none\n' >"$CTX/control/last_drained"
printf 'p1\n' >"$HOME_DIR/route/default_provider"
printf 'p1\n' >"$HOME_DIR/route/openai.chat/provider"
printf 'm1\n' >"$HOME_DIR/route/openai.chat/model"
printf 'ready\n' >"$HOME_DIR/route/openai.chat/reason"
printf 'p1\n' >"$CTX/provider/list"
printf 'Provider One\n' >"$CTX/provider/p1/name"
printf 'openai-compatible\n' >"$CTX/provider/p1/family"
printf 'openai.chat\n' >"$CTX/provider/p1/format"
printf 'https://example.invalid/\n' >"$CTX/provider/p1/url.effective"
mkdir -p "$CTX/provider/p1/url"
printf 'https://example.invalid/\n' >"$CTX/provider/p1/url/effective"
printf '1\n' >"$CTX/provider/p1/enabled/effective"
printf 'configured\n' >"$CTX/provider/p1/secrets/status"
printf 'ready\n' >"$CTX/provider/p1/health/status"
printf 'm1\n' >"$CTX/provider/p1/model/list"
printf 'demo\tworkspace\t\t\n' >"$HOME_DIR/thread/list"

cat >"$FAKE_BIN/nc" <<'EOF_NC'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$NC_ARGS_FILE"
cat >"$NC_STDIN_FILE"
printf '{"type":"accepted","request_id":"t1"}\n{"type":"delta","content":"socket-ok"}\n{"type":"message","role":"assistant","content":"socket-ok"}\n{"type":"done","request_id":"t1"}\n'
EOF_NC
chmod +x "$FAKE_BIN/nc"

cleanup(){ rm -rf "$ROOT"; }
trap cleanup EXIT

assert_contains(){ case "$1" in *"$2"*) ;; *) printf 'missing %s in %s\n' "$2" "$1" >&2; exit 1 ;; esac; }

bash -n "$BIN"

out=$(CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" status)
assert_contains "$out" "route_reason=ready"

out=$(CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" doctor)
assert_contains "$out" "ready=1"

sock="$HOME_DIR/thread/demo/io.sock"
/usr/bin/nc -lU "$sock" >/dev/null 2>&1 &
listener=$!
for _ in 1 2 3 4 5; do [[ -S "$sock" ]] && break; sleep 0.1; done
kill "$listener" 2>/dev/null || true
[[ -S "$sock" ]] || { printf 'failed to create test socket\n' >&2; exit 1; }
chmod 666 "$sock"
NC_ARGS_FILE="$ROOT/nc.args" NC_STDIN_FILE="$ROOT/nc.stdin" PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" chat demo "hello socket"
assert_contains "$(cat "$ROOT/nc.args")" "$HOME_DIR/thread/demo/io.sock"
assert_contains "$(cat "$ROOT/nc.stdin")" '"op":"send"'
assert_contains "$(cat "$ROOT/nc.stdin")" 'hello socket'

out=$(NC_ARGS_FILE="$ROOT/chat-default.args" NC_STDIN_FILE="$ROOT/chat-default.stdin" PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" chat "default thread prompt")
assert_contains "$out" 'socket-ok'
case "$out" in *'"type":"accepted"'*) printf 'chat leaked raw socket events\n' >&2; exit 1 ;; esac
assert_contains "$(cat "$ROOT/chat-default.args")" "$HOME_DIR/thread/demo/io.sock"
assert_contains "$(cat "$ROOT/chat-default.stdin")" 'default thread prompt'
assert_contains "$(cat "$ROOT/chat-default.stdin")" '"session":"cwd-'

out=$(CORTEX_RAW_EVENTS=1 NC_ARGS_FILE="$ROOT/chat-raw.args" NC_STDIN_FILE="$ROOT/chat-raw.stdin" PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" chat "raw prompt")
assert_contains "$out" '"type":"accepted"'
case "$(cat "$ROOT/chat-raw.stdin")" in *'"history"'*) printf 'chat sent local history instead of CortexFS-native session id\n' >&2; exit 1 ;; esac

printf 'cwd-cortexfs-123\tworkspace\tunix:1\t/tmp/cortexfs\n' >"$HOME_DIR/thread/list"
out=$(CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" sessions)
assert_contains "$out" 'cwd-'
out=$(printf '/new focused\n/sessions\n/resume focused\n/temp\n/share team\n/exit\n' | PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN")
assert_contains "$out" 'session=focused'
assert_contains "$out" 'scope=temp'
assert_contains "$out" 'shared-team'

printf 'default repl\n/exit\n' | NC_ARGS_FILE="$ROOT/default.args" NC_STDIN_FILE="$ROOT/default.stdin" PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" >/dev/null
assert_contains "$(cat "$ROOT/default.stdin")" 'default repl'

printf 'socket one\n\nsocket two\n' | NC_ARGS_FILE="$ROOT/repl.args" NC_STDIN_FILE="$ROOT/repl.stdin" PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" repl demo >/dev/null
assert_contains "$(cat "$ROOT/repl.stdin")" 'socket two'

out=$(printf '/status\n/exit\n' | NC_ARGS_FILE="$ROOT/cmd.args" NC_STDIN_FILE="$ROOT/cmd.stdin" PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN")
assert_contains "$out" 'route_reason=ready'
[[ ! -e "$ROOT/cmd.stdin" ]] || { printf 'slash command unexpectedly used socket\n' >&2; exit 1; }

mv "$sock" "$sock.off"
out=$(printf 'will fail\n/status\n/exit\n' | PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" 2>/dev/null)
assert_contains "$out" 'route_reason=ready'
mv "$sock.off" "$sock"

printf '{"ok":true}\n' >"$CTX/tool/filesystem.read/invoke/outbox/read-1.resp.json"
out=$(CORTEX_REQUEST_ID=read-1 CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" read status)
assert_contains "$out" '"ok":true'
assert_contains "$(cat "$CTX/tool/filesystem.read/invoke/inbox/read-1.req.json")" '"path":"status"'

printf '{"status":"queued"}\n' >"$CTX/tool/shell.exec/invoke/outbox/run-1.resp.json"
out=$(CORTEX_REQUEST_ID=run-1 CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" run "echo hi")
assert_contains "$out" '"status":"queued"'
assert_contains "$(cat "$CTX/tool/shell.exec/invoke/inbox/run-1.req.json")" '"command":"echo hi"'

printf '{"status":"done"}\n' >"$CTX/agent/helper/outbox/task-1.resp.json"
out=$(CORTEX_REQUEST_ID=task-1 CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" submit inspect)
assert_contains "$out" '"status":"done"'
assert_contains "$(cat "$CTX/agent/helper/inbox/task-1.req.json")" '"task":"inspect"'

out=$(CORTEX_REQUEST_ID=cluster-1 CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" cluster-submit summarize)
assert_contains "$out" 'cluster-1'
assert_contains "$(cat "$CTX/cluster/local/queue/default/pending/cluster-1.req.json")" '"task":"summarize"'

out=$(printf '{"jsonrpc":"2.0","id":1,"method":"tools/list"}\n' | CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" mcp)
assert_contains "$out" "thread.send"
assert_contains "$out" "terminal.run"

printf '{"mcp":true}\n' >"$CTX/tool/filesystem.read/invoke/outbox/mcp-read.resp.json"
out=$(printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"filesystem.read","arguments":{"path":"status"}}}\n' | CORTEX_REQUEST_ID=mcp-read CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" mcp)
assert_contains "$out" '"isError":false'
assert_contains "$out" '\"mcp\":true'
assert_contains "$(cat "$CTX/tool/filesystem.read/invoke/inbox/mcp-read.req.json")" '"path":"status"'

printf '{"mcp":"run"}\n' >"$CTX/tool/shell.exec/invoke/outbox/mcp-run.resp.json"
out=$(printf '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"terminal.run","arguments":{"command":"pwd"}}}\n' | CORTEX_REQUEST_ID=mcp-run CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" mcp)
assert_contains "$out" '"isError":false'
assert_contains "$out" '\"mcp\":\"run\"'
assert_contains "$(cat "$CTX/tool/shell.exec/invoke/inbox/mcp-run.req.json")" '"command":"pwd"'

out=$(printf '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"thread.send","arguments":{"thread":"demo","prompt":"mcp socket"}}}\n' | NC_ARGS_FILE="$ROOT/mcp-thread.args" NC_STDIN_FILE="$ROOT/mcp-thread.stdin" PATH="$FAKE_BIN:$PATH" CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" mcp)
assert_contains "$out" '"isError":false'
assert_contains "$(cat "$ROOT/mcp-thread.stdin")" 'mcp socket'

out=$(CTX_ROOT="$CTX" CTX_HOME="$HOME_DIR" "$BIN" mcp-config)
assert_contains "$out" '"cortex-agent"'
assert_contains "$out" '"args":["mcp"]'

printf 'agent.sh tests passed\n'
