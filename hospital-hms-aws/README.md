# Hospital HMS AWS Monorepo

Hospital HMS AWS is a production-ready monorepo that packages a React/Vite frontline experience, a Node/Express/Prisma API, Kubernetes Helm charts, and CI/CD automation for Amazon EKS.

## Repository layout

```
hospital-hms-aws/
├── apps
│   ├── frontend      # React + Vite + Amplify Auth
│   └── backend       # Express API + Prisma + AWS integrations
├── infra
│   ├── helm          # Umbrella chart with frontend/backend subcharts
│   └── k8s-addons    # Optional manifests (IngressClass, HPAs, VPAs)
└── .github/workflows # CI/CD pipeline
```

## Prerequisites

Before deploying to AWS ensure the following infrastructure pieces already exist:

- **Amazon EKS** cluster with worker nodes, IAM roles, and OIDC provider configured.
- **aws-load-balancer-controller** installed in the cluster and associated IAM roles created.
- Public subnets with an Internet Gateway and private subnets with NAT Gateway routing.
- Amazon ECR repositories named `frontend` and `backend` in the target region.
- Amazon Aurora PostgreSQL (or RDS PostgreSQL) writer endpoint reachable from the cluster.
- Amazon Cognito user pool and app client configured for hosted UI flows.
- Amazon S3 bucket for patient document uploads (e.g. `hms-data-prod`).
- Amazon DynamoDB table for audit logging (e.g. `hms-audit-prod`).

## Local development

### Frontend

```bash
cd apps/frontend
cp .env.example .env
# update values to point at local backend or mock services
npm install
npm run dev
```

> The frontend loads runtime configuration from `public/app-config.js` if present (the Helm chart injects it). For local development the `.env` file still controls the Cognito and API settings.

### Backend

```bash
cd apps/backend
cp .env.example .env
# update DATABASE_URL to use a local Postgres instance
npm install
npm run prisma:generate
npm run dev
```

## Building and pushing Docker images locally

```bash
# Frontend
cd apps/frontend
docker build -t <account-id>.dkr.ecr.eu-west-3.amazonaws.com/frontend:local -f Dockerfile.production .

# Backend
cd ../backend
docker build -t <account-id>.dkr.ecr.eu-west-3.amazonaws.com/backend:local -f Dockerfile.production .
```

Push the images with `docker push` once authenticated against Amazon ECR.

## Deploying to Amazon EKS

You can now provision the required AWS infrastructure with the Terraform module located in `infra/terraform`.

### Option A – Terraform automated provisioning

1. Change into the Terraform directory and initialize:

   ```bash
   cd infra/terraform
   terraform init
   ```

2. Review the plan and apply the changes (override variables as needed for your AWS account/region):

   ```bash
   terraform plan -out plan.tfplan
   terraform apply plan.tfplan
   ```

   The module provisions a VPC, EKS cluster, managed node group, Amazon ECR repositories, and the AWS Load Balancer Controller. Enable the `deploy_helm_release` variable to have Terraform roll out the bundled Helm chart once your container images are pushed.

3. Update your kubeconfig to talk to the new cluster:

   ```bash
   aws eks update-kubeconfig \
     --name $(terraform output -raw cluster_name) \
     --region $(terraform output -raw region)
   ```

### Option B – Manual deployment to an existing cluster

Follow the steps below to deploy the frontend and backend workloads into an existing Amazon EKS cluster.

### 1. Configure your local environment

1. Install the AWS CLI (`aws`), `kubectl`, and `helm` on your workstation or CI runner.
2. Authenticate with AWS and update the kubeconfig for the target cluster:

   ```bash
   aws configure
   aws eks update-kubeconfig --name <cluster-name> --region <aws-region>
   ```

3. Confirm connectivity by listing the cluster nodes: `kubectl get nodes`.

### 2. Prepare application configuration

1. Copy `infra/helm/values.yaml` to an environment-specific file (e.g. `infra/helm/values-prod.yaml`).
2. Update the following sections with the infrastructure you provisioned earlier:
   - `global.hostedZone` and `global.domain` for the external ALB DNS records.
   - `frontend.config` entries for the Cognito user pool, identity pool, and API URLs.
   - `backend.env` variables including `DATABASE_URL`, `S3_BUCKET`, `DYNAMODB_TABLE`, and AWS service ARNs.

### 3. Build and push container images

1. Authenticate Docker to Amazon ECR: `aws ecr get-login-password --region <aws-region> | docker login --username AWS --password-stdin <account-id>.dkr.ecr.<aws-region>.amazonaws.com`.
2. Build the production images from the monorepo:

   ```bash
   # Frontend
   cd apps/frontend
   docker build -t <account-id>.dkr.ecr.<aws-region>.amazonaws.com/frontend:<tag> -f Dockerfile.production .

   # Backend
   cd ../backend
   docker build -t <account-id>.dkr.ecr.<aws-region>.amazonaws.com/backend:<tag> -f Dockerfile.production .
   ```

3. Push the images to ECR with `docker push` for each tag.
4. Update your Helm values file so `frontend.image.tag` and `backend.image.tag` match the pushed `<tag>`.

### 4. Create Kubernetes secrets

Create the database password secret and any other sensitive values referenced in the chart:

```bash
kubectl -n hms-prod create secret generic hms-db-password --from-literal=DB_PASSWORD='StrongPassword!'
kubectl -n hms-prod create secret generic hms-backend-env --from-literal=JWT_SECRET='<random-value>'
```

Supply additional secrets (for example, third-party API keys) as key/value pairs or sealed secrets according to your security requirements.

### 5. Deploy the Helm chart

Install or upgrade the umbrella chart using the environment-specific values file created earlier:

```bash
helm upgrade --install hms infra/helm \
  --namespace hms-prod \
  --create-namespace \
  -f infra/helm/values-prod.yaml
```

The chart provisions ConfigMaps that render an `app-config.js` file consumed by the frontend, injects backend environment variables, and creates autoscalers, PodDisruptionBudgets, and network policies.

### 6. Verify the deployment

```bash
kubectl -n hms-prod get pods
kubectl -n hms-prod get ingress
```

Wait for the AWS Load Balancer Controller to provision an ALB, then map the generated DNS name to your domain via Route 53 (or update your external DNS solution).

## Disaster recovery considerations

- Store infrastructure definitions (EKS, VPC, Aurora, Cognito) in IaC such as Terraform or AWS CDK for repeatable re-provisioning.
- Enable automated Aurora backups and multi-AZ deployments; test snapshot restores regularly.
- Configure S3 versioning and cross-region replication for critical medical documents.
- Export DynamoDB streams to Kinesis Firehose or S3 for immutable audit log retention.

## Troubleshooting

- **Ingress / ALB provisioning**: confirm subnets have the `kubernetes.io/role/elb` tag and the aws-load-balancer-controller service account has the correct IAM role.
- **HTTP 502 from ALB**: ensure backend pods pass readiness probes and security groups or network policies allow ingress from the ALB target group.
- **HPA scaling**: verify the metrics-server is installed and that requests/limits are tuned to allow CPU-based scaling.
- **Cognito authentication errors**: confirm the hosted UI callback matches the frontend domain and that JWT audiences match the API client ID.

## CI/CD workflow

The GitHub Actions workflow at `.github/workflows/ci-cd.yml` builds, tests, pushes container images to ECR, updates the Helm chart with the new tag, and deploys the release to the `hms-prod` namespace.
