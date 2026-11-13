#!/usr/bin/env bash
# Tear down the container Worker and, optionally, one run's R2 prefix,
# then check by listing. Don't trust exit codes: a non-interactive delete
# without --force can print "Aborted." and exit 0 having done nothing.
set -euo pipefail
# shellcheck source=env.sh
. "$(dirname "$0")/env.sh"

usage() {
  cat <<'U'
usage: teardown.sh [--worker NAME] [--application-id ID ...] [--image NAME:TAG]
                   [--bucket NAME --run-id ID [--profile r2-tests]]

Container applications are deleted by ID. Run it once without IDs to see
the list (it prints `cf containers applications list --name WORKER`), then
again with --application-id for each one.

With --bucket and --run-id it also deletes runs/<run-id>/ and checks the
prefix lists empty. Only delete a prefix for a run that passed; keep a
failed one to look at, and clean it before it eats the budget.

U
  ft_common_usage
}

worker='' image='' bucket='' run='' profile=${AWS_PROFILE:-r2-tests} apps=()
while (($#)); do
  n=0; cf_opt "$@" || n=$?
  if ((n)); then shift "$n"; continue; fi
  case $1 in
    --worker) worker=${2:?}; shift 2 ;;
    --application-id) apps+=("${2:?}"); shift 2 ;;
    --image) image=${2:?}; shift 2 ;;
    --bucket) bucket=${2:?}; shift 2 ;;
    --run-id) run=${2:?}; shift 2 ;;
    --profile) profile=${2:?}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) ft_die "unknown argument: $1" ;;
  esac
done
if [[ -z $worker$image$bucket ]] && ! ((FT_APPLY)); then
  worker='<worker>' image='<image>:<tag>' bucket='<bucket>' run='<run-id>'
  apps=('<application-id>')
fi

ft_banner
ft_need_cmd cf
failed=0

if [[ -n $worker ]]; then
  ft_run cf containers applications list --name "$worker"
  for a in ${apps[@]+"${apps[@]}"}; do
    ft_run cf containers applications delete "$a" --force
  done
  ft_run cf workers delete "$worker" --force
fi
if [[ -n $image ]]; then
  ft_run cf containers images delete "$image" --force
fi

ft_note "check: these lists should no longer show what you deleted"
[[ -n $worker ]] && ft_run cf containers applications list --name "$worker"
ft_run cf containers images list

prefix_empty() {
  local left
  left=$(aws s3api list-objects-v2 --bucket "$bucket" --prefix "runs/$run/" \
    --profile "$profile" --query 'KeyCount' --output text)
  if [[ $left == 0 ]]; then
    echo "verified: runs/$run/ is empty"
  else
    echo "runs/$run/ still has $left objects" >&2
    failed=1
  fi
}
if [[ -n $bucket ]]; then
  ft_need "$run" --run-id
  [[ $run == */* ]] && ft_die "--run-id can't contain a slash"
  ft_run aws s3 rm "s3://$bucket/runs/$run/" --recursive --profile "$profile"
  ft_step "aws s3api list-objects-v2 --bucket $bucket --prefix runs/$run/ --profile $profile --query KeyCount   # expect 0" prefix_empty
fi
exit "$failed"
