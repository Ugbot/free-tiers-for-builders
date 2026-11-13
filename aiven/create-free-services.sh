#!/usr/bin/env bash
# Create services on their free plans only. Idempotent: an existing service
# with the same name is left alone (--no-fail-if-exists).
#
#   create-free-services.sh --cloud <cloud> NAME:TYPE [NAME:TYPE ...]
#   TYPE is one of: pg mysql kafka valkey opensearch
set -euo pipefail
# shellcheck source=env.sh
. "$(dirname "$0")/env.sh"

usage() {
  cat <<'U'
usage: create-free-services.sh --cloud CLOUD NAME:TYPE [NAME:TYPE ...]

TYPE and the free plan it gets:
  pg free-1-1gb   mysql free-1-1gb   kafka free-0   valkey free-1   opensearch free-4-20

Pick a cloud near your clients from the ones the free plans offer
(`avn cloud list`). Anything that isn't a free plan is refused.

U
  aiven_usage
}

free_plan() {
  case $1 in
    pg|mysql) echo free-1-1gb ;;
    kafka) echo free-0 ;;
    valkey) echo free-1 ;;
    opensearch) echo free-4-20 ;;
    *) return 1 ;;
  esac
}

CLOUD='<cloud>'
specs=()
while (($#)); do
  n=0; aiven_opt "$@" || n=$?
  if ((n)); then shift "$n"; continue; fi
  case $1 in
    --cloud) CLOUD=${2:?--cloud needs a value}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) ft_die "unknown argument: $1" ;;
    *) specs+=("$1"); shift ;;
  esac
done
((${#specs[@]})) || specs=('<service>:pg')

aiven_init
ft_need "$CLOUD" --cloud
for spec in "${specs[@]}"; do
  name=${spec%%:*} type=${spec#*:}
  plan=$(free_plan "$type") || ft_die "no free plan for type '$type'"
  ft_run avn service create "$name" -t "$type" -p "$plan" --cloud "$CLOUD" \
    --project "$PROJECT" --no-fail-if-exists
done
ft_note "creation is asynchronous: run wait-running.sh next."
