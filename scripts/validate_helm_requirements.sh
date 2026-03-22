#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:?usage: $0 <localdev|sandbox|staging|production>}"

VALUES_FILE="values/${ENVIRONMENT}.yaml"
if [[ ! -f "${VALUES_FILE}" ]]; then
  echo "Values file not found: ${VALUES_FILE}"
  exit 2
fi

CHARTS=(
  "service-a ./charts/service-a"
  "service-b ./charts/service-b"
)

FAILURES=0

has_pattern() {
  local pattern="$1"
  local file="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -q "${pattern}" "${file}"
  else
    grep -Eq "${pattern}" "${file}"
  fi
}

render_and_check() {
  local release_name="$1"
  local chart_path="$2"
  local ns="$ENVIRONMENT"

  echo
  echo "==> Validating requirements for ${release_name} (env=${ENVIRONMENT})"

  local rendered
  rendered="$(mktemp)"

  helm template "${release_name}-${ENVIRONMENT}" "${chart_path}" -n "${ns}" -f "${VALUES_FILE}" > "${rendered}"

  check() {
    local desc="$1"
    local pattern="$2"
    if ! has_pattern "${pattern}" "${rendered}"; then
      echo "FAIL: ${desc}"
      FAILURES=$((FAILURES + 1))
    else
      echo "OK:   ${desc}"
    fi
  }

  check "readinessProbe exists" "readinessProbe:"
  check "livenessProbe exists" "livenessProbe:"

  check "ConfigMap wiring exists (configMapKeyRef present)" "configMapKeyRef:"
  check "ConfigMap key used (LOG_LEVEL)" "key:[[:space:]]*LOG_LEVEL"
  check "Secret wiring exists (secretKeyRef present)" "secretKeyRef:"
  check "Secret key used (APP_TOKEN)" "key:[[:space:]]*APP_TOKEN"

  # resources must have non-empty requests/limits. We do a heuristic check that
  # they are not rendered as empty objects.
  if has_pattern "requests:\s*\{\}" "${rendered}"; then
    echo "FAIL: resources.requests is empty"
    FAILURES=$((FAILURES + 1))
  else
    echo "OK:   resources.requests is non-empty (heuristic)"
  fi
  if has_pattern "limits:\s*\{\}" "${rendered}"; then
    echo "FAIL: resources.limits is empty"
    FAILURES=$((FAILURES + 1))
  else
    echo "OK:   resources.limits is non-empty (heuristic)"
  fi

  # securityContext should harden at least runAsNonRoot; allow missing if candidate documents,
  # but default scoring should expect it.
  check "securityContext hardening (runAsNonRoot)" "runAsNonRoot:\s*true"
  check "securityContext drop capabilities present" "capabilities:\s*$"

  # RBAC rolebinding + role rules should not be empty.
  check "ServiceAccount present" "kind: ServiceAccount"
  check "RoleBinding present" "kind: RoleBinding"
  if has_pattern "verbs:\s*\[\s*\]" "${rendered}"; then
    echo "FAIL: RBAC role rules verbs are empty (verbs: [])"
    FAILURES=$((FAILURES + 1))
  else
    echo "OK:   RBAC role rules verbs are non-empty"
  fi

  rm -f "${rendered}"
}

for entry in "${CHARTS[@]}"; do
  # shellcheck disable=SC2206
  set -- ${entry}
  render_and_check "$1" "$2"
done

if [[ "${FAILURES}" -ne 0 ]]; then
  echo
  echo "Validation failed with ${FAILURES} failure(s)."
  exit 1
fi

echo
echo "All helm requirements checks passed (heuristics)."

