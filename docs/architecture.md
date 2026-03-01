# Hotelier Architecture Overview

This document describes the high-level architecture of the Hotelier platform: components, data flows, messaging, observability, deployment topology, and local development notes.

## High-Level Components

```
┌------------------------------------------------------------------------------┐
│  Frontend (React + Vite)                                                     │
│  web/hotelier-frontend                                                       │
└----------------------------┬-------------------------------------------------┘
                             │ HTTP / JSON
┌----------------------------▼-------------------------------------------------┐
│  API Gateway / Ingress                                                       │
└--┬------┬------┬------┬------┬------┬------┬------┬--------------------------┘
   │      │      │      │      │      │      │      │
   ▼      ▼      ▼      ▼      ▼      ▼      ▼      ▼
┌------┐┌------┐┌------┐┌------┐┌------┐┌------┐┌------┐┌------┐
│iden- ││accom-││avail-││reser-││rati- ││noti- ││sear- ││ cdn  │
│tity  ││moda- ││abil- ││vati- ││ng    ││fica- ││ch    ││      │
│      ││tion  ││ity   ││on    ││      ││tion  ││      ││      │
└--┬---┘└--┬---┘└--┬---┘└--┬---┘└--┬---┘└--┬---┘└--┬---┘└--┬---┘
   │       │       │       │       │       │       │       │
   ▼       ▼       ▼       ▼       ▼       ▼       ▼       ▼
┌------------------------------------------------------------------┐
│  RabbitMQ  (MassTransit 8.5.6)                                   │
│  Async domain events across all services                         │
└------------------------------------------------------------------┘
```

### Services (8 .NET 9.0 microservices)
- **identity-service** — authentication, JWT token issuance, user management
- **accommodation-service** — accommodation CRUD, amenities, guest limits
- **availability-service** — availability periods, pricing (per-unit/per-guest), price modifiers
- **reservation-service** — booking lifecycle (create, approve, reject, cancel), auto-approval
- **rating-service** — ratings for accommodations and hosts (1–5 stars, completed-stay verification)
- **notification-service** — in-app notifications triggered by domain events, per-type preferences
- **search-service** — aggregated read model for accommodation discovery (MongoDB)
- **cdn-service** — image upload, storage, and static file delivery

### Messaging
- RabbitMQ via MassTransit for async inter-service communication
- 15 distinct event types published across 6 services
- 21 consumers across 6 services
- All events use the shared namespace `Hotelier.Events`

### Observability
- OpenTelemetry instrumentation on all services
- Prometheus scraping endpoints (`/metrics`)
- Grafana dashboards
- Loki + Promtail for centralized logging

### Deployment
- Kubernetes via Helm charts (`helm-charts/`)
- Kaniko for container image building
- Ingress configuration for routing

### Frontend
- React 19 + TypeScript + Vite (`web/hotelier-frontend`)
- Material UI (MUI v7) component library
- Axios HTTP client with JWT auto-refresh

## Clean Architecture

Each service follows the same three-project structure:

```
services/<name>-service/src/
├-- <Name>Service.Api/           # ASP.NET Core host, controllers, Program.cs
├-- <Name>Service.Domain/        # Entities, interfaces, value objects, events
└-- <Name>Service.Infrastructure/# EF Core DbContext, MassTransit consumers, HTTP clients

services/<name>-service/tests/
└-- <Name>Service.Tests/         # xUnit + Moq + FluentAssertions
```

**Dependency rule:** Api → Domain ← Infrastructure. Domain has no external dependencies.

## Data Stores

Each service owns its persistence (database-per-service pattern):

| Service               | Database                                | Technology       |
| --------------------- | --------------------------------------- | ---------------- |
| identity-service      | PostgreSQL                              | EF Core (Npgsql) |
| accommodation-service | PostgreSQL                              | EF Core (Npgsql) |
| availability-service  | PostgreSQL                              | EF Core (Npgsql) |
| reservation-service   | PostgreSQL                              | EF Core (Npgsql) |
| rating-service        | PostgreSQL                              | EF Core (Npgsql) |
| notification-service  | MongoDB                                 | MongoDB.Driver   |
| search-service        | MongoDB                                 | MongoDB.Driver   |
| cdn-service           | MongoDB (metadata) + filesystem (files) | MongoDB.Driver   |

No shared databases. Services communicate exclusively via HTTP APIs and domain events.

## Authentication & Authorization

- Identity-service issues JWT tokens (issuer: `hotelier-identity`, audience: `hotelier`)
- All services validate tokens via shared JWT Bearer configuration
- Role-based authorization: `Guest` and `Host` roles enforced at controller level
- Service-to-service calls use internal-only endpoints (no auth, network-level isolation)

## Event Flow

```
identity-service --► UserRegistered       → (no consumers)
                 --► UserUpdated          → (no consumers)
                 --► UserDeleted          → accommodation, reservation, rating

accommodation    --► AccommodationCreated → search
                 --► AccommodationUpdated → search
                 --► AccommodationDeleted → search, availability, reservation, rating

cdn-service      --► CdnAssetProcessed   → accommodation
                 --► CdnAssetDeleted      → accommodation

reservation      --► ReservationCreated   → notification
                 --► ReservationApproved  → availability, notification
                 --► ReservationCancelled → availability, notification
                 --► ReservationRejected  → notification

rating-service   --► AccommodationRated   → search, notification
                 --► HostRated            → notification

availability     --► AvailabilityUpdated  → search
```

### Key Cascade Flows

1. **User deletion (host):** identity → `UserDeleted` → accommodation deletes all listings → `AccommodationDeleted` × N → search removes indexes, availability removes windows, reservation cancels bookings, rating removes ratings
2. **Reservation approval:** reservation → `ReservationApproved` → availability marks dates unavailable + auto-rejects overlapping pending reservations → `ReservationRejected` × N → notification informs affected guests
3. **Image upload:** cdn → `CdnAssetProcessed` → accommodation adds URL to pictures list → `AccommodationUpdated` → search updates index

## Service-to-Service HTTP

| Caller       | Callee        | Purpose                                               |
| ------------ | ------------- | ----------------------------------------------------- |
| identity     | reservation   | Pre-check active reservations before account deletion |
| availability | reservation   | Block pricing changes if reservations exist in period |
| reservation  | accommodation | Resolve host ID, auto-approval setting, guest limits  |
| reservation  | availability  | Verify date availability and calculate pricing        |
| rating       | reservation   | Verify guest completed a stay before allowing rating  |
| rating       | accommodation | Resolve HostId for accommodation ratings              |

## Deployment Topology

### Kubernetes
- Helm charts: `helm-charts/<service-name>/`
- Kube state configs: `kube-state/dev/`
- Ingress: path-based routing to all services
- Secrets: managed via kube-state secrets

### Docker Compose (local development)
- `docker-compose.yml` at project root
- All services + RabbitMQ + PostgreSQL + MongoDB

### Build & Deploy
- `make setup-all` — full Minikube cluster setup
- `make deploy` — deploy services via Helm
- `etc/scripts/build-images-kaniko.sh` — Kaniko-based image builds
- `etc/scripts/build-images-minikube.sh` — Minikube-based image builds

## Observability

Every service exposes:
- `GET /health` — liveness/readiness (used by Kubernetes probes)
- `GET /test` — smoke test endpoint
- `GET /metrics` — Prometheus scraping endpoint

Monitoring stack:
- **Prometheus** — metrics collection (config in `etc/prometheus/`)
- **Grafana** — dashboards (config in `etc/grafana/`)
- **Loki** — log aggregation (config in `etc/loki/`)
- **Promtail** — log shipping (config in `etc/promtail/`)

## Test Stack

- **xUnit 2.9.2** — test framework
- **Moq 4.20.72** — mocking
- **FluentAssertions 7.0.0** — assertion library
- **EF Core InMemory 9.0.2** — in-memory database for integration tests
- **216 total tests** across all 8 services
