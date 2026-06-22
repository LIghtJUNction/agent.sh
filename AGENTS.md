# AGENTS.md

- Keep `agent.sh` dependency-free: no `jq`, Python, Node, npm, Cargo, cloud SDK, provider client, or package manager.
- Keep `agent.sh` as a single file under 500 lines.
- Linux is the target runtime.
- Treat `agent.sh` as a v1 ABI frontend only, not as the CortexFS runtime.
- Do not add provider-specific API clients here.
- Do not use forbidden root ABI namespaces such as `provider`, `format`, `cluster`, `control`, `thread`, `workflow`, `mcp`, or `skill`.
- Interactive traffic must use `/ctx/agent/<agent>.sock`.
- Session reads must use `$CTX_HOME/agent/<agent>/session/<session>/`.
- Tool discovery must use `CTX_PATH` and ordinary executable tool files.
