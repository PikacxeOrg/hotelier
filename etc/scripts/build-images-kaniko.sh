#!/bin/bash
# Kaniko image builder - builds service images via per-service Kubernetes Jobs
set -euo pipefail

# ========================================
# CONFIGURATION
# ========================================
ALL_SERVICES=(
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

NAMESPACE="hotelier"
REGISTRY="registry.kube-system.svc.cluster.local:5000"
CACHE_REPO="$REGISTRY/kaniko-cache"

# ========================================
# ARGUMENT PARSING
# ========================================
IMAGE_TAG="latest"
BUILD_SERVICES=()

usage() {
    echo "Usage: $0 [--all | --service <name> [--service <name> ...]] [--tag <tag>]"
    echo ""
    echo "  --all                Build all services (default if no flag given)"
    echo "  --service <name>     Build a specific service (repeatable)"
    echo "  --tag <tag>          Image tag (default: latest)"
    echo ""
    echo "  Known services: ${ALL_SERVICES[*]}"
    exit "${1:-1}"
}

if [ $# -eq 0 ]; then
    BUILD_SERVICES=("${ALL_SERVICES[@]}")
else
    while [ $# -gt 0 ]; do
        case "$1" in
            --help|-h)
                usage 0
                ;;
            --all)
                BUILD_SERVICES=("${ALL_SERVICES[@]}")
                shift
                ;;
            --service)
                [ -z "${2:-}" ] && { echo "ERROR: --service requires a name"; usage; }
                BUILD_SERVICES+=("$2")
                shift 2
                ;;
            --tag)
                [ -z "${2:-}" ] && { echo "ERROR: --tag requires a value"; usage; }
                IMAGE_TAG="$2"
                shift 2
                ;;
            -*)
                echo "ERROR: Unknown flag: $1"; usage
                ;;
            *)
                # Backwards-compat: bare positional arg treated as tag
                IMAGE_TAG="$1"
                BUILD_SERVICES=("${ALL_SERVICES[@]}")
                shift
                ;;
        esac
    done
fi

if [ ${#BUILD_SERVICES[@]} -eq 0 ]; then
    BUILD_SERVICES=("${ALL_SERVICES[@]}")
fi

# Validate --service names
for _svc in "${BUILD_SERVICES[@]}"; do
    valid=0
    for _known in "${ALL_SERVICES[@]}"; do
        [ "$_svc" = "$_known" ] && valid=1 && break
    done
    if [ "$valid" -eq 0 ]; then
        echo "ERROR: Unknown service '$_svc'"
        echo "Known services: ${ALL_SERVICES[*]}"
        exit 1
    fi
done

JOB_TAG=$(echo "$IMAGE_TAG" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | cut -c1-50)
JOB_NAME="kaniko-build-${JOB_TAG}"

echo "Services : ${BUILD_SERVICES[*]}"
echo "Tag      : $IMAGE_TAG"
echo ""

# ========================================
# KUBECTL DETECTION
# ========================================
if command -v kubectl >/dev/null 2>&1; then
    KUBECTL="kubectl"
elif command -v minikube >/dev/null 2>&1; then
    KUBECTL="minikube kubectl --"
else
    echo "ERROR: kubectl not found. Install kubectl or minikube."
    exit 1
fi

# ========================================
# CLEANUP HELPER (called on success and failure)
# ========================================
cleanup() {
    $KUBECTL delete jobs -n "$NAMESPACE" -l app.kubernetes.io/managed-by=kaniko-builder --ignore-not-found >/dev/null 2>&1 || true
}

# ========================================
# ONE-TIME PREREQUISITES
# ========================================
echo "Checking prerequisites..."

# 1. Ensure Minikube is running (if applicable)
if command -v minikube >/dev/null 2>&1; then
    if ! minikube status >/dev/null 2>&1; then
        echo "ERROR: Minikube is not running. Start it first: make start"
        exit 1
    fi
    echo "  Minikube is running"
fi

# 2. Ensure the in-cluster registry exists
ensure_registry() {
    if $KUBECTL get deployment registry -n kube-system >/dev/null 2>&1; then
        echo "  Registry already running"
        return
    fi
    echo "  Deploying registry..."
    $KUBECTL apply -f - <<'REGISTRY_EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: registry-data
  namespace: kube-system
spec:
  accessModes: [ReadWriteOnce]
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
REGISTRY_EOF
    $KUBECTL wait --for=condition=available --timeout=60s deployment/registry -n kube-system
    echo "  Registry ready"
}
ensure_registry

# Copy source into the minikube container via tar piped through docker exec.
# minikube (docker driver) is a container named "minikube"; docker exec -i
# has no PTY so binary tar data is transmitted cleanly.
PROJECT_PATH="/data/hotelier-build"
MINIKUBE_CONTAINER="minikube"

echo "  Syncing source to container ${MINIKUBE_CONTAINER}:${PROJECT_PATH} ..."
docker exec "$MINIKUBE_CONTAINER" sh -c \
    "rm -rf ${PROJECT_PATH} && mkdir -p ${PROJECT_PATH}"

tar -czf - \
    --exclude='.git' \
    --exclude='node_modules' \
    --exclude='**/obj' \
    --exclude='**/bin/Debug' \
    --exclude='**/bin/Release' \
    . | docker exec -i "$MINIKUBE_CONTAINER" sh -c "tar -xzf - -C ${PROJECT_PATH}"
echo "  Source synced to ${MINIKUBE_CONTAINER}:${PROJECT_PATH}"

$KUBECTL apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kaniko-builder
  namespace: $NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: kaniko:build
  namespace: $NAMESPACE
rules:
- apiGroups: [""]
  resources: ["pods/log", "configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: kaniko:build
  namespace: $NAMESPACE
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: kaniko:build
subjects:
- kind: ServiceAccount
  name: kaniko-builder
  namespace: $NAMESPACE
EOF
echo "Prerequisites complete"

# ========================================
# BUILD JOBS (one per service, each in its own fresh pod)
# ========================================
echo ""
echo "Submitting build jobs (tag: $IMAGE_TAG)..."

# Clean up any leftover jobs from a previous run
$KUBECTL delete jobs -n "$NAMESPACE" -l app.kubernetes.io/managed-by=kaniko-builder --ignore-not-found >/dev/null 2>&1 || true

JOB_NAMES=()

for SVC in "${BUILD_SERVICES[@]}"; do
    case "$SVC" in
        frontend) SVC_DIR="web/hotelier-frontend" ;;
        *)        SVC_DIR="services/$SVC" ;;
    esac

    if [ ! -f "$SVC_DIR/Dockerfile" ]; then
        echo "  SKIP $SVC (no Dockerfile at $SVC_DIR/Dockerfile)"
        continue
    fi

    SVC_JOB="${JOB_NAME}-${SVC}"
    SVC_IMG="$REGISTRY/hotelier-${SVC}:$IMAGE_TAG"
    SVC_PATH="${PROJECT_PATH}/${SVC_DIR}"

    echo "  Queuing $SVC -> $SVC_IMG"

    $KUBECTL apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: $SVC_JOB
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/managed-by: kaniko-builder
    hotelier/service: $SVC
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 600
  template:
    spec:
      serviceAccountName: kaniko-builder
      restartPolicy: Never
      volumes:
      - name: source-code
        hostPath:
          path: ${SVC_PATH}
          type: Directory
      - name: docker-config
        emptyDir: {}
      containers:
      - name: kaniko
        image: gcr.io/kaniko-project/executor:v1.23.2-debug
        args:
        - --context=dir:///source
        - --dockerfile=/source/Dockerfile
        - --destination=${SVC_IMG}
        - --cache=true
        - --cache-repo=${CACHE_REPO}
        - --cache-ttl=720h
        - --snapshot-mode=time
        - --compressed-caching=false
        - --insecure
        - --skip-tls-verify
        - --push-retry=3
        - --verbosity=warn
        - --push-retry=3
        resources:
          requests:
            cpu: "1000m"
            memory: "2Gi"
          limits:
            cpu: "4000m"
            memory: "6Gi"
        volumeMounts:
        - name: source-code
          mountPath: /source
          readOnly: true
        - name: docker-config
          mountPath: /kaniko/.docker
EOF

    JOB_NAMES+=("$SVC_JOB")
done

echo ""
echo "Waiting for ${#JOB_NAMES[@]} build job(s) to complete (timeout: 30m per job)..."
echo "Watch: $KUBECTL get pods -n $NAMESPACE -l app.kubernetes.io/managed-by=kaniko-builder -w"
echo ""

FAILED_SVCS=()
for JOB in "${JOB_NAMES[@]}"; do
    SVC=$(echo "$JOB" | sed "s/^${JOB_NAME}-//")
    echo -n "  Waiting for $SVC ... "
    if $KUBECTL wait --for=condition=complete --timeout=30m "job/$JOB" -n "$NAMESPACE" 2>/dev/null; then
        echo "DONE"
    else
        echo "FAILED"
        echo "  Logs for $SVC:"
        $KUBECTL logs "job/$JOB" -n "$NAMESPACE" -c kaniko --tail=30 2>/dev/null | sed 's/^/    /' || true
        FAILED_SVCS+=("$SVC")
    fi
done

cleanup

echo ""
if [ "${#FAILED_SVCS[@]}" -gt 0 ]; then
    echo "ERROR: ${#FAILED_SVCS[@]} build(s) failed: ${FAILED_SVCS[*]}"
    exit 1
fi

echo "======================================"
echo "BUILD COMPLETE"
echo "======================================"
echo "Images : $REGISTRY/hotelier-<service>:$IMAGE_TAG"
echo "Cache  : $CACHE_REPO (persistent across builds)"
echo ""
echo "Restart deployments:"
echo "  $KUBECTL rollout restart deployment -n $NAMESPACE"
