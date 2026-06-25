# agent.sh

`agent.sh` is a compatibility wrapper over `ctx agent` commands. It is not a
runtime, provider SDK, policy engine, scheduler, or chat database.

It only uses stable v1 paths:

```text
/ctx/agent/<agent>.sock
/ctx/agent/<agent>.d/
/ctx/home/<uid>/agent/<agent>/session/
/ctx/tool
/ctx/home/<uid>/tool
/ctx/shared
```

It does not use root namespaces such as `provider`, `format`, `cluster`,
`control`, `thread`, `workflow`, `mcp`, or `skill`.

## Usage

```bash
export CTX_ROOT=/ctx
export CTX_HOME="/ctx/home/$(id -u)"
export CTX_PATH="$CTX_ROOT/tool:$CTX_HOME/tool"

./agent.sh coder
./agent.sh coder "fix tests"
./agent.sh --chat coder
./agent.sh --session default coder
./agent.sh --resume coder
./agent.sh --history coder
./agent.sh --pack coder
./agent.sh --tools coder
./agent.sh --children coder
./agent.sh --cancel coder
```

With no prompt from an interactive TTY, `agent.sh AGENT` attaches to the agent
terminal through `ctx agent attach AGENT`, so the user sees `ctxterm -> tsh`.
With a prompt, it delegates to `ctx agent send AGENT`. Use
`agent.sh --chat AGENT` for the agent socket chat REPL.

When run from a CortexFS checkout, `agent.sh` prefers `../target/debug/ctx`
or `../target/release/ctx` before the `ctx` found on `PATH`. Set `CTX_BIN` to
force an exact ctx binary:

```bash
CTX_BIN=/path/to/ctx ./agent.sh coder
```

Socket requests are JSONL:

```jsonl
{"op":"send","id":"agent-sh-...","session":"default","scope":"private","cwd":"/work","input":"fix tests"}
{"op":"resume","session":"default"}
{"op":"cancel","id":"run-1"}
```

Responses are rendered by `ctx agent` as assistant text by default. Pass
`--raw` to print raw JSONL.

## Sessions

`agent.sh` never stores private history. It reads the v1 session tree:

```text
$CTX_HOME/agent/<agent>/session/index/current
$CTX_HOME/agent/<agent>/session/<session>/messages.jsonl
$CTX_HOME/agent/<agent>/session/<session>/events.jsonl
$CTX_HOME/agent/<agent>/session/<session>/latest.md
$CTX_HOME/agent/<agent>/session/<session>/context/
```

If no session is selected, `index/current` is used when present, otherwise
`default`.

Use `ctx agent output <agent>` to print the latest assistant output for the
selected session.

## Tools And Children

`--tools` lists executable files found through `CTX_PATH` and
`agent/<agent>.d/path`. It does not decide policy locally.

`--children` reads:

```text
$CTX_HOME/agent/<agent>/session/<session>/context/child/
```

The script is dependency-free in the project sense: no `jq`, Python, Node, npm,
Cargo, cloud SDK, provider client, or package manager. Linux `nc` with Unix
socket support is used for socket transport.
