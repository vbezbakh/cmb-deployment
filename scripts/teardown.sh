#!/usr/bin/env bash
# Delete the local cluster and everything in it.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
require minikube

step "deleting the minikube cluster"
minikube delete
ok "done; run scripts/bootstrap.sh to start again"
