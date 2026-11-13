#!/usr/bin/env bash
# Refuse an upload that would take the bucket past a size cap.
# Run it before the first byte goes up, every time.
#
# Exit codes: 0 fits, 3 refused, 2 usage error.
set -euo pipefail
# shellcheck source=env.sh
. "$(dirname "$0")/env.sh"

usage() {
  cat <<'U'
usage: r2-budget-check.sh --bucket NAME --planned-bytes N
                          [--budget-bytes N] [--profile r2-tests]
                          [--used-bytes N]

Measures the bucket (ListObjectsV2 over the whole bucket, paged to the end,
summing Size) and checks used + planned <= budget. The budget defaults to
5 GiB, or R2_BUDGET_BYTES.

--used-bytes skips the listing, for testing the rule offline.

U
  ft_common_usage
}

bucket='<bucket>' planned='' used='' profile=${AWS_PROFILE:-r2-tests}
budget=${R2_BUDGET_BYTES:-$((5 * 1024 * 1024 * 1024))}
while (($#)); do
  n=0; cf_opt "$@" || n=$?
  if ((n)); then shift "$n"; continue; fi
  case $1 in
    --bucket) bucket=${2:?}; shift 2 ;;
    --planned-bytes) planned=${2:?}; shift 2 ;;
    --budget-bytes) budget=${2:?}; shift 2 ;;
    --used-bytes) used=${2:?}; shift 2 ;;
    --profile) profile=${2:?}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) ft_die "unknown argument: $1" ;;
  esac
done

is_int() { [[ $1 =~ ^[0-9]+$ ]]; }
is_int "${planned:-x}" || ft_die "--planned-bytes must be a whole number of bytes"
is_int "$budget" || ft_die "--budget-bytes must be a whole number of bytes"

measure() {
  aws s3api list-objects-v2 --bucket "$bucket" --profile "$profile" \
    --query 'Contents[].Size' --output text \
    | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) s += $i } END { printf "%d\n", s }'
}

if [[ -z $used ]]; then
  ft_banner
  ft_need "$bucket" --bucket
  ft_need_cmd aws
  if ((FT_APPLY)); then
    used=$(measure)
  else
    printf '%s\n' "aws s3api list-objects-v2 --bucket $bucket --profile $profile --query 'Contents[].Size' --output text | <sum>" >&3
    ft_note "then refuse if used + $planned > $budget"
    exit 0
  fi
fi
is_int "$used" || ft_die "--used-bytes must be a whole number of bytes"

total=$((used + planned))
if ((total > budget)); then
  echo "refused: used $used + planned $planned = $total bytes would exceed the budget of $budget" >&2
  exit 3
fi
echo "ok: used $used + planned $planned = $total of $budget bytes"
