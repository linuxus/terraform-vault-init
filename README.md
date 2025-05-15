# HashiCorp Vault Initialization and Unsealing on AWS EKS

This Terraform module automates the initialization and unsealing process for a HashiCorp Vault cluster running on AWS EKS. The module handles key management, unsealing, and configuring the Vault cluster in a high-availability setup using Raft consensus.

## Overview

This module performs the following tasks:

1. Creates necessary Kubernetes resources (ServiceAccount, Role, RoleBinding) for Vault initialization
2. Deploys a Kubernetes pod that runs the initialization script
3. Initializes Vault with a 5/3 key threshold (5 key shares, 3 required for unsealing)
4. Unseals the Vault nodes
5. Configures Raft consensus across multiple Vault nodes
6. Stores initialization keys in a ConfigMap (and optionally in an S3 bucket)
7. Exposes the Vault UI through a Kubernetes service

## Prerequisites

* AWS account with appropriate permissions
* EKS cluster running on AWS
* Vault deployed on the EKS cluster
* Terraform Cloud account
* `kubectl` CLI configured to access your EKS cluster

## Terraform Cloud Configuration

This module uses Terraform Cloud for state management and remote operations. It references two other workspaces:

1. A workspace for EKS deployment
2. A workspace for Vault deployment

## Usage

### 1. Set up variables

Create a `terraform.tfvars` file with the following variables:

```hcl
aws_region                = "us-west-2"
deployment_id             = "unique-id"
vault_deployment_workspace = "terraform-vault-demo"
eks_deployment_workspace   = "terraform-eks-demo"
organization              = "your-terraform-cloud-org"
keys_backup_bucket        = "your-backup-bucket-name" # Optional
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Apply the Terraform configuration

```bash
terraform apply
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| aws_region | AWS region to deploy resources | string | `"us-west-2"` | no |
| deployment_id | Unique identifier for this deployment | string | `"ws-i8r9uytsqyeznuer"` | no |
| vault_deployment_workspace | Name of the Terraform Cloud workspace that deployed Vault | string | `"terraform-vault-demo"` | no |
| eks_deployment_workspace | Name of the Terraform Cloud workspace that deployed EKS | string | `"terraform-eks-demo"` | no |
| organization | Terraform Cloud organization name | string | `"abdi-sbx"` | no |
| keys_backup_bucket | S3 bucket name to store encrypted Vault keys backup | string | `"acme-bucket-vault"` | no |

## Outputs

| Name | Description |
|------|-------------|
| vault_init_pod | Name of the Vault initialization pod |
| vault_namespace | Kubernetes namespace where Vault is deployed |
| vault_service_name | Name of the Vault Kubernetes service |
| initialization_status | Status of the Vault initialization process |
| initialization_timestamp | Timestamp when the initialization process was started |
| vault_access_instructions | Instructions to access the Vault UI |

## Vault Initialization Process

The initialization script (`initialize-vault.sh`) performs the following steps:

1. Scales down the Vault StatefulSet to 0 replicas (if not already at 0)
2. Scales up to 1 replica (vault-0)
3. Initializes Vault with 5 key shares and a threshold of 3
4. Unseals vault-0
5. Scales up to 2 replicas and joins vault-1 to the Raft cluster
6. Unseals vault-1
7. Scales up to 3 replicas and joins vault-2 to the Raft cluster
8. Unseals vault-2
9. Verifies the Raft peer configuration

## Accessing Vault

After initialization, you can access the Vault UI by following the instructions provided in the `vault_access_instructions` output:

```bash
kubectl port-forward svc/vault -n <vault-namespace> 8200:8200
```

Then open your browser to: http://localhost:8200

The root token for initial login is stored in the `vault-keys.txt` file which is saved in a ConfigMap named `vault-init-results-<deployment_id>`.

## Security Considerations

* **Important**: The Vault unseal keys and root token are stored in a Kubernetes ConfigMap. In a production environment, you should use more secure storage methods such as:
  - AWS KMS for key encryption
  - AWS Secrets Manager or HashiCorp Vault (separate instance) for secure storage
  - Auto-unseal using cloud provider KMS services

* The optional S3 bucket for key backup uses server-side encryption.

## Vault Auto-Unseal

For production environments, consider implementing auto-unseal using AWS KMS or another KMS provider to avoid storing unseal keys in plain text. This would require modifying the Vault configuration and this initialization module.

## Troubleshooting

To check the status of the initialization process:

```bash
kubectl logs <vault_init_pod> -n <vault_namespace>
```

To view the stored keys and initialization results:

```bash
kubectl get configmap vault-init-results-<deployment_id> -n <vault_namespace> -o yaml
```

## Terraform Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0.0 |
| aws | >= 5.0.0 |
| kubernetes | >= 2.23.0 |
| null | >= 3.2.0 |

## License

This module is licensed under the MIT License.
