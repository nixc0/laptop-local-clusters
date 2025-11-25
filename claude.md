# Project Context for Claude

This document provides context about the local-cluster-standard project for AI assistants.

## Project Overview

**Purpose**: Standardize local Kubernetes cluster testing across multiple laptops (macOS and Linux) with optional centralized GitOps management via homelab ArgoCD.

**Key Technologies**:
- Talos Linux (immutable Kubernetes OS)
- Cilium (eBPF-based CNI)
- ArgoCD (GitOps continuous delivery)
- Docker (container runtime for local clusters)
- VPN/Tailscale (multi-cluster connectivity)

## Architecture

### Two Deployment Modes

**1. Standalone Mode**
- Single laptop with independent cluster
- Cilium and ArgoCD installed locally
- Full autonomy, no external dependencies
- Quick setup for individual development

**2. Multi-Cluster GitOps Mode**
- Multiple laptop clusters managed by centralized homelab ArgoCD
- Core applications (Cilium, monitoring, ingress, cert-manager) synced from Git
- Testing applications deployed manually per laptop
- Consistent infrastructure across all laptops

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
├── cilium-patch.yaml                 # Talos config to disable default CNI
├── create-cluster.sh                 # Cluster creation (standalone or ArgoCD-managed)
├── install-argocd.sh                 # Install ArgoCD locally (standalone mode)
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
│       ├── cilium/                   # Cilium CNI
│       ├── monitoring/               # Prometheus/Grafana
│       └── dev-tools/                # Ingress, cert-manager
└── test-apps/
    └── hello-world/                  # Sample testing application
```

## Key Concepts

### Talos Linux
- Immutable, minimal Kubernetes OS
- API-driven (no SSH access)
- Runs in Docker containers for local development
- Creates realistic production-like environments

### ApplicationSet Pattern
- ArgoCD feature for managing multiple clusters
- Uses cluster labels for targeting (`environment=laptop`)
- Single ApplicationSet → Multiple Applications (one per cluster)
- Enables consistent core infrastructure across all laptops

### Sync Waves
- Control deployment order via annotations
- Wave -1: Cilium (must deploy first for networking)
- Wave 0: Infrastructure (ingress, cert-manager)
- Wave 1: Monitoring
- Wave 2+: Applications

### Hybrid Deployment Model
- **Core Apps**: Managed by ArgoCD, always in sync, cannot be modified manually
- **Testing Apps**: Deployed via kubectl/helm, independent per laptop, not in Git

## Common Workflows

### Create Standalone Cluster
```bash
./create-cluster.sh my-cluster
./install-argocd.sh
```

### Create ArgoCD-Managed Cluster
```bash
# ONE-TIME: Apply bootstrap app to homelab (if not already done)
kubectl apply -f argocd-apps/bootstrap-laptop-management.yaml --context homelab

# Create laptop cluster and register with homelab
./create-cluster.sh --skip-cilium --register-with-homelab homelab my-laptop
# ArgoCD automatically deploys core apps via ApplicationSets
```

### Deploy Testing Application
```bash
kubectl config use-context admin@my-cluster
kubectl apply -f test-apps/hello-world/deployment.yaml
```

### Add New Core Application
1. Create `argocd-apps/core-apps/new-app/` with manifests
2. Add ApplicationSet to `laptop-clusters-applicationset.yaml`
3. Commit and push
4. ArgoCD syncs to all registered clusters

### Destroy Cluster
```bash
talosctl cluster destroy --name my-cluster
```

## Important Files

### bootstrap-laptop-management.yaml
Bootstrap Application deployed to homelab ArgoCD (App-of-Apps pattern):
- Manages the ApplicationSets in Git
- Auto-syncs changes to ApplicationSets
- Applied ONCE to homelab, then everything is GitOps
- Enables fully declarative multi-cluster management

### laptop-clusters-applicationset.yaml
Defines ALL core applications deployed to laptop clusters:
- Managed by the bootstrap Application
- Contains ApplicationSets for Cilium, monitoring, ingress, cert-manager
- Uses cluster selector `environment=laptop` for targeting
- Single source of truth for multi-cluster infrastructure

### cilium-patch.yaml
Talos machine config patch that disables default CNI, allowing Cilium to be installed instead.

### create-cluster.sh
Main cluster creation script with two modes:
- Default: Installs Cilium locally
- `--skip-cilium`: Skips Cilium for ArgoCD management
- `--register-with-homelab`: Auto-registers with homelab ArgoCD

### register-cluster.sh
Registers laptop cluster with homelab ArgoCD:
1. Creates service account in laptop cluster
2. Grants cluster-admin to ArgoCD
3. Adds cluster to ArgoCD with `environment=laptop` label
4. ApplicationSets detect new cluster and deploy core apps

## Configuration

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
- Local clusters use CIDR: 10.5.0.0/24 (default)
- Multiple clusters need different CIDRs: 10.6.0.0/24, etc.
- VPN/Tailscale required for homelab → laptop connectivity
- Services use NodePort (not LoadBalancer) for local clusters

## Troubleshooting

### Cluster Creation Hangs
Normal behavior - nodes stay NotReady until CNI (Cilium) is installed. Wait for script completion.

### ArgoCD Can't Reach Cluster
- Verify VPN/Tailscale connection
- Check cluster API is reachable from homelab
- Test: `kubectl --context homelab cluster-info`

### Applications Not Syncing
- Check Git repository URL in ApplicationSet
- Verify cluster has `environment=laptop` label
- Force sync: `argocd app sync cluster-name-app-name`

### Cilium Not Installing
- Verify Cilium ApplicationSet has sync-wave: "-1"
- Check pods: `kubectl get pods -n kube-system`
- Review logs: `kubectl logs -n kube-system -l k8s-app=cilium`

## Design Decisions

### Why Talos?
- Production-like immutable OS
- API-driven (no SSH)
- Security-focused
- Runs well in Docker for local development

### Why Cilium?
- Modern eBPF-based networking
- Superior observability (Hubble)
- Network policies
- kube-proxy replacement

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

### When Updating Documentation
- README.md: Quick start and common operations
- CLUSTER_PLAN.md: Architecture rationale and design
- MULTI_CLUSTER_SETUP.md: Multi-cluster setup and workflows
- Individual READMEs: Context-specific documentation

## Repository State

- Git initialized: Yes
- Commits: 2
  1. Initial commit (standalone mode)
  2. Multi-cluster GitOps architecture
- Remote: Not yet configured (user should push to GitHub)
- Branch: main

## Next Steps for User

1. Push repository to GitHub/GitLab
2. Update repository URLs in both files (replace YOUR-USERNAME):
   - `argocd-apps/bootstrap-laptop-management.yaml`
   - `argocd-apps/laptop-clusters-applicationset.yaml`
3. Apply bootstrap Application to homelab ArgoCD (ONE-TIME):
   ```bash
   kubectl apply -f argocd-apps/bootstrap-laptop-management.yaml --context homelab
   ```
4. Create first laptop cluster and register
5. Verify core apps deploy automatically via ApplicationSets
6. Deploy testing applications manually

## Important Notes

- **Secrets**: Not managed yet - consider sealed-secrets or external-secrets
- **Backstage**: Mentioned in requirements but not yet implemented
- **VPN/Tailscale**: Required for multi-cluster mode, not covered in detail
- **Security**: Service account has cluster-admin - reduce in production
- **Storage**: Uses default storage class or emptyDir
- **Long-running**: Designed for clusters that persist days/weeks, not ephemeral

## Related Documentation

- [Talos Documentation](https://www.talos.dev/)
- [Cilium Documentation](https://docs.cilium.io/)
- [ArgoCD ApplicationSets](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [ArgoCD Multi-Cluster](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#clusters)
