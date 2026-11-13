#!/usr/bin/env bash
# Build, push and deploy the container template. Needs Workers Paid.
#
# Order matters: the first call is a cheap containers call, so a plan gate
# shows up in seconds, not after the build and push.
set -euo pipefail
# shellcheck source=env.sh
. "$(dirname "$0")/env.sh"

usage() {
  cat <<'U'
usage: deploy.sh --worker NAME --account-id ID --image NAME --tag TAG
                 --token-file PATH [--instance-type standard-1]

--token-file is the per-run bearer token, a 0600 file. Make one with:
  (umask 077 && openssl rand -hex 32 > PATH)
It is sent to Wrangler on stdin as the RUN_TOKEN secret, never printed.

Instance types run from lite to standard-4 (4 vCPU, 12 GiB, 20 GB). Billing
is for provisioned memory and disk plus active CPU, so use the smallest one
that does the job.

U
  ft_common_usage
}

worker='<worker>' account='<account-id>' image='<image>' tag='<tag>'
token_file='<token-file>' itype=standard-1
while (($#)); do
  n=0; cf_opt "$@" || n=$?
  if ((n)); then shift "$n"; continue; fi
  case $1 in
    --worker) worker=${2:?}; shift 2 ;;
    --account-id) account=${2:?}; shift 2 ;;
    --image) image=${2:?}; shift 2 ;;
    --tag) tag=${2:?}; shift 2 ;;
    --token-file) token_file=${2:?}; shift 2 ;;
    --instance-type) itype=${2:?}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) ft_die "unknown argument: $1" ;;
  esac
done

ft_banner
for pair in "$worker:--worker" "$account:--account-id" "$image:--image" \
            "$tag:--tag" "$token_file:--token-file"; do
  ft_need "${pair%:*}" "${pair##*:}"
done
ft_need_cmd npx docker sed
((FT_APPLY)) && ft_secret_file "$token_file"

dir="$here/container-template"
config="$dir/wrangler.jsonc"

ft_note "1. plan gate: fails fast without Workers Paid"
ft_run "${WRANGLER[@]}" containers list

ft_note "2. build for amd64 and push"
ft_run docker build --platform linux/amd64 -t "$image:$tag" "$dir"
ft_run "${WRANGLER[@]}" containers push "$image:$tag"

render() {
  sed -e "s|<worker>|$worker|" -e "s|<account-id>|$account|" \
      -e "s|<image>|$image|" -e "s|<tag>|$tag|" -e "s|<instance-type>|$itype|" \
      "$dir/wrangler.template.jsonc" >"$config"
}
ft_note "3. config and deploy"
ft_step "render $dir/wrangler.template.jsonc > $config" render
ft_run "${WRANGLER[@]}" deploy --config "$config"

put_secret() { "${WRANGLER[@]}" secret put RUN_TOKEN --config "$config" <"$token_file"; }
ft_step "${WRANGLER[*]} secret put RUN_TOKEN --config $config < $token_file   # never printed" put_secret

ft_note "start a runner:  curl -X POST -H \"Authorization: Bearer \$(cat $token_file)\" https://$worker.<subdomain>.workers.dev/runners/r1/start"
ft_note "when done: teardown.sh --worker $worker --image $image:$tag"
