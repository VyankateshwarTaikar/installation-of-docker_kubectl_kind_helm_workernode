#!/bin/bash
set -euo pipefail
exec > >(tee -a /var/log/kind-setup.log) 2>&1

CLUSTER_NAME="argocd-cluster"
KIND_VERSION="v0.30.0"
KUBECTL_VERSION="v1.33.1"            # matches the node image
NODE_IMAGE="kindest/node:v1.33.1"
API_PORT="40000"                     # must match api_port in variables.tf
TARGET_USER="ubuntu"
TARGET_HOME="/home/${TARGET_USER}"
export DEBIAN_FRONTEND=noninteractive

ARCH=$(dpkg --print-architecture)    # amd64 or arm64

# ---------------------------
# 0. Detect this instance's private IP (IMDSv2)
# ---------------------------
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
API_ADDRESS=$(curl -s -H "X-aws-ec2-metadata-token: ${TOKEN}" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

if [ -z "$API_ADDRESS" ]; then
  echo "❌ Could not read private IP from metadata service"
  exit 1
fi
echo "Private IP: $API_ADDRESS"

# ---------------------------
# 1. Install tools
# ---------------------------
if ! command -v docker &> /dev/null; then
  apt-get update -y
  apt-get install -y docker.io curl ca-certificates
  systemctl enable --now docker
fi
usermod -aG docker "$TARGET_USER"

# Wait until the Docker daemon is responding
for i in $(seq 1 30); do
  docker info &> /dev/null && break
  sleep 2
done
docker info &> /dev/null || { echo "❌ Docker daemon not reachable"; exit 1; }

if ! command -v kubectl &> /dev/null; then
  curl -fsSLo /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"
  chmod 0755 /usr/local/bin/kubectl
fi

if ! command -v kind &> /dev/null; then
  curl -fsSLo /usr/local/bin/kind \
    "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${ARCH}"
  chmod 0755 /usr/local/bin/kind
fi

if ! command -v helm &> /dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# ---------------------------
# 2. Create Kind config (1 control-plane, 2 workers)
# ---------------------------
KIND_CONFIG="/root/kind-config.yaml"
cat > "$KIND_CONFIG" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: "${API_ADDRESS}"
  apiServerPort: ${API_PORT}
nodes:
  - role: control-plane
    image: ${NODE_IMAGE}
  - role: worker
    image: ${NODE_IMAGE}
  - role: worker
    image: ${NODE_IMAGE}
EOF

# ---------------------------
# 3. Create cluster
# ---------------------------
EXISTING_CLUSTERS=$(kind get clusters)
if grep -qx "$CLUSTER_NAME" <<< "$EXISTING_CLUSTERS"; then
  echo "⚠️ Cluster $CLUSTER_NAME already exists, skipping creation."
else
  echo "📦 Creating Kind cluster: $CLUSTER_NAME ..."
  kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG"
fi

# ---------------------------
# 4. Give the ubuntu user kubectl access
# ---------------------------
mkdir -p "${TARGET_HOME}/.kube"
kind get kubeconfig --name "$CLUSTER_NAME" > "${TARGET_HOME}/.kube/config"
chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.kube"
chmod 600 "${TARGET_HOME}/.kube/config"

export KUBECONFIG="${TARGET_HOME}/.kube/config"
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo "✅ Cluster is ready."
kubectl cluster-info
kubectl get nodes -o wide
