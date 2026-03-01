# Hotelier – Accommodation Booking Platform

Microservices-based platform for accommodation booking, built with .NET 9.0 / ASP.NET Core and a React 19 frontend. Supports three deployment targets: **Docker Compose** (local dev), **Docker Swarm**, and **Kubernetes (Minikube)**.

## Architecture

| Service               | Purpose                           | Database             |
| --------------------- | --------------------------------- | -------------------- |
| identity-service      | Auth, JWT tokens, user management | PostgreSQL           |
| accommodation-service | Listing CRUD, amenities, pictures | PostgreSQL           |
| availability-service  | Availability windows, pricing     | PostgreSQL           |
| reservation-service   | Booking lifecycle                 | PostgreSQL           |
| rating-service        | Accommodation & host ratings      | PostgreSQL           |
| notification-service  | In-app notifications              | MongoDB              |
| search-service        | Aggregated read model for search  | MongoDB              |
| cdn-service           | Image upload & delivery           | MongoDB + filesystem |
| frontend              | React 19 SPA served via nginx     | —                    |

**Infrastructure:** PostgreSQL 16, MongoDB 8.0, RabbitMQ 3.12, Prometheus, Grafana, Loki, Promtail

See [docs/services-overview.md](docs/services-overview.md) and [docs/architecture.md](docs/architecture.md) for details.

---

## Prerequisites

| Tool                                                              | Version | Required For                                |
| ----------------------------------------------------------------- | ------- | ------------------------------------------- |
| [Docker](https://docs.docker.com/get-docker/) + Docker Compose v2 | 24+     | All targets                                 |
| [Make](https://www.gnu.org/software/make/)                        | any     | Running Makefile targets                    |
| [Minikube](https://minikube.sigs.k8s.io/docs/start/)              | 1.32+   | Kubernetes deployment                       |
| [kubectl](https://kubernetes.io/docs/tasks/tools/)                | 1.28+   | Kubernetes deployment                       |
| [Helm](https://helm.sh/docs/intro/install/)                       | 3.14+   | Kubernetes deployment                       |
| [Node.js](https://nodejs.org/)                                    | 22+     | Frontend development (optional)             |
| [.NET SDK](https://dotnet.microsoft.com/download)                 | 9.0     | Running/testing services locally (optional) |

---

## Configuration

### 1. Environment variables

All credentials are managed through a single `.env` file at the project root (gitignored). Docker Compose reads it automatically via the `COMPOSE_FILE` variable inside it.

```bash
cp .env.example .env
# Edit .env with your values (defaults work for local dev)
```

The `.env` file controls:
- PostgreSQL, MongoDB, RabbitMQ credentials
- JWT signing key, issuer, audience
- Grafana admin password
- Docker registry and image tag (for Swarm)

### 2. Kubernetes secrets (Minikube only)

```bash
cp etc/kubernetes/secrets/hotelier-secrets.yaml.example \
   etc/kubernetes/secrets/hotelier-secrets.yaml
# Edit the file — values must be base64-encoded
```

This file is also gitignored. The `make start` command applies it automatically.

---

## Quick Start

### Docker Compose (local development)

```bash
# Start everything (databases + services + monitoring + frontend)
docker compose --profile all up -d

# Or start selectively:
docker compose --profile data up -d        # databases + rabbitmq only
docker compose --profile services up -d     # backend services only
docker compose --profile monitoring up -d   # prometheus + grafana + loki
```

The frontend is available at `http://localhost` (port 80).
Grafana is at `http://localhost:3000`, RabbitMQ management at `http://localhost:15672`.

### Kubernetes (Minikube)

```bash
make start          # Start minikube, apply namespace + secrets + ingress
make build-images   # Build all container images via Kaniko
make setup-all      # Deploy everything (databases, services, monitoring)
```

#### Accessing the frontend

The `make setup-all` command enables the ingress addon and patches the controller automatically.

1. Add local DNS entries (first time only):
   ```bash
   sudo sh -c 'echo "127.0.0.1 hotelier.local monitoring.local rabbitmq.local" >> /etc/hosts'
   ```
2. Port-forward the ingress controller (keep this terminal open):
   ```bash
   kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80
   ```
3. Open `http://hotelier.local:8080` in your browser.

#### Other dashboards

```bash
kubectl port-forward -n observability svc/grafana 3000:3000       # http://localhost:3000
kubectl port-forward -n observability svc/prometheus 9090:9090     # http://localhost:9090
kubectl port-forward -n databases svc/rabbitmq 15672:15672         # http://localhost:15672
```

### Docker Swarm (backup deployment)

```bash
make swarm-deploy       # Build images, push to local registry, deploy stack
```

---

## Makefile Targets

### Minikube

| Target                  | Description                                                |
| ----------------------- | ---------------------------------------------------------- |
| `make start`            | Start minikube cluster, apply namespaces, secrets, ingress |
| `make stop`             | Stop minikube                                              |
| `make delete`           | Delete minikube cluster entirely                           |
| `make dashboard`        | Open the Kubernetes dashboard                              |
| `make build-images`     | Build all service images using Kaniko                      |
| `make rebuild-services` | Build images + rolling restart all deployments             |
| `make setup-all`        | Full cluster setup (databases, services, monitoring)       |
| `make status`           | Show all pods across namespaces                            |

### Docker Swarm

| Target                  | Description                            |
| ----------------------- | -------------------------------------- |
| `make swarm-deploy`     | Build, push, and deploy the full stack |
| `make swarm-build-push` | Build and push images only             |
| `make swarm-down`       | Tear down the Swarm stack              |
| `make swarm-status`     | List Swarm service status              |

### Health & Diagnostics

| Target                  | Description                               |
| ----------------------- | ----------------------------------------- |
| `make health-docker`    | Health check all Docker Compose services  |
| `make health-k8s`       | Health check all Kubernetes services      |
| `make verify-db-docker` | Verify database connectivity (Docker)     |
| `make verify-db-k8s`    | Verify database connectivity (Kubernetes) |
| `make logs-loki`        | Tail Loki logs                            |
| `make logs-promtail`    | Tail Promtail logs                        |

---

## Seed Data

Populate the platform with sample accommodations:

```bash
bash etc/scripts/seed-data.sh -n 50    # Create 50 sample listings
```

Requires the identity and accommodation services to be running.

---

## Frontend Development

```bash
cd web/hotelier-frontend
npm install
npm run dev     # Starts Vite dev server on http://localhost:3002
```

The Vite dev server proxies `/api/*` requests to the backend services. See [web/hotelier-frontend/README.md](web/hotelier-frontend/README.md) for more details.

---

## Project Structure

```
├── docker-compose.dev.yml          # Local dev compose (profiles: data, services, monitoring, all)
├── docker-compose.swarm.yml        # Docker Swarm deployment
├── Makefile                        # All build/deploy/utility targets
├── .env.example                    # Template for credentials (copy to .env)
├── services/                       # 8 .NET microservices
│   └── <service>/src/              #   Clean Architecture (Api / Domain / Infrastructure)
├── web/hotelier-frontend/          # React 19 + Vite + MUI frontend
├── helm-charts/                    # Helm charts for each service
├── kube-state/dev/                 # Helm values + K8s manifests for dev environment
├── etc/
│   ├── kubernetes/                 # Namespace, ingress, secrets
│   ├── scripts/                    # Build, deploy, health-check, seed scripts
│   ├── grafana/                    # Dashboard provisioning
│   ├── prometheus/                 # Prometheus config
│   ├── loki/                       # Loki config
│   └── promtail/                   # Promtail config
└── docs/                           # Architecture & API documentation
```

---

## License

[MIT](LICENSE)