# Terraform: Amazon EKS deployment

This module provisions the AWS infrastructure required to run the Hospital HMS workloads on Amazon EKS and optionally deploys the bundled Helm chart. It creates:

- A dedicated VPC with public and private subnets across the provided Availability Zones.
- An Amazon EKS cluster and managed node group with IAM Roles for Service Accounts enabled.
- Amazon ECR repositories for the frontend and backend container images (with lifecycle policies).
- An IRSA-mapped service account plus Helm deployment for the AWS Load Balancer Controller.
- (Optional) A Helm release of the Hospital HMS umbrella chart using images that live in the created ECR repos.

## Usage

```hcl
terraform {
  required_version = ">= 1.5.0"
}

module "hms" {
  source = "./infra/terraform"

  project     = "hospital-hms"
  environment = "prod"
  region      = "eu-west-3"

  # Uncomment to automatically roll out the Helm chart once the
  # frontend/backend images are available in ECR.
  # deploy_helm_release = true
  # helm_values_files   = ["../helm/values-prod.yaml"]
  # frontend_image_tag  = "v1.0.0"
  # backend_image_tag   = "v1.0.0"
}
```

### Initialization and deployment

```bash
cd infra/terraform
terraform init
terraform plan -var="region=eu-west-3" -out plan.tfplan
terraform apply plan.tfplan
```

Terraform outputs the ECR repository URLs for the frontend and backend images. Use these values when tagging the Docker images built from `apps/frontend` and `apps/backend`.

To automatically deploy the workloads after pushing images, enable `deploy_helm_release` and supply one or more values files via `helm_values_files`. The module will reuse the local `infra/helm` chart and inject the image repository URLs and tags you provide.

### Accessing the cluster

To update your local kubeconfig, use the AWS CLI (the commands below assume your AWS credentials are already configured):

```bash
aws eks update-kubeconfig \
  --name $(terraform output -raw cluster_name) \
  --region $(terraform output -raw region)
```

### Destroying the environment

```bash
terraform destroy
```

Ensure any stateful data stores (Aurora, S3, DynamoDB) have been backed up before tearing down the cluster.
