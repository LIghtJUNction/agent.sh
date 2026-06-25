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

exec "$(resolve_ctx)" agent-sh "$@"
