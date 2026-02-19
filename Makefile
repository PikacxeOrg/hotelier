# -------------------------------
# Global
# -------------------------------
NAMESPACE = hotelier
MONITORING_NS = monitoring

# Path helpers
SCRIPT_DIR = etc/scripts
KUBE_TOOLS = $(SCRIPT_DIR)/kube-tools.sh

# Detect kubectl dynamically (real kubectl or minikube kubectl)
KCTL = $(shell bash $(KUBE_TOOLS) && detect_kubectl)

# -------------------------------
# Minikube
# -------------------------------
start:
	minikube start --cpus=8 --memory=12288 --driver=docker
	kubectl apply -f etc/kubernetes/namespace.yaml
	kubectl apply -f etc/kubernetes/secrets/hotelier-secrets.yaml
	kubectl apply -f etc/kubernetes/ingress.yaml

stop:
	minikube stop

delete:
	minikube delete

dashboard:
	minikube dashboard

ip:
	minikube ip

build-images:
	chmod +x $(SCRIPT_DIR)/build-images-minikube.sh
	$(SCRIPT_DIR)/build-images-minikube.sh

rebuild-services:
	make build-images
	kubectl rollout restart deployment -n hotelier
	@echo "Waiting for services to restart..."
	sleep 5
	kubectl get pods -n hotelier


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
	kubectl logs -n $(MONITORING_NS) -l app.kubernetes.io/name=loki --tail=200 -f

logs-promtail:
	kubectl logs -n $(MONITORING_NS) -l app.kubernetes.io/name=promtail --tail=200 -f


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
	kubectl get pods -A
