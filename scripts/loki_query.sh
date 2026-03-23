#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:?usage: $0 <environment-namespace> <logging-namespace> <service-label> [log-substring]}"
LOGGING_NAMESPACE="${2:?usage: $0 <environment-namespace> <logging-namespace> <service-label> [log-substring]}"
SERVICE_LABEL="${3:?usage: $0 <environment-namespace> <logging-namespace> <service-label> [log-substring]}"
LOG_SUBSTRING="${4:-healthz_ok}"

QUERY='{namespace="'${ENVIRONMENT}'",service="'${SERVICE_LABEL}'"} |= "'${LOG_SUBSTRING}'"'

PORT="${LOKI_PORT:-3100}"
LOCAL_URL="http://127.0.0.1:${PORT}"

cleanup() {
  if [[ -n "${PF_PID:-}" ]]; then
    kill "${PF_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "==> Loki query: ${QUERY}"
echo "==> Port-forwarding loki (namespace=${LOGGING_NAMESPACE}) to localhost:${PORT}"

kubectl -n "${LOGGING_NAMESPACE}" port-forward "svc/loki" "${PORT}:3100" >/tmp/loki-port-forward.log 2>&1 &
PF_PID="$!"

for _ in $(seq 1 20); do
  if curl -sf "${LOCAL_URL}/ready" >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

echo "==> Querying Loki for ingested health logs (with retries)"
count=0
for _ in $(seq 1 30); do
  resp="$(
    curl -sf -G "${LOCAL_URL}/loki/api/v1/query" \
      --data-urlencode "query=${QUERY}"
  )" || true

  if [[ -n "${resp:-}" ]]; then
    count="$(
      echo "${resp}" | python3 -c "
import json,sys
raw=sys.stdin.read()
data=json.loads(raw)
results=data.get('data',{}).get('result',[])
print(len(results))
"
    )" || count=0
  fi

  echo "==> Loki results: ${count} stream(s)"
  if [[ "${count}" -ge 1 ]]; then
    break
  fi
  sleep 1
done

if [[ "${count}" -lt 1 ]]; then
  echo "FAIL: No '${LOG_SUBSTRING}' logs found for namespace=${ENVIRONMENT}, service=${SERVICE_LABEL}"
  exit 1
fi

echo "OK: Loki ingestion verified."
exit 0

