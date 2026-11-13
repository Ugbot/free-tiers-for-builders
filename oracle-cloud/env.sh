# shellcheck shell=bash
# Shared OCI options. Sourced by the scripts in this folder.
#
# Credentials are the OCI CLI's own: ~/.oci/config and the API signing key
# it points at, made by `oci setup config`. Nothing here reads the key or
# prints the config.

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/common.sh
. "$here/../lib/common.sh"

OCI_PROFILE=${OCI_CLI_PROFILE:-DEFAULT}
OCI_CONFIG=${OCI_CLI_CONFIG_FILE:-$HOME/.oci/config}
TENANCY='<tenancy-ocid>'

# The CLI prints SyntaxWarnings from its own code on newer Pythons. They
# are harmless, but they go to stderr; silence them so they don't read as
# failures.
export PYTHONWARNINGS=${PYTHONWARNINGS:-ignore::SyntaxWarning}

oci_usage() {
  cat <<'EOT'
OCI options:
  --profile NAME   profile in ~/.oci/config (or OCI_CLI_PROFILE; default DEFAULT)
EOT
  ft_common_usage
}

oci_opt() {
  case $1 in
    --apply) FT_APPLY=1; return 1 ;;
    --dry-run) FT_APPLY=0; return 1 ;;
    --profile) OCI_PROFILE=${2:?--profile needs a name}; return 2 ;;
  esac
  return 0
}

# Read one key of the chosen profile from the config file.
oci_config_value() {
  awk -v want="[$OCI_PROFILE]" -v key="$1" '
    /^\[/ { in_p = ($0 == want); next }
    in_p { split($0, kv, "="); k = kv[1]; gsub(/[ \t]/, "", k)
           if (k == key) { v = substr($0, index($0, "=") + 1); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit } }
  ' "$OCI_CONFIG"
}

oci_init() {
  ft_banner
  ft_need_cmd oci jq
  OCI=(oci --profile "$OCI_PROFILE")
  if ((FT_APPLY)); then
    [[ -f $OCI_CONFIG ]] || ft_die "no OCI config at $OCI_CONFIG; run: oci setup config"
    TENANCY=$(oci_config_value tenancy)
    [[ -n $TENANCY ]] || ft_die "no tenancy in profile [$OCI_PROFILE] of $OCI_CONFIG"
  fi
}

# The CLI with the chosen profile. Set by oci_init, after options are parsed.
OCI=(oci)

# Freeform tag keys can't contain dots ("contains forbidden characters").
# shellcheck disable=SC2034  # used by the scripts that source this
TAGS='{"purpose":"free_tier","managed_by":"free_tiers_for_builders"}'
oci_check_tags() {
  if jq -e 'keys | map(select(test("[.]"))) | length > 0' <<<"$1" >/dev/null; then
    ft_die "tag keys can't contain dots in OCI: $1"
  fi
}

# Print the IDs a list query returns, one per line. In a dry run, print
# the query and return the placeholder instead.
#   for id in $(oci_ids '<instance-ocid>' compute instance list -c "$C"); do
oci_ids() {
  local placeholder=$1 out
  shift
  out=$(ft_capture "$placeholder" "${OCI[@]}" "$@" --all --query 'data[].id' --raw-output)
  if ((FT_APPLY)); then
    [[ -n $out ]] && jq -r '.[]?' <<<"$out"
    return 0
  fi
  printf '%s\n' "$out"
}

# IDs from earlier steps live here, 0600 and git-ignored.
STATE_FILE="$here/state.env"
oci_save_state() {
  ((FT_APPLY)) || return 0
  (umask 077 && printf '%s=%s\n' "$1" "$2" >>"$STATE_FILE")
}
oci_load_state() {
  # shellcheck disable=SC1090
  [[ -f $STATE_FILE ]] && . "$STATE_FILE"
  return 0
}
