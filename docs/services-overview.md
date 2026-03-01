# Hotelier Services Overview

This document summarizes the microservices in the Hotelier platform, how they are built, deployed, and the key runtime details.

## Summary

The platform consists of 8 microservices:

| Service               | Purpose                                             | Database             | Consumers | Tests |
| --------------------- | --------------------------------------------------- | -------------------- | --------- | ----- |
| identity-service      | Authentication, JWT tokens, user management         | PostgreSQL           | 0         | 36    |
| accommodation-service | Accommodation CRUD, amenities, pictures             | PostgreSQL           | 3         | 30    |
| availability-service  | Availability periods, pricing, price modifiers      | PostgreSQL           | 3         | 16    |
| reservation-service   | Booking lifecycle (create, approve, reject, cancel) | PostgreSQL           | 2         | 46    |
| rating-service        | Ratings for accommodations and hosts (1–5 stars)    | PostgreSQL           | 2         | 17    |
| notification-service  | In-app notifications, per-type preferences          | MongoDB              | 6         | 25    |
| search-service        | Aggregated read model for accommodation search      | MongoDB              | 5         | 10    |
| cdn-service           | Image upload, metadata, static file delivery        | MongoDB + filesystem | 0         | 36    |

Each service is:
- Built with .NET 9.0 and ASP.NET Core
- Structured as Clean Architecture (Api / Domain / Infrastructure)
- Instrumented with OpenTelemetry and Prometheus
- Packaged as a Helm chart under `helm-charts/<service-name>`
- Containerized via Dockerfile

## Per-Service Details

### identity-service
- **Purpose:** User registration, login, JWT token issuance/refresh, profile management, account deletion
- **Database:** PostgreSQL (EF Core)
- **Publishes:** `UserRegistered`, `UserUpdated`, `UserDeleted`
- **Consumes:** none
- **Key endpoints:** `POST /api/auth/register`, `POST /api/auth/login`, `PUT /api/users/me`, `DELETE /api/users/me`
- **Notable:** Calls reservation-service internally to verify no active reservations before account deletion
- [Dockerfile](../services/identity-service/Dockerfile) · [Helm chart](../helm-charts/hotelier-identity-service) · [README](../services/identity-service/README.md)

### accommodation-service
- **Purpose:** CRUD for accommodation listings (name, location, amenities, guest limits, auto-approval). Pictures managed via CDN events.
- **Database:** PostgreSQL (EF Core)
- **Publishes:** `AccommodationCreated`, `AccommodationUpdated`, `AccommodationDeleted`
- **Consumes:** `UserDeleted` (cascade-delete host's listings), `CdnAssetProcessed` (add picture URL), `CdnAssetDeleted` (remove picture URL)
- **Key endpoints:** `POST /api/accommodation`, `GET /api/accommodation/{id}`, `GET /api/accommodation/mine`
- [Dockerfile](../services/accommodation-service/Dockerfile) · [Helm chart](../helm-charts/hotelier-accommodation-service) · [README](../services/accommodation-service/README.md)

### availability-service
- **Purpose:** Define availability windows with pricing (per-unit or per-guest), price modifiers (weekend, holiday). Serves availability checks for reservation-service.
- **Database:** PostgreSQL (EF Core)
- **Publishes:** `AvailabilityUpdated`
- **Consumes:** `AccommodationDeleted` (remove all windows), `ReservationApproved` (mark dates unavailable), `ReservationCancelled` (free dates)
- **Key endpoints:** `POST /api/availability`, `GET /api/availability/accommodation/{id}`, `GET /api/availability/internal/check`
- **Notable:** Calls reservation-service to block changes when reservations exist in period
- [Dockerfile](../services/availability-service/Dockerfile) · [Helm chart](../helm-charts/hotelier-availability-service) · [README](../services/availability-service/README.md)

### reservation-service
- **Purpose:** Full booking lifecycle — create (with availability + guest count validation), auto-approval, manual approve/reject, cancel (1-day rule), auto-reject overlapping.
- **Database:** PostgreSQL (EF Core)
- **Publishes:** `ReservationCreated`, `ReservationApproved`, `ReservationRejected`, `ReservationCancelled`
- **Consumes:** `UserDeleted` (cancel active reservations), `AccommodationDeleted` (cancel reservations for listing)
- **Key endpoints:** `POST /api/reservations`, `PUT /api/reservations/{id}/approve`, `PUT /api/reservations/{id}/cancel`
- **Internal endpoints:** `can-delete/{userId}`, `has-reservations`, `completed` (for rating verification)
- [Dockerfile](../services/reservation-service/Dockerfile) · [Helm chart](../helm-charts/hotelier-reservation-service) · [README](../services/reservation-service/README.md)

### rating-service
- **Purpose:** Guests rate accommodations and hosts (1–5 stars with optional comment). Enforces completed-stay verification and one rating per target.
- **Database:** PostgreSQL (EF Core)
- **Publishes:** `AccommodationRated`, `HostRated`
- **Consumes:** `UserDeleted` (remove all ratings by user), `AccommodationDeleted` (remove ratings for listing)
- **Key endpoints:** `POST /api/ratings`, `GET /api/ratings/target/{id}/summary`, `GET /api/ratings/mine`
- **Notable:** Calls reservation-service to verify completed stay; calls accommodation-service to resolve HostId
- [Dockerfile](../services/rating-service/Dockerfile) · [Helm chart](../helm-charts/hotelier-rating-service) · [README](../services/rating-service/README.md)

### notification-service
- **Purpose:** In-app notifications triggered by domain events. Supports per-type enable/disable preferences.
- **Database:** MongoDB
- **Publishes:** none
- **Consumes:** `ReservationCreated` (notify host), `ReservationApproved` (notify guest), `ReservationCancelled` (notify host), `ReservationRejected` (notify guest), `AccommodationRated` (notify host), `HostRated` (notify host)
- **Key endpoints:** `GET /api/notifications`, `PUT /api/notifications/read-all`, `PUT /api/notifications/preferences`
- [Dockerfile](../services/notification-service/Dockerfile) · [Helm chart](../helm-charts/hotelier-notification-service) · [README](../services/notification-service/README.md)

### search-service
- **Purpose:** Aggregated read model for accommodation discovery. Maintains a denormalized MongoDB index updated by events from accommodation, rating, and availability services.
- **Database:** MongoDB
- **Publishes:** none
- **Consumes:** `AccommodationCreated` (insert), `AccommodationUpdated` (update), `AccommodationDeleted` (delete), `AccommodationRated` (update rating), `AvailabilityUpdated` (update windows)
- **Key endpoints:** `GET /api/search` (full-text + filter search with pagination), `GET /api/search/{id}`
- [Dockerfile](../services/search-service/Dockerfile) · [Helm chart](../helm-charts/hotelier-search-service) · [README](../services/search-service/README.md)

### cdn-service
- **Purpose:** Image upload (multipart), metadata storage, and static file delivery. Files stored on local filesystem; metadata in MongoDB.
- **Database:** MongoDB + filesystem
- **Publishes:** `CdnAssetProcessed`, `CdnAssetDeleted`
- **Consumes:** none
- **Key endpoints:** `POST /api/assets` (upload), `GET /assets/{filename}` (static serve), `DELETE /api/assets/{id}`
- [Dockerfile](../services/cdn-service/Dockerfile) · [Helm chart](../helm-charts/hotelier-cdn-service) · [README](../services/cdn-service/README.md)

## Common Implementation Patterns

- **Controller pattern:** Primary constructor injection, `GetUserId()` from JWT claims, `MapResponse()` static helpers
- **OpenTelemetry + Prometheus** export enabled on all services
- **RabbitMQ** via MassTransit for inter-service messaging (all events in `namespace Hotelier.Events`)
- **JWT Bearer** authentication validated by all services (issuer: `hotelier-identity`, audience: `hotelier`)
- **Health and test endpoints** on every service (`/health`, `/test`)
- **JsonStringEnumConverter** configured on all services for human-readable enum serialization

## Deployment & Local Setup

### Docker Compose
```bash
docker-compose up -d    # Start all services locally
```

### Kubernetes (Minikube)
```bash
make setup-all          # Full Minikube cluster setup
make deploy             # Deploy services via Helm charts
```

### Build Images
```bash
etc/scripts/build-images-kaniko.sh    # Kaniko builds (CI)
etc/scripts/build-images-minikube.sh  # Minikube builds (local)
```

### Health Check
```bash
etc/scripts/health-check.sh           # Verify all services are running
```

## Frontend

React 19 + TypeScript SPA with Material UI, located at `web/hotelier-frontend/`.

- **Dev server:** `npm run dev` (Vite, port 3002)
- **API proxy:** Vite dev proxy routes `/api/*` to backend services
- **Auth:** JWT auto-attach via Axios interceptors, token refresh on 401
- **Pages:** Home (search), login/register, accommodation detail/create/edit, reservations, ratings, notifications, profile
- See [frontend README](../web/hotelier-frontend/README.md) for details.
