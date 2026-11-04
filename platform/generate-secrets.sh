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
