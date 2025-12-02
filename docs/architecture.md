# Hotelier architecture overview

This document describes the high-level architecture of the Hotelier platform: components, data flows, messaging, observability, deployment topology, and local development notes.

## High-level components
- Services (microservices, built with .NET)
  - accommodation-service
  - availability-service
  - identity-service
  - notification-service
  - rating-service
  - reservation-service
  - search-service
  - cdn-service
- Messaging
  - RabbitMQ via MassTransit for async inter-service communication and domain events
- Observability
  - OpenTelemetry instrumentation in services, Prometheus scraping endpoints, Grafana dashboards, Loki/Promtail for logs
- Deployment
  - Kubernetes via Helm charts `(infrastructure/helm/)`, scripts under `infrastructure/scripts`, Makefile wrappers
- UI
  - React + Vite frontend (hotelier-frontend)

## Service responsibilities & interactions
- identity-service: authentication, user identity, issues tokens / user events
- accommodation-service: manages accommodations catalog and metadata
- availability-service: computes and serves availability queries
- rating-service: stores and serves ratings & reviews
- notification-service: sends emails/push based on events (reservation created, rating posted, etc.)
- search-service: indexes content for discovery (may consume accommodation/reservation events)
- cdn-service: manages static/media assets and delivery
  
Common patterns:
- Services expose small HTTP APIs (including /health and /test) and a Prometheus scraping endpoint.
- Domain events (reservation.created, reservation.cancelled, user.registered, accommodation.updated, accommodation.asset.updated, etc.) flow over RabbitMQ and are handled via MassTransit consumers.
- Read models and search indexes are eventually consistent and updated by event consumers.

## Data stores
- Each service may own its own persistence (database per service pattern). Check service directories for concrete DB adapters/config.
- Search uses an index (Elasticsearch or other index) — check search-service implementation.
- CDN/media:
  - cdn-service uses object storage (S3 or MinIO for local/dev) for blobs and may maintain a small metadata DB for asset records
  - caching is handled at HTTP layer + edge cache; invalidation endpoints/events are emitted when assets change
- No shared database; communication is via APIs/events.

## Messaging & event flow (example)
1. Client requests booking via availability-service HTTP API.
2. availability-service and notification-service consume `reservation.created`:
   - availability-service updates availability caches
   - notification-service sends confirmation to user
3. rating-service / search-service consume events to update read models/indexes
4. accommodation image update flow (CDN-related):
   - accommodation-service publishes `accommodation.asset.updated` when images are added/changed
   - cdn-service consumes `accommodation.asset.updated`, fetches/receives the asset, processes variants (thumbs, webp), stores in object storage, and publishes `cdn.asset.processed` (or `cdn.asset.invalidated`) for downstream consumers (search-service, frontend cache invalidation, etc.)
   - Frontend retrieves images via cdn-service URLs (or signed URLs) which are served with appropriate caching headers and edge invalidation when needed

Simple ASCII sequence:
Client -> availability-service -> (DB write)
availability-service -> RabbitMQ -> notification-service / availability-service / search-service

accommodation-service -> RabbitMQ -> cdn-service -> object storage -> cdn.asset.processed -> search-service / frontend cache

## Observability & telemetry
- OpenTelemetry enabled in services; traces exported and metrics exposed for Prometheus.
- Each service exposes:
  - /health (liveness/readiness)
  - /test (smoke/test endpoint)
  - Prometheus scrape endpoint (configured in each Program.cs)
- cdn-service exports metrics around request rates, cache hit/miss, processing duration, and storage operation metrics.
- Monitoring stack (Prometheus, Grafana, Loki, Promtail) installable via infrastructure/scripts/install-monitoring.sh or `make monitoring-install`.
- Use traces to follow cross-service requests and events; use Prometheus metrics for service health and capacity.

## Deployment topology
- Helm charts located: `infrastructure/helm/<service-name>`
  - cdn-service chart located at `infrastructure/helm/cdn-service`
- Install services: infrastructure/scripts/install-services.sh or `make deploy`
- Full local cluster: infrastructure/scripts/setup-all.sh or `make setup-all` (Minikube)
- Charts include helpers and values.yaml to configure image tags, resources, probes, and Prometheus annotations.

## Local development
- Run an individual service locally (dotnet run) — endpoints are the same as in-cluster.
- For cdn-service local development:
  - run MinIO (or configure AWS S3 credentials) and point cdn-service to local object storage
  - start cdn-service with env vars for storage, RabbitMQ, and CDN cache backend
  - use the upload/signed-url endpoints for manual testing
- For end-to-end local runs, use Minikube setup (`make setup-all`) or run RabbitMQ locally and start services with environment variables pointing to local RabbitMQ and DB instances.
- Helpful scripts:
  - infrastructure/scripts/install-services.sh
  - infrastructure/scripts/install-monitoring.sh
  - infrastructure/scripts/setup-all.sh

## Operational notes
- Health endpoints are used by Kubernetes liveness/readiness probes — ensure /health returns correct status.
- Ensure Prometheus scrape config picks up services (annotations in Helm charts).
- When making schema or event changes, version events and consumers to maintain compatibility.
- CDN-specific:
  - Ensure proper cache-control headers and a clear invalidation strategy; emit invalidation events when assets change.
  - Use signed URLs for access to private assets and rotate keys periodically.
  - Monitor cache hit ratio and processing queue/backpressure for image processing tasks.
