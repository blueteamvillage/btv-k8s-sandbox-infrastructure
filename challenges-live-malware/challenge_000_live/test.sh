#!/usr/bin/env bash
# Static checks for the challenge-000-live image (no detonation).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-ghcr.io/blueteamvillage/dc34-obsidian-seceng:challenge-000-live-latest}"
DOCKERFILE="${DOCKERFILE:-$HERE/Dockerfile}"

PASS=0; FAIL=0
ok() { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
no() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }

echo "== Build amd64 inert image =="
if docker build --platform linux/amd64 -f "$DOCKERFILE" -t "$IMAGE" "$HERE" >/dev/null 2>&1; then
    ok "docker build --platform linux/amd64"
else
    no "docker build failed"
fi

IMG_ARCH="$(docker image inspect "$IMAGE" --format '{{.Architecture}}' 2>/dev/null || true)"
if [[ "$IMG_ARCH" == "amd64" ]]; then
    ok "image arch amd64"
else
    no "image arch is '${IMG_ARCH:-none}', expected amd64"
fi

echo "== Guest loader =="
if docker run --rm --platform linux/amd64 --entrypoint /usr/bin/test "$IMAGE" -e /lib64/ld-linux-x86-64.so.2 2>/dev/null; then
    ok "loader /lib64/ld-linux-x86-64.so.2 present"
else
    no "guest loader missing"
fi

echo "== Tooling =="
for bin in curl file bash timeout sha256sum; do
    if docker run --rm --platform linux/amd64 --entrypoint /usr/bin/env "$IMAGE" bash -c "command -v $bin" >/dev/null 2>&1; then
        ok "$bin present"
    else
        no "$bin missing"
    fi
done

echo "== No malware baked in =="
if docker run --rm --platform linux/amd64 --entrypoint /bin/bash "$IMAGE" -c 'find /samples -type f 2>/dev/null | grep -q .' ; then
    no "unexpected files under /samples in image"
else
    ok "/samples empty in image"
fi

echo "== Hard stop outside k8s =="
OUT="$(docker run --rm --platform linux/amd64 --entrypoint /start.sh "$IMAGE" 2>&1 || true)"
if printf '%s' "$OUT" | grep -q "HARD STOP"; then
    ok "entrypoint hard-stops without KUBERNETES_SERVICE_HOST"
else
    no "entrypoint did not hard-stop outside cluster"
    printf '%s\n' "$OUT" | sed 's/^/    /'
fi

echo ""
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
