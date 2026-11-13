#!/usr/bin/env bash
# Delete everything in the compartment, then the compartment.
#
# Lists first. Order: instances (with boot volumes), subnets, route rules,
# internet gateways, extra security lists, VCNs, then the compartment.
# Then lists again.
set -euo pipefail
# The loops below split list output on whitespace on purpose: OCIDs never
# contain spaces, and this works on the bash 3.2 that macOS ships.
# shellcheck disable=SC2046
# shellcheck source=env.sh
. "$(dirname "$0")/env.sh"

usage() {
  cat <<'U'
usage: teardown.sh [--compartment-id ID] [--keep-compartment]

The compartment defaults to the one network.sh saved. Deleting a
compartment is asynchronous and can take a while; it fails if anything is
still in it, which is a useful check on its own.

Only point this at a compartment made for this. It deletes every instance
and network in it.

U
  oci_usage
}

oci_load_state
comp=${COMPARTMENT_ID:-<compartment-ocid>} keep=0
while (($#)); do
  n=0; oci_opt "$@" || n=$?
  if ((n)); then shift "$n"; continue; fi
  case $1 in
    --compartment-id) comp=${2:?}; shift 2 ;;
    --keep-compartment) keep=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) ft_die "unknown argument: $1" ;;
  esac
done

oci_init
ft_need "$comp" --compartment-id
[[ $comp != "$TENANCY" ]] || ft_die "refusing to tear down the root compartment"

search_text="query all resources where compartmentId = '$comp' && lifecycleState != 'TERMINATED' && lifecycleState != 'DELETED'"
list_all() {
  "${OCI[@]}" search resource structured-search --query-text "$search_text" \
    --query 'data.items[].{type:"resource-type",name:"display-name",state:"lifecycle-state"}' --output table
}

ft_note "1. what's there (the search index can lag a minute behind)"
ft_step "oci search resource structured-search --query-text \"$search_text\"" list_all

ft_note "2. instances, boot volumes included"
for state in RUNNING STOPPED; do
  for i in $(oci_ids "<instance-ocid-$state>" compute instance list -c "$comp" --lifecycle-state "$state"); do
    ft_run "${OCI[@]}" compute instance terminate --instance-id "$i" \
      --preserve-boot-volume false --force --wait-for-state TERMINATED
  done
done

ft_note "3. network"
for s in $(oci_ids '<subnet-ocid>' network subnet list -c "$comp"); do
  ft_run "${OCI[@]}" network subnet delete --subnet-id "$s" --force --wait-for-state TERMINATED
done

for v in $(oci_ids '<vcn-ocid>' network vcn list -c "$comp"); do
  rt=$(ft_capture '<vcn-default-route-table>' "${OCI[@]}" network vcn get --vcn-id "$v" \
    --query 'data."default-route-table-id"' --raw-output)
  sl_default=$(ft_capture '<vcn-default-security-list>' "${OCI[@]}" network vcn get --vcn-id "$v" \
    --query 'data."default-security-list-id"' --raw-output)
  ft_run_quiet "${OCI[@]}" network route-table update --rt-id "$rt" --route-rules '[]' --force

  for g in $(oci_ids '<igw-ocid>' network internet-gateway list -c "$comp" --vcn-id "$v"); do
    ft_run "${OCI[@]}" network internet-gateway delete --ig-id "$g" --force --wait-for-state TERMINATED
  done
  for l in $(oci_ids '<seclist-ocid>' network security-list list -c "$comp" --vcn-id "$v"); do
    [[ $l != "$sl_default" ]] || continue
    ft_run "${OCI[@]}" network security-list delete --security-list-id "$l" --force --wait-for-state TERMINATED
  done
  ft_run "${OCI[@]}" network vcn delete --vcn-id "$v" --force --wait-for-state TERMINATED
done

ft_note "4. anything left over (block storage past 200 GB is billed)"
ft_run "${OCI[@]}" bv volume list -c "$comp" --lifecycle-state AVAILABLE \
  --query 'data[].{name:"display-name",gb:"size-in-gbs"}' --output table
# shellcheck disable=SC2016  # JMESPath backticks, not shell
ft_run "${OCI[@]}" bv boot-volume list -c "$comp" \
  --query 'data[?"lifecycle-state"!=`TERMINATED`].{name:"display-name",gb:"size-in-gbs"}' --output table

if ((keep)); then
  ft_note "5. keeping the compartment"
else
  ft_note "5. the compartment itself (asynchronous; fails if anything is left)"
  ft_run "${OCI[@]}" iam compartment delete --compartment-id "$comp" --force
  if ((FT_APPLY)) && [[ -f $STATE_FILE ]]; then
    : >"$STATE_FILE"
  fi
fi

ft_note "6. check: the search should come back empty, apart from the compartment while it deletes"
ft_step "oci search resource structured-search --query-text \"$search_text\"" list_all
