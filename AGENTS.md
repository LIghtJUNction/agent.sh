# AGENTS.md

- Keep `agent.sh` dependency-free. Do not require `jq`, Python, Node, npm, Cargo, or package managers.
- Keep `agent.sh` under 200 lines.
- Linux is the target runtime.
- Treat CortexFS as the execution plane and cluster scheduler.
- Do not add provider-specific API clients here.
- Use atomic rename into CortexFS inbox/pending directories.
- MCP support must stay stdio-based.
- Terminal execution is explicit through `terminal.run`; cluster task submission is explicit through `cluster.submit`.
