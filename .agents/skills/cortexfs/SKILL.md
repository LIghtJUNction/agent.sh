---
name: cortexfs
description: This skill should be used when working on the dependency-free agent.sh CLI as a CortexFS frontend, including AI calls through the filesystem ABI, MCP stdio, and cluster task submission.
version: 0.2.0
---

# cortexfs

Core identity: this is CortexFS infrastructure exposed through a tiny shell agent. The skill is about the CortexFS ABI, not about terminal execution.

Rules:

- Keep `agent.sh` below 200 lines.
- Do not add dependencies.
- Treat CortexFS as the execution plane; do not bypass it for AI calls or cluster tasks.
- MCP stdio messages are JSON-RPC lines.
- Terminal execution is only one explicit MCP tool, `terminal.run`; do not let it define the project.
- Cluster work must be explicit through `cluster.submit`.

Test:

```bash
bash -n agent.sh
./agent.sh help
./agent.sh run 'printf "%s\n" ok'
printf '%s\n' '{"jsonrpc":"2.0","id":"1","method":"tools/list"}' | ./agent.sh mcp
```
