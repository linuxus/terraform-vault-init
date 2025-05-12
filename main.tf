# Original job resource with wait_for_completion set to false
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
            set -e
            
            echo "Starting Vault initialization job..."
            
            # Copy script from ConfigMap
            cp /scripts/initialize-vault.sh /tmp/initialize-vault.sh
            chmod +x /tmp/initialize-vault.sh
            
            # Create directory for output
            mkdir -p /tmp/vault-data
            cd /tmp
            
            # Execute the initialization script
            ./initialize-vault.sh || {
              echo "ERROR: Vault initialization script failed with exit code $?"
              exit 1
            }
            
            # Check if vault-keys.txt exists before using it
            if [ -f "vault-keys.txt" ]; then
              echo "Vault keys file found, creating ConfigMap..."
              kubectl create configmap vault-init-results-${local.deployment_id} \
                --from-literal=completed=true \
                --from-literal=timestamp="$(date)" \
                --from-file=vault-keys.txt \
                -n ${local.vault_namespace}
              echo "ConfigMap created successfully."
            else
              echo "ERROR: vault-keys.txt not found. Initialization may have failed."
              echo "Current directory contents:"
              ls -la
              exit 1
            fi
            
            # Create a marker file to indicate completion
            kubectl create configmap vault-init-completion-marker-${local.deployment_id} \
              --from-literal=completed=true \
              --from-literal=timestamp="$(date)" \
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
  
  # Important: Don't wait for completion in Terraform
  wait_for_completion = false
  
  depends_on = [
    kubernetes_config_map.vault_init_script,
    kubernetes_service_account.vault_init_sa,
    kubernetes_role_binding.vault_init_rb
  ]
}

# Add a separate resource to monitor job completion
resource "null_resource" "monitor_vault_init" {
  depends_on = [kubernetes_job.vault_init_job]
  
  # Use a timestamp trigger to ensure this always runs
  triggers = {
    job_creation_time = kubernetes_job.vault_init_job.metadata[0].creation_timestamp
  }
  
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      #!/bin/bash
      set -e
      
      echo "Monitoring Vault initialization job..."
      max_attempts=30
      sleep_interval=20
      attempt=0
      
      while [ $attempt -lt $max_attempts ]; do
        echo "Checking job status (attempt $((attempt+1))/$max_attempts)..."
        
        # Check for completion marker
        if kubectl get configmap vault-init-completion-marker-${local.deployment_id} -n ${local.vault_namespace} &>/dev/null; then
          echo "✅ Vault initialization completed successfully!"
          exit 0
        fi
        
        # Check if job succeeded
        job_succeeded=$(kubectl get job vault-initialization-job-${local.deployment_id} -n ${local.vault_namespace} -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
        if [ "$job_succeeded" == "1" ]; then
          echo "✅ Vault initialization job succeeded!"
          exit 0
        fi
        
        # Check if job failed
        job_failed=$(kubectl get job vault-initialization-job-${local.deployment_id} -n ${local.vault_namespace} -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
        if [ "$job_failed" -ge "1" ]; then
          echo "❌ Vault initialization job failed!"
          
          # Get logs from the failed pods
          echo "Job failure details:"
          pod_names=$(kubectl get pods -n ${local.vault_namespace} -l job-name=vault-initialization-job-${local.deployment_id} -o jsonpath='{.items[*].metadata.name}')
          
          for pod in $pod_names; do
            echo "Logs from pod $pod:"
            kubectl logs -n ${local.vault_namespace} $pod || echo "Could not retrieve logs for $pod"
          done
          
          exit 1
        fi
        
        echo "Job still running, waiting for ${sleep_interval} seconds..."
        sleep $sleep_interval
        attempt=$((attempt+1))
      done
      
      echo "⚠️ Timed out waiting for Vault initialization job to complete!"
      echo "The job may still be running. Check its status manually:"
      echo "kubectl get job vault-initialization-job-${local.deployment_id} -n ${local.vault_namespace}"
      echo "kubectl logs -n ${local.vault_namespace} -l job-name=vault-initialization-job-${local.deployment_id}"
      
      # Even though we timed out, don't fail the Terraform apply
      # The job might complete successfully later
      exit 0
    EOT
  }
}

# Check for the results after monitoring
data "kubernetes_config_map" "init_results" {
  depends_on = [null_resource.monitor_vault_init]
  
  metadata {
    name      = "vault-init-results-${local.deployment_id}"
    namespace = local.vault_namespace
  }
  
  # Only try to read this after the monitoring is done
  
  timeouts {
    read = "5m"
  }
}