#!/bin/bash

# Build all container images using Kaniko inside Kubernetes.
#
# Performance features:
#   --cache-repo  → dedicated layer cache in the in-cluster registry; on
#                   subsequent runs the dotnet restore / npm ci layers are
#                   skipped entirely (≈ 60-80 % faster after first build).
#   cache-warmer intentionally omitted: kaniko-project/warmer only works with
#                   PV-based --cache-dir, not with registry --cache-repo.
#   --snapshot-mode=redo  → 10-20 % faster than the default "full" mode.
#   --compressed-caching=false → skips compression for local cache I/O.
#   PersistentVolumeClaim on registry → layers survive Minikube restarts,
#                   preventing the multi-GB re-pull on every session.
#   Parallel jobs → all services build at the same time.
#
# NOTE: --cache-repo is self-managing. The first build is slow (executor pushes
# all layers to the cache registry). Every subsequent build reuses them.
# No warmer needed — kaniko-project/warmer is for PV-based caching only.

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
    "frontend"
)

declare -A SERVICE_DIRS
SERVICE_DIRS[frontend]="web/hotelier-frontend"

NAMESPACE="hotelier"
REGISTRY="registry.kube-system.svc.cluster.local:5000"
CACHE_REPO="$REGISTRY/kaniko-cache"
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
echo " Building Hotelier images with Kaniko"
echo "======================================"
echo ""

if command -v minikube >/dev/null 2>&1; then
    if ! minikube status > /dev/null 2>&1; then
        echo "Minikube is not running. Please start it first:"
        echo "   make start"
        exit 1
    fi
    echo "Minikube is running"
fi

# ---------------------------------------------------------------------------
# Ensure in-cluster registry with a PersistentVolumeClaim.
# The PVC ensures cached image layers survive Minikube/pod restarts,
# avoiding multi-GB re-downloads on every build session.
# ---------------------------------------------------------------------------
ensure_registry() {
    echo "Checking for in-cluster registry..."

    if $KUBECTL get deployment registry -n kube-system > /dev/null 2>&1; then
        echo "Registry already running"
        return
    fi

    echo "Deploying in-cluster registry with persistent storage..."
    $KUBECTL apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: registry-data
  namespace: kube-system
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
---
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
          env:
            - name: REGISTRY_STORAGE_DELETE_ENABLED
              value: "true"
          volumeMounts:
            - name: data
              mountPath: /var/lib/registry
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: registry-data
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
    echo "Registry is ready (data persisted to PVC)"
}

ensure_registry
echo ""
echo "Cache repo: $CACHE_REPO  (first build populates it — subsequent builds reuse layers)"
echo ""

# ---------------------------------------------------------------------------
# Phase 1: tar build contexts → ConfigMaps → launch all Kaniko jobs
# ---------------------------------------------------------------------------
LAUNCHED_SERVICES=()

for service in "${SERVICES[@]}"; do
    SERVICE_DIR="${SERVICE_DIRS[$service]:-services/$service}"
    IMAGE_NAME="hotelier-$service"
    FULL_IMAGE="$REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
    JOB_NAME="kaniko-build-${service}"

    if [ ! -d "$SERVICE_DIR" ]; then
        echo "WARNING: Service directory not found: $SERVICE_DIR — skipping"
        continue
    fi

    echo "Launching build: $service"

    $KUBECTL delete job "$JOB_NAME" -n "$NAMESPACE" --ignore-not-found > /dev/null 2>&1

    EXCLUDES=""
    if [ -f "$SERVICE_DIR/.dockerignore" ]; then
        while IFS= read -r pattern || [ -n "$pattern" ]; do
            pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [ -z "$pattern" ] && continue
            [[ "$pattern" == \#* ]] && continue
            EXCLUDES="$EXCLUDES --exclude=$pattern"
        done < "$SERVICE_DIR/.dockerignore"
    fi
    eval tar -czf /tmp/kaniko-context-${service}.tar.gz $EXCLUDES -C "$SERVICE_DIR" .

    $KUBECTL delete configmap "kaniko-context-${service}" -n "$NAMESPACE" --ignore-not-found > /dev/null 2>&1
    $KUBECTL create configmap "kaniko-context-${service}" \
        --from-file=context.tar.gz=/tmp/kaniko-context-${service}.tar.gz \
        -n "$NAMESPACE"

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
            - "--cache=true"
            - "--cache-repo=$CACHE_REPO"
            - "--snapshot-mode=redo"
            - "--compressed-caching=false"
            - "--insecure"
            - "--skip-tls-verify"
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

    LAUNCHED_SERVICES+=("$service")
    rm -f /tmp/kaniko-context-${service}.tar.gz
done

echo ""
echo "All ${#LAUNCHED_SERVICES[@]} build jobs launched — waiting for completion..."
echo ""

# ---------------------------------------------------------------------------
# Phase 2: Wait for all jobs
# ---------------------------------------------------------------------------
FAILED_SERVICES=()

for service in "${LAUNCHED_SERVICES[@]}"; do
    JOB_NAME="kaniko-build-${service}"

    DEADLINE=$((SECONDS + 600))
    BUILD_RESULT=""
    while [ $SECONDS -lt $DEADLINE ]; do
        if $KUBECTL wait --for=condition=complete --timeout=5s job/"$JOB_NAME" -n "$NAMESPACE" 2>/dev/null; then
            BUILD_RESULT="success"
            break
        fi
        if $KUBECTL wait --for=condition=failed --timeout=1s job/"$JOB_NAME" -n "$NAMESPACE" 2>/dev/null; then
            BUILD_RESULT="failed"
            break
        fi
    done

    if [ "$BUILD_RESULT" = "success" ]; then
        echo "  + $service"
    else
        echo "  - $service — FAILED"
        $KUBECTL logs job/"$JOB_NAME" -n "$NAMESPACE" --tail=20 2>/dev/null || true
        FAILED_SERVICES+=("$service")
    fi

    $KUBECTL delete configmap "kaniko-context-${service}" -n "$NAMESPACE" --ignore-not-found > /dev/null 2>&1
done

echo ""

if [ ${#FAILED_SERVICES[@]} -gt 0 ]; then
    echo "ERROR: ${#FAILED_SERVICES[@]} service(s) failed: ${FAILED_SERVICES[*]}"
    exit 1
fi

echo "======================================"
echo " All images built with Kaniko!"
echo "======================================"
echo ""
echo "Cache repo:   $CACHE_REPO  (persisted — survives Minikube restarts)"
echo "Built images: $REGISTRY/hotelier-<service>:$IMAGE_TAG"
echo ""
echo "To restart deployments with new images:"
echo "  kubectl rollout restart deployment -n $NAMESPACE"
