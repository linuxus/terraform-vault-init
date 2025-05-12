output "initialization_status" {
  description = "Status of the Vault initialization"
  value       = "Vault cluster successfully initialized and unsealed"
}

output "vault_service_name" {
  description = "The name of the Vault Kubernetes service"
  value       = local.vault_service_name
}

output "vault_namespace" {
  description = "Kubernetes namespace where Vault is deployed"
  value       = local.vault_namespace
}

output "initialization_timestamp" {
  description = "Timestamp when Vault was initialized"
  value       = lookup(data.kubernetes_config_map.init_results.data, "timestamp", "Unknown")
}

output "root_token_stored" {
  description = "Indicates whether the root token is safely stored in the ConfigMap"
  value       = contains(keys(data.kubernetes_config_map.init_results.binary_data), "vault-keys.txt")
  sensitive   = false
}

# Optional: Add an output to securely retrieve keys if authorized
output "vault_keys_configmap" {
  description = "Name of the ConfigMap containing Vault keys"
  value       = "vault-init-results-${local.deployment_id}"
  sensitive   = false
}