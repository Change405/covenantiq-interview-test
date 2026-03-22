# Validation guide (Tasks 1–4)

The main [`README.md`](README.md) describes **what** to implement. This document maps each task to **how to validate** it using the repo’s scripts and CI—so you can run the same checks locally that the pipeline expects.

| Task | Focus | Primary scripts / automation |
| --- | --- | --- |
| **1** | Helm defaults (probes, resources, security, RBAC, ConfigMap/Secret) | `scripts/validate_helm_requirements.sh`, `helm lint` |
| **2** | Logging labels + Loki ingestion | `scripts/smoke_test.sh` → `scripts/loki_query.sh`; **details:** [`runbook.md`](runbook.md) |
| **3** | Four env overlays, same charts | `helm template` (all envs) + `scripts/deploy.sh` + `make smoke-*` |
| **4** | CI quality gates | [`.github/workflows/takehome-ci.yml`](.github/workflows/takehome-ci.yml) (push/PR) or mirror commands below |

Run commands from the **repository root** (`InterviewDevOps`).

---

## Prerequisites

- `docker`, `kubectl`, `helm` (v3), `kind`, `curl`, `python3` (see [`README.md`](README.md))
- For Task 4 security scanning locally: `checkov` (same as CI: `pip install checkov`)

---

## Task 1 — Helm: production-minded defaults

### Script: `scripts/validate_helm_requirements.sh`

This script **renders** `charts/service-a` and `charts/service-b` with `values/<environment>.yaml` and checks (heuristically) that manifests include:

- `readinessProbe` / `livenessProbe`
- Non-empty `resources` requests/limits
- Hardened `securityContext` (e.g. `runAsNonRoot`, capability drops)
- `ConfigMap` / `Secret` wiring (`configMapKeyRef` / `secretKeyRef`)
- ServiceAccount + RoleBinding + non-empty RBAC `verbs`

```bash
chmod +x scripts/validate_helm_requirements.sh

# Validate every environment (recommended locally)
for env in localdev sandbox staging production; do
  ./scripts/validate_helm_requirements.sh "$env"
done
```

**Note:** The validator covers the **two backend HTTP charts** (`service-a`, `service-b`). The `worker` chart is validated indirectly via deploy/smoke (Task 2) and `helm lint` (Task 4 lint job).

### Lint (also used in CI `lint` job)

```bash
helm lint ./charts/service-a
helm lint ./charts/service-b
helm lint ./charts/worker
```

### Optional manual inspection

```bash
helm template "service-a-localdev" ./charts/service-a -n localdev -f values/localdev.yaml | less
```

Confirm ClusterIP `Service` and other chart objects as required by [`README.md`](README.md).

---

## Task 2 — Logging: centralized logs + labels

There is **no separate “task-2-only” script name**, but validation is **built into** the smoke test and documented for **Grafana / LogQL** in the runbook.

### Automated: `scripts/smoke_test.sh`

After deployments are up, the smoke test:

1. Calls each backend’s `/healthz` (via ephemeral `curl` pods).
2. Runs **`scripts/loki_query.sh`** to assert logs exist in Loki for `service-a` and `service-b`.
3. Triggers worker enqueue and checks **`queue_processed`** via `loki_query.sh`.

Example (after cluster + images + deploy):

```bash
make deploy-localdev   # or: ./scripts/deploy.sh localdev
make smoke-localdev    # or: ./scripts/smoke_test.sh localdev
```

Use the same pattern for other environments, e.g. `make smoke-staging`.

### Programmatic Loki checks: `scripts/loki_query.sh`

Direct usage (same as invoked from smoke tests):

```bash
./scripts/loki_query.sh <env-namespace> <logging-namespace> <service-label> [log-substring]

# Examples (logging namespace defaults to `logging` in Makefile/runbook)
./scripts/loki_query.sh localdev logging service-a
./scripts/loki_query.sh localdev logging service-b
./scripts/loki_query.sh localdev logging worker queue_processed
```

### Grafana, LogQL, labels, troubleshooting — see **`runbook.md`**

For **namespace / pod / container** label expectations, **Grafana port-forward**, example **LogQL** queries, and **troubleshooting** (Promtail, Loki, “0 results”), use:

- **[`runbook.md`](runbook.md)** — primary reference for logging verification and evidence (e.g. screenshot of query filtered by `namespace`).

**Task 2 hands-on:** `infra/logging/manifests/stack.yaml` is shipped **without** a working Promtail. Restore them until **Grafana** LogQL (see `runbook.md`) and **`loki_query.sh` / `smoke_test.sh`** succeed.

---

## Task 3 — SDLC: four environments, same charts

There is **no single script named `validate-task3.sh`**. Validation is:

### Step 1 — Render all four overlays

Render all four value files with the **same** chart paths (no per-env chart forks):

```bash
for env in localdev sandbox staging production; do
  helm template "service-a-${env}" ./charts/service-a -n "${env}" -f "values/${env}.yaml" > "/tmp/service-a-${env}.yaml"
  helm template "service-b-${env}" ./charts/service-b -n "${env}" -f "values/${env}.yaml" > "/tmp/service-b-${env}.yaml"
done
```

### Step 2 — Deploy proof (README: localdev + staging)

README acceptance: deploy at least `localdev` and `staging`:

```bash
make kind-up          # once
make build-images
make load-images

make deploy-localdev
make smoke-localdev

make deploy-staging
make smoke-staging
```

`scripts/deploy.sh <env>` always uses `values/<env>.yaml` for `service-a`, `service-b`, and `worker`—that is the “swap values only” contract.

**Task 3 hints:** All four of `values/localdev.yaml`, `values/sandbox.yaml`, `values/staging.yaml`, and `values/production.yaml` are incomplete for services. Need to be fixed until `validate_helm_requirements.sh` and deploy/smokes succeed for each environment.

**Task 3 (`deploy.sh`):** `scripts/deploy.sh` uses a **placeholder** `VALUES_FILE` path until you set the real overlay pattern. Until fixed, deploy exits before Helm runs.

---

## Task 4 — CI quality gates

Validation is the **GitHub Actions workflow** in **`.github/workflows/takehome-ci.yml`** (runs on push/PR to `main`).

Stages (names in the workflow):

1. **`lint`** — `helm lint` on all three charts  
2. **`render`** — `helm template` for `service-a` and `service-b` for **all four** envs  
3. **`security`** — render to `tmp/rendered`, run **checkov** on selected checks; run `validate_helm_requirements.sh` for **all four** envs  
4. **`deploy-sandbox`** — ephemeral `kind`, build/load images, `./scripts/deploy.sh sandbox`, `./scripts/smoke_test.sh sandbox`  
5. **`deploy-staging`** — same for `staging`  
6. **`deploy-production`** — same for `production` (job may use environment protection)

**Task 4 hands-on (workflow):** `.github/workflows/takehome-ci.yml` contains **intentional gaps** you must close:

| Job | What to fix |
| --- | --- |
| **`lint`** | Add `helm lint` for all services; remove the failing `exit` lines. |
| **`render`** | Extend it for all environments ; remove the failing `exit` lines. |
| **`security`** | Set **`CHECKOV_DIR`** to match the render step in that job; uncomment and run the **`validate_helm_requirements.sh`** loop for all envs; remove the failing `exit` lines. |
| **`deploy-*`** | Depends on fixing **`scripts/deploy.sh`** (`VALUES_FILE`), **values overlays**, **Promtail**, etc. |
| **`deploy-production`** | If GitHub reports a missing environment, create **`production`** under **Repo → Settings → Environments**. |

### Local mirror (approximate CI)

```bash
# lint
# TODO helm lint for all services

# render (same as CI render job)
# TODO helm template for service a and b in all environments

# security (install checkov first)
mkdir -p tmp/rendered
# TODO helm template for all environments for service a and b.
checkov -d tmp/rendered --check "CKV_K8S_6,CKV_K8S_8,CKV_K8S_9,CKV_K8S_10,CKV_K8S_11,CKV_K8S_12,CKV_K8S_13,CKV_K8S_36"

for env in localdev sandbox staging production; do
  ./scripts/validate_helm_requirements.sh "${env}"
done
```

Deploy jobs require Docker + kind + kubectl; use CI for full parity, or run `./scripts/deploy.sh <env>` and `./scripts/smoke_test.sh <env>` manually on a local cluster.

---

## Quick checklist

| Task | Quick validation |
| --- | --- |
| 1 | Complete `values/*.yaml` (see `reference.localdev.yaml`); then `./scripts/validate_helm_requirements.sh` ×4 envs + `helm lint` ×3 charts |
| 2 | `make deploy-localdev` → `make smoke-localdev`; see [`runbook.md`](runbook.md) for Grafana/LogQL |
| 3 | `helm template` loop ×4 envs; `make deploy-localdev` + `make deploy-staging` + smokes |
| 4 | Fix Task 4 workflow gaps + prerequisites; push and watch jobs pass; create **`production`** environment if needed |
