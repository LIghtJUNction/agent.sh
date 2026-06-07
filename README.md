# agent.sh

`agent.sh` is a tiny Linux shell agent CLI built around the CortexFS ABI.

It stays deliberately small:

- no `jq`, Python, Node, npm, Cargo, cloud SDK, or package manager dependency;
- AI calls go through the CortexFS file ABI;
- cluster work goes through the CortexFS cluster queue ABI;
- MCP stdio exposes CortexFS-facing tools.

## Usage

```bash
export CTX_ROOT=/ctx
export CTX_HOME="/ctx/home/$(id -u)"

./agent.sh ask "Reply with cortexfs-ok"
./agent.sh submit '{"task":"inspect","target":"README.md"}'
./agent.sh cluster
./agent.sh drain
./agent.sh run 'printf "%s\n" hello'
./agent.sh mcp
```

## CortexFS ABI

Prompt submission:

```text
$CTX_HOME/api/openai.chat/inbox/<id>.req.json
```

Cluster task submission:

```text
$CTX_ROOT/cluster/local/queue/default/pending/<id>.req.json
```

Cluster state:

```text
$CTX_ROOT/cluster/local/state
$CTX_ROOT/cluster/local/queue/default/{pending,running,done,failed}
```

CortexFS owns routing, policy, audit, execution, memory, cluster scheduling, and export. `agent.sh` is only a tiny Unix front end for that ABI. Terminal execution is one explicit MCP tool, not the identity of the project. The bundled project skill is named `cortexfs` for the same reason.
