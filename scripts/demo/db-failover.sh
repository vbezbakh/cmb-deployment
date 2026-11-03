#!/usr/bin/env bash
# Database failover: crash the Postgres primary (force-delete, like a node dying) while the
# API is taking writes. A plain delete would trigger a *graceful* shutdown, where Postgres waits
# up to smartShutdownTimeout for clients to disconnect before CloudNativePG fails over.
# CloudNativePG promotes a replica; PgBouncer reconnects to the new primary. The app answers
# 503 + Retry-After for the few seconds the primary is gone (never 500), and no app pod
# restarts, because liveness and readiness deliberately do not depend on the database.
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

old=$(current_primary)
step "Current primary: $old. Sending 20 writes/s for 60s and crashing it after 10s"
(
  sleep 10
  kubectl -n "$DB_NS" delete pod "$old" --grace-period=0 --force >/dev/null 2>&1
  start=$SECONDS
  info "crashed $old"
  until new=$(current_primary) && [[ -n "$new" && "$new" != "$old" ]]; do
    ((SECONDS - start > 120)) && {
      info "no new primary after 120s"
      exit 1
    }
    sleep 1
  done
  info "new primary: $new (promoted after ~$((SECONDS - start))s)"
) &
load failover-load -qps 20 -c 4 -t 60s \
  -content-type application/json -payload '{"name":"failover-demo"}' \
  "$INGRESS_IN_CLUSTER/api/v1/items"
wait

step "App pod restarts during the failover (expect 0)"
kubectl -n "$APP_NS" get pods -l app.kubernetes.io/name=cmb-app \
  -o custom-columns=POD:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount
step "Postgres cluster"
kubectl -n "$DB_NS" get cluster cmb-pg
