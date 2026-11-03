#!/usr/bin/env bash
# Autoscaling: drive the API hard for 3 minutes and watch the HPA add pods.
# Scale-up is aggressive (up to +100% every 30s); scale-down waits 5 minutes.
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

step "Unthrottled load (16 connections) for 180s; HPA every 20s"
(
  for _ in $(seq 1 9); do
    sleep 20
    kubectl -n "$APP_NS" get hpa cmb-app-api --no-headers \
      -o custom-columns=TARGETS:.status.currentMetrics[0].resource.current.averageUtilization,REPLICAS:.status.currentReplicas,DESIRED:.status.desiredReplicas |
      awk '{printf "  cpu %s%% of request, replicas %s, desired %s\n", $1, $2, $3}'
  done
) &
load autoscale-load -qps 0 -c 16 -t 180s "$INGRESS_IN_CLUSTER/api/v1/items"
wait
kubectl -n "$APP_NS" get hpa
