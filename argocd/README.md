# ArgoCD Setup and Usage Guide

## Overview
This guide covers the setup and usage of ArgoCD in our multi-cluster Kubernetes environment. ArgoCD is configured to manage applications across dev, staging, and production clusters using the GitOps methodology.

## Quick Start

### Installation
```bash
./argocd/scripts/install-argocd.sh
```

### Accessing ArgoCD UI

1. Start port forwarding:
```bash
./argocd/scripts/port-forward.sh
# or directly using kubectl:
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

2. Access the UI:
   - URL: `https://localhost:8080` (note: must use HTTPS)
   - Username: `admin`
   - To get password:
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
   ```

## Common Issues and Solutions

### 1. Connection Issues

**Symptom**: Seeing errors like:
```
error copying from local connection to remote stream: writeto tcp6 [::1]:8080->[::1]:53726: read: connection reset by peer
```

**Solutions**:
1. Stop existing port forwards:
```bash
pkill -f "kubectl port-forward.*8080:443"
```
2. Restart port forwarding:
```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

### 2. Login Problems

**Symptoms**:
- Password not working
- Unable to log in
- Getting authentication errors

**Solutions**:
1. Verify you're using HTTPS:
   - Correct: `https://localhost:8080`
   - Incorrect: `http://localhost:8080`

2. Get a fresh password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

3. Verify you're in the correct cluster context:
```bash
kubectl config current-context  # Should show k3d-dev
```

### 3. Installation Issues

**Symptoms**:
- Pods in CrashLoopBackOff
- Installation taking too long
- Missing resources

**Solutions**:
1. Check pod status:
```bash
kubectl -n argocd get pods
```

2. Check specific pod logs:
```bash
kubectl -n argocd logs deployment/argocd-server
```

3. If needed, clean reinstall:
```bash
kubectl delete namespace argocd
./argocd/scripts/install-argocd.sh
```

### 4. Browser Security Warning

**Symptom**: Browser shows security warning about certificate

**Solution**: 
- This is expected as we're using a self-signed certificate
- Click "Advanced" and proceed anyway
- The connection is secure within your local environment

## Best Practices

1. **Always verify cluster context**:
```bash
kubectl config current-context
```

2. **Check pod health regularly**:
```bash
kubectl -n argocd get pods
```

3. **Monitor ArgoCD logs**:
```bash
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-server --tail=100
```

4. **Port Management**:
- Keep track of running port forwards
- Use `pkill` to clean up stale forwards
- Verify port availability before starting new forwards

## Maintenance

### Regular Health Checks
1. Verify all pods are running:
```bash
kubectl -n argocd get pods
```

2. Check ingress status:
```bash
kubectl -n argocd get ingress
```

3. Verify service status:
```bash
kubectl -n argocd get svc
```

### Cleanup
To remove ArgoCD completely:
```bash
kubectl delete namespace argocd
```

## Support and Resources

- Official ArgoCD Documentation: https://argo-cd.readthedocs.io/
- Local Support: Check the `scripts` directory for maintenance tools
- Common Commands: See the Quick Start section above

Remember to always check the pod status and logs when troubleshooting, as they often contain valuable debugging information.

## Managing Applications

### Application Structure
- We use the App-of-Apps pattern
- Applications are organized by environment (dev/staging/prod)
- Configuration is managed through Kustomize overlays

### Adding New Applications

1. Create application manifest in `argocd/applications/`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-new-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: <repository-url>
    targetRevision: HEAD
    path: path/to/manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
```

2. Add environment-specific configurations in `argocd/overlays/<environment>/`

3. Update the ApplicationSet in `app-of-apps.yaml` if needed

### Managing Environments

- Dev environment: Used for development and testing
  - Accessible at dev.local
  - Automatic sync enabled
  - Minimal resources

- Staging environment: Pre-production testing
  - Accessible at staging.local
  - Manual sync for validation
  - Production-like configuration

- Production environment: Live environment
  - Accessible at prod.local
  - Manual sync required
  - Full resource allocation

## Troubleshooting

### Common Issues

1. **Application Not Syncing**
   - Check application status: `argocd app get <app-name>`
   - Verify Git repository access
   - Check for validation errors: `argocd app logs <app-name>`

2. **Access Issues**
   - Verify cluster access: `kubectl cluster-info`
   - Check ingress configuration
   - Verify SSL certificates if using HTTPS

3. **Resource Conflicts**
   - Check for namespace conflicts
   - Verify RBAC permissions
   - Review resource quotas

### Debugging Steps

1. Check ArgoCD server logs:
```bash
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-server
```

2. Verify application status:
```bash
kubectl -n argocd get applications
```

3. Check sync status:
```bash
argocd app sync <app-name> --dry-run
```

## Best Practices

1. **Git Repository Management**
   - Use separate branches for environments
   - Implement PR reviews for production changes
   - Keep sensitive data in Kubernetes secrets

2. **Application Configuration**
   - Use Kustomize for environment-specific configs
   - Implement resource limits
   - Configure health checks

3. **Security**
   - Regularly rotate credentials
   - Use RBAC for access control
   - Enable audit logging

## Support and Maintenance

### Regular Maintenance Tasks
1. Update ArgoCD version periodically
2. Rotate certificates and credentials
3. Review and clean up unused applications
4. Monitor resource usage

### Getting Help
- Check ArgoCD documentation: https://argo-cd.readthedocs.io/
- Review application logs
- Contact platform team for support 