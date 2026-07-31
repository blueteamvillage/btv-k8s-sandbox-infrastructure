# `scripts/`

Helper scripts for the DC34 sandbox.

Nothing in here is required to compete. `make up` builds the cluster, and
applying a challenge manifest pulls whatever image it needs on its own. These
scripts exist to make specific jobs less tedious — mainly *doing the network
work at home instead of on the con Wi-Fi*.

---

## `pull-btv-images.sh`

Downloads every Blue Team Village challenge image and side-loads each one into
your local `dc34` cluster.

### Why you'd run it

DEF CON internet is famously unreliable, and a challenge you can't pull is a
challenge you can't play. The challenge pods are declared with
`imagePullPolicy: IfNotPresent`, so any image already present in the cluster is
used as-is with no registry round trip. Pre-load them at home and the con
network never sits between you and an investigation.

Run it the night before you travel, not in the queue at the village.

### Requirements

- `gh`, `docker`, and `jq` on your PATH
- Docker actually running (colima on macOS, Docker Desktop on Windows)
- A GitHub token carrying the **`read:packages`** scope

That last one catches people out. Listing an organization's packages requires
`read:packages` **even when those packages are public** — it's a property of the
API endpoint, not of the images. Grant it with:

```sh
gh auth refresh -h github.com -s read:packages
```

Or supply a classic PAT instead:

```sh
export GHCR_TOKEN=<token with read:packages>
```

The script checks this up front and tells you exactly what to run if the scope
is missing, rather than failing halfway through with an opaque 403.

### Usage

```sh
./scripts/pull-btv-images.sh --dry-run     # list what would be pulled, then stop
./scripts/pull-btv-images.sh               # pull everything, load into dc34
./scripts/pull-btv-images.sh --no-load     # pull only, don't touch minikube
```

| Flag | Default | What it does |
|------|---------|--------------|
| `-o, --org ORG` | `blueteamvillage` | Org that owns the packages |
| `-p, --profile NAME` | `dc34` | minikube profile to side-load into |
| `--no-load` | — | Pull only; skip the side-load step |
| `-t, --tag TAG` | `latest` | Which tag to pull for each package |
| `-a, --all-tags` | — | Pull every tag, not just one |
| `-f, --filter REGEX` | — | Only packages matching this expression |
| `-j, --jobs N` | `3` | Parallel pulls |
| `-n, --dry-run` | — | Print the plan and exit |
| `-h, --help` | — | Full help |

Start with `--dry-run`. It hits the API and prints the exact image list without
downloading anything, which is a cheap way to confirm your token works.

Grabbing a subset:

```sh
./scripts/pull-btv-images.sh --filter '^challenge-00'          # 000-009
./scripts/pull-btv-images.sh --filter 'converged|001-s' -a     # every Converged Frontier tag
```

### What it does, in order

1. Verifies `gh`/`docker`/`jq` exist and the Docker daemon is reachable.
2. Probes the packages API so a missing scope fails fast with a fix.
3. Lists every container package in the org, applies `--filter`, expands tags.
4. Logs in to `ghcr.io` and pulls, `--jobs` at a time.
5. Re-inspects each image locally, so the counts reflect what actually landed
   rather than what was attempted.
6. Side-loads the images that are genuinely present into the minikube profile.

Re-running is safe. Already-pulled layers are skipped by Docker, and loading an
image the cluster already has is a no-op.

If the `dc34` profile isn't running, the script warns and skips step 6 instead
of failing — the images stay cached in Docker, so start the cluster and re-run
to finish the job.

### About the token

The token is read from `gh auth token` (or `$GHCR_TOKEN`) and piped to
`docker login --password-stdin`. It is never echoed, never passed as a
command-line argument — so it stays out of `ps` output and your shell history —
and never written to disk.

**Don't hardcode a PAT into the script.** If you need a non-`gh` token, pass it
through the `GHCR_TOKEN` environment variable.

When you're done, `docker logout ghcr.io` clears the stored credential.

### Just want one image?

You don't need this script, or a token, for a single challenge:

```sh
docker pull ghcr.io/blueteamvillage/challenge-000:latest
minikube -p dc34 image load ghcr.io/blueteamvillage/challenge-000:latest
```

Or skip it entirely and let the manifest do the work:

```sh
kubectl --context dc34 apply -f challenges/challenge-000.pod.yaml
```

---

## Conventions for anything added here

- **POSIX-ish bash, compatible with bash 3.2.** Stock macOS still ships 3.2, so
  no `mapfile`, no associative arrays, and guard array expansions under
  `set -u`. Check with `/bin/bash -n script.sh` before committing.
- **`set -euo pipefail`** at the top.
- **`--dry-run` for anything destructive or slow**, so people can look before
  they leap.
- **Never print, log, or commit a credential.** Read tokens from the
  environment or `gh`, and hand them to other tools over stdin.
