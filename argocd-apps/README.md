# ArgoCD Applications

This directory contains ArgoCD application manifests for both standalone and multi-cluster deployments.

## Directory Structure

```
argocd-apps/
├── README.md                              # This file
├── laptop-clusters-applicationset.yaml    # Multi-cluster deployment (for homelab ArgoCD)
├── hello-world-app.yaml                   # Example standalone ArgoCD app
└── core-apps/                             # Core applications for multi-cluster mode
    ├── cilium/                            # Cilium CNI
    ├── monitoring/                        # Prometheus/Grafana stack
    └── dev-tools/                         # Ingress, cert-manager, etc.
```

## Usage

### Multi-Cluster Mode (Homelab ArgoCD)

The `laptop-clusters-applicationset.yaml` uses an ApplicationSet to deploy core applications to all laptop clusters labeled with `environment=laptop`.

**Deploy to homelab ArgoCD:**
```bash
kubectl config use-context homelab
kubectl apply -f laptop-clusters-applicationset.yaml
```

The ApplicationSet will automatically create Applications for:
- Cilium (every cluster with `environment=laptop`)
- Monitoring stack (every cluster with `environment=laptop`)
- Ingress-nginx (every cluster with `environment=laptop`)
- Cert-manager (every cluster with `environment=laptop`)

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
