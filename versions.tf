terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws" 
      version = ">= 5.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }
  }
}