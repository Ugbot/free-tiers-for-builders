# Cloudflare

Scripts for [Free Tiers for Builders: Cloudflare](https://aibywire.com/blog/free-tiers-cloudflare).
R2 as a real test target under a byte budget, and containers that can't be
left running because a Durable Object owns the clock that kills them.

## Prerequisites

- `cf` (checked against 0.15; `npm install --global cf`, Node 22.18+), logged
  in with `cf auth login`.
- Wrangler, pinned and run with `npx` (the scripts use 4.161.0; override with
  `WRANGLER_VERSION`), logged in separately with `npx --yes wrangler@4.161.0 login`.
- For the S3 API: the AWS CLI and an R2 API token scoped to one bucket, with
  its keys in `~/.aws/credentials` under a profile (`r2-tests` by default).
- For containers: the **Workers Paid** plan, and Docker that can build
  `linux/amd64`.

## The scripts

All of them print the commands and stop. Add `--apply` to run them.

| Script | Does |
|---|---|
| `r2-bucket.sh --bucket B` | create the bucket with a location hint, print the S3 profile to add |
| `r2-temp-creds.sh --bucket B --parent-access-key-id K --run-id R --out FILE` | temporary credentials that only reach `runs/R/`, written 0600 |
| `r2-budget-check.sh --bucket B --planned-bytes N` | measure the bucket, refuse (exit 3) if used + planned > 5 GiB |
| `deploy.sh --worker W --account-id A --image I --tag T --token-file F` | plan-gate probe, amd64 build, push, deploy, bearer secret |
| `teardown.sh --worker W --image I:T [--bucket B --run-id R]` | delete, then list to check; optionally clear a run prefix and check it's empty |

`container-template/` is the Worker: one `LeasedRunner` Durable Object per
runner starts the container and sets an alarm at the earlier of the lease
(10 minutes, renewable) and a hard deadline (2 hours, not renewable). If
whatever started it goes away, the alarm destroys the container. The
container gets its own TTL as well, so there are two clocks before you add
your own reaper.

## Things that will catch you out

- **The plan gate is in an odd place.** Containers need Workers Paid. An
  OAuth login can hold the container scopes without the account having the
  plan; you find out at deploy. `deploy.sh` makes a cheap containers call
  first so you find out in seconds.
- **Daily on free, monthly on paid.** Free quotas reset daily. Work out
  your peak day, not your average month.
- **Two CLIs, two logins.** In a project with a Wrangler config, keep
  Wrangler for build and deploy; use `cf` for buckets, DNS and the rest.
- **`Aborted.` exits 0.** A destructive `cf` command run non-interactively
  without `--force` prints `Aborted.` and exits 0 having done nothing. Check
  by listing.
- **You can't pick the machine.** Containers are amd64 microVMs placed by
  Cloudflare, possibly somewhere else after a restart. Fine for services;
  for benchmarks, run both variants on every runner and compare ratios.
- **R2 is S3, mostly.** Region is `auto`. Multipart parts must all be the
  same size (at least 5 MiB) except the last. No ACLs, object lock, SSE-KMS,
  tagging or versioning. Writing one key more than once a second returns
  429. A location hint only counts the first time a bucket name is created.

## Try it yourself

- [ ] Read the pricing page for each product you plan to use, and note which limits are daily.
- [ ] `cf auth login`, and Wrangler pinned with `npx` only if the project needs it.
- [ ] One R2 bucket for tests, location hint chosen once, a token scoped to that bucket.
- [ ] A byte budget checked before every upload, and a run refused if it would cross it.
- [ ] One prefix per run. Delete it on a pass, keep it on a fail, and clean the failures.
- [ ] Multipart uploads with equal-sized parts, and no loops rewriting one key faster than once a second.
- [ ] For containers: Workers Paid, amd64 images, and a Durable Object alarm as the deadline.
- [ ] For benchmarks: both variants on every runner, interleaved, paired ratios, and only trust what every runner agrees on.
- [ ] List everything at the end. Don't trust a zero exit code from a delete.
