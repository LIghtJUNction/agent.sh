#!/usr/bin/env bash
set -euo pipefail

VERSION=0.3.0
FORMAT=${CORTEX_FORMAT:-openai.chat}
CTX_ROOT=${CTX_ROOT:-/ctx}
CTX_HOME=${CTX_HOME:-$CTX_ROOT/home/$(id -u)}
AGENT=${CORTEX_AGENT:-helper}
THREAD=${CORTEX_THREAD:-demo}
CLUSTER=${CORTEX_CLUSTER:-local}
QUEUE=${CORTEX_QUEUE:-default}
MAX_DRAINS=${CORTEX_DRAIN_STEPS:-8}

err(){ printf 'agent.sh: %s\n' "$*" >&2; }
die(){ err "$*"; exit 1; }
usage(){ cat <<'EOF_USAGE'
agent.sh - tiny CortexFS agent CLI

usage:
  agent.sh status
  agent.sh models
  agent.sh route
  agent.sh ask <prompt>
  agent.sh thread [thread-id] <prompt>
  agent.sh submit <json-or-text>        # agent/<agent>/inbox
  agent.sh cluster-submit <json-or-text>
  agent.sh cluster
  agent.sh tool <tool-id> <json-or-text>
  agent.sh drain [steps]
  agent.sh mcp
  agent.sh help
EOF_USAGE
}
json_escape(){
  local s=${1-}
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\t'/\\t}
  printf '%s' "$s"
}
json_get_string(){ local key=$1 line=$2 rest val; rest=${line#*\"$key\"}; [[ $rest != "$line" ]] || return 1; rest=${rest#*:}; rest=${rest#*\"}; val=${rest%%\"*}; printf '%s' "$val"; }
json_id(){ local line=$1 rest val; rest=${line#*\"id\"}; [[ $rest != "$line" ]] || { printf 'null'; return; }; rest=${rest#*:}; rest=${rest#${rest%%[![:space:]]*}}; if [[ $rest == \"* ]]; then val=${rest#\"}; printf '"%s"' "${val%%\"*}"; else val=${rest%%,*}; val=${val%%\}*}; printf '%s' "${val//[[:space:]]/}"; fi; }
request_id(){ printf 'agent-%s-%s' "$$" "$(date +%s%N 2>/dev/null || date +%s)"; }
read_text(){ [[ -r $1 ]] && cat "$1" || true; }
show_file(){ [[ -r $2 ]] && printf '%s=%s\n' "$1" "$(cat "$2")" || true; }
body_from_args(){ local body=$*; case "$body" in \{*|\[* ) printf '%s\n' "$body" ;; *) printf '{"task":"%s"}\n' "$(json_escape "$body")" ;; esac; }
chat_body(){ printf '{"messages":[{"role":"user","content":"%s"}]}\n' "$(json_escape "$*")"; }

submit_raw(){
  local dir=$1 id=$2 body=$3 inbox tmp req
  inbox="$dir/inbox"; [[ -d "$inbox" ]] || inbox="$dir"
  [[ -d "$inbox" ]] || die "missing submission directory: $dir"
  tmp="$inbox/$id.tmp"; req="$inbox/$id.req.json"
  printf '%s' "$body" >"$tmp"; mv "$tmp" "$req"
}
drain_once(){ [[ -w "$CTX_ROOT/control/drain" ]] || die "missing writable control: $CTX_ROOT/control/drain"; printf '1\n' >"$CTX_ROOT/control/drain"; }
drain_steps(){ local n=${1:-1} i=0; while (( i<n )); do drain_once; i=$((i+1)); done; }
queue_depth(){ local q="$CTX_ROOT/control/queue_depth"; [[ -r $q ]] && tr -d '\n' <"$q" || printf '?'; }
wait_file(){
  local ok=$1 errfile=${2:-} i=0
  while (( i<=MAX_DRAINS )); do
    [[ -r "$ok" ]] && { cat "$ok"; return 0; }
    [[ -n $errfile && -r "$errfile" ]] && { cat "$errfile" >&2; return 1; }
    (( i==MAX_DRAINS )) && break
    drain_once; i=$((i+1))
  done
  die "response not ready: $ok"
}

status(){
  printf 'version=%s\nroot=%s\nhome=%s\nformat=%s\nagent=%s\nthread=%s\nqueue_depth=%s\n' "$VERSION" "$CTX_ROOT" "$CTX_HOME" "$FORMAT" "$AGENT" "$THREAD" "$(queue_depth)"
  show_file status "$CTX_ROOT/status"
  show_file last_drained "$CTX_ROOT/control/last_drained"
  show_file route_provider "$CTX_HOME/route/$FORMAT/provider"
  show_file route_model "$CTX_HOME/route/$FORMAT/model"
  show_file route_reason "$CTX_HOME/route/$FORMAT/reason"
  for f in state pid heartbeat current_thread current_task; do show_file "agent_$f" "$CTX_ROOT/agent/$AGENT/runtime/$f"; done
}
models(){
  show_file count "$CTX_HOME/model/count"
  if [[ -r "$CTX_HOME/model/list" ]]; then cat "$CTX_HOME/model/list"; elif [[ -r "$CTX_ROOT/format/$FORMAT/model/list" ]]; then cat "$CTX_ROOT/format/$FORMAT/model/list"; else die "missing model list"; fi
}
route(){
  show_file default_provider "$CTX_HOME/route/default_provider"
  for f in provider model reason; do show_file "$FORMAT.$f" "$CTX_HOME/route/$FORMAT/$f"; done
}
ask(){ [[ $# -gt 0 ]] || die "missing prompt"; local id dir out errfile; id=$(request_id); dir="$CTX_HOME/api/$FORMAT"; submit_raw "$dir" "$id" "$(chat_body "$@")"; out="$dir/outbox/$id.resp.json"; errfile="$dir/outbox/$id.error"; wait_file "$out" "$errfile"; }
thread(){ local tid=$THREAD prompt; if [[ $# -gt 1 ]]; then tid=$1; shift; fi; [[ $# -gt 0 ]] || die "missing prompt"; local dir="$CTX_HOME/thread/$tid" id; id=$(request_id); submit_raw "$dir" "$id" "$(chat_body "$@")"; drain_steps "$MAX_DRAINS"; [[ -r "$dir/latest.md" ]] && cat "$dir/latest.md" || cat "$dir/messages.jsonl"; }
submit(){ [[ $# -gt 0 ]] || die "missing task"; local id dir out errfile; id=$(request_id); dir="$CTX_ROOT/agent/$AGENT"; submit_raw "$dir" "$id" "$(body_from_args "$@")"; out="$dir/outbox/$id.resp.json"; errfile="$dir/outbox/$id.error"; wait_file "$out" "$errfile"; }
cluster_submit(){ [[ $# -gt 0 ]] || die "missing task"; local id dir; id=$(request_id); dir="$CTX_ROOT/cluster/$CLUSTER/queue/$QUEUE/pending"; submit_raw "$dir" "$id" "$(body_from_args "$@")"; printf '%s\n' "$id"; }
tool_invoke(){
  [[ $# -gt 1 ]] || die "usage: agent.sh tool <tool-id> <json-or-text>"
  local tool=$1 id dir out errfile body; shift; id=$(request_id); dir="$CTX_ROOT/tool/$tool/invoke"
  case "$*" in \{*|\[* ) body="$*"$'\n' ;; *) body="{\"path\":\"$(json_escape "$*")\"}"$'\n' ;; esac
  submit_raw "$dir" "$id" "$body"; out="$dir/outbox/$id.resp.json"; errfile="$dir/outbox/$id.error"; wait_file "$out" "$errfile"
}
cluster(){
  local base q worker
  base="$CTX_ROOT/cluster/$CLUSTER"; q="$base/queue/$QUEUE"
  [[ -d $base ]] || die "missing cluster: $base"; printf 'cluster=%s\nqueue=%s\n' "$CLUSTER" "$QUEUE"
  show_file state "$base/state"; worker=$(read_text "$base/worker/list" | head -n1); [[ -n $worker ]] && for f in state heartbeat load current_task; do show_file "worker_$f" "$base/worker/$worker/$f"; done
  for d in pending running done failed; do [[ -d "$q/$d" ]] && printf '%s=%s\n' "$d" "$(find "$q/$d" -maxdepth 1 -type f 2>/dev/null | wc -l)"; done
}

mcp_result(){ printf '{"jsonrpc":"2.0","id":%s,"result":%s}\n' "$1" "$2"; }
mcp_error(){ printf '{"jsonrpc":"2.0","id":%s,"error":{"code":%s,"message":"%s"}}\n' "${1:-null}" "$2" "$(json_escape "$3")"; }
mcp_tools(){ cat <<'EOF_TOOLS'
{"tools":[{"name":"cortex.ask","description":"Submit a chat prompt through CortexFS API.","inputSchema":{"type":"object","properties":{"prompt":{"type":"string"}},"required":["prompt"]}},{"name":"agent.submit","description":"Submit a task to agent/<agent>/inbox.","inputSchema":{"type":"object","properties":{"task":{"type":"string"}},"required":["task"]}},{"name":"cluster.submit","description":"Submit a task to the CortexFS cluster queue.","inputSchema":{"type":"object","properties":{"task":{"type":"string"}},"required":["task"]}},{"name":"cortex.status","description":"Read CortexFS agent status.","inputSchema":{"type":"object","properties":{}}}]}
EOF_TOOLS
}
mcp_call(){
  local id=$1 line=$2 name arg out code; name=$(json_get_string name "$line" || true)
  case "$name" in
    cortex.ask) arg=$(json_get_string prompt "$line" || true); [[ -n $arg ]] || { mcp_error "$id" -32602 "missing prompt"; return; }; set +e; out=$(ask "$arg" 2>&1); code=$?; set -e ;;
    agent.submit) arg=$(json_get_string task "$line" || true); [[ -n $arg ]] || { mcp_error "$id" -32602 "missing task"; return; }; set +e; out=$(submit "$arg" 2>&1); code=$?; set -e ;;
    cluster.submit) arg=$(json_get_string task "$line" || true); [[ -n $arg ]] || { mcp_error "$id" -32602 "missing task"; return; }; set +e; out=$(cluster_submit "$arg" 2>&1); code=$?; set -e ;;
    cortex.status) set +e; out=$(status 2>&1); code=$?; set -e ;;
    *) mcp_error "$id" -32601 "unknown tool"; return ;;
  esac
  mcp_result "$id" "{\"content\":[{\"type\":\"text\",\"text\":\"$(json_escape "$out")\"}],\"isError\":$([[ $code -eq 0 ]] && printf false || printf true)}"
}
mcp(){ local line id method; while IFS= read -r line; do id=$(json_id "$line"); method=$(json_get_string method "$line" || true); case "$method" in initialize) mcp_result "$id" "{\"protocolVersion\":\"2025-06-18\",\"serverInfo\":{\"name\":\"agent.sh\",\"version\":\"$VERSION\"},\"capabilities\":{\"tools\":{}}}" ;; tools/list) mcp_result "$id" "$(mcp_tools)" ;; tools/call) mcp_call "$id" "$line" ;; notifications/*) ;; *) mcp_error "$id" -32601 "unknown method" ;; esac; done; }

case "${1:-help}" in
  status) status ;; models) models ;; route) route ;; ask) shift; ask "$@" ;; thread) shift; thread "$@" ;; submit) shift; submit "$@" ;;
  cluster-submit) shift; cluster_submit "$@" ;; cluster) cluster ;; tool) shift; tool_invoke "$@" ;; drain) shift; drain_steps "${1:-1}" ;;
  mcp) mcp ;; help|-h|--help) usage ;; *) usage; exit 2 ;;
esac
