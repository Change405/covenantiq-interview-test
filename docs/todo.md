# TODO

## Runtime checks

- [ ] **Verify `runAsNonRoot` for service-a and service-b**
  After deploying to the kind cluster, confirm both pods start successfully.
  The Dockerfiles for service-a and service-b do not explicitly create a non-root user — if either image defaults to UID 0, Kubernetes will reject the pod at admission.
  If pods fail to start, the fix is to update their Dockerfiles to match the worker (create UID 1000, `chown /app`, switch with `USER 1000`).
  Check with:
  ```bash
  kubectl get pods -n localdev
  kubectl describe pod <pod-name> -n localdev
  ```

- [ ] **HPA — revisit if metrics-server or Prometheus is added**
  No HPA is defined for any service. service-a and service-b expose no `/metrics` endpoint, and no metrics-server or Prometheus adapter is deployed in the cluster. The worker must not be scaled horizontally — it reads from a shared `hostPath` volume and multiple replicas would race on the same files. If metrics infrastructure is added in future, HPA could be introduced for service-a and service-b on CPU/memory.

- [ ] **Verify `readOnlyRootFilesystem` for service-a and service-b**
  Both services may write to the filesystem at startup — Node.js (service-a) can touch `/tmp`, Python (service-b) writes `__pycache__` to `/app`. If either crashes on startup, mount an `emptyDir` volume at the offending path (e.g. `/tmp`, `/app/__pycache__`) rather than disabling the setting.
  Check with:
  ```bash
  kubectl logs <pod-name> -n localdev
  ```
