# Core Applications

Core infrastructure applications that are deployed to all laptop clusters via ArgoCD ApplicationSet.

## Overview

These applications provide the foundational infrastructure for laptop testing clusters:
- **Networking**: Cilium CNI
- **Observability**: Prometheus, Grafana, Alertmanager
- **Ingress**: Nginx ingress controller
- **Certificates**: Cert-manager for TLS

All applications in this directory are automatically deployed to laptop clusters registered with your homelab ArgoCD when they have the label `environment=laptop`.

## Applications

### cilium/
Cilium CNI with eBPF-based networking and network policies.

**Files:**
- `application.yaml` - ArgoCD Application manifest (for standalone use)
- `values.yaml` - Helm values customized for Talos Linux

**Key Features:**
- Kubernetes IPAM mode
- kube-proxy replacement
- Hubble UI for network observability
- Optimized for Talos Linux

### monitoring/
Complete monitoring stack based on kube-prometheus-stack.

**Files:**
- `application.yaml` - ArgoCD Application manifest
- `values.yaml` - Helm values with reduced resource requirements

**Components:**
- Prometheus: Metrics collection and storage
- Grafana: Visualization dashboards
- Alertmanager: Alert routing and management

**Access Grafana:**
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Username: admin, Password: admin
```

### dev-tools/
Development and infrastructure tools.

**Files:**
- `ingress-nginx.yaml` - Ingress controller application
- `ingress-nginx-values.yaml` - Customized for local Docker clusters (NodePort)
- `cert-manager.yaml` - Certificate management application

**Included Tools:**
- **Ingress-Nginx**: HTTP/HTTPS traffic routing
- **Cert-Manager**: Automated certificate management

## Adding a New Core Application

To add a new application that should be deployed to all laptop clusters:

### 1. Create Application Directory
```bash
mkdir -p argocd-apps/core-apps/my-app
```

### 2. Add Application Files

**Option A: Helm-based (recommended)**
```yaml
# application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://charts.example.com/
    chart: my-app
    targetRevision: 1.0.0
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

```yaml
# values.yaml
# Your Helm values here
key: value
```

**Option B: Plain Kubernetes manifests**
Create YAML files with your Kubernetes resources.

### 3. Add to ApplicationSet

Edit `../laptop-clusters-applicationset.yaml` and add a new ApplicationSet:

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: laptop-clusters-my-app
  namespace: argocd
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            environment: laptop
  template:
    metadata:
      name: '{{name}}-my-app'
      labels:
        cluster: '{{name}}'
        environment: laptop
      annotations:
        argocd.argoproj.io/sync-wave: "2"  # Choose appropriate sync wave
    spec:
      project: default
      source:
        repoURL: https://charts.example.com/
        chart: my-app
        targetRevision: 1.0.0
        helm:
          releaseName: my-app
          values: |
            # Your values here
            key: value
      destination:
        server: '{{server}}'
        namespace: my-app
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

### 4. Commit and Push

```bash
git add argocd-apps/core-apps/my-app/
git add argocd-apps/laptop-clusters-applicationset.yaml
git commit -m "Add my-app to core applications"
git push
```

### 5. Verify Deployment

After ArgoCD syncs (automatic or manual):

```bash
# On homelab cluster
argocd app list | grep my-app

# On laptop cluster
kubectl get pods -n my-app
```

## Sync Waves Explained

Sync waves control the order of application deployment:

| Wave | Purpose | Applications |
|------|---------|-------------|
| -1   | Networking | Cilium (must be first) |
| 0    | Infrastructure | Ingress, Cert-Manager |
| 1    | Observability | Monitoring stack |
| 2+   | Applications | Your apps |

Lower numbers deploy first. Use sync waves to handle dependencies.

## Best Practices

1. **Resource Limits**: Keep resource requests/limits low for local testing clusters
2. **NodePort Services**: Use NodePort instead of LoadBalancer for Docker-based clusters
3. **Minimal Replicas**: Default to 1 replica for local clusters
4. **Disable Webhooks**: Admission webhooks can be problematic in local clusters
5. **Storage**: Use dynamic provisioning or emptyDir for local storage

## Customizing for Specific Clusters

Use cluster labels and ApplicationSet templating:

```yaml
helm:
  values: |
    clusterName: {{name}}
    replicas: {{metadata.labels.replicas}}
    storageClass: {{metadata.labels.storageClass}}
```

## Removing a Core Application

1. Remove from `laptop-clusters-applicationset.yaml`
2. Commit and push
3. ArgoCD will automatically prune the application from all clusters

Or manually delete:
```bash
argocd app delete my-cluster-my-app
```

## See Also

- [../../MULTI_CLUSTER_SETUP.md](../../MULTI_CLUSTER_SETUP.md) - Multi-cluster architecture guide
- [ArgoCD Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [ApplicationSet Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
