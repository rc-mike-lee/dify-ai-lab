#!/bin/sh
# Install or upgrade Dify securely with plain Helm (no Flux).
#   - creates Secret dify-secrets with random credentials if it doesn't exist yet
#   - installs the pinned community chart with the lab values, taking every credential from
#     that Secret (via a temporary, owner-only file that is deleted afterwards)
#
#   ./install-dify.sh [namespace]            (default namespace: dify-lab)
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
helm upgrade --install dify dify/dify --version "$CHART_VERSION" -n "$NS" \
  -f "$HERE/values/dify-lab.yaml" -f "$TMP" --timeout 15m
echo
echo "Dify is installing in $NS. Watch:   kubectl get pods -n $NS -w"
echo "Then open it:                       kubectl port-forward -n $NS svc/dify 8080:80"
