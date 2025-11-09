provider "aws" {
  region  = var.primary_region
  profile = var.aws_profile
}

provider "aws" {
  alias   = "dr"
  region  = var.dr_region
  profile = var.aws_profile
}

locals {
  project          = var.project_name
  tags = merge(var.default_tags, {
    "Project"     = var.project_name,
    "Environment" = var.environment
  })
}

data "aws_availability_zones" "primary" {
  state = "available"
}

data "aws_availability_zones" "dr" {
  provider = aws.dr
  state    = "available"
}

############################
# Primary Region Networking
############################
resource "aws_vpc" "edge" {
  cidr_block           = var.edge_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.tags, {
    Name = "${local.project}-edge"
  })
}

resource "aws_vpc" "services" {
  cidr_block           = var.services_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.tags, {
    Name = "${local.project}-services"
  })
}

resource "aws_internet_gateway" "services" {
  vpc_id = aws_vpc.services.id
  tags   = merge(local.tags, { Name = "${local.project}-services-igw" })
}

resource "aws_vpc" "data" {
  cidr_block           = var.data_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.tags, {
    Name = "${local.project}-data"
  })
}

resource "aws_internet_gateway" "edge" {
  vpc_id = aws_vpc.edge.id
  tags   = merge(local.tags, { Name = "${local.project}-edge-igw" })
}

resource "aws_subnet" "edge_public" {
  for_each = { for idx, cidr in var.edge_public_subnet_cidrs : idx => cidr }

  vpc_id                  = aws_vpc.edge.id
  cidr_block              = each.value
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.primary.names[tonumber(each.key) % length(data.aws_availability_zones.primary.names)]
  tags = merge(local.tags, {
    Name = "${local.project}-edge-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_subnet" "services_private" {
  for_each = { for idx, cidr in var.services_private_subnet_cidrs : idx => cidr }

  vpc_id            = aws_vpc.services.id
  cidr_block        = each.value
  availability_zone = data.aws_availability_zones.primary.names[tonumber(each.key) % length(data.aws_availability_zones.primary.names)]
  tags = merge(local.tags, {
    Name = "${local.project}-services-private-${each.key}"
    Tier = "private"
  })
}

resource "aws_subnet" "services_egress" {
  for_each = { for idx, cidr in var.services_egress_subnet_cidrs : idx => cidr }

  vpc_id                  = aws_vpc.services.id
  cidr_block              = each.value
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.primary.names[tonumber(each.key) % length(data.aws_availability_zones.primary.names)]
  tags = merge(local.tags, {
    Name = "${local.project}-services-egress-${each.key}"
    Tier = "egress"
  })
}

resource "aws_subnet" "data_private" {
  for_each = { for idx, cidr in var.data_private_subnet_cidrs : idx => cidr }

  vpc_id            = aws_vpc.data.id
  cidr_block        = each.value
  availability_zone = data.aws_availability_zones.primary.names[tonumber(each.key) % length(data.aws_availability_zones.primary.names)]
  tags = merge(local.tags, {
    Name = "${local.project}-data-private-${each.key}"
    Tier = "private"
  })
}

resource "aws_nat_gateway" "services" {
  for_each = aws_subnet.services_egress

  allocation_id = aws_eip.services[each.key].id
  subnet_id     = each.value.id
  tags          = merge(local.tags, { Name = "${local.project}-services-nat-${each.key}" })
  depends_on    = [aws_internet_gateway.services]
}

resource "aws_eip" "services" {
  for_each = aws_subnet.services_egress

  domain = "vpc"
  tags   = merge(local.tags, { Name = "${local.project}-services-eip-${each.key}" })
}

resource "aws_route_table" "edge_public" {
  vpc_id = aws_vpc.edge.id
  tags   = merge(local.tags, { Name = "${local.project}-edge-public-rt" })
}

resource "aws_route" "edge_internet" {
  route_table_id         = aws_route_table.edge_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.edge.id
}

resource "aws_route" "edge_to_services" {
  route_table_id         = aws_route_table.edge_public.id
  destination_cidr_block = var.services_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
}

resource "aws_route" "edge_to_data" {
  route_table_id         = aws_route_table.edge_public.id
  destination_cidr_block = var.data_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
}

resource "aws_route_table_association" "edge_public" {
  for_each       = aws_subnet.edge_public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.edge_public.id
}

resource "aws_route_table" "services_private" {
  for_each = aws_nat_gateway.services

  vpc_id = aws_vpc.services.id
  tags   = merge(local.tags, { Name = "${local.project}-services-private-rt-${each.key}" })
}

resource "aws_route" "services_private_nat" {
  for_each = aws_route_table.services_private

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.services[each.key].id
}

resource "aws_route" "services_private_to_data" {
  for_each = aws_route_table.services_private

  route_table_id         = each.value.id
  destination_cidr_block = var.data_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
}

resource "aws_route" "services_private_to_edge" {
  for_each = aws_route_table.services_private

  route_table_id         = each.value.id
  destination_cidr_block = var.edge_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
}

resource "aws_route_table_association" "services_private" {
  for_each = aws_subnet.services_private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.services_private[each.key].id
}

resource "aws_route_table" "services_egress" {
  for_each = aws_subnet.services_egress

  vpc_id = aws_vpc.services.id
  tags   = merge(local.tags, { Name = "${local.project}-services-egress-rt-${each.key}" })
}

resource "aws_route" "services_egress_internet" {
  for_each = aws_route_table.services_egress

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.services.id
}

resource "aws_route_table_association" "services_egress" {
  for_each = aws_subnet.services_egress

  subnet_id      = each.value.id
  route_table_id = aws_route_table.services_egress[each.key].id
}

resource "aws_route_table" "data_private" {
  vpc_id = aws_vpc.data.id
  tags   = merge(local.tags, { Name = "${local.project}-data-private-rt" })
}

resource "aws_route_table_association" "data_private" {
  for_each = aws_subnet.data_private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.data_private.id
}

resource "aws_route" "data_to_services" {
  route_table_id         = aws_route_table.data_private.id
  destination_cidr_block = var.services_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
}

resource "aws_route" "data_to_edge" {
  route_table_id         = aws_route_table.data_private.id
  destination_cidr_block = var.edge_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
}

#########################
# Transit Gateway (TGW)
#########################
resource "aws_ec2_transit_gateway" "this" {
  description = "${local.project} hub"
  tags        = merge(local.tags, { Name = "${local.project}-tgw" })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "edge" {
  subnet_ids         = [for s in aws_subnet.edge_public : s.id]
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = aws_vpc.edge.id
  tags               = merge(local.tags, { Name = "${local.project}-edge-attachment" })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "services" {
  subnet_ids         = [for s in aws_subnet.services_private : s.id]
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = aws_vpc.services.id
  tags               = merge(local.tags, { Name = "${local.project}-services-attachment" })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "data" {
  subnet_ids         = [for s in aws_subnet.data_private : s.id]
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = aws_vpc.data.id
  tags               = merge(local.tags, { Name = "${local.project}-data-attachment" })
}

resource "aws_ec2_transit_gateway" "dr" {
  provider    = aws.dr
  description = "${local.project} dr hub"
  tags        = merge(local.tags, { Name = "${local.project}-tgw-dr" })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "edge_dr" {
  provider            = aws.dr
  subnet_ids          = [for s in aws_subnet.edge_dr_public : s.id]
  transit_gateway_id  = aws_ec2_transit_gateway.dr.id
  vpc_id              = aws_vpc.edge_dr.id
  tags                = merge(local.tags, { Name = "${local.project}-edge-dr-attachment" })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "services_dr" {
  provider            = aws.dr
  subnet_ids          = [for s in aws_subnet.services_dr_private : s.id]
  transit_gateway_id  = aws_ec2_transit_gateway.dr.id
  vpc_id              = aws_vpc.services_dr.id
  tags                = merge(local.tags, { Name = "${local.project}-services-dr-attachment" })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "data_dr" {
  provider            = aws.dr
  subnet_ids          = [for s in aws_subnet.data_dr_private : s.id]
  transit_gateway_id  = aws_ec2_transit_gateway.dr.id
  vpc_id              = aws_vpc.data_dr.id
  tags                = merge(local.tags, { Name = "${local.project}-data-dr-attachment" })
}

#########################
# Primary Region Services
#########################
resource "aws_ecr_repository" "microservices" {
  for_each = toset(["frontend", "backend", "telemedicine", "notification"])

  name                 = "${var.project_name}-${each.value}"
  image_tag_mutability = "MUTABLE"
  encryption_configuration {
    encryption_type = "KMS"
  }
  tags = merge(local.tags, { Name = "${local.project}-${each.value}-repo" })
}

resource "aws_security_group" "eks_cluster" {
  name        = "${local.project}-eks-cluster"
  description = "Cluster communication"
  vpc_id      = aws_vpc.services.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    cidr_blocks     = [var.services_vpc_cidr]
    description     = "Cluster API"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.project}-eks-cluster-sg" })
}

resource "aws_security_group" "eks_nodes" {
  name        = "${local.project}-eks-nodes"
  description = "Worker node communication"
  vpc_id      = aws_vpc.services.id

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    self            = true
    description     = "Node to node"
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
    description     = "Cluster API"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.project}-eks-nodes-sg" })
}

resource "aws_iam_role" "eks_cluster" {
  name = "${local.project}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_nodes" {
  name = "${local.project}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "eks_ssm" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_eks_cluster" "this" {
  name     = "${local.project}-eks"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_version

  vpc_config {
    subnet_ids         = concat([for s in aws_subnet.services_private : s.id])
    security_group_ids = [aws_security_group.eks_cluster.id]
    endpoint_public_access = false
    endpoint_private_access = true
  }

  tags = local.tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster
  ]
}

resource "aws_eks_node_group" "primary" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.project}-primary"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = [for s in aws_subnet.services_private : s.id]

  scaling_config {
    desired_size = var.eks_desired_size
    max_size     = var.eks_max_size
    min_size     = var.eks_min_size
  }

  update_config {
    max_unavailable = 1
  }

  capacity_type  = "ON_DEMAND"
  instance_types = var.eks_instance_types

  tags = local.tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.eks_ecr,
    aws_security_group.eks_nodes
  ]
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier      = "${local.project}-aurora"
  engine                  = "aurora-postgresql"
  engine_version          = var.aurora_engine_version
  master_username         = var.aurora_master_username
  master_password         = var.aurora_master_password
  database_name           = var.aurora_database_name
  backup_retention_period = 7
  preferred_backup_window = "02:00-03:00"
  storage_encrypted       = true
  vpc_security_group_ids  = [aws_security_group.rds.id]
  db_subnet_group_name    = aws_db_subnet_group.aurora.name

  tags = merge(local.tags, { Name = "${local.project}-aurora" })
}

resource "aws_rds_cluster_instance" "aurora_instances" {
  count              = var.aurora_instance_count
  identifier         = "${local.project}-aurora-${count.index}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.aurora_instance_class
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
  publicly_accessible = false
  db_subnet_group_name = aws_db_subnet_group.aurora.name
  tags = merge(local.tags, { Name = "${local.project}-aurora-${count.index}" })
}

resource "aws_security_group" "rds" {
  name   = "${local.project}-aurora-sg"
  vpc_id = aws_vpc.data.id

  ingress {
    description      = "EKS to Aurora"
    from_port        = 5432
    to_port          = 5432
    protocol         = "tcp"
    cidr_blocks      = [var.services_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.project}-aurora-sg" })
}

resource "aws_db_subnet_group" "aurora" {
  name       = "${local.project}-aurora-subnets"
  subnet_ids = [for s in aws_subnet.data_private : s.id]
  tags       = merge(local.tags, { Name = "${local.project}-aurora-subnets" })
}

resource "aws_dynamodb_table" "audit" {
  name           = "${local.project}-audit"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "pk"
  range_key      = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  tags = merge(local.tags, { Name = "${local.project}-audit" })
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${local.project}-redis-subnets"
  subnet_ids = [for s in aws_subnet.data_private : s.id]
}

resource "aws_security_group" "redis" {
  name   = "${local.project}-redis-sg"
  vpc_id = aws_vpc.data.id

  ingress {
    description     = "EKS to Redis"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    cidr_blocks     = [var.services_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.project}-redis-sg" })
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id          = "${local.project}-redis"
  description                   = "Redis cache for HMS"
  engine                        = "redis"
  engine_version                = var.redis_engine_version
  node_type                     = var.redis_node_type
  number_cache_clusters         = var.redis_node_count
  automatic_failover_enabled    = true
  multi_az_enabled              = true
  security_group_ids            = [aws_security_group.redis.id]
  subnet_group_name             = aws_elasticache_subnet_group.redis.name
  transit_encryption_enabled    = true
  at_rest_encryption_enabled    = true
  tags                          = merge(local.tags, { Name = "${local.project}-redis" })
}

resource "aws_s3_bucket" "medical_reports" {
  bucket = "${var.project_name}-${var.environment}-medical-reports"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
      }
    }
  }

  tags = merge(local.tags, { Name = "${local.project}-reports" })
}

resource "aws_s3_bucket" "medical_reports_dr" {
  provider = aws.dr
  bucket   = "${var.project_name}-${var.environment}-medical-reports-dr"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
      }
    }
  }

  tags = merge(local.tags, { Name = "${local.project}-reports-dr" })
}

resource "aws_s3_bucket_replication_configuration" "reports" {
  bucket = aws_s3_bucket.medical_reports.id

  role = aws_iam_role.s3_replication.arn

  rules {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.medical_reports_dr.arn
      storage_class = "STANDARD"
    }
  }

  depends_on = [aws_s3_bucket.medical_reports, aws_s3_bucket.medical_reports_dr]
}

resource "aws_iam_role" "s3_replication" {
  name = "${local.project}-s3-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "s3_replication" {
  name = "${local.project}-s3-replication-policy"
  role = aws_iam_role.s3_replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.medical_reports.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionTagging",
          "s3:GetObjectRetention",
          "s3:GetObjectLegalHold"
        ]
        Resource = ["${aws_s3_bucket.medical_reports.arn}/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
          "s3:GetObjectVersionTagging",
          "s3:ObjectOwnerOverrideToBucketOwner"
        ]
        Resource = ["${aws_s3_bucket.medical_reports_dr.arn}/*"]
      }
    ]
  })
}

resource "aws_cognito_user_pool" "this" {
  name = "${local.project}-users"
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OPTIONAL"
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }
  tags = merge(local.tags, { Name = "${local.project}-user-pool" })
}

resource "aws_cognito_user_pool_client" "this" {
  name         = "${local.project}-app"
  user_pool_id = aws_cognito_user_pool.this.id
  generate_secret               = true
  prevent_user_existence_errors = "ENABLED"
  allowed_oauth_flows           = ["code", "implicit"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes          = ["email", "openid", "profile"]
  callback_urls                 = var.cognito_callback_urls
  logout_urls                   = var.cognito_logout_urls
}

resource "aws_lb" "primary" {
  name               = "${local.project}-alb-primary"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.edge_alb.id]
  subnets            = [for s in aws_subnet.edge_public : s.id]
  tags               = merge(local.tags, { Name = "${local.project}-primary-alb" })
}

resource "aws_lb_listener" "primary_http" {
  load_balancer_arn = aws_lb.primary.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "HMS ALB healthy"
      status_code  = "200"
    }
  }
}

resource "aws_lb_listener" "primary_https" {
  load_balancer_arn = aws_lb.primary.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.primary_certificate_arn

  default_action {
    type             = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "HMS ALB healthy"
      status_code  = "200"
    }
  }
}

resource "aws_security_group" "edge_alb" {
  name   = "${local.project}-alb-sg"
  vpc_id = aws_vpc.edge.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.project}-alb-sg" })
}

resource "aws_cloudwatch_metric_alarm" "alb_healthy_hosts" {
  alarm_name          = "${local.project}-primary-alb-health"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 1

  dimensions = {
    LoadBalancer = aws_lb.primary.arn_suffix
  }

  alarm_description = "Alert if ALB has fewer than 1 healthy hosts"
  alarm_actions     = [aws_sns_topic.failover.arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_dr_healthy_hosts" {
  provider             = aws.dr
  alarm_name           = "${local.project}-dr-alb-health"
  comparison_operator  = "LessThanThreshold"
  evaluation_periods   = 1
  metric_name          = "HealthyHostCount"
  namespace            = "AWS/ApplicationELB"
  period               = 60
  statistic            = "Average"
  threshold            = 1

  dimensions = {
    LoadBalancer = aws_lb.dr.arn_suffix
  }

  alarm_description = "Alert if DR ALB has fewer than 1 healthy hosts"
  alarm_actions     = [aws_sns_topic.failover.arn]
}

resource "aws_sns_topic" "failover" {
  name = "${local.project}-failover"
  tags = merge(local.tags, { Name = "${local.project}-sns" })
}

resource "aws_route53_health_check" "primary_alb" {
  fqdn              = var.primary_health_check_fqdn
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30
}

resource "aws_route53_health_check" "dr_alb" {
  fqdn              = var.dr_health_check_fqdn
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30
}

resource "aws_route53_record" "failover" {
  zone_id = var.route53_zone_id
  name    = var.route53_record_name
  type    = "A"

  set_identifier = "primary"
  failover_routing_policy {
    type = "PRIMARY"
  }

  alias {
    name                   = aws_lb.primary.dns_name
    zone_id                = aws_lb.primary.zone_id
    evaluate_target_health = true
  }

  health_check_id = aws_route53_health_check.primary_alb.id
}

resource "aws_route53_record" "failover_secondary" {
  zone_id = var.route53_zone_id
  name    = var.route53_record_name
  type    = "A"

  set_identifier = "secondary"
  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = aws_lb.dr.dns_name
    zone_id                = aws_lb.dr.zone_id
    evaluate_target_health = true
  }

  health_check_id = aws_route53_health_check.dr_alb.id
}

#########################
# Disaster Recovery Region
#########################
resource "aws_vpc" "edge_dr" {
  provider             = aws.dr
  cidr_block           = var.edge_vpc_cidr_dr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.tags, { Name = "${local.project}-edge-dr" })
}

resource "aws_vpc" "services_dr" {
  provider             = aws.dr
  cidr_block           = var.services_vpc_cidr_dr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.tags, { Name = "${local.project}-services-dr" })
}

resource "aws_internet_gateway" "services_dr" {
  provider = aws.dr
  vpc_id   = aws_vpc.services_dr.id
  tags     = merge(local.tags, { Name = "${local.project}-services-dr-igw" })
}

resource "aws_vpc" "data_dr" {
  provider             = aws.dr
  cidr_block           = var.data_vpc_cidr_dr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(local.tags, { Name = "${local.project}-data-dr" })
}

resource "aws_internet_gateway" "edge_dr" {
  provider = aws.dr
  vpc_id   = aws_vpc.edge_dr.id
  tags     = merge(local.tags, { Name = "${local.project}-edge-dr-igw" })
}

resource "aws_subnet" "edge_dr_public" {
  provider = aws.dr
  for_each = { for idx, cidr in var.edge_public_subnet_cidrs_dr : idx => cidr }

  vpc_id                  = aws_vpc.edge_dr.id
  cidr_block              = each.value
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.dr.names[tonumber(each.key) % length(data.aws_availability_zones.dr.names)]
  tags = merge(local.tags, {
    Name = "${local.project}-edge-dr-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_subnet" "services_dr_private" {
  provider = aws.dr
  for_each = { for idx, cidr in var.services_private_subnet_cidrs_dr : idx => cidr }

  vpc_id            = aws_vpc.services_dr.id
  cidr_block        = each.value
  availability_zone = data.aws_availability_zones.dr.names[tonumber(each.key) % length(data.aws_availability_zones.dr.names)]
  tags = merge(local.tags, {
    Name = "${local.project}-services-dr-private-${each.key}"
    Tier = "private"
  })
}

resource "aws_subnet" "services_dr_egress" {
  provider = aws.dr
  for_each = { for idx, cidr in var.services_egress_subnet_cidrs_dr : idx => cidr }

  vpc_id                  = aws_vpc.services_dr.id
  cidr_block              = each.value
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.dr.names[tonumber(each.key) % length(data.aws_availability_zones.dr.names)]
  tags = merge(local.tags, {
    Name = "${local.project}-services-dr-egress-${each.key}"
    Tier = "egress"
  })
}

resource "aws_subnet" "data_dr_private" {
  provider = aws.dr
  for_each = { for idx, cidr in var.data_private_subnet_cidrs_dr : idx => cidr }

  vpc_id            = aws_vpc.data_dr.id
  cidr_block        = each.value
  availability_zone = data.aws_availability_zones.dr.names[tonumber(each.key) % length(data.aws_availability_zones.dr.names)]
  tags = merge(local.tags, {
    Name = "${local.project}-data-dr-private-${each.key}"
    Tier = "private"
  })
}

resource "aws_route_table" "data_dr_private" {
  provider = aws.dr
  vpc_id   = aws_vpc.data_dr.id
  tags     = merge(local.tags, { Name = "${local.project}-data-dr-private-rt" })
}

resource "aws_route_table_association" "data_dr_private" {
  provider = aws.dr
  for_each = aws_subnet.data_dr_private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.data_dr_private.id
}

resource "aws_eip" "services_dr" {
  provider = aws.dr
  for_each = aws_subnet.services_dr_egress

  domain = "vpc"
  tags   = merge(local.tags, { Name = "${local.project}-services-dr-eip-${each.key}" })
}

resource "aws_nat_gateway" "services_dr" {
  provider = aws.dr
  for_each = aws_subnet.services_dr_egress

  allocation_id = aws_eip.services_dr[each.key].id
  subnet_id     = each.value.id
  tags          = merge(local.tags, { Name = "${local.project}-services-dr-nat-${each.key}" })
  depends_on    = [aws_internet_gateway.services_dr]
}

resource "aws_route_table" "edge_dr_public" {
  provider = aws.dr
  vpc_id   = aws_vpc.edge_dr.id
  tags     = merge(local.tags, { Name = "${local.project}-edge-dr-public-rt" })
}

resource "aws_route" "edge_dr_internet" {
  provider              = aws.dr
  route_table_id        = aws_route_table.edge_dr_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id            = aws_internet_gateway.edge_dr.id
}

resource "aws_route" "edge_dr_to_services" {
  provider               = aws.dr
  route_table_id         = aws_route_table.edge_dr_public.id
  destination_cidr_block = var.services_vpc_cidr_dr
  transit_gateway_id     = aws_ec2_transit_gateway.dr.id
}

resource "aws_route" "edge_dr_to_data" {
  provider               = aws.dr
  route_table_id         = aws_route_table.edge_dr_public.id
  destination_cidr_block = var.data_vpc_cidr_dr
  transit_gateway_id     = aws_ec2_transit_gateway.dr.id
}

resource "aws_route_table_association" "edge_dr_public" {
  provider       = aws.dr
  for_each       = aws_subnet.edge_dr_public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.edge_dr_public.id
}

resource "aws_route_table" "services_dr_private" {
  provider = aws.dr
  for_each = aws_nat_gateway.services_dr

  vpc_id = aws_vpc.services_dr.id
  tags   = merge(local.tags, { Name = "${local.project}-services-dr-private-rt-${each.key}" })
}

resource "aws_route" "services_dr_private_nat" {
  provider = aws.dr
  for_each = aws_route_table.services_dr_private

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.services_dr[each.key].id
}

resource "aws_route" "services_dr_to_data" {
  provider = aws.dr
  for_each = aws_route_table.services_dr_private

  route_table_id         = each.value.id
  destination_cidr_block = var.data_vpc_cidr_dr
  transit_gateway_id     = aws_ec2_transit_gateway.dr.id
}

resource "aws_route" "services_dr_to_edge" {
  provider = aws.dr
  for_each = aws_route_table.services_dr_private

  route_table_id         = each.value.id
  destination_cidr_block = var.edge_vpc_cidr_dr
  transit_gateway_id     = aws_ec2_transit_gateway.dr.id
}

resource "aws_route_table" "services_dr_egress" {
  provider = aws.dr
  for_each = aws_subnet.services_dr_egress

  vpc_id = aws_vpc.services_dr.id
  tags   = merge(local.tags, { Name = "${local.project}-services-dr-egress-rt-${each.key}" })
}

resource "aws_route" "services_dr_egress_internet" {
  provider = aws.dr
  for_each = aws_route_table.services_dr_egress

  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.services_dr.id
}

resource "aws_route_table_association" "services_dr_egress" {
  provider = aws.dr
  for_each = aws_subnet.services_dr_egress

  subnet_id      = each.value.id
  route_table_id = aws_route_table.services_dr_egress[each.key].id
}

resource "aws_route_table_association" "services_dr_private" {
  provider = aws.dr
  for_each = aws_subnet.services_dr_private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.services_dr_private[each.key].id
}

resource "aws_route" "data_dr_to_services" {
  provider              = aws.dr
  route_table_id        = aws_route_table.data_dr_private.id
  destination_cidr_block = var.services_vpc_cidr_dr
  transit_gateway_id    = aws_ec2_transit_gateway.dr.id
}

resource "aws_route" "data_dr_to_edge" {
  provider              = aws.dr
  route_table_id        = aws_route_table.data_dr_private.id
  destination_cidr_block = var.edge_vpc_cidr_dr
  transit_gateway_id    = aws_ec2_transit_gateway.dr.id
}

resource "aws_db_subnet_group" "aurora_dr" {
  provider   = aws.dr
  name       = "${local.project}-aurora-dr-subnets"
  subnet_ids = [for s in aws_subnet.data_dr_private : s.id]
}

resource "aws_security_group" "aurora_dr" {
  provider = aws.dr
  name     = "${local.project}-aurora-dr-sg"
  vpc_id   = aws_vpc.data_dr.id

  ingress {
    description = "Primary Aurora"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.data_vpc_cidr, var.data_vpc_cidr_dr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_rds_global_cluster" "aurora" {
  global_cluster_identifier = "${local.project}-aurora-global"
  engine                    = aws_rds_cluster.aurora.engine
  engine_version            = aws_rds_cluster.aurora.engine_version
}

resource "aws_rds_cluster" "aurora_dr" {
  provider                = aws.dr
  cluster_identifier      = "${local.project}-aurora-dr"
  engine                  = "aurora-postgresql"
  engine_version          = var.aurora_engine_version
  master_username         = var.aurora_master_username
  master_password         = var.aurora_master_password
  db_subnet_group_name    = aws_db_subnet_group.aurora_dr.name
  vpc_security_group_ids  = [aws_security_group.aurora_dr.id]
  global_cluster_identifier = aws_rds_global_cluster.aurora.id
  storage_encrypted       = true
  skip_final_snapshot     = true
  depends_on              = [aws_rds_global_cluster.aurora]
}

resource "aws_rds_cluster_instance" "aurora_dr_instances" {
  provider           = aws.dr
  count              = 1
  identifier         = "${local.project}-aurora-dr-${count.index}"
  cluster_identifier = aws_rds_cluster.aurora_dr.id
  instance_class     = var.aurora_instance_class
  engine             = aws_rds_cluster.aurora_dr.engine
  engine_version     = aws_rds_cluster.aurora_dr.engine_version
  publicly_accessible = false
  db_subnet_group_name = aws_db_subnet_group.aurora_dr.name
}

resource "aws_security_group" "eks_cluster_dr" {
  provider    = aws.dr
  name        = "${local.project}-eks-cluster-dr"
  description = "DR Cluster communication"
  vpc_id      = aws_vpc.services_dr.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    cidr_blocks     = [var.services_vpc_cidr_dr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.project}-eks-cluster-dr-sg" })
}

resource "aws_security_group" "eks_nodes_dr" {
  provider    = aws.dr
  name        = "${local.project}-eks-nodes-dr"
  description = "DR Worker nodes"
  vpc_id      = aws_vpc.services_dr.id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster_dr.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.project}-eks-nodes-dr-sg" })
}

resource "aws_iam_role" "eks_cluster_dr" {
  name = "${local.project}-eks-cluster-dr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_dr" {
  role       = aws_iam_role.eks_cluster_dr.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_nodes_dr" {
  name = "${local.project}-eks-nodes-dr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_nodes_dr_worker" {
  role       = aws_iam_role.eks_nodes_dr.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_nodes_dr_cni" {
  role       = aws_iam_role.eks_nodes_dr.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_nodes_dr_ecr" {
  role       = aws_iam_role.eks_nodes_dr.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_cluster" "dr" {
  provider = aws.dr
  name     = "${local.project}-eks-dr"
  role_arn = aws_iam_role.eks_cluster_dr.arn
  version  = var.eks_version

  vpc_config {
    subnet_ids         = [for s in aws_subnet.services_dr_private : s.id]
    security_group_ids = [aws_security_group.eks_cluster_dr.id]
    endpoint_public_access = false
    endpoint_private_access = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_dr]
}

resource "aws_eks_node_group" "dr" {
  provider         = aws.dr
  cluster_name     = aws_eks_cluster.dr.name
  node_group_name  = "${local.project}-dr"
  node_role_arn    = aws_iam_role.eks_nodes_dr.arn
  subnet_ids       = [for s in aws_subnet.services_dr_private : s.id]
  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 2
  }
  instance_types = var.eks_instance_types
  capacity_type  = "ON_DEMAND"

  depends_on = [
    aws_iam_role_policy_attachment.eks_nodes_dr_worker,
    aws_iam_role_policy_attachment.eks_nodes_dr_cni,
    aws_iam_role_policy_attachment.eks_nodes_dr_ecr
  ]
}

resource "aws_lb" "dr" {
  provider           = aws.dr
  name               = "${local.project}-alb-dr"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.edge_alb_dr.id]
  subnets            = [for s in aws_subnet.edge_dr_public : s.id]
  tags               = merge(local.tags, { Name = "${local.project}-dr-alb" })
}

resource "aws_security_group" "edge_alb_dr" {
  provider = aws.dr
  name     = "${local.project}-alb-dr-sg"
  vpc_id   = aws_vpc.edge_dr.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.project}-alb-dr-sg" })
}

resource "aws_lb_listener" "dr_http" {
  provider          = aws.dr
  load_balancer_arn = aws_lb.dr.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "HMS DR ALB healthy"
      status_code  = "200"
    }
  }
}

resource "aws_lb_listener" "dr_https" {
  provider          = aws.dr
  load_balancer_arn = aws_lb.dr.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.dr_certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "HMS DR ALB healthy"
      status_code  = "200"
    }
  }
}

#########################
# GitHub Actions OIDC Role
#########################
resource "aws_iam_role" "github_actions" {
  name = "${local.project}-github-oidc"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" : "repo:${var.github_repository}:ref:refs/heads/${var.github_branch}"
        }
      }
    }]
  })
}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list = [
    "sts.amazonaws.com"
  ]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role_policy" "github_actions" {
  name = "${local.project}-github-actions"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:DescribeRepositories",
          "sts:AssumeRole",
          "eks:DescribeCluster"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "iam:PassRole"
        ],
        Resource = [
          aws_iam_role.eks_nodes.arn,
          aws_iam_role.eks_cluster.arn,
          aws_iam_role.eks_nodes_dr.arn,
          aws_iam_role.eks_cluster_dr.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

#########################
# Helm Deployments
#########################
provider "kubernetes" {
  host                   = aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

data "aws_eks_cluster_auth" "this" {
  name = aws_eks_cluster.this.name
}

resource "helm_release" "frontend" {
  name       = "frontend"
  repository = null
  chart      = "${path.module}/helm/frontend"
  namespace  = var.kubernetes_namespace
  create_namespace = true
  values = [
    jsonencode({
      image = {
        repository = aws_ecr_repository.microservices["frontend"].repository_url
        tag        = var.image_tag
      },
      ingress = {
        host = var.route53_record_name
        path = "/"
        alb  = {
          scheme      = "internet-facing"
          target_type = "ip"
          cert_arn    = var.primary_certificate_arn
          load_balancer_name = aws_lb.primary.name
        }
      }
    })
  ]
  depends_on = [aws_eks_node_group.primary]
}

resource "helm_release" "backend" {
  name      = "backend"
  chart     = "${path.module}/helm/backend"
  namespace = var.kubernetes_namespace
  values = [
    jsonencode({
      image = {
        repository = aws_ecr_repository.microservices["backend"].repository_url
        tag        = var.image_tag
      },
      ingress = {
        host = var.route53_record_name
        path = "/api"
        alb  = {
          scheme      = "internet-facing"
          target_type = "ip"
          cert_arn    = var.primary_certificate_arn
          load_balancer_name = aws_lb.primary.name
        }
      }
    })
  ]
  depends_on = [helm_release.frontend]
}

resource "helm_release" "telemedicine" {
  name      = "telemedicine"
  chart     = "${path.module}/helm/telemedicine"
  namespace = var.kubernetes_namespace
  values = [
    jsonencode({
      image = {
        repository = aws_ecr_repository.microservices["telemedicine"].repository_url
        tag        = var.image_tag
      },
      ingress = {
        host = var.route53_record_name
        path = "/tele"
        alb  = {
          scheme      = "internet-facing"
          target_type = "ip"
          cert_arn    = var.primary_certificate_arn
          load_balancer_name = aws_lb.primary.name
        }
      }
    })
  ]
  depends_on = [helm_release.backend]
}

resource "helm_release" "notification" {
  name      = "notification"
  chart     = "${path.module}/helm/notification"
  namespace = var.kubernetes_namespace
  values = [
    jsonencode({
      image = {
        repository = aws_ecr_repository.microservices["notification"].repository_url
        tag        = var.image_tag
      },
      ingress = {
        host = var.route53_record_name
        path = "/notify"
        alb  = {
          scheme      = "internet-facing"
          target_type = "ip"
          cert_arn    = var.primary_certificate_arn
          load_balancer_name = aws_lb.primary.name
        }
      }
    })
  ]
  depends_on = [helm_release.telemedicine]
}

