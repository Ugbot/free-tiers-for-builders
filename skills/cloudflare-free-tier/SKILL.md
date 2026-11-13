---
name: cloudflare-free-tier
description: Use the scripts in cloudflare/ to create an R2 test bucket, mint per-run temporary credentials, check a byte budget before uploading, deploy a Worker + Durable Object + container that tears itself down, and tear everything down and verify. Use when asked to test against real R2, run short-lived containers on Cloudflare, or clean up Cloudflare resources.
---

# Cloudflare free tier

The scripts are in `cloudflare/` of this repo. Read `cloudflare/README.md` first.

## How to use them safely

1. **Dry run first, always.** Every script prints the exact commands and
   runs nothing unless given `--apply`. Run it without, show the human the
   output, and ask before re-running with `--apply`.
2. **Budget first.** Before any upload to R2, run
   `r2-budget-check.sh --bucket B --planned-bytes N --apply`. Exit 3 means
   refused: don't upload, and don't shrink the data to squeeze under the
   cap. Write fewer, smaller objects or ask the human.
3. **One prefix per run.** Write only under `runs/<run-id>/`, ideally with
   `r2-temp-creds.sh` credentials that can't reach anything else. Delete the
   prefix after a pass; keep it after a failure, and tell the human it's
   counting against the budget.
4. **Credentials.** Use the `cf` and Wrangler logins and the AWS profile
   that already exist. Never ask for a key in chat, never print one, never
   put one in an env var on a command line. Generated credential files are
   0600; pass their paths, don't `cat` them.
5. **Containers cost money.** They need Workers Paid. Ask before
   `deploy.sh --apply`, and say what instance type it uses.
6. **Teardown after.** Run `teardown.sh` with `--apply` after asking.

## Quirks to expect

- **Containers plan gate.** A deploy can fail with "You do not have access
  to Cloudflare Containers. Deploying containers requires the Workers Paid
  plan." even though the login has container scopes. Scopes aren't the plan.
  Stop and tell the human; don't retry or look for a workaround.
- **`Aborted.` with exit 0.** A destructive `cf` command without `--force`
  run non-interactively does nothing and exits 0. Always use `--force` in
  scripts and verify by listing.
- **Two CLIs.** Wrangler for build/push/deploy in a project with a Wrangler
  config; `cf` for buckets and other resources. Separate logins.
- **Renamed products.** Pipelines, R2 Data Catalog and R2 SQL are now Basin
  Pipelines, Basin Catalog and Basin SQL. Search for both names.
- **amd64 only.** Build container images with `--platform linux/amd64`.
  Placement isn't controllable: don't take absolute benchmark numbers.
- **R2 isn't quite S3.** Region `auto`. Multipart parts must all be equal
  size (>= 5 MiB) except the last; adaptive part sizing fails. No ACLs,
  object lock, SSE-KMS, tagging or versioning. More than one write per
  second to the same key returns 429. Incomplete multipart uploads are
  aborted after 7 days. A location hint only counts on a bucket name's
  first creation.

## Verifying teardown

`teardown.sh --apply` deletes, then lists applications and images again;
check that the worker's application and the image tag are gone from those
lists, rather than trusting exit codes. With `--bucket` and `--run-id` it
also deletes the run prefix and prints `verified: runs/<id>/ is empty` or
fails. Report the lists, not just that the commands ran.
