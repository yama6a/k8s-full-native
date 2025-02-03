# Vault

### Connect to Web UI

```bash
# Print the root token (for login to the webUI)
kubectl get -n sys-vault secret vault-unseal-keys -o jsonpath='{.data.vault-root}' | base64 --decode && echo ""

# Port forward to the vault service
kubectl port-forward -n sys-vault service/vault 8200:8200
```
The Vault Web UI is available at [https://localhost:8200/ui/vault/auth?with=token](https://localhost:8200/ui/vault/auth?with=token)
