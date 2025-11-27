# Project Context for Claude

This document provides context about the laptop-local-clusters project for AI assistants.

## Project Overview

**Purpose**: Standardize local Kubernetes cluster testing across multiple laptops (macOS and Linux) with optional centralized GitOps management via homelab ArgoCD.

**Key Technologies**:
- **k3d** (k3s in Docker) - Lightweight local Kubernetes clusters
- **k3s** - Lightweight production Kubernetes distribution
- **Cilium** (optional, eBPF-based CNI) - For ArgoCD-managed clusters
- **Flannel** (default CNI) - For standalone clusters
- **ArgoCD** - GitOps continuous delivery
- **Docker Desktop / Podman Desktop** - Container runtime

## Architecture

### Two Deployment Modes

**1. Standalone Mode**
- Single laptop with independent cluster
- Uses k3s default Flannel CNI (fast, simple)
- Optional ArgoCD installed locally
- Full autonomy, no external dependencies
- **Ultra-fast setup: ~15 seconds**

**2. Multi-Cluster GitOps Mode**
- Multiple laptop clusters managed by centralized homelab ArgoCD
- Core applications (Cilium with ingress, monitoring, cert-manager) synced from Git
- Testing applications deployed manually per laptop
- Consistent infrastructure across all laptops
- **ArgoCD installs Cilium CNI** (Flannel disabled)

### Multi-Cluster Architecture Flow
```
Homelab Cluster (ArgoCD)
    ↓ (via VPN/Tailscale)
Git Repository (core-apps)
    ↓
Laptop Clusters (labeled: environment=laptop)
    ├─ Core Apps (ArgoCD-managed, synced)
    └─ Testing Apps (manual kubectl/helm)
```

## Directory Structure

```
.
├── README.md                         # Quick start guide
├── CLUSTER_PLAN.md                   # Detailed feasibility analysis
├── MULTI_CLUSTER_SETUP.md            # Multi-cluster setup guide
├── CLAUDE.md                         # This file
├── create-cluster-k3d.sh             # k3d cluster creation (PRIMARY SCRIPT)
├── create-cluster.sh                 # Legacy Talos script (deprecated)
├── install-argocd.sh                 # Install ArgoCD locally (standalone mode)
├── cilium-patch.yaml                 # Legacy Talos config (not used with k3d)
├── scripts/
│   ├── README.md                     # Scripts documentation
│   └── register-cluster.sh           # Register laptop with homelab ArgoCD
├── argocd-apps/
│   ├── README.md                     # ArgoCD apps documentation
│   ├── bootstrap-laptop-management.yaml      # Bootstrap app (apply once to homelab)
│   ├── laptop-clusters-applicationset.yaml   # ApplicationSets (managed by bootstrap)
│   ├── hello-world-app.yaml          # Example ArgoCD app
│   └── core-apps/                    # Core infrastructure apps
│       ├── README.md                 # Core apps documentation
│       ├── cilium/                   # Cilium CNI + Ingress Controller
│       ├── monitoring/               # Prometheus/Grafana
│       └── dev-tools/                # cert-manager
└── test-apps/
    └── hello-world/                  # Sample testing application
```

## Key Concepts

### k3d and k3s
- **k3d**: Tool to run k3s clusters in Docker containers
- **k3s**: Lightweight Kubernetes (CNCF-certified distribution)
- Production-ready but optimized for resource-constrained environments
- Perfect for local development and testing
- Fast startup, low memory footprint

### Container Runtime Detection
- Scripts automatically detect Docker Desktop or Podman Desktop
- Sets `DOCKER_HOST` environment variable if Podman is detected
- Works seamlessly with both runtimes

### ApplicationSet Pattern
- ArgoCD feature for managing multiple clusters
- Uses cluster labels for targeting (`environment=laptop`)
- Single ApplicationSet → Multiple Applications (one per cluster)
- Enables consistent core infrastructure across all laptops

### Sync Waves
- Control deployment order via annotations
- Wave -1: Cilium (must deploy first for networking and ingress)
- Wave 0: Infrastructure (cert-manager)
- Wave 1: Monitoring
- Wave 2+: Applications

### Hybrid Deployment Model
- **Core Apps**: Managed by ArgoCD, always in sync, cannot be modified manually
- **Testing Apps**: Deployed via kubectl/helm, independent per laptop, not in Git

### CNI Selection
- **Standalone mode**: Uses Flannel (k3s default) - fast, simple, battle-tested
- **ArgoCD-managed mode**: Uses Cilium (installed by ArgoCD) - advanced features, observability

## Common Workflows

### Create Standalone Cluster
```bash
./create-cluster-k3d.sh my-cluster
./install-argocd.sh  # optional
```

### Create ArgoCD-Managed Cluster
```bash
# ONE-TIME: Apply bootstrap app to homelab (if not already done)
kubectl apply -f argocd-apps/bootstrap-laptop-management.yaml --context homelab

# Create laptop cluster and register with homelab
./create-cluster-k3d.sh --skip-cilium --register-with-homelab homelab my-laptop
# ArgoCD automatically deploys core apps via ApplicationSets
```

### Deploy Testing Application
```bash
kubectl config use-context k3d-my-cluster
kubectl apply -f test-apps/hello-world/deployment.yaml
```

### Add New Core Application
1. Create `argocd-apps/core-apps/new-app/` with manifests
2. Add ApplicationSet to `laptop-clusters-applicationset.yaml`
3. Commit and push
4. ArgoCD syncs to all registered clusters

### Destroy Cluster
```bash
k3d cluster delete my-cluster
```

## Important Files

### create-cluster-k3d.sh (PRIMARY SCRIPT)
Main cluster creation script with two modes:
- Default: Creates cluster with Flannel CNI (~15 seconds)
- `--skip-cilium`: Disables Flannel for ArgoCD to install Cilium
- `--register-with-homelab`: Auto-registers with homelab ArgoCD
- Automatically detects Docker/Podman

### bootstrap-laptop-management.yaml
Bootstrap Application deployed to homelab ArgoCD (App-of-Apps pattern):
- Manages the ApplicationSets in Git
- Auto-syncs changes to ApplicationSets
- Applied ONCE to homelab, then everything is GitOps
- Enables fully declarative multi-cluster management

### laptop-clusters-applicationset.yaml
Defines ALL core applications deployed to laptop clusters:
- Managed by the bootstrap Application
- Contains ApplicationSets for Cilium (with ingress), monitoring, cert-manager
- Uses cluster selector `environment=laptop` for targeting
- Single source of truth for multi-cluster infrastructure

### register-cluster.sh
Registers laptop cluster with homelab ArgoCD:
1. Creates service account in laptop cluster
2. Grants cluster-admin to ArgoCD
3. Adds cluster to ArgoCD with `environment=laptop` label
4. ApplicationSets detect new cluster and deploy core apps
5. **Updated to support both k3d and legacy Talos naming conventions**

## Configuration

### Cluster Context Naming
- **k3d clusters**: Context named `k3d-<cluster-name>` (e.g., `k3d-my-laptop`)
- **Legacy Talos**: Context named `admin@<cluster-name>` (e.g., `admin@my-laptop`)
- Registration script handles both conventions automatically

### Cluster Labels
Registered clusters should have:
- `environment: laptop` (required for ApplicationSet targeting)
- `hostname: <hostname>` (for identification)
- Custom labels for per-cluster customization

### Resource Sizing
Core apps use reduced resource limits for local clusters:
- Prometheus: 512Mi-1Gi memory
- Grafana: 128Mi-256Mi memory
- Single replica for most components

### Networking
- k3d automatically manages networking (no CIDR conflicts)
- Multiple clusters can run simultaneously without configuration
- Services use NodePort (not LoadBalancer) for local clusters
- VPN/Tailscale required for homelab → laptop connectivity

## Troubleshooting

### Cluster Creation Fast but Nodes NotReady
Normal for ArgoCD-managed clusters - nodes stay NotReady until Cilium is installed by ArgoCD.

### ArgoCD Can't Reach Cluster
- Verify VPN/Tailscale connection
- Check cluster API is reachable from homelab
- Test: `kubectl --context homelab exec -it <argocd-pod> -- curl <laptop-cluster-api>`

### Applications Not Syncing
- Check Git repository URL in ApplicationSet
- Verify cluster has `environment=laptop` label
- Force sync: `argocd app sync cluster-name-app-name`

### Cilium Not Installing (ArgoCD-managed clusters)
- Verify Cilium ApplicationSet has sync-wave: "-1"
- Check pods: `kubectl get pods -n kube-system`
- Review logs: `kubectl logs -n kube-system -l k8s-app=cilium`
- Confirm Flannel was disabled: `kubectl get pods -A | grep flannel` (should be empty)

### Container Runtime Issues
- **Docker Desktop**: Ensure it's running
- **Podman Desktop**: Ensure Docker socket compatibility is enabled
- Check: `docker ps` or `podman ps`
- Script shows which runtime is detected

## Design Decisions

### Why k3d (instead of Talos)?
- **Speed**: 15 seconds vs hours of troubleshooting
- **Reliability**: Excellent macOS/Podman compatibility
- **Simplicity**: Fewer moving parts, easier to debug
- **Familiarity**: Standard Kubernetes, no custom API-driven OS
- **Resource Efficiency**: Lightweight, perfect for laptops
- **Iteration Speed**: Create/destroy in seconds

### Why Still Support Cilium?
- Modern eBPF-based networking
- Superior observability (Hubble)
- Network policies
- kube-proxy replacement
- Useful for testing production-like scenarios

### Why Flannel for Standalone?
- Battle-tested, stable
- Low resource usage
- Fast startup
- No configuration needed
- Good enough for local testing

### Why Multi-Cluster GitOps?
- Consistent core infrastructure across laptops
- Centralized management from homelab
- Flexibility for independent testing apps
- Realistic multi-cluster scenarios

### Why Hybrid Model?
- Core apps need consistency (monitoring, networking)
- Testing apps need flexibility (experimentation, feature branches)
- Separates infrastructure from applications
- Prevents accidental modification of core infrastructure

## Development Notes

### When Modifying Core Apps
1. Edit files in `argocd-apps/core-apps/`
2. Update ApplicationSet if needed
3. Commit and push
4. ArgoCD auto-syncs to all clusters (if automated sync enabled)

### When Adding Scripts
1. Place in `scripts/`
2. Make executable: `chmod +x scripts/script.sh`
3. Update `scripts/README.md`
4. Follow existing error handling patterns
5. Support both Docker and Podman

### When Updating Documentation
- README.md: Quick start and common operations
- CLUSTER_PLAN.md: Architecture rationale and design
- MULTI_CLUSTER_SETUP.md: Multi-cluster setup and workflows
- CLAUDE.md: Context for AI assistants (this file)

## Repository State

- Git initialized: Yes
- Primary script: `create-cluster-k3d.sh`
- Remote: Should be pushed to GitHub/GitLab
- Branch: main

## Migration from Talos

**Why we migrated:**
- Talos had persistent Docker socket connection issues on macOS
- Talos clusters took hours to troubleshoot vs 15 seconds with k3d
- k3d has better Podman Desktop compatibility
- Simpler architecture, fewer points of failure
- Same GitOps multi-cluster architecture still works

**What was kept:**
- Multi-cluster GitOps architecture
- ApplicationSet pattern
- Core apps structure
- Hybrid deployment model
- Documentation structure

**What changed:**
- Cluster creation tool: Talos → k3d
- Default CNI: None (Talos) → Flannel (k3s default)
- Cluster creation time: Minutes/hours → 15 seconds
- Context naming: `admin@name` → `k3d-name`
- Cluster management: `talosctl` → `k3d`

## Next Steps for User

1. **Immediate**: Start creating k3d clusters for local testing
2. **Optional**: Push repository to GitHub/GitLab
3. **Optional**: Update repository URLs in ApplicationSet files
4. **Optional**: Apply bootstrap Application to homelab ArgoCD
5. **Optional**: Create and register laptop clusters with homelab
6. **Optional**: Verify core apps deploy automatically via ApplicationSets
7. **Always**: Deploy testing applications manually to laptop clusters

## Important Notes

- **Secrets**: Not managed yet - consider sealed-secrets or external-secrets
- **VPN/Tailscale**: Required for multi-cluster mode, not covered in detail
- **Security**: Service account has cluster-admin - reduce in production
- **Storage**: Uses default storage class or emptyDir
- **Podman**: Requires `podman-mac-helper` for Docker socket compatibility on macOS

## Related Documentation

- [k3d Documentation](https://k3d.io/)
- [k3s Documentation](https://docs.k3s.io/)
- [Cilium Documentation](https://docs.cilium.io/)
- [ArgoCD ApplicationSets](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [ArgoCD Multi-Cluster](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#clusters)
- [Podman Desktop](https://podman-desktop.io/)
