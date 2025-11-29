# -------------------------------
# Global
# -------------------------------
NAMESPACE=default
MONITORING_NS=monitoring

# -------------------------------
# Minikube
# -------------------------------
start:
	minikube start --cpus=4 --memory=8192

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
	chmod +x infrastructure/scripts/setup-all.sh
	cd infrastructure/scripts && ./setup-all.sh


# -------------------------------
# Monitoring Stack
# -------------------------------
monitoring-install:
	chmod +x infrastructure/scripts/install-monitoring.sh
	cd infrastructure/scripts && ./install-monitoring.sh

monitoring-uninstall:
	helm uninstall grafana -n $(MONITORING_NS) || true
	helm uninstall promtail -n $(MONITORING_NS) || true
	helm uninstall loki -n $(MONITORING_NS) || true
	helm uninstall prom -n $(MONITORING_NS) || true


# -------------------------------
# Microservices Deployment (wrapping script)
# -------------------------------
deploy:
	chmod +x infrastructure/scripts/install-services.sh
	cd infrastructure/scripts && ./install-services.sh

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
	kubectl logs -n $(MONITORING_NS) deployment/loki

logs-promtail:
	kubectl logs -n $(MONITORING_NS) -l app=promtail


# -------------------------------
# Utility
# -------------------------------
status:
	kubectl get pods -A
