# agent.sh

`agent.sh` is a tiny Linux shell agent CLI built around the CortexFS ABI.
It stays deliberately small: no `jq`, Python, Node, npm, Cargo, cloud SDK, or package manager dependency.

Interactive agent traffic uses CortexFS thread sockets. Running `./agent.sh`,
`chat`, `thread`, `repl`, and MCP `thread.send` write JSONL to
`$CTX_HOME/thread/<session>/io.sock` and render streamed events as human text.

Atomic `rename` into `inbox/*.req.json` is kept only for non-interactive file
ABI commands such as `ask`, explicit `submit`, `cluster-submit`, `tool`, `read`,
and `run`.

## Usage

```bash
export CTX_ROOT=/ctx
export CTX_HOME="/ctx/home/$(id -u)"

./agent.sh
./agent.sh status
./agent.sh models
./agent.sh route
./agent.sh ask "Reply with cortexfs-ok"
./agent.sh chat demo "continue"
./agent.sh thread demo "continue"
./agent.sh repl demo
./agent.sh sessions
./agent.sh resume cwd-cortexfs-123
./agent.sh new focused
./agent.sh temp
./agent.sh share team
./agent.sh cluster
./agent.sh read home/1000/thread/demo/messages.jsonl
./agent.sh run 'echo explicit terminal request'
./agent.sh tool filesystem.read /status
./agent.sh drain 1
./agent.sh mcp
./agent.sh mcp-config
```

`mcp` exposes a stdio MCP server with Claude Code-style explicit tools:
`thread.send`, `filesystem.read`, `terminal.run`, `agent.submit`,
`cluster.submit`, `cortex.ask`, and `cortex.status`.
Use `mcp-config` to print a JSON snippet for registering this server.

## Interactive Socket Path

Conversational thread traffic uses the realtime socket fast path:

```text
$CTX_HOME/thread/<session>/io.sock
```

`chat` and `thread` send one JSON object to the socket:

```json
{"op":"send","session":"cwd-cortexfs-123","scope":"workspace","cwd":"/work/cortexfs","message":{"role":"user","content":"continue"}}
```

The listener streams JSONL events:

```jsonl
{"type":"accepted","request_id":"thread-cwd-cortexfs-123-000001"}
{"type":"delta","content":"..."}
{"type":"message","role":"assistant","content":"..."}
{"type":"done","request_id":"thread-cwd-cortexfs-123-000001"}
```

`agent.sh` renders these events as plain assistant text by default. Set
`CORTEX_RAW_EVENTS=1` only when another program needs the raw JSONL stream.

Socket traffic is still CortexFS-owned: the runtime validates peer credentials,
uses the configured route/provider policy, appends `messages.jsonl`, updates
`latest.md`, `state`, `fingerprint`, and writes audit facts.

## Sessions And Resume

The default session is derived from the current working directory:

```text
cwd-<directory-name>-<path-hash>
```

Sessions are CortexFS threads. `agent.sh` does not keep a private chat history.
It reads and resumes sessions through the native CortexFS thread view:

```text
$CTX_HOME/thread/list
$CTX_HOME/thread/current
$CTX_HOME/thread/<session>/messages.jsonl
$CTX_HOME/thread/<session>/latest.md
```

List available sessions:

```bash
./agent.sh sessions
```

Resume one by id:

```bash
./agent.sh resume cwd-cortexfs-123
```

Inside the interactive REPL:

```text
/sessions
/resume cwd-cortexfs-123
/new focused
/temp
/share team
```

`/new <id>` creates a private persistent session, `/share <id>` creates a
shared persistent session, and `/temp` creates an ephemeral session that is not
restored after remount. Persistent sessions are restored by CortexFS on the next
mount, then shown again by `sessions` and `/sessions`.

## File ABI Paths

These commands intentionally use file submissions because they are not
interactive chat turns:

```text
$CTX_HOME/api/<format>/inbox/<id>.req.json
$CTX_ROOT/agent/<agent>/inbox/<id>.req.json
$CTX_ROOT/cluster/<cluster>/queue/<queue>/pending/<id>.req.json
$CTX_ROOT/tool/<tool-id>/invoke/inbox/<id>.req.json
```

`ask` is a one-shot API submission. `submit` targets `agent/<agent>/inbox`.
`cluster-submit` enqueues background work. They are explicit lower-level ABI
commands and are not part of the default chat experience.

`repl` reads prompts from stdin and sends each non-empty line through the same
thread socket.

Running `./agent.sh` with no arguments starts the same interactive socket
session. Slash commands are handled locally:

```text
/status
/doctor
/providers
/models
/route
/sessions
/resume <session>
/new <session>
/temp
/share <session>
/read <path>
/run <command>
/ask <prompt>
/exit
```

Observed runtime views:

```text
$CTX_HOME/model/{count,list,refresh}
$CTX_HOME/route/<format>/{provider,model,reason}
$CTX_ROOT/agent/<agent>/runtime/{state,pid,heartbeat,current_thread,current_task}
$CTX_ROOT/control/{drain,queue_depth,last_drained}
```

`agent.sh` does not choose a provider or special-case any local model. Provider/model routing remains CortexFS policy.

The main script is intentionally kept under 500 lines.
