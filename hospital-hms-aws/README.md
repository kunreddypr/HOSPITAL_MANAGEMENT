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

## Running in Amazon AWS

Follow these steps to take the application from containers on your workstation to a production-grade deployment on Amazon EKS.

### 1. Authenticate and prepare registries

```bash
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <account-id>.dkr.ecr.<region>.amazonaws.com
aws ecr describe-repositories --repository-names frontend backend || \
  aws ecr create-repository --repository-name frontend && \
  aws ecr create-repository --repository-name backend
```

### 2. Build Docker images

```bash
# Frontend
cd apps/frontend
docker build -t <account-id>.dkr.ecr.<region>.amazonaws.com/frontend:<tag> -f Dockerfile.production .

# Backend
cd ../backend
docker build -t <account-id>.dkr.ecr.<region>.amazonaws.com/backend:<tag> -f Dockerfile.production .
```

### 3. Push images to ECR

```bash
docker push <account-id>.dkr.ecr.<region>.amazonaws.com/frontend:<tag>
docker push <account-id>.dkr.ecr.<region>.amazonaws.com/backend:<tag>
```

### 4. Configure cluster access

```bash
aws eks --region <region> update-kubeconfig --name <cluster-name>
kubectl config set-context --current --namespace=hms-prod
```

Ensure the `aws-load-balancer-controller` is running and that the `hms-prod` namespace exists (create it with `kubectl create namespace hms-prod` if required).

### 5. Create required secrets and config maps

```bash
kubectl -n hms-prod create secret generic hms-db-password --from-literal=DB_PASSWORD='StrongPassword!' --dry-run=client -o yaml | kubectl apply -f -
kubectl -n hms-prod create secret generic hms-backend --from-env-file=infra/helm/secrets/backend.env --dry-run=client -o yaml | kubectl apply -f -
```

Update `infra/helm/secrets/backend.env` with production environment variables (Cognito IDs, S3 bucket, DynamoDB table, etc.) before applying.

### 6. Deploy with Helm

```bash
helm upgrade --install hms infra/helm \
  --namespace hms-prod \
  --set imageTags.frontend=<tag> \
  --set imageTags.backend=<tag> \
  -f infra/helm/values.yaml
```

The umbrella chart rolls out the frontend and backend services, provisions ConfigMaps that render the `app-config.js` file, and wires autoscaling, PodDisruptionBudgets, and network policies.

### 7. Verify the rollout

```bash
kubectl get pods
kubectl get svc
kubectl describe ingress hms-frontend
```

Navigate to the DNS name exposed by the AWS Application Load Balancer once the ingress status shows an address.

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
