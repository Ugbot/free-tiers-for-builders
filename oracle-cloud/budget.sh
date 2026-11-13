#!/usr/bin/env bash
# A budget with email alerts, before you create anything else.
# Alerts at 50/80/100% of actual spend and 100% of forecast. A budget is an
# alert, not a cap: it emails you, it switches nothing off.
set -euo pipefail
# shellcheck source=env.sh
. "$(dirname "$0")/env.sh"

usage() {
  cat <<'U'
usage: budget.sh --email ADDRESS [--amount 50] [--name builders-budget]

The budget lives in the root compartment (the tenancy) and covers it all.

U
  oci_usage
}

email='<you@example.com>' amount=50 name=builders-budget
while (($#)); do
  n=0; oci_opt "$@" || n=$?
  if ((n)); then shift "$n"; continue; fi
  case $1 in
    --email) email=${2:?}; shift 2 ;;
    --amount) amount=${2:?}; shift 2 ;;
    --name) name=${2:?}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) ft_die "unknown argument: $1" ;;
  esac
done

oci_init
ft_need "$email" --email

budget=$(ft_capture '<budget-ocid>' "${OCI[@]}" budgets budget budget create -c "$TENANCY" \
  --amount "$amount" --reset-period MONTHLY \
  --target-type COMPARTMENT --targets "[\"$TENANCY\"]" \
  --display-name "$name" --query data.id --raw-output)

for t in 50 80 100; do
  ft_run_quiet "${OCI[@]}" budgets budget alert-rule create --budget-id "$budget" \
    --type ACTUAL --threshold "$t" --threshold-type PERCENTAGE --recipients "$email"
done
ft_run_quiet "${OCI[@]}" budgets budget alert-rule create --budget-id "$budget" \
  --type FORECAST --threshold 100 --threshold-type PERCENTAGE --recipients "$email"
ft_note "the forecast alert is the useful one: it warns while a mistake still hasn't cost anything."
