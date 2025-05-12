output "vault_init_pod" {
  description = "Name of the Vault initialization pod"
  value       = kubernetes_pod.vault_init_pod.metadata[0].name
}

output "vault_namespace" {
  description = "Kubernetes namespace where Vault is deployed"
  value       = local.vault_namespace
}

output "vault_service_name" {
  description = "Name of the Vault Kubernetes service"
  value       = local.vault_service_name
}

output "initialization_status" {
  description = "Status of the Vault initialization process"
  value       = "Vault initialization process has been started. Check pod logs with: kubectl logs ${kubernetes_pod.vault_init_pod.metadata[0].name} -n ${local.vault_namespace}"
}

output "initialization_timestamp" {
  description = "Timestamp when the initialization process was started"
  value       = kubernetes_config_map.vault_init_status.data.timestamp
}

output "vault_access_instructions" {
  description = "Instructions to access the Vault UI"
  value       = "To access Vault UI, run: kubectl port-forward svc/vault -n ${local.vault_namespace} 8200:8200 and open http://localhost:8200"
}