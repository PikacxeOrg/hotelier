#!/bin/bash

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install prom prometheus-community/kube-prometheus-stack -n monitoring
helm install loki grafana/loki-stack -n monitoring --set grafana.enabled=false --set prometheus.enabled=false
helm install promtail grafana/promtail -n monitoring --set loki.serviceName=loki
helm install grafana grafana/grafana -n monitoring --set service.type=NodePort --set adminPassword='admin'

kubectl -n monitoring wait --for=condition=available --timeout=300s deployment/prom-grafana