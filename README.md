# Local Kubernetes Cluster Standard

Standardized setup for local Kubernetes testing clusters using k3d, optional Cilium CNI, and ArgoCD.

Works on both macOS and Linux laptops with consistent configuration, using either Docker Desktop or Podman Desktop.

## Quick Start

### Prerequisites

Make sure you have these installed:
- **Docker Desktop** or **Podman Desktop** (with Docker socket compatibility)
- **k3d** - Lightweight Kubernetes in Docker
- **kubectl** - Kubernetes CLI
- **cilium CLI** (optional, only if using Cilium via ArgoCD)
- **argocd CLI** (optional, for multi-cluster setup)

#### Install k3d

```bash
# macOS
brew install k3d

# Linux
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
```

See [CLUSTER_PLAN.md](CLUSTER_PLAN.md) for detailed installation instructions for your platform.

### Create Your First Cluster

```bash
# Clone this repo on your laptop
git clone <your-repo-url>
cd laptop-local-clusters

# Make scripts executable (first time only)
chmod +x *.sh scripts/*.sh

# Create a cluster (default: 1 control plane, 2 workers, Flannel CNI)
./create-cluster-k3d.sh

# Optional: Install ArgoCD for standalone use
./install-argocd.sh
```

That's it! You now have a fully functional Kubernetes cluster ready in **15-30 seconds**.

## Two Modes of Operation

This repository supports two deployment models:

### 1. Standalone Mode (Default)
Perfect for individual testing and development on a single laptop.
- Uses k3s default Flannel CNI (fast, simple)
- Optional ArgoCD installed locally on the cluster
- Full autonomy per cluster
- Ultra-fast setup: **~15 seconds**

```bash
./create-cluster-k3d.sh my-cluster
```

### 2. Multi-Cluster GitOps Mode
Ideal when you have multiple laptops and want consistent core applications managed centrally.
- **Homelab ArgoCD** manages core apps (Cilium CNI, monitoring, ingress, cert-manager) on ALL laptop clusters
- **Laptop clusters** can still deploy testing apps manually (kubectl/helm)
- Core apps always in sync, testing apps are independent
- Uses Cilium CNI (managed by ArgoCD) instead of Flannel

**Use Multi-Cluster GitOps when:**
- You work across multiple laptops (MacBook + Linux)
- You want core infrastructure consistent everywhere
- You have a homelab cluster with ArgoCD
- Laptops connect to homelab via VPN/Tailscale

**See [MULTI_CLUSTER_SETUP.md](MULTI_CLUSTER_SETUP.md) for complete multi-cluster setup guide.**

### Quick Multi-Cluster Start

```bash
# ONE-TIME: On homelab cluster, apply the bootstrap Application
kubectl apply -f argocd-apps/bootstrap-laptop-management.yaml --context homelab
# This creates the ApplicationSets that manage all laptop clusters

# On your laptop (creates cluster and registers with homelab)
./create-cluster-k3d.sh --skip-cilium --register-with-homelab homelab my-laptop

# ArgoCD will automatically deploy core apps:
# - Cilium CNI with Ingress Controller (sync-wave -1, deploys first)
# - Cert-manager (sync-wave 0)
# - Prometheus/Grafana monitoring (sync-wave 1)

# Deploy testing apps manually (not managed by ArgoCD):
kubectl apply -f test-apps/hello-world/deployment.yaml
```

## Common Commands

### Create Cluster Variants

```bash
# Default cluster (1 control plane, 2 workers)
./create-cluster-k3d.sh

# Custom name and size
./create-cluster-k3d.sh my-test 3 1  # name, workers, control-planes

# Minimal single-node cluster
./create-cluster-k3d.sh mini 0 1

# ArgoCD-managed cluster (with Cilium)
./create-cluster-k3d.sh --skip-cilium --register-with-homelab homelab laptop-name
```

### Manage Clusters

```bash
# List running clusters
k3d cluster list

# Get cluster info
kubectl cluster-info --context k3d-my-cluster
kubectl get nodes --context k3d-my-cluster

# Destroy cluster
k3d cluster delete my-cluster

# Stop/start cluster (preserves state)
k3d cluster stop my-cluster
k3d cluster start my-cluster
```

### Verify Installation

```bash
# Check nodes
kubectl get nodes

# Check all pods
kubectl get pods -A

# Check Cilium status (if using ArgoCD-managed cluster)
cilium status

# Check ArgoCD (if installed)
kubectl get pods -n argocd
```

### Access ArgoCD

```bash
# Port forward to ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Then visit: https://localhost:8080
# Username: admin
# Password: (run this command)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Repository Structure

```
laptop-local-clusters/
├── README.md                         # This file
├── CLUSTER_PLAN.md                   # Detailed plan and rationale
├── MULTI_CLUSTER_SETUP.md            # Multi-cluster GitOps guide
├── CLAUDE.md                         # Project context for AI assistants
├── create-cluster-k3d.sh             # k3d cluster creation script (PRIMARY)
├── create-cluster.sh                 # Legacy Talos script (deprecated)
├── install-argocd.sh                 # ArgoCD installation script (standalone)
├── cilium-patch.yaml                 # Legacy Talos config (not used with k3d)
├── scripts/
│   └── register-cluster.sh           # Register laptop with homelab ArgoCD
├── test-apps/                        # Sample testing applications
│   └── hello-world/
└── argocd-apps/                      # ArgoCD application manifests
    ├── bootstrap-laptop-management.yaml     # Bootstrap app (App-of-Apps)
    ├── laptop-clusters-applicationset.yaml  # Multi-cluster deployment
    └── core-apps/                    # Core apps (Cilium, monitoring, etc.)
        ├── cilium/
        ├── monitoring/
        └── dev-tools/
```

## Multiple Clusters

You can run multiple clusters simultaneously:

```bash
# Create first cluster
./create-cluster-k3d.sh cluster1

# Create second cluster
./create-cluster-k3d.sh cluster2

# k3d automatically manages networking, no CIDR conflicts!

# Switch between clusters
kubectl config use-context k3d-cluster1
kubectl config use-context k3d-cluster2

# List all contexts
kubectl config get-contexts
```

## Troubleshooting

### Container runtime not found
If you see "Docker daemon not running":
- **Docker Desktop**: Make sure it's started
- **Podman Desktop**: Make sure it's started and Docker socket compatibility is enabled
- The script automatically detects and uses either runtime

### Cluster creation fails
```bash
# Clean up any partial state
k3d cluster delete <cluster-name>
docker network prune -f
docker volume prune -f

# Try again
./create-cluster-k3d.sh <cluster-name>
```

### Nodes NotReady (ArgoCD-managed clusters only)
This is expected! With `--skip-cilium`, nodes stay NotReady until ArgoCD installs Cilium CNI. Wait for ArgoCD sync to complete.

### Can't reach homelab from laptop
Multi-cluster mode requires VPN/Tailscale for homelab → laptop communication. See [MULTI_CLUSTER_SETUP.md](MULTI_CLUSTER_SETUP.md).

### More help
See [CLUSTER_PLAN.md](CLUSTER_PLAN.md) for comprehensive documentation, known issues, and solutions.

## What Makes This Special?

- **Blazing Fast**: Clusters ready in 15-30 seconds (vs hours with other tools)
- **Cross-platform**: Same setup on macOS and Linux
- **Flexible Runtime**: Works with Docker Desktop or Podman Desktop
- **Modern CNI**: Optional Cilium with eBPF for high-performance networking
- **GitOps ready**: ArgoCD for declarative deployments
- **Instant iteration**: Create/destroy clusters in seconds
- **Multi-cluster**: Test complex scenarios with multiple clusters
- **Resource efficient**: k3s is lightweight and runs great on laptops

## Migration from Talos

This repository previously used Talos Linux. We migrated to k3d for:
- **Speed**: 15 seconds vs hours of troubleshooting
- **Reliability**: Better macOS/Podman compatibility
- **Simplicity**: Fewer moving parts
- **Flexibility**: Still supports same GitOps architecture

The old `create-cluster.sh` (Talos) is kept for reference but **deprecated**. Use `create-cluster-k3d.sh` instead.

## Next Steps

### Standalone Mode
1. Deploy a test application to verify everything works
2. Set up an ArgoCD application to deploy from Git
3. Experiment with k3s features and lightweight Kubernetes

### Multi-Cluster GitOps Mode
1. Read [MULTI_CLUSTER_SETUP.md](MULTI_CLUSTER_SETUP.md) for complete setup
2. Push this repo to GitHub/GitLab
3. Deploy ApplicationSet to homelab ArgoCD
4. Create and register laptop clusters
5. Deploy testing apps manually while core apps auto-sync

### Advanced
- Read [CLUSTER_PLAN.md](CLUSTER_PLAN.md) for detailed architecture and rationale
- Customize core app configurations in `argocd-apps/core-apps/`
- Add your own core applications to the ApplicationSet
- Explore Cilium features (network policies, Hubble observability, etc.)

## Resources

- [k3d Documentation](https://k3d.io/)
- [k3s Documentation](https://docs.k3s.io/)
- [Cilium Documentation](https://docs.cilium.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Podman Desktop](https://podman-desktop.io/)
