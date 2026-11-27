#!/bin/bash
set -e

CLUSTER_NAME="argocd-cluster"
KIND_CONFIG="kind-config.yaml"
API_ADDRESS="172.31.1.127"   # your private IP
API_PORT="33893"

# ---------------------------
# 1. Install tools
# ---------------------------
if ! command -v docker &> /dev/null; then
  sudo apt-get update
  sudo apt-get install -y docker.io
  sudo systemctl enable --now docker
  sudo usermod -aG docker "$USER"
fi

if ! command -v kubectl &> /dev/null; then
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
fi

if ! command -v kind &> /dev/null; then
  [ "$(uname -m)" = "x86_64" ] && ARCH=amd64 || ARCH=arm64
  curl -Lo ./kind "https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-${ARCH}"
  sudo install -o root -m 0755 kind /usr/local/bin/kind
  rm -f kind
fi

if ! command -v helm &> /dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Docker group membership needs a new login shell.
if ! docker info &> /dev/null; then
  echo "❌ Docker isn't reachable yet. Run 'newgrp docker' (or log out and back in), then rerun this script."
  exit 1
fi

# ---------------------------
# 2. Create Kind config (3 nodes: 1 control-plane, 2 workers)
# ---------------------------
cat > "$KIND_CONFIG" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: "${API_ADDRESS}"
  apiServerPort: ${API_PORT}
nodes:
  - role: control-plane
    image: kindest/node:v1.33.1
  - role: worker
    image: kindest/node:v1.33.1
  - role: worker
    image: kindest/node:v1.33.1
EOF

# ---------------------------
# 3. Create cluster
# ---------------------------
echo "📦 Creating Kind cluster: $CLUSTER_NAME ..."
if kind get clusters | grep -qx "$CLUSTER_NAME"; then
  echo "⚠️ Cluster $CLUSTER_NAME already exists. Delete it first if you want to rebuild:"
  echo "   kind delete cluster --name $CLUSTER_NAME"
else
  kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG"
fi

echo "✅ Cluster is ready."
kubectl cluster-info
kubectl get nodes -o wide
