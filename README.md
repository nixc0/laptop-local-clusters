# Local Kubernetes Cluster Standard

Standardized setup for local Kubernetes testing clusters using Talos Linux, Cilium CNI, and ArgoCD.

Works on both macOS and Linux laptops with consistent configuration.

## Quick Start

### Prerequisites

Make sure you have these installed:
- Docker (18.03+)
- talosctl
- kubectl
- cilium CLI (optional but recommended)
- argocd CLI (optional)

See [CLUSTER_PLAN.md](CLUSTER_PLAN.md) for detailed installation instructions for your platform.

### Create Your First Cluster

```bash
# Clone this repo on your laptop
git clone <your-repo-url>
cd local-cluster-standard

# Make scripts executable (first time only)
chmod +x *.sh

# Create a cluster (default: 1 control plane, 2 workers)
./create-cluster.sh

# Install ArgoCD
./install-argocd.sh
```

That's it! You now have a fully functional Kubernetes cluster with Cilium and ArgoCD.

## Two Modes of Operation

This repository supports two deployment models:

### 1. Standalone Mode (Default)
Perfect for individual testing and development on a single laptop.
- Cilium and ArgoCD installed locally on the cluster
- Full autonomy per cluster
- Quick setup with `./create-cluster.sh`

### 2. Multi-Cluster GitOps Mode
Ideal when you have multiple laptops and want consistent core applications managed centrally.
- **Homelab ArgoCD** manages core apps (Cilium, monitoring, ingress, cert-manager) on ALL laptop clusters
- **Laptop clusters** can still deploy testing apps manually (kubectl/helm)
- Core apps always in sync, testing apps are independent

**Use Multi-Cluster GitOps when:**
- You work across multiple laptops (MacBook + Linux)
- You want core infrastructure consistent everywhere
- You have a homelab cluster with ArgoCD
- Laptops connect to homelab via VPN/Tailscale

**See [MULTI_CLUSTER_SETUP.md](MULTI_CLUSTER_SETUP.md) for complete multi-cluster setup guide.**

### Quick Multi-Cluster Start

```bash
# On your laptop (after homelab ArgoCD is set up)
./create-cluster.sh --skip-cilium --register-with-homelab homelab my-laptop

# ArgoCD will automatically deploy:
# - Cilium CNI
# - Prometheus/Grafana monitoring
# - Ingress-nginx
# - Cert-manager
# - Any other core apps defined in the ApplicationSet

# Deploy testing apps manually:
kubectl apply -f test-apps/hello-world/deployment.yaml
```

## Common Commands

### Create Cluster Variants

```bash
# Default cluster
./create-cluster.sh

# Custom name and size
./create-cluster.sh my-test 3 1  # name, workers, control-planes

# Minimal single-node cluster
./create-cluster.sh mini 0 1
```

### Manage Clusters

```bash
# List running clusters
talosctl cluster show

# Get cluster info
kubectl cluster-info
kubectl get nodes

# Destroy cluster
talosctl cluster destroy --name talos-local

# Destroy specific cluster
talosctl cluster destroy --name my-test
```

### Verify Installation

```bash
# Check Cilium status
cilium status

# Run Cilium connectivity test
cilium connectivity test

# Check ArgoCD
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
local-cluster-standard/
├── README.md                         # This file
├── CLUSTER_PLAN.md                   # Detailed plan and rationale
├── MULTI_CLUSTER_SETUP.md            # Multi-cluster GitOps guide
├── create-cluster.sh                 # Cluster creation script
├── install-argocd.sh                 # ArgoCD installation script (standalone)
├── cilium-patch.yaml                 # Talos config for Cilium CNI
├── scripts/
│   └── register-cluster.sh           # Register laptop with homelab ArgoCD
├── test-apps/                        # Sample testing applications
│   └── hello-world/
└── argocd-apps/                      # ArgoCD application manifests
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
./create-cluster.sh cluster1

# Create second cluster (requires different CIDR)
talosctl cluster create --name cluster2 --cidr 10.6.0.0/24 --config-patch @cilium-patch.yaml

# Switch between clusters
kubectl config use-context admin@cluster1
kubectl config use-context admin@cluster2
```

## Troubleshooting

### Cluster creation hangs
This is normal! Nodes won't show as "Ready" until Cilium is installed. Wait for the script to complete.

### Can't connect to Docker on macOS
```bash
sudo ln -s ~/Library/Containers/com.docker.docker/Data/docker.sock /var/run/docker.sock
```

### DNS not working in pods
The scripts already handle this, but if you're installing Cilium manually:
```bash
cilium install --set forwardKubeDNSToHost=false
```

### More help
See [CLUSTER_PLAN.md](CLUSTER_PLAN.md) for comprehensive documentation, known issues, and solutions.

## What Makes This Special?

- **Cross-platform**: Same setup on macOS and Linux
- **Production-like**: Talos is an immutable, secure, minimal Kubernetes OS
- **Modern CNI**: Cilium with eBPF for high-performance networking
- **GitOps ready**: ArgoCD for declarative deployments
- **Fast iteration**: Create/destroy clusters in minutes
- **Multi-cluster**: Test complex scenarios with multiple clusters

## Next Steps

### Standalone Mode
1. Deploy a test application to verify everything works
2. Set up an ArgoCD application to deploy from Git
3. Experiment with Cilium features (network policies, hubble, etc.)

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

## Resources

- [Talos Documentation](https://www.talos.dev/)
- [Cilium Documentation](https://docs.cilium.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
