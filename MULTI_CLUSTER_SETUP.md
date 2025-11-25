# Multi-Cluster GitOps Setup

This guide explains how to use your homelab ArgoCD to manage core applications across all your laptop clusters while retaining the ability to deploy testing applications locally.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│          Homelab Cluster                                │
│                                                          │
│  ┌───────────────────────────────────────────────────┐  │
│  │              ArgoCD                                │  │
│  │                                                    │  │
│  │  1. Bootstrap App (you apply once)                │  │
│  │     ↓                                              │  │
│  │  2. ApplicationSets (auto-synced from Git)        │  │
│  │     - laptop-clusters-cilium                      │  │
│  │     - laptop-clusters-monitoring                  │  │
│  │     - laptop-clusters-ingress-nginx               │  │
│  │     - laptop-clusters-cert-manager                │  │
│  │     ↓                                              │  │
│  │  3. Applications (auto-created per cluster)       │  │
│  │     When cluster labeled environment=laptop       │  │
│  └─────┬──────────────────────────┬──────────────────┘  │
└────────┼──────────────────────────┼─────────────────────┘
         │                          │
         │ (via VPN/Tailscale)      │
         │                          │
    ┌────▼──────────────┐    ┌──────▼────────────────┐
    │  MacBook Cluster  │    │  Linux Laptop Cluster │
    │                   │    │                       │
    │  Core Apps:       │    │  Core Apps:           │
    │  ✓ Cilium         │    │  ✓ Cilium             │
    │  ✓ Monitoring     │    │  ✓ Monitoring         │
    │  ✓ Ingress        │    │  ✓ Ingress            │
    │  ✓ Cert-Manager   │    │  ✓ Cert-Manager       │
    │                   │    │                       │
    │  Testing Apps:    │    │  Testing Apps:        │
    │  • App A (local)  │    │  • App C (local)      │
    │  • App B (local)  │    │                       │
    └───────────────────┘    └───────────────────────┘
         ▲                         ▲
         │                         │
    kubectl apply           kubectl apply
    (not in Git)           (not in Git)
```

**GitOps Flow:**
```
GitHub Repo
    ↓
1. Bootstrap App (applied once to homelab)
    ↓ (watches argocd-apps/laptop-clusters-applicationset.yaml)
2. ApplicationSets (auto-synced)
    ↓ (watches for clusters with environment=laptop label)
3. Applications (auto-created when cluster registered)
    ↓ (deploys to laptop clusters)
4. Core Infrastructure (Cilium, Monitoring, etc.)
```

## Prerequisites

### On Homelab Cluster
1. ArgoCD installed and running
2. Accessible via VPN/Tailscale from laptop clusters

### On Laptop Clusters
1. VPN/Tailscale configured to reach homelab
2. This repository cloned locally
3. Cluster created via `create-cluster.sh`

### Required Tools
- `argocd` CLI
- `kubectl`
- `talosctl`
- VPN/Tailscale client

## Setup Guide

### Step 1: Push Repository to Git

First, push this repository to GitHub (or your preferred Git hosting):

```bash
# On your laptop
git remote add origin https://github.com/YOUR-USERNAME/local-cluster-standard.git
git push -u origin main
```

### Step 2: Update ApplicationSet Repository URL

Edit the ApplicationSet to point to your Git repository:

```bash
# Edit this file
vim argocd-apps/laptop-clusters-applicationset.yaml

# Update line with YOUR-USERNAME to your actual GitHub username
# repoURL: https://github.com/YOUR-USERNAME/local-cluster-standard.git
```

Commit and push:

```bash
git add argocd-apps/laptop-clusters-applicationset.yaml
git commit -m "Update ApplicationSet repository URL"
git push
```

### Step 3: Deploy Bootstrap Application on Homelab

On your homelab cluster, deploy the bootstrap Application that manages the ApplicationSets:

```bash
# Switch to homelab context
kubectl config use-context homelab

# Verify ArgoCD is running
kubectl get pods -n argocd

# Apply the bootstrap Application (only needed once!)
kubectl apply -f argocd-apps/bootstrap-laptop-management.yaml

# Verify the bootstrap app was created
kubectl get app laptop-management-bootstrap -n argocd

# Wait for it to sync (creates the ApplicationSets)
argocd app sync laptop-management-bootstrap

# Verify ApplicationSets were created
kubectl get applicationset -n argocd
# You should see:
# - laptop-clusters-cilium
# - laptop-clusters-monitoring
# - laptop-clusters-ingress-nginx
# - laptop-clusters-cert-manager
```

**What just happened?**
- The bootstrap Application now manages the ApplicationSets
- Any changes you make to `laptop-clusters-applicationset.yaml` in Git will auto-sync
- This is fully GitOps - everything is managed through Git!

### Step 4: Create and Register Laptop Cluster

On your laptop (MacBook or Linux):

#### Option A: Create Cluster with ArgoCD Management

```bash
# Create cluster in ArgoCD-managed mode
./create-cluster.sh --skip-cilium --register-with-homelab homelab my-laptop-cluster

# This will:
# 1. Create the Talos cluster without Cilium
# 2. Automatically register with homelab ArgoCD
# 3. ArgoCD will deploy all core apps
```

#### Option B: Create Standalone, Then Register Later

```bash
# Create standalone cluster (with Cilium)
./create-cluster.sh my-laptop-cluster

# Later, register with homelab ArgoCD
./scripts/register-cluster.sh my-laptop-cluster homelab
```

### Step 5: Verify Core Applications Deployment

After registration, ArgoCD will automatically deploy core applications:

```bash
# Watch ArgoCD sync status (on homelab)
kubectl config use-context homelab
argocd app list

# Or via ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Visit https://localhost:8080

# Check applications on laptop cluster
kubectl config use-context admin@my-laptop-cluster

# Wait for Cilium (deploys first, sync-wave -1)
kubectl wait --for=condition=ready pod -l k8s-app=cilium -n kube-system --timeout=300s

# Check monitoring stack
kubectl get pods -n monitoring

# Check ingress
kubectl get pods -n ingress-nginx

# Check cert-manager
kubectl get pods -n cert-manager
```

## Core Applications Managed by ArgoCD

The following applications are automatically deployed to all laptop clusters with label `environment=laptop`:

### 1. **Cilium** (Sync Wave: -1)
- **Namespace**: kube-system
- **Purpose**: CNI and network policies
- **Features**: Hubble for observability, kube-proxy replacement

### 2. **Kube-Prometheus-Stack** (Sync Wave: 1)
- **Namespace**: monitoring
- **Purpose**: Metrics collection and visualization
- **Components**: Prometheus, Grafana, Alertmanager
- **Access**: Port-forward Grafana on port 3000

### 3. **Ingress-Nginx** (Sync Wave: 0)
- **Namespace**: ingress-nginx
- **Purpose**: HTTP/HTTPS ingress controller
- **Type**: NodePort (for local Docker clusters)

### 4. **Cert-Manager** (Sync Wave: 0)
- **Namespace**: cert-manager
- **Purpose**: Certificate management
- **Features**: Self-signed and Let's Encrypt certs

## Working with Testing Applications

Testing applications are NOT managed by ArgoCD and can be deployed/removed freely:

### Deploy Testing Application

```bash
# Switch to laptop cluster context
kubectl config use-context admin@my-laptop-cluster

# Deploy your test app
kubectl apply -f test-apps/hello-world/deployment.yaml

# Or use helm
helm install my-test-app ./my-chart

# Or use kubectl run
kubectl run test-nginx --image=nginx
```

### Verify Testing App

```bash
kubectl get pods -n hello-world
kubectl port-forward -n hello-world svc/hello-world 8080:80
```

### Remove Testing App

```bash
kubectl delete -f test-apps/hello-world/deployment.yaml
# Or
kubectl delete namespace hello-world
```

## Hybrid Workflow: Core vs Testing Apps

### Core Applications (ArgoCD-Managed)
✓ Always in sync across all laptop clusters
✓ Managed in Git repository
✓ Deployed automatically when cluster is registered
✓ Self-heal if manually modified
✓ Cannot be deleted manually (ArgoCD will recreate)

**Examples**: Cilium, Prometheus, Grafana, Ingress, Cert-Manager, Backstage

### Testing Applications (Manually Deployed)
✓ Independent per laptop cluster
✓ Not in Git (or in separate directories)
✓ Deployed via kubectl/helm manually
✓ Can be modified/deleted freely
✓ Won't be synced to other clusters

**Examples**: Feature branches, experimental apps, temporary workloads

## Common Operations

### Add New Core Application

1. Create application manifests in `argocd-apps/core-apps/new-app/`
2. Add to ApplicationSet in `laptop-clusters-applicationset.yaml`
3. Commit and push to Git
4. ArgoCD automatically deploys to all registered clusters

### Remove Laptop Cluster from Management

```bash
# On homelab cluster
kubectl config use-context homelab

# List clusters
argocd cluster list

# Remove cluster
argocd cluster rm https://cluster-api-url

# This stops ArgoCD management but doesn't destroy the cluster
```

### Destroy Laptop Cluster

```bash
# On laptop
talosctl cluster destroy --name my-laptop-cluster

# Optionally remove from ArgoCD (if not already done)
kubectl config use-context homelab
argocd cluster rm admin@my-laptop-cluster
```

### Check Sync Status

```bash
# On homelab cluster
argocd app list | grep my-laptop-cluster

# Get details for specific app
argocd app get my-laptop-cluster-cilium

# Force sync
argocd app sync my-laptop-cluster-cilium
```

### Access Monitoring Stack

```bash
# On laptop cluster
kubectl config use-context admin@my-laptop-cluster

# Port-forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Visit http://localhost:3000
# Username: admin
# Password: admin (or configured value)
```

## Troubleshooting

### Cluster Registration Fails

**Problem**: `argocd cluster add` fails
**Solution**:
1. Verify VPN/Tailscale connection
2. Check laptop cluster API is reachable from homelab
3. Verify kubectl context exists: `kubectl config get-contexts`

### Applications Not Syncing

**Problem**: Applications stuck in "OutOfSync"
**Solution**:
```bash
# Check application details
argocd app get my-laptop-cluster-cilium

# Check sync status
argocd app sync my-laptop-cluster-cilium --dry-run

# Force sync
argocd app sync my-laptop-cluster-cilium --force
```

### Cilium Not Installing

**Problem**: Nodes remain NotReady
**Solution**:
1. Check Cilium sync wave is -1 (deploys first)
2. Verify Cilium pods are running: `kubectl get pods -n kube-system`
3. Check logs: `kubectl logs -n kube-system -l k8s-app=cilium`

### ArgoCD Cannot Reach Cluster

**Problem**: "Unable to connect to cluster"
**Solution**:
1. Verify VPN/Tailscale is running
2. Test connectivity: `kubectl --context homelab cluster-info`
3. Check service account token is valid
4. Re-register cluster if needed

## Multi-Cluster Best Practices

1. **Consistent Naming**: Use descriptive cluster names (e.g., `macbook-m1`, `thinkpad-linux`)
2. **Cluster Labels**: Add meaningful labels during registration for targeting
3. **Resource Limits**: Keep resource requests low for local clusters
4. **Git Workflow**: Always commit/push before expecting ArgoCD to sync
5. **Testing Isolation**: Use separate namespaces for testing apps to avoid conflicts
6. **Monitoring**: Check ArgoCD UI regularly for sync failures
7. **Cluster Lifecycle**: Long-running clusters (days/weeks) work best with this setup

## Network Configuration

### VPN/Tailscale Setup

Ensure laptop clusters can be reached from homelab:

```bash
# Get cluster API server URL
kubectl config view -o jsonpath='{.clusters[?(@.name=="my-laptop-cluster")].cluster.server}'

# Test connectivity from homelab
curl -k https://cluster-api-url
```

If using Tailscale, consider using MagicDNS for stable cluster URLs.

## Security Considerations

1. **Service Account Permissions**: The `argocd-manager` service account has cluster-admin. Consider reducing permissions in production.
2. **Secrets Management**: ArgoCD can sync secrets, but consider using sealed-secrets or external-secrets for sensitive data.
3. **Network Isolation**: Laptop clusters should only be reachable from homelab via VPN, not public internet.
4. **Cluster Authentication**: Rotate service account tokens periodically.

## Advanced Configuration

### Cluster-Specific Values

Use ApplicationSet template variables to customize per cluster:

```yaml
helm:
  values: |
    clusterName: {{name}}
    replicas: {{metadata.labels.replicas}}
```

Register cluster with custom labels:

```bash
argocd cluster add my-cluster \
  --label environment=laptop \
  --label replicas=3 \
  --label region=us-west
```

### Progressive Rollout

Deploy to one cluster first, then others:

```yaml
generators:
  - clusters:
      selector:
        matchLabels:
          environment: laptop
          rollout: canary  # Deploy to canary first
```

## Next Steps

1. Push this repository to your Git hosting
2. Update ApplicationSet repository URLs
3. Deploy ApplicationSet to homelab ArgoCD
4. Create and register your first laptop cluster
5. Deploy a test application manually
6. Monitor everything in ArgoCD UI

## Resources

- [ArgoCD Multi-Cluster Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#clusters)
- [ApplicationSets Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [Cluster Decision Resource](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Cluster-Decision-Resource/)
