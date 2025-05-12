output "initialization_job_name" {
  description = "Name of the Vault initialization job"
  value       = kubernetes_job.vault_init_job.metadata[0].name
}

output "vault_namespace" {
  description = "Kubernetes namespace where Vault is deployed"
  value       = local.vault_namespace
}

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