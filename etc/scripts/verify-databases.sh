#!/bin/bash

# Database Schema Verification Script
# Checks if all service databases have been properly initialized with tables/collections

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Environment detection
ENV=${1:-docker}

check_postgres_docker() {
    print_header "PostgreSQL Database Schema Check"
    
    PG_DATABASES=(
        "hotelier_availability"
        "hotelier_accommodation"
        "hotelier_identity"
        "hotelier_rating"
        "hotelier_reservation"
    )
    
    echo "Checking PostgreSQL databases..."
    echo ""
    
    for db in "${PG_DATABASES[@]}"; do
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Database: $db"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Check if database exists
        if docker compose exec -T postgres psql -U hotelier -lqt | cut -d \| -f 1 | grep -qw "$db"; then
            print_success "Database exists"
            
            # Check for tables
            echo "Tables:"
            table_count=$(docker compose exec -T postgres psql -U hotelier -d "$db" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')
            
            if [ "$table_count" -gt 0 ]; then
                print_success "Found $table_count table(s)"
                docker compose exec -T postgres psql -U hotelier -d "$db" -c "\dt" 2>/dev/null | grep -E "^ public" || echo "  (No tables to display)"
            else
                print_warning "No tables found - migrations may not have run yet"
                echo "  This is expected if the service hasn't been started or hasn't run migrations"
            fi
        else
            print_error "Database not found"
        fi
        echo ""
    done
}

check_mongo_docker() {
    print_header "MongoDB Database Schema Check"
    
    MONGO_DATABASES=(
        "hotelier_notification"
        "hotelier_search"
    )
    
    echo "Checking MongoDB databases..."
    echo ""
    
    for db in "${MONGO_DATABASES[@]}"; do
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Database: $db"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Check if database exists
        db_exists=$(docker compose exec -T mongodb mongosh --username hotelier --password hotelier --authenticationDatabase admin --quiet --eval "db.adminCommand({ listDatabases: 1 }).databases.map(d => d.name).includes('$db')" 2>/dev/null)
        
        if [ "$db_exists" == "true" ]; then
            print_success "Database exists"
            
            # Check for collections
            echo "Collections:"
            collections=$(docker compose exec -T mongodb mongosh --username hotelier --password hotelier --authenticationDatabase admin "$db" --quiet --eval "db.getCollectionNames().join(', ')" 2>/dev/null)
            
            if [ -n "$collections" ] && [ "$collections" != "" ]; then
                print_success "Collections found"
                echo "  $collections"
            else
                print_warning "No collections found - service may not have created them yet"
                echo "  This is expected if the service hasn't been started or hasn't inserted data"
            fi
        else
            print_warning "Database not found or not initialized yet"
        fi
        echo ""
    done
}

check_postgres_k8s() {
    print_header "PostgreSQL Database Schema Check (Kubernetes)"
    
    # Detect kubectl
    if command -v minikube &> /dev/null && minikube status &> /dev/null; then
        KUBECTL="minikube kubectl --"
    else
        KUBECTL="kubectl"
    fi
    
    # Check if postgres pod is running
    if ! $KUBECTL get pods -n databases -l app=postgres -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
        print_error "PostgreSQL pod is not running"
        return 1
    fi
    
    POD_NAME=$($KUBECTL get pods -n databases -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    PG_DATABASES=(
        "hotelier_availability"
        "hotelier_accommodation"
        "hotelier_identity"
        "hotelier_rating"
        "hotelier_reservation"
    )
    
    for db in "${PG_DATABASES[@]}"; do
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Database: $db"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Check if database exists
        if $KUBECTL exec -n databases "$POD_NAME" -- psql -U hotelier -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "$db"; then
            print_success "Database exists"
            
            # Check for tables
            table_count=$($KUBECTL exec -n databases "$POD_NAME" -- psql -U hotelier -d "$db" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')
            
            if [ "$table_count" -gt 0 ]; then
                print_success "Found $table_count table(s)"
                $KUBECTL exec -n databases "$POD_NAME" -- psql -U hotelier -d "$db" -c "\dt" 2>/dev/null | grep -E "^ public" || echo "  (No tables to display)"
            else
                print_warning "No tables found - migrations may not have run yet"
            fi
        else
            print_error "Database not found"
        fi
        echo ""
    done
}

check_mongo_k8s() {
    print_header "MongoDB Database Schema Check (Kubernetes)"
    
    # Detect kubectl
    if command -v minikube &> /dev/null && minikube status &> /dev/null; then
        KUBECTL="minikube kubectl --"
    else
        KUBECTL="kubectl"
    fi
    
    # Check if mongo pod is running
    if ! $KUBECTL get pods -n databases -l app=mongodb -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
        print_error "MongoDB pod is not running"
        return 1
    fi
    
    POD_NAME=$($KUBECTL get pods -n databases -l app=mongodb -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    MONGO_DATABASES=(
        "hotelier_notification"
        "hotelier_search"
    )
    
    for db in "${MONGO_DATABASES[@]}"; do
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Database: $db"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Check if database exists
        db_exists=$($KUBECTL exec -n databases "$POD_NAME" -- mongosh --username hotelier --password hotelier --authenticationDatabase admin --quiet --eval "db.adminCommand({ listDatabases: 1 }).databases.map(d => d.name).includes('$db')" 2>/dev/null)
        
        if [ "$db_exists" == "true" ]; then
            print_success "Database exists"
            
            # Check for collections
            collections=$($KUBECTL exec -n databases "$POD_NAME" -- mongosh --username hotelier --password hotelier --authenticationDatabase admin "$db" --quiet --eval "db.getCollectionNames().join(', ')" 2>/dev/null)
            
            if [ -n "$collections" ] && [ "$collections" != "" ]; then
                print_success "Collections found"
                echo "  $collections"
            else
                print_warning "No collections found - service may not have created them yet"
            fi
        else
            print_warning "Database not found or not initialized yet"
        fi
        echo ""
    done
}

# Main execution
main() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════╗"
    echo "║   Database Schema Verification            ║"
    echo "╚═══════════════════════════════════════════╝"
    echo -e "${NC}"

    case $ENV in
        docker|compose)
            check_postgres_docker
            check_mongo_docker
            ;;
        k8s|kubernetes|minikube)
            check_postgres_k8s
            check_mongo_k8s
            ;;
        *)
            echo "Usage: $0 [docker|k8s]"
            echo ""
            echo "  docker - Check Docker Compose databases"
            echo "  k8s    - Check Kubernetes databases"
            echo ""
            exit 1
            ;;
    esac

    print_header "Summary"
    echo "Database verification completed."
    echo ""
    echo "Note: Empty tables/collections are normal if:"
    echo "  1. Services haven't been started yet"
    echo "  2. EF Core migrations haven't run yet"
    echo "  3. No data has been inserted yet"
    echo ""
    echo "Services typically auto-migrate on first startup."
    echo "Check service logs to verify migration execution."
}

main "$@"
