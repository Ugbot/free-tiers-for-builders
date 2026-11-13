#!/usr/bin/env bash
# Wait, bounded, until services report RUNNING.
set -euo pipefail
# shellcheck source=env.sh
. "$(dirname "$0")/env.sh"

usage() {
  echo "usage: wait-running.sh SERVICE [SERVICE ...] [--timeout SECONDS]"
  echo
  echo "Polls until RUNNING or the timeout (default 900 s). Exits non-zero on timeout."
  echo "If this process dies, nothing is lost: just run it again."
  echo
  aiven_usage
}

timeout=900 services=()
while (($#)); do
  n=0; aiven_opt "$@" || n=$?
  if ((n)); then shift "$n"; continue; fi
  case $1 in
    --timeout) timeout=${2:?--timeout needs seconds}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) ft_die "unknown argument: $1" ;;
    *) services+=("$1"); shift ;;
  esac
done
((${#services[@]})) || services=('<service>')

aiven_init
ft_run avn service wait "${services[@]}" --timeout "$timeout" --project "$PROJECT"
