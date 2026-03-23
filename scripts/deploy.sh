#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:?usage: $0 <localdev|sandbox|staging|production>}"

ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-300s}"

RELEASE_NAME_A="service-a"
RELEASE_NAME_B="service-b"
RELEASE_NAME_WORKER="worker"

LOGGING_NAMESPACE="${LOGGING_NAMESPACE:-logging}"
SERVICE_NAMESPACE="${ENVIRONMENT}"

VALUES_FILE="${HELM_VALUES_DIR:-values}/${ENVIRONMENT}.yaml"
if [[ ! -f "${VALUES_FILE}" ]]; then
  echo "ERROR: ${VALUES_FILE} does not exist."
  exit 1
fi

APP_TOKEN="${APP_TOKEN:?APP_TOKEN env var must be set}"

if [[ "${ENVIRONMENT}" == "localdev" ]] && command -v docker >/dev/null 2>&1; then
  for img in "local/service-a:local" "local/service-b:local" "local/service-worker:local"; do
    if ! docker image inspect "${img}" >/dev/null 2>&1; then
      echo "WARN: Docker image '${img}' not found on this machine."
      echo "      Run: make build-images && make load-images"
    fi
  done
fi

echo "==> Deploying logging stack to namespace: ${LOGGING_NAMESPACE}"
./infra/logging/install.sh "${LOGGING_NAMESPACE}"

echo "==> Deploying services to namespace: ${SERVICE_NAMESPACE}"
kubectl create namespace "${SERVICE_NAMESPACE}" 2>/dev/null || true

helm upgrade --install "${RELEASE_NAME_A}" ./charts/service-a \
  --namespace "${SERVICE_NAMESPACE}" \
  --values "${VALUES_FILE}" \
  --set serviceA.secret.appToken="${APP_TOKEN}"

helm upgrade --install "${RELEASE_NAME_B}" ./charts/service-b \
  --namespace "${SERVICE_NAMESPACE}" \
  --values "${VALUES_FILE}" \
  --set serviceB.secret.appToken="${APP_TOKEN}"

echo "==> Waiting for deployments to become available"

SERVICE_A_DEPLOY="${RELEASE_NAME_A}-${RELEASE_NAME_A}"
SERVICE_B_DEPLOY="${RELEASE_NAME_B}-${RELEASE_NAME_B}"
WORKER_DEPLOY="${RELEASE_NAME_WORKER}-${RELEASE_NAME_WORKER}"

helm upgrade --install "${RELEASE_NAME_WORKER}" ./charts/worker \
  --namespace "${SERVICE_NAMESPACE}" \
  --values "${VALUES_FILE}" \
  --set worker.secret.appToken="${APP_TOKEN}"

wait_rollout() {
  local deploy="$1"
  echo "==> Rollout: ${deploy} (timeout=${ROLLOUT_TIMEOUT})"
  if kubectl -n "${SERVICE_NAMESPACE}" rollout status "deployment/${deploy}" --timeout="${ROLLOUT_TIMEOUT}"; then
    return 0
  fi
  echo
  echo "ERROR: Rollout failed or timed out for deployment/${deploy} in namespace ${SERVICE_NAMESPACE}."
  echo "Common localdev fix: images must exist inside the kind node → make build-images && make load-images"
  echo
  echo "--- kubectl get pods -n ${SERVICE_NAMESPACE} -o wide ---"
  kubectl -n "${SERVICE_NAMESPACE}" get pods -o wide || true
  echo
  echo "--- recent events ---"
  kubectl -n "${SERVICE_NAMESPACE}" get events --sort-by='.lastTimestamp' 2>/dev/null | tail -n 30 || true
  exit 1
}

wait_rollout "${SERVICE_A_DEPLOY}"
wait_rollout "${SERVICE_B_DEPLOY}"
wait_rollout "${WORKER_DEPLOY}"

