# shellcheck shell=bash
# Shared Cloudflare options. Sourced by the scripts in this folder.
#
# Credentials: the `cf` CLI's own login (`cf auth login`), Wrangler's own
# login, and an AWS-style profile for the R2 S3 API (keys in
# ~/.aws/credentials, never in this repo). Nothing here prints them.

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/common.sh
. "$here/../lib/common.sh"

WRANGLER_VERSION=${WRANGLER_VERSION:-4.161.0}

cf_opt() {
  case $1 in
    --apply) FT_APPLY=1; return 1 ;;
    --dry-run) FT_APPLY=0; return 1 ;;
  esac
  return 0
}

# Wrangler pinned, run through npx rather than installed globally.
# shellcheck disable=SC2034  # used by the scripts that source this
WRANGLER=(npx --yes "wrangler@$WRANGLER_VERSION")
