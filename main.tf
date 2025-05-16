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

# Create a ConfigMap with the initialization script
resource "kubernetes_config_map" "vault_init_script" {
  metadata {
    name      = "vault-init-script-${local.deployment_id}"
    namespace = local.vault_namespace
  }

  data = {
    "initialize-vault.sh" = file("${path.module}/scripts/initialize-vault.sh")
  }
}

# Create a ServiceAccount for initialization
resource "kubernetes_service_account" "vault_init_sa" {
  metadata {
    name      = "vault-init-sa-${local.deployment_id}"
    namespace = local.vault_namespace
  }
}

# Create a Role for the ServiceAccount
resource "kubernetes_role" "vault_init_role" {
  metadata {
    name      = "vault-init-role-${local.deployment_id}"
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
}

# Bind the Role to the ServiceAccount
resource "kubernetes_role_binding" "vault_init_rb" {
  metadata {
    name      = "vault-init-rb-${local.deployment_id}"
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

# Create the Pod resource directly with Terraform
resource "kubernetes_pod" "vault_init_pod" {
  metadata {
    name      = "vault-init-pod-${local.deployment_id}"
    namespace = local.vault_namespace
  }

  spec {
    service_account_name = kubernetes_service_account.vault_init_sa.metadata[0].name
    
    container {
      name    = "vault-init"
      image   = "bitnami/kubectl:latest"
      
      command = ["/bin/bash", "-c"]
      args = [<<-EOT
        cp /scripts/initialize-vault.sh /tmp/
        chmod +x /tmp/initialize-vault.sh
        cd /tmp
        ./initialize-vault.sh 2>&1 | tee /tmp/init.log
        echo "Saving results to ConfigMap..."
        if [ -f "vault-keys.txt" ]; then
          kubectl create configmap vault-init-results-${local.deployment_id} \
            --from-literal=completed=true \
            --from-literal=timestamp="$(date)" \
            --from-file=vault-keys.txt=/tmp/vault-keys.txt \
            --from-file=init-logs=/tmp/init.log \
            -n ${local.vault_namespace}
          echo "Initialization completed successfully!"
        else
          echo "Error: Vault keys file not found"
          exit 1
        fi
      EOT
      ]
      
      volume_mount {
        name       = "scripts-volume"
        mount_path = "/scripts"
      }
    }
    
    volume {
      name = "scripts-volume"
      config_map {
        name = kubernetes_config_map.vault_init_script.metadata[0].name
        default_mode = "0777"
      }
    }
    
    restart_policy = "Never"
  }
  
  timeouts {
    create = "15m"
  }
}

# Create a service to expose the vault UI
resource "kubernetes_service" "vault_ui" {
  metadata {
    name      = "vault-ui-${local.deployment_id}"
    namespace = local.vault_namespace
  }

  spec {
    selector = {
      app = "vault"
    }
    
    port {
      name        = "http"
      port        = 8200
      target_port = 8200
    }
    
    type = "ClusterIP"
  }
}

# Wait a bit to ensure pod has time to start
resource "time_sleep" "wait_for_pod" {
  depends_on = [kubernetes_pod.vault_init_pod]
  create_duration = "30s"
}

# Vault initialization status ConfigMap
resource "kubernetes_config_map" "vault_init_status" {
  metadata {
    name      = "vault-init-status-${local.deployment_id}"
    namespace = local.vault_namespace
  }

  data = {
    completed  = "true"
    timestamp  = timestamp()
    pod_name   = kubernetes_pod.vault_init_pod.metadata[0].name
  }

  depends_on = [
    time_sleep.wait_for_pod
  ]
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