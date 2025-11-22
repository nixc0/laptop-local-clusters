#!/bin/bash

set -e

echo "========================================"
echo "Installing ArgoCD"
echo "========================================"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed"
    exit 1
fi

# Create namespace
echo "Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
echo "Installing ArgoCD manifests..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
echo ""
echo "Waiting for ArgoCD to be ready (this may take a few minutes)..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd

echo ""
echo "========================================"
echo "ArgoCD is ready!"
echo "========================================"
echo ""

# Get initial admin password
echo "Initial admin credentials:"
echo "  Username: admin"
echo -n "  Password: "
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "(secret not found yet, wait a moment)"
echo ""
echo ""

echo "To access ArgoCD UI:"
echo "  1. Port forward:"
echo "     kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "  2. Visit: https://localhost:8080"
echo "     (Accept the self-signed certificate warning)"
echo ""
echo "  3. Login with username 'admin' and password above"
echo ""
echo "Or use the ArgoCD CLI:"
echo "  argocd login localhost:8080 --insecure"
echo ""
