variable "project_name" {
  description = "Human readable project prefix for tagging and naming"
  type        = string
  default     = "hospital-hms"
}

variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "prod"
}

variable "primary_region" {
  description = "Primary AWS region for active infrastructure"
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "Disaster recovery AWS region"
  type        = string
  default     = "us-west-2"
}

variable "aws_profile" {
  description = "Named AWS CLI profile to use"
  type        = string
  default     = "default"
}

variable "default_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {
    Owner = "platform"
  }
}

variable "edge_vpc_cidr" {
  description = "CIDR block for the primary edge VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "edge_public_subnet_cidrs" {
  description = "Public subnet CIDRs for the edge VPC"
  type        = list(string)
  default     = ["10.10.0.0/24", "10.10.1.0/24"]
}

variable "services_vpc_cidr" {
  description = "CIDR block for the primary services VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "services_private_subnet_cidrs" {
  description = "Private subnet CIDRs hosting EKS worker nodes"
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
}

variable "services_egress_subnet_cidrs" {
  description = "Public egress subnets containing NAT gateways"
  type        = list(string)
  default     = ["10.20.100.0/24", "10.20.101.0/24"]
}

variable "data_vpc_cidr" {
  description = "CIDR block for the primary data VPC"
  type        = string
  default     = "10.30.0.0/16"
}

variable "data_private_subnet_cidrs" {
  description = "Private subnet CIDRs for database and cache workloads"
  type        = list(string)
  default     = ["10.30.0.0/24", "10.30.1.0/24", "10.30.2.0/24"]
}

variable "edge_vpc_cidr_dr" {
  description = "CIDR block for the DR edge VPC"
  type        = string
  default     = "10.110.0.0/16"
}

variable "edge_public_subnet_cidrs_dr" {
  description = "Public subnet CIDRs for the DR edge VPC"
  type        = list(string)
  default     = ["10.110.0.0/24", "10.110.1.0/24"]
}

variable "services_vpc_cidr_dr" {
  description = "CIDR block for the DR services VPC"
  type        = string
  default     = "10.120.0.0/16"
}

variable "services_private_subnet_cidrs_dr" {
  description = "Private subnet CIDRs in the DR services VPC"
  type        = list(string)
  default     = ["10.120.0.0/24", "10.120.1.0/24"]
}

variable "services_egress_subnet_cidrs_dr" {
  description = "Public egress subnet CIDRs in the DR services VPC"
  type        = list(string)
  default     = ["10.120.100.0/24"]
}

variable "data_vpc_cidr_dr" {
  description = "CIDR block for the DR data VPC"
  type        = string
  default     = "10.130.0.0/16"
}

variable "data_private_subnet_cidrs_dr" {
  description = "Private subnet CIDRs for the DR data VPC"
  type        = list(string)
  default     = ["10.130.0.0/24", "10.130.1.0/24"]
}

variable "eks_version" {
  description = "Amazon EKS control plane version"
  type        = string
  default     = "1.29"
}

variable "eks_instance_types" {
  description = "EC2 instance types for the node groups"
  type        = list(string)
  default     = ["m6i.large"]
}

variable "eks_min_size" {
  description = "Minimum number of EKS nodes"
  type        = number
  default     = 3
}

variable "eks_desired_size" {
  description = "Desired number of EKS nodes"
  type        = number
  default     = 3
}

variable "eks_max_size" {
  description = "Maximum number of EKS nodes"
  type        = number
  default     = 6
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "15.3"
}

variable "aurora_instance_class" {
  description = "Instance class for Aurora provisioned instances"
  type        = string
  default     = "db.r7g.large"
}

variable "aurora_master_username" {
  description = "Master username for the Aurora cluster"
  type        = string
  default     = "hmsadmin"
}

variable "aurora_master_password" {
  description = "Master password for the Aurora cluster"
  type        = string
  sensitive   = true
}

variable "aurora_database_name" {
  description = "Default Aurora database name"
  type        = string
  default     = "hospital"
}

variable "aurora_instance_count" {
  description = "Number of Aurora instances in the primary region"
  type        = number
  default     = 2
}

variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.1"
}

variable "redis_node_type" {
  description = "Node type for Redis replication group"
  type        = string
  default     = "cache.r6g.large"
}

variable "redis_node_count" {
  description = "Number of cache nodes in the replication group"
  type        = number
  default     = 2
}

variable "kubernetes_namespace" {
  description = "Namespace used for HMS workloads"
  type        = string
  default     = "hms-prod"
}

variable "image_tag" {
  description = "Docker image tag deployed by Helm"
  type        = string
  default     = "latest"
}

variable "route53_zone_id" {
  description = "Hosted zone ID where the HMS DNS record lives"
  type        = string
}

variable "route53_record_name" {
  description = "Record name for the HMS public endpoint"
  type        = string
}

variable "primary_certificate_arn" {
  description = "ACM certificate ARN used by the primary ALB"
  type        = string
}

variable "dr_certificate_arn" {
  description = "ACM certificate ARN used by the DR ALB"
  type        = string
}

variable "primary_health_check_fqdn" {
  description = "Health check endpoint for the primary Region ALB"
  type        = string
}

variable "dr_health_check_fqdn" {
  description = "Health check endpoint for the DR Region ALB"
  type        = string
}

variable "cognito_callback_urls" {
  description = "Allowed callback URLs for Cognito"
  type        = list(string)
  default     = ["https://app.example.com/callback"]
}

variable "cognito_logout_urls" {
  description = "Allowed logout URLs for Cognito"
  type        = list(string)
  default     = ["https://app.example.com"]
}

variable "github_repository" {
  description = "GitHub repository in the form org/name"
  type        = string
}

variable "github_branch" {
  description = "Branch triggering the deployment pipeline"
  type        = string
  default     = "main"
}
*** End EOF
