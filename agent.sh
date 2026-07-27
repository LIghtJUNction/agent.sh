#!/usr/bin/env bash
set -euo pipefail

die(){ printf 'agent.sh %s\n' "$*" >&2; exit 1; }

resolve_ctx(){
  if [[ -n ${CTX_BIN:-} ]]; then
    [[ -x $CTX_BIN ]] || die "CTX_BIN is not executable: $CTX_BIN"
    printf '%s\n' "$CTX_BIN"
    return
  fi

  local script_dir candidate
  script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
  for candidate in \
    "$script_dir/../target/debug/ctx" \
    "$script_dir/../target/release/ctx"
  do
    if [[ -x $candidate ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  command -v ctx >/dev/null 2>&1 || die "ctx not found; set CTX_BIN or install cortexfs"
  command -v ctx
}

usage(){
  cat <<'EOF'
usage:
  agent.sh [--session SESSION] [--raw] AGENT [INPUT...]
  agent.sh --chat|--repl [--session SESSION] [--raw] AGENT
  agent.sh --start [--session SESSION] AGENT [CTX_AGENT_START_ARGS...]
  agent.sh --attach|--watch|--resume|--history|--output|--pack|--tools|--children|--status [--session SESSION] AGENT
  agent.sh --cancel [--session SESSION] AGENT [RUN]

agent.sh is a small default wrapper over ctx agent.
EOF
}

ctx=$(resolve_ctx)
session=default
raw=()
mode=auto

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --session|-s)
      [[ $# -ge 2 ]] || die "--session requires a value"
      session=$2
      shift 2
      ;;
    --raw)
      raw=(--raw)
      shift
      ;;
    --start|--attach|--watch|--resume|--history|--output|--pack|--tools|--children|--cancel|--status)
      mode=${1#--}
      shift
      ;;
    --chat|--repl)
      mode=chat
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

[[ $# -ge 1 ]] || die "missing agent name"
agent=$1
shift

case "$mode" in
  auto)
    if [[ $# -gt 0 ]]; then
      exec "$ctx" agent send "$agent" --session "$session" "${raw[@]}" "$*"
    fi
    exec "$ctx" agent chat "$agent" --session "$session" "${raw[@]}"
    ;;
  chat)
    exec "$ctx" agent chat "$agent" --session "$session" "${raw[@]}"
    ;;
  start)
    exec "$ctx" agent start "$agent" --session "$session" "$@"
    ;;
  attach|watch|resume|history|output|pack|children)
    exec "$ctx" agent "$mode" "$agent" --session "$session" "$@"
    ;;
  cancel)
    exec "$ctx" agent cancel "$agent" --session "$session" "${raw[@]}" "$@"
    ;;
  tools|status)
    exec "$ctx" agent "$mode" "$agent" "$@"
    ;;
  *)
    die "unknown mode: $mode"
    ;;
esac
