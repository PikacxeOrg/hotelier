#!/bin/bash
set -e

# Detect kubectl
detect_kubectl() {
    if command -v kubectl >/dev/null 2>&1; then
        echo "kubectl"
        return
    fi

    # Fallback to Minikube
    if command -v minikube >/dev/null 2>&1; then
        echo "minikube kubectl --"
        return
    fi

    echo "ERROR: kubectl not found. Install kubectl or Minikube."
    exit 1
}
