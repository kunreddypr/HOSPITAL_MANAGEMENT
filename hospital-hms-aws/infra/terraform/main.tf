provider "aws" {
  region = var.region
}

data "aws_region" "current" {}

data "aws_partition" "current" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.5"

  name = local.name_prefix
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = true
  enable_dns_hostnames   = true
  enable_dns_support     = true
  manage_default_security_group = false

  public_subnet_tags = {
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/${local.name_prefix}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/${local.name_prefix}" = "shared"
  }

  tags = local.default_tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = local.name_prefix
  cluster_version = var.cluster_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = false

  enable_irsa = true

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = var.cluster_log_retention_days

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"
    disk_size      = 50
    instance_types = var.node_instance_types
  }

  eks_managed_node_groups = {
    default = {
      name = "${local.name_prefix}-default"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      capacity_type = "ON_DEMAND"
      subnet_ids    = module.vpc.private_subnets
      tags          = local.default_tags
    }
  }

  tags = local.default_tags
}

resource "aws_ecr_repository" "frontend" {
  name                 = var.frontend_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.default_tags
}

resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Retain only the most recent 20 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 20
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_ecr_repository" "backend" {
  name                 = var.backend_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.default_tags
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Retain only the most recent 20 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 20
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

module "aws_load_balancer_controller_irsa" {
  source  = "terraform-aws-modules/eks/aws//modules/irsa"
  version = "~> 20.8"

  cluster_name = module.eks.cluster_name

  namespace            = "kube-system"
  service_account_name = "aws-load-balancer-controller"

  attach_policy_arns = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSLoadBalancerControllerIAMPolicy"
  ]

  tags = local.default_tags
}

data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.aws_load_balancer_controller_version

  depends_on = [
    module.aws_load_balancer_controller_irsa,
    module.eks
  ]

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "region"
    value = data.aws_region.current.name
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = module.aws_load_balancer_controller_irsa.service_account_name
  }
}

locals {
  frontend_repository_url = var.frontend_image_repository_override != "" ? var.frontend_image_repository_override : aws_ecr_repository.frontend.repository_url
  backend_repository_url  = var.backend_image_repository_override != "" ? var.backend_image_repository_override : aws_ecr_repository.backend.repository_url
}

resource "helm_release" "hospital_hms" {
  count      = var.deploy_helm_release ? 1 : 0
  name       = local.name_prefix
  chart      = "${path.module}/../helm"
  namespace  = var.helm_namespace
  create_namespace = true
  dependency_update = true

  values = [for file_path in var.helm_values_files : file(file_path)]

  set {
    name  = "global.image.registry"
    value = split("/", local.frontend_repository_url)[0]
  }

  set {
    name  = "frontend.image.repository"
    value = local.frontend_repository_url
  }

  set {
    name  = "backend.image.repository"
    value = local.backend_repository_url
  }

  set {
    name  = "frontend.image.tag"
    value = var.frontend_image_tag
  }

  set {
    name  = "backend.image.tag"
    value = var.backend_image_tag
  }

  depends_on = [
    module.eks,
    helm_release.aws_load_balancer_controller
  ]
}
