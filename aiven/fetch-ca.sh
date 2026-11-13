#!/usr/bin/env bash
# Download the project CA. Kafka, PostgreSQL, MySQL and OpenSearch verify
# against it. Valkey verifies against the system trust store instead.
set -euo pipefail
# shellcheck source=env.sh
. "$(dirname "$0")/env.sh"

usage() {
  echo "usage: fetch-ca.sh --out DIR"
  echo
  echo "Writes DIR/<project>-ca.pem. DIR is created 0700."
  echo
  aiven_usage
}

out='<dir>'
while (($#)); do
  n=0; aiven_opt "$@" || n=$?
  if ((n)); then shift "$n"; continue; fi
  case $1 in
    --out) out=${2:?--out needs a directory}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) ft_die "unknown argument: $1" ;;
  esac
done

aiven_init
ft_need "$out" --out
ft_private_dir "$out"
ft_run avn project ca-get --project "$PROJECT" --target-filepath "$out/$PROJECT-ca.pem"
