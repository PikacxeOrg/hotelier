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
	minikube start --cpus=8 --memory=12288
	kubectl apply -f kubernetes/namespace.yaml
	kubectl apply -f kubernetes/secrets/hotelier-secrets.yaml
	kubectl apply -f kubernetes/ingress.yaml
stop:
	minikube stop

delete:
	minikube delete

dashboard:
	minikube dashboard

ip:
	minikube ip


# -------------------------------
# FULL SETUP (WRAPS SCRIPT)
# -------------------------------
setup-all:
	chmod +x $(SCRIPT_DIR)/setup-all.sh
	cd $(SCRIPT_DIR) && ./setup-all.sh


# -------------------------------
# Monitoring Stack
# -------------------------------
monitoring-install:
	chmod +x $(SCRIPT_DIR)/install-monitoring.sh
	cd $(SCRIPT_DIR) && ./install-monitoring.sh

monitoring-uninstall:
	helm uninstall grafana -n $(MONITORING_NS) || true
	helm uninstall loki -n $(MONITORING_NS) || true
	helm uninstall prom-stack -n $(MONITORING_NS) || true


# -------------------------------
# Microservices Deployment
# -------------------------------
deploy:
	chmod +x $(SCRIPT_DIR)/install-services.sh
	cd $(SCRIPT_DIR) && ./install-services.sh

undeploy:
	helm uninstall identity -n $(NAMESPACE) || true
	helm uninstall reservation -n $(NAMESPACE) || true
	helm uninstall search -n $(NAMESPACE) || true
	helm uninstall rating -n $(NAMESPACE) || true
	helm uninstall availability -n $(NAMESPACE) || true
	helm uninstall accommodation -n $(NAMESPACE) || true
	helm uninstall notification -n $(NAMESPACE) || true


# -------------------------------
# Logs
# -------------------------------
logs-loki:
	$(KCTL) logs -n $(MONITORING_NS) -l app.kubernetes.io/name=loki --tail=200 -f

logs-promtail:
	$(KCTL) logs -n $(MONITORING_NS) -l app.kubernetes.io/name=promtail --tail=200 -f


# -------------------------------
# Utility
# -------------------------------
status:
	$(KCTL) get pods -A
