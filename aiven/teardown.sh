#!/usr/bin/env bash
# Power services off, then check that they are off.
#
#   teardown.sh SERVICE [SERVICE ...]
#   teardown.sh --all           every service in the project that is RUNNING
#
# Power-off keeps the service and its data and stops it using resources.
# Deleting a service is `avn service terminate`, deliberately not here.
set -euo pipefail
# shellcheck source=env.sh
. "$(dirname "$0")/env.sh"

usage() {
  cat <<'U'
usage: teardown.sh SERVICE [SERVICE ...] | --all [--checks N]

Run it when the tests pass and when they fail. After powering off it lists
the services again, up to N times 15 s apart (default 20), and exits
non-zero if any of them is still RUNNING.

U
  aiven_usage
}

all=0 checks=20 services=()
while (($#)); do
  n=0; aiven_opt "$@" || n=$?
  if ((n)); then shift "$n"; continue; fi
  case $1 in
    --all) all=1; shift ;;
    --checks) checks=${2:?}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) ft_die "unknown argument: $1" ;;
    *) services+=("$1"); shift ;;
  esac
done

aiven_init

running() {
  avn service list --project "$PROJECT" --json \
    | jq -r '.[] | select(.state != "POWEROFF") | .service_name'
}

if ((all)); then
  if ((FT_APPLY)); then
    while IFS= read -r s; do services+=("$s"); done < <(running)
  else
    ft_note "with --apply: services = every service not already POWEROFF"
    printf '%s\n' "avn service list --project $PROJECT --json | jq '.[] | select(.state != \"POWEROFF\") | .service_name'" >&3
    services=('<service>')
  fi
fi
((${#services[@]})) || { ft_note "nothing to power off"; exit 0; }

for s in "${services[@]}"; do
  ft_run avn service update "$s" --power-off --force --project "$PROJECT"
done

verify() {
  local i left
  for ((i = 1; i <= checks; i++)); do
    left=$(running | grep -Fx -f <(printf '%s\n' "${services[@]}") || true)
    if [[ -z $left ]]; then
      echo "verified: all powered off"
      return 0
    fi
    sleep 15
  done
  echo "still not POWEROFF:" >&2
  printf '  %s\n' "$left" >&2
  return 1
}
ft_step "avn service list --project $PROJECT --format '{service_name} {state}'   # repeat until every one reads POWEROFF" verify
