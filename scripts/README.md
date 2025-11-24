# Scripts

Helper scripts for managing laptop clusters and multi-cluster deployments.

## Available Scripts

### register-cluster.sh

Registers a local laptop cluster with your homelab ArgoCD instance for centralized management.

**Usage:**
```bash
./register-cluster.sh <cluster-name> <homelab-context>
```

**Example:**
```bash
./register-cluster.sh my-macbook homelab
```

**What it does:**
1. Verifies both laptop and homelab contexts exist
2. Creates service account in laptop cluster for ArgoCD
3. Grants cluster-admin permissions to ArgoCD
4. Logs into homelab ArgoCD
5. Registers laptop cluster with label `environment=laptop`
6. Triggers automatic deployment of core applications

**Prerequisites:**
- Laptop cluster must be created first (`../create-cluster.sh`)
- Homelab ArgoCD must be running
- VPN/Tailscale connection between laptop and homelab
- `argocd` CLI installed

**After registration:**
ArgoCD will automatically deploy all core applications defined in the ApplicationSet to your laptop cluster.

## Creating New Scripts

When adding new helper scripts:

1. **Make them executable:**
   ```bash
   chmod +x scripts/my-script.sh
   ```

2. **Add usage documentation** in comments at the top of the script

3. **Update this README** with script description and usage

4. **Follow existing patterns** for error handling and user feedback

## See Also

- [MULTI_CLUSTER_SETUP.md](../MULTI_CLUSTER_SETUP.md) - Complete multi-cluster setup guide
- [../create-cluster.sh](../create-cluster.sh) - Cluster creation script with ArgoCD integration
