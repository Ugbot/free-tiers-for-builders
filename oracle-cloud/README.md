# Oracle Cloud

Scripts for [Free Tiers for Builders: Oracle Cloud](https://aibywire.com/blog/free-tiers-oracle-cloud).
An Arm box that never switches off, inside the Always Free allowance, that
only you can reach, with a budget that emails you before anything costs money.

## Prerequisites

- An OCI account. Pick the home region carefully: it's permanent, and
  Always Free resources have to live there.
- The OCI CLI (checked against 3.96.2) and `jq`. Run `oci setup config`,
  then upload the public key it made under your user's API keys.
- An SSH key pair, and the public IPv4 address you'll connect from.

## The scripts

All of them print the commands and stop. Add `--apply` to run them. Run
them in this order.

| Script | Does |
|---|---|
| `check-config.sh` | is the config's region one the tenancy is subscribed to? |
| `budget.sh --email ADDR` | a monthly budget, alerts at 50/80/100% actual and 100% forecast |
| `network.sh --my-ip A.B.C.D` | compartment, VCN, internet gateway, route, SSH-from-your-/32-only security list, public subnet |
| `launch-a1.sh --ssh-key PATH.pub` | Ubuntu 24.04 on A1 at 2 OCPUs / 12 GB, Docker by cloud-init, retrying across ADs on "Out of host capacity" |
| `teardown.sh` | list the compartment, delete everything in it, then the compartment, then list again |

IDs from `network.sh` and `launch-a1.sh` are kept in `state.env` (0600,
git-ignored) so the next script can find them. `cloud-init.yaml` installs
Docker and zstd. [`idle-reclaim.md`](idle-reclaim.md) is about keeping the
box from being reclaimed.

Once it's up, keep the app on localhost and come in through a tunnel:

```sh
docker save myapp:dev | zstd -T0 | ssh ubuntu@<host> 'zstd -d | docker load'
ssh ubuntu@<host> 'docker run -d --name myapp -p 127.0.0.1:8080:8080 myapp:dev'
ssh -N -L 8080:127.0.0.1:8080 ubuntu@<host>
```

## Things that will catch you out

- **A 401 that means "wrong place".** A region the tenancy isn't
  subscribed to fails with `401 NotAuthenticated`, exactly like a bad key.
  Check the region before you check the key: `check-config.sh`.
- **Tag keys can't have dots.** `project.role` is refused as "forbidden
  characters". Use underscores. The scripts check.
- **The A1 allowance changed.** Oracle's page now says 1,500 OCPU hours and
  9,000 GB hours a month: 2 OCPUs and 12 GB all month, across *all* your A1
  instances. Older guides say 4 and 24. `launch-a1.sh` refuses more than
  2 / 12 for one instance, but it can't see your others.
- **The service limit isn't the free allowance.** `oci limits
  resource-availability get` tells you what Oracle will let you have, not
  what's free. Anything in between is billed.
- **A budget is an alert, not a cap.** It emails you. It switches nothing off.
- **Out of host capacity.** Try each AD in turn, back off, try later. Don't
  hammer one AD.
- **Idle boxes get reclaimed.** Seven days below 20% on CPU (p95), network
  and memory. Give it a real job.
- **`SyntaxWarning`s.** On newer Pythons the CLI prints them from its own
  code to stderr. Harmless; the scripts silence them.

## Try it yourself

- [ ] Pick a home region near you. It's permanent.
- [ ] `oci setup config`, then check your config region is one you're subscribed to.
- [ ] A budget with email alerts, actual and forecast, before anything else.
- [ ] Freeform tag keys without dots.
- [ ] A compartment, a VCN, and SSH allowed from your /32 only.
- [ ] One A1 box at 2 OCPUs and 12 GB, trying each AD if capacity is short.
- [ ] Your app bound to localhost, with auth on, reached through an SSH tunnel.
- [ ] A real job for it, so it isn't idle for a week.
- [ ] For anything temporary: lease first, create second, reap automatically.
