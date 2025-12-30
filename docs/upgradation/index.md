## 🔄 Upgrade Deployment


Before upgrading Kindly take a backup of kubernetes secrets in composio namespace. You can use below command 

## 🔄 Upgrade Deployment


Before upgrading Kindly take a backup of kubernetes secrets in composio namespace. You can use below command 

```bash 
kubectl get secrets -n composio -oyaml > backup-secrets.yaml
```

```bash
helm upgrade --install composio ./composio/ -f values-file.yaml  --timeout 15m  -n composio
```
