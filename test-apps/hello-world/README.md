# Hello World Test Application

Simple test application to verify cluster functionality.

## Manual Deployment

```bash
kubectl apply -f deployment.yaml
```

## Verify Deployment

```bash
# Check pods
kubectl get pods -n hello-world

# Check service
kubectl get svc -n hello-world

# Test the application
kubectl port-forward -n hello-world svc/hello-world 8080:80

# Visit http://localhost:8080
```

## Deploy via ArgoCD

After pushing this repo to GitHub and updating the `repoURL` in `argocd-apps/hello-world-app.yaml`:

```bash
kubectl apply -f argocd-apps/hello-world-app.yaml
```

Then watch it deploy in the ArgoCD UI!

## Cleanup

```bash
kubectl delete -f deployment.yaml
# or
kubectl delete namespace hello-world
```
