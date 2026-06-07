# AGENTS.md

- Keep `agent.sh` dependency-free. Do not require `jq`, Python, Node, npm, Cargo, or package managers.
- Keep `agent.sh` under 200 lines.
- Linux is the target runtime.
- Treat CortexFS as the execution plane. Do not add provider-specific API clients here.
- Use file submission by atomic rename into `$CTX_HOME/api/<format>/inbox/*.req.json`.
- MCP support must stay stdio-based and auditable by the caller.
- `terminal.run` is dangerous by nature; keep it explicit and do not hide command execution.
