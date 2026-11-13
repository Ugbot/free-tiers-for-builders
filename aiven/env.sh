# shellcheck shell=bash
# Shared Aiven options. Sourced by the scripts in this folder.
#
# Credentials come from, in order:
#   --token-file PATH   a 0600 file holding an API token
#   AIVEN_AUTH_TOKEN    already in the environment
#   avn's own login     from `avn user login`
# The token is never printed.

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/common.sh
. "$here/../lib/common.sh"

PROJECT=${AIVEN_PROJECT:-<project>}
TOKEN_FILE=

aiven_usage() {
  cat <<'EOF'
Aiven options:
  --project NAME      Aiven project (or AIVEN_PROJECT)
  --token-file PATH   0600 file with an API token (else AIVEN_AUTH_TOKEN or avn login)
EOF
  ft_common_usage
}

# Consume one common option. Returns the number of words used (0 if none).
aiven_opt() {
  case $1 in
    --apply) FT_APPLY=1; return 1 ;;
    --dry-run) FT_APPLY=0; return 1 ;;
    --project) PROJECT=${2:?--project needs a value}; return 2 ;;
    --token-file) TOKEN_FILE=${2:?--token-file needs a path}; return 2 ;;
  esac
  return 0
}

aiven_init() {
  ft_banner
  ft_need "$PROJECT" --project
  ft_need_cmd avn jq
  if [[ -n $TOKEN_FILE ]]; then
    ft_note "token: read from $TOKEN_FILE into AIVEN_AUTH_TOKEN (not printed)"
    if ((FT_APPLY)); then
      ft_secret_file "$TOKEN_FILE"
      AIVEN_AUTH_TOKEN=$(<"$TOKEN_FILE")
      export AIVEN_AUTH_TOKEN
    fi
  fi
}
