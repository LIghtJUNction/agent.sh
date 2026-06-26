# AGENTS.md

- Keep `agent.sh` dependency-free: no `jq`, Python, Node, npm, Cargo, cloud SDK, provider client, or package manager.
- Keep `agent.sh` as a single file under 500 lines.
- Linux is the target runtime.
- Treat `agent.sh` as a small `ctx agent ...` default wrapper only, not as the CortexFS runtime.
- Do not add provider-specific API clients here.
- Do not use forbidden root ABI namespaces such as `provider`, `format`, `cluster`, `control`, `thread`, `workflow`, `mcp`, or `skill`.
- Interactive traffic, session reads, and tool discovery belong in Rust `ctx`, not in this shell wrapper.
