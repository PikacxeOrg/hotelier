#!/usr/bin/env bash
set -euo pipefail

# Build all images with Docker and push to a registry for Swarm deployment.
#
# Usage:
#   ./etc/scripts/swarm-deploy.sh                     # build, push, deploy
#   ./etc/scripts/swarm-deploy.sh build-push           # only build & push
#   ./etc/scripts/swarm-deploy.sh deploy               # only deploy (images must exist)
#   ./etc/scripts/swarm-deploy.sh down                 # tear down the stack
#
# Environment:
#   REGISTRY  – image registry (default: localhost:5000)
#   TAG       – image tag      (default: latest)

STACK_NAME="hotelier"
COMPOSE_FILE="docker-compose.swarm.yml"

# Load .env file if present (provides POSTGRES_*, MONGO_*, RABBITMQ_*, JWT_*, GF_* vars)
ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    . "$ENV_FILE"
    set +a
fi

# Override COMPOSE_FILE – swarm uses its own file, not the dev compose
COMPOSE_FILE="docker-compose.swarm.yml"

REGISTRY="${REGISTRY:-localhost:5000}"
TAG="${TAG:-latest}"

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

# Map service name → build context
declare -A BUILD_CONTEXTS
BUILD_CONTEXTS[availability-service]="services/availability-service"
BUILD_CONTEXTS[accommodation-service]="services/accommodation-service"
BUILD_CONTEXTS[identity-service]="services/identity-service"
BUILD_CONTEXTS[notification-service]="services/notification-service"
BUILD_CONTEXTS[rating-service]="services/rating-service"
BUILD_CONTEXTS[reservation-service]="services/reservation-service"
BUILD_CONTEXTS[search-service]="services/search-service"
BUILD_CONTEXTS[cdn-service]="services/cdn-service"
BUILD_CONTEXTS[frontend]="web/hotelier-frontend"

ensure_registry() {
    if curl -sf "http://${REGISTRY}/v2/" > /dev/null 2>&1; then
        echo "Registry at ${REGISTRY} is reachable"
        return
    fi

    echo "Registry at ${REGISTRY} is not reachable."
    echo "Starting a local registry on port 5000..."
    if ! docker inspect registry > /dev/null 2>&1; then
        docker run -d -p 5000:5000 --name registry registry:2
    else
        docker start registry 2>/dev/null || true
    fi
    sleep 2
    echo "Local registry started"
}

build_and_push() {
    echo "======================================"
    echo "Building & pushing images"
    echo "  Registry: ${REGISTRY}"
    echo "  Tag:      ${TAG}"
    echo "======================================"
    echo ""

    ensure_registry

    # Build backend services
    for svc in "${SERVICES[@]}"; do
        IMAGE="${REGISTRY}/hotelier-${svc}:${TAG}"
        echo "Building ${IMAGE} ..."
        docker build -t "$IMAGE" "${BUILD_CONTEXTS[$svc]}"
        docker push "$IMAGE"
        echo "  ✓ ${svc}"
        echo ""
    done

    # Build frontend
    IMAGE="${REGISTRY}/hotelier-frontend:${TAG}"
    echo "Building ${IMAGE} ..."
    docker build -t "$IMAGE" "${BUILD_CONTEXTS[frontend]}"
    docker push "$IMAGE"
    echo "  ✓ frontend"

    echo ""
    echo "All images pushed to ${REGISTRY}"
}

deploy_stack() {
    echo "======================================"
    echo "Deploying stack: ${STACK_NAME}"
    echo "======================================"

    # Ensure swarm is initialized
    local swarm_state
    swarm_state=$(docker info --format '{{ .Swarm.LocalNodeState }}' 2>/dev/null || echo "inactive")
    if [ "$swarm_state" != "active" ]; then
        echo "Initializing Docker Swarm..."
        docker swarm init 2>/dev/null || true
    fi

    REGISTRY="${REGISTRY}" TAG="${TAG}" \
        docker stack deploy -c "${COMPOSE_FILE}" "${STACK_NAME}"

    echo ""
    echo "Waiting for services to converge (timeout: 120s)..."
    local deadline=$((SECONDS + 120))
    while [ $SECONDS -lt $deadline ]; do
        local not_ready=0
        while IFS= read -r replicas; do
            local current desired
            current="${replicas%%/*}"
            desired="${replicas##*/}"
            if [ "$current" != "$desired" ]; then
                not_ready=$((not_ready + 1))
            fi
        done < <(docker stack services "${STACK_NAME}" --format '{{.Replicas}}')
        if [ "$not_ready" -eq 0 ]; then
            echo "All services converged."
            break
        fi
        echo "  ${not_ready} service(s) still converging..."
        sleep 5
    done

    echo ""
    docker stack services "${STACK_NAME}" --format "table {{.Name}}\t{{.Replicas}}\t{{.Ports}}"
    echo ""
    echo "Check status with:"
    echo "  docker stack services ${STACK_NAME}"
    echo "  docker stack ps ${STACK_NAME}"
}

teardown_stack() {
    echo "Removing stack: ${STACK_NAME}..."
    docker stack rm "${STACK_NAME}"
    echo ""
    echo "Stack removed. Volumes are preserved."
    echo "To also remove volumes: docker volume prune"
}

# -- Main --
ACTION="${1:-all}"

case "$ACTION" in
    build-push)
        build_and_push
        ;;
    deploy)
        deploy_stack
        ;;
    down)
        teardown_stack
        ;;
    all)
        build_and_push
        deploy_stack
        ;;
    *)
        echo "Usage: $0 {all|build-push|deploy|down}"
        exit 1
        ;;
esac
