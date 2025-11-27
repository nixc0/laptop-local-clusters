# Migration from Talos to k3d

This document explains why and how we migrated from Talos Linux to k3d for local Kubernetes cluster management.

## Why We Migrated

### The Problem with Talos
After hours of troubleshooting, we encountered persistent issues:
- **Connection errors**: Docker socket issues on macOS with Podman
- **Long setup times**: Hours spent debugging vs. 10 minutes with kind/k3d
- **Bootstrap failures**: Clusters failed to reach Ready state
- **Complexity**: Too many moving parts for local development

### The Solution: k3d
- **Cluster creation**: 15 seconds vs. hours of troubleshooting
- **Reliability**: Works flawlessly with both Docker Desktop and Podman Desktop
- **Simplicity**: Standard Kubernetes, fewer components
- **Proven**: Battle-tested tool designed specifically for local development

## What Changed

### Tools
| Aspect | Before (Talos) | After (k3d) |
|--------|----------------|-------------|
| Cluster tool | `talosctl` | `k3d` |
| Cluster creation time | Minutes to hours | 15 seconds |
| OS | Talos Linux (immutable) | Standard containers |
| Default CNI | None (manual Cilium) | Flannel (k3s default) |
| Context naming | `admin@cluster-name` | `k3d-cluster-name` |
| Container runtime | Docker only | Docker or Podman |

### Commands
| Task | Before | After |
|------|---------|--------|
| Create cluster | `./create-cluster.sh` | `./create-cluster-k3d.sh` |
| List clusters | `talosctl cluster show` | `k3d cluster list` |
| Delete cluster | `talosctl cluster destroy --name X` | `k3d cluster delete X` |
| View nodes | `kubectl get nodes` | `kubectl get nodes` (same) |

### Scripts
- **Primary script**: `create-cluster.sh` → `create-cluster-k3d.sh`
- **Legacy script**: `create-cluster.sh` kept for reference (deprecated)
- **Registration**: Updated `scripts/register-cluster.sh` to support both naming conventions

## What Stayed the Same

✅ **Multi-cluster GitOps architecture** - Still works perfectly
✅ **ArgoCD ApplicationSets** - No changes needed
✅ **Core apps pattern** - Cilium, monitoring, cert-manager
✅ **Hybrid deployment model** - Core apps via ArgoCD, test apps manually
✅ **Repository structure** - All ArgoCD apps and configs intact
✅ **Documentation approach** - Same organization

## Migration Guide

### For New Users
Just use `create-cluster-k3d.sh` - the Talos scripts are deprecated.

```bash
# Create standalone cluster
./create-cluster-k3d.sh my-cluster

# Create ArgoCD-managed cluster
./create-cluster-k3d.sh --skip-cilium --register-with-homelab homelab my-laptop
```

### For Existing Talos Users
1. **Delete old Talos clusters**:
   ```bash
   talosctl cluster destroy --name old-cluster
   ```

2. **Create k3d clusters** with same name:
   ```bash
   ./create-cluster-k3d.sh old-cluster
   ```

3. **Re-register with homelab** (if using multi-cluster):
   ```bash
   ./scripts/register-cluster.sh k3d-old-cluster homelab
   ```

4. **No changes needed** to ArgoCD ApplicationSets - they still work!

## Technical Details

### Podman Desktop Support
The k3d script includes automatic Podman detection:

```bash
detect_container_runtime() {
    # Check if Podman is running
    if command -v podman &> /dev/null && podman machine list 2>/dev/null | grep -q "Currently running"; then
        PODMAN_SOCK=$(find /var/folders -name "podman-machine-default-api.sock" 2>/dev/null | head -1)
        if [ -n "$PODMAN_SOCK" ]; then
            echo "Using Podman Desktop (socket: $PODMAN_SOCK)"
            export DOCKER_HOST="unix://$PODMAN_SOCK"
            return 0
        fi
    fi
    # Falls back to Docker if Podman not found
}
```

### CNI Selection
- **Standalone mode**: Uses Flannel (k3s default)
  - Fast, simple, battle-tested
  - No configuration needed

- **ArgoCD-managed mode**: Uses Cilium (installed by ArgoCD)
  - Advanced networking features
  - Hubble observability
  - Network policies
  - Disabled Flannel via `--flannel-backend=none`

### Context Naming
The registration script was updated to handle both naming conventions:

```bash
# Try k3d naming first
LAPTOP_CONTEXT="${CLUSTER_NAME}"
if ! kubectl config get-contexts "${LAPTOP_CONTEXT}" &> /dev/null; then
    # Fall back to Talos naming
    LAPTOP_CONTEXT="admin@${CLUSTER_NAME}"
fi
```

## Performance Comparison

### Cluster Creation Time
- **Talos**: Minutes to hours (with troubleshooting)
- **k3d**: ~15 seconds

### Resource Usage
- **Talos**: Moderate (full OS in containers)
- **k3d**: Low (k3s is lightweight)

### Reliability
- **Talos on macOS**: Frequent socket issues
- **k3d on macOS**: Works perfectly

## Benefits Realized

1. **Speed**: Create/destroy clusters in seconds
2. **Reliability**: No more Docker socket issues
3. **Flexibility**: Works with Docker or Podman
4. **Simplicity**: Standard Kubernetes, easier to debug
5. **Compatibility**: Better macOS support
6. **Iteration**: Fast experimentation

## What We Learned

- **Right tool for the job**: Talos is excellent for production, but overkill for local dev
- **Simplicity wins**: Fewer moving parts = fewer things to break
- **Speed matters**: 15 seconds vs. hours changes development workflow
- **Architecture > Tool**: Multi-cluster GitOps pattern works with any Kubernetes

## Future Considerations

- **Talos still valid** for production-like testing (immutable OS, API-driven)
- **k3d is primary** for fast local development
- **Both can coexist** in the repository if needed
- **GitOps architecture** is tool-agnostic

## Questions & Answers

**Q: Can I still use Talos?**
A: Yes, `create-cluster.sh` still exists, but it's deprecated and unsupported.

**Q: Will my ArgoCD ApplicationSets still work?**
A: Yes! They target clusters by label (`environment=laptop`), not by tool.

**Q: Do I need to change my core-apps?**
A: No changes needed. Cilium still deploys the same way.

**Q: What about Cilium in standalone mode?**
A: Standalone uses Flannel by default. Cilium is optional via manual installation.

**Q: Can k3d run multiple clusters?**
A: Yes! k3d automatically manages networking, no CIDR conflicts.

## Conclusion

The migration from Talos to k3d was driven by practical needs:
- **Faster iteration** for local development
- **Better reliability** on macOS and with Podman
- **Simpler architecture** with fewer failure points
- **Same capabilities** for multi-cluster GitOps

The k3d approach maintains all the architectural benefits of the original design while dramatically improving the developer experience.

**Result**: 15-second cluster creation vs. hours of troubleshooting. The GitOps architecture remains intact.
