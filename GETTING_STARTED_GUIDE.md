# Getting Started Guide

This guide walks you through the complete implementation process from the very beginning.

## Prerequisites Check

Before starting, make sure you have:

### On Your Homelab Cluster:
```bash
# Verify ArgoCD is installed and running
kubectl --context homelab get pods -n argocd

# Expected output: argocd-server, argocd-repo-server, argocd-application-controller pods running
```

### On Your Laptop:
```bash
# Verify tools are installed
docker --version          # Docker for running Talos clusters
talosctl version          # Talos CLI
kubectl version --client  # Kubernetes CLI
argocd version --client   # ArgoCD CLI (optional but helpful)

# Verify VPN/Tailscale connection to homelab
ping <homelab-ip>  # Make sure you can reach your homelab
```

---

## Step 1: Bootstrap Your Homelab ArgoCD (ONE-TIME SETUP)

This is where the magic starts. You'll apply the bootstrap Application to your homelab, which will manage everything else.

```bash
# Navigate to the repo
cd /Users/curtisnix/Projects/01-homelab/laptop-local-clusters

# Switch to homelab cluster context
kubectl config use-context homelab

# Verify you're on the right cluster
kubectl config current-context

# Apply the bootstrap Application
kubectl apply -f argocd-apps/bootstrap-laptop-management.yaml
```

**What just happened?**
- You created an ArgoCD `Application` resource named `laptop-management-bootstrap`
- This Application is watching your GitHub repo: `https://github.com/nixc0/laptop-local-clusters.git`
- It's specifically watching the `argocd-apps/laptop-clusters-applicationset.yaml` file

---

## Step 2: Verify Bootstrap Application Synced

```bash
# Check if the bootstrap app was created
kubectl get app laptop-management-bootstrap -n argocd

# Expected output:
# NAME                           SYNC STATUS   HEALTH STATUS
# laptop-management-bootstrap    Synced        Healthy

# Force sync if needed
argocd app sync laptop-management-bootstrap

# Or via kubectl
kubectl get app laptop-management-bootstrap -n argocd -o yaml
```

**Watch the sync happen:**
```bash
# In one terminal, watch ApplicationSets being created
watch kubectl get applicationset -n argocd

# You should see these appear:
# NAME                              AGE
# laptop-clusters-cilium            10s
# laptop-clusters-monitoring        10s
# laptop-clusters-cert-manager      10s
```

---

## Step 3: Verify ApplicationSets Are Watching

At this point, the ApplicationSets exist but aren't doing anything yet because there are no laptop clusters registered.

```bash
# Check ApplicationSets
kubectl get applicationset -n argocd

# Check for Applications (should be empty for now)
kubectl get applications -n argocd | grep laptop

# No output expected because no clusters are registered yet
```

**What's happening:**
- ApplicationSets are running
- They're looking for clusters with label `environment=laptop`
- When they find one, they'll automatically create Applications

---

## Step 4: Create Your First Laptop Cluster

Now let's create a laptop cluster and register it with your homelab ArgoCD.

### Option A: Automated Registration (Recommended)

The `create-cluster.sh` script can register with homelab automatically:

```bash
# On your laptop, in the repo directory
cd /Users/curtisnix/Projects/01-homelab/laptop-local-clusters

# Create cluster with automatic homelab registration
./create-cluster.sh --skip-cilium --register-with-homelab homelab my-macbook

# Parameters:
# --skip-cilium: Don't install Cilium locally (ArgoCD will do it)
# --register-with-homelab: Auto-register with homelab ArgoCD
# homelab: Name of your homelab kubectl context
# my-macbook: Name for this laptop cluster
```

### Option B: Manual Registration (If You Want More Control)

```bash
# Step 1: Create the cluster without Cilium
./create-cluster.sh --skip-cilium my-macbook

# Step 2: Manually register with homelab
./scripts/register-cluster.sh my-macbook homelab
```

**What `create-cluster.sh` does:**
1. Creates Talos cluster in Docker (1 control plane, 2 workers by default)
2. Applies `cilium-patch.yaml` to disable default CNI
3. Waits for nodes to be ready (they'll stay NotReady until Cilium is installed)
4. If `--register-with-homelab`: Runs the registration script

**What `register-cluster.sh` does:**
1. Creates a service account in the laptop cluster: `argocd-manager`
2. Grants it `cluster-admin` permissions
3. Extracts the service account token
4. Adds the cluster to homelab ArgoCD with label `environment=laptop`

---

## Step 5: Watch The Magic Happen

Once the cluster is registered, the ApplicationSets detect it and start deploying!

### On Homelab (watch Applications being created):

```bash
# Switch to homelab context
kubectl config use-context homelab

# Watch Applications being created
watch kubectl get applications -n argocd

# You should see:
# NAME                    SYNC STATUS   HEALTH STATUS
# my-macbook-cilium       Syncing       Progressing
# my-macbook-monitoring   OutOfSync     Missing (waiting for Cilium)
# my-macbook-cert-manager OutOfSync     Missing (waiting for Cilium)
```

### On Laptop Cluster (watch pods being deployed):

```bash
# Switch to laptop cluster context
kubectl config use-context admin@my-macbook

# Watch Cilium deploy first (sync-wave -1)
watch kubectl get pods -n kube-system

# Expected progression:
# 1. Cilium operator pods start
# 2. Cilium agent pods start on each node
# 3. Nodes transition from NotReady -> Ready
# 4. Other apps start deploying

# Once Cilium is ready, watch other apps
watch kubectl get pods -A

# Check nodes are ready
kubectl get nodes
```

---

## Step 6: Verify Complete Deployment

After a few minutes, everything should be deployed:

```bash
# On laptop cluster
kubectl config use-context admin@my-macbook

# Check Cilium (should be running)
kubectl get pods -n kube-system -l k8s-app=cilium
kubectl get ingressclass  # Should show "cilium" as default

# Check cert-manager (should be running)
kubectl get pods -n cert-manager

# Check monitoring (should be running)
kubectl get pods -n monitoring

# Check all applications are healthy
kubectl get pods -A
```

### On Homelab (verify ArgoCD shows everything healthy):

```bash
kubectl config use-context homelab

# Check all applications
argocd app list | grep my-macbook

# Or
kubectl get applications -n argocd -o wide

# Expected:
# my-macbook-cilium          Synced   Healthy
# my-macbook-cert-manager    Synced   Healthy
# my-macbook-monitoring      Synced   Healthy
```

---

## Step 7: Test Cilium Ingress Controller

Create a simple test app to verify Cilium ingress works:

```bash
# On laptop cluster
kubectl config use-context admin@my-macbook

# Deploy test app
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80

# Create Ingress using Cilium
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
spec:
  ingressClassName: cilium
  rules:
    - host: nginx.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
EOF

# Check ingress
kubectl get ingress

# Test it (add to /etc/hosts first)
# echo "127.0.0.1 nginx.local" | sudo tee -a /etc/hosts
# curl http://nginx.local
```

---

## Visual Timeline of What Happens:

```
┌─────────────────────────────────────────────────────────┐
│ T+0min: You apply bootstrap-laptop-management.yaml     │
│ └─> ArgoCD creates Application                         │
│     └─> Application syncs ApplicationSets from Git     │
│         └─> ApplicationSets created but idle (waiting) │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│ T+2min: You create laptop cluster                       │
│ └─> Talos cluster created in Docker                    │
│     └─> Nodes are NotReady (no CNI)                    │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│ T+3min: Cluster registered with homelab                │
│ └─> argocd-manager service account created             │
│     └─> Cluster added to ArgoCD with label             │
│         environment=laptop                              │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│ T+3min: ApplicationSets detect new cluster!            │
│ └─> Create my-macbook-cilium (sync-wave -1)           │
│ └─> Create my-macbook-cert-manager (sync-wave 0)      │
│ └─> Create my-macbook-monitoring (sync-wave 1)        │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│ T+4min: Cilium deploys (sync-wave -1 goes first)      │
│ └─> Cilium operator starts                             │
│     └─> Cilium agents start on each node              │
│         └─> CNI configured                             │
│             └─> Nodes become Ready!                    │
│                 └─> Ingress Controller enabled         │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│ T+5min: Infrastructure deploys (sync-wave 0)           │
│ └─> cert-manager starts deploying                      │
│     └─> CRDs installed                                 │
│         └─> cert-manager pods running                  │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│ T+7min: Monitoring deploys (sync-wave 1)               │
│ └─> Prometheus operator starts                         │
│     └─> Prometheus, Grafana, Alertmanager deploy      │
│         └─> All pods running                           │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│ T+10min: Everything is healthy! ✅                      │
│ - Cilium: Running with ingress controller              │
│ - Cert-manager: Running                                │
│ - Monitoring: Running                                  │
│ - Cluster: Fully operational                           │
└─────────────────────────────────────────────────────────┘
```

---

## Common Issues & Troubleshooting:

### Issue 1: Bootstrap app won't sync
```bash
# Check app details
argocd app get laptop-management-bootstrap

# Common fixes:
# - Verify GitHub repo URL is correct
# - Check ArgoCD has network access to GitHub
# - Force sync: argocd app sync laptop-management-bootstrap
```

### Issue 2: ApplicationSets created but no Applications
```bash
# Check if cluster was registered
argocd cluster list

# Verify label
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster -o yaml | grep environment

# If missing, re-run registration
./scripts/register-cluster.sh my-macbook homelab
```

### Issue 3: Nodes stay NotReady
```bash
# This is normal until Cilium deploys!
# Check Cilium application status on homelab
kubectl --context homelab get app my-macbook-cilium -n argocd

# Force sync if needed
argocd app sync my-macbook-cilium

# Watch Cilium pods
kubectl --context admin@my-macbook get pods -n kube-system -w
```

---

## Next Steps After First Cluster Works:

1. **Add more laptop clusters** - Just repeat Step 4 with different names
2. **Deploy test applications** - Use `kubectl apply` on laptop clusters
3. **Modify core apps** - Edit `laptop-clusters-applicationset.yaml`, commit, push (auto-syncs!)
4. **Monitor via ArgoCD UI** - Port-forward ArgoCD on homelab and watch in browser

---

## Summary: The Complete Flow

1. **Bootstrap** (once): Apply `bootstrap-laptop-management.yaml` to homelab
2. **ApplicationSets created**: Automatically from Git
3. **Create laptop cluster**: Run `create-cluster.sh` with registration
4. **ApplicationSets detect cluster**: Create Applications automatically
5. **Apps deploy**: Cilium → cert-manager → monitoring (via sync waves)
6. **Cluster ready**: Deploy your test apps manually

The beauty of this setup is that after the initial bootstrap, everything is GitOps - just commit and push changes to `laptop-clusters-applicationset.yaml` and they'll automatically sync to all registered clusters!

---

## Additional Resources

- [README.md](README.md) - Quick start and overview
- [MULTI_CLUSTER_SETUP.md](MULTI_CLUSTER_SETUP.md) - Detailed multi-cluster setup
- [CLUSTER_PLAN.md](CLUSTER_PLAN.md) - Architecture and design decisions
- [argocd-apps/README.md](argocd-apps/README.md) - ApplicationSet documentation
