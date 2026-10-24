# Forgejo + Forgejo Actions Runner

Self-hosted Git forge (Forgejo 16) with a Docker-in-Docker (dind) Actions runner
for CI/CD. Runs on `lxc-devops` (192.168.68.110), exposed at `git.slavik.tech`.

## Stack Topology

- **forgejo** — Forgejo 16 server (`data.forgejo.org/forgejo/forgejo:16`), serves
  Git + web UI on `:3000`, SSH on `:222`. Actions feature enabled server-side.
- **db** — PostgreSQL for Forgejo's metadata.
- **dind** — Docker-in-Docker daemon (`docker:29-dind`). Gives the runner an
  isolated second docker daemon so CI jobs never touch the host docker. Persistent
  volume keeps the per-job image cache.
- **runner** — `data.forgejo.org/forgejo/runner:13` (v13.2.0). Fetches workflows
  from Forgejo, spawns job containers inside dind. Config from
  [`runner-config.yml`](./runner-config.yml), registration state in the `/data`
  volume.

```
                    ┌─────────────────────────────────────────┐
                    │  lxc-devops                              │
                    │                                          │
   git.slavik.tech  │  ┌─ forgejo ──┐   ┌─ runner ──────────┐  │
   :3000 / :222 ───►│  │            │◄──│  forgejo-runner    │  │
                    │  │  actions   │   │  daemon            │  │
                    │  │  enabled   │   │                    │  │
                    │  └────────────┘   └─────────┬──────────┘  │
                    │                             │ tcp://dind  │
                    │                 ┌───────────▼──────────┐  │
                    │                 │ dind (isolated dock) │  │
                    │                 │ job containers       │  │
                    │                 └──────────────────────┘  │
                    │                                          │
                    └─────────────────────────────────────────┘
```

## Prerequisites

1. Komodo stack `forgejo` already configured (see `stacks.toml`).
2. The following env vars set as Komodo variables / stack environment:
   `FORGEJO_DOMAIN`, `FORGEJO_ROOT_URL`, `FORGEJO_SSH_DOMAIN`,
   `FORGEJO_SSH_PORT`, `FORGEJO_DB_NAME`, `FORGEJO_DB_USER`, `FORGEJO_DB_PASS`,
   `FORGEJO_RUNNER_TOKEN`, `FORGEJO_RUNNER_NAME`, `DOCKER_VOLUME_STORAGE`.

## One-time host prep (required before first deploy)

The runner container runs as UID/GID 1000 and needs to write to the `/data` bind
mount; dind needs a persistent `/var/lib/docker`. Run this **once** on the devops
LXC:

```bash
ssh lxc-devops
export DOCKER_VOLUME_STORAGE=/srv/appdata
bash -c "$(curl -fsSL <paste setup.sh URL from this repo>)"
# or copy stacks/devops/forgejo/setup.sh over and run it
```

## Getting the runner registration token

The runner must be registered with Forgejo before it will run jobs. Get a fresh
token one of two ways:

**Option A — Web UI (recommended for a single runner):**
1. Log into `git.slavik.tech` as an admin.
2. Go to **Site Administration → Actions → Runners → Create new runner**.
3. Copy the displayed token. This becomes `FORGEJO_RUNNER_TOKEN`.

**Option B — API (scriptable):**
```bash
curl -s -H "Authorization: token $FORGEJO_PAT" \
  https://git.slavik.tech/api/v1/user/actions/runners/registration-token
```

> Scope: a **user-level** runner (token from `/user/actions/...`) runs workflows
> from all repos owned by that user. For instance-wide coverage, register at the
> **Site Administration** level instead. See [Runner Registration](https://forgejo.org/docs/latest/admin/actions/registration/).

Set the token in the Komodo stack environment as `FORGEJO_RUNNER_TOKEN`, then
deploy.

## Deploy

```bash
# from the homelab repo after the PR is merged to main
docker compose -f stacks/devops/forgejo/compose.yaml up -d
```
or trigger a redeploy of the `forgejo` stack in Komodo.

On first start, the runner container:
1. registers with Forgejo using `FORGEJO_RUNNER_TOKEN` (writes uuid+token to
   `/data/.runner`),
2. starts `forgejo-runner daemon --config /config.yaml`.

You should see the runner appear as **online** under **Site Administration →
Actions → Runners**, and as idle under the repository's Actions tab.

## Verify the runner

```bash
# runner process is up and not crash-looping
docker exec forgejo-runner forgejo-runner --version
docker logs forgejo-runner --tail 50

# registration succeeded (file exists on the LXC)
ls -la /srv/appdata/forgejo/runner/data/.runner
```

Then push a smoke-test workflow (below) and confirm it runs.

## Adding a workflow to a repository

Workflows live in `.forgejo/workflows/` (GitHub-style `.yml`). Minimal example —
create `.forgejo/workflows/ci.yml` in any repo owned by the runner's user:

```yaml
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Hello from Forgejo Actions 🐼"
```

Push it; the job should appear under **Actions** in the repo and run on this
runner.

## Notes / Gotchas

- **Labels** are defined in `runner-config.yml` (`runner.labels`). Jobs declare
  `runs-on:` and the runner only accepts labels it has. Defaults here support
  `ubuntu-latest/-22.04/-24.04` (docker) and `self-hosted` (host, no isolation).
- **Job containers run inside dind**, which is isolated from the host docker
  daemon (safer, and jobs' `docker build` output is keep inside dind).
- **`container.network` is empty** in the config → the runner creates a fresh
  per-job network each run. To share a network (e.g. to reach Forgejo internals),
  set `container.network: forgejo` and ensure jobs are trusted on it.
- **Cache** is enabled (`cache.enabled: true`) and stored under
  `/srv/appdata/forgejo/runner/data/.cache`. Actions like `actions/cache` or
  `actions/setup-go` interoperate.
- **Concurrency** (`runner.capacity`) is 1. Bump it only if the devops LXC has
  spare CPU/RAM — each concurrent job spawns a container in dind.
- **dind storage**: `/srv/appdata/forgejo/runner/dind` holds the per-job image
  cache. `docker system prune` it occasionally (see upgrade guide).
- **Forgejo 13→16 upgrade**: server image bumped `forgejo:13` → `forgejo:16`, DB
  migrations run automatically on first start. Take a backup first
  ([upgrade guide](https://forgejo.org/docs/v16.0/admin/upgrade/)). Runner bumped
  `runner:12` → `runner:13` (v13.2.0, latest).

## References

- [Forgejo Actions overview](https://forgejo.org/docs/latest/admin/actions/)
- [Runner Docker install](https://forgejo.org/docs/latest/admin/actions/installation/docker/)
- [Runner configuration](https://forgejo.org/docs/latest/admin/actions/configuration/)
- [Runner registration](https://forgejo.org/docs/latest/admin/actions/registration/)
- [Docker access (dind)](https://forgejo.org/docs/latest/admin/actions/docker-access/)