# agent.sh

`agent.sh` is a tiny Linux shell frontend for the CortexFS v1 agent ABI. It is
not a runtime, provider SDK, policy engine, scheduler, or chat database.

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
./agent.sh --session default coder
./agent.sh --resume coder
./agent.sh --history coder
./agent.sh --latest coder
./agent.sh --pack coder
./agent.sh --tools coder
./agent.sh --children coder
./agent.sh --cancel coder
```

With no prompt, `agent.sh AGENT` reads lines from stdin or an interactive TTY
and sends each non-empty line to `/ctx/agent/<agent>.sock`.

Socket requests are JSONL:

```jsonl
{"op":"send","id":"agent-sh-...","session":"default","scope":"private","cwd":"/work","input":"fix tests"}
{"op":"resume","session":"default"}
{"op":"cancel","id":"run-1"}
```

Responses are rendered as assistant text by default. Set `CORTEX_RAW_EVENTS=1`
or pass `--raw` to print raw JSONL.

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
