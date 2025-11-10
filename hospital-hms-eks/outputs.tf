output "primary_vpc_ids" {
  description = "IDs for the primary region VPCs"
  value = {
    edge     = aws_vpc.edge.id
    services = aws_vpc.services.id
    data     = aws_vpc.data.id
  }
}

output "dr_vpc_ids" {
  description = "IDs for the DR region VPCs"
  value = {
    edge     = aws_vpc.edge_dr.id
    services = aws_vpc.services_dr.id
    data     = aws_vpc.data_dr.id
  }
}

output "eks_cluster_name" {
  description = "Name of the primary EKS cluster"
  value       = aws_eks_cluster.this.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint URL for the primary EKS cluster"
  value       = aws_eks_cluster.this.endpoint
}

output "aurora_endpoint" {
  description = "Writer endpoint for the primary Aurora cluster"
  value       = aws_rds_cluster.aurora.endpoint
}

output "s3_bucket_name" {
  description = "Primary medical reports S3 bucket"
  value       = aws_s3_bucket.medical_reports.bucket
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito user pool"
  value       = aws_cognito_user_pool.this.id
}

output "cognito_app_client_id" {
  description = "ID of the Cognito user pool app client"
  value       = aws_cognito_user_pool_client.this.id
}

output "github_actions_role_arn" {
  description = "IAM role ARN assumed by GitHub Actions"
  value       = aws_iam_role.github_actions.arn
}

output "primary_alb_name" {
  description = "Name of the primary region ALB"
  value       = aws_lb.primary.name
}

output "primary_alb_dns" {
  description = "DNS name of the primary region ALB"
  value       = aws_lb.primary.dns_name
}

output "dr_alb_dns" {
  description = "DNS name of the disaster recovery ALB"
  value       = aws_lb.dr.dns_name
}
