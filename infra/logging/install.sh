#!/usr/bin/env bash
set -euo pipefail

LOGGING_NAMESPACE="${1:?usage: $0 <namespace>}"

echo "==> Ensuring logging namespace exists: ${LOGGING_NAMESPACE}"
kubectl create namespace "${LOGGING_NAMESPACE}" 2>/dev/null || true

echo "==> Applying logging stack manifests"
if [[ -d "./infra/logging/manifests" ]] && compgen -G "./infra/logging/manifests/*.yaml" > /dev/null; then
  kubectl apply -n "${LOGGING_NAMESPACE}" -f ./infra/logging/manifests
else
  echo "No logging manifests found yet in infra/logging/manifests. (Fill in the logging stack.)"
fi

echo "==> Waiting for Loki/Grafana/Promtail"
kubectl -n "${LOGGING_NAMESPACE}" rollout status "deployment/loki" --timeout=120s >/dev/null 2>&1 || true
kubectl -n "${LOGGING_NAMESPACE}" rollout status "deployment/grafana" --timeout=120s >/dev/null 2>&1 || true
kubectl -n "${LOGGING_NAMESPACE}" rollout status "daemonset/promtail" --timeout=120s >/dev/null 2>&1 || true


