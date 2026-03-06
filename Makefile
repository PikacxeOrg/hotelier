# -------------------------------
# Global
# -------------------------------
NAMESPACE = hotelier
MONITORING_NS = observability

# Path helpers
SCRIPT_DIR = etc/scripts

# Detect kubectl dynamically (real kubectl or minikube kubectl)
KCTL = $(shell command -v kubectl >/dev/null 2>&1 && echo kubectl || echo minikube kubectl --)

.PHONY: start stop delete dashboard ip build-images build-service rebuild-services \
	    deploy undeploy monitoring-install monitoring-uninstall \
	    setup-all logs-loki logs-promtail \
	    health-docker health-k8s health \
	    verify-db-docker verify-db-k8s status \
	    swarm-deploy swarm-build-push swarm-down swarm-status

# -------------------------------
# Minikube
# -------------------------------
start:
	minikube start --cpus=12 --memory=20480mb --driver=docker
	@echo "Enabling ingress addon..."
	minikube addons enable ingress 2>/dev/null || true
	@echo "Waiting for ingress controller..."
	$(KCTL) wait --for=condition=available --timeout=120s deployment/ingress-nginx-controller -n ingress-nginx 2>/dev/null || true
	$(KCTL) patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec":{"type":"LoadBalancer"}}' 2>/dev/null || true
	$(KCTL) apply -f etc/kubernetes/namespace.yaml
	$(KCTL) apply -f etc/kubernetes/secrets/hotelier-secrets.yaml

stop:
	minikube stop

delete:
	minikube delete

dashboard:
	minikube dashboard

ip:
	minikube ip

## Build all service images in-cluster via kaniko.
## Optional: TAG=<tag>  (default: latest)
build-images:
	chmod +x $(SCRIPT_DIR)/build-images-kaniko.sh
	$(SCRIPT_DIR)/build-images-kaniko.sh --all $(if $(TAG),--tag $(TAG))

## Build a single service image.  Requires: SERVICE=<name>
## Optional: TAG=<tag>  (default: latest)
## Example:  make build-service SERVICE=search-service TAG=v1.2.3
build-service:
	@test -n "$(SERVICE)" || (echo "ERROR: SERVICE is required. Usage: make build-service SERVICE=<name>"; exit 1)
	chmod +x $(SCRIPT_DIR)/build-images-kaniko.sh
	$(SCRIPT_DIR)/build-images-kaniko.sh --service $(SERVICE) $(if $(TAG),--tag $(TAG))

rebuild-services:
	make build-images $(if $(TAG),TAG=$(TAG))
	$(KCTL) rollout restart deployment -n $(NAMESPACE)
	@echo "Waiting for services to restart..."
	sleep 5
	$(KCTL) get pods -n $(NAMESPACE)


# -------------------------------
# FULL SETUP (WRAPS SCRIPT)
# -------------------------------
setup-all:
	chmod +x $(SCRIPT_DIR)/setup-all.sh
	$(SCRIPT_DIR)/setup-all.sh

# -------------------------------
# Logs
# -------------------------------
logs-loki:
	$(KCTL) logs -n $(MONITORING_NS) -l app.kubernetes.io/name=loki --tail=200 -f

logs-promtail:
	$(KCTL) logs -n $(MONITORING_NS) -l app.kubernetes.io/name=promtail --tail=200 -f


# -------------------------------
# Health Checks
# -------------------------------
health-docker:
	chmod +x $(SCRIPT_DIR)/health-check.sh
	$(SCRIPT_DIR)/health-check.sh docker

health-k8s:
	chmod +x $(SCRIPT_DIR)/health-check.sh
	$(SCRIPT_DIR)/health-check.sh k8s

health:
	@echo "Choose environment: 'make health-docker' or 'make health-k8s'"

verify-db-docker:
	chmod +x $(SCRIPT_DIR)/verify-databases.sh
	$(SCRIPT_DIR)/verify-databases.sh docker

verify-db-k8s:
	chmod +x $(SCRIPT_DIR)/verify-databases.sh
	$(SCRIPT_DIR)/verify-databases.sh k8s

# -------------------------------
# Utility
# -------------------------------
status:
	$(KCTL) get pods -A

# -------------------------------
# Docker Swarm
# -------------------------------
swarm-deploy:
	chmod +x $(SCRIPT_DIR)/swarm-deploy.sh
	$(SCRIPT_DIR)/swarm-deploy.sh all

swarm-build-push:
	chmod +x $(SCRIPT_DIR)/swarm-deploy.sh
	$(SCRIPT_DIR)/swarm-deploy.sh build-push

swarm-down:
	chmod +x $(SCRIPT_DIR)/swarm-deploy.sh
	$(SCRIPT_DIR)/swarm-deploy.sh down

swarm-status:
	docker stack services hotelier
