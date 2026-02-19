#!/bin/bash

# Build all Docker images inside Minikube's Docker daemon
# This makes images available to Kubernetes without needing a registry

set -e

SERVICES=(
    "availability-service"
    "accommodation-service"
    "identity-service"
    "notification-service"
    "rating-service"
    "reservation-service"
    "search-service"
    "cdn-service"
)

echo "======================================"
echo "Building Hotelier service images"
echo "======================================"
echo ""

# Check if minikube is running
if ! minikube status > /dev/null 2>&1; then
    echo "Minikube is not running. Please start it first:"
    echo "   make start"
    exit 1
fi

echo "Minikube is running"
echo ""

# Configure shell to use minikube's Docker daemon
echo "Configuring Docker to use Minikube's daemon..."
eval $(minikube docker-env)
echo "Docker configured to use Minikube daemon"
echo ""

# Build each service
for service in "${SERVICES[@]}"; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Building: $service"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    SERVICE_DIR="services/$service"
    IMAGE_NAME="hotelier-$service:latest"
    
    if [ ! -d "$SERVICE_DIR" ]; then
        echo "Service directory not found: $SERVICE_DIR"
        continue
    fi
    
    # Build the image
    docker build -t "$IMAGE_NAME" "$SERVICE_DIR"
    
    if [ $? -eq 0 ]; then
        echo "Successfully built: $IMAGE_NAME"
    else
        echo "Failed to build: $IMAGE_NAME"
        exit 1
    fi
    
    echo ""
done

echo "======================================"
echo " All images built successfully!"
echo "======================================"
echo ""
echo "Images available in Minikube:"
docker images | grep hotelier
echo ""
echo "To verify images in Kubernetes, restart pods:"
echo "  kubectl rollout restart deployment -n hotelier"
echo ""
echo "To reset Docker environment to host:"
echo "  eval \$(minikube docker-env -u)"
