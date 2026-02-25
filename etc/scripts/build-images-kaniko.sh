#!/bin/bash

# Build all container images using Kaniko inside Kubernetes
# Kaniko builds images without requiring a Docker daemon
# Images are pushed to a local registry running in the cluster

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

NAMESPACE="hotelier"
REGISTRY="localhost:5000"
IMAGE_TAG="${1:-latest}"

# Detect kubectl
if command -v kubectl >/dev/null 2>&1; then
    KUBECTL="kubectl"
elif command -v minikube >/dev/null 2>&1; then
    KUBECTL="minikube kubectl --"
else
    echo "ERROR: kubectl not found. Install kubectl or Minikube."
    exit 1
fi

echo "======================================"
echo "Building Hotelier images with Kaniko"
echo "======================================"
echo ""

# Check if minikube is running
if command -v minikube >/dev/null 2>&1; then
    if ! minikube status > /dev/null 2>&1; then
        echo "Minikube is not running. Please start it first:"
        echo "   make start"
        exit 1
    fi
    echo "Minikube is running"
fi

# Ensure local registry is available
ensure_registry() {
    echo "Checking for in-cluster registry..."

    if $KUBECTL get deployment registry -n kube-system > /dev/null 2>&1; then
        echo "Registry already running"
        return
    fi

    echo "Deploying in-cluster registry..."
    $KUBECTL apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: registry
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: registry
  template:
    metadata:
      labels:
        app: registry
    spec:
      containers:
        - name: registry
          image: registry:2
          ports:
            - containerPort: 5000
---
apiVersion: v1
kind: Service
metadata:
  name: registry
  namespace: kube-system
spec:
  type: NodePort
  selector:
    app: registry
  ports:
    - port: 5000
      targetPort: 5000
      nodePort: 30500
EOF

    echo "Waiting for registry to be ready..."
    $KUBECTL wait --for=condition=available --timeout=60s deployment/registry -n kube-system
    echo "Registry is ready"
}

ensure_registry
echo ""

# Build each service using a Kaniko Job
for service in "${SERVICES[@]}"; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Building: $service"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    SERVICE_DIR="services/$service"
    IMAGE_NAME="hotelier-$service"
    FULL_IMAGE="registry.kube-system.svc.cluster.local:5000/$IMAGE_NAME:$IMAGE_TAG"
    JOB_NAME="kaniko-build-${service}"

    if [ ! -d "$SERVICE_DIR" ]; then
        echo "WARNING: Service directory not found: $SERVICE_DIR — skipping"
        echo ""
        continue
    fi

    # Clean up any previous build job
    $KUBECTL delete job "$JOB_NAME" -n "$NAMESPACE" --ignore-not-found > /dev/null 2>&1

    # Create a ConfigMap with the build context (tar the source)
    echo "  Creating build context..."
    tar -czf /tmp/kaniko-context-${service}.tar.gz -C "$SERVICE_DIR" .

    # Delete old configmap if it exists
    $KUBECTL delete configmap "kaniko-context-${service}" -n "$NAMESPACE" --ignore-not-found > /dev/null 2>&1

    # Upload build context as a configmap (for small services) or use a PVC/volume
    # For larger contexts, consider using a PersistentVolumeClaim or git init container
    $KUBECTL create configmap "kaniko-context-${service}" \
        --from-file=context.tar.gz=/tmp/kaniko-context-${service}.tar.gz \
        -n "$NAMESPACE"

    # Create and run the Kaniko build job
    $KUBECTL apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: $JOB_NAME
  namespace: $NAMESPACE
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      initContainers:
        - name: extract-context
          image: busybox:1.36
          command: ["sh", "-c", "cp /context/context.tar.gz /workspace/context.tar.gz && cd /workspace && tar -xzf context.tar.gz && rm context.tar.gz"]
          volumeMounts:
            - name: context
              mountPath: /context
            - name: workspace
              mountPath: /workspace
      containers:
        - name: kaniko
          image: gcr.io/kaniko-project/executor:latest
          args:
            - "--context=dir:///workspace"
            - "--destination=$FULL_IMAGE"
            - "--insecure"
            - "--skip-tls-verify"
            - "--cache=true"
          volumeMounts:
            - name: workspace
              mountPath: /workspace
      volumes:
        - name: context
          configMap:
            name: kaniko-context-${service}
        - name: workspace
          emptyDir: {}
EOF

    echo "  Waiting for Kaniko build to complete..."
    if $KUBECTL wait --for=condition=complete --timeout=300s job/"$JOB_NAME" -n "$NAMESPACE" 2>/dev/null; then
        echo "  Successfully built: $FULL_IMAGE"
    else
        echo "  Build failed for $service. Logs:"
        $KUBECTL logs job/"$JOB_NAME" -n "$NAMESPACE" --tail=30 2>/dev/null || true
        echo ""
        echo "  ERROR: Failed to build $service"
        exit 1
    fi

    # Clean up context configmap
    $KUBECTL delete configmap "kaniko-context-${service}" -n "$NAMESPACE" --ignore-not-found > /dev/null 2>&1
    rm -f /tmp/kaniko-context-${service}.tar.gz

    echo ""
done

echo "======================================"
echo " All images built with Kaniko!"
echo "======================================"
echo ""
echo "Images available in the cluster registry:"
echo "  Registry: registry.kube-system.svc.cluster.local:5000"
echo ""
for service in "${SERVICES[@]}"; do
    echo "  - hotelier-$service:$IMAGE_TAG"
done
echo ""
echo "To restart deployments with new images:"
echo "  kubectl rollout restart deployment -n $NAMESPACE"
