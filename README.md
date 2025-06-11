# Local Kubernetes Development Environment

This repository contains scripts and configurations for managing local Kubernetes clusters using k3d. The setup includes three environments: development, staging, and production, each with its own resource limits and network configurations.

## System Requirements

### Platform Compatibility
- **macOS Only**: This setup is specifically designed and tested for macOS (both Intel and ARM-based)
- **Bash Version**: Uses macOS default bash v3.2 for maximum compatibility
- **Docker Desktop for Mac**: Required for container runtime

### Hardware Requirements
- At least 4GB RAM (16GB recommended)
- Available ports: 8080-8081, 8443, 9080-9081, 9443, 10080-10081, 10443

### Required Software
- Docker Desktop for Mac
- kubectl
- k3d
- bash (default macOS version 3.2 or later)

## Quick Start

1. Clone this repository:
```bash
git clone <repository-url>
cd local-k8s
```

2. Make scripts executable:
```bash
chmod +x setup-clusters.sh cleanup-clusters.sh apply-configs.sh
```

3. Create clusters:
```bash
./setup-clusters.sh
```

4. Apply configurations:
```bash
./apply-configs.sh
```

## Cluster Information

### Port Mappings

| Environment | HTTP Port | HTTPS Port | ArgoCD Port |
|------------|-----------|------------|-------------|
| Dev        | 8080      | 8443       | 8081        |
| Staging    | 9080      | 9443       | 9081        |
| Production | 10080     | 10443      | 10081       |

### Resource Limits

| Environment | CPU Request/Limit | Memory Request/Limit | Max Pods |
|------------|------------------|---------------------|----------|
| Dev        | 1/2 cores        | 2Gi/4Gi             | 10       |
| Staging    | 2/4 cores        | 4Gi/8Gi             | 15       |
| Production | 4/6 cores        | 8Gi/12Gi            | 25       |

## Common Commands

### Cluster Management

Switch between clusters:
```bash
kubectl config use-context dev      # Switch to dev cluster
kubectl config use-context staging  # Switch to staging cluster
kubectl config use-context prod     # Switch to production cluster
```

View available contexts:
```bash
kubectl config get-contexts
```

Check cluster status:
```bash
kubectl get nodes
kubectl get pods -A
```

### Accessing Services

Access a service (replace PORT with the appropriate port number):
```bash
# HTTP services
curl http://localhost:PORT

# HTTPS services
curl -k https://localhost:PORT
```

### Cleanup

Remove all clusters:
```bash
./cleanup-clusters.sh
```

Remove a specific cluster:
```bash
k3d cluster delete <cluster-name>  # dev, staging, or prod
```

## Troubleshooting

### Common Issues

1. **"Connection refused" or Wrong Port Errors**
   
   If you see errors like "connection to the server was refused" or wrong port issues, your kubeconfig might be out of sync. Fix it using either method:

   ```bash
   # Option 1: Regenerate single cluster config
   k3d kubeconfig get dev > $HOME/.k3d/kubeconfig-dev.yaml
   export KUBECONFIG=$HOME/.k3d/kubeconfig-dev.yaml

   # Option 2: Regenerate all configs
   for cluster in dev staging prod; do 
     k3d kubeconfig get $cluster > $HOME/.k3d/kubeconfig-$cluster.yaml
   done
   KUBECONFIG=$(for f in $HOME/.k3d/kubeconfig-*.yaml; do echo -n ":$f"; done | cut -c2-) kubectl config view --flatten > $HOME/.k3d/kubeconfig-all.yaml
   export KUBECONFIG=$HOME/.k3d/kubeconfig-all.yaml
   ```

   This typically happens when:
   - Clusters are restarted
   - Docker Desktop is restarted
   - System is rebooted

2. **Ports Already in Use**
   ```bash
   # Check what's using the port
   lsof -i :<port-number>
   
   # Kill the process if needed
   kill -9 <PID>
   ```

3. **Insufficient Resources**
   
   Symptoms:
   - Pods stuck in "Pending" state
   - Node showing "NotReady"
   
   Solutions:
   ```bash
   # Check node resources
   kubectl describe node
   
   # Check pod events
   kubectl describe pod <pod-name>
   
   # Increase Docker Desktop resources
   # Open Docker Desktop → Settings → Resources
   ```

4. **Context Switching Issues**
   ```bash
   # Reset kubeconfig
   k3d kubeconfig merge <cluster-name> --kubeconfig-switch-context
   
   # Or manually merge configs
   KUBECONFIG=~/.k3d/kubeconfig-dev.yaml:~/.k3d/kubeconfig-staging.yaml:~/.k3d/kubeconfig-prod.yaml kubectl config view --merge --flatten > ~/.kube/config
   ```

5. **Cluster Not Responding**
   ```bash
   # Restart cluster
   k3d cluster stop <cluster-name>
   k3d cluster start <cluster-name>
   
   # If still issues, recreate cluster
   k3d cluster delete <cluster-name>
   ./setup-clusters.sh
   ./apply-configs.sh
   ```

6. **Docker Issues**
   ```bash
   # Reset Docker Desktop
   docker system prune -a  # Warning: removes all unused containers/images
   
   # Check Docker resources
   docker stats
   ```

### Monitoring and Debugging

Check cluster resources:
```bash
# CPU and Memory usage
kubectl top nodes
kubectl top pods -A

# Check events
kubectl get events --sort-by='.lastTimestamp'

# Check logs
kubectl logs -n <namespace> <pod-name>
```

View resource quotas:
```bash
kubectl get resourcequota -A
kubectl describe resourcequota
```

### Best Practices

1. Regularly clean up unused resources:
   ```bash
   kubectl delete pods --field-selector status.phase=Failed -A
   kubectl delete pods --field-selector status.phase=Succeeded -A
   ```

2. Monitor Docker Desktop resources
3. Keep your k3d and kubectl versions up to date
4. Use namespace isolation for different applications
5. Regularly check cluster health:
   ```bash
   kubectl get componentstatuses
   kubectl cluster-info
   ```

## macOS Compatibility Notes

This project is specifically designed to work with macOS's default bash version (3.2) and includes several macOS-specific optimizations:

1. **Bash Compatibility**:
   - Uses bash 3.2 compatible syntax
   - Avoids advanced bash features not available in macOS default shell
   - Properly handles macOS-specific paths and commands

2. **Docker Desktop Integration**:
   - Correctly detects Docker Desktop storage location
   - Handles macOS-specific Docker resource management
   - Uses compatible volume mounts and networking

3. **Resource Management**:
   - Adapts to macOS memory management
   - Handles Docker Desktop resource limits appropriately
   - Uses macOS-compatible disk space checking

## Additional Resources

- [k3d Documentation](https://k3d.io/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Docker Desktop Documentation](https://docs.docker.com/desktop/mac/)

## Support

For issues specific to this setup:
1. Check the troubleshooting section above
2. Review the logs using commands provided
3. Ensure all prerequisites are met
4. Try recreating the specific cluster that's having issues

## License

[Add your license information here] 