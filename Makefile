# -------------------------------
# Global
# -------------------------------
NAMESPACE = hotelier
MONITORING_NS = observability

# Path helpers
SCRIPT_DIR = etc/scripts

# Detect kubectl dynamically (real kubectl or minikube kubectl)
KCTL = $(shell command -v kubectl >/dev/null 2>&1 && echo kubectl || echo minikube kubectl --)

.PHONY: start stop delete dashboard ip build-images rebuild-services \
	    deploy undeploy monitoring-install monitoring-uninstall \
	    setup-all logs-loki logs-promtail \
	    health-docker health-k8s health \
	    verify-db-docker verify-db-k8s status

# -------------------------------
# Minikube
# -------------------------------
start:
	minikube start --cpus=8 --memory=12288 --driver=docker
	$(KCTL) apply -f etc/kubernetes/namespace.yaml
	$(KCTL) apply -f etc/kubernetes/secrets/hotelier-secrets.yaml
	$(KCTL) apply -f etc/kubernetes/ingress.yaml

stop:
	minikube stop

delete:
	minikube delete

dashboard:
	minikube dashboard

ip:
	minikube ip

build-images:
	chmod +x $(SCRIPT_DIR)/build-images-kaniko.sh
	$(SCRIPT_DIR)/build-images-kaniko.sh

rebuild-services:
	make build-images
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
