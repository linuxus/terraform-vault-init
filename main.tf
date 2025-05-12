terraform {
  # Terraform Cloud backend configuration
  backend "remote" {
    organization = "abdi-sbx"
    
    workspaces {
      name = "terraform-vault-init"
    }
  }
}

# Access remote state from the Vault deployment workspace
data "terraform_remote_state" "vault_deployment" {
  backend = "remote"
  
  config = {
    organization = "abdi-sbx"
    workspaces = {
      name = var.vault_deployment_workspace
    }
  }
}
# Access remote state from the Vault deployment workspace
data "terraform_remote_state" "eks_deployment" {
  backend = "remote"
  
  config = {
    organization = "abdi-sbx"
    workspaces = {
      name = var.eks_deployment_workspace
    }
  }
}

# Configure AWS provider using outputs from the Vault deployment workspace
provider "aws" {
  region = local.region
}

# Configure Kubernetes provider
provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.this.token
}

# Get EKS cluster authentication token
data "aws_eks_cluster_auth" "this" {
  name = local.cluster_name
}

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
  
  # Configure script location
  script_content = file("${path.module}/scripts/initialize-vault.sh")
}

# Create a ConfigMap to store the initialization script
resource "kubernetes_config_map" "vault_init_script" {
  metadata {
    name      = "vault-init-script"
    namespace = local.vault_namespace
  }

  data = {
    "initialize-vault.sh" = local.script_content
  }
}

# Create a Kubernetes Job to run the initialization process
resource "kubernetes_job" "vault_init_job" {
  metadata {
    name      = "vault-initialization-job-${local.deployment_id}"
    namespace = local.vault_namespace
  }

  spec {
    template {
      metadata {
        labels = {
          app = "vault-init"
        }
      }

      spec {
        service_account_name = "vault-init-sa"
        
        container {
          name    = "vault-init"
          image   = "bitnami/kubectl:latest"
          command = ["/bin/bash", "-c"]
          
          args = [
            <<-EOT
            # Copy script from ConfigMap
            cp /scripts/initialize-vault.sh /tmp/initialize-vault.sh
            chmod +x /tmp/initialize-vault.sh
            
            # Execute the initialization script
            cd /tmp
            ./initialize-vault.sh
            
            # Save results to a ConfigMap
            INIT_RESULT=$(cat vault-keys.txt)
            kubectl create configmap vault-init-results-${local.deployment_id} \
              --from-literal=completed=true \
              --from-literal=timestamp="$(date)" \
              --from-file=vault-keys.txt \
              -n ${local.vault_namespace}
            EOT
          ]
          
          volume_mount {
            name       = "scripts-volume"
            mount_path = "/scripts"
            read_only  = true
          }
        }
        
        volume {
          name = "scripts-volume"
          config_map {
            name = kubernetes_config_map.vault_init_script.metadata[0].name
          }
        }
        
        restart_policy = "Never"
      }
    }

    backoff_limit = 2
    ttl_seconds_after_finished = 3600  # Clean up after 1 hour
  }
  
  # Ensures the job runs only when triggered, not on every apply
  wait_for_completion = true
  
  depends_on = [
    kubernetes_config_map.vault_init_script,
    kubernetes_service_account.vault_init_sa,
    kubernetes_role_binding.vault_init_rb
  ]
}

# Create a ServiceAccount for the initialization job
resource "kubernetes_service_account" "vault_init_sa" {
  metadata {
    name      = "vault-init-sa"
    namespace = local.vault_namespace
  }
}

# Create a Role for the ServiceAccount with necessary permissions
resource "kubernetes_role" "vault_init_role" {
  metadata {
    name      = "vault-init-role"
    namespace = local.vault_namespace
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "pods/exec", "pods/log", "services", "configmaps", "secrets"]
    verbs      = ["get", "list", "create", "delete", "patch", "update", "watch"]
  }
  
  rule {
    api_groups = ["apps"]
    resources  = ["statefulsets", "statefulsets/scale"]
    verbs      = ["get", "list", "patch", "update", "watch"]
  }
  
  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["get", "list", "watch"]
  }
}

# Bind the Role to the ServiceAccount
resource "kubernetes_role_binding" "vault_init_rb" {
  metadata {
    name      = "vault-init-rb"
    namespace = local.vault_namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.vault_init_role.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vault_init_sa.metadata[0].name
    namespace = local.vault_namespace
  }
}

# Extract initialization results from ConfigMap for outputs
data "kubernetes_config_map" "init_results" {
  metadata {
    name      = "vault-init-results-${local.deployment_id}"
    namespace = local.vault_namespace
  }
  
  depends_on = [kubernetes_job.vault_init_job]
}

# Conditionally create an S3 bucket for encrypted key backup
resource "aws_s3_bucket" "vault_keys_backup" {
  count  = var.keys_backup_bucket != "" ? 1 : 0
  bucket = var.keys_backup_bucket
  
  tags = {
    Name        = "vault-keys-backup"
    Environment = "production"
  }
}

# Enable server-side encryption for the bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "vault_keys_encryption" {
  count  = var.keys_backup_bucket != "" ? 1 : 0
  bucket = aws_s3_bucket.vault_keys_backup[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Backup keys to S3
resource "null_resource" "backup_keys" {
  count = var.keys_backup_bucket != "" ? 1 : 0
  
  triggers = {
    job_completion = kubernetes_job.vault_init_job.id
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      # Extract keys from ConfigMap and encrypt with AWS KMS before upload
      kubectl get configmap vault-init-results-${local.deployment_id} -n ${local.vault_namespace} -o jsonpath='{.data.vault-keys\.txt}' | \
      aws kms encrypt \
        --key-id alias/vault-key-backup \
        --plaintext fileb:///dev/stdin \
        --output text \
        --query CiphertextBlob | \
      aws s3 cp - s3://${var.keys_backup_bucket}/vault-keys-${local.deployment_id}.enc
    EOT
  }
  
  depends_on = [
    kubernetes_job.vault_init_job,
    aws_s3_bucket.vault_keys_backup
  ]
}