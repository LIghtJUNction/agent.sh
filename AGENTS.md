# AGENTS.md

- Keep `agent.sh` dependency-free. Do not require `jq`, Python, Node, npm, Cargo, or package managers.
- Keep `agent.sh` as a single file under 500 lines.
- Linux is the target runtime.
- Treat CortexFS as the execution plane and cluster scheduler.
- Do not add provider-specific API clients here.
- Use `$CTX_HOME/thread/<session>/io.sock` for interactive chat, default REPL traffic, and MCP `thread.send`.
- Use atomic rename into CortexFS inbox/pending directories only for explicit non-interactive submissions such as `ask`, `submit`, `cluster-submit`, `tool`, `read`, and `run`.
- MCP support must stay stdio-based.
- Terminal execution is explicit through `terminal.run`; cluster task submission is explicit through `cluster.submit`.
