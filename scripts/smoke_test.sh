#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:?usage: $0 <localdev|sandbox|staging|production>}"
SERVICE_NAMESPACE="${ENVIRONMENT}"
LOGGING_NAMESPACE="${LOGGING_NAMESPACE:-logging}"

RELEASE_NAME_A="service-a"
RELEASE_NAME_B="service-b"
RELEASE_NAME_WORKER="worker"
SERVICE_A_NAME="${RELEASE_NAME_A}-${RELEASE_NAME_A}"
SERVICE_B_NAME="${RELEASE_NAME_B}-${RELEASE_NAME_B}"
WORKER_DEPLOY="${RELEASE_NAME_WORKER}-${RELEASE_NAME_WORKER}"

echo "==> Smoke test: health endpoints"

kubectl -n "${SERVICE_NAMESPACE}" wait --for=condition=available --timeout=120s "deployment/${SERVICE_A_NAME}" 2>/dev/null || true
kubectl -n "${SERVICE_NAMESPACE}" wait --for=condition=available --timeout=120s "deployment/${SERVICE_B_NAME}" 2>/dev/null || true
kubectl -n "${SERVICE_NAMESPACE}" wait --for=condition=available --timeout=120s "deployment/${WORKER_DEPLOY}" 2>/dev/null || true

kubectl -n "${SERVICE_NAMESPACE}" run --rm -i --restart=Never curl-a \
  --image=curlimages/curl:8.6.0 \
  -- curl -sSf "http://${SERVICE_A_NAME}:8080/healthz" | cat >/dev/null

kubectl -n "${SERVICE_NAMESPACE}" run --rm -i --restart=Never curl-b \
  --image=curlimages/curl:8.6.0 \
  -- curl -sSf "http://${SERVICE_B_NAME}:8080/healthz" | cat >/dev/null

echo "==> Health endpoints OK"

if [[ -x "./scripts/loki_query.sh" ]]; then
  echo "==> Logging ingestion check (strict)"
  ./scripts/loki_query.sh "${ENVIRONMENT}" "${LOGGING_NAMESPACE}" "service-a"
  ./scripts/loki_query.sh "${ENVIRONMENT}" "${LOGGING_NAMESPACE}" "service-b"

  echo "==> Triggering worker enqueue_once inside consumer pod"
  POD_NAME="$(
    kubectl -n "${SERVICE_NAMESPACE}" get pods \
      -l "app.kubernetes.io/name=worker,app.kubernetes.io/instance=${RELEASE_NAME_WORKER},app.kubernetes.io/component=consumer" \
      -o jsonpath='{.items[0].metadata.name}'
  )"

  if [[ -z "${POD_NAME}" ]]; then
    echo "FAIL: Could not find worker consumer pod (namespace=${SERVICE_NAMESPACE})."
    exit 1
  fi

  kubectl -n "${SERVICE_NAMESPACE}" exec "${POD_NAME}" -- python /app/app.py --mode enqueue_once
  ./scripts/loki_query.sh "${ENVIRONMENT}" "${LOGGING_NAMESPACE}" "worker" "queue_processed"
fi

