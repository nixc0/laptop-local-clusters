#!/bin/bash

set -e

# Detect and configure container runtime (Docker or Podman)
detect_container_runtime() {
    # Check if Podman is running
    if command -v podman &> /dev/null && podman machine list 2>/dev/null | grep -q "Currently running"; then
        # Get Podman socket path dynamically
        PODMAN_SOCK=$(find /var/folders -name "podman-machine-default-api.sock" 2>/dev/null | head -1)
        if [ -n "$PODMAN_SOCK" ]; then
            echo "Using Podman Desktop (socket: $PODMAN_SOCK)"
            export DOCKER_HOST="unix://$PODMAN_SOCK"
            return 0
        fi
    fi

    # Check if Docker is running
    if docker info &> /dev/null; then
        echo "Using Docker Desktop"
        return 0
    fi

    echo "Error: Neither Docker nor Podman is running"
    echo "Please start Docker Desktop or Podman Desktop"
    exit 1
}

# Configure container runtime
detect_container_runtime

# Parse arguments
SKIP_CILIUM=false
HOMELAB_CONTEXT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-cilium)
            SKIP_CILIUM=true
            shift
            ;;
        --register-with-homelab)
            HOMELAB_CONTEXT="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

CLUSTER_NAME="${1:-talos-local}"
WORKERS="${2:-2}"
CONTROL_PLANES="${3:-1}"

echo "========================================"
echo "Creating Talos cluster: ${CLUSTER_NAME}"
echo "Control planes: ${CONTROL_PLANES}"
echo "Workers: ${WORKERS}"
if [ "$SKIP_CILIUM" = true ]; then
    echo "Mode: ArgoCD-managed (Cilium will be installed by ArgoCD)"
else
    echo "Mode: Standalone (Cilium installed locally)"
fi
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
  --endpoint 127.0.0.1 \
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

if [ "$SKIP_CILIUM" = false ]; then
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
else
    echo "Skipping Cilium installation (will be managed by ArgoCD)"
    echo ""
fi

echo ""
echo "========================================"
echo "Cluster is ready!"
echo "========================================"
echo ""
kubectl get nodes || true
echo ""

if [ "$SKIP_CILIUM" = false ]; then
    echo "To interact with your cluster:"
    echo "  kubectl get pods -A"
    echo "  kubectl cluster-info"
    echo ""
else
    echo "Next steps:"
    echo "1. Register cluster with homelab ArgoCD:"
    if [ -n "$HOMELAB_CONTEXT" ]; then
        echo "   ./scripts/register-cluster.sh ${CLUSTER_NAME} ${HOMELAB_CONTEXT}"
    else
        echo "   ./scripts/register-cluster.sh ${CLUSTER_NAME} <homelab-context>"
    fi
    echo ""
    echo "2. Wait for ArgoCD to deploy core applications (Cilium, monitoring, etc.)"
    echo "   ArgoCD will automatically sync all core apps to this cluster"
    echo ""
    echo "3. Monitor sync status in ArgoCD UI"
    echo ""
fi

echo "To destroy the cluster:"
echo "  talosctl cluster destroy --name ${CLUSTER_NAME}"
echo ""

# Auto-register if homelab context was provided
if [ -n "$HOMELAB_CONTEXT" ] && [ "$SKIP_CILIUM" = true ]; then
    echo "Auto-registering cluster with homelab ArgoCD..."
    ./scripts/register-cluster.sh "${CLUSTER_NAME}" "${HOMELAB_CONTEXT}"
fi
