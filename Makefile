.PHONY: tools up stop clean status load-challenge

PROFILE := dc34
export MINIKUBE_PROFILE := $(PROFILE)
export DOCKER_CONTEXT := colima-$(PROFILE)

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
	@echo "  make clean   tear down the cluster and VM (disk and all)"

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

CHALLENGE_IMAGE = ghcr.io/blueteamvillage/challenge-$(N):latest

# Pull one challenge image and load it into the dc34 node with the right Docker
# context and minikube profile already set. Run `docker login ghcr.io` first
# once the organizers hand out credentials. The pull is best-effort so an image
# already present locally (or loaded another way) still gets loaded — but the
# load only runs if the image is really there, so a pull that 401s tells you to
# log in instead of failing later on a reference minikube can't find.
# For every challenge image in one pass, use scripts/pull-btv-images.sh.
# Usage: make load-challenge N=000   (or N=023-pro, N=001-s001-beginner, ...)
load-challenge:
	@test -n "$(N)" || { echo "Usage: make load-challenge N=<NNN | NNN-beginner | NNN-pro | 001-s<NNN>-beginner | 001-s<NNN>-pro>   e.g. N=000"; exit 1; }
	@docker info >/dev/null 2>&1 || { echo "Error: the Docker daemon isn't reachable on context $(DOCKER_CONTEXT). Run 'make up' (or start colima) first."; exit 1; }
	-docker pull $(CHALLENGE_IMAGE)
	@docker image inspect $(CHALLENGE_IMAGE) >/dev/null 2>&1 || { \
		echo ""; \
		echo "Error: $(CHALLENGE_IMAGE) isn't in the local Docker cache, so there's nothing to load."; \
		echo "Challenge images are private until the CTF opens — authenticate first:"; \
		echo "  docker login ghcr.io -u <your-github-username>"; \
		echo "then re-run: make load-challenge N=$(N)"; \
		exit 1; \
	}
	minikube image load $(CHALLENGE_IMAGE)
