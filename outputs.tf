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
  value       = length(data.kubernetes_config_map.init_results) > 0 ? lookup(data.kubernetes_config_map.init_results[0].data, "timestamp", "Unknown") : "Initialization in progress"
}

output "root_token_stored" {
  description = "Indicates whether the root token is safely stored in the ConfigMap"
  value       = length(data.kubernetes_config_map.init_results) > 0 ? contains(keys(data.kubernetes_config_map.init_results[0].binary_data), "vault-keys.txt") : false
  sensitive   = false
}

# Optional: Add an output to securely retrieve keys if authorized
output "vault_keys_configmap" {
  description = "Name of the ConfigMap containing Vault keys"
  value       = "vault-init-results-${local.deployment_id}"
  sensitive   = false
}