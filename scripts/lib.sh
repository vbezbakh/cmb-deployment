# Shared helpers, sourced by the other scripts.
# shellcheck shell=bash disable=SC2034  # variables are used by the scripts that source this file
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NS=cmb
DB_NS=database
ARGO_NS=argocd
INGRESS_PORT=${INGRESS_PORT:-8080}
BASE_URL="http://localhost:${INGRESS_PORT}"
# In-cluster address of the ingress controller, used by the load generator so that load goes
# through the same path as real traffic (ingress -> Service -> pods).
INGRESS_IN_CLUSTER=http://ingress-nginx-controller.ingress-nginx.svc.cluster.local
FORTIO_IMAGE=fortio/fortio:1.76.0

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok() { printf '\033[32m✓\033[0m %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die() {
  printf '\033[31m✗ %s\033[0m\n' "$*" >&2
  exit 1
}

require() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null || die "missing required tool: $tool"
  done
}

# wait_for <description> <timeout seconds> <command...>
wait_for() {
  local what=$1 timeout=$2 start=$SECONDS
  shift 2
  info "waiting for ${what}..."
  until "$@" >/dev/null 2>&1; do
    ((SECONDS - start > timeout)) && die "timed out after ${timeout}s waiting for: $what"
    sleep 5
  done
  ok "$what ($((SECONDS - start))s)"
}

app_healthy() {
  [[ "$(kubectl -n "$ARGO_NS" get application "$1" \
    -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)" == "Synced/Healthy" ]]
}

# Forward the ingress controller to localhost for the rest of the calling script.
start_ingress_port_forward() {
  kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller "${INGRESS_PORT}:80" >/dev/null 2>&1 &
  PORT_FORWARD_PID=$!
  trap 'kill "$PORT_FORWARD_PID" 2>/dev/null || true' EXIT
  wait_for "ingress on localhost:${INGRESS_PORT}" 30 curl -s -o /dev/null "${BASE_URL}/"
}

webhook_secret() {
  kubectl -n "$APP_NS" get secret cmb-app-secrets -o jsonpath='{.data.WEBHOOK_SIGNING_SECRET}' |
    base64 --decode | cut -d, -f1
}

# sign_webhook <secret> <body> [timestamp] -> value for the Payment-Signature header
sign_webhook() {
  local ts=${3:-$(date +%s)} sig
  sig=$(printf '%s.%s' "$ts" "$2" | openssl dgst -sha256 -hmac "$1" | awk '{print $NF}')
  printf 't=%s,v1=%s' "$ts" "$sig"
}

# Run fortio inside the cluster: load <name> <fortio args...>
load() {
  local name=$1
  shift
  kubectl -n "$APP_NS" delete pod "$name" --ignore-not-found >/dev/null
  kubectl -n "$APP_NS" run "$name" --image="$FORTIO_IMAGE" --restart=Never --quiet \
    --rm -i -- load -quiet "$@" 2>&1 | grep -E '^(Code|All done|# target 99%|Sockets used)' || true
}

current_primary() {
  kubectl -n "$DB_NS" get cluster cmb-pg -o jsonpath='{.status.currentPrimary}'
}
