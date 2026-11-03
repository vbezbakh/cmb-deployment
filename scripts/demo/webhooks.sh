#!/usr/bin/env bash
# Payment webhooks: signature verification, replay protection and idempotency.
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"
start_ingress_port_forward
secret=$(webhook_secret)
body="{\"id\":\"evt_demo_$(date +%s)\",\"type\":\"payment.succeeded\",\"data\":{\"amount\":1299}}"
send() {
  printf '  %-34s -> ' "$1"
  curl -s -w ' (HTTP %{http_code})\n' -X POST "$BASE_URL/webhooks/payments" -H "Payment-Signature: $2" -d "$3"
}

step "Deliveries"
signature=$(sign_webhook "$secret" "$body")
send "valid signature" "$signature" "$body"
send "same event delivered again" "$signature" "$body"
send "body tampered after signing" "$signature" "${body/1299/1}"
send "signed with the wrong secret" "$(sign_webhook wrong-secret "$body")" "$body"
send "replayed 10 minutes later" "$(sign_webhook "$secret" "$body" $(($(date +%s) - 600)))" "$body"

step "Outcomes recorded by the webhooks pod (/metrics)"
kubectl -n "$APP_NS" exec deploy/cmb-app-webhooks -- python -c \
  "import urllib.request; print(urllib.request.urlopen('http://localhost:8000/metrics').read().decode())" |
  grep '^payment_webhooks_total'
