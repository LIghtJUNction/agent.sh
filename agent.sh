#!/usr/bin/env bash
set -euo pipefail

SESSION=${CORTEX_SESSION:-}
MODE=repl
RAW=0

err(){ printf 'agent.sh %s\n' "$*" >&2; }
die(){ err "$*"; exit 1; }

usage(){
  cat <<'EOF_USAGE'
usage:
  agent.sh [--session SESSION] AGENT [INPUT...]
  agent.sh --session default AGENT
  agent.sh --resume AGENT
  agent.sh --history AGENT
  agent.sh --pack AGENT
  agent.sh --tools AGENT
  agent.sh --children AGENT
  agent.sh --cancel AGENT [RUN]
  agent.sh --status AGENT
  agent.sh --raw AGENT "prompt"

agent.sh is a compatibility wrapper over ctx agent commands.
EOF_USAGE
}

valid_object_name(){
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$ ]] &&
    [[ $1 != *.sock ]] &&
    [[ $1 != *.d ]]
}

session_args(){
  [[ -n $SESSION ]] && printf '%s\n%s\n' --session "$SESSION"
}

raw_args(){
  [[ $RAW == 1 ]] && printf '%s\n' --raw
}

run_ctx(){
  local -a args=("$@")
  exec ctx "${args[@]}"
}

parse_args(){
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session)
        [[ $# -gt 1 ]] || die "missing --session value"
        SESSION=$2
        shift 2
        ;;
      --raw)
        RAW=1
        shift
        ;;
      --resume) MODE=resume; shift ;;
      --history) MODE=history; shift ;;
      --pack) MODE=pack; shift ;;
      --tools) MODE=tools; shift ;;
      --children) MODE=children; shift ;;
      --cancel) MODE=cancel; shift ;;
      --status) MODE=status; shift ;;
      --help|-h|help) usage; exit 0 ;;
      --) shift; break ;;
      -*) die "unknown option: $1" ;;
      *) break ;;
    esac
  done

  [[ $# -gt 0 ]] || { usage; exit 2; }
  local agent=$1
  shift
  valid_object_name "$agent" || die "invalid agent name: $agent"

  local -a session=()
  while IFS= read -r item; do session+=("$item"); done < <(session_args)
  local -a raw=()
  while IFS= read -r item; do raw+=("$item"); done < <(raw_args)

  case "$MODE" in
    repl)
      if [[ $# -gt 0 ]]; then
        run_ctx agent send "$agent" "${session[@]}" "${raw[@]}" "$*"
      fi
      run_ctx agent repl "$agent" "${session[@]}" "${raw[@]}"
      ;;
    resume) run_ctx agent resume "$agent" "${session[@]}" "${raw[@]}" ;;
    history) run_ctx agent history "$agent" "${session[@]}" ;;
    output) run_ctx agent output "$agent" "${session[@]}" ;;
    pack) run_ctx agent pack "$agent" "${session[@]}" ;;
    tools) run_ctx agent tools "$agent" ;;
    children) run_ctx agent children "$agent" "${session[@]}" ;;
    cancel) run_ctx agent cancel "$agent" "${session[@]}" "${raw[@]}" "$@" ;;
    status) run_ctx agent status "$agent" ;;
    *) die "internal mode error: $MODE" ;;
  esac
}

parse_args "$@"
