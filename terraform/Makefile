export REGION=eu-west-2
export REPO_NAME=shirwalab_blog

ifndef ENVNAME
$(error ENVNAME is not set)
endif

clean:
	rm -rf .terraform

workspace:
	terraform workspace select $(ENVNAME) || terraform workspace new $(ENVNAME)

init:
	terraform get
	terraform init \
		-get=true \
		-backend=true \
		-backend-config="bucket=$(ENVNAME)-tfstate" \
		-backend-config="workspace_key_prefix=env:" \
		-backend-config="key=$(REPO_NAME).tfstate" \
		-backend-config="region=$(REGION)" \
		-backend-config="encrypt=true" \
		$(INIT_EXTRA_ARGS)

plan: workspace
	terraform plan -var "envname=$(ENVNAME)" -var-file=tfvars/$(ENVNAME).tfvars $(EXTRA_ARGS)

ci-plan: workspace
	terraform plan -var "envname=$(ENVNAME)" -var-file=tfvars/$(ENVNAME).tfvars -out=plan.out $(EXTRA_ARGS)

planjson: workspace
	terraform plan -out tfplan.binary -var "envname=$(ENVNAME)" -var-file=tfvars/$(ENVNAME).tfvars $(EXTRA_ARGS)
	terraform show -json tfplan.binary > tfplan.json
	rm tfplan.binary

apply: workspace
	terraform apply -var "envname=$(ENVNAME)" -var-file=tfvars/$(ENVNAME).tfvars $(EXTRA_ARGS)

ci-apply: workspace
	terraform apply $(EXTRA_ARGS) plan.out

plan-destroy: workspace
	terraform plan -destroy -var "envname=$(ENVNAME)" -var-file=tfvars/$(ENVNAME).tfvars $(EXTRA_ARGS)

destroy: workspace
	terraform destroy -var "envname=$(ENVNAME)" -var-file=tfvars/$(ENVNAME).tfvars $(EXTRA_ARGS)
