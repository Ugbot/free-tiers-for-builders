#!/usr/bin/env bash
# Create one R2 bucket for tests and print the S3 profile to use with it.
set -euo pipefail
# shellcheck source=env.sh
. "$(dirname "$0")/env.sh"

usage() {
  cat <<'U'
usage: r2-bucket.sh --bucket NAME [--location-hint weur] [--account-id ID]

The location hint is only honoured the first time a bucket name is created.
Choose it once.

For the S3 API, make an R2 API token in the dashboard scoped to this one
bucket, and put its access key and secret in ~/.aws/credentials under the
profile printed below. Not in this repo, not in your shell history.

U
  ft_common_usage
}

bucket='<bucket>' hint=weur account='<account-id>'
while (($#)); do
  n=0; cf_opt "$@" || n=$?
  if ((n)); then shift "$n"; continue; fi
  case $1 in
    --bucket) bucket=${2:?}; shift 2 ;;
    --location-hint) hint=${2:?}; shift 2 ;;
    --account-id) account=${2:?}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) ft_die "unknown argument: $1" ;;
  esac
done

ft_banner
ft_need "$bucket" --bucket
ft_need_cmd cf
ft_run cf r2 buckets create --name "$bucket" --location-hint "$hint"
ft_run cf r2 buckets list --name-contains "$bucket"

cat >&3 <<P
# Add to ~/.aws/config (no secrets in this part):
#   [profile r2-tests]
#   region = auto
#   endpoint_url = https://$account.r2.cloudflarestorage.com
# Then: aws s3 ls s3://$bucket/ --profile r2-tests
P
