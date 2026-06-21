# agent.sh

`agent.sh` is a tiny Linux shell agent CLI built around the CortexFS ABI.
It stays deliberately small: no `jq`, Python, Node, npm, Cargo, cloud SDK, or package manager dependency.

The script talks to CortexFS by atomic `rename` into `inbox/*.req.json`; CortexFS owns routing, policy, audit, execution, memory, cluster scheduling, and export.

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
./agent.sh submit '{"task":"inspect","target":"README.md"}'
./agent.sh cluster-submit '{"task":"summarize","input":"cluster visible"}'
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

## CortexFS ABI paths

Primary file submissions:

```text
$CTX_HOME/api/<format>/inbox/<id>.req.json
$CTX_HOME/thread/<thread>/inbox/<id>.req.json
$CTX_ROOT/agent/<agent>/inbox/<id>.req.json
$CTX_ROOT/cluster/<cluster>/queue/<queue>/pending/<id>.req.json
$CTX_ROOT/tool/<tool-id>/invoke/inbox/<id>.req.json
```

Conversational thread traffic uses the realtime socket fast path:

```text
$CTX_HOME/thread/<thread>/io.sock
```

`ask` is a one-shot API submission. `chat` and `thread` send JSONL to `io.sock`
and expect the daemon/listener to stream accepted/delta/message/done events.
They do not fall back to `thread/<thread>/inbox`; if the listener is not running,
the command reports the socket failure.

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
