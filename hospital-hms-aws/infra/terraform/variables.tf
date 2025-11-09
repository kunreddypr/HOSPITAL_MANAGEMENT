variable "project" {
  description = "Project identifier used as name prefix."
  type        = string
  default     = "hospital-hms"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)."
  type        = string
  default     = "prod"
}

variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-west-3"
}

variable "tags" {
  description = "Additional tags to apply to all resources."
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones to spread subnets across."
  type        = list(string)
  default     = ["eu-west-3a", "eu-west-3b", "eu-west-3c"]
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets (must align with availability_zones)."
  type        = list(string)
  default     = ["10.40.0.0/20", "10.40.16.0/20", "10.40.32.0/20"]
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets (must align with availability_zones)."
  type        = list(string)
  default     = ["10.40.128.0/20", "10.40.144.0/20", "10.40.160.0/20"]
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.30"
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  description = "Minimum number of nodes in the default node group."
  type        = number
  default     = 2
}

variable "node_desired_size" {
  description = "Desired number of nodes in the default node group."
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Maximum number of nodes in the default node group."
  type        = number
  default     = 6
}

variable "cluster_log_retention_days" {
  description = "Retention in days for EKS control plane logs."
  type        = number
  default     = 30
}

variable "frontend_repository_name" {
  description = "Name of the Amazon ECR repository for the frontend image."
  type        = string
  default     = "frontend"
}

variable "backend_repository_name" {
  description = "Name of the Amazon ECR repository for the backend image."
  type        = string
  default     = "backend"
}

variable "deploy_helm_release" {
  description = "When true, deploy the Hospital HMS Helm chart via Terraform."
  type        = bool
  default     = false
}

variable "helm_namespace" {
  description = "Namespace for the Hospital HMS Helm release."
  type        = string
  default     = "hms-prod"
}

variable "helm_values_files" {
  description = "Optional list of values files to apply to the Hospital HMS Helm release."
  type        = list(string)
  default     = []
}

variable "frontend_image_tag" {
  description = "Container image tag for the frontend deployment."
  type        = string
  default     = "latest"
}

variable "backend_image_tag" {
  description = "Container image tag for the backend deployment."
  type        = string
  default     = "latest"
}

variable "frontend_image_repository_override" {
  description = "Override for the frontend container image repository. Leave blank to use the created ECR repository."
  type        = string
  default     = ""
}

variable "backend_image_repository_override" {
  description = "Override for the backend container image repository. Leave blank to use the created ECR repository."
  type        = string
  default     = ""
}

variable "aws_load_balancer_controller_version" {
  description = "Helm chart version for the AWS Load Balancer Controller."
  type        = string
  default     = "1.8.1"
}
