---
name: oracle-cloud-free-tier
description: Use the scripts in oracle-cloud/ to set up an Oracle Cloud (OCI) Always Free Arm box safely: check the CLI region, create a budget with alerts, a compartment and SSH-from-one-IP network, launch an A1 instance at the free size with capacity retry, and tear the whole compartment down. Use when asked to set up, debug or remove OCI free-tier resources, or when an OCI call returns 401 NotAuthenticated.
---

# Oracle Cloud free tier

The scripts are in `oracle-cloud/` of this repo. Read `oracle-cloud/README.md` first.

## How to use them safely

1. **Dry run first, always.** Every script prints the exact `oci` commands
   and runs nothing unless given `--apply`. Run it without, show the human
   the output, and ask before re-running with `--apply`.
2. **Budget first.** Run `check-config.sh`, then `budget.sh --email ...`,
   before creating anything else. A budget only alerts; it doesn't stop
   spending.
3. **Stay inside the allowance.** A1 is free up to 2 OCPUs and 12 GB in
   total across all A1 instances (Oracle's page, 13 November 2026; older
   guides say 4 and 24). Block and boot volumes share 200 GB. Before
   launching, check for existing A1 instances; if there are any, ask
   before adding another. `launch-a1.sh` refuses more than the allowance
   for one instance but can't see the others.
4. **Credentials.** Use the CLI's own `~/.oci/config` and key. Never read,
   print or copy the private key or the config contents. Never commit
   `state.env`.
5. **Network.** SSH from one /32 only, the human's address, which they give
   you. Don't open other ports. Bind apps to 127.0.0.1 and use an SSH tunnel.
6. **Teardown after**, for anything temporary: `teardown.sh` with `--apply`
   after asking. Never point it at a compartment you didn't create for this.

## Quirks to expect

- **401 NotAuthenticated can mean wrong region.** If the config's region
  isn't one the tenancy is subscribed to, every call fails as if the
  signature were bad. Run `check-config.sh --apply` (and `--try-region
  <home>`) before suspecting the key, fingerprint, passphrase or clock.
- **Tag keys can't contain dots.** Freeform tag keys like `project.role`
  are rejected as "forbidden characters". Use underscores.
- **Out of host capacity.** Normal for A1. `launch-a1.sh` tries each AD,
  then backs off. Don't loop on one AD for hours.
- **Service limits aren't the free allowance.** `oci limits
  resource-availability get` shows what Oracle allows, not what's free.
- **Command names.** Budgets are `oci budgets budget budget create`. That
  isn't a typo. `--generate-param-json-input <arg>` shows any JSON shape.
- **Stderr noise.** The CLI prints `SyntaxWarning`s on newer Pythons;
  they're harmless and the scripts suppress them. Don't treat stderr alone
  as failure.
- **Idle reclaim.** Always Free instances below 20% CPU (p95), network and
  memory for seven days may be reclaimed. Give the box real work; don't
  write a CPU-burning keepalive.

## Verifying teardown

`teardown.sh --apply` lists everything in the compartment before and after.
The second listing should be empty apart from the compartment while its
deletion runs; compartment deletion is asynchronous and fails if anything
is left in it. Also confirm no instance is RUNNING and no boot or block
volumes remain (the script lists both). Report the final listing.
