# Runbook: Kubernetes Logging Verification (Grafana + Loki + Promtail)

## What “good” looks like
After deploying a backend service into an environment namespace (e.g., `sandbox`), you should be able to:
1. Hit `GET /healthz` successfully
2. See a `healthz_ok` log line appear in Loki
3. Query Loki in Grafana using at least `namespace` (environment) and `service`

## Prerequisites
- `kind`
- `kubectl`
- `docker`
- `helm`
- `curl` (used by `scripts/loki_query.sh` to call Loki’s HTTP API)
- `python3` (used by `scripts/loki_query.sh` to parse query results)

## Local workflow (recommended)
1. Create a local Kubernetes cluster:
   - `make kind-up`
2. Build and load the container images into `kind`:
   - `make build-images`
   - `make load-images`
3. Deploy the stack to `localdev`:
   - `make deploy-localdev`
4. Verify smoke tests:
   - `make smoke-localdev`

## Grafana access
1. Port-forward Grafana:
   - `kubectl -n logging port-forward svc/grafana 3000:80`
2. Open Grafana:
   - http://localhost:3000

Loki should already be configured as the default datasource.

## Expected Loki (LogQL) queries
Use these queries in **Grafana Explore** (or the LogQL query box).

### Query by environment (namespace) + service
```txt
{namespace="localdev", service="service-a"} |= "healthz_ok"
```

Same pattern for `service-b`:
```txt
{namespace="localdev", service="service-b"} |= "healthz_ok"
```

### Query by environment only (sanity check)
```txt
{namespace="localdev"} |= "healthz_ok"
```

### Worker: queue processing verification
The worker emits structured JSON logs when it consumes messages from the queue directory.

```txt
{namespace="localdev", service="worker"} |= "queue_processed"
```

## Programmatic verification (CLI)
After deploying an environment:

```bash
./scripts/loki_query.sh localdev logging service-a
./scripts/loki_query.sh localdev logging service-b
./scripts/loki_query.sh localdev logging worker queue_processed
```

These commands fail if no matching `healthz_ok` logs are found.

## Troubleshooting

### Loki or Grafana pods are not ready
Run:
- `kubectl -n logging get pods`
- `kubectl -n logging logs deployment/loki --tail=200`
- `kubectl -n logging logs deployment/grafana --tail=200`

If Loki doesn’t come up, verify the `loki-config` ConfigMap exists:
- `kubectl -n logging get configmap loki-config -o yaml`

### Promtail is not ingesting logs
Run:
- `kubectl -n logging get ds/promtail`
- `kubectl -n logging logs ds/promtail --tail=200`

If Promtail has errors, check the Promtail config:
- `kubectl -n logging get configmap promtail-config -o yaml`

### Loki query returns “0 results”
Common causes:
- Logs were not emitted: confirm health calls succeeded.
- Label mismatch:
  - In this repo, Promtail is expected to set `namespace`, `pod`, `container`, and `service` labels.
  - If your service label doesn’t show up, try querying by `namespace` only:
    - `{namespace="localdev"} |= "healthz_ok"`
- Ingestion latency: rerun the query after a few seconds.

### Smoke test fails
If `scripts/smoke_test.sh` fails, re-run with a fresh deploy:
- `make deploy-localdev`
- `make smoke-localdev`

Then check:
- `kubectl -n localdev get pods`
- `kubectl -n localdev logs <pod-name> --tail=50`

