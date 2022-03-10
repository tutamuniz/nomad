PKG_PATH = $(shell pwd)/../../pkg/linux_amd64/nomad

# deploy for quick local development testing

plan: tidy
	terraform plan -auto-approve \
		-var="nomad_local_binary=$(PKG_PATH)" \
		-var="client_count_ubuntu_bionic_amd64=2" \
		-var="client_count_windows_2016_amd64=0"

apply: tidy
	terraform apply -auto-approve \
		-var="nomad_local_binary=$(PKG_PATH)" \
		-var="client_count_ubuntu_bionic_amd64=2" \
		-var="client_count_windows_2016_amd64=0"
	terraform output environment

clean: destroy tidy

destroy:
	terraform destroy -auto-approve \
		-var="nomad_local_binary=$(PKG_PATH)" \
		-var="client_count_ubuntu_bionic_amd64=2" \
		-var="client_count_windows_2016_amd64=0"

# deploy what's in E2E nightly

plan_full: tidy
	terraform plan -auto-approve

apply_full: tidy
	terraform apply -auto-approve

clean_full: destroy tidy

destroy_full:
	terraform destroy -auto-approve

# util

tidy:
	rm -rf keys
	mkdir keys
	chmod 0700 keys
	rm -rf uploads/*
	git checkout uploads/README.md
	rm -f terraform.tfstate.*.backup
