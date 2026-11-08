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
| `scripts/tf.sh` | Runs Terraform in a stack with the right backend settings |

More stacks arrive with later posts (compute, events, ML, delivery, observability).

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
```

Costly pieces are **off by default**: `enable_nat` (20-network), `enable_secretsmanager_endpoint` (30-security) and `enable_rds` (40-data). Switch one on with `-var`, for example `scripts/tf.sh 20-network apply -var enable_nat=true`.

## Tear down

```bash
make down      # destroys stacks in reverse order; keeps bootstrap
```

The state bucket has `prevent_destroy`. Removing it is deliberate and manual (Post 01).
