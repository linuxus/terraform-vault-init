# Extract required values from the remote state
locals {
  # EKS Cluster Details
  cluster_name          = data.terraform_remote_state.eks_deployment.outputs.cluster_name
  cluster_endpoint      = data.terraform_remote_state.eks_deployment.outputs.cluster_endpoint
  cluster_ca_certificate = data.terraform_remote_state.eks_deployment.outputs.cluster_certificate_authority_data
  region                = var.aws_region
  
  # Vault Details
  vault_namespace       = data.terraform_remote_state.vault_deployment.outputs.vault_namespace
  vault_service_name    = data.terraform_remote_state.vault_deployment.outputs.vault_service_name
  deployment_id         = var.deployment_id
  
  # If the remote state doesn't have these values, provide defaults
  default_namespace = "vault"
  default_service_name = "vault-internal"
  
  # Use the values from remote state if available, otherwise use defaults
  effective_namespace = local.vault_namespace != "" ? local.vault_namespace : local.default_namespace
  effective_service_name = local.vault_service_name != "" ? local.vault_service_name : local.default_service_name
  
  # Configure script location
  script_content = file("${path.module}/scripts/initialize-vault.sh")
}