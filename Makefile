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
# Utility
# -------------------------------
status:
	$(KCTL) get pods -A
