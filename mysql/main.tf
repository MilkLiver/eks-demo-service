terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}

resource "helm_release" "mysql" {
  name       = "mysql"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "mysql"
  namespace  = var.namespace

  set = [
    # Architecture: replication (primary + secondary)
    {
      name  = "architecture"
      value = "replication"
    },

    # Auth
    {
      name  = "auth.rootPassword"
      value = var.mysql_root_password
    },
    {
      name  = "auth.database"
      value = var.mysql_database
    },
    {
      name  = "auth.username"
      value = var.mysql_username
    },
    {
      name  = "auth.password"
      value = var.mysql_password
    },
    {
      name  = "auth.replicationUser"
      value = "replicator"
    },
    {
      name  = "auth.replicationPassword"
      value = var.mysql_replication_password
    },

    # Primary
    {
      name  = "primary.persistence.enabled"
      value = "true"
    },
    {
      name  = "primary.persistence.storageClass"
      value = var.storage_class_name
    },
    {
      name  = "primary.persistence.size"
      value = var.primary_storage_size
    },

    # Secondary (read replicas)
    {
      name  = "secondary.replicaCount"
      value = var.secondary_replica_count
    },
    {
      name  = "secondary.persistence.enabled"
      value = "true"
    },
    {
      name  = "secondary.persistence.storageClass"
      value = var.storage_class_name
    },
    {
      name  = "secondary.persistence.size"
      value = var.secondary_storage_size
    },
  ]
}
