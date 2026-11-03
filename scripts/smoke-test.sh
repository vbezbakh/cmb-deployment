#!/usr/bin/env bash
# End-to-end checks against a running deployment. Used by bootstrap.sh and by CI.
#   API_URL, WEBHOOKS_URL  base URLs (the same ingress URL locally, two port-forwards in CI)
#   WEBHOOK_SECRET         the payment webhook signing secret
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
: "${API_URL:?}" "${WEBHOOKS_URL:?}" "${WEBHOOK_SECRET:?}"

failures=0
expect() {
  local description=$1 expected=$2 actual=$3
  if [[ "$actual" == "$expected" ]]; then
    ok "$description"
  else
    printf '\033[31m✗\033[0m %s: expected %s, got %s\n' "$description" "$expected" "$actual"
    failures=$((failures + 1))
  fi
}

status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

name="smoke-$(date +%s)"
created=$(curl -s -X POST "$API_URL/api/v1/items" -H 'content-type: application/json' -d "{\"name\":\"$name\"}")
id=$(printf '%s' "$created" | sed -nE 's/.*"id":([0-9]+).*/\1/p')
expect "create item" "$name" "$(printf '%s' "$created" | sed -nE 's/.*"name":"([^"]+)".*/\1/p')"
expect "read item back from the primary" 200 "$(status "$API_URL/api/v1/items/$id")"
expect "list items from the replica pool" 200 "$(status "$API_URL/api/v1/items")"

body="{\"id\":\"evt_${name}\",\"type\":\"payment.succeeded\"}"
signature=$(sign_webhook "$WEBHOOK_SECRET" "$body")
post_webhook() {
  curl -s -X POST "$WEBHOOKS_URL/webhooks/payments" -H "Payment-Signature: $1" -d "$body"
}
expect "signed webhook is accepted" '{"status":"accepted"}' "$(post_webhook "$signature")"
expect "redelivered webhook is deduplicated" '{"status":"duplicate"}' "$(post_webhook "$signature")"
expect "forged webhook is rejected" 401 \
  "$(status -X POST "$WEBHOOKS_URL/webhooks/payments" -H "Payment-Signature: t=$(date +%s),v1=forged" -d "$body")"

((failures == 0)) || die "$failures smoke check(s) failed"
ok "all smoke checks passed"
