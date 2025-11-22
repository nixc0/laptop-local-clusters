# Local Kubernetes Cluster Standardization Plan

## Executive Summary

**Feasibility: HIGHLY FEASIBLE** ✓

Using `talosctl cluster create` to spin up local Docker-based Talos Kubernetes clusters is an excellent choice for standardized testing across macOS and Linux laptops. This approach provides:

- **Cross-platform compatibility**: Works on both macOS (with Docker Desktop) and Linux
- **Consistent environment**: Same Talos Linux base on both platforms
- **Full CNI flexibility**: Native support for Cilium as custom CNI
- **Quick iteration**: Fast cluster creation/destruction
- **Multi-cluster support**: Run multiple isolated clusters simultaneously

---

## Platform Compatibility Assessment

### macOS (Your MacBook)
- ✓ **Supported** via Docker Desktop
- ✓ Talosctl cluster create works natively
- ⚠️ **Limitations**:
  - No VIP (Virtual IP) support due to Docker networking constraints
  - Upgrade/reset APIs unavailable in container mode
  - May need to manually create Docker socket link if encountering daemon connection errors

### Linux (Your Linux Laptop)
- ✓ **Fully Supported** with Docker
- ✓ All features available
- ✓ Better performance (native containers vs. VM-based on macOS)
- ✓ No networking limitations

**Recommendation**: talosctl + Docker is ideal for your use case. The macOS limitations are minor and won't affect typical testing workflows.

---

## Prerequisites

### Both Platforms
1. **Docker**: Version 18.03 or later
   - macOS: Docker Desktop
   - Linux: Docker Engine
2. **talosctl**: Latest version
   - Download from: https://github.com/siderolabs/talos/releases
3. **kubectl**: For cluster interaction
4. **cilium-cli** (optional): For easier Cilium management
5. **argocd-cli** (optional): For ArgoCD management

### Installation Commands

#### macOS
```bash
# Install talosctl
brew install siderolabs/tap/talosctl

# Docker Desktop (manual install from docker.com)
# kubectl
brew install kubectl

# Cilium CLI
brew install cilium-cli

# ArgoCD CLI
brew install argocd
```

#### Linux
```bash
# Install talosctl
curl -sL https://talos.dev/install | sh

# Docker (example for Ubuntu/Debian)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Cilium CLI
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -L --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-amd64.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin
rm cilium-linux-amd64.tar.gz{,.sha256sum}

# ArgoCD CLI
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

---

## Standard Cluster Configuration

### 1. Machine Configuration Patch for Cilium

Create a patch file to disable default CNI (required for Cilium):

**File**: `cilium-patch.yaml`
```yaml
cluster:
  network:
    cni:
      name: none
  proxy:
    disabled: true  # Optional: if you want Cilium to replace kube-proxy
```

### 2. Cluster Creation Script

Create a standardized script for cluster creation:

**File**: `create-cluster.sh`
```bash
#!/bin/bash

CLUSTER_NAME="${1:-talos-local}"
WORKERS="${2:-2}"
CONTROL_PLANES="${3:-1}"

echo "Creating Talos cluster: ${CLUSTER_NAME}"
echo "Control planes: ${CONTROL_PLANES}, Workers: ${WORKERS}"

talosctl cluster create \
  --name "${CLUSTER_NAME}" \
  --workers "${WORKERS}" \
  --controlplanes "${CONTROL_PLANES}" \
  --config-patch @cilium-patch.yaml \
  --wait

echo "Cluster created. Waiting for nodes to be ready..."
kubectl wait --for=condition=ready node --all --timeout=300s || true

echo "Installing Cilium..."
cilium install \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true

echo "Waiting for Cilium to be ready..."
cilium status --wait

echo "Cluster ready!"
kubectl get nodes
```

### 3. Cilium Installation Options

#### Option A: Using Cilium CLI (Recommended)
```bash
# After cluster creation
cilium install \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true
```

#### Option B: Using Helm
```bash
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true
```

#### Option C: Inline Manifests (Advanced)
Generate machine config with embedded Cilium manifests for fully automated deployment.

### 4. ArgoCD Installation

**File**: `install-argocd.sh`
```bash
#!/bin/bash

echo "Installing ArgoCD..."

# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd

# Get initial admin password
echo ""
echo "ArgoCD is ready!"
echo "Initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo ""
echo ""
echo "Access ArgoCD UI:"
echo "kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "Then visit: https://localhost:8080"
```

---

## Standard Workflow

### Creating a New Test Cluster
```bash
# Default cluster (1 control plane, 2 workers)
./create-cluster.sh

# Named cluster with custom sizing
./create-cluster.sh my-test 3 1

# Install ArgoCD
./install-argocd.sh
```

### Managing Multiple Clusters
```bash
# Create second cluster on different CIDR
talosctl cluster create \
  --name cluster2 \
  --cidr 10.6.0.0/24 \
  --config-patch @cilium-patch.yaml

# Switch contexts
kubectl config use-context admin@cluster2
talosctl config context cluster2

# List contexts
kubectl config get-contexts
```

### Verifying Installation
```bash
# Check nodes
kubectl get nodes

# Check Cilium status
cilium status

# Test Cilium connectivity
cilium connectivity test

# Check ArgoCD
kubectl get pods -n argocd
```

### Cleanup
```bash
# Destroy cluster
talosctl cluster destroy --name talos-local

# Destroy all clusters
talosctl cluster destroy --name cluster2
```

---

## Known Issues & Workarounds

### Issue 1: DNS Resolution Problems
**Symptom**: Pods can't resolve DNS
**Solution**: Disable `forwardKubeDNSToHost` in Cilium configuration
```bash
cilium install --set forwardKubeDNSToHost=false
```

### Issue 2: Cluster Appears Hung During Bootstrap
**Cause**: Nodes only become "Ready" after CNI is installed
**Solution**: This is normal; wait for Cilium installation to complete

### Issue 3: PodSecurity Violations (Cilium Connectivity Test)
**Solution**: Add label to test namespace
```bash
kubectl label namespace cilium-test pod-security.kubernetes.io/enforce=privileged
```

### Issue 4: macOS Docker Socket Connection
**Symptom**: talosctl can't connect to Docker daemon
**Solution**: Create socket link
```bash
sudo ln -s ~/Library/Containers/com.docker.docker/Data/docker.sock /var/run/docker.sock
```

---

## Testing Strategy

### Standard Test Scenarios
1. **Basic Cluster Creation**: Verify cluster comes up cleanly
2. **Cilium Networking**: Run `cilium connectivity test`
3. **ArgoCD Deployment**: Deploy a test application via ArgoCD
4. **Cross-Platform**: Verify same commands work on both laptops
5. **Multi-Cluster**: Test running multiple clusters simultaneously

### Validation Checklist
- [ ] Cluster creates successfully
- [ ] All nodes reach Ready state
- [ ] Cilium is healthy (`cilium status`)
- [ ] Pod-to-pod connectivity works
- [ ] External connectivity works
- [ ] ArgoCD is accessible
- [ ] Can deploy applications via ArgoCD

---

## Directory Structure

Recommended repository layout:
```
local-cluster-standard/
├── CLUSTER_PLAN.md              # This file
├── README.md                     # Quick start guide
├── create-cluster.sh             # Cluster creation script
├── install-argocd.sh             # ArgoCD installation script
├── cilium-patch.yaml             # Talos CNI configuration
├── test-apps/                    # Sample applications for testing
│   └── hello-world/
│       └── deployment.yaml
└── argocd-apps/                  # ArgoCD application manifests
    └── test-app.yaml
```

---

## Next Steps

1. **Immediate**:
   - Install prerequisites on both laptops
   - Create the configuration files (cilium-patch.yaml, scripts)
   - Test basic cluster creation on both platforms

2. **Short-term**:
   - Document any platform-specific quirks encountered
   - Create sample test applications
   - Set up ArgoCD application templates

3. **Long-term**:
   - Consider adding monitoring stack (Prometheus/Grafana)
   - Create automated testing pipelines
   - Document common troubleshooting scenarios

---

## Comparison with Alternatives

| Feature | talosctl | minikube | KinD |
|---------|----------|----------|------|
| Multi-platform | ✓ | ✓ | ✓ |
| Multi-node | ✓ | ✓ (limited) | ✓ |
| Production-like | ✓✓✓ | ✓ | ✓✓ |
| Custom CNI | ✓✓✓ | ✓✓ | ✓✓ |
| Speed | ✓✓ | ✓ | ✓✓✓ |
| Immutable OS | ✓✓✓ | ✗ | ✗ |
| API-driven | ✓✓✓ | ✓ | ✓ |

**Why Talos wins for your use case**:
- Immutable, API-driven OS (closest to production)
- Excellent Cilium support
- Consistent behavior across platforms
- Security-focused (no SSH, API-only)
- Great for testing GitOps workflows with ArgoCD

---

## Resources

- [Talos Documentation](https://www.talos.dev/)
- [Talos CLI Reference](https://docs.siderolabs.com/talos/v1.11/reference/cli/)
- [Cilium on Talos](https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Cilium Documentation](https://docs.cilium.io/)
