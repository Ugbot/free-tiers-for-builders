#!/usr/bin/env bash
# Check the CLI config before anything else.
#
# A region the tenancy isn't subscribed to fails with 401 NotAuthenticated,
# which looks like a bad key. It isn't. This compares the config's region
# with the regions the tenancy is subscribed to.
set -euo pipefail
# shellcheck source=env.sh
. "$(dirname "$0")/env.sh"

usage() {
  echo "usage: check-config.sh [--try-region REGION] [options]"
  echo
  echo "--try-region sends the check to another region, to tell a wrong region from a bad key."
  echo
  oci_usage
}

try_region=

while (($#)); do
  n=0; oci_opt "$@" || n=$?
  if ((n)); then shift "$n"; continue; fi
  case $1 in
    --try-region) try_region=${2:?}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) ft_die "unknown argument: $1" ;;
  esac
done

oci_init

check() {
  local region list home
  region=$(oci_config_value region)
  echo "config region: ${region:-<none>}  (profile $OCI_PROFILE)"
  if ! list=$("${OCI[@]}" iam region-subscription list --tenancy-id "$TENANCY" ${try_region:+--region "$try_region"}); then
    cat >&2 <<'MSG'
The call failed. If it was 401 NotAuthenticated, the key may well be fine:
a region the tenancy isn't subscribed to fails exactly like a bad signature.
Re-run with --try-region <your-home-region>. If that works, set region= in
the config to it.
MSG
    return 1
  fi
  jq -r '.data[] | "\(."region-name")  \(.status)\(if ."is-home-region" then "  (home)" else "" end)"' <<<"$list"
  home=$(jq -r '.data[] | select(."is-home-region") | ."region-name"' <<<"$list")
  if jq -e --arg r "$region" '.data | map(."region-name") | index($r) != null' <<<"$list" >/dev/null; then
    echo "ok: $region is subscribed (home: $home)"
  else
    echo "problem: $region is not subscribed. Set region=$home in $OCI_CONFIG." >&2
    return 1
  fi
}

ft_step "oci iam region-subscription list --tenancy-id <tenancy-ocid>   # compare with region= in $OCI_CONFIG" check
