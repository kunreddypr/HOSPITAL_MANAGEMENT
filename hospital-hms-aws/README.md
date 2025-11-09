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

## Deploying with Helm

Package and deploy the umbrella chart once your cluster context is configured:

```bash
helm upgrade --install hms infra/helm -n hms-prod -f infra/helm/values.yaml
```

The chart provisions ConfigMaps that render an `app-config.js` file consumed by the frontend and injects all backend environment variables, autoscalers, PodDisruptionBudgets, and network policies.

### Database password secret

Create the database password secret referenced by the chart before deploying:

```bash
kubectl -n hms-prod create secret generic hms-db-password --from-literal=DB_PASSWORD='StrongPassword!'
```

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
