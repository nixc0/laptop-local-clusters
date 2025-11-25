# ArgoCD Applications

This directory contains ArgoCD application manifests for both standalone and multi-cluster deployments.

## Directory Structure

```
argocd-apps/
├── README.md                              # This file
├── bootstrap-laptop-management.yaml       # Bootstrap app (apply once to homelab)
├── laptop-clusters-applicationset.yaml    # ApplicationSets (managed by bootstrap app)
├── hello-world-app.yaml                   # Example standalone ArgoCD app
└── core-apps/                             # Core applications for multi-cluster mode
    ├── cilium/                            # Cilium CNI
    ├── monitoring/                        # Prometheus/Grafana stack
    └── dev-tools/                         # Ingress, cert-manager, etc.
```

## Usage

### Multi-Cluster Mode (Homelab ArgoCD)

**Step 1: Apply Bootstrap Application (ONE-TIME)**

The `bootstrap-laptop-management.yaml` is an Application that manages the ApplicationSets. This is the GitOps way!

```bash
kubectl config use-context homelab
kubectl apply -f bootstrap-laptop-management.yaml
```

**Step 2: Bootstrap App Auto-Syncs ApplicationSets**

The bootstrap Application will:
1. Watch the Git repository for changes to `laptop-clusters-applicationset.yaml`
2. Auto-sync any changes to the ApplicationSets
3. The ApplicationSets will then create Applications for each registered laptop cluster

**Step 3: Register Laptop Clusters**

When you register a laptop cluster with label `environment=laptop`, the ApplicationSets automatically create Applications for:
- Cilium (every cluster with `environment=laptop`)
- Monitoring stack (every cluster with `environment=laptop`)
- Ingress-nginx (every cluster with `environment=laptop`)
- Cert-manager (every cluster with `environment=laptop`)

**Why Use Bootstrap Application?**
- Fully GitOps - changes to ApplicationSets are synced automatically
- No manual `kubectl apply` needed after initial setup
- Changes in Git propagate to all clusters automatically
- Follows App-of-Apps pattern (best practice)

### Standalone Mode (Local ArgoCD)

For standalone clusters, you can deploy individual applications:

```bash
# Example: Deploy hello-world app
kubectl apply -f hello-world-app.yaml
```

## Core Applications

### Cilium
- **Namespace**: kube-system
- **Chart**: https://helm.cilium.io/
- **Purpose**: CNI with eBPF networking
- **Sync Wave**: -1 (deploys first)

### Monitoring
- **Namespace**: monitoring
- **Chart**: kube-prometheus-stack
- **Components**: Prometheus, Grafana, Alertmanager
- **Sync Wave**: 1

### Ingress-Nginx
- **Namespace**: ingress-nginx
- **Chart**: ingress-nginx
- **Purpose**: HTTP/HTTPS ingress controller
- **Sync Wave**: 0

### Cert-Manager
- **Namespace**: cert-manager
- **Chart**: cert-manager
- **Purpose**: Certificate management
- **Sync Wave**: 0

## Adding New Core Applications

To add a new core application that should be deployed to all laptop clusters:

1. **Create directory and manifests:**
   ```bash
   mkdir -p core-apps/my-new-app
   ```

2. **Add application YAML or Helm values**

3. **Add to ApplicationSet:**
   Edit `laptop-clusters-applicationset.yaml` and add a new ApplicationSet section following the existing pattern.

4. **Commit and push:**
   ```bash
   git add .
   git commit -m "Add my-new-app to core applications"
   git push
   ```

5. **ArgoCD will automatically sync** to all registered laptop clusters

## Customizing Per Cluster

Use cluster labels to customize application deployment:

```yaml
# In ApplicationSet template
helm:
  values: |
    replicas: {{metadata.labels.replicas}}
    region: {{metadata.labels.region}}
```

Register cluster with custom labels:
```bash
argocd cluster add my-cluster \
  --label environment=laptop \
  --label replicas=3 \
  --label region=us-west
```

## Sync Waves

Applications use sync waves to control deployment order:
- **-1**: Cilium (must deploy first for networking)
- **0**: Infrastructure (ingress, cert-manager)
- **1**: Monitoring and observability
- **2+**: Application layer

## See Also

- [MULTI_CLUSTER_SETUP.md](../MULTI_CLUSTER_SETUP.md) - Complete multi-cluster guide
- [ArgoCD ApplicationSets](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
