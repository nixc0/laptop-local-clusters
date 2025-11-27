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

CLUSTER_NAME="${1:-k3d-local}"
WORKERS="${2:-2}"
CONTROL_PLANES="${3:-1}"

echo "========================================"
echo "Creating k3d cluster: ${CLUSTER_NAME}"
echo "Control planes: ${CONTROL_PLANES}"
echo "Workers: ${WORKERS}"
if [ "$SKIP_CILIUM" = true ]; then
    echo "CNI: Cilium (managed by ArgoCD)"
else
    echo "CNI: Flannel (k3s default)"
fi
echo "========================================"
echo ""

# Check if k3d is installed
if ! command -v k3d &> /dev/null; then
    echo "Error: k3d is not installed"
    echo "Install with: brew install k3d"
    exit 1
fi

# Build k3d create command
K3D_ARGS=(
    "cluster" "create" "${CLUSTER_NAME}"
    "--servers" "${CONTROL_PLANES}"
    "--agents" "${WORKERS}"
    "--wait"
)

# If ArgoCD-managed, disable default CNI (Flannel) so ArgoCD can install Cilium
if [ "$SKIP_CILIUM" = true ]; then
    K3D_ARGS+=(
        "--k3s-arg" "--flannel-backend=none@server:*"
        "--k3s-arg" "--disable-network-policy@server:*"
    )
    echo "Disabling Flannel CNI for Cilium installation via ArgoCD..."
else
    echo "Using k3s default Flannel CNI..."
fi

# Create the cluster
echo ""
echo "Creating cluster..."
k3d "${K3D_ARGS[@]}"

echo ""
echo "Cluster created successfully!"
echo ""

# Wait for API server and nodes
echo "Waiting for Kubernetes to be ready..."
kubectl wait --for=condition=ready node --all --timeout=120s --context "k3d-${CLUSTER_NAME}" 2>/dev/null || true

if [ "$SKIP_CILIUM" = true ]; then
    echo ""
    echo "Note: Nodes will remain NotReady until Cilium is installed by ArgoCD"
fi

echo ""
echo "========================================"
echo "Cluster is ready!"
echo "========================================"
echo ""
kubectl get nodes --context "k3d-${CLUSTER_NAME}" || true
echo ""

echo "To interact with your cluster:"
echo "  kubectl --context k3d-${CLUSTER_NAME} get pods -A"
echo "  kubectl --context k3d-${CLUSTER_NAME} cluster-info"
echo ""

if [ "$SKIP_CILIUM" = true ]; then
    echo "Next steps for ArgoCD-managed cluster:"
    echo "1. Register cluster with homelab ArgoCD:"
    if [ -n "$HOMELAB_CONTEXT" ]; then
        echo "   ./scripts/register-cluster.sh k3d-${CLUSTER_NAME} ${HOMELAB_CONTEXT}"
    else
        echo "   ./scripts/register-cluster.sh k3d-${CLUSTER_NAME} <homelab-context>"
    fi
    echo ""
    echo "2. Wait for ArgoCD to deploy Cilium and other core apps"
    echo "   Monitor sync status in ArgoCD UI"
    echo ""
fi

echo "To destroy the cluster:"
echo "  k3d cluster delete ${CLUSTER_NAME}"
echo ""

# Auto-register if homelab context was provided
if [ -n "$HOMELAB_CONTEXT" ] && [ "$SKIP_CILIUM" = true ]; then
    echo "Auto-registering cluster with homelab ArgoCD..."
    ./scripts/register-cluster.sh "k3d-${CLUSTER_NAME}" "${HOMELAB_CONTEXT}"
fi
