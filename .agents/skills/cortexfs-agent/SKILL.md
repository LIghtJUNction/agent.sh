---
name: cortexfs-agent
description: This skill should be used when working on the dependency-free agent.sh CLI whose core is CortexFS: AI calls, MCP stdio, and cluster task submission all go through the filesystem ABI.
version: 0.2.0
---

# cortexfs-agent

Core identity: this is a CortexFS agent front end, not a terminal-agent skill.

Rules:

- Keep `agent.sh` below 200 lines.
- Do not add dependencies.
- Treat CortexFS as the execution plane; do not bypass it for AI calls or cluster tasks.
- MCP stdio messages are JSON-RPC lines.
- Terminal execution is only one explicit MCP tool: `terminal.run`.
- Cluster work must be explicit through `cluster.submit`.

Test:

```bash
bash -n agent.sh
./agent.sh help
./agent.sh run 'printf "%s\n" ok'
printf '%s\n' '{"jsonrpc":"2.0","id":"1","method":"tools/list"}' | ./agent.sh mcp
```
