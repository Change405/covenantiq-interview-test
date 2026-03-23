# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Context

This is a DevOps take-home assessment. Venky (founder of CovenantIQ) **intentionally broke several things** across the repo. The goal is to find and fix all breakages, understanding the *why* behind each one.

All commands should be run from the `InterviewDevOps/` directory (the repo root).

---

## Common Commands

### Cluster lifecycle
```bash
make kind-up          # Create local kind cluster (named local-takehome)
make kind-down        # Destroy it
make build-images     # Build all 3 Docker images
make load-images      # Push built images into the kind cluster
```

### Deploy & smoke test
```bash
make deploy-localdev  # Runs scripts/deploy.sh localdev
make smoke-localdev   # Runs scripts/smoke_test.sh localdev
# Same pattern for: sandbox, staging, production
```

### Helm validation
```bash
helm lint ./charts/service-a
helm lint ./charts/service-b
helm lint ./charts/worker

# Render a chart for inspection
helm template "service-a-localdev" ./charts/service-a -n localdev -f values/localdev.yaml | less

# Validate all requirements (probes, resources, securityContext, RBAC, wiring) for an env
./scripts/validate_helm_requirements.sh localdev
# Run for all environments
for env in localdev sandbox staging production; do ./scripts/validate_helm_requirements.sh "$env"; done
```

### Logging verification
```bash
# Port-forward Grafana
kubectl -n logging port-forward svc/grafana 3000:80
# Then open http://localhost:3000 — anonymous access enabled, Loki pre-configured as datasource

# Programmatic Loki check (used by smoke tests)
./scripts/loki_query.sh localdev logging service-a
./scripts/loki_query.sh localdev logging service-b
./scripts/loki_query.sh localdev logging worker queue_processed
```

### Security scanning (requires `pip install checkov`)
```bash
mkdir -p tmp/rendered
for env in localdev sandbox staging production; do
  helm template "service-a-${env}" ./charts/service-a -n "${env}" -f "values/${env}.yaml" > "tmp/rendered/service-a-${env}.yaml"
  helm template "service-b-${env}" ./charts/service-b -n "${env}" -f "values/${env}.yaml" > "tmp/rendered/service-b-${env}.yaml"
done
checkov -d tmp/rendered --check "CKV_K8S_6,CKV_K8S_8,CKV_K8S_9,CKV_K8S_10,CKV_K8S_11,CKV_K8S_12,CKV_K8S_13,CKV_K8S_36"
```

---

## Architecture

### Services
- **service-a** — Node.js/Express, port 8080. Emits JSON logs to stdout on every `/healthz` hit (`event: "healthz_ok"`).
- **service-b** — Python/FastAPI, port 8080. Same JSON log contract as service-a.
- **worker** — Python queue consumer. Reads from `/queue/messages`, moves processed items to `/queue/processed`. Emits `queue_processed` logs. Also accepts `--mode enqueue_once` to manually enqueue a test message (used by smoke tests). Runs a CronJob alongside the Deployment.

All three use the same env var contract: `SERVICE_NAME`, `APP_ENV`, `LOG_LEVEL` (from ConfigMap), `APP_TOKEN` (from Secret).

### Helm Charts & Value Wiring
Each chart under `charts/` has empty-by-default values for `probes`, `resources`, and `securityContext`. These **must be filled in via environment overlays** in `values/<env>.yaml`. The chart templates gate on empty values (e.g., `readinessProbe` is only rendered if `probes.readinessPath` is non-empty).

Helm deployment naming convention: release name `service-a` → Deployment named `service-a-service-a`. The smoke test and deploy scripts rely on this pattern.

### SDLC Environments
Four environments (`localdev`, `sandbox`, `staging`, `production`) share identical charts; only `values/<env>.yaml` overlays differ. **Locally**, each environment is a separate namespace in the same kind cluster. **In CI**, each deploy job creates a fresh ephemeral kind cluster (e.g. `kind-sandbox`) and tears it down after the smoke test. The logging stack always deploys to the `logging` namespace regardless of environment.

### Logging Stack (`infra/logging/manifests/stack.yaml`)
- **Loki** — log aggregation backend, port 3100
- **Grafana** — visualization, port 80 (anonymous admin access). Loki auto-configured as datasource.
- **Promtail** — DaemonSet that tails container logs and ships to Loki

Promtail must be configured to relabel Kubernetes pod metadata into stream labels (`namespace`, `pod`, `container`, `service`). The smoke tests and `loki_query.sh` query Loki using `{namespace="<env>", service="<service-name>"}` — if Promtail doesn't emit those labels, Loki queries return 0 results and smoke tests fail.

### CI Pipeline (`.github/workflows/takehome-ci.yml`)
Progressive quality gates:
1. `lint` → `render` → `security` → `deploy-sandbox` → `deploy-staging` → `deploy-production`

Each deploy job spins up a **fresh ephemeral kind cluster**, builds/loads images, runs `scripts/deploy.sh <env>`, then `scripts/smoke_test.sh <env>`, then tears down the cluster. `deploy-production` uses a GitHub `environment:` requiring manual approval.

---

## Change Justification

For every value added or replaced in this repo, document *why* that specific value was chosen — not just what changed. This applies to Helm values, resource limits, probe paths, security contexts, RBAC verbs, ConfigMap keys, etc. If a value was broken intentionally, explain what the correct value is and why it fixes the issue.

All justifications are recorded in `docs/justifications.md`.

---

## Validation Contract

`scripts/validate_helm_requirements.sh` checks (via regex on rendered YAML):
- `readinessProbe:` and `livenessProbe:` present
- `configMapKeyRef:` with key `LOG_LEVEL`
- `secretKeyRef:` with key `APP_TOKEN`
- `resources.requests` and `resources.limits` are non-empty objects
- `runAsNonRoot: true` and `capabilities:` (drop ALL)
- `kind: ServiceAccount`, `kind: RoleBinding`, and non-empty RBAC `verbs`

`scripts/loki_query.sh` port-forwards to Loki's HTTP API and queries `{namespace="<env>", service="<svc>"} |= "<substring>"`, failing if 0 streams are returned after 30 retries.
