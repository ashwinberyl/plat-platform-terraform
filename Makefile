# Stacks apply in this order and destroy in the reverse order.
STACKS := 10-identity 20-network 30-security 40-data 50-ec2 52-ecs 55-eks 60-events 70-ml 80-delivery 90-observe 95-cost
REVERSE := $(shell echo $(STACKS) | tr ' ' '\n' | tac | tr '\n' ' ')

.PHONY: fmt validate plan up down pause verify smoke test

fmt:
	terraform fmt -recursive

validate:
	@for d in bootstrap stacks/* modules/* labs/*; do \
	  echo "== $$d"; terraform -chdir=$$d init -backend=false -input=false >/dev/null && terraform -chdir=$$d validate || exit 1; \
	done

plan:
	@for s in $(STACKS); do echo "== plan $$s"; scripts/tf.sh $$s plan -input=false || exit 1; done

up:
	@for s in $(STACKS); do echo "== apply $$s"; scripts/tf.sh $$s apply -input=false -auto-approve || exit 1; done

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

verify:
	scripts/verify.sh

smoke:
	scripts/verify.sh --smoke --poison

test:
	terraform -chdir=modules/s3-bucket init -backend=false -input=false >/dev/null && terraform -chdir=modules/s3-bucket test
	terraform -chdir=modules/vpc init -backend=false -input=false >/dev/null && terraform -chdir=modules/vpc test
