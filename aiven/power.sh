#!/usr/bin/env bash
# Power services on or off. Power-on waits for RUNNING unless --no-wait.
#
#   power.sh on  SERVICE [SERVICE ...]
#   power.sh off SERVICE [SERVICE ...]
set -euo pipefail
# shellcheck source=env.sh
. "$(dirname "$0")/env.sh"

usage() {
  cat <<'U'
usage: power.sh on|off SERVICE [SERVICE ...] [--no-wait] [--timeout SECONDS]

Powering on returns at once and the service takes minutes to build
(Valkey ~3 min, Kafka up to ~10 on the free plans). By default this waits
for RUNNING with `avn service wait`, bounded by --timeout (default 900).

U
  aiven_usage
}

action='' wait=1 timeout=900 services=()
while (($#)); do
  n=0; aiven_opt "$@" || n=$?
  if ((n)); then shift "$n"; continue; fi
  case $1 in
    on|off) action=$1; shift ;;
    --no-wait) wait=0; shift ;;
    --timeout) timeout=${2:?--timeout needs seconds}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) ft_die "unknown argument: $1" ;;
    *) services+=("$1"); shift ;;
  esac
done
[[ -n $action ]] || { usage; exit 2; }
((${#services[@]})) || services=('<service>')

aiven_init
for s in "${services[@]}"; do
  ft_need "$s" SERVICE
  ft_run avn service update "$s" "--power-$action" --force --project "$PROJECT"
done

if [[ $action == on ]] && ((wait)); then
  ft_run avn service wait "${services[@]}" --timeout "$timeout" --project "$PROJECT"
  ft_note "RUNNING can come a little before new users and ACLs work. Retry the first connect."
fi
