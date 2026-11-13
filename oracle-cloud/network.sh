#!/usr/bin/env bash
# A compartment and a network that only lets SSH in from you.
#
#   compartment -> VCN -> internet gateway -> default route out
#   -> security list: TCP 22 from one /32, nothing else in -> public subnet
#
# The IDs go to state.env (0600, git-ignored) for launch-a1.sh and teardown.sh.
set -euo pipefail
# shellcheck source=env.sh
. "$(dirname "$0")/env.sh"

usage() {
  cat <<'U'
usage: network.sh --my-ip A.B.C.D [--name builders]

--my-ip is the public IPv4 you'll SSH from; it becomes the only /32
allowed in. This script doesn't look it up for you.

U
  oci_usage
}

my_ip='<your-ip>' name=builders
while (($#)); do
  n=0; oci_opt "$@" || n=$?
  if ((n)); then shift "$n"; continue; fi
  case $1 in
    --my-ip) my_ip=${2:?}; shift 2 ;;
    --name) name=${2:?}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) ft_die "unknown argument: $1" ;;
  esac
done

oci_init
ft_need "$my_ip" --my-ip
if ((FT_APPLY)); then
  [[ $my_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || ft_die "--my-ip must be one IPv4 address"
fi
[[ $name =~ ^[a-z][a-z0-9]{0,14}$ ]] || ft_die "--name: lowercase letters and digits, 15 at most (it's a DNS label too)"
oci_check_tags "$TAGS"

comp=$(ft_capture '<compartment-ocid>' "${OCI[@]}" iam compartment create -c "$TENANCY" \
  --name "$name" --description "free tier box" --freeform-tags "$TAGS" \
  --wait-for-state ACTIVE --query data.id --raw-output)
oci_save_state COMPARTMENT_ID "$comp"

vcn_json=$(ft_capture '{"id":"<vcn-ocid>","default-route-table-id":"<vcn-default-route-table>"}' \
  "${OCI[@]}" network vcn create -c "$comp" --cidr-blocks '["10.0.0.0/16"]' \
  --display-name "$name-vcn" --dns-label "$name" --freeform-tags "$TAGS" \
  --wait-for-state AVAILABLE --query data --raw-output)
vcn=$(jq -r .id <<<"$vcn_json")
rt=$(jq -r '."default-route-table-id"' <<<"$vcn_json")
oci_save_state VCN_ID "$vcn"

igw=$(ft_capture '<igw-ocid>' "${OCI[@]}" network internet-gateway create -c "$comp" --vcn-id "$vcn" \
  --is-enabled true --display-name "$name-igw" --freeform-tags "$TAGS" \
  --wait-for-state AVAILABLE --query data.id --raw-output)

ft_run_quiet "${OCI[@]}" network route-table update --rt-id "$rt" --force \
  --route-rules "[{\"destination\":\"0.0.0.0/0\",\"destinationType\":\"CIDR_BLOCK\",\"networkEntityId\":\"$igw\"}]"

# Protocol "6" is TCP: the API wants the IANA number.
seclist=$(ft_capture '<seclist-ocid>' "${OCI[@]}" network security-list create -c "$comp" --vcn-id "$vcn" \
  --display-name ssh-from-me --freeform-tags "$TAGS" \
  --egress-security-rules '[{"destination":"0.0.0.0/0","protocol":"all"}]' \
  --ingress-security-rules "[{\"source\":\"$my_ip/32\",\"protocol\":\"6\",\"tcpOptions\":{\"destinationPortRange\":{\"min\":22,\"max\":22}}}]" \
  --wait-for-state AVAILABLE --query data.id --raw-output)

subnet=$(ft_capture '<subnet-ocid>' "${OCI[@]}" network subnet create -c "$comp" --vcn-id "$vcn" \
  --cidr-block 10.0.1.0/24 --display-name public --dns-label pub \
  --route-table-id "$rt" --security-list-ids "[\"$seclist\"]" --freeform-tags "$TAGS" \
  --wait-for-state AVAILABLE --query data.id --raw-output)
oci_save_state SUBNET_ID "$subnet"

ft_note "next: launch-a1.sh. IDs saved to $STATE_FILE (0600) with --apply."
ft_note "any argument's JSON shape: add --generate-param-json-input <argument> to the oci command."
