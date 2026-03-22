# DevOps Take-home: Kubernetes, SDLC Environments, and Observability

## Overview

This take-home is designed to evaluate your Kubernetes and DevOps fundamentals using a realistic SDLC workflow and centralized logging.

You will:

- Deploy and iterate on workloads in a local Kubernetes cluster (`kind`)
- Implement production-minded Kubernetes settings (health checks, security, resources, RBAC)
- Set up centralized logging using **Grafana + Loki + Promtail** running in the same cluster
- Add CI quality gates that progress from static checks to “deploy + smoke test” in increasing environments

## Timebox

Best effort: **Finish as many of the tasks as possible and explain solution for the rest**.

## Pre-requisites

You need these tools installed locally:

- `docker`
- `kubectl`
- `helm` (v3)
- `kind`
- `curl`
- `python3`

## Mac Setup

If you use Homebrew on macOS:

```bash
brew install kubectl helm kind
```

Install Docker Desktop (if not already installed): [https://www.docker.com/products/docker-desktop/](https://www.docker.com/products/docker-desktop/)

Verify installs:

```bash
docker --version
kubectl version --client
helm version
kind version
python3 --version
curl --version
```

## How this repo is structured

- `services/`: sample backend services (already implemented; you do not need to change them)
- `frontend/`: a small React app (provided; optional to deploy/ignore for the core Kubernetes/observability evaluation)
- `charts/`: Helm charts (you will update these to meet the requirements)
- `infra/`:
  - `kind/`: local `kind` cluster config
  - `logging/`: Grafana/Loki/Promtail deployment + configuration hooks
- `.github/workflows/`: CI skeleton with progressive quality gates
- `scripts/`: helper scripts for deploy + smoke tests (used by CI)

## Your tasks (bounded scope)

### 1) Helm: production-minded Kubernetes defaults (required)

Update the Helm charts under `charts/` for **at least 2 backend services** (you may do all).
You must ensure each service’s `Deployment` includes:

- `readinessProbe` and `livenessProbe`
- `resources` (`requests` and `limits`)
- `securityContext` hardening (runAsNonRoot, drop capabilities, readOnlyRootFilesystem where applicable)
- A `serviceAccount` and minimal RBAC (if not needed by the service, document why; otherwise include an actual least-privilege RBAC binding)
- Wiring via `ConfigMap`/`Secret` values (no hard-coded secrets)

Also ensure the service has:

- An internal `Service` (ClusterIP)

Optional (bonus):

- `HorizontalPodAutoscaler` if your service exposes a metric (otherwise explain why HPA isn’t included).

### 2) Logging: centralized logs + useful labels (required)

Grafana/Loki/Promtail run inside the same Kubernetes cluster.

Update the Promtail configuration (under `infra/logging/` or via Helm values) so that:

- Logs include at least these labels:
  - `namespace` (must match the Helm environment namespace)
  - `pod`
  - `container`
- In Grafana, you can run a query that filters logs by:
  - environment via `namespace`
  - service/pod via pod/container labels

Deliverable evidence:

- A screenshot (or copy/paste) of the Grafana query results demonstrating filtering by `namespace`.

### 3) SDLC environment modeling (required)

Model four environments using Helm values:

- `localdev` (developer laptop / local `kind` namespace)
- `sandbox`
- `staging`
- `production`

Acceptance criterion:

- The same charts deploy to all four environments by swapping values (no templating forks per env).

Deliverable evidence:

- Proof you can deploy to at least `localdev` + `staging` (screenshots or CI logs are fine).

### 4) CI quality gates: increasing confidence (required)

Implement progressive CI gates in `.github/workflows/` so that the pipeline:

- Fails fast on lint/render issues
- Progresses to deploy + smoke tests in increasing environments
- Includes a “security” gate using lightweight static analysis

At a minimum, your pipeline must include these stages (names can vary):

1. `lint`: format checks + `helm lint` + YAML sanity checks
2. `render`: `helm template` for all environments
3. `security`: run a small manifest security scanner against rendered YAML
4. `deploy-sandbox`: deploy to a fresh ephemeral `kind` cluster + smoke tests
5. `deploy-staging`: deploy to a fresh ephemeral `kind` cluster + smoke tests + verify logs in Loki
6. `deploy-production`: deployment step gated behind prior success (manual approval is acceptable)

Smoke tests must be deterministic:

- Call each backend’s `/healthz`
- Verify that the corresponding logs were ingested into Loki (query by labels)

## What is provided (do not change unless instructed)

- Sample backend services with:
  - `GET /healthz` and deterministic log lines on each call
  - Dockerfiles to build images locally
- Provided workloads:
  - `service-a` and `service-b` (backend HTTP services)
  - `worker` (queue consumer + scheduled enqueue simulation)
- A working deployment framework:
  - Helm chart scaffolding
  - `kind` helper scripts
  - A logging stack installer
  - CI workflow skeleton
- A [validation.md](http://validation.md) guide on how to validate each task.
- A `runbook.md` to help you verify logging and troubleshoot common issues

## Local verification (recommended)

**Per-task validation commands and script mapping (Tasks 1–4):** see `**[Validation.md](Validation.md)`**. For Grafana/Loki queries and troubleshooting, see `**[runbook.md](runbook.md)**`.

Prerequisites:

- `docker`
- `kubectl`
- `helm` (v3)
- `kind`

Suggested workflow:

1. Spin up local cluster:
  - `make kind-up`
2. Build images:
  - `make build-images`
3. Deploy to `localdev`:
  - `make deploy-localdev`
4. Verify observability:
  - Port-forward Grafana and run the required Loki query (see `runbook.md`)
5. Run smoke tests:
  - `make smoke-localdev`

For additional environments:

- `make deploy-staging` and `make smoke-staging`

## Deliverables (what you should submit)

1. Your Git diff (or zip) containing:
  - Updated Helm charts under `charts/`
  - Updated Promtail/Loki/Grafana configuration under `infra/logging/`
  - Completed CI workflow with quality gates
2. Evidence folder (any format):
  - `docs/evidence/grafana-namespace-filter.`* (screenshot/text export)
  - `docs/evidence/smoke-test-output.`* (logs of smoke tests)

## Acceptance criteria summary

You pass if:

- At least 2 backend Helm charts include required probes/resources/security/RBAC
- Promtail emits logs with correct labels and Grafana query can filter by `namespace`
- The provided `worker` workload’s queue consumption logs are ingested into Loki (CI smoke test).
- You can deploy the stack into `localdev` and `staging` by swapping Helm values
- CI runs lint/render/security/deploy gates and smoke tests succeed

