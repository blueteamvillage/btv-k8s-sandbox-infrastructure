#!/bin/bash
# Entrypoint for challenge-000-live.
#
# Fetches a third-party sample at runtime (SAMPLE_URL). Village does not
# ship malware bytes in the image or the repo.
#
# Pod logs are intentionally opaque: no URL, hash, family name, or path
# leaks on stdout/stderr.

set -euo pipefail

EXPECTED_NS="challenge-000-live"
EXTRACT_DIR="/samples/extracted"
PAYLOAD_PATH="${EXTRACT_DIR}/p"
LOG_FILE="/var/log/runtime-output.log"
# Implant sleeps 135–224s before re-exec; 30s harness dies mid-sleep.
EXEC_TIMEOUT="${EXEC_TIMEOUT:-300s}"
KILL_GRACE="${KILL_GRACE:-10s}"
EXPECTED_SHA256="${EXPECTED_SHA256:-}"

warn_stop() {
    echo ""
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "  HARD STOP: challenge-000-live will not run here."
    echo "  $1"
    echo "  Live execution is restricted to the dc34 cluster"
    echo "  namespace ${EXPECTED_NS}. Do not docker run this image."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo ""
    exit 1
}

stage() { echo "[*] stage: $1"; }
fail()  { echo "[!] stage failed: $1"; exit 1; }

if [ -z "${KUBERNETES_SERVICE_HOST:-}" ]; then
    warn_stop "Not running in Kubernetes (KUBERNETES_SERVICE_HOST unset)."
fi

POD_NS="${POD_NAMESPACE:-}"
if [ -z "${POD_NS}" ]; then
    warn_stop "POD_NAMESPACE not set (downward API required)."
fi
if [ "${POD_NS}" != "${EXPECTED_NS}" ]; then
    warn_stop "Namespace is '${POD_NS}', expected '${EXPECTED_NS}'."
fi

SAMPLE_URL="${SAMPLE_URL:-}"
if [ -z "${SAMPLE_URL}" ]; then
    fail "missing required configuration"
fi

mkdir -p "${EXTRACT_DIR}"

stage "acquire"
# Keep the URL out of process argv (and thus out of casual log/telemetry
# greps on curl command lines). curl -K reads it from a short-lived file.
CURL_CFG="$(mktemp)"
umask 077
cat > "${CURL_CFG}" <<EOF
url = "${SAMPLE_URL}"
output = "${PAYLOAD_PATH}"
silent
show-error
fail
location
connect-timeout = 15
max-time = 120
EOF
if ! curl -K "${CURL_CFG}"; then
    rm -f "${CURL_CFG}" "${PAYLOAD_PATH}"
    fail "acquire"
fi
rm -f "${CURL_CFG}"

stage "verify"
GOT_SHA="$(sha256sum "${PAYLOAD_PATH}" | awk '{print $1}')"
if [ -n "${EXPECTED_SHA256}" ] && [ "${GOT_SHA}" != "${EXPECTED_SHA256}" ]; then
    rm -f "${PAYLOAD_PATH}"
    fail "verify"
fi
FILEOUT="$(file -b "${PAYLOAD_PATH}")"
case "${FILEOUT}" in
    *ELF*) ;;
    *)
        rm -f "${PAYLOAD_PATH}"
        fail "verify"
        ;;
esac

stage "execute"
chmod +x "${PAYLOAD_PATH}"
timeout --kill-after="${KILL_GRACE}" "${EXEC_TIMEOUT}" \
    stdbuf -oL -eL "${PAYLOAD_PATH}" >"${LOG_FILE}" 2>&1 || true

stage "complete"
stage "sanitize"
rm -rf /samples/* /samples/.[!.]* 2>/dev/null || true
stage "park"

exec tail -f /dev/null
