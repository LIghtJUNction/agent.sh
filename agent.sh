#!/usr/bin/env bash
set -euo pipefail

VERSION=0.2.0
FORMAT=${CORTEX_FORMAT:-openai.chat}
CTX_ROOT=${CTX_ROOT:-/ctx}
CTX_HOME=${CTX_HOME:-$CTX_ROOT/home/$(id -u)}
CLUSTER=${CORTEX_CLUSTER:-local}
QUEUE=${CORTEX_QUEUE:-default}

die(){ printf 'agent.sh: %s\n' "$*" >&2; exit 1; }
usage(){ cat <<'EOF'
agent.sh - tiny CortexFS agent CLI

usage:
  agent.sh ask <prompt>
  agent.sh submit <json-or-text>
  agent.sh cluster
  agent.sh drain
  agent.sh run <command>
  agent.sh mcp
  agent.sh help
EOF
}
json_escape(){
  local s=${1-}
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\t'/\\t}
  printf '%s' "$s"
}
json_get_string(){
  local key=$1 line=$2 rest val
  rest=${line#*\"$key\"}; [[ $rest != "$line" ]] || return 1
  rest=${rest#*:}; rest=${rest#*\"}; val=${rest%%\"*}; printf '%s' "$val"
}
request_id(){ printf 'agent-%s-%s' "$$" "$(date +%s%N 2>/dev/null || date +%s)"; }
drain(){
  local global="$CTX_ROOT/control/drain" cluster="$CTX_ROOT/cluster/$CLUSTER/control/drain"
  [[ -w "$global" ]] && printf '1\n' >"$global" || true
  [[ -w "$cluster" ]] && printf '1\n' >"$cluster" || true
}
ask(){
  [[ $# -gt 0 ]] || die "missing prompt"
  local prompt=$* id api tmp req out
  api="$CTX_HOME/api/$FORMAT"; [[ -d "$api/inbox" ]] || die "missing inbox: $api/inbox"
  id=$(request_id); tmp="$api/inbox/$id.tmp"; req="$api/inbox/$id.req.json"; out="$api/outbox/$id.resp.json"
  printf '{"messages":[{"role":"user","content":"%s"}]}\n' "$(json_escape "$prompt")" >"$tmp"
  mv "$tmp" "$req"; drain
  [[ -r "$out" ]] || die "response not ready: $out"
  cat "$out"
}
submit(){
  [[ $# -gt 0 ]] || die "missing task"
  local body=$* id dir tmp req
  dir="$CTX_ROOT/cluster/$CLUSTER/queue/$QUEUE/pending"; [[ -d "$dir" ]] || die "missing queue: $dir"
  id=$(request_id); tmp="$dir/$id.tmp"; req="$dir/$id.req.json"
  case "$body" in
    \{*) printf '%s\n' "$body" >"$tmp" ;;
    *) printf '{"task":"%s"}\n' "$(json_escape "$body")" >"$tmp" ;;
  esac
  mv "$tmp" "$req"; printf '%s\n' "$id"
}
cluster(){
  local base="$CTX_ROOT/cluster/$CLUSTER" q="$CTX_ROOT/cluster/$CLUSTER/queue/$QUEUE"
  [[ -d "$base" ]] || die "missing cluster: $base"
  printf 'cluster=%s\nqueue=%s\n' "$CLUSTER" "$QUEUE"
  for f in "$base/state" "$base/worker/local/state" "$base/worker/local/load"; do
    [[ -r "$f" ]] && printf '%s=%s' "${f#$CTX_ROOT/}" "$(cat "$f")"
  done
  for d in pending running done failed; do
    [[ -d "$q/$d" ]] && printf '%s=%s\n' "$d" "$(find "$q/$d" -maxdepth 1 -type f 2>/dev/null | wc -l)"
  done
}
run_cmd(){
  [[ $# -gt 0 ]] || die "missing command"
  local out code; set +e; out=$(bash -c "$*" 2>&1); code=$?; set -e
  printf '%s\n' "$out"; return "$code"
}
mcp_result(){ printf '{"jsonrpc":"2.0","id":%s,"result":%s}\n' "$1" "$2"; }
mcp_error(){ printf '{"jsonrpc":"2.0","id":%s,"error":{"code":%s,"message":"%s"}}\n' "${1:-null}" "$2" "$(json_escape "$3")"; }
mcp_tools(){ cat <<'EOF'
{"tools":[{"name":"terminal.run","description":"Run an explicit shell command.","inputSchema":{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}},{"name":"cluster.submit","description":"Submit a task to the CortexFS cluster queue.","inputSchema":{"type":"object","properties":{"task":{"type":"string"}},"required":["task"]}}]}
EOF
}
mcp_call(){
  local id=$1 line=$2 name arg out code task
  name=$(json_get_string name "$line" || true)
  case "$name" in
    terminal.run)
      arg=$(json_get_string command "$line" || true); [[ -n $arg ]] || { mcp_error "$id" -32602 "missing command"; return; }
      set +e; out=$(bash -c "$arg" 2>&1); code=$?; set -e
      mcp_result "$id" "{\"content\":[{\"type\":\"text\",\"text\":\"$(json_escape "$out")\"}],\"isError\":$([[ $code -eq 0 ]] && printf false || printf true)}" ;;
    cluster.submit)
      task=$(json_get_string task "$line" || true); [[ -n $task ]] || { mcp_error "$id" -32602 "missing task"; return; }
      out=$(submit "$task"); mcp_result "$id" "{\"content\":[{\"type\":\"text\",\"text\":\"$(json_escape "$out")\"}],\"isError\":false}" ;;
    *) mcp_error "$id" -32601 "unknown tool" ;;
  esac
}
mcp(){
  local line id method
  while IFS= read -r line; do
    id=$(json_get_string id "$line" || printf 'null'); method=$(json_get_string method "$line" || true)
    case "$method" in
      initialize) mcp_result "$id" "{\"protocolVersion\":\"2025-06-18\",\"serverInfo\":{\"name\":\"agent\",\"version\":\"$VERSION\"},\"capabilities\":{\"tools\":{}}}" ;;
      tools/list) mcp_result "$id" "$(mcp_tools)" ;;
      tools/call) mcp_call "$id" "$line" ;;
      notifications/*) ;;
      *) mcp_error "$id" -32601 "unknown method" ;;
    esac
  done
}
case "${1:-help}" in
  ask) shift; ask "$@" ;;
  submit) shift; submit "$@" ;;
  cluster) cluster ;;
  drain) drain ;;
  run) shift; run_cmd "$@" ;;
  mcp) mcp ;;
  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac
