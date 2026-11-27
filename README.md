# installation-of-docker_kubectl_kind_helm_workernode_WithArgoCD
Installing Docker, kubectl, and Helm sets up a complete local workflow for building, managing, and deploying containerized applications.


#!/bin/bash
set -e

CLUSTER_NAME="argocd-cluster"
KIND_CONFIG="kind-config.yaml"
NAMESPACE="argocd"
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

# Docker group membership needs a new login shell. If docker fails with a
# permission error below, run "newgrp docker" and rerun this script.
if ! docker info &> /dev/null; then
  echo "❌ Docker isn't reachable yet. Run 'newgrp docker' (or log out and back in), then rerun this script."
  exit 1
fi

# ---------------------------
# 2. Create Kind config (3 nodes)
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
  echo "⚠️ Cluster $CLUSTER_NAME already exists. Delete it first if the node count or API address is wrong:"
  echo "   kind delete cluster --name $CLUSTER_NAME"
else
  kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG"
fi

kubectl cluster-info
kubectl get nodes -o wide

# ---------------------------
# 4. Install Argo CD
# ---------------------------
echo "========================================="
echo "   🚀 ArgoCD Setup on Kind Cluster"
echo "========================================="
echo "1) Helm   2) Manifests"
read -p "Enter choice [1 or 2]: " choice

kubectl create namespace "$NAMESPACE" 2>/dev/null || echo "⚠️ Namespace $NAMESPACE already exists."

if [ "$choice" == "1" ]; then
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update
  helm upgrade --install argocd argo/argo-cd -n "$NAMESPACE"
elif [ "$choice" == "2" ]; then
  kubectl apply -n "$NAMESPACE" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
else
  echo "❌ Invalid choice. Run the script again and choose 1 or 2."
  exit 1
fi

# ---------------------------
# 5. Install Argo CD CLI
# ---------------------------
if ! command -v argocd &> /dev/null; then
  curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
  sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
  rm -f argocd-linux-amd64
fi

# ---------------------------
# 6. Verify
# ---------------------------
kubectl wait --for=condition=Available deployment/argocd-server -n "$NAMESPACE" --timeout=300s || true
kubectl get pods -n "$NAMESPACE"
kubectl get svc -n "$NAMESPACE"

PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n "$NAMESPACE" -o jsonpath="{.data.password}" | base64 -d)
echo ""
echo "🔑 Admin password: $PASSWORD"
echo "🌐 Run: kubectl port-forward svc/argocd-server -n $NAMESPACE 8080:443 --address=0.0.0.0 &"
echo "   Then open: https://<instance_public_ip>:8080 (user: admin)"
