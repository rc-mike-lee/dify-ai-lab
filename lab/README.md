# Stage 2: the AI workload (lab)

Adds the Customer Support Copilot's supporting services to `dify-lab`. Deploy after stage 1
(`platform/`) is running and the Dify admin account exists.

| Object | File |
|---|---|
| `lab-customer-db`, `lab-mcp-crm`, `lab-ollama`, `lab-litellm` (Deployments, Services, ServiceAccounts, ConfigMaps) | `manifests/lab-supporting.yaml` |
| Gateway routing ConfigMap `lab-litellm-config` | generated from `providers/anthropic.yaml` (swap for another provider file) |
| Traffic driver CronJob | `manifests/lab-driver.yaml`, **shipped suspended** |

## Flux Kustomization (example)

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: dify-lab-workload
  namespace: flux-system
spec:
  dependsOn:
    - name: dify-platform
  interval: 10m
  path: ./<path-to>/dify-ai-lab/lab
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  timeout: 10m
```

## Secrets (not in Git)

| Secret | Keys | Needed before |
|---|---|---|
| `lab-provider-keys` | the provider's variables, e.g. `ANTHROPIC_API_KEY` (see the provider file's header) | `lab-litellm` starts |
| `lab-driver-key` | `key`: the Copilot's Dify API key | the driver is un-suspended |

```bash
kubectl create secret generic lab-provider-keys -n dify-lab --from-literal=ANTHROPIC_API_KEY="$(pbpaste)"
# later, after the Copilot is built in Dify:
kubectl create secret generic lab-driver-key -n dify-lab --from-literal=key="$(pbpaste)"
```

Flux doesn't manage or prune Secrets it didn't create.

## After Flux deploys

1. Configure the Copilot in Dify's UI (`docs/04-dify-configuration.md`). This lives in Dify's
   database, not in Git.
2. Create `lab-driver-key`, then remove the suspend patch from `kustomization.yaml`.

## Things that change under GitOps

- Switching provider = change the `configMapGenerator` file in `kustomization.yaml`; the
  gateway restarts automatically (the generated name changes).
- Ad-hoc `kubectl` edits to managed objects (e.g. `kubectl set env` on `lab-ollama`) are
  reverted by Flux; make them in Git.
