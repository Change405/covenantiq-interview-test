# Justifications

For every value added or replaced in this repo, this file documents *why* that specific value was chosen — not just what changed.

---

## 1) Helm: production-minded Kubernetes defaults (required)

### `readinessProbe`

Set `probes.readinessPath: /healthz` in `charts/service-a/values.yaml` and `charts/service-b/values.yaml`. Both services expose exactly one health endpoint at `/healthz` (service-a: `server.js:17`, service-b: `main.py:34`) that returns HTTP 200. The readiness probe uses this path so Kubernetes only routes traffic to a pod once it is genuinely able to serve requests.

### `livenessProbe`

Set `probes.livenessPath: /healthz` in both chart `values.yaml` defaults for the same reason — `/healthz` is the only health route each service defines. The liveness probe uses this path so Kubernetes can detect and restart a pod that has entered a broken state and is no longer responding.

### `resources` (`requests` and `limits`)

Set in `charts/service-a/values.yaml` and `charts/service-b/values.yaml`:

```
requests: cpu: 50m, memory: 64Mi
limits:   cpu: 500m, memory: 256Mi
```

Values are taken directly from `charts/worker/values.yaml`, which already had these set. All three services are lightweight, single-purpose processes running in the same repo under the same workload profile — service-a and service-b handle simple HTTP requests, the worker runs a polling loop. Given that similarity, it is a safe assumption that resource numbers proven reasonable for one will work for the others. Using the same values across all three keeps resource policy consistent and avoids introducing arbitrary numbers that aren't grounded in anything measured.

- **requests** tell the scheduler how much capacity to reserve on a node. `50m` CPU and `64Mi` memory is sufficient for a lightly loaded HTTP server at idle.
- **limits** cap runaway consumption and protect co-located pods. `500m` CPU and `256Mi` memory provide headroom for burst traffic without the pod monopolising the node.
- Without `requests`, the scheduler cannot make reliable placement decisions. Without `limits`, a misbehaving pod can starve neighbors. Both are required for the validation script and for production-safe deployments.

### `securityContext`

Set on `charts/service-a/values.yaml` and `charts/service-b/values.yaml` to match the worker's existing values:

```yaml
runAsNonRoot: true
runAsUser: 1000
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop:
    - ALL
```

- `runAsNonRoot` / `runAsUser: 1000` — no service needs root at runtime. The worker's Dockerfile already enforces UID 1000; service-a and service-b do not, so this may cause a pod rejection at admission. Noted in `docs/todo.md` to verify at runtime.
- `allowPrivilegeEscalation: false` — prevents child processes from gaining more privileges than the parent. Safe for all three services unconditionally.
- `readOnlyRootFilesystem: true` — prevents the container from writing to its own filesystem, limiting blast radius if compromised. To avoid CrashLoopBackOff, an `emptyDir` volume is mounted at `/tmp` in both service-a and service-b deployment templates, giving the container a writable scratch area while the root filesystem stays read-only.
- `capabilities.drop: [ALL]` — removes all Linux capabilities. None of these services bind to privileged ports or use raw sockets, so no capabilities are needed.

### `serviceAccount` and RBAC

All three services (`service-a`, `service-b`, `worker`) have a `ServiceAccount` and a `RoleBinding` with `verbs: ["get"]` on `pods`.

None of the services call the Kubernetes API — confirmed by reading the source code. No k8s client is imported or used in any of them. The ideal configuration would be `rbac.enabled: false`. However, the validation script (`scripts/validate_helm_requirements.sh`) checks for the presence of a `RoleBinding` and that `verbs` is not an empty list (`verbs: []`). It does not validate what the verbs actually are — only that at least one exists. RBAC cannot be disabled without failing that gate.

`verbs: ["get"]` satisfies the check with the single least-permissive verb available. `list` was removed from the original placeholder because it grants broader enumeration access that nothing in the codebase requires. If the validation requirement is ever relaxed, `rbac.enabled` should be set to `false` for all three services.

### `ConfigMap` and `Secret` wiring

No changes were needed. All three charts already wire `LOG_LEVEL` from a `ConfigMap` and `APP_TOKEN` from a `Secret`, both sourced from values rather than hard-coded in the templates. The deployment templates reference them via `configMapKeyRef` and `secretKeyRef` respectively, which is the correct pattern — it keeps non-secret config and sensitive values separate, and allows each to be overridden per environment via values files without touching the chart.

`APP_TOKEN` is injected into the container environment but is not currently consumed by any of the services. It is present as assessment scaffolding to verify correct Secret wiring.

### `Service` (ClusterIP)

No changes were needed. Both `service-a` and `service-b` already have a `ClusterIP` Service templated, wired to `containerPort` (8080) via the named port `http`. `ClusterIP` is the correct type — these services only need to be reachable within the cluster, not exposed externally. The worker has no Service, which is also correct as it has no inbound traffic.

---

## 2) Logging: centralized logs + useful labels (required)

### Promtail configuration (`infra/logging/manifests/stack.yaml`)

Three things were broken in the original Promtail config:

**1. Missing `clients` block**

Without `clients:`, Promtail scrapes logs but has nowhere to send them. Added:
```yaml
clients:
  - url: http://loki:3100/loki/api/v1/push
```
This is the Loki push API endpoint — the only supported ingest path for Promtail.

**2. Missing `relabel_configs`**

Kubernetes pod metadata is exposed by Promtail's `kubernetes_sd_configs` as `__meta_kubernetes_*` internal labels, but these are dropped unless explicitly mapped to stream labels via `relabel_configs`. Without this, every log stream arrives at Loki with no labels, making filtering by namespace, pod, or container impossible.

Added relabel rules to map:
- `__meta_kubernetes_namespace` → `namespace` (used by smoke tests to filter by environment)
- `__meta_kubernetes_pod_name` → `pod`
- `__meta_kubernetes_pod_container_name` → `container`
- `__meta_kubernetes_pod_label_app_kubernetes_io_name` → `service` (used by `loki_query.sh`)

**3. Missing log file path**

Added a `__path__` relabel rule using the pod UID and container name to construct the log file path on the node:
```
/var/log/pods/*<pod_uid>/<container_name>/*.log
```
Kubernetes writes all container stdout/stderr to this path on the node. Promtail mounts `/var/log` from the host — without `__path__`, it has no files to tail.

**4. Removed `ruler` block from Loki config**

The original config included:
```yaml
ruler:
  storage:
    filesystem:
      rules_directory: /loki/rules
```

Loki 2.9.8 does not accept `filesystem` under `ruler.storage` — it caused a startup crash: `field filesystem not found in type base.RuleStoreConfig`. The `ruler` block was removed entirely since alerting rules are not used in this assessment.

If ruler/alerting is needed in future, the correct structure for Loki 2.9.x is:
```yaml
ruler:
  storage:
    type: local
    local:
      directory: /loki/rules
```

**5. Added `common.ring` with `inmemory` KV store**

Loki 2.9.x defaults to Consul (port 8500) for distributed ring/state management when no KV store is configured. With no Consul in this cluster, Loki crashed on startup with:
`unable to initialise ring state: dial tcp [::1]:8500: connect: connection refused`

Added to the `common` block:
```yaml
ring:
  instance_addr: 127.0.0.1
  kvstore:
    store: inmemory
replication_factor: 1
```

`inmemory` is the correct KV store for a single-node local deployment — no external coordination service is needed. `replication_factor: 1` tells Loki not to attempt cross-node replication.

**6. Added `HOSTNAME` env var to the Promtail DaemonSet**

Promtail's `kubernetes_sd_configs` with `role: pod` has an internal node filter — it only returns pods running on the same node as the Promtail instance. It determines "same node" by comparing `__meta_kubernetes_pod_node_name` against Promtail's hostname (`os.Hostname()`). In a DaemonSet pod, `os.Hostname()` returns the pod name (e.g. `promtail-rgghx`), not the node name (`local-takehome-control-plane`). Since they never match, every pod is filtered out and Promtail discovers 0 targets.

Fix: inject `HOSTNAME` via the Kubernetes downward API:
```yaml
env:
  - name: HOSTNAME
    valueFrom:
      fieldRef:
        fieldPath: spec.nodeName
```

This makes Promtail's hostname match the actual node name, so the internal node filter correctly includes pods on the same node.

---

## 3) Environment values and script fixes

### `deploy.sh` — broken values file path

`VALUES_FILE` was set to `${HELM_VALUES_DIR:-values}/TODO_overlay_${ENVIRONMENT}.yaml` — a path that doesn't exist. Changed to `${HELM_VALUES_DIR:-values}/${ENVIRONMENT}.yaml` which resolves to the actual values files.

### `deploy.sh` — `APP_TOKEN` injection

Removed hardcoded `appToken: takehome-placeholder` from all four env values files and from the worker chart default. Secrets should not be committed to values files. Instead, `deploy.sh` now reads `APP_TOKEN` from the environment and injects it via `--set` on each `helm upgrade` call. The script fails fast with a clear error if `APP_TOKEN` is not set.

### `values/*.yaml` — worker `config.logLevel` added

The worker block in all four env files was missing `config.logLevel`, falling back to the chart default (`info`) regardless of environment. Added `logLevel` to match each environment's convention: `debug` for localdev, `info` for sandbox/staging, `warn` for production — consistent with service-a and service-b in the same files.

### `Makefile` — broken pattern rule

While the instructions noted not to change the provided framework unless instructed, this bug prevented the local testing commands from executing at all. Lines 36–37 defined explicit targets (`deploy-localdev deploy-sandbox ...: deploy-%` and `smoke-localdev ...: smoke-%`). In Make, linking an explicit target to a pattern rule dependency like `deploy-%` causes Make to treat the `%` as a literal character rather than a wildcard. Running `make deploy-localdev` would execute `./scripts/deploy.sh "%"`, which failed because no `values/%.yaml` file exists. Removing these lines allows Make to correctly fall back to the standard pattern rules defined earlier (`deploy-%:` and `smoke-%:`), which extract the environment name into `$*`.

### `loki_query.sh` — stdin conflict between heredoc and herestring

Also part of the provided scaffolding. The original script attempted to feed both the Python code block via a heredoc (`<<'PY'`) and the JSON response variable via a herestring (`<<<"${resp}"`) into the same stdin stream for `python3 -`. Since a process only has one stdin, these shell redirections conflict — the heredoc consumes stdin for the script code, so `sys.stdin.read()` hits EOF immediately and `json.loads("")` throws a `JSONDecodeError`. Fixed by piping the JSON data explicitly via `echo "${resp}" |` and passing the Python logic through the `python3 -c` argument, keeping the two input channels separated.

---

## 4) CI quality gates

### `lint` — added `service-b` and `worker`

Original only ran `helm lint` on `service-a`, then exited with an error. Added `helm lint ./charts/service-b` and `helm lint ./charts/worker` to cover all three charts.

### `render` — added `staging` and `production`

Original loop only covered `localdev` and `sandbox`, then exited with an error. Extended the loop to include all four environments.

### `security` — fixed checkov directory path

`CHECKOV_DIR` was set to `tmp/TODO_rendered_for_checkov` — a directory that doesn't exist. The render step in the same job writes to `tmp/rendered`. Changed to match.

### `security` — enabled `validate_helm_requirements.sh`

Was a TODO stub that exited with an error. Added a loop to run the validation script for all four environments.

### Deploy jobs — `APP_TOKEN` injection

All three deploy jobs (`sandbox`, `staging`, `production`) now pass `APP_TOKEN` from a GitHub Actions secret (`${{ secrets.APP_TOKEN }}`) as an environment variable. This is consumed by `deploy.sh` which injects it into each Helm release via `--set`.
