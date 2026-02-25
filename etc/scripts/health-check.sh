#!/bin/bash

# Health Check Script for Hotelier Platform
# Checks the health of all services, databases, and infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Environment detection
ENV=${1:-docker} # docker or k8s

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Docker Compose Health Checks
check_docker_health() {
    print_header "Docker Compose Environment Health Check"
    
    # Check if docker-compose is running
    if ! docker compose ps > /dev/null 2>&1; then
        print_error "Docker Compose is not running. Start it with: docker compose --profile all up -d"
        return 1
    fi

    # Check databases
    print_header "Database Health"
    
    # PostgreSQL
    echo -n "PostgreSQL: "
    if docker compose exec -T postgres pg_isready -U hotelier > /dev/null 2>&1; then
        print_success "PostgreSQL is healthy and accepting connections"
        
        # List databases
        echo "  Databases:"
        docker compose exec -T postgres psql -U hotelier -d hotelierdb -c "\l" 2>/dev/null | grep hotelier | awk '{print "    - " $1}'
    else
        print_error "PostgreSQL is not healthy"
    fi

    # MongoDB
    echo -n "MongoDB: "
    if docker compose exec -T mongodb mongosh --username hotelier --password hotelier --authenticationDatabase admin --eval "db.adminCommand({ ping: 1 })" --quiet > /dev/null 2>&1; then
        print_success "MongoDB is healthy and accepting connections"
        
        # List databases
        echo "  Databases:"
        docker compose exec -T mongodb mongosh --username hotelier --password hotelier --authenticationDatabase admin --eval "db.adminCommand({ listDatabases: 1 }).databases.forEach(function(db) { if (db.name.includes('hotelier')) print(db.name); })" --quiet 2>/dev/null | while read db; do
            echo "    - $db"
        done
    else
        print_error "MongoDB is not healthy"
    fi

    # Message Broker
    print_header "Message Broker Health"
    echo -n "RabbitMQ: "
    if curl -s -u guest:guest http://localhost:15672/api/overview > /dev/null 2>&1; then
        print_success "RabbitMQ is healthy"
        rabbit_info=$(curl -s -u guest:guest http://localhost:15672/api/overview)
        connections=$(echo "$rabbit_info" | jq -r '.object_totals.connections // 0' 2>/dev/null || echo "N/A")
        channels=$(echo "$rabbit_info" | jq -r '.object_totals.channels // 0' 2>/dev/null || echo "N/A")
        queues=$(echo "$rabbit_info" | jq -r '.object_totals.queues // 0' 2>/dev/null || echo "N/A")
        echo "  Connections: $connections | Channels: $channels | Queues: $queues"
    else
        print_error "RabbitMQ is not responding"
    fi

    # Monitoring Stack
    print_header "Monitoring Stack Health"
    
    echo -n "Prometheus: "
    if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
        print_success "Prometheus is healthy"
    else
        print_error "Prometheus is not responding"
    fi

    echo -n "Grafana: "
    if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
        print_success "Grafana is healthy"
    else
        print_error "Grafana is not responding"
    fi

    echo -n "Loki: "
    if curl -s http://localhost:3100/ready > /dev/null 2>&1; then
        print_success "Loki is healthy"
    else
        print_error "Loki is not responding"
    fi

    # Microservices
    print_header "Microservices Health"
    
    services=(
        "availability-service:5001"
        "accommodation-service:5002"
        "identity-service:5003"
        "notification-service:5004"
        "rating-service:5005"
        "reservation-service:5006"
        "search-service:5007"
        "cdn-service:5008"
    )

    for service in "${services[@]}"; do
        IFS=':' read -r name port <<< "$service"
        echo -n "$name: "
        
        # Check if container is running
        if ! docker compose ps --format json | jq -r '.[].Service' 2>/dev/null | grep -q "^${name}$"; then
            print_warning "Container not running (profile might not be active)"
            continue
        fi
        
        # Check /health endpoint
        if curl -sf http://localhost:${port}/health > /dev/null 2>&1; then
            print_success "Healthy (http://localhost:${port})"
        else
            print_error "Not responding on port $port"
        fi
    done

    print_header "Overall Status"
    print_success "Health check completed for Docker Compose environment"
}

# Kubernetes Health Checks
check_k8s_health() {
    print_header "Kubernetes Environment Health Check"
    
    NAMESPACE=${NAMESPACE:-hotelier}
    MONITORING_NS=${MONITORING_NS:-observability}
    
    # Detect kubectl
    if command -v minikube &> /dev/null && minikube status &> /dev/null; then
        KUBECTL="minikube kubectl --"
    else
        KUBECTL="kubectl"
    fi

    # Check if cluster is accessible
    if ! $KUBECTL cluster-info > /dev/null 2>&1; then
        print_error "Cannot access Kubernetes cluster"
        return 1
    fi

    # Check namespaces
    print_header "Namespaces"
    if $KUBECTL get namespace $NAMESPACE > /dev/null 2>&1; then
        print_success "Namespace '$NAMESPACE' exists"
    else
        print_error "Namespace '$NAMESPACE' not found"
    fi

    if $KUBECTL get namespace $MONITORING_NS > /dev/null 2>&1; then
        print_success "Namespace '$MONITORING_NS' exists"
    else
        print_warning "Namespace '$MONITORING_NS' not found"
    fi

    # Check databases
    print_header "Database Health"
    
    echo -n "PostgreSQL: "
    if $KUBECTL get pods -n $NAMESPACE -l app=postgres -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
        print_success "PostgreSQL pod is running"
        
        # Check readiness
        ready=$($KUBECTL get pods -n $NAMESPACE -l app=postgres -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
        if [ "$ready" == "true" ]; then
            echo "  Status: Ready to accept connections"
        else
            print_warning "  Status: Not ready yet"
        fi
    else
        print_error "PostgreSQL pod not running"
    fi

    echo -n "MongoDB: "
    if $KUBECTL get pods -n $NAMESPACE -l app=mongodb -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
        print_success "MongoDB pod is running"
        
        ready=$($KUBECTL get pods -n $NAMESPACE -l app=mongodb -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
        if [ "$ready" == "true" ]; then
            echo "  Status: Ready to accept connections"
        else
            print_warning "  Status: Not ready yet"
        fi
    else
        print_error "MongoDB pod not running"
    fi

    # Check RabbitMQ
    print_header "Message Broker Health"
    echo -n "RabbitMQ: "
    if $KUBECTL get pods -n $NAMESPACE -l app=rabbitmq -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
        print_success "RabbitMQ pod is running"
        
        ready=$($KUBECTL get pods -n $NAMESPACE -l app=rabbitmq -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
        if [ "$ready" == "true" ]; then
            echo "  Status: Ready"
        else
            print_warning "  Status: Not ready yet"
        fi
    else
        print_error "RabbitMQ pod not running"
    fi

    # Check monitoring stack
    print_header "Monitoring Stack Health"
    
    for component in prometheus grafana loki promtail; do
        echo -n "$component: "
        if $KUBECTL get pods -n $MONITORING_NS -l app.kubernetes.io/name=$component -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
            print_success "Running"
        else
            print_warning "Not found or not running"
        fi
    done

    # Check microservices
    print_header "Microservices Health"
    
    services=(
        "availability-service"
        "accommodation-service"
        "identity-service"
        "notification-service"
        "rating-service"
        "reservation-service"
        "search-service"
        "cdn-service"
    )

    for service in "${services[@]}"; do
        echo -n "$service: "
        
        # Get pod status
        phase=$($KUBECTL get pods -n $NAMESPACE -l app=$service -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
        
        if [ "$phase" == "Running" ]; then
            ready=$($KUBECTL get pods -n $NAMESPACE -l app=$service -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
            if [ "$ready" == "true" ]; then
                print_success "Running and ready"
            else
                print_warning "Running but not ready"
            fi
        elif [ -z "$phase" ]; then
            print_warning "Not deployed"
        else
            print_error "Status: $phase"
        fi
    done

    # Pod summary
    print_header "Pod Summary"
    echo "All pods in namespace '$NAMESPACE':"
    $KUBECTL get pods -n $NAMESPACE -o wide 2>/dev/null || echo "No pods found"
    
    echo ""
    echo "All pods in namespace '$MONITORING_NS':"
    $KUBECTL get pods -n $MONITORING_NS -o wide 2>/dev/null || echo "No pods found"

    print_header "Overall Status"
    print_success "Health check completed for Kubernetes environment"
}

# Main execution
main() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════╗"
    echo "║   Hotelier Platform Health Check          ║"
    echo "╚═══════════════════════════════════════════╝"
    echo -e "${NC}"

    case $ENV in
        docker|compose)
            check_docker_health
            ;;
        k8s|kubernetes|minikube)
            check_k8s_health
            ;;
        both)
            check_docker_health
            echo ""
            check_k8s_health
            ;;
        *)
            echo "Usage: $0 [docker|k8s|both]"
            echo ""
            echo "  docker    - Check Docker Compose environment"
            echo "  k8s       - Check Kubernetes/Minikube environment"
            echo "  both      - Check both environments"
            echo ""
            exit 1
            ;;
    esac

    echo ""
    echo -e "${GREEN}Health check completed!${NC}"
    echo ""
    echo "Quick access URLs (Docker Compose):"
    echo "  RabbitMQ Management: http://localhost:15672 (guest/guest)"
    echo "  Prometheus:          http://localhost:9090"
    echo "  Grafana:             http://localhost:3000 (admin/admin)"
    echo ""
}

main "$@"
