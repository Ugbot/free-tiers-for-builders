#!/usr/bin/env bash
# Mint temporary S3 credentials that can only touch one run's prefix.
# They expire after the TTL whether you remember or not.
set -euo pipefail
# shellcheck source=env.sh
. "$(dirname "$0")/env.sh"

usage() {
  cat <<'U'
usage: r2-temp-creds.sh --bucket NAME --parent-access-key-id ID --run-id ID
                        --out FILE [--ttl-seconds 3600] [--read-only]

Scopes the credentials to runs/<run-id>/ in the bucket. The response goes
to FILE, created 0600, and is never printed. --env also writes FILE.env
with AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_SESSION_TOKEN, for
a child process to source.

U
  ft_common_usage
}

bucket='<bucket>' parent='<access-key-id>' run='<run-id>' out='<dir>/r2-creds.json'
ttl=3600 perm=object-read-write want_env=0
while (($#)); do
  n=0; cf_opt "$@" || n=$?
  if ((n)); then shift "$n"; continue; fi
  case $1 in
    --bucket) bucket=${2:?}; shift 2 ;;
    --parent-access-key-id) parent=${2:?}; shift 2 ;;
    --run-id) run=${2:?}; shift 2 ;;
    --out) out=${2:?}; shift 2 ;;
    --ttl-seconds) ttl=${2:?}; shift 2 ;;
    --read-only) perm=object-read-only; shift ;;
    --env) want_env=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) ft_die "unknown argument: $1" ;;
  esac
done

ft_banner
for pair in "$bucket:--bucket" "$parent:--parent-access-key-id" "$run:--run-id" "$out:--out"; do
  ft_need "${pair%:*}" "${pair##*:}"
done
ft_need_cmd cf jq
ft_note "preview without sending: add --dry-run to the cf command below (cf's own flag)"
ft_to_file "$out" cf r2 temporary-credentials create --bucket "$bucket" \
  --parent-access-key-id "$parent" --permission "$perm" \
  --prefixes "runs/$run/" --ttl-seconds "$ttl"

to_env() {
  (umask 077 && jq -r '(.result // .) |
    "AWS_ACCESS_KEY_ID=\(.accessKeyId)\nAWS_SECRET_ACCESS_KEY=\(.secretAccessKey)\nAWS_SESSION_TOKEN=\(.sessionToken)"' \
    "$out" >"$out.env")
  chmod 600 "$out.env"
  grep -q '=null$' "$out.env" && { : >"$out.env"; ft_die "unexpected response shape in $out; inspect it yourself"; }
  return 0
}
if ((want_env)); then
  ft_step "jq <keys> $out > $out.env   # 0600, never printed" to_env
fi
