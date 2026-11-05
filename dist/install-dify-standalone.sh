#!/bin/sh
# Install Dify securely for the AI workload lab: one file, no repository needed.
#   - pinned community chart dify/dify 0.38.0 (Dify 1.16.1)
#   - lab settings (storage that works without shared volumes, smaller footprint,
#     one ServiceAccount per component, resource limits)
#   - random values for every credential; none of the chart's published defaults remain
#
# Usage:   sh install-dify-standalone.sh [namespace]      (default: dify-lab)
# Needs:   kubectl (pointed at your TEST cluster), helm 3.14+, openssl
# Generated from the dify-ai-lab repository by tools/build-standalone.sh; don't edit by hand.
set -eu
NS="${1:-dify-lab}"
CHART_VERSION="0.38.0"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/values"
cat > "$WORK/values/dify-lab.yaml" <<'LABVALUES'
# Dify values for the AI workload lab.
# Chart: dify/dify 0.38.0 (Dify 1.16.1), from https://borispolonsky.github.io/dify-helm
#
# Install with platform/install-dify.sh (plain Helm) or the Flux HelmRelease in platform/.
# Both replace every default credential in the chart with random values from Secret
# `dify-secrets`, so this file contains no credentials. Don't install with this file alone:
# the chart's built-in passwords and keys are published.
#
# What's changed from the chart defaults, and why:
#   - Storage: api, worker and plugin-daemon volumes use ReadWriteOnce. The chart asks for
#     ReadWriteMany, which most clusters (EKS by default) don't offer, so the pods sit Pending.
#     api and worker share a volume, so api is pinned to worker's node and both use Recreate.
#   - Footprint: postgres and redis run standalone (no read replicas); Weaviate gets 8Gi, not 32Gi.
#   - Identity: one ServiceAccount per Dify component (the chart default is `default` for all).
#   - Access: no ingress. Use `kubectl port-forward -n dify-lab svc/dify 8080:80`.
#   - Resources: explicit requests/limits (the chart sets none).
# The default StorageClass is used. Set storageClass below if your cluster needs another.

api:
  serviceAccount:
    create: true
  replicas: 1
  # A replacement pod can't mount the RWO volume while the old one holds it, and
  # RollingUpdate won't stop the old pod first, so updates would deadlock.
  updateStrategy:
    type: Recreate
  persistence:
    persistentVolumeClaim:
      accessModes: ReadWriteOnce
  # api and worker share pvc/dify (RWO), so they must run on the same node.
  # The chart labels pods `component=worker`, not `app.kubernetes.io/component`.
  affinity:
    podAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
              - key: component
                operator: In
                values: ["worker"]
          topologyKey: kubernetes.io/hostname
  resources:
    requests: {cpu: "250m", memory: "1Gi"}
    limits:   {cpu: "1",    memory: "2Gi"}

worker:
  serviceAccount:
    create: true
  replicas: 1
  updateStrategy:
    type: Recreate
  persistence:
    persistentVolumeClaim:
      accessModes: ReadWriteOnce
  resources:
    requests: {cpu: "250m", memory: "1Gi"}
    limits:   {cpu: "1",    memory: "2Gi"}

beat:
  serviceAccount:
    create: true
  resources:
    requests: {cpu: "50m",  memory: "256Mi"}
    limits:   {cpu: "200m", memory: "512Mi"}

web:
  serviceAccount:
    create: true
  replicas: 1
  resources:
    requests: {cpu: "100m", memory: "256Mi"}
    limits:   {cpu: "500m", memory: "1Gi"}

proxy:
  serviceAccount:
    create: true
  resources:
    requests: {cpu: "50m",  memory: "128Mi"}
    limits:   {cpu: "200m", memory: "256Mi"}

sandbox:
  serviceAccount:
    create: true
  resources:
    requests: {cpu: "100m", memory: "256Mi"}
    limits:   {cpu: "500m", memory: "1Gi"}

pluginDaemon:
  serviceAccount:
    create: true
  updateStrategy:
    type: Recreate
  persistence:
    persistentVolumeClaim:
      accessModes: ReadWriteOnce
  resources:
    requests: {cpu: "100m", memory: "512Mi"}
    limits:   {cpu: "500m", memory: "1Gi"}

agentBackend:
  serviceAccount:
    create: true

localSandbox:
  serviceAccount:
    create: true

postgresql:
  enabled: true
  architecture: standalone
  primary:
    persistence:
      enabled: true
      size: 8Gi
    resources:
      requests: {cpu: "250m", memory: "512Mi"}
      limits:   {cpu: "1",    memory: "2Gi"}

redis:
  enabled: true
  architecture: standalone
  master:
    persistence:
      enabled: true
      size: 4Gi
    resources:
      requests: {cpu: "100m", memory: "256Mi"}
      limits:   {cpu: "500m", memory: "1Gi"}

weaviate:
  enabled: true
  storage:
    size: 8Gi
  resources:
    requests: {cpu: "250m", memory: "512Mi"}
    limits:   {cpu: "1",    memory: "2Gi"}
LABVALUES
cat > "$WORK/generate-secrets.sh" <<'GENSECRETS'
#!/bin/sh
# Create Secret `dify-secrets` with random values for every credential the Dify chart would
# otherwise take from its public defaults. Run ONCE, before Dify's first install: the database
# and Redis passwords are fixed when those are first created, so they can't be changed later
# through Helm. Nothing is printed or written to disk.
#
#   ./generate-secrets.sh [namespace]        (default namespace: dify-lab)
set -eu
NS="${1:-dify-lab}"

if kubectl get secret dify-secrets -n "$NS" >/dev/null 2>&1; then
  echo "Secret dify-secrets already exists in $NS; leaving it unchanged."
  echo "(Regenerating it would lock Dify out of its own database.)"
  exit 0
fi
kubectl get namespace "$NS" >/dev/null 2>&1 || kubectl create namespace "$NS"

alnum() { openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | cut -c1-"$1"; }

kubectl create secret generic dify-secrets -n "$NS" \
  --from-literal=appSecretKey="sk-$(alnum 48)" \
  --from-literal=internalApiKey="$(alnum 48)" \
  --from-literal=pluginDaemonServerKey="$(alnum 48)" \
  --from-literal=agentBackendServerSecretKey="$(openssl rand -hex 16 | tr -d '\n' | base64 | tr -d '=\n')" \
  --from-literal=sandboxApiKey="$(alnum 32)" \
  --from-literal=postgresPassword="$(alnum 32)" \
  --from-literal=redisPassword="$(alnum 32)" \
  --from-literal=weaviateApiKey="$(alnum 36)" >/dev/null
# Lets Flux re-apply the HelmRelease as soon as this Secret changes (Flux 2.3+); harmless otherwise.
kubectl label secret dify-secrets -n "$NS" reconcile.fluxcd.io/watch=Enabled >/dev/null
echo "Created Secret dify-secrets in $NS (8 random values; not displayed)."
GENSECRETS
cat > "$WORK/install-dify.sh" <<'INSTALL'
#!/bin/sh
# Install or upgrade Dify securely with plain Helm (no Flux).
#   - creates Secret dify-secrets with random credentials if it doesn't exist yet
#   - installs the pinned community chart with the lab values, taking every credential from
#     that Secret (via a temporary, owner-only file that is deleted afterwards)
#
#   ./install-dify.sh [namespace]            (default namespace: dify-lab)
#
# Cluster-specific settings (for example an ingress) go in your own values file(s), passed
# with EXTRA_VALUES (space-separated paths), applied after the lab values:
#   EXTRA_VALUES=values/ingress-example.yaml ./install-dify.sh dify-lab
set -eu
NS="${1:-dify-lab}"
CHART_VERSION="0.38.0"
HERE="$(cd "$(dirname "$0")" && pwd)"

"$HERE/generate-secrets.sh" "$NS"

get() { kubectl get secret dify-secrets -n "$NS" -o "jsonpath={.data.$1}" | base64 -d; }

umask 077
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<VALUES
global:
  appSecretKey: "$(get appSecretKey)"
api:
  auth:
    internalApiKey: "$(get internalApiKey)"
pluginDaemon:
  auth:
    serverKey: "$(get pluginDaemonServerKey)"
agentBackend:
  auth:
    serverSecretKey: "$(get agentBackendServerSecretKey)"
sandbox:
  auth:
    apiKey: "$(get sandboxApiKey)"
postgresql:
  global:
    postgresql:
      auth:
        postgresPassword: "$(get postgresPassword)"
redis:
  auth:
    password: "$(get redisPassword)"
weaviate:
  authentication:
    apikey:
      allowed_keys:
        - "$(get weaviateApiKey)"
  # Weaviate's env var takes priority over the config above, so set both to the same key.
  env:
    AUTHENTICATION_APIKEY_ALLOWED_KEYS: "$(get weaviateApiKey)"
VALUES

helm repo add dify https://borispolonsky.github.io/dify-helm >/dev/null 2>&1 || true
helm repo update dify >/dev/null
EXTRA=""
for f in ${EXTRA_VALUES:-}; do EXTRA="$EXTRA -f $f"; done
# shellcheck disable=SC2086
helm upgrade --install dify dify/dify --version "$CHART_VERSION" -n "$NS" \
  -f "$HERE/values/dify-lab.yaml" $EXTRA -f "$TMP" --timeout 15m
echo
echo "Dify is installing in $NS. Watch:   kubectl get pods -n $NS -w"
echo "Then open it:                       kubectl port-forward -n $NS svc/dify 8080:80"
INSTALL
chmod +x "$WORK/generate-secrets.sh" "$WORK/install-dify.sh"
echo "Installing Dify into namespace $NS on context: $(kubectl config current-context)"
"$WORK/install-dify.sh" "$NS"
