# Free Tiers for Builders

Scripts and agent skills for the *Free Tiers for Builders* series: what the
free plans give you, what they're good for, where their edges are, and how
to set them up without leaving anything running.

| Post | Here |
|---|---|
| [Part 1: Testing Against Aiven](https://aibywire.com/blog/localhost-lies-aiven-free-tier) | [`aiven/`](aiven/) · [skill](skills/aiven-free-tier/SKILL.md) |
| [Cloudflare](https://aibywire.com/blog/free-tiers-cloudflare) | [`cloudflare/`](cloudflare/) · [skill](skills/cloudflare-free-tier/SKILL.md) |
| [Oracle Cloud, or Coming Over to the Dark Side](https://aibywire.com/blog/free-tiers-oracle-cloud) | [`oracle-cloud/`](oracle-cloud/) · [skill](skills/oracle-cloud-free-tier/SKILL.md) |

The posts are drafts until they're published, so the links go live then.

## What's here

- **`aiven/`**: list services, power on and off, wait for RUNNING, Kafka
  topic and scoped user and ACL, the project CA, connection files at 0600,
  power everything off and check.
- **`cloudflare/`**: an R2 bucket for tests, temporary credentials per run
  prefix, a budget check that refuses an upload past a size cap, a Worker
  with a container that a Durable Object alarm tears down, and teardown
  that checks by listing.
- **`oracle-cloud/`**: the wrong-region 401 check, a budget with alerts,
  a compartment and network that only lets SSH in from your /32, an A1 box
  at the Always Free size with capacity retry across ADs, and teardown of
  the whole compartment.
- **`skills/`**: one [agent skill](https://docs.claude.com/en/docs/claude-code/skills)
  per provider, so a coding agent can use the scripts without surprising you.

Each folder's README has the prerequisites and the checklist from the post.

## The rules

**Budget first.** Before creating anything: a spend alert on Oracle, a byte
cap on R2, free plans only on Aiven. A budget is an alert, not a cap, so
the scripts also refuse sizes above the free allowance.

**Dry run by default.** Every script prints the exact commands it would run
and runs nothing. Add `--apply` to do it. Read-only calls are gated too, so
a dry run never touches your account. Read the output first.

**Never commit credentials.** Scripts read them from the provider's own CLI
config, from the environment, or from a file you pass that must be 0600.
Anything they generate with a secret in it is written 0600 and never
printed. `.gitignore` covers the usual file names; `scripts/secret-scan.sh`
runs in CI on the tree and the whole history.

**Always tear down.** Every folder has a `teardown.sh`, and it checks by
listing afterwards rather than trusting exit codes. Run it when the tests
pass and when they fail.

## Requirements

Bash, `jq`, and the provider's CLI. The commands were checked against
`avn` 4.18, `cf` 0.15 and Wrangler 4.161, and OCI CLI 3.96.2. They work on
the bash 3.2 macOS ships.

Everything uses placeholders such as `<project>` and `<bucket>`. With
`--apply`, a script refuses to run while any value it needs is still a
placeholder.

## Licence

[Apache 2.0](LICENSE). Use it, change it, and check your bill anyway.
