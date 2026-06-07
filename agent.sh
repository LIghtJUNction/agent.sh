#!/usr/bin/env bash
set -euo pipefail

VERSION=0.1.0
FORMAT=${CORTEX_FORMAT:-openai.chat}
CTX_HOME=${CTX_HOME:-/ctx/home/$(id -u)}
CTX_ROOT=${CTX_ROOT:-/ctx}

die(){ printf 'agent.sh: %s\n' "$*" >&2; exit 1; }
usage(){ cat <<'EOF'
agent.sh - tiny CortexFS/MCP terminal agent

usage:
  agent.sh ask <prompt>
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
  rest=${line#*\"$key\"}
  [[ $rest != "$line" ]] || return 1
  rest=${rest#*:}; rest=${rest#*\"}; val=${rest%%\"*}
  printf '%s' "$val"
}
request_id(){ printf 'agent-%s-%s' "$$" "$(date +%s%N 2>/dev/null || date +%s)"; }
ask(){
  [[ $# -gt 0 ]] || die "missing prompt"
  local prompt=$* id api tmp req out drain
  api="$CTX_HOME/api/$FORMAT"
  [[ -d "$api/inbox" ]] || die "missing CortexFS inbox: $api/inbox"
  id=$(request_id); tmp="$api/inbox/$id.tmp"; req="$api/inbox/$id.req.json"; out="$api/outbox/$id.resp.json"
  printf '{"messages":[{"role":"user","content":"%s"}]}\n' "$(json_escape "$prompt")" >"$tmp"
  mv "$tmp" "$req"
  drain="$CTX_ROOT/control/drain"; [[ -w "$drain" ]] && printf '1\n' >"$drain" || true
  [[ -r "$out" ]] || die "response not ready: $out"
  cat "$out"
}
run_cmd(){
  [[ $# -gt 0 ]] || die "missing command"
  local out code
  set +e
  out=$(bash -c "$*" 2>&1); code=$?
  set -e
  printf '%s\n' "$out"
  return "$code"
}
mcp_result(){
  printf '{"jsonrpc":"2.0","id":%s,"result":%s}\n' "$1" "$2"
}
mcp_error(){
  printf '{"jsonrpc":"2.0","id":%s,"error":{"code":%s,"message":"%s"}}\n' "${1:-null}" "$2" "$(json_escape "$3")"
}
mcp_tools(){
  cat <<'EOF'
{"tools":[{"name":"terminal.run","description":"Run an explicit shell command on this Linux host.","inputSchema":{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}}]}
EOF
}
mcp_call(){
  local id=$1 line=$2 name cmd out code
  name=$(json_get_string name "$line" || true)
  [[ $name == "terminal.run" ]] || { mcp_error "$id" -32601 "unknown tool"; return; }
  cmd=$(json_get_string command "$line" || true)
  [[ -n $cmd ]] || { mcp_error "$id" -32602 "missing command"; return; }
  set +e
  out=$(bash -c "$cmd" 2>&1); code=$?
  set -e
  mcp_result "$id" "{\"content\":[{\"type\":\"text\",\"text\":\"$(json_escape "$out")\"}],\"isError\":$([[ $code -eq 0 ]] && printf false || printf true)}"
}
mcp(){
  local line id method
  while IFS= read -r line; do
    id=$(json_get_string id "$line" || printf 'null')
    method=$(json_get_string method "$line" || true)
    case "$method" in
      initialize) mcp_result "$id" "{\"protocolVersion\":\"2025-06-18\",\"serverInfo\":{\"name\":\"agent.sh\",\"version\":\"$VERSION\"},\"capabilities\":{\"tools\":{}}}" ;;
      tools/list) mcp_result "$id" "$(mcp_tools)" ;;
      tools/call) mcp_call "$id" "$line" ;;
      notifications/*) ;;
      *) mcp_error "$id" -32601 "unknown method" ;;
    esac
  done
}
case "${1:-help}" in
  ask) shift; ask "$@" ;;
  run) shift; run_cmd "$@" ;;
  mcp) mcp ;;
  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac
