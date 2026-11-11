# Stacks apply in this order and destroy in the reverse order.
STACKS := 10-identity 20-network 30-security 40-data 50-ec2 52-ecs 55-eks 60-events 70-ml 80-delivery 90-observe 95-cost
REVERSE := $(shell echo $(STACKS) | tr ' ' '\n' | tac | tr '\n' ' ')

.PHONY: fmt validate plan up full down pause verify smoke test destroy-bootstrap

fmt:
	terraform fmt -recursive

validate:
	@for d in bootstrap stacks/* modules/* labs/*; do \
	  echo "== $$d"; terraform -chdir=$$d init -backend=false -input=false >/dev/null && terraform -chdir=$$d validate || exit 1; \
	done

plan:
	@for s in $(STACKS); do echo "== plan $$s"; scripts/tf.sh $$s plan -input=false || exit 1; done

# Everything at its defaults: the cheap configuration. Switches you turned on by hand go back off.
up:
	@for s in $(STACKS); do echo "== apply $$s"; scripts/tf.sh $$s apply -input=false -auto-approve || exit 1; done

# Everything on except EKS and the SageMaker endpoint (those need a decision of their own).
# Usage: make full ALERT_EMAIL=you@example.com
ALERT_EMAIL ?=
full:
	scripts/tf.sh 10-identity apply -input=false -auto-approve
	scripts/tf.sh 20-network apply -input=false -auto-approve -var enable_nat=true
	scripts/tf.sh 30-security apply -input=false -auto-approve
	scripts/tf.sh 40-data apply -input=false -auto-approve -var enable_rds=true
	scripts/tf.sh 50-ec2 apply -input=false -auto-approve
	scripts/tf.sh 52-ecs apply -input=false -auto-approve -var enable_service=true
	scripts/tf.sh 60-events apply -input=false -auto-approve -var alert_email=$(ALERT_EMAIL)
	scripts/tf.sh 70-ml apply -input=false -auto-approve
	scripts/tf.sh 80-delivery apply -input=false -auto-approve -var enable_deploy_stage=true
	scripts/tf.sh 90-observe apply -input=false -auto-approve
	scripts/tf.sh 95-cost apply -input=false -auto-approve -var alert_email=$(ALERT_EMAIL)

down:
	@for s in $(REVERSE); do echo "== destroy $$s"; scripts/tf.sh $$s destroy -input=false -auto-approve || exit 1; done

# Turn off the hourly-billed pieces but keep everything else.
pause:
	scripts/tf.sh 20-network apply -input=false -auto-approve -var enable_nat=false
	scripts/tf.sh 30-security apply -input=false -auto-approve -var enable_secretsmanager_endpoint=false
	scripts/tf.sh 40-data apply -input=false -auto-approve -var enable_rds=false
	scripts/tf.sh 52-ecs apply -input=false -auto-approve -var enable_service=false
	scripts/tf.sh 55-eks apply -input=false -auto-approve -var enable_eks=false
	scripts/tf.sh 70-ml apply -input=false -auto-approve -var enable_endpoint=false
	scripts/tf.sh 50-ec2 apply -input=false -auto-approve -var enable_ssm_endpoints=false
	scripts/tf.sh 80-delivery apply -input=false -auto-approve
	scripts/tf.sh 90-observe apply -input=false -auto-approve

verify:
	scripts/verify.sh

smoke:
	scripts/verify.sh --smoke --poison

test:
	terraform -chdir=modules/s3-bucket init -backend=false -input=false >/dev/null && terraform -chdir=modules/s3-bucket test
	terraform -chdir=modules/vpc init -backend=false -input=false >/dev/null && terraform -chdir=modules/vpc test

# The very last step, after `make down`. Asks you to type the account id.
destroy-bootstrap:
	scripts/destroy-bootstrap.sh
