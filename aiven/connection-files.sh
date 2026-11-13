#!/usr/bin/env bash
# Write connection details for one service user to 0600 files.
#
#   DIR/SERVICE.env              host, port, user, TLS settings, file paths
#   DIR/SERVICE-USER.pass        the password, alone
#   kafka: DIR/SERVICE.properties   Kafka client config (SASL_SSL, SCRAM-SHA-256)
#   pg:    DIR/SERVICE.pgpass       libpq password file
#   mysql: DIR/SERVICE.cnf          [client] option file
#
# Passwords go from avn straight into files through jq; they are never
# printed or held in a shell variable.
set -euo pipefail
# shellcheck source=env.sh
. "$(dirname "$0")/env.sh"

usage() {
  cat <<'U'
usage: connection-files.sh SERVICE --user USER --out DIR

Run fetch-ca.sh --out DIR first: the files point at DIR/<project>-ca.pem.
Valkey verifies against the system trust store, so it gets no CA path.

U
  aiven_usage
}

service='<service>' user='<user>' out='<dir>'
while (($#)); do
  n=0; aiven_opt "$@" || n=$?
  if ((n)); then shift "$n"; continue; fi
  case $1 in
    --user) user=${2:?}; shift 2 ;;
    --out) out=${2:?}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) ft_die "unknown argument: $1" ;;
    *) service=$1; shift ;;
  esac
done

aiven_init
ft_need "$service" SERVICE
ft_need "$user" --user
ft_need "$out" --out

ca="$out/$PROJECT-ca.pem"
pass="$out/$service-$user.pass"
env_file="$out/$service.env"

# host and port for the service's own component; for Kafka, the SASL listener
# shellcheck disable=SC2016  # a jq program, not shell
endpoint_jq='
  .service_type as $t
  | ([.components[]?
      | select(.component == (if $t == "pg" then "pg" else $t end))
      | select(($t != "kafka") or (.kafka_authentication_method == "sasl"))
      | select((.usage // "primary") == "primary")
      | select((.route // "dynamic") == "dynamic")][0]
     // .service_uri_params)
  | "SERVICE_TYPE=\($t)\nHOST=\(.host)\nPORT=\(.port)"'

write_env() {
  (umask 077 && avn service get "$service" --project "$PROJECT" --json \
    | jq -r "$endpoint_jq" >"$env_file")
  local type
  type=$(sed -n 's/^SERVICE_TYPE=//p' "$env_file")
  {
    printf 'USERNAME=%s\nPASSWORD_FILE=%s\n' "$user" "$pass"
    case $type in
      valkey) printf 'URL_SCHEME=rediss\nCA_FILE=\n# verify against the system trust store\n' ;;
      pg) printf 'PGSSLMODE=verify-full\nPGSSLROOTCERT=%s\nPGPASSFILE=%s\n' "$ca" "$out/$service.pgpass" ;;
      mysql) printf 'SSL_MODE=VERIFY_IDENTITY\nCA_FILE=%s\nMYSQL_OPTION_FILE=%s\n' "$ca" "$out/$service.cnf" ;;
      *) printf 'CA_FILE=%s\n' "$ca" ;;
    esac
  } >>"$env_file"
  chmod 600 "$env_file"
}

user_json() { avn service user-get "$service" --username "$user" --project "$PROJECT" --json; }

write_secret_files() {
  local type host port
  type=$(sed -n 's/^SERVICE_TYPE=//p' "$env_file")
  host=$(sed -n 's/^HOST=//p' "$env_file")
  port=$(sed -n 's/^PORT=//p' "$env_file")
  (umask 077 && user_json | jq -r .password >"$pass")
  case $type in
    kafka)
      (umask 077 && user_json | jq -r --arg u "$user" --arg h "$host:$port" --arg ca "$ca" '
        "bootstrap.servers=\($h)\nsecurity.protocol=SASL_SSL\nsasl.mechanism=SCRAM-SHA-256\n" +
        "ssl.truststore.type=PEM\nssl.truststore.location=\($ca)\n" +
        "sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required " +
        "username=\"\($u)\" password=\"\(.password)\";"' >"$out/$service.properties") ;;
    pg)
      (umask 077 && user_json | jq -r --arg u "$user" --arg h "$host" --arg p "$port" \
        '"\($h):\($p):*:\($u):\(.password)"' >"$out/$service.pgpass") ;;
    mysql)
      (umask 077 && user_json | jq -r --arg u "$user" --arg h "$host" --arg p "$port" --arg ca "$ca" '
        "[client]\nhost=\($h)\nport=\($p)\nuser=\($u)\npassword=\(.password)\n" +
        "ssl-mode=VERIFY_IDENTITY\nssl-ca=\($ca)"' >"$out/$service.cnf") ;;
  esac
  chmod 600 "$out"/"$service"*
}

ft_private_dir "$out"
ft_step "avn service get $service --project $PROJECT --json | jq <endpoint> > $env_file   # 0600" write_env
ft_step "avn service user-get $service --username $user --project $PROJECT --json | jq .password > $pass   # 0600, never printed" \
  write_secret_files
ft_note "plus a client config for kafka (.properties), pg (.pgpass) or mysql (.cnf), all 0600."
if ((FT_APPLY)); then
  ft_note "written (contents not shown):"
  ls -l "$out" >&3
fi
