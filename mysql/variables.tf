variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "namespace" {
  description = "Kubernetes namespace for MySQL"
  type        = string
  default     = "default"
}

variable "mysql_root_password" {
  description = "MySQL root password"
  type        = string
  sensitive   = true
}

variable "mysql_database" {
  description = "Default database to create"
  type        = string
  default     = "appdb"
}

variable "mysql_username" {
  description = "MySQL application user"
  type        = string
  default     = "appuser"
}

variable "mysql_password" {
  description = "MySQL application user password"
  type        = string
  sensitive   = true
}

variable "mysql_replication_password" {
  description = "MySQL replication user password"
  type        = string
  sensitive   = true
}

variable "storage_class_name" {
  description = "StorageClass name for MySQL PVCs"
  type        = string
  default     = "efs-sc"
}

variable "primary_storage_size" {
  description = "Storage size for primary node"
  type        = string
  default     = "10Gi"
}

variable "secondary_replica_count" {
  description = "Number of read replica (secondary) nodes"
  type        = number
  default     = 2
}

variable "secondary_storage_size" {
  description = "Storage size for each secondary node"
  type        = string
  default     = "10Gi"
}
