#!/bin/sh
# Build dist/install-dify-standalone.sh: one self-contained file that installs Dify securely
# (values + secret generation + Helm install), for customers who only want step 1.
# Rerun after changing platform/values/dify-lab.yaml or the platform scripts.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist/install-dify-standalone.sh"
{
cat <<'HEAD'
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
HEAD
cat "$ROOT/platform/values/dify-lab.yaml"
echo "LABVALUES"
echo 'cat > "$WORK/generate-secrets.sh" <<'"'"'GENSECRETS'"'"
cat "$ROOT/platform/generate-secrets.sh"
echo "GENSECRETS"
echo 'cat > "$WORK/install-dify.sh" <<'"'"'INSTALL'"'"
cat "$ROOT/platform/install-dify.sh"
echo "INSTALL"
cat <<'TAIL'
chmod +x "$WORK/generate-secrets.sh" "$WORK/install-dify.sh"
echo "Installing Dify into namespace $NS on context: $(kubectl config current-context)"
"$WORK/install-dify.sh" "$NS"
TAIL
} > "$OUT"
chmod +x "$OUT"
echo "Wrote $OUT ($(wc -l < "$OUT") lines)"
