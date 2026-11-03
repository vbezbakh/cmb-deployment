#!/usr/bin/env bash
# Zero-downtime rollout: restart every API pod while 50 req/s flow through the ingress.
# Expect 100% HTTP 200: maxUnavailable 0, readiness gating, preStop sleep and uvicorn's
# graceful drain together mean no request is dropped.
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

step "Rolling restart of the API in 10s, under 50 req/s for 60s"
(
  sleep 10
  kubectl -n "$APP_NS" rollout restart deployment/cmb-app-api >/dev/null
  info "rollout started"
  kubectl -n "$APP_NS" rollout status deployment/cmb-app-api --timeout=120s >/dev/null
  info "rollout finished"
) &
load rollout-load -qps 50 -c 4 -t 60s "$INGRESS_IN_CLUSTER/api/v1/items"
wait
ok "pods now running:"
kubectl -n "$APP_NS" get pods -l app.kubernetes.io/component=api
