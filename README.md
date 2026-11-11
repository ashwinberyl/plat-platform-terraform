# plat-platform-terraform

The whole "Platform Lab" capstone from the AWS series, rebuilt as Terraform and taught step by step in the **AWS on Terraform** series on the blog.

| Directory | What it is |
|---|---|
| `bootstrap/` | State bucket (S3 native locking) and the GitHub OIDC roles. Applied once, from your laptop. |
| `modules/` | Reusable building blocks: `s3-bucket`, `vpc`. |
| `stacks/10-identity` | Identity Center groups, users, permission sets, `plat-demo-reader` |
| `stacks/20-network` | VPC, subnets, routes, optional NAT, gateway endpoints |
| `stacks/30-security` | KMS key, secret, security groups, optional interface endpoint |
| `stacks/40-data` | S3 data lake, DynamoDB `plat-jobs`, optional RDS `plat-meta`, EFS |
| `stacks/50-ec2` | Instance reachable only through Session Manager (`enable_ec2`) |
| `stacks/52-ecs` | ECR, ECS Fargate service, ALB (`enable_service`) |
| `stacks/55-eks` | EKS cluster, node group, access entries, Pod Identity (`enable_eks`) |
| `stacks/60-events` | S3 → SQS → Lambda ingest, DLQ, EventBridge schedule and rules, SNS |
| `stacks/70-ml` | SageMaker Studio domain and churn endpoint (`enable_studio`, `enable_endpoint`) |
| `stacks/80-delivery` | GitHub connection, CodeBuild, CodePipeline (`enable_deploy_stage`) |
| `stacks/90-observe` | Dashboard, alarms, log metric filters |
| `stacks/95-cost` | Budget, anomaly detection, cost allocation tags |
| `labs/` | Small throw-away configurations used by individual posts |
| `scripts/tf.sh` | Runs Terraform in a stack with the right backend settings |
| `scripts/verify.sh` | Checks the deployed platform from the AWS side; skips switched-off parts |

## Before you start

* An AWS account, the AWS CLI v2 and Terraform 1.10 or newer.
* You are signed in with admin rights (`aws sts get-caller-identity` works).
* Identity Center is **enabled by hand once** (Post 03). Terraform can read it but cannot enable it.
* If you built the lab by hand in the AWS series, **destroy those resources first** (or expect name clashes: the IAM role, KMS alias, bucket, table, secret and security groups all share names).

## First run

```bash
export AWS_PROFILE=plat-admin AWS_REGION=us-east-1

# 1. state bucket and CI roles, using local state for this one stack
terraform -chdir=bootstrap init
terraform -chdir=bootstrap apply

# 2. move bootstrap's own state into the bucket it just created
cp bootstrap/backend.tf.example bootstrap/backend.tf
scripts/tf.sh bootstrap migrate

# 3. the stacks, in order
cp stacks/10-identity/terraform.tfvars.example stacks/10-identity/terraform.tfvars   # edit the emails
for s in 10-identity 20-network 30-security 40-data; do scripts/tf.sh $s apply; done
# the rest (50-ec2 … 95-cost) follow in order, one post each; or `make up`
```

Costly pieces are **off by default**: `enable_nat` (20-network), `enable_secretsmanager_endpoint` (30-security) and `enable_rds` (40-data). Switch one on with `-var`, for example `scripts/tf.sh 20-network apply -var enable_nat=true`.

## Cost switches

| Switch | Stack | Default | Costs roughly |
|---|---|---|---|
| `enable_nat` | 20-network | off | NAT gateway hourly + data |
| `enable_secretsmanager_endpoint` | 30-security | off | interface endpoint hourly |
| `enable_rds` | 40-data | off | db.t4g.micro hourly |
| `enable_ec2` / `enable_ssm_endpoints` | 50-ec2 | off | instance, 3 endpoints |
| `enable_service` | 52-ecs | off | Fargate task + ALB |
| `enable_eks` | 55-eks | off | control plane + nodes |
| `enable_studio` / `enable_endpoint` | 70-ml | off | Studio apps, endpoint instance |
| `enable_deploy_stage` | 80-delivery | off | ECS deploy action |
| `enable_cost_allocation_tags` / `enable_anomaly_detection` | 95-cost | off | free, but need Cost Explorer enabled |

`make pause` switches the hourly-billed pieces off; `make up` switches them on. Check the result with `make verify` (add `make smoke` for the S3→DynamoDB and dead-letter tests).

## Tear down

```bash
make down                # destroys the 12 stacks in reverse order; keeps bootstrap
make destroy-bootstrap   # last: the state bucket and CI roles (asks for the account id)
```

The state bucket has `prevent_destroy`. Removing it is deliberate and manual (Post 01).
