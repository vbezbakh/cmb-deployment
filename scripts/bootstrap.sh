#!/usr/bin/env bash
# From nothing to the full stack on minikube, in one command:
#   minikube -> secrets -> Argo CD -> (Git takes over) -> CNPG operator -> Postgres -> app
# Safe to re-run: every step skips work that is already done.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require minikube kubectl helm openssl curl

ARGOCD_CHART_VERSION=10.11.6 # Argo CD v3.5.6
KUBERNETES_VERSION=v1.34.0

step "1/6 minikube"
if minikube status >/dev/null 2>&1; then
  ok "cluster already running"
else
  minikube start --driver=docker \
    --cpus="${MINIKUBE_CPUS:-4}" --memory="${MINIKUBE_MEMORY:-5g}" \
    --kubernetes-version="$KUBERNETES_VERSION"
fi
minikube addons enable ingress >/dev/null
minikube addons enable metrics-server >/dev/null
kubectl config use-context minikube >/dev/null
ok "ingress and metrics-server addons enabled"

step "2/6 secrets (generated locally, never committed)"
"$ROOT/scripts/create-secrets.sh"

step "3/6 Argo CD"
if helm list -n "$ARGO_NS" --filter '^argocd$' --output yaml 2>/dev/null |
  grep -q "chart: argo-cd-${ARGOCD_CHART_VERSION}$"; then
  ok "Argo CD ${ARGOCD_CHART_VERSION} already installed"
else
  helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
  helm upgrade --install argocd argo/argo-cd --version "$ARGOCD_CHART_VERSION" \
    --namespace "$ARGO_NS" --create-namespace \
    --values "$ROOT/argocd/values.yaml" --wait --timeout 10m >/dev/null
  ok "Argo CD installed"
fi

step "4/6 hand over to Git"
kubectl apply -f "$ROOT/argocd/root.yaml" >/dev/null
ok "root app applied; everything else is synced from github.com/vbezbakh/cmb-deployment"

step "5/6 sync (operator -> database -> app)"
# Each Application only appears once the previous wave is healthy, so a missing app simply
# counts as "not ready yet".
for app in cnpg-operator database cmb-app; do
  wait_for "$app synced and healthy" 900 app_healthy "$app"
done

step "6/6 smoke test through the ingress"
start_ingress_port_forward
API_URL=$BASE_URL WEBHOOKS_URL=$BASE_URL WEBHOOK_SECRET=$(webhook_secret) \
  "$ROOT/scripts/smoke-test.sh"

password=$(kubectl -n "$ARGO_NS" get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode)
cat <<EOF

$(printf '\033[1;32m')Done.$(printf '\033[0m')

  App (via ingress):  kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller ${INGRESS_PORT}:80
                      curl ${BASE_URL}/api/v1/items
  Argo CD UI:         kubectl -n argocd port-forward svc/argocd-server 8443:80
                      http://localhost:8443  (admin / ${password})
  Demos:              scripts/demo/*.sh
EOF
