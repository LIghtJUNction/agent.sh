---
name: cortexfs-agent
description: Use when working on the dependency-free agent.sh CLI built on CortexFS for AI calls, MCP stdio, terminal execution, and cluster task submission.
version: 0.2.0
---

# cortexfs-agent

Rules:

- Keep `agent.sh` below 200 lines.
- Do not add dependencies.
- Do not bypass CortexFS for AI calls or cluster tasks.
- MCP stdio messages are JSON-RPC lines.
- Terminal execution must be explicit through `terminal.run`.
- Cluster work must be explicit through `cluster.submit`.

Test:

```bash
bash -n agent.sh
./agent.sh help
./agent.sh run 'printf "%s\n" ok'
printf '%s\n' '{"jsonrpc":"2.0","id":"1","method":"tools/list"}' | ./agent.sh mcp
```
