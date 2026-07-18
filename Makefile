.PHONY: tools up mvp containers stop clean status

PROFILE := dc34
export MINIKUBE_PROFILE := $(PROFILE)
export DOCKER_CONTEXT := colima-$(PROFILE)

SCENARIOS := mvp

tools:
	@command -v brew >/dev/null 2>&1 || { echo "Error: Homebrew not installed. Install from https://brew.sh"; exit 1; }
	brew bundle

up: tools
	colima start -p $(PROFILE) --cpu 4 --memory 8
	minikube start --driver=docker --cpus=4 --memory=6144 --cni=cilium --addons=metrics-server
	helmfile sync --enable-live-output
	@echo ""
	@echo "When done with the competition:"
	@echo "  make stop    pause the cluster (state preserved)"
	@echo "  make clean   tear down everything (VM disk and all)"

stop:
	minikube stop
	colima stop -p $(PROFILE)

clean:
	-minikube delete
	-colima delete -p $(PROFILE) --data --force
	-colima prune -p $(PROFILE) --force
	@kubectl config delete-context $(PROFILE) >/dev/null 2>&1 || true
	@kubectl config delete-cluster $(PROFILE) >/dev/null 2>&1 || true
	@kubectl config delete-user $(PROFILE) >/dev/null 2>&1 || true

status:
	colima status -p $(PROFILE)
	minikube status
