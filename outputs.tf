<<<<<<< HEAD
output "initialization_job_name" {
  description = "Name of the Vault initialization job"
  value       = kubernetes_job.vault_init_job.metadata[0].name
=======
output "initialization_status" {
  description = "Status of the Vault initialization"
  value       = "Vault cluster successfully initialized and unsealed"
}

output "vault_service_name" {
  description = "The name of the Vault Kubernetes service"
  value       = local.vault_service_name
>>>>>>> 7893cea (first commit)
}

output "vault_namespace" {
  description = "Kubernetes namespace where Vault is deployed"
  value       = local.vault_namespace
}

<<<<<<< HEAD
output "monitoring_command" {
  description = "Command to check initialization status"
  value       = "kubectl logs -n ${local.vault_namespace} -l job-name=${kubernetes_job.vault_init_job.metadata[0].name} -f"
}

# output "configmap_check_command" {
#   description = "Command to check if initialization completed"
#   value       = "kubectl get configmap -n ${local.vault_namespace} vault-init-completion-marker-${local.deployment_id}"
# }

# output "keys_configmap_name" {
#   description = "Name of the ConfigMap that will contain Vault keys upon successful initialization"
#   value       = "vault-init-results-${local.deployment_id}"
# }
=======
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
>>>>>>> 7893cea (first commit)
