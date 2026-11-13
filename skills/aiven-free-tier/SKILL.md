---
name: aiven-free-tier
description: Use the scripts in aiven/ to power Aiven free-tier services (Kafka, PostgreSQL, MySQL, Valkey, OpenSearch) on and off for tests, set up Kafka topics, users and ACLs, fetch the CA, write 0600 connection files and tear down. Use when asked to test against real managed services on Aiven, to get Aiven connection details, or to make sure nothing is left powered on.
---

# Aiven free tier

The scripts are in `aiven/` of this repo. Read `aiven/README.md` first.

## How to use them safely

1. **Dry run first, always.** Every script prints the exact `avn` commands
   and runs nothing unless given `--apply`. Run it without `--apply`, show
   the human the output, and ask before running it again with `--apply`.
   Read-only scripts need `--apply` too, so a dry run never touches the account.
2. **Budget first.** Only free plans: `create-free-services.sh` refuses
   anything else. Anything that isn't free (ClickHouse, a bigger plan, a
   new service type) needs the human's explicit approval with the price.
3. **Credentials.** Never ask for a token in chat and never print one.
   The scripts use `avn user login`, `AIVEN_AUTH_TOKEN`, or `--token-file`
   pointing at a 0600 file. `connection-files.sh` writes passwords into
   0600 files through `jq`; point programs at those files and don't `cat`
   them. Don't commit anything they write.
4. **Teardown after.** When the work is done, or has failed, run
   `teardown.sh <services>` (or `--all`) with `--apply` after asking, and
   don't report success until it prints `verified: all powered off`.

## Quirks to expect

- **Power-on is asynchronous.** Create and power-on return immediately;
  RUNNING takes minutes (Valkey ~3, Kafka up to ~10). Use `power.sh on`
  (which waits, bounded) or `wait-running.sh`. Never write a sleep loop.
  If a wait is interrupted, re-run it: it's idempotent.
- **ACL propagation.** After RUNNING and after `acl-add`, a new Kafka
  user may be refused for a short while. Retry the first produce/consume
  a few times with a delay before deciding the ACL is wrong.
- **Per-service CA trust.** Kafka, PostgreSQL, MySQL and OpenSearch verify
  against the project CA (`fetch-ca.sh`). Valkey verifies against the system
  trust store; giving it the project CA fails verification.
- **SASL port.** Kafka's SASL listener is a different port from the
  client-certificate one. Use the port in the generated `.env`, never guess.
- **Use strict TLS.** PostgreSQL `sslmode=verify-full`, MySQL
  `ssl-mode=VERIFY_IDENTITY`. A connection that only works with
  verification off is a bug to report, not a setting to change.
- **Publications** need `aiven_extras.pg_create_publication_for_all_tables`,
  not `CREATE PUBLICATION`, because there's no superuser.

## Verifying teardown

`teardown.sh --apply` lists the services again until every one it powered
off reads `POWEROFF`, up to about five minutes, and exits non-zero if any
didn't. Afterwards, `list-services.sh --apply` should show no service in
`RUNNING` that you started. Report what it printed, not that you ran it.
