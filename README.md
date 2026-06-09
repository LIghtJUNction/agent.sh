# agent.sh

`agent.sh` is a tiny Linux shell agent CLI built around the CortexFS ABI.
It stays deliberately small: no `jq`, Python, Node, npm, Cargo, cloud SDK, or package manager dependency.

The script talks to CortexFS by atomic `rename` into `inbox/*.req.json`; CortexFS owns routing, policy, audit, execution, memory, cluster scheduling, and export.

## Usage

```bash
export CTX_ROOT=/ctx
export CTX_HOME="/ctx/home/$(id -u)"

./agent.sh status
./agent.sh models
./agent.sh route
./agent.sh ask "Reply with cortexfs-ok"
./agent.sh thread demo "continue"
./agent.sh submit '{"task":"inspect","target":"README.md"}'
./agent.sh cluster-submit '{"task":"summarize","input":"cluster visible"}'
./agent.sh cluster
./agent.sh tool filesystem.read /status
./agent.sh drain 1
./agent.sh mcp
```

## CortexFS ABI paths

Primary file submissions:

```text
$CTX_HOME/api/<format>/inbox/<id>.req.json
$CTX_HOME/thread/<thread>/inbox/<id>.req.json
$CTX_ROOT/agent/<agent>/inbox/<id>.req.json
$CTX_ROOT/cluster/<cluster>/queue/<queue>/pending/<id>.req.json
$CTX_ROOT/tool/<tool-id>/invoke/inbox/<id>.req.json
```

Observed runtime views:

```text
$CTX_HOME/model/{count,list,refresh}
$CTX_HOME/route/<format>/{provider,model,reason}
$CTX_ROOT/agent/<agent>/runtime/{state,pid,heartbeat,current_thread,current_task}
$CTX_ROOT/control/{drain,queue_depth,last_drained}
```

`agent.sh` does not choose a provider or special-case any local model. Provider/model routing remains CortexFS policy.
