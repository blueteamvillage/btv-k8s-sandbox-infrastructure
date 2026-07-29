#!/usr/bin/env bash
#
# Pull every container package published by a GitHub org from GHCR, and
# optionally side-load each image into a local minikube profile so the cluster
# never has to reach the network during the con.
#
# Works whether the packages are public or private — private ones just need a
# token carrying the read:packages scope. The token is read from the gh CLI (or
# $GHCR_TOKEN) and piped to `docker login --password-stdin`; it is never echoed,
# never passed as an argv flag, and never written to disk by this script.
#
#   ./pull-btv-images.sh --dry-run
#   ./pull-btv-images.sh --profile dc34
#   ./pull-btv-images.sh --filter '^challenge-' --all-tags
#
# Kept compatible with bash 3.2, which is what stock macOS still ships.
#
set -euo pipefail

ORG="blueteamvillage"
PROFILE="dc34"
TAG="latest"
ALL_TAGS=0
FILTER=""
DRY_RUN=0
JOBS=3

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarn:\033[0m %s\n' "$*" >&2; }

usage() {
  sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Options:
  -o, --org ORG        GitHub org that owns the packages (default: blueteamvillage)
  -p, --profile NAME   minikube profile to side-load into (default: dc34)
      --no-load        pull only; skip the minikube side-load step
  -t, --tag TAG        tag to pull for each package (default: latest)
  -a, --all-tags       pull every tag of every package, not just one
  -f, --filter REGEX   only packages whose name matches this ERE
  -j, --jobs N         parallel pulls (default: 3)
  -n, --dry-run        list what would be pulled, then stop
  -h, --help           show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -o|--org)      ORG="${2:?--org needs a value}"; shift 2 ;;
    -p|--profile)  PROFILE="${2:?--profile needs a value}"; shift 2 ;;
    --no-load)     PROFILE=""; shift ;;
    -t|--tag)      TAG="${2:?--tag needs a value}"; shift 2 ;;
    -a|--all-tags) ALL_TAGS=1; shift ;;
    -f|--filter)   FILTER="${2:?--filter needs a value}"; shift 2 ;;
    -j|--jobs)     JOBS="${2:?--jobs needs a value}"; shift 2 ;;
    -n|--dry-run)  DRY_RUN=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "unknown argument: $1 (try --help)" ;;
  esac
done

# ---------------------------------------------------------------- preflight --
for bin in gh docker jq; do
  command -v "$bin" >/dev/null 2>&1 || die "$bin is required but not installed"
done
docker info >/dev/null 2>&1 \
  || die "the Docker daemon isn't reachable — start Docker Desktop / colima first"

# Prefer an explicit token, else borrow the gh CLI's. Held in a variable only:
# never printed, never placed in argv, never written to disk.
TOKEN="${GHCR_TOKEN:-$(gh auth token 2>/dev/null || true)}"
[ -n "$TOKEN" ] || die "no GitHub token available — run 'gh auth login', or export GHCR_TOKEN"

GH_USER="$(gh api user --jq .login 2>/dev/null || true)"
[ -n "$GH_USER" ] || die "couldn't resolve your GitHub username via 'gh api user'"

# The packages API needs read:packages. Probe it up front so a missing scope is
# one clear message instead of an opaque 403 halfway through the run.
if ! probe="$(gh api "/orgs/$ORG/packages?package_type=container&per_page=1" 2>&1)"; then
  if printf '%s' "$probe" | grep -qi 'read:packages'; then
    die "your gh token lacks the read:packages scope. Fix it with:

    gh auth refresh -h github.com -s read:packages

  then re-run this script. (Or export GHCR_TOKEN=<classic PAT with read:packages>.)"
  fi
  die "couldn't list packages for org '$ORG':
$probe"
fi

# --------------------------------------------------------------- discovery --
info "listing container packages in '$ORG'"
PACKAGES=()
while IFS= read -r line; do
  [ -n "$line" ] && PACKAGES+=("$line")
done < <(gh api --paginate "/orgs/$ORG/packages?package_type=container&per_page=100" \
           --jq '.[].name' | sort -u)

[ ${#PACKAGES[@]} -gt 0 ] || die "no container packages found in org '$ORG'"

if [ -n "$FILTER" ]; then
  FILTERED=()
  for pkg in "${PACKAGES[@]}"; do
    printf '%s' "$pkg" | grep -Eq "$FILTER" && FILTERED+=("$pkg")
  done
  [ ${#FILTERED[@]} -gt 0 ] || die "no packages matched filter '$FILTER'"
  PACKAGES=("${FILTERED[@]}")
fi

# Package names may contain '/', which has to be percent-encoded in the API path.
urlencode_path() { printf '%s' "$1" | sed 's|/|%2F|g'; }

# Expand packages into concrete image references.
REFS=()
for pkg in "${PACKAGES[@]}"; do
  if [ "$ALL_TAGS" -eq 1 ]; then
    enc="$(urlencode_path "$pkg")"
    TAGS=()
    while IFS= read -r t; do
      [ -n "$t" ] && TAGS+=("$t")
    done < <(gh api --paginate \
               "/orgs/$ORG/packages/container/$enc/versions?per_page=100" \
               --jq '.[].metadata.container.tags[]?' 2>/dev/null | sort -u)
    if [ ${#TAGS[@]} -eq 0 ]; then
      warn "$pkg has no tagged versions — skipping"
      continue
    fi
    for t in "${TAGS[@]}"; do REFS+=("ghcr.io/$ORG/$pkg:$t"); done
  else
    REFS+=("ghcr.io/$ORG/$pkg:$TAG")
  fi
done

[ ${#REFS[@]} -gt 0 ] || die "nothing to pull after expanding tags"

info "${#PACKAGES[@]} package(s), ${#REFS[@]} image reference(s)"
printf '  %s\n' "${REFS[@]}"

if [ "$DRY_RUN" -eq 1 ]; then
  info "dry run — nothing pulled"
  exit 0
fi

# ------------------------------------------------------------------- pull --
info "authenticating to ghcr.io as $GH_USER"
printf '%s' "$TOKEN" | docker login ghcr.io -u "$GH_USER" --password-stdin >/dev/null \
  || die "docker login to ghcr.io failed — token may lack read:packages"

info "pulling with $JOBS parallel job(s)"
printf '%s\n' "${REFS[@]}" \
  | xargs -P "$JOBS" -I{} sh -c \
      'docker pull --quiet "$1" >/dev/null 2>&1 \
         && echo "  pulled $1" \
         || { echo "  FAILED $1" >&2; exit 1; }' _ {} \
  || warn "one or more pulls failed — see FAILED lines above"

# Re-check what actually landed, so the side-load step and the final count
# reflect reality rather than what we hoped for.
PULLED=()
for ref in "${REFS[@]}"; do
  docker image inspect "$ref" >/dev/null 2>&1 && PULLED+=("$ref")
done
info "${#PULLED[@]}/${#REFS[@]} image(s) present locally"

# -------------------------------------------------------------- side-load --
if [ -n "$PROFILE" ] && [ ${#PULLED[@]} -gt 0 ]; then
  if ! command -v minikube >/dev/null 2>&1; then
    warn "minikube not installed — skipping side-load into '$PROFILE'"
  elif ! minikube -p "$PROFILE" status >/dev/null 2>&1; then
    warn "minikube profile '$PROFILE' isn't running — skipping side-load."
    warn "start it, then re-run this script to load the cached images."
  else
    info "side-loading ${#PULLED[@]} image(s) into minikube profile '$PROFILE'"
    for ref in "${PULLED[@]}"; do
      if minikube -p "$PROFILE" image load "$ref"; then
        echo "  loaded $ref"
      else
        warn "failed to load $ref"
      fi
    done
  fi
fi

info "done. Images are cached locally; the cluster no longer needs the network to start a challenge."
