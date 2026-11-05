# Stage 1: Dify (platform)

Installs Dify 1.16.1 from the community Helm chart 0.38.0 into namespace `dify-lab`, with the
lab's values (`values/dify-lab.yaml`). No AI traffic yet: anything RoonCyber shows at this
stage comes from Dify itself, which makes a useful baseline before the workload is added.

| Object | File |
|---|---|
| Namespace `dify-lab` | `namespace.yaml` |
| HelmRepository `dify` | `helmrepository.yaml` |
| HelmRelease `dify` | `helmrelease.yaml`; values from ConfigMap `dify-values` (generated from `values/dify-lab.yaml`) |

No CRDs, and nothing cluster-scoped except the namespace.

## Flux Kustomization (example)

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: dify-platform
  namespace: flux-system
spec:
  interval: 10m
  path: ./<path-to>/dify-ai-lab/platform
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  timeout: 20m
```

## Secrets: required before the first reconcile

The chart ships fixed, published default credentials (app key, internal service keys, sandbox
key, Postgres and Redis passwords, Weaviate key). The HelmRelease replaces **all of them** with
values from Secret `dify-secrets`, and won't install until that Secret exists.

Create it once, before Flux first deploys Dify:

```bash
./generate-secrets.sh dify-lab      # 8 random values; nothing printed or written to disk
```

Or create it with your own secrets tooling (SOPS, Sealed Secrets, External Secrets) using these
keys: `appSecretKey`, `internalApiKey`, `pluginDaemonServerKey`, `agentBackendServerSecretKey`,
`sandboxApiKey`, `postgresPassword`, `redisPassword`, `weaviateApiKey`.

**Create it once and keep it.** The Postgres and Redis passwords are fixed when those databases
are first created; regenerating the Secret later would lock Dify out of its own data. The
generator refuses to overwrite an existing Secret.

## Done when

- All pods in `dify-lab` are Running (about 12 workloads)
- `kubectl port-forward -n dify-lab svc/dify 8080:80` opens Dify at http://localhost:8080 and
  the admin account has been created

Then continue with stage 2 (`lab/`).

## Optional: internal ingress

To reach Dify at a stable address instead of port-forward, add an internal ingress.
`values/ingress-example.yaml` shows the settings. With Flux, put them in the HelmRelease
(`spec.values`, or another `valuesFrom` entry) for your cluster; with plain Helm, pass the file
with `EXTRA_VALUES` (below). Keep it internal (VPN or private network only).

## Plain Helm (without Flux)

```bash
./install-dify.sh dify-lab
EXTRA_VALUES=my-ingress.yaml ./install-dify.sh dify-lab     # optionally, with your own extra values
```

It creates `dify-secrets` if needed, then runs `helm upgrade --install` for the pinned chart with
`values/dify-lab.yaml` and the credentials from the Secret (passed through a temporary,
owner-only file that is deleted afterwards). Safe to rerun for upgrades.
