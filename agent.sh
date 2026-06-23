#!/usr/bin/env bash
set -euo pipefail

VERSION=1.0.0-v1
CTX_ROOT=${CTX_ROOT:-/ctx}
CTX_HOME=${CTX_HOME:-$CTX_ROOT/home/$(id -u)}
CTX_PATH=${CTX_PATH:-$CTX_ROOT/tool:$CTX_HOME/tool}
SESSION=${CORTEX_SESSION:-}
MODE=send
RAW_EVENTS=${CORTEX_RAW_EVENTS:-0}
RUN_ID=${CORTEX_RUN_ID:-}

err(){ printf 'agent.sh: %s\n' "$*" >&2; }
die(){ err "$*"; exit 1; }

usage(){ cat <<'EOF_USAGE'
usage:
  agent.sh [--session SESSION] AGENT [INPUT...]
  agent.sh --session default AGENT
  agent.sh --resume AGENT
  agent.sh --history AGENT
  agent.sh --latest AGENT
  agent.sh --pack AGENT
  agent.sh --tools AGENT
  agent.sh --children AGENT
  agent.sh --cancel AGENT [RUN]
  agent.sh --status AGENT
  agent.sh --raw AGENT "prompt"
EOF_USAGE
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

json_text(){
  local s
  s=$(json_get_string "$1" "$2") || return 1
  s=${s//\\n/$'\n'}; s=${s//\\t/$'\t'}; s=${s//\\\"/\"}; s=${s//\\\\/\\}
  printf '%s' "$s"
}

valid_object_name(){
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$ ]] &&
    [[ $1 != *.sock ]] &&
    [[ $1 != *.d ]]
}

valid_session_name(){
  [[ -n $1 && $1 != "." && $1 != ".." && $1 != */* && $1 != *$'\n'* && $1 != *$'\t'* ]]
}

read_text(){ [[ -r $1 ]] && cat "$1" || true; }

agent_dir(){ printf '%s/agent/%s' "$CTX_ROOT" "$1"; }
agent_home(){ printf '%s/agent/%s' "$CTX_HOME" "$1"; }
agent_socket(){ printf '%s/agent/%s.sock' "$CTX_ROOT" "$1"; }

current_session(){
  local agent=$1 current
  if [[ -n $SESSION ]]; then
    printf '%s' "$SESSION"; return
  fi
  current=$(read_text "$(agent_home "$agent")/session/index/current" | tr -d '\n')
  [[ -n $current ]] && { printf '%s' "$current"; return; }
  printf 'default'
}

session_dir(){
  local agent=$1 session=$2
  printf '%s/session/%s' "$(agent_home "$agent")" "$session"
}

request_id(){
  [[ -n ${CORTEX_REQUEST_ID:-} ]] && { printf '%s' "$CORTEX_REQUEST_ID"; return; }
  printf 'agent-sh-%s-%s' "$$" "$(date +%s%N 2>/dev/null || date +%s)"
}

agent_cwd(){
  local agent=$1 cwd
  cwd=$(read_text "$(agent_dir "$agent").d/cwd" | tr -d '\n')
  [[ -n $cwd ]] && { printf '%s' "$cwd"; return; }
  printf '/work'
}

frame_check(){
  local frame=$1
  if (( ${#frame} > 1048576 )); then
    die "EMSGSIZE: socket frame exceeds 1048576 bytes"
  fi
}

render_events(){
  local line type text code msg saw_delta=0 exit_code=0
  [[ $RAW_EVENTS == 1 ]] && { cat; return; }
  while IFS= read -r line; do
    type=$(json_get_string type "$line" || true)
    case "$type" in
      delta|reasoning_delta)
        text=$(json_text text "$line" || json_text content "$line" || true)
        [[ -n $text ]] && { printf '%s' "$text"; saw_delta=1; }
        ;;
      message|reasoning_message)
        text=$(json_text text "$line" || json_text content "$line" || true)
        [[ -n $text && $saw_delta == 0 ]] && printf '%s\n' "$text"
        ;;
      tool_call)
        msg=$(json_text name "$line" || printf 'tool_call')
        printf '[tool] %s\n' "$msg" >&2
        ;;
      error)
        code=$(json_text code "$line" || printf 'EIO')
        msg=$(json_text message "$line" || printf 'runtime error')
        printf 'error: %s: %s\n' "$code" "$msg" >&2
        exit_code=1
        ;;
      pong)
        printf 'pong\n'
        ;;
      done)
        [[ $saw_delta == 1 ]] && printf '\n'
        ;;
    esac
  done
  return "$exit_code"
}

socket_send(){
  local agent=$1 request=$2 sock timeout=${CORTEX_SOCKET_TIMEOUT:-30}
  sock=$(agent_socket "$agent")
  [[ -S $sock ]] || die "missing agent socket: $sock"
  command -v nc >/dev/null 2>&1 || die "missing nc with Unix socket support"
  frame_check "$request"
  printf '%s' "$request" | nc -U -N -w "$timeout" "$sock" | render_events
}

send_once(){
  local agent=$1 session=$2 input=$3 id request cwd
  id=$(request_id); cwd=$(agent_cwd "$agent")
  request=$(printf '{"op":"send","id":"%s","session":"%s","scope":"private","cwd":"%s","input":"%s"}\n' \
    "$(json_escape "$id")" "$(json_escape "$session")" "$(json_escape "$cwd")" "$(json_escape "$input")")
  socket_send "$agent" "$request"
}

resume_agent(){
  local agent=$1 session=$2 request
  request=$(printf '{"op":"resume","session":"%s"}\n' "$(json_escape "$session")")
  socket_send "$agent" "$request"
}

latest_run(){
  local agent=$1 session=$2 dir line run last=
  dir=$(session_dir "$agent" "$session")
  [[ -r "$dir/current_run" ]] && { tr -d '\n' <"$dir/current_run"; return; }
  [[ -r "$dir/events.jsonl" ]] || return 1
  while IFS= read -r line; do
    run=$(json_get_string run "$line" || true)
    [[ -n $run ]] && last=$run
  done <"$dir/events.jsonl"
  [[ -n $last ]] || return 1
  printf '%s' "$last"
}

cancel_agent(){
  local agent=$1 session=$2 run=${3:-} request
  [[ -n $run ]] || run=$RUN_ID
  [[ -n $run ]] || run=$(latest_run "$agent" "$session" || true)
  [[ -n $run ]] || die "missing run id; pass RUN or set CORTEX_RUN_ID"
  request=$(printf '{"op":"cancel","id":"%s"}\n' "$(json_escape "$run")")
  socket_send "$agent" "$request"
}

history_agent(){
  local agent=$1 session=$2 file
  file=$(session_dir "$agent" "$session")/messages.jsonl
  [[ -r $file ]] || die "missing history: $file"
  cat "$file"
}

latest_agent(){
  local agent=$1 session=$2 file
  file=$(session_dir "$agent" "$session")/latest.md
  [[ -r $file ]] || die "missing latest output: $file"
  cat "$file"
}

pack_agent(){
  local agent=$1 session=$2 dir
  dir=$(session_dir "$agent" "$session")/context
  if [[ -r "$dir/pack.md" ]]; then cat "$dir/pack.md"; return; fi
  if [[ -r "$dir/pack.json" ]]; then cat "$dir/pack.json"; return; fi
  if [[ -r "$dir/summary.md" ]]; then cat "$dir/summary.md"; return; fi
  die "missing context pack: $dir/pack.md"
}

children_agent(){
  local agent=$1 session=$2 base child name status ref
  base=$(session_dir "$agent" "$session")/context/child
  [[ -d $base ]] || return 0
  for child in "$base"/*; do
    [[ -d $child ]] || continue
    name=${child##*/}
    status=$(read_text "$child/status" | tr -d '\n')
    ref=$(read_text "$child/agent" | tr -d '\n')
    printf '%s\t%s\t%s\n' "$name" "${status:-unknown}" "${ref:-agent?}"
  done
}

status_agent(){
  local agent=$1 session=$2 home ctl
  home=$(agent_home "$agent"); ctl=$(agent_dir "$agent").d
  printf 'version=%s\nroot=%s\nhome=%s\nagent=%s\nsession=%s\nsocket=%s\n' \
    "$VERSION" "$CTX_ROOT" "$CTX_HOME" "$agent" "$session" "$(agent_socket "$agent")"
  for file in owner uid gid label iso parent life root cwd model status pid log; do
    [[ -r "$ctl/$file" ]] && printf '%s=%s\n' "$file" "$(tr -d '\n' <"$ctl/$file")"
  done
  [[ -d "$home/session" ]] && printf 'session_dir=%s\n' "$home/session"
}

tool_hits(){
  local paths path file name status
  paths=$CTX_PATH
  [[ -r "$(agent_dir "$1").d/path" ]] && paths="$paths:$(paste -sd: "$(agent_dir "$1").d/path")"
  IFS=':' read -r -a parts <<<"$paths"
  for path in "${parts[@]}"; do
    [[ -d $path ]] || continue
    for file in "$path"/*; do
      [[ -f $file || -L $file ]] || continue
      [[ -x $file ]] || continue
      name=${file##*/}
      [[ $name == *.sock || $name == *.d ]] && continue
      status=$(read_text "$file.d/status" | tr -d '\n')
      printf '%s\t%s\t%s\n' "$name" "$file" "${status:-unknown}"
    done
  done
}

tool_log(){
  local tool=$1 path file
  IFS=':' read -r -a parts <<<"$CTX_PATH"
  for path in "${parts[@]}"; do
    file="$path/$tool.d/log"
    [[ -r $file ]] && { cat "$file"; return; }
  done
  die "missing tool log: $tool"
}

interactive(){
  local agent=$1 session=$2 line
  [[ -t 0 ]] && printf 'agent.sh %s  agent=%s session=%s\n' "$VERSION" "$agent" "$session" >&2
  [[ -t 0 ]] && printf '%s> ' "$agent" >&2
  while IFS= read -r line; do
    case "$line" in
      '') ;;
      /exit|/quit) break ;;
      /resume) resume_agent "$agent" "$session" || true ;;
      /history) history_agent "$agent" "$session" || true ;;
      /latest) latest_agent "$agent" "$session" || true ;;
      /pack) pack_agent "$agent" "$session" || true ;;
      /tools) tool_hits "$agent" || true ;;
      /children) children_agent "$agent" "$session" || true ;;
      /cancel) cancel_agent "$agent" "$session" || true ;;
      /status) status_agent "$agent" "$session" ;;
      /*) err "unknown command: $line" ;;
      *) send_once "$agent" "$session" "$line" || true ;;
    esac
    [[ -t 0 ]] && printf '%s> ' "$agent" >&2
  done
  return 0
}

parse_args(){
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session) [[ $# -gt 1 ]] || die "missing --session value"; SESSION=$2; shift 2 ;;
      --resume) MODE=resume; shift ;;
      --history) MODE=history; shift ;;
      --latest) MODE=latest; shift ;;
      --pack) MODE=pack; shift ;;
      --tools) MODE=tools; shift ;;
      --children) MODE=children; shift ;;
      --cancel) MODE=cancel; shift ;;
      --status) MODE=status; shift ;;
      --tool-log) MODE=tool_log; shift ;;
      --raw) RAW_EVENTS=1; shift ;;
      --help|-h|help) usage; exit 0 ;;
      --) shift; break ;;
      -*) die "unknown option: $1" ;;
      *) break ;;
    esac
  done
  [[ $# -gt 0 ]] || { usage; exit 2; }
  AGENT=$1; shift
  valid_object_name "$AGENT" || die "invalid agent name: $AGENT"
  SESSION=$(current_session "$AGENT")
  valid_session_name "$SESSION" || die "invalid session name: $SESSION"
  case "$MODE" in
    send)
      if [[ $# -gt 0 ]]; then
        send_once "$AGENT" "$SESSION" "$*"
      else
        interactive "$AGENT" "$SESSION"
      fi
      ;;
    resume) resume_agent "$AGENT" "$SESSION" ;;
    history) history_agent "$AGENT" "$SESSION" ;;
    latest) latest_agent "$AGENT" "$SESSION" ;;
    pack) pack_agent "$AGENT" "$SESSION" ;;
    tools) tool_hits "$AGENT" ;;
    children) children_agent "$AGENT" "$SESSION" ;;
    cancel) cancel_agent "$AGENT" "$SESSION" "${1:-}" ;;
    status) status_agent "$AGENT" "$SESSION" ;;
    tool_log) [[ $# -gt 0 ]] || die "missing tool name"; tool_log "$1" ;;
    *) die "internal mode error: $MODE" ;;
  esac
}

parse_args "$@"
