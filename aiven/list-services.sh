#!/usr/bin/env bash
# List the services in a project with their plan and state.
set -euo pipefail
# shellcheck source=env.sh
. "$(dirname "$0")/env.sh"

usage() { echo "usage: list-services.sh [options]"; echo; aiven_usage; }

while (($#)); do
  n=0; aiven_opt "$@" || n=$?
  if ((n)); then shift "$n"; continue; fi
  case $1 in
    -h|--help) usage; exit 0 ;;
    *) ft_die "unknown argument: $1" ;;
  esac
done

aiven_init
ft_run avn service list --project "$PROJECT" \
  --format '{service_name} {service_type} {plan} {state}'
