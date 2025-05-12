variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}

variable "deployment_id" {
  description = "Vault deployment ID when successfully completed a terraform apply in TF Cloud"
  type        = string
  default     = "acme-id"
}

variable "vault_deployment_workspace" {
  description = "Name of the Terraform Cloud workspace that deployed Vault"
  type        = string
  default = "terraform-vault-demo"
}

variable "eks_deployment_workspace" {
  description = "Name of the Terraform Cloud workspace that deployed Vault"
  type        = string
  default = "terraform-eks-demo"
}

variable "organization" {
  description = "Terraform Cloud organization name"
  type        = string
  default = "abdi-sbx"
}

variable "keys_backup_bucket" {
  description = "Optional: S3 bucket name to store encrypted Vault keys backup"
  type        = string
  default     = ""
}