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
usage:
  agent.sh                         # interactive thread socket session
  agent.sh status|doctor|providers|models|route|cluster|sessions
  agent.sh ask|chat|thread <prompt>
  agent.sh repl|resume|new|temp|share [session]
  agent.sh submit|cluster-submit <json-or-text>
  agent.sh read <path> | run <command>
  agent.sh tool <tool-id> <json-or-text> | drain [steps]
  agent.sh mcp|mcp-config|help
EOF_USAGE
}
json_escape(){
  local s=${1-}
  s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\t'/\\t}
  printf '%s' "$s"
}
json_get_string(){ local key=$1 line=$2 rest val; rest=${line#*\"$key\"}; [[ $rest != "$line" ]] || return 1; rest=${rest#*:}; rest=${rest#*\"}; val=${rest%%\"*}; printf '%s' "$val"; }
json_id(){ local line=$1 rest val; rest=${line#*\"id\"}; [[ $rest != "$line" ]] || { printf 'null'; return; }; rest=${rest#*:}; rest=${rest#${rest%%[![:space:]]*}}; if [[ $rest == \"* ]]; then val=${rest#\"}; printf '"%s"' "${val%%\"*}"; else val=${rest%%,*}; val=${val%%\}*}; printf '%s' "${val//[[:space:]]/}"; fi; }
json_text(){ local s; s=$(json_get_string "$1" "$2") || return 1; s=${s//\\n/$'\n'}; s=${s//\\t/$'\t'}; s=${s//\\\"/\"}; s=${s//\\\\/\\}; printf '%s' "$s"; }
render_events(){ local line type text saw=0 code=0; [[ ${CORTEX_RAW_EVENTS:-0} == 1 ]] && { cat; return; }; while IFS= read -r line; do type=$(json_get_string type "$line" || true); case "$type" in delta) json_text content "$line"; saw=1 ;; message) (( saw )) || { json_text content "$line"; printf '\n'; } ;; error) text=$(json_text message "$line" || printf 'unknown error'); printf 'error: %s\n' "$text" >&2; code=1 ;; done) (( saw )) && printf '\n' ;; esac; done; return "$code"; }
slug(){ local s=${1##*/}; s=${s:-root}; s=${s,,}; s=${s//[^a-z0-9_.-]/-}; s=${s#[._-]}; s=${s%[._-]}; [[ -n $s ]] || s=root; printf '%.40s' "$s"; }
hash_text(){ local sum rest; read -r sum rest < <(printf '%s' "$1" | cksum); printf '%s' "$sum"; }
session_default(){ [[ -n ${CORTEX_SESSION:-} ]] && { printf '%s' "$CORTEX_SESSION"; return; }; printf 'cwd-%s-%s' "$(slug "$PWD")" "$(hash_text "$PWD")"; }
SESSION=${SESSION:-$(session_default)}
SESSION_SCOPE=${SESSION_SCOPE:-workspace}
session_switch(){ SESSION=$1; SESSION_SCOPE=${2:-workspace}; }
session_new(){ local id=${1:-chat-$(date +%Y%m%d-%H%M%S)}; session_switch "$(slug "$id")" private; }
session_temp(){ session_switch "tmp-$$-$(date +%s)" temp; }
session_share(){ local id=${1:-$(slug "$PWD")}; session_switch "shared-$(slug "$id")" shared; }
session_list(){ [[ -r "$CTX_HOME/thread/list" ]] && cat "$CTX_HOME/thread/list" || printf 'demo\tworkspace\t\t\n'; }
session_info(){ printf 'session=%s\nscope=%s\nthread=%s\n' "$SESSION" "$SESSION_SCOPE" "$CTX_HOME/thread/$SESSION"; }
request_id(){ [[ -n ${CORTEX_REQUEST_ID:-} ]] && printf '%s' "$CORTEX_REQUEST_ID" || printf 'agent-%s-%s' "$$" "$(date +%s%N 2>/dev/null || date +%s)"; }
read_text(){ [[ -r $1 ]] && cat "$1" || true; }
show_file(){ [[ -r $2 ]] && printf '%s=%s\n' "$1" "$(cat "$2")" || true; }
body_from_args(){ local body=$*; case "$body" in \{*|\[* ) printf '%s\n' "$body" ;; *) printf '{"task":"%s"}\n' "$(json_escape "$body")" ;; esac; }
chat_body(){ printf '{"messages":[{"role":"user","content":"%s"}]}\n' "$(json_escape "$*")"; }
thread_body(){ printf '{"op":"send","session":"%s","scope":"%s","cwd":"%s","message":{"role":"user","content":"%s"}}\n' "$(json_escape "$SESSION")" "$(json_escape "$SESSION_SCOPE")" "$(json_escape "$PWD")" "$(json_escape "$*")"; }
submit_raw(){
  local dir=$1 id=$2 body=$3 inbox tmp req
  inbox="$dir/inbox"; [[ -d "$inbox" ]] || inbox="$dir"
  [[ -d "$inbox" ]] || die "missing submission directory: $dir"
  tmp="$inbox/$id.tmp"; req="$inbox/$id.req.json"
  printf '%s' "$body" >"$tmp"
  if ! mv "$tmp" "$req"; then
    if [[ $dir == "$CTX_HOME/api/"* ]]; then
      err "api submission denied; route provider=$(read_text "$CTX_HOME/route/$FORMAT/provider" | tr -d '\n') model=$(read_text "$CTX_HOME/route/$FORMAT/model" | tr -d '\n') reason=$(read_text "$CTX_HOME/route/$FORMAT/reason" | tr -d '\n')"
      err "fix provider/secret/route, then retry"
    fi
    return 1
  fi
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
  printf 'version=%s\nroot=%s\nhome=%s\nformat=%s\nagent=%s\nthread=%s\nsession=%s\nscope=%s\nqueue_depth=%s\n' "$VERSION" "$CTX_ROOT" "$CTX_HOME" "$FORMAT" "$AGENT" "$THREAD" "$SESSION" "$SESSION_SCOPE" "$(queue_depth)"
  show_file status "$CTX_ROOT/status"
  show_file last_drained "$CTX_ROOT/control/last_drained"
  show_file route_provider "$CTX_HOME/route/$FORMAT/provider"
  show_file route_model "$CTX_HOME/route/$FORMAT/model"
  show_file route_reason "$CTX_HOME/route/$FORMAT/reason"
  for f in state pid heartbeat current_thread current_task; do show_file "agent_$f" "$CTX_ROOT/agent/$AGENT/runtime/$f"; done
}
doctor(){
  status
  printf 'mount=%s\n' "$([[ -d $CTX_ROOT ]] && printf ok || printf missing)"
  local p; p=$(read_text "$CTX_HOME/route/$FORMAT/provider" | tr -d '\n')
  [[ -n $p ]] || { printf 'ready=0\nreason=no_route\n'; return; }
  for f in enabled/effective secrets/status health/status model/list; do show_file "provider_$f" "$CTX_ROOT/provider/$p/$f"; done
  show_file api_unix_status "$CTX_HOME/api/unix/status"
  local ts=missing socket_ready=0 route_ready=0; [[ -S "$CTX_HOME/thread/$THREAD/io.sock" ]] && { ts=present; socket_ready=1; }; [[ $(read_text "$CTX_HOME/route/$FORMAT/reason" | tr -d '\n') == ready ]] && route_ready=1
  printf 'thread_socket=%s\napi_route_ready=%s\nchat_ready=%s\nready=%s\n' "$ts" "$route_ready" "$socket_ready" "$socket_ready"
}
providers(){
  local list p
  list=$(read_text "$CTX_ROOT/provider/list")
  [[ -n $list ]] || die "missing provider list"
  while IFS= read -r p; do
    [[ -n $p ]] || continue
    printf '[%s]\n' "$p"
    for f in name family format url/effective enabled/effective secrets/status health/status model/list; do show_file "$f" "$CTX_ROOT/provider/$p/$f"; done
  done <<<"$list"
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
thread(){
  local tid=$THREAD sock timeout=${CORTEX_SOCKET_TIMEOUT:-30} out prompt=$*
  if [[ $# -gt 1 && -S "$CTX_HOME/thread/$1/io.sock" ]]; then tid=$1; shift; prompt=$*; fi
  [[ $tid != "$THREAD" ]] && SESSION=$tid
  [[ $# -gt 0 ]] || { err "missing prompt"; return 1; }
  sock="$CTX_HOME/thread/$tid/io.sock"
  [[ -S "$sock" ]] || { err "missing thread socket: $sock"; return 1; }
  command -v nc >/dev/null 2>&1 || { err "missing nc with Unix socket support"; return 1; }
  if ! out=$(thread_body "$@" | nc -U -N -w "$timeout" "$sock" | render_events); then
    err "thread request failed: $sock"
    return 1
  fi
  printf '%s\n' "$out"
}
repl(){
  [[ $# -gt 0 ]] && session_switch "$1"; local tid=$THREAD line
  [[ -t 0 ]] && { printf 'agent.sh %s  session=%s  type /help for commands\n' "$VERSION" "$SESSION" >&2; printf 'agent> ' >&2; }
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    case "$line" in
      /exit|/quit) break ;;
      /help) usage ;;
      /status) status ;;
      /doctor) doctor ;;
      /providers) providers ;;
      /models) models ;;
      /route) route ;;
      /cluster) cluster ;;
      /mcp-config) mcp_config ;;
      /sessions) session_list ;; /resume\ *) session_switch "${line#/resume }"; session_info ;; /new) session_new; session_info ;; /new\ *) session_new "${line#/new }"; session_info ;; /temp) session_temp; session_info ;; /share) session_share; session_info ;; /share\ *) session_share "${line#/share }"; session_info ;;
      /read\ *) read_tool "${line#/read }" ;;
      /run\ *) terminal_run "${line#/run }" ;;
      /ask\ *) ask "${line#/ask }" ;;
      /submit\ *) submit "${line#/submit }" ;;
      /cluster-submit\ *) cluster_submit "${line#/cluster-submit }" ;;
      /*) err "unknown command: $line" ;;
      *) thread "$tid" "$line" || true ;;
    esac
    [[ -t 0 ]] && printf 'agent> ' >&2
  done
  return 0
}
submit(){ [[ $# -gt 0 ]] || die "missing task"; local id dir out errfile; id=$(request_id); dir="$CTX_ROOT/agent/$AGENT"; submit_raw "$dir" "$id" "$(body_from_args "$@")"; out="$dir/outbox/$id.resp.json"; errfile="$dir/outbox/$id.error"; wait_file "$out" "$errfile"; }
cluster_submit(){ [[ $# -gt 0 ]] || die "missing task"; local id dir; id=$(request_id); dir="$CTX_ROOT/cluster/$CLUSTER/queue/$QUEUE/pending"; submit_raw "$dir" "$id" "$(body_from_args "$@")"; printf '%s\n' "$id"; }
tool_invoke(){
  [[ $# -gt 1 ]] || die "usage: agent.sh tool <tool-id> <json-or-text>"
  local tool=$1 id dir out errfile body; shift; id=$(request_id); dir="$CTX_ROOT/tool/$tool/invoke"
  case "$*" in \{*|\[* ) body="$*"$'\n' ;; *) body="{\"path\":\"$(json_escape "$*")\"}"$'\n' ;; esac
  submit_raw "$dir" "$id" "$body"; out="$dir/outbox/$id.resp.json"; errfile="$dir/outbox/$id.error"; wait_file "$out" "$errfile"
}
read_tool(){ [[ $# -gt 0 ]] || die "missing path"; tool_invoke filesystem.read "$*"; }
terminal_run(){ [[ $# -gt 0 ]] || die "missing command"; tool_invoke shell.exec "{\"command\":\"$(json_escape "$*")\"}"; }
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
{"tools":[{"name":"cortex.ask","description":"Submit a one-shot prompt through CortexFS API inbox/outbox.","inputSchema":{"type":"object","properties":{"prompt":{"type":"string"}},"required":["prompt"]}},{"name":"thread.send","description":"Send a conversational turn through thread/<id>/io.sock.","inputSchema":{"type":"object","properties":{"prompt":{"type":"string"},"thread":{"type":"string"}},"required":["prompt"]}},{"name":"cortex.status","description":"Read CortexFS agent status.","inputSchema":{"type":"object","properties":{}}},{"name":"filesystem.read","description":"Read a CortexFS-visible file through the filesystem.read tool.","inputSchema":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}},{"name":"terminal.run","description":"Submit an explicit shell execution request through CortexFS shell.exec.","inputSchema":{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}},{"name":"agent.submit","description":"Submit a task to agent/<agent>/inbox.","inputSchema":{"type":"object","properties":{"task":{"type":"string"}},"required":["task"]}},{"name":"cluster.submit","description":"Submit a task to the CortexFS cluster queue.","inputSchema":{"type":"object","properties":{"task":{"type":"string"}},"required":["task"]}}]}
EOF_TOOLS
}
mcp_call(){
  local id=$1 line=$2 name arg out code; name=$(json_get_string name "$line" || true)
  case "$name" in
    cortex.ask) arg=$(json_get_string prompt "$line" || true); [[ -n $arg ]] || { mcp_error "$id" -32602 "missing prompt"; return; }; set +e; out=$(ask "$arg" 2>&1); code=$?; set -e ;;
    thread.send) arg=$(json_get_string prompt "$line" || true); [[ -n $arg ]] || { mcp_error "$id" -32602 "missing prompt"; return; }; set +e; out=$(thread "$(json_get_string thread "$line" || printf '%s' "$THREAD")" "$arg" 2>&1); code=$?; set -e ;;
    filesystem.read) arg=$(json_get_string path "$line" || true); [[ -n $arg ]] || { mcp_error "$id" -32602 "missing path"; return; }; set +e; out=$(read_tool "$arg" 2>&1); code=$?; set -e ;;
    terminal.run) arg=$(json_get_string command "$line" || true); [[ -n $arg ]] || { mcp_error "$id" -32602 "missing command"; return; }; set +e; out=$(terminal_run "$arg" 2>&1); code=$?; set -e ;;
    agent.submit) arg=$(json_get_string task "$line" || true); [[ -n $arg ]] || { mcp_error "$id" -32602 "missing task"; return; }; set +e; out=$(submit "$arg" 2>&1); code=$?; set -e ;;
    cluster.submit) arg=$(json_get_string task "$line" || true); [[ -n $arg ]] || { mcp_error "$id" -32602 "missing task"; return; }; set +e; out=$(cluster_submit "$arg" 2>&1); code=$?; set -e ;;
    cortex.status) set +e; out=$(status 2>&1); code=$?; set -e ;;
    *) mcp_error "$id" -32601 "unknown tool"; return ;;
  esac
  mcp_result "$id" "{\"content\":[{\"type\":\"text\",\"text\":\"$(json_escape "$out")\"}],\"isError\":$([[ $code -eq 0 ]] && printf false || printf true)}"
}
mcp(){ local line id method; while IFS= read -r line; do id=$(json_id "$line"); method=$(json_get_string method "$line" || true); case "$method" in initialize) mcp_result "$id" "{\"protocolVersion\":\"2025-06-18\",\"serverInfo\":{\"name\":\"agent.sh\",\"version\":\"$VERSION\"},\"capabilities\":{\"tools\":{}}}" ;; tools/list) mcp_result "$id" "$(mcp_tools)" ;; tools/call) mcp_call "$id" "$line" ;; notifications/*) ;; *) mcp_error "$id" -32601 "unknown method" ;; esac; done; }
mcp_config(){ local self; self=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}"); printf '{"mcpServers":{"cortex-agent":{"command":"%s","args":["mcp"],"env":{"CTX_ROOT":"%s","CTX_HOME":"%s"}}}}\n' "$(json_escape "$self")" "$(json_escape "$CTX_ROOT")" "$(json_escape "$CTX_HOME")"; }

cmd=${1:-repl}; [[ $# -gt 0 ]] && shift
case "$cmd" in
  status) status ;; doctor) doctor ;; providers) providers ;; models) models ;; route) route ;; sessions) session_list ;; resume) session_switch "$1"; repl ;; new) session_new "${1:-}"; repl ;; temp) session_temp; repl ;; share) session_share "${1:-}"; repl ;; ask) ask "$@" ;; chat|thread) thread "$@" ;; repl) repl "$@" ;; submit) submit "$@" ;;
  cluster-submit) cluster_submit "$@" ;; cluster) cluster ;; read) read_tool "$@" ;; run|terminal-run) terminal_run "$@" ;; tool) tool_invoke "$@" ;; drain) drain_steps "${1:-1}" ;;
  mcp) mcp ;; mcp-config) mcp_config ;; help|-h|--help) usage ;; *) usage; exit 2 ;;
esac
