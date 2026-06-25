#!/usr/bin/env bash
set -euo pipefail

SESSION=${CORTEX_SESSION:-}
MODE=auto
RAW=0
CTX_BIN=${CTX_BIN:-}

err(){ printf 'agent.sh %s\n' "$*" >&2; }
die(){ err "$*"; exit 1; }

usage(){
  cat <<'EOF_USAGE'
usage:
  agent.sh [--session SESSION] AGENT
  agent.sh [--session SESSION] AGENT INPUT...
  agent.sh --chat AGENT
  agent.sh --resume AGENT
  agent.sh --history AGENT
  agent.sh --pack AGENT
  agent.sh --tools AGENT
  agent.sh --children AGENT
  agent.sh --cancel AGENT [RUN]
  agent.sh --status AGENT
  agent.sh --raw AGENT "prompt"

agent.sh is a compatibility wrapper over ctx agent commands.
With no INPUT, it attaches to the agent terminal.
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

resolve_ctx(){
  if [[ -n $CTX_BIN ]]; then
    [[ -x $CTX_BIN ]] || die "CTX_BIN is not executable: $CTX_BIN"
    printf '%s\n' "$CTX_BIN"
    return
  fi

  local script_dir candidate
  script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
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

run_ctx(){
  local -a args=("$@")
  local ctx_bin
  ctx_bin=$(resolve_ctx)
  exec "$ctx_bin" "${args[@]}"
}

ctx_command(){
  local ctx_bin
  ctx_bin=$(resolve_ctx)
  "$ctx_bin" "$@"
}

attach_or_start_terminal(){
  local agent=$1
  shift
  local -a session=("$@")
  if ctx_command agent attach "$agent" "${session[@]}"; then
    return 0
  fi
  err "terminal is not running; starting agent terminal"
  ctx_command agent start "$agent" "${session[@]}"
  exec "$(resolve_ctx)" agent attach "$agent" "${session[@]}"
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
      --chat|--repl) MODE=repl; shift ;;
      --attach) MODE=attach; shift ;;
      --watch) MODE=watch; shift ;;
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
    auto)
      if [[ $# -gt 0 ]]; then
        run_ctx agent send "$agent" "${session[@]}" "${raw[@]}" "$*"
      fi
      if [[ -t 0 ]]; then
        attach_or_start_terminal "$agent" "${session[@]}"
      fi
      run_ctx agent repl "$agent" "${session[@]}" "${raw[@]}"
      ;;
    repl)
      if [[ $# -gt 0 ]]; then
        run_ctx agent send "$agent" "${session[@]}" "${raw[@]}" "$*"
      fi
      run_ctx agent repl "$agent" "${session[@]}" "${raw[@]}"
      ;;
    attach) attach_or_start_terminal "$agent" "${session[@]}" ;;
    watch) run_ctx agent watch "$agent" "${session[@]}" ;;
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
