#!/usr/bin/env bash
# Kafka: turn on SASL, create a topic, a scoped user and an ACL for it.
#
# The user's password is not printed. Use connection-files.sh to write it,
# and the client config, to 0600 files.
set -euo pipefail
# shellcheck source=env.sh
. "$(dirname "$0")/env.sh"

usage() {
  cat <<'U'
usage: kafka-access.sh SERVICE --topic TOPIC --user USER
                       --partitions N --replication N [--permission readwrite]

Permissions: read, write, readwrite, admin. Keep it to what the test needs.

ACLs take a moment to propagate after RUNNING and after acl-add. If the
first produce fails with an authorization error, wait and retry before
assuming the ACL is wrong.

U
  aiven_usage
}

service='<service>' topic='<topic>' user='<user>'
partitions='<partitions>' replication='<replication>' permission=readwrite
while (($#)); do
  n=0; aiven_opt "$@" || n=$?
  if ((n)); then shift "$n"; continue; fi
  case $1 in
    --topic) topic=${2:?}; shift 2 ;;
    --user) user=${2:?}; shift 2 ;;
    --partitions) partitions=${2:?}; shift 2 ;;
    --replication) replication=${2:?}; shift 2 ;;
    --permission) permission=${2:?}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) ft_die "unknown argument: $1" ;;
    *) service=$1; shift ;;
  esac
done

aiven_init
for pair in "$service:SERVICE" "$topic:--topic" "$user:--user" \
            "$partitions:--partitions" "$replication:--replication"; do
  ft_need "${pair%:*}" "${pair##*:}"
done

ft_run avn service update "$service" -c kafka_authentication_methods.sasl=true \
  --project "$PROJECT"
ft_run avn service topic-create "$service" "$topic" \
  --partitions "$partitions" --replication "$replication" --project "$PROJECT"
ft_run_quiet avn service user-create "$service" --username "$user" --project "$PROJECT"
ft_run avn service acl-add "$service" --username "$user" --topic "$topic" \
  --permission "$permission" --project "$PROJECT"
ft_note "SASL has its own port. connection-files.sh takes it from the service, not a guess."
