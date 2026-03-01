# Hotelier API Endpoints

Complete reference for all HTTP endpoints across the 8 microservices.

> **Common endpoints** — every service exposes:
> - `GET /health` — liveness/readiness probe, returns `"OK"`
> - `GET /test` — smoke test, returns `{ "message": "<Service> service running" }`
> - `GET /metrics` — Prometheus scraping endpoint

---

## Identity Service

### AuthController — `/api/auth`

| Method | Route                | Auth      | Description                             |
| ------ | -------------------- | --------- | --------------------------------------- |
| POST   | `/api/auth/register` | Anonymous | Register a new user (Guest or Host)     |
| POST   | `/api/auth/login`    | Anonymous | Authenticate with username and password |
| POST   | `/api/auth/refresh`  | Anonymous | Refresh an expired access token         |

**Register** — `POST /api/auth/register`
```json
{
  "username": "string",
  "password": "string",
  "name": "string",
  "lastName": "string",
  "email": "string",
  "address": "string",
  "userType": "Guest | Host"
}
```
Returns `AuthResponse { accessToken, refreshToken, expiresAt, user: UserProfile }`.

**Login** — `POST /api/auth/login`
```json
{ "username": "string", "password": "string" }
```
Returns `AuthResponse`.

**Refresh** — `POST /api/auth/refresh`
```json
{ "accessToken": "string", "refreshToken": "string" }
```
Returns `AuthResponse`.

### UsersController — `/api/users`

| Method | Route                       | Auth      | Description                                     |
| ------ | --------------------------- | --------- | ----------------------------------------------- |
| GET    | `/api/users/me`             | Authorize | Get current user profile                        |
| PUT    | `/api/users/me`             | Authorize | Update personal info (name, email, address)     |
| PUT    | `/api/users/me/credentials` | Authorize | Change username and/or password                 |
| DELETE | `/api/users/me`             | Authorize | Delete account (blocked if active reservations) |
| GET    | `/api/users/{id}`           | Anonymous | Get public profile by ID (service-to-service)   |

**Events published:** `UserRegistered`, `UserUpdated`, `UserDeleted`

---

## Accommodation Service

### AccommodationController — `/api/accommodation`

| Method | Route                              | Auth      | Description                                                     |
| ------ | ---------------------------------- | --------- | --------------------------------------------------------------- |
| POST   | `/api/accommodation`               | Host      | Create accommodation listing                                    |
| GET    | `/api/accommodation/{id}`          | Anonymous | Get accommodation by ID                                         |
| GET    | `/api/accommodation`               | Anonymous | List accommodations (optional: `location`, `guests`, `amenity`) |
| GET    | `/api/accommodation/host/{hostId}` | Anonymous | List accommodations by host                                     |
| GET    | `/api/accommodation/mine`          | Host      | List current host's accommodations                              |
| PUT    | `/api/accommodation/{id}`          | Host      | Update accommodation (owner only)                               |
| DELETE | `/api/accommodation/{id}`          | Host      | Delete accommodation (owner only)                               |

**Create** — `POST /api/accommodation`
```json
{
  "name": "string",
  "location": "string",
  "amenities": ["WiFi", "Kitchen", "AC"],
  "minGuests": 1,
  "maxGuests": 6,
  "autoApproval": false
}
```
Returns `AccommodationResponse { id, name, location, amenities, pictures, minGuests, maxGuests, hostId, autoApproval }`.

**Events published:** `AccommodationCreated`, `AccommodationUpdated`, `AccommodationDeleted`

---

## CDN Service

### Static File Serving
| Method | Route                | Auth      | Description                   |
| ------ | -------------------- | --------- | ----------------------------- |
| GET    | `/assets/{filename}` | Anonymous | Serve uploaded file from disk |

### AssetsController — `/api/assets`

| Method | Route                            | Auth      | Description                                           |
| ------ | -------------------------------- | --------- | ----------------------------------------------------- |
| POST   | `/api/assets`                    | Authorize | Upload image files (multipart/form-data, 50 MB limit) |
| GET    | `/api/assets/{assetId}/metadata` | Anonymous | Get asset metadata                                    |
| GET    | `/api/assets/entity/{entityId}`  | Anonymous | List assets for an entity (e.g. accommodation)        |
| GET    | `/api/assets/owner/{ownerId}`    | Authorize | List assets by owner                                  |
| GET    | `/api/assets/mine`               | Authorize | List current user's assets                            |
| DELETE | `/api/assets/{assetId}`          | Authorize | Delete asset (owner only)                             |

**Upload** — `POST /api/assets` `Content-Type: multipart/form-data`
- `files` — one or more image files
- `entityId` — optional GUID linking to an accommodation

Returns `UploadResponse[] { assetId, url, contentType, sizeBytes, uploadedAt }`.

**Events published:** `CdnAssetProcessed`, `CdnAssetDeleted`

---

## Notification Service

### NotificationsController — `/api/notifications`

| Method | Route                             | Auth      | Description                                                      |
| ------ | --------------------------------- | --------- | ---------------------------------------------------------------- |
| GET    | `/api/notifications`              | Authorize | List notifications (paginated: `page`, `pageSize`, `unreadOnly`) |
| GET    | `/api/notifications/unread-count` | Authorize | Get unread notification count                                    |
| PUT    | `/api/notifications/{id}/read`    | Authorize | Mark notification as read                                        |
| PUT    | `/api/notifications/read-all`     | Authorize | Mark all notifications as read                                   |
| GET    | `/api/notifications/preferences`  | Authorize | Get notification preferences                                     |
| PUT    | `/api/notifications/preferences`  | Authorize | Update notification preferences                                  |
| DELETE | `/api/notifications/{id}`         | Authorize | Delete a notification                                            |

No events published — this service is a pure consumer.

---

## Availability Service

### AvailabilityController — `/api/availability`

| Method | Route                                               | Auth      | Description                                                  |
| ------ | --------------------------------------------------- | --------- | ------------------------------------------------------------ |
| POST   | `/api/availability`                                 | Host      | Create availability period with pricing                      |
| PUT    | `/api/availability/{id}`                            | Host      | Update period/pricing (blocked if reservations exist)        |
| DELETE | `/api/availability/{id}`                            | Host      | Delete availability period (blocked if reservations exist)   |
| GET    | `/api/availability/{id}`                            | Anonymous | Get availability by ID                                       |
| GET    | `/api/availability/accommodation/{accommodationId}` | Anonymous | List availability for accommodation (`availableOnly` filter) |
| GET    | `/api/availability/internal/check`                  | Anonymous | Service-to-service: check availability + price for dates     |

**Create** — `POST /api/availability`
```json
{
  "accommodationId": "guid",
  "fromDate": "2026-06-01",
  "toDate": "2026-09-01",
  "price": 120.00,
  "priceType": "PerUnit | PerGuest",
  "priceModifiers": { "weekend": 1.2, "holiday": 1.5 }
}
```
Returns `AvailabilityResponse { id, accommodationId, fromDate, toDate, price, priceType, priceModifiers, isAvailable }`.

**Internal Check** — `GET /api/availability/internal/check?accommodationId=...&checkIn=...&checkOut=...`
Returns `CheckAvailabilityResponse { isAvailable, price?: { pricePerNight, priceType, nights, totalPrice, priceModifiers } }`.

**Events published:** `AvailabilityUpdated`

---

## Reservation Service

### ReservationsController — `/api/reservations`

| Method | Route                                       | Auth      | Description                                                                        |
| ------ | ------------------------------------------- | --------- | ---------------------------------------------------------------------------------- |
| POST   | `/api/reservations`                         | Guest     | Create reservation (validates availability, guest count; auto-approves if enabled) |
| GET    | `/api/reservations/{id}`                    | Authorize | Get reservation (guest or host only)                                               |
| GET    | `/api/reservations/mine`                    | Guest     | List guest's reservations (`status` filter)                                        |
| GET    | `/api/reservations/host`                    | Host      | List host's incoming reservations (`status` filter)                                |
| DELETE | `/api/reservations/{id}`                    | Guest     | Delete pending reservation                                                         |
| PUT    | `/api/reservations/{id}/cancel`             | Guest     | Cancel approved reservation (≥ 1 day before start)                                 |
| PUT    | `/api/reservations/{id}/approve`            | Host      | Approve pending reservation (auto-rejects overlapping)                             |
| PUT    | `/api/reservations/{id}/reject`             | Host      | Reject pending reservation (optional reason)                                       |
| GET    | `/api/reservations/guest-history/{guestId}` | Host      | View guest's cancellation stats                                                    |

### ReservationsInternalController — `/api/reservations/internal`

| Method | Route                                            | Auth     | Description                                       |
| ------ | ------------------------------------------------ | -------- | ------------------------------------------------- |
| GET    | `/api/reservations/internal/can-delete/{userId}` | Internal | Check if user can safely delete account           |
| GET    | `/api/reservations/internal/has-reservations`    | Internal | Check if accommodation has reservations in period |
| GET    | `/api/reservations/internal/completed`           | Internal | Check if guest completed a stay at target         |

**Events published:** `ReservationCreated`, `ReservationApproved`, `ReservationRejected`, `ReservationCancelled`

---

## Rating Service

### RatingsController — `/api/ratings`

| Method | Route                                    | Auth      | Description                                                           |
| ------ | ---------------------------------------- | --------- | --------------------------------------------------------------------- |
| POST   | `/api/ratings`                           | Guest     | Rate host or accommodation (must have completed stay; one per target) |
| PUT    | `/api/ratings/{id}`                      | Guest     | Update own rating                                                     |
| DELETE | `/api/ratings/{id}`                      | Guest     | Delete own rating                                                     |
| GET    | `/api/ratings/{id}`                      | Anonymous | Get rating by ID                                                      |
| GET    | `/api/ratings/target/{targetId}`         | Anonymous | List all ratings for a target (`targetType` filter)                   |
| GET    | `/api/ratings/target/{targetId}/summary` | Anonymous | Get average score + count                                             |
| GET    | `/api/ratings/mine`                      | Guest     | List guest's own ratings                                              |

**Create** — `POST /api/ratings`
```json
{
  "targetId": "guid",
  "targetType": "Accommodation | Host",
  "score": 4,
  "comment": "Great place!"
}
```
Returns `RatingResponse { id, guestId, targetId, targetType, score, comment, createdTimestamp, modifiedTimestamp }`.

**Events published:** `AccommodationRated`, `HostRated`

---

## Search Service

### SearchController — `/api/search`

| Method | Route                           | Auth      | Description                                    |
| ------ | ------------------------------- | --------- | ---------------------------------------------- |
| GET    | `/api/search`                   | Anonymous | Search accommodations with filters (paginated) |
| GET    | `/api/search/{accommodationId}` | Anonymous | Get single indexed accommodation document      |

**Search** — `GET /api/search`

Query parameters:
- `Location` — regex filter on location
- `NumberOfGuests` — accommodation must support this guest count
- `CheckIn`, `CheckOut` — date range availability filter
- `MinPrice`, `MaxPrice` — price range filter
- `MinRating` — minimum average rating
- `Amenities` — comma-separated required amenities
- `Page` (default 1), `PageSize` (default 12)

Returns `SearchPagedResponse { items: SearchResponse[], page, pageSize, totalCount, totalPages }`.

Each `SearchResponse`: `{ accommodationId, hostId, name, location, amenities, pictures, minGuests, maxGuests, autoApproval, unitPrice?, totalPrice?, averageRating, totalRatings }`.

No events published — this service is a pure consumer.

---

## Event Bus Summary

### Events Published

| Service       | Event                  | Trigger                                         |
| ------------- | ---------------------- | ----------------------------------------------- |
| identity      | `UserRegistered`       | User registers                                  |
| identity      | `UserUpdated`          | Profile or credentials updated                  |
| identity      | `UserDeleted`          | Account deleted                                 |
| accommodation | `AccommodationCreated` | New listing created                             |
| accommodation | `AccommodationUpdated` | Listing updated                                 |
| accommodation | `AccommodationDeleted` | Listing deleted (or cascade from host deletion) |
| cdn           | `CdnAssetProcessed`    | Image uploaded                                  |
| cdn           | `CdnAssetDeleted`      | Asset deleted                                   |
| availability  | `AvailabilityUpdated`  | Period created or updated                       |
| reservation   | `ReservationCreated`   | Reservation submitted                           |
| reservation   | `ReservationApproved`  | Reservation approved (manual or auto)           |
| reservation   | `ReservationRejected`  | Reservation rejected (manual or auto-overlap)   |
| reservation   | `ReservationCancelled` | Guest cancels                                   |
| rating        | `AccommodationRated`   | Accommodation rated                             |
| rating        | `HostRated`            | Host rated                                      |

### Consumers

| Service       | Consumes               | Action                                     |
| ------------- | ---------------------- | ------------------------------------------ |
| accommodation | `UserDeleted`          | Delete all host's accommodations (cascade) |
| accommodation | `CdnAssetProcessed`    | Add picture URL to accommodation           |
| accommodation | `CdnAssetDeleted`      | Remove picture URL from accommodation      |
| availability  | `AccommodationDeleted` | Remove all availability windows            |
| availability  | `ReservationApproved`  | Mark dates unavailable                     |
| availability  | `ReservationCancelled` | Mark dates available again                 |
| reservation   | `UserDeleted`          | Cancel active reservations for user        |
| reservation   | `AccommodationDeleted` | Cancel reservations for accommodation      |
| rating        | `UserDeleted`          | Remove all ratings by user                 |
| rating        | `AccommodationDeleted` | Remove ratings for accommodation           |
| search        | `AccommodationCreated` | Insert index document                      |
| search        | `AccommodationUpdated` | Update index document                      |
| search        | `AccommodationDeleted` | Delete index document                      |
| search        | `AccommodationRated`   | Update average rating                      |
| search        | `AvailabilityUpdated`  | Update availability windows                |
| notification  | `ReservationCreated`   | Notify host                                |
| notification  | `ReservationApproved`  | Notify guest                               |
| notification  | `ReservationCancelled` | Notify host                                |
| notification  | `ReservationRejected`  | Notify guest                               |
| notification  | `AccommodationRated`   | Notify host                                |
| notification  | `HostRated`            | Notify host                                |

### Service-to-Service HTTP

| Caller       | Callee        | Endpoint                                             | Purpose                                   |
| ------------ | ------------- | ---------------------------------------------------- | ----------------------------------------- |
| identity     | reservation   | `GET /api/reservations/internal/can-delete/{userId}` | Pre-check before account deletion         |
| availability | reservation   | `GET /api/reservations/internal/has-reservations`    | Block changes if reservations exist       |
| reservation  | accommodation | `GET /api/accommodation/{id}`                        | Resolve host, auto-approval, guest limits |
| reservation  | availability  | `GET /api/availability/internal/check`               | Verify availability + get pricing         |
| rating       | reservation   | `GET /api/reservations/internal/completed`           | Verify completed stay                     |
| rating       | accommodation | `GET /api/accommodation/{id}`                        | Resolve HostId for accommodation ratings  |
