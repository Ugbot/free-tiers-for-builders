#!/usr/bin/env bash
# Launch an Ampere A1 box inside the Always Free allowance, retrying
# across availability domains when a host is out of capacity.
set -euo pipefail
# shellcheck source=env.sh
. "$(dirname "$0")/env.sh"

# Always Free A1, per Oracle's page on 13 November 2026: 1,500 OCPU hours
# and 9,000 GB hours a month, which is 2 OCPUs and 12 GB all month.
# Older guides say 4 and 24. Check the page; this refuses anything above it.
MAX_OCPUS=2 MAX_MEMORY_GB=12 MAX_BOOT_GB=200

usage() {
  cat <<U
usage: launch-a1.sh --ssh-key PATH.pub [--ocpus 2] [--memory-gb 12]
                    [--boot-gb 100] [--name builders-a1]
                    [--rounds 3] [--backoff-seconds 300]
                    [--compartment-id ID] [--subnet-id ID]

Compartment and subnet default to the ones network.sh saved.
The limits across ALL your A1 instances are $MAX_OCPUS OCPUs and $MAX_MEMORY_GB GB, and
boot plus block volumes share $MAX_BOOT_GB GB. This checks one instance, not
your total: if you already have an A1 box, a second one is billed.

On "Out of host capacity" it tries the next AD, and after each pass over
all of them waits --backoff-seconds before the next round. It doesn't
hammer one AD in a loop.

U
  oci_usage
}

oci_load_state
comp=${COMPARTMENT_ID:-<compartment-ocid>} subnet=${SUBNET_ID:-<subnet-ocid>}
key='<ssh-public-key>' ocpus=$MAX_OCPUS mem=$MAX_MEMORY_GB boot=100
name=builders-a1 rounds=3 backoff=300
while (($#)); do
  n=0; oci_opt "$@" || n=$?
  if ((n)); then shift "$n"; continue; fi
  case $1 in
    --ssh-key) key=${2:?}; shift 2 ;;
    --ocpus) ocpus=${2:?}; shift 2 ;;
    --memory-gb) mem=${2:?}; shift 2 ;;
    --boot-gb) boot=${2:?}; shift 2 ;;
    --name) name=${2:?}; shift 2 ;;
    --rounds) rounds=${2:?}; shift 2 ;;
    --backoff-seconds) backoff=${2:?}; shift 2 ;;
    --compartment-id) comp=${2:?}; shift 2 ;;
    --subnet-id) subnet=${2:?}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) ft_die "unknown argument: $1" ;;
  esac
done

oci_init
ft_need "$comp" --compartment-id
ft_need "$subnet" --subnet-id
ft_need "$key" --ssh-key
((ocpus >= 1 && ocpus <= MAX_OCPUS)) || ft_die "--ocpus $ocpus is outside the free allowance (1..$MAX_OCPUS)"
((mem >= 1 && mem <= MAX_MEMORY_GB)) || ft_die "--memory-gb $mem is outside the free allowance (1..$MAX_MEMORY_GB)"
((boot >= 50 && boot <= MAX_BOOT_GB)) || ft_die "--boot-gb must be 50..$MAX_BOOT_GB"
if ((FT_APPLY)); then
  [[ $key == *.pub && -f $key ]] || ft_die "--ssh-key must be an existing .pub file"
fi
oci_check_tags "$TAGS"

image=$(ft_capture '<image-ocid>' "${OCI[@]}" compute image list -c "$TENANCY" \
  --operating-system "Canonical Ubuntu" --operating-system-version "24.04" \
  --shape VM.Standard.A1.Flex --sort-by TIMECREATED --limit 1 \
  --query 'data[0].id' --raw-output)

ads_json=$(ft_capture '["<ad-1>","<ad-2>"]' "${OCI[@]}" iam availability-domain list -c "$TENANCY" \
  --query 'data[].name' --raw-output)
ads=()
while IFS= read -r ad; do ads+=("$ad"); done < <(jq -r '.[]' <<<"$ads_json")
((${#ads[@]})) || ft_die "no availability domains returned"

ft_note "free allowance is not the service limit: resource-availability shows the limit, and anything between is billed."

launch_in() {
  "${OCI[@]}" compute instance launch -c "$comp" --availability-domain "$1" \
    --shape VM.Standard.A1.Flex --shape-config "{\"ocpus\":$ocpus,\"memoryInGBs\":$mem}" \
    --image-id "$image" --subnet-id "$subnet" --assign-public-ip true \
    --boot-volume-size-in-gbs "$boot" --ssh-authorized-keys-file "$key" \
    --user-data-file "$here/cloud-init.yaml" --display-name "$name" \
    --freeform-tags "$TAGS" --wait-for-state RUNNING \
    --query 'data.id' --raw-output
}

if ! ((FT_APPLY)); then
  printf '%s\n' "for each round (up to $rounds), for each AD:" >&3
  ft_quote "${OCI[@]}" compute instance launch -c "$comp" --availability-domain '<ad>' \
    --shape VM.Standard.A1.Flex --shape-config "{\"ocpus\":$ocpus,\"memoryInGBs\":$mem}" \
    --image-id "$image" --subnet-id "$subnet" --assign-public-ip true \
    --boot-volume-size-in-gbs "$boot" --ssh-authorized-keys-file "$key" \
    --user-data-file "$here/cloud-init.yaml" --display-name "$name" \
    --freeform-tags "$TAGS" --wait-for-state RUNNING >&3
  printf '%s\n' "  'Out of host capacity' -> next AD; after a full pass, sleep $backoff s" >&3
  exit 0
fi

for ((r = 1; r <= rounds; r++)); do
  for ad in "${ads[@]}"; do
    echo "round $r: trying $ad" >&2
    if out=$(launch_in "$ad" 2>&1); then
      id=$(tail -n 1 <<<"$out")
      oci_save_state INSTANCE_ID "$id"
      echo "launched in $ad"
      ip=$("${OCI[@]}" compute instance list-vnics --instance-id "$id" \
        --query 'data[0]."public-ip"' --raw-output)
      echo "ssh ubuntu@$ip   (cloud-init needs a minute or two for Docker)"
      exit 0
    fi
    if grep -qi 'out of host capacity' <<<"$out"; then
      echo "  out of host capacity in $ad" >&2
      continue
    fi
    printf '%s\n' "$out" >&2
    ft_die "launch failed for a reason other than capacity"
  done
  ((r < rounds)) && { echo "no capacity anywhere; waiting $backoff s" >&2; sleep "$backoff"; }
done
ft_die "no A1 capacity after $rounds rounds. Try again later."
