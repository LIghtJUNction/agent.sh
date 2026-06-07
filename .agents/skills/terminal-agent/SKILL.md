---
name: terminal-agent
description: Use when working on the dependency-free agent.sh CortexFS/MCP terminal agent.
version: 0.1.0
---

# terminal-agent

Rules:

- Keep `agent.sh` below 200 lines.
- Do not add dependencies.
- Do not bypass CortexFS for AI calls.
- MCP stdio messages are JSON-RPC lines.
- Terminal execution must be explicit through `terminal.run`.

Test:

```bash
bash -n agent.sh
./agent.sh help
./agent.sh run 'printf "%s\n" ok'
```
