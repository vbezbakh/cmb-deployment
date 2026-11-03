#!/usr/bin/env bash
# Create the two Secrets the local stack needs (once; existing Secrets are kept).
# Values are generated here and never written to Git. In real clusters External Secrets
# creates cmb-app-secrets from the cloud secret manager instead.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

DB_RW=cmb-pg-pooler-rw.${DB_NS}.svc.cluster.local
DB_RO=cmb-pg-pooler-ro.${DB_NS}.svc.cluster.local

for ns in "$DB_NS" "$APP_NS"; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
done

if kubectl -n "$DB_NS" get secret cmb-pg-app-credentials >/dev/null 2>&1; then
  password=$(kubectl -n "$DB_NS" get secret cmb-pg-app-credentials -o jsonpath='{.data.password}' | base64 --decode)
  ok "database credentials already exist"
else
  password=$(openssl rand -hex 24)
  kubectl -n "$DB_NS" create secret generic cmb-pg-app-credentials \
    --type=kubernetes.io/basic-auth \
    --from-literal=username=app \
    --from-literal=password="$password" >/dev/null
  ok "created database credentials (${DB_NS}/cmb-pg-app-credentials)"
fi

if kubectl -n "$APP_NS" get secret cmb-app-secrets >/dev/null 2>&1; then
  ok "app secrets already exist"
else
  kubectl -n "$APP_NS" create secret generic cmb-app-secrets \
    --from-literal=DATABASE_URL="postgresql://app:${password}@${DB_RW}:5432/app" \
    --from-literal=DATABASE_READ_URL="postgresql://app:${password}@${DB_RO}:5432/app" \
    --from-literal=WEBHOOK_SIGNING_SECRET="$(openssl rand -hex 32)" >/dev/null
  ok "created app secrets (${APP_NS}/cmb-app-secrets)"
fi
