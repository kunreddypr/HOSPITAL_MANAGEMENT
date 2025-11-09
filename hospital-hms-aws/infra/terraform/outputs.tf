output "cluster_name" {
  description = "Name of the provisioned EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "API server endpoint for the EKS cluster."
  value       = module.eks.cluster_endpoint
}

output "region" {
  description = "AWS region where the infrastructure was created."
  value       = var.region
}

output "cluster_oidc_issuer" {
  description = "OIDC issuer URL for the EKS cluster."
  value       = module.eks.cluster_oidc_issuer_url
}

output "node_group_role_arn" {
  description = "IAM role ARN for the default managed node group."
  value       = module.eks.eks_managed_node_groups["default"].iam_role_arn
}

output "vpc_id" {
  description = "Identifier of the created VPC."
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Private subnet IDs associated with the cluster."
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "Public subnet IDs for load balancer integration."
  value       = module.vpc.public_subnets
}

output "frontend_repository_url" {
  description = "URL of the frontend ECR repository."
  value       = aws_ecr_repository.frontend.repository_url
}

output "backend_repository_url" {
  description = "URL of the backend ECR repository."
  value       = aws_ecr_repository.backend.repository_url
}

output "kubectl_config" {
  description = "Map containing the data required to configure kubectl/Helm access."
  value = {
    endpoint = data.aws_eks_cluster.this.endpoint
    certificate = data.aws_eks_cluster.this.certificate_authority[0].data
    token       = data.aws_eks_cluster_auth.this.token
  }
  sensitive = true
}
