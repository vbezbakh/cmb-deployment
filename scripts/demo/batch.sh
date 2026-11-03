#!/usr/bin/env bash
# Daily batch job: trigger it by hand twice for today and show the result is the same
# (idempotent upsert), which is what makes retries and re-runs safe.
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"
today=$(date -u +%Y-%m-%d)

run_batch() {
  local job
  job="batch-manual-$(date +%s)"
  kubectl -n "$APP_NS" create job "$job" --from=cronjob/cmb-app-batch --dry-run=client -o json |
    jq --arg day "$today" '.spec.template.spec.containers[0].args = ["--date", $day]' |
    kubectl -n "$APP_NS" create -f - >/dev/null
  kubectl -n "$APP_NS" wait "job/$job" --for=condition=Complete --timeout=120s >/dev/null
  kubectl -n "$APP_NS" logs "job/$job" | grep '"batch finished"' | jq -c '{msg, day, rows_written}'
}

step "Run 1 for $today"
run_batch
step "Run 2 for the same day (same rows, no double counting)"
run_batch

step "daily_payment_summary on the primary"
kubectl -n "$DB_NS" exec "$(current_primary)" -c postgres -- \
  psql -d app -c "SELECT day, event_type, event_count FROM daily_payment_summary WHERE day = '$today'"
