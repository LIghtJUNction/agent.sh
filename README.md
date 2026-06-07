# agent.sh

`agent.sh` is a tiny Linux shell agent built for CortexFS.

It has two jobs:

- submit prompts to a CortexFS API inbox using the normal file ABI;
- expose a minimal MCP stdio server with one terminal tool: `terminal.run`.

No runtime dependencies are required beyond POSIX userland plus Bash. It does not require `jq`, Python, Node, npm, Cargo, or a cloud SDK.

## Usage

Set CortexFS home:

```bash
export CTX_HOME="/ctx/home/$(id -u)"
```

Submit one prompt through CortexFS:

```bash
./agent.sh ask "Reply with cortexfs-ok"
```

Run as an MCP stdio server:

```bash
./agent.sh mcp
```

Call a terminal command directly:

```bash
./agent.sh run 'printf "%s\n" hello'
```

## CortexFS Contract

`agent.sh ask` writes a temporary request and atomically renames it into:

```text
$CTX_HOME/api/openai.chat/inbox/<id>.req.json
```

It then asks CortexFS to drain if `/ctx/control/drain` exists and prints:

```text
$CTX_HOME/api/openai.chat/outbox/<id>.resp.json
```

The script intentionally does not know provider IDs, model IDs, secrets, or routes. CortexFS owns routing, policy, audit, execution, and export.
