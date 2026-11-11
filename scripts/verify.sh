#!/usr/bin/env bash
# End-to-end check of the whole platform, from the AWS side (not from Terraform's point of view).
#   scripts/verify.sh            checks every component that exists and skips the switched-off ones
#   scripts/verify.sh --smoke    also uploads a CSV and waits for the ingest pipeline to record it
#   scripts/verify.sh --poison   also drops a poison file and waits for it to reach the dead-letter queue
set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
DATA="plat-data-${ACCOUNT}-${REGION}"
STATE="plat-tfstate-${ACCOUNT}-${REGION}"
pass=0; fail=0; skip=0

ok()   { echo "PASS  $1"; pass=$((pass+1)); }
bad()  { echo "FAIL  $1${2:+ -> $2}"; fail=$((fail+1)); }
skp()  { echo "SKIP  $1 ($2)"; skip=$((skip+1)); }

# expect <name> <expected output> <command...>
expect() {
  local name="$1" want="$2"; shift 2
  local got; got="$("$@" 2>&1 | tr -d '\r' | head -c 300)"
  if [ "$got" = "$want" ]; then ok "$name"; else bad "$name" "wanted '$want', got '$got'"; fi
}

echo "== account $ACCOUNT, region $REGION"

echo "== foundations"
expect "state bucket versioned"      "Enabled" aws s3api get-bucket-versioning --bucket "$STATE" --query Status --output text
expect "VPC exists"                  "1"       aws ec2 describe-vpcs --filters Name=tag:Name,Values=plat-vpc --query 'length(Vpcs)' --output text
expect "4 subnets"                   "4"       aws ec2 describe-subnets --filters Name=tag:project,Values=plat --query 'length(Subnets)' --output text
NAT=$(aws ec2 describe-nat-gateways --filter Name=state,Values=available,pending --query 'length(NatGateways)' --output text)
echo "INFO  NAT gateways running: $NAT"
expect "KMS key rotation on"         "True"    aws kms get-key-rotation-status --key-id alias/plat-data --query KeyRotationEnabled --output text
expect "secret encrypted with plat-data" "True" bash -c "aws secretsmanager describe-secret --secret-id plat/demo/api-key --query KmsKeyId --output text | grep -q key/ && echo True"
expect "demo reader role"            "plat-demo-reader" aws iam get-role --role-name plat-demo-reader --query Role.RoleName --output text

echo "== data"
expect "data bucket uses KMS"        "aws:kms" aws s3api get-bucket-encryption --bucket "$DATA" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text
expect "jobs table active"           "ACTIVE"  aws dynamodb describe-table --table-name plat-jobs --query Table.TableStatus --output text
expect "jobs TTL on"                 "ENABLED" aws dynamodb describe-time-to-live --table-name plat-jobs --query TimeToLiveDescription.TimeToLiveStatus --output text
expect "EFS available"               "available" aws efs describe-file-systems --query 'FileSystems[?Name==`plat-efs`]|[0].LifeCycleState' --output text
RDS=$(aws rds describe-db-instances --query 'length(DBInstances[?DBInstanceIdentifier==`plat-meta`])' --output text)
if [ "$RDS" = "1" ]; then expect "RDS available" "available" aws rds describe-db-instances --db-instance-identifier plat-meta --query 'DBInstances[0].DBInstanceStatus' --output text; else skp "RDS plat-meta" "enable_rds is off"; fi

echo "== compute"
IID=$(aws ec2 describe-instances --filters Name=tag:Name,Values=plat-ec2 Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)
if [ -n "$IID" ] && [ "$IID" != "None" ]; then
  ok "plat-ec2 running ($IID)"
  expect "plat-ec2 reachable by Session Manager" "Online" aws ssm describe-instance-information --filters Key=InstanceIds,Values="$IID" --query 'InstanceInformationList[0].PingStatus' --output text
else skp "plat-ec2" "not running"; fi
expect "ECR repo"                    "plat-api" aws ecr describe-repositories --repository-names plat-api --query 'repositories[0].repositoryName' --output text
expect "ECS cluster"                 "ACTIVE"   aws ecs describe-clusters --clusters plat-cluster --query 'clusters[0].status' --output text
SVC=$(aws ecs describe-services --cluster plat-cluster --services plat-api-svc --query 'services[?status==`ACTIVE`]|length(@)' --output text 2>/dev/null)
if [ "$SVC" = "1" ]; then
  expect "API tasks running" "1" bash -c "aws ecs describe-services --cluster plat-cluster --services plat-api-svc --query 'services[0].runningCount>=\`1\`' --output text | sed 's/True/1/;s/False/0/'"
  ALB=$(aws elbv2 describe-load-balancers --names plat-alb --query 'LoadBalancers[0].DNSName' --output text)
  expect "ALB answers (HTTP status)" "200" curl -s -o /dev/null -w '%{http_code}' "http://$ALB/"
else skp "ECS service plat-api-svc" "enable_service is off"; fi
EKS=$(aws eks list-clusters --query 'length(clusters[?@==`plat-eks`])' --output text)
if [ "$EKS" = "1" ]; then expect "EKS cluster" "ACTIVE" aws eks describe-cluster --name plat-eks --query cluster.status --output text; else skp "EKS plat-eks" "enable_eks is off"; fi

echo "== events"
expect "ingest Lambda"               "Active"  aws lambda get-function --function-name plat-ingest --query Configuration.State --output text
expect "report Lambda"               "Active"  aws lambda get-function --function-name plat-report --query Configuration.State --output text
expect "nightly rule enabled"        "ENABLED" aws events describe-rule --name plat-nightly-report --query State --output text
expect "ec2 state rule enabled"      "ENABLED" aws events describe-rule --name plat-ec2-state-change --query State --output text
QURL=$(aws sqs get-queue-url --queue-name plat-ingest-queue --query QueueUrl --output text)
expect "ingest queue has a DLQ"      "1"       bash -c "aws sqs get-queue-attributes --queue-url $QURL --attribute-names RedrivePolicy --query 'length(Attributes)' --output text"

echo "== ml, delivery, observability, cost"
SM=$(aws sagemaker list-domains --query 'length(Domains[?DomainName==`plat-studio`])' --output text)
if [ "$SM" = "1" ]; then ok "SageMaker domain plat-studio"; else skp "SageMaker domain" "enable_studio is off"; fi
EP=$(aws sagemaker list-endpoints --name-contains plat-churn --query 'length(Endpoints)' --output text)
if [ "$EP" != "0" ]; then expect "churn endpoint in service" "InService" aws sagemaker describe-endpoint --endpoint-name plat-churn --query EndpointStatus --output text; else skp "plat-churn endpoint" "enable_endpoint is off"; fi
expect "GitHub connection authorised" "AVAILABLE" aws codestar-connections list-connections --query 'Connections[?ConnectionName==`plat-github`]|[0].ConnectionStatus' --output text
expect "pipeline exists"             "plat-api-pipeline" aws codepipeline get-pipeline --name plat-api-pipeline --query pipeline.name --output text
expect "dashboard exists"            "plat-overview" aws cloudwatch get-dashboard --dashboard-name plat-overview --query DashboardName --output text
expect "alarms exist (at least 2)"   "True"    bash -c "aws cloudwatch describe-alarms --alarm-name-prefix plat- --query 'length(MetricAlarms)>=\`2\`' --output text"
expect "budget exists"               "plat-monthly-guard" aws budgets describe-budget --account-id "$ACCOUNT" --budget-name plat-monthly-guard --query Budget.BudgetName --output text

if [[ " $* " == *" --smoke "* ]]; then
  echo "== smoke test: S3 -> SQS -> Lambda -> DynamoDB"
  KEY="raw/verify-$(date +%s).csv"
  printf 'id,value\n1,a\n2,b\n3,c\n' > /tmp/verify.csv
  aws s3 cp /tmp/verify.csv "s3://$DATA/$KEY" --only-show-errors
  for i in $(seq 1 20); do
    ROWS=$(aws dynamodb get-item --table-name plat-jobs --key "{\"job_id\":{\"S\":\"$KEY\"}}" --query 'Item.rows.N' --output text 2>/dev/null)
    [ -n "$ROWS" ] && [ "$ROWS" != "None" ] && break
    sleep 3
  done
  if [ "$ROWS" = "3" ]; then ok "object ingested, 3 rows recorded"; else bad "ingest pipeline" "no item with rows=3 after 60 s"; fi
fi

if [[ " $* " == *" --poison "* ]]; then
  echo "== poison test: a failing message must reach the dead-letter queue"
  printf 'POISON\n' > /tmp/poison.csv
  aws s3 cp /tmp/poison.csv "s3://$DATA/raw/poison-$(date +%s).csv" --only-show-errors
  DLQ=$(aws sqs get-queue-url --queue-name plat-ingest-dlq --query QueueUrl --output text)
  for i in $(seq 1 40); do
    N=$(aws sqs get-queue-attributes --queue-url "$DLQ" --attribute-names ApproximateNumberOfMessages --query 'Attributes.ApproximateNumberOfMessages' --output text)
    [ "$N" -ge 1 ] 2>/dev/null && break
    sleep 10
  done
  if [ "${N:-0}" -ge 1 ] 2>/dev/null; then ok "poison message reached the DLQ (depth $N)"; else bad "dead-letter queue" "still empty after 400 s"; fi
fi

echo
echo "passed $pass, failed $fail, skipped $skip"
[ "$fail" -eq 0 ]
