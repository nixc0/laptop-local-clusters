#!/bin/bash

set -e

# Script to register a local laptop cluster with homelab ArgoCD

CLUSTER_NAME="${1:-talos-local}"
HOMELAB_CONTEXT="${2:-homelab}"

echo "========================================"
echo "Registering Cluster with Homelab ArgoCD"
echo "========================================"
echo ""
echo "Cluster name: ${CLUSTER_NAME}"
echo "Homelab context: ${HOMELAB_CONTEXT}"
echo ""

# Check if argocd CLI is installed
if ! command -v argocd &> /dev/null; then
    echo "Error: argocd CLI is not installed"
    echo "Install from: https://argo-cd.readthedocs.io/en/stable/cli_installation/"
    exit 1
fi

# Verify homelab context exists
if ! kubectl config get-contexts "${HOMELAB_CONTEXT}" &> /dev/null; then
    echo "Error: Homelab context '${HOMELAB_CONTEXT}' not found"
    echo "Available contexts:"
    kubectl config get-contexts -o name
    exit 1
fi

# Verify laptop cluster context exists
# k3d creates contexts with name "k3d-NAME" while Talos uses "admin@NAME"
LAPTOP_CONTEXT="${CLUSTER_NAME}"
if ! kubectl config get-contexts "${LAPTOP_CONTEXT}" &> /dev/null; then
    # Try Talos naming convention
    LAPTOP_CONTEXT="admin@${CLUSTER_NAME}"
    if ! kubectl config get-contexts "${LAPTOP_CONTEXT}" &> /dev/null; then
        echo "Error: Laptop cluster context not found"
        echo "Tried: ${CLUSTER_NAME} and admin@${CLUSTER_NAME}"
        echo "Available contexts:"
        kubectl config get-contexts -o name | grep -v "homelab"
        exit 1
    fi
fi
echo "Using context: ${LAPTOP_CONTEXT}"
echo ""

# Get laptop cluster server URL
echo "Getting laptop cluster API server URL..."
# k3d names clusters as "k3d-NAME" while Talos uses "NAME"
LAPTOP_SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"${CLUSTER_NAME}\")].cluster.server}")
if [ -z "$LAPTOP_SERVER" ]; then
    echo "Error: Could not find server URL for cluster '${CLUSTER_NAME}'"
    exit 1
fi

echo "Laptop cluster API: ${LAPTOP_SERVER}"
echo ""

# Switch to homelab context
echo "Switching to homelab context..."
kubectl config use-context "${HOMELAB_CONTEXT}"

# Check if ArgoCD is running
echo "Verifying ArgoCD is running on homelab cluster..."
if ! kubectl get namespace argocd &> /dev/null; then
    echo "Error: ArgoCD namespace not found on homelab cluster"
    echo "Please install ArgoCD on your homelab cluster first"
    exit 1
fi

# Get ArgoCD admin password (for CLI login)
echo ""
echo "Getting ArgoCD credentials..."
ARGOCD_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")

if [ -z "$ARGOCD_PWD" ]; then
    echo "Warning: Could not retrieve ArgoCD password automatically"
    echo "You may need to log in manually"
fi

# Port forward to ArgoCD (in background)
echo "Setting up port forward to ArgoCD..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 &> /dev/null &
PF_PID=$!

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up port forward..."
    kill $PF_PID 2>/dev/null || true
}
trap cleanup EXIT

# Wait for port forward to be ready
sleep 3

# Login to ArgoCD
echo "Logging into ArgoCD..."
if [ -n "$ARGOCD_PWD" ]; then
    argocd login localhost:8080 --username admin --password "$ARGOCD_PWD" --insecure
else
    echo "Please log in manually:"
    argocd login localhost:8080 --insecure
fi

# Get service account token for the laptop cluster
echo ""
echo "Creating service account for ArgoCD in laptop cluster..."
kubectl config use-context "${LAPTOP_CONTEXT}"

# Create argocd-manager service account
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: argocd-manager
type: kubernetes.io/service-account-token
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: argocd-manager
    namespace: kube-system
EOF

echo "Waiting for token to be generated..."
sleep 3

# Get the token
TOKEN=$(kubectl -n kube-system get secret argocd-manager-token -o jsonpath='{.data.token}' | base64 -d)

# Get the CA cert
CA_CERT=$(kubectl -n kube-system get secret argocd-manager-token -o jsonpath='{.data.ca\.crt}')

# Switch back to homelab context
kubectl config use-context "${HOMELAB_CONTEXT}"

# Register the cluster with ArgoCD
echo ""
echo "Registering cluster '${CLUSTER_NAME}' with ArgoCD..."

argocd cluster add "${LAPTOP_CONTEXT}" \
  --name "${CLUSTER_NAME}" \
  --server "${LAPTOP_SERVER}" \
  --service-account argocd-manager \
  --system-namespace kube-system \
  --label environment=laptop \
  --label hostname="$(hostname -s)" \
  --yes

echo ""
echo "========================================"
echo "Cluster registered successfully!"
echo "========================================"
echo ""
echo "The laptop cluster '${CLUSTER_NAME}' has been registered with ArgoCD."
echo ""
echo "Core applications will be automatically deployed via ApplicationSet."
echo "Check ArgoCD UI to monitor the sync status:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Visit: https://localhost:8080"
echo ""
echo "To verify cluster registration:"
echo "  argocd cluster list"
echo ""
echo "To deploy testing applications (not managed by ArgoCD):"
echo "  kubectl config use-context ${LAPTOP_CONTEXT}"
echo "  kubectl apply -f your-test-app.yaml"
echo ""
