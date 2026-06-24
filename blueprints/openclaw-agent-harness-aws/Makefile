SHELL := /usr/bin/env bash

.PHONY: preflight fmt validate init plan apply destroy smoke check-routes

preflight:
	./scripts/preflight.sh

fmt:
	terraform fmt -recursive

validate:
	terraform validate

init:
	terraform init

plan:
	terraform plan

apply:
	terraform apply

destroy:
	terraform destroy

smoke:
	@echo "Run the output command from terraform output -raw ssm_start_session, then:"
	@echo "  POLICY_MODE=$$(terraform output -raw policy_mode 2>/dev/null || echo monitor) /opt/openclaw-vca/verify-egress.sh"

check-routes:
	./scripts/check-routes.sh
