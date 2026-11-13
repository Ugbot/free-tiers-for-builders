# Aiven

Scripts for [Part 1: Testing Against Aiven](https://aibywire.com/blog/localhost-lies-aiven-free-tier).
Real Kafka, PostgreSQL, MySQL, Valkey and OpenSearch on the free plans,
with TLS everywhere, powered on for a test run and off again after.

## Prerequisites

- An Aiven account and one project for tests.
- [`avn`](https://github.com/aiven/aiven-client) (checked against 4.18) and `jq`.
- A token. Either `avn user login`, or a short-lived one in a 0600 file:

  ```sh
  umask 077
  avn user access-token create --description "connector tests" \
      --max-age-seconds 86400 --json | jq -r .full_token > <dir>/aiven-token
  ```

  Then pass `--token-file <dir>/aiven-token`. The scripts never print it.

Set the project once with `export AIVEN_PROJECT=<project>`, or pass `--project`.

## The scripts

All of them print the commands and stop. Add `--apply` to run them.

| Script | Does |
|---|---|
| `list-services.sh` | name, type, plan and state of each service |
| `create-free-services.sh --cloud C NAME:TYPE ...` | create on the free plan only; idempotent |
| `power.sh on SERVICE ...` | power on and wait, bounded, for RUNNING |
| `power.sh off SERVICE ...` | power off |
| `wait-running.sh SERVICE ...` | just the wait; safe to re-run if interrupted |
| `kafka-access.sh SERVICE --topic T --user U ...` | SASL on, topic, scoped user, ACL |
| `fetch-ca.sh --out DIR` | the project CA |
| `connection-files.sh SERVICE --user U --out DIR` | host, port and password in 0600 files, plus a Kafka `.properties`, a `.pgpass` or a MySQL `.cnf` |
| `teardown.sh SERVICE ... \| --all` | power off and check every one reads POWEROFF |

A typical run:

```sh
./power.sh on <kafka> <pg> --apply
./kafka-access.sh <kafka> --topic <topic> --user <user> --partitions <n> --replication <r> --apply
./fetch-ca.sh --out ~/.secrets/aiven --apply
./connection-files.sh <kafka> --user <user> --out ~/.secrets/aiven --apply
# ... tests ...
./teardown.sh --all --apply
```

## Things that will catch you out

- **Power-on is asynchronous.** Create and power-on return straight away;
  RUNNING comes minutes later (Valkey ~3, Kafka up to ~10 on the free
  plans). Don't write a sleep loop: wait with a bound, and make the wait
  safe to re-run.
- **RUNNING isn't quite ready.** New Kafka ACLs take a moment to propagate.
  If the first produce fails with an authorization error, wait and retry.
- **SASL has its own port.** It isn't the client-certificate port. Take it
  from the service, which `connection-files.sh` does.
- **Trust is per service.** Kafka, PostgreSQL, MySQL and OpenSearch verify
  against the project CA. Valkey (`rediss://`) verifies against the system
  trust store.
- **Publications need aiven-extras.** Creating a PostgreSQL publication
  normally needs a superuser. Use
  [aiven-extras](https://github.com/aiven/aiven-extras):
  `SELECT * FROM aiven_extras.pg_create_publication_for_all_tables('<publication>', 'INSERT,UPDATE,DELETE');`
- **The free OpenSearch plan has one user.** Its tests run as that user.

## Try it yourself

- [ ] One project, five services on their free plans, in a region near your clients.
- [ ] A short-lived API token in a 0600 file.
- [ ] The project CA downloaded. System trust for Valkey.
- [ ] Kafka: SASL on, topic, scoped user, ACL, and a retry around the first produce.
- [ ] Postgres: `verify-full`, grants, a publication via aiven-extras.
- [ ] MySQL: `VERIFY_IDENTITY`, replication grants, binlog settings read before you trust them.
- [ ] Credentials only in 0600 files, never printed.
- [ ] Power off at the end, every time, including when the tests fail.
