#!/bin/bash

set -e

CLUSTER_NAME="${1:-talos-local}"
WORKERS="${2:-2}"
CONTROL_PLANES="${3:-1}"

echo "========================================"
echo "Creating Talos cluster: ${CLUSTER_NAME}"
echo "Control planes: ${CONTROL_PLANES}"
echo "Workers: ${WORKERS}"
echo "========================================"
echo ""

# Check if talosctl is installed
if ! command -v talosctl &> /dev/null; then
    echo "Error: talosctl is not installed"
    echo "Please install from: https://github.com/siderolabs/talos/releases"
    exit 1
fi

# Check if cilium CLI is installed
if ! command -v cilium &> /dev/null; then
    echo "Warning: cilium CLI is not installed"
    echo "Cilium will be installed but you won't be able to use 'cilium status'"
    echo "Install from: https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli"
    echo ""
fi

# Create the cluster
echo "Creating cluster..."
talosctl cluster create \
  --name "${CLUSTER_NAME}" \
  --workers "${WORKERS}" \
  --controlplanes "${CONTROL_PLANES}" \
  --config-patch @cilium-patch.yaml \
  --wait

echo ""
echo "Cluster created successfully!"
echo ""

# Wait a bit for the API server to be fully ready
echo "Waiting for Kubernetes API server..."
sleep 5

# Try to wait for nodes (they won't be ready until CNI is installed)
echo "Checking node status (nodes will be NotReady until Cilium is installed)..."
kubectl get nodes || true
echo ""

# Install Cilium
echo "Installing Cilium CNI..."
if command -v cilium &> /dev/null; then
    cilium install \
      --set ipam.mode=kubernetes \
      --set kubeProxyReplacement=true

    echo ""
    echo "Waiting for Cilium to be ready..."
    cilium status --wait
else
    # Fallback to kubectl if cilium CLI is not available
    echo "Installing Cilium via kubectl (cilium CLI not found)..."
    kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v1.18.0/install/kubernetes/quick-install.yaml
    echo "Waiting for Cilium pods to be ready..."
    kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=300s
fi

echo ""
echo "Waiting for all nodes to be ready..."
kubectl wait --for=condition=ready node --all --timeout=300s

echo ""
echo "========================================"
echo "Cluster is ready!"
echo "========================================"
echo ""
kubectl get nodes
echo ""
echo "To interact with your cluster:"
echo "  kubectl get pods -A"
echo "  kubectl cluster-info"
echo ""
echo "To destroy the cluster:"
echo "  talosctl cluster destroy --name ${CLUSTER_NAME}"
echo ""
