# Hotelier services overview

This document summarizes the microservices in the Hotelier platform, how they are built, deployed, and the key runtime endpoints / instrumentation available.

## Summary
The repository contains the following core services:
- accommodation-service
- availability-service
- identity-service
- notification-service
- rating-service
- reservation-service
- search-service

Each service is:
- Built with .NET (see service Dockerfiles).
- Instrumented with OpenTelemetry and exposes Prometheus scraping endpoints.
- Packaged as Helm charts under `infrastructure/helm`.

## Per-service details

### accommodation-service
- Purpose: core accommodation management.
- Dockerfile: [services/accommodation-service/Dockerfile](services/accommodation-service/Dockerfile)
- Helm chart: [infrastructure/helm/accommodation-service](infrastructure/helm/accommodation-service)
- README: [services/accommodation-service/README.md](services/accommodation-service/README.md)

### availability-service
- Purpose: availability and availability queries.
- Dockerfile: [services/availability-service/Dockerfile](services/availability-service/Dockerfile)
- Helm chart: [infrastructure/helm/availability-service](infrastructure/helm/availability-service)
- README: [services/availability-service/README.md](services/availability-service/README.md)

### identity-service
- Purpose: authentication / identity management.
- Dockerfile: [services/identity-service/Dockerfile](services/identity-service/Dockerfile) Helm chart: [infrastructure/helm/identity-service](infrastructure/helm/identity-service)- README: [services/identity-service/README.md](services/identity-service/README.md)

### notification-service
- Purpose: user notifications (emails, push, etc.).
- Dockerfile: [services/notification-service/Dockerfile](services/notification-service/Dockerfile) Helm chart: [infrastructure/helm/notification-service](infrastructure/helm/notification-service)
- README: [services/notification-service/README.md](services/notification-service/README.md)

### rating-service
- Purpose: ratings and reviews.
- Dockerfile: [services/rating-service/Dockerfile](services/rating-service/Dockerfile) Helm chart: [infrastructure/helm/rating-service](infrastructure/helm/rating-service)- README: [services/rating-service/README.md](services/rating-service/README.md)

### reservation-service
- Purpose: booking / reservation workflows.
- Helm chart: [infrastructure/helm/reservation-service](infrastructure/helm/reservation-service)
- Deployment entry: installed by the script [infrastructure/scripts/install-services.sh](infrastructure/scripts/install-services.sh)
- NOTE: there is no Dockerfile or service source excerpt included in the workspace summary; check the service directory if implementation is present.

### search-service
- Purpose: search and discovery.
- Dockerfile: [services/search-service/Dockerfile](services/search-service/Dockerfile): [infrastructure/helm/search-service](infrastructure/helm/search-service)- README: [services/search-service/README.md](services/search-service/README.md)

## Common implementation notes
- OpenTelemetry + Prometheus export is enabled in multiple services.
- RabbitMQ is used via MassTransit for inter-service messaging 
- Each service exposes simple health and test endpoints (`/health`, `/test`)

## Deployment & local setup
- Install all services to a Kubernetes cluster via Helm using:
  - Script: [infrastructure/scripts/install-services.sh](infrastructure/scripts/install-services.sh)
  - Make target: `make deploy` — wrapper uses [infrastructure/scripts/install-services.sh](infrastructure/scripts/install-services.sh) (see [Makefile](Makefile)).
- Monitoring stack (Prometheus, Grafana, Loki, Promtail) install:
  - Script: [infrastructure/scripts/install-monitoring.sh](infrastructure/scripts/install-monitoring.sh)
  - Make targets: `make monitoring-install` / `make monitoring-uninstall` (see [Makefile](Makefile)).
- Full local setup uses Minikube via [infrastructure/scripts/setup-all.sh](infrastructure/scripts/setup-all.sh) and Make target `make setup-all` (see [Makefile](Makefile)).

## Frontend
- React + Vite frontend is in [hotelier-frontend](hotelier-frontend).
  - Entry: [hotelier-frontend/src/main.tsx](hotelier-frontend/src/main.tsx)
  - ESLint config: [hotelier-frontend/eslint.config.js](hotelier-frontend/eslint.config.js)
  - Vite config: [hotelier-frontend/vite.config.ts](hotelier-frontend/vite.config.ts)
  - README: [hotelier-frontend/README.md](hotelier-frontend/README.md)

## Helpful files
- Root Makefile: [Makefile](Makefile)
- Monitoring install script: [infrastructure/scripts/install-monitoring.sh](infrastructure/scripts/install-monitoring.sh)
- Services install script: [infrastructure/scripts/install-services.sh](infrastructure/scripts/install-services.sh)
