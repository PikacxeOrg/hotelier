#!/bin/bash

# =============================================================================
# Seed Data Script
# Populates all databases with test data for local development.
#
# Prereqs: docker compose services running (postgres, mongodb)
# Usage  : bash etc/scripts/seed-data.sh [-n COUNT] [-m MODE]
#
# -n COUNT  Number of EXTRA entities to generate beyond the core test data.
#           Each unit adds: 1 host, 2 guests, 2 accommodations,
#           4 availability windows, ~8 reservations, ~3 ratings.
#           Default: 0 (core data only).
#
# -m MODE   Deployment mode: compose (default), swarm, k8s.
#           Controls how the script finds containers and service URLs.
#
# Examples:
#   bash etc/scripts/seed-data.sh          # core 3 users, 2 accommodations
#   bash etc/scripts/seed-data.sh -n 5     # + 5 hosts, 10 guests, 10 accoms…
#   bash etc/scripts/seed-data.sh -n 50    # stress test (~750 reservations)
# =============================================================================

set -euo pipefail

# -- CLI args ----------------------------------------------------------------
EXTRA_COUNT=0
DEPLOY_MODE="compose"
while getopts "n:m:" opt; do
    case $opt in
        n) EXTRA_COUNT="$OPTARG" ;;
        m) DEPLOY_MODE="$OPTARG" ;;
        *) echo "Usage: $0 [-n COUNT] [-m compose|swarm|k8s]" >&2; exit 1 ;;
    esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR]${NC}   $*"; }

# -- Configuration -----------------------------------------------------------

PG_USER="${PG_USER:-hotelier}"
PG_PASS="${PG_PASS:-hotelier}"
MONGO_USER="${MONGO_USER:-hotelier}"
MONGO_PASS="${MONGO_PASS:-hotelier}"

# Resolve container names and service URLs based on deployment mode
case "$DEPLOY_MODE" in
    compose)
        PG_CONTAINER="${PG_CONTAINER:-hotelier-postgres-1}"
        MONGO_CONTAINER="${MONGO_CONTAINER:-hotelier-mongodb-1}"
        IDENTITY_URL="${IDENTITY_URL:-http://localhost:5003}"
        CDN_URL="${CDN_URL:-http://localhost:5008}"
        ;;
    swarm)
        # In swarm, container names are randomized — find them by service label
        PG_CONTAINER="${PG_CONTAINER:-$(docker ps --filter "label=com.docker.swarm.service.name=hotelier_postgres" --format '{{.Names}}' | head -1)}"
        MONGO_CONTAINER="${MONGO_CONTAINER:-$(docker ps --filter "label=com.docker.swarm.service.name=hotelier_mongodb" --format '{{.Names}}' | head -1)}"
        # Identity and CDN services publish the same ports as compose
        IDENTITY_URL="${IDENTITY_URL:-http://localhost:5003}"
        CDN_URL="${CDN_URL:-http://localhost:5008}"
        ;;
    k8s)
        K8S_NAMESPACE="${K8S_NAMESPACE:-hotelier}"
        DB_NAMESPACE="${DB_NAMESPACE:-databases}"
        # Find database pods by deployment label
        PG_POD=$(kubectl get pods -n "$DB_NAMESPACE" -l app=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        MONGO_POD=$(kubectl get pods -n "$DB_NAMESPACE" -l app=mongodb -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        PG_CONTAINER=""
        MONGO_CONTAINER=""
        IDENTITY_URL="${IDENTITY_URL:-http://localhost:5003}"
        CDN_URL="${CDN_URL:-http://localhost:5008}"
        info "K8s mode: you MUST port-forward identity & CDN before running this script:"
        info "  kubectl port-forward -n hotelier svc/identity-service 5003:80 &"
        info "  kubectl port-forward -n hotelier svc/cdn-service 5008:80 &"
        if [ -z "$PG_POD" ] || [ -z "$MONGO_POD" ]; then
            err "Could not find database pods in namespace '$DB_NAMESPACE'"
            exit 1
        fi
        info "Found PG pod: $PG_POD, Mongo pod: $MONGO_POD"
        ;;
    *)
        err "Unknown mode: $DEPLOY_MODE (use compose, swarm, or k8s)"
        exit 1
        ;;
esac
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLACEHOLDER_IMG="${SCRIPT_DIR}/../seed-images/placeholder.jpg"

psql_cmd() {
    local db="$1"; shift
    if [[ "$DEPLOY_MODE" == "k8s" ]]; then
        kubectl exec -i -n "$DB_NAMESPACE" "$PG_POD" -- \
            env PGPASSWORD="$PG_PASS" psql -U "$PG_USER" -d "$db" -q -t "$@"
    else
        docker exec -i -e PGPASSWORD="$PG_PASS" "$PG_CONTAINER" \
            psql -U "$PG_USER" -d "$db" -q -t "$@"
    fi
}

mongo_cmd() {
    local db="$1"; shift
    if [[ "$DEPLOY_MODE" == "k8s" ]]; then
        kubectl exec -i -n "$DB_NAMESPACE" "$MONGO_POD" -- \
            mongosh "mongodb://${MONGO_USER}:${MONGO_PASS}@localhost:27017/${db}?authSource=admin" --quiet "$@"
    else
        docker exec -i "$MONGO_CONTAINER" \
            mongosh "mongodb://${MONGO_USER}:${MONGO_PASS}@localhost:27017/${db}?authSource=admin" --quiet "$@"
    fi
}

# -- Deterministic UUID generator --------------------------------------------
# uuid_from <namespace> <index>  →  deterministic UUID (idempotent reruns)
uuid_from() {
    local raw
    raw=$(echo -n "${1}-${2}" | md5sum | head -c 32)
    echo "${raw:0:8}-${raw:8:4}-${raw:12:4}-${raw:16:4}-${raw:20:12}"
}

# -- Fixed core IDs ----------------------------------------------------------
HOST_USER_ID="aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa"
GUEST_USER_ID="bbbbbbbb-2222-2222-2222-bbbbbbbbbbbb"
GUEST2_USER_ID="cccccccc-3333-3333-3333-cccccccccccc"

ACCOM1_ID="11111111-aaaa-aaaa-aaaa-111111111111"
ACCOM2_ID="22222222-bbbb-bbbb-bbbb-222222222222"

AVAIL1_ID="11111111-a1a1-a1a1-a1a1-111111111111"
AVAIL2_ID="22222222-a2a2-a2a2-a2a2-222222222222"
AVAIL3_ID="33333333-a3a3-a3a3-a3a3-333333333333"
AVAIL4_ID="44444444-a4a4-a4a4-a4a4-444444444444"

RES_PAST1_ID="11111111-b1b1-b1b1-b1b1-111111111111"
RES_PAST2_ID="22222222-b2b2-b2b2-b2b2-222222222222"
RES_PAST3_ID="33333333-b3b3-b3b3-b3b3-333333333333"
RES_PENDING_ID="44444444-b4b4-b4b4-b4b4-444444444444"
RES_FUTURE_ID="55555555-b5b5-b5b5-b5b5-555555555555"
RES_CANCELLED_ID="66666666-b6b6-b6b6-b6b6-666666666666"

RATING1_ID="11111111-c1c1-c1c1-c1c1-111111111111"

# Password: "Test1234!" for all users (BCrypt hash, cost 12)
BCRYPT_HASH='$2b$12$8bj8pdrhZy90NnRebvWPQ.tpTYPYTgjguK0IjRho42Z11ZvlQdyhy'

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# -- Data pools for random generation ----------------------------------------
FIRST_NAMES=(Emma Liam Olivia Noah Ava Elijah Sophia James Isabella Lucas Mia
    Benjamin Charlotte Henry Amelia Alexander Harper Daniel Evelyn Michael Abigail
    Ethan Emily Jacob Ella Matthew Scarlett Sebastian Aria Jack Chloe Aiden Zoey
    Owen Nora Samuel Lily Joseph Hannah David Addison Carter Aubrey Wyatt Stella)

LAST_NAMES=(Smith Johnson Williams Brown Jones Garcia Miller Davis Rodriguez
    Martinez Hernandez Lopez Gonzalez Wilson Anderson Thomas Taylor Moore Jackson
    Martin Lee Perez Thompson White Harris Sanchez Clark Ramirez Lewis Robinson
    Walker Young Allen King Wright Scott Torres Nguyen Hill Flores Green Adams
    Nelson Baker Hall Rivera Campbell Mitchell Carter Roberts)

CITIES=("Split, Croatia" "Zagreb, Croatia" "Zadar, Croatia" "Rovinj, Croatia"
    "Hvar, Croatia" "Sibenik, Croatia" "Opatija, Croatia" "Makarska, Croatia"
    "Korcula, Croatia" "Trogir, Croatia" "Porec, Croatia" "Bol, Croatia"
    "Cavtat, Croatia" "Primosten, Croatia" "Mali Losinj, Croatia"
    "Dubrovnik, Croatia" "Plitvice, Croatia" "Rijeka, Croatia"
    "Pula, Croatia" "Biograd, Croatia")

ACCOM_TYPES=("Apartment" "Villa" "Cottage" "Studio" "Penthouse" "Bungalow"
    "Loft" "Chalet" "Cabin" "Suite" "Farmhouse" "Townhouse")

ACCOM_ADJECTIVES=("Sunny" "Cozy" "Luxury" "Charming" "Modern" "Rustic"
    "Elegant" "Seaside" "Hilltop" "Central" "Quiet" "Panoramic"
    "Historic" "Romantic" "Spacious" "Boutique" "Exclusive" "Tropical")

ALL_AMENITIES=("WiFi" "Pool" "Parking" "Air Conditioning" "Fireplace"
    "Balcony" "Garden" "BBQ" "Washing Machine" "Dishwasher" "TV"
    "Sea View" "Mountain View" "Pet Friendly" "Gym" "Sauna" "Hot Tub"
    "Bike Rental" "Kayak" "Kitchen")

REVIEW_COMMENTS=(
    "Wonderful stay! Everything was perfect."
    "Great location and very clean. Would come back."
    "The host was incredibly helpful and responsive."
    "Beautiful property, exactly as described."
    "Loved the amenities. Kids had a blast!"
    "Quiet and relaxing, exactly what we needed."
    "Amazing views from the balcony!"
    "Good value for money. Recommended."
    "Perfect for a weekend getaway."
    "Spotless clean and well-equipped kitchen."
    "The pool was the highlight of our trip."
    "Cozy place with great local restaurant recommendations from host."
    "Would definitely book again for next summer."
    "Nice place overall, minor issues with hot water."
    "Fantastic hospitality. Felt like home."
)

# Helpers
rand_elem()  { local arr=("$@"); echo "${arr[RANDOM % ${#arr[@]}]}"; }
rand_range() { echo $(( RANDOM % ($2 - $1 + 1) + $1 )); }
rand_amenities() {
    local count
    count=$(rand_range 3 7)
    printf '%s\n' "${ALL_AMENITIES[@]}" | shuf -n "$count" | \
        awk 'BEGIN{printf "["} NR>1{printf ", "} {printf "\"%s\"", $0} END{printf "]"}'
}
rand_date_between() {
    local s e
    s=$(date -d "$1" +%s)
    e=$(date -d "$2" +%s)
    local diff=$(( e - s ))
    local offset=$(( RANDOM % (diff / 86400 + 1) ))
    date -u -d "@$(( s + offset * 86400 ))" +%Y-%m-%d
}
add_days() {
    date -u -d "$1 + $2 days" +%Y-%m-%d
}

echo ""
echo "============================================================"
echo "  Hotelier – Seed Data  (extra batches: ${EXTRA_COUNT})"
echo "============================================================"
echo ""

# =============================================================================
# 1. IDENTITY SERVICE – core users
# =============================================================================
info "Seeding identity service (core users)..."

psql_cmd hotelier_identity <<SQL
INSERT INTO "Users" ("Id", "Username", "PasswordHash", "Name", "LastName", "Email", "Address", "UserType", "NotificationPreferences", "CreatedBy", "ModifiedBy", "CreatedTimestamp", "ModifiedTimestamp")
VALUES
    ('${HOST_USER_ID}', 'host1', '${BCRYPT_HASH}', 'John', 'Host', 'host1@test.com', '123 Host Street, City', 1,
     '{"reservation_created": true, "reservation_cancelled": true, "rating_received": true}',
     'seed', 'seed', '${NOW}', '${NOW}'),
    ('${GUEST_USER_ID}', 'guest1', '${BCRYPT_HASH}', 'Jane', 'Guest', 'guest1@test.com', '456 Guest Ave, Town', 0,
     '{"reservation_approved": true, "reservation_rejected": true}',
     'seed', 'seed', '${NOW}', '${NOW}'),
    ('${GUEST2_USER_ID}', 'guest2', '${BCRYPT_HASH}', 'Alice', 'Traveler', 'guest2@test.com', '789 Traveler Blvd, Village', 0,
     '{"reservation_approved": true, "reservation_rejected": true}',
     'seed', 'seed', '${NOW}', '${NOW}')
ON CONFLICT ("Id") DO UPDATE SET
    "Username" = EXCLUDED."Username",
    "PasswordHash" = EXCLUDED."PasswordHash",
    "ModifiedTimestamp" = '${NOW}';
SQL

ok "Identity: 3 core users (host1, guest1, guest2)"

# =============================================================================
# 2. ACCOMMODATION SERVICE – core properties
# =============================================================================
info "Seeding accommodation service (core)..."

psql_cmd hotelier_accommodation <<SQL
INSERT INTO "Accommodations" ("Id", "Name", "Location", "Amenities", "Pictures", "MinGuests", "MaxGuests", "HostId", "AutoApproval", "CreatedBy", "ModifiedBy", "CreatedTimestamp", "ModifiedTimestamp")
VALUES
    ('${ACCOM1_ID}', 'Seaside Villa', 'Dubrovnik, Croatia',
     '["WiFi", "Pool", "Parking", "Air Conditioning"]', '[]',
     1, 6, '${HOST_USER_ID}', true, 'seed', 'seed', '${NOW}', '${NOW}'),
    ('${ACCOM2_ID}', 'Mountain Cabin', 'Plitvice Lakes, Croatia',
     '["WiFi", "Fireplace", "Hiking Trails", "BBQ"]', '[]',
     2, 4, '${HOST_USER_ID}', false, 'seed', 'seed', '${NOW}', '${NOW}')
ON CONFLICT ("Id") DO UPDATE SET
    "Name" = EXCLUDED."Name", "Location" = EXCLUDED."Location",
    "Amenities" = EXCLUDED."Amenities", "ModifiedTimestamp" = '${NOW}';
SQL

ok "Accommodation: 2 core properties"

# =============================================================================
# 3. AVAILABILITY SERVICE – core windows
# =============================================================================
info "Seeding availability service (core)..."

psql_cmd hotelier_availability <<SQL
INSERT INTO "Availabilities" ("Id", "AccommodationId", "FromDate", "ToDate", "Price", "PriceType", "PriceModifiers", "IsAvailable", "CreatedBy", "ModifiedBy", "CreatedTimestamp", "ModifiedTimestamp")
VALUES
    ('${AVAIL1_ID}', '${ACCOM1_ID}', '2025-12-01', '2025-12-31', 120.00, 1, '{}', true, 'seed', 'seed', '${NOW}', '${NOW}'),
    ('${AVAIL2_ID}', '${ACCOM2_ID}', '2026-01-10', '2026-02-10', 85.00, 0, '{"weekend": 1.15}', true, 'seed', 'seed', '${NOW}', '${NOW}'),
    ('${AVAIL3_ID}', '${ACCOM1_ID}', '2026-03-01', '2026-06-30', 150.00, 1, '{"summer": 1.25}', true, 'seed', 'seed', '${NOW}', '${NOW}'),
    ('${AVAIL4_ID}', '${ACCOM2_ID}', '2026-04-01', '2026-09-30', 95.00, 0, '{}', true, 'seed', 'seed', '${NOW}', '${NOW}')
ON CONFLICT ("Id") DO UPDATE SET
    "FromDate" = EXCLUDED."FromDate", "ToDate" = EXCLUDED."ToDate",
    "Price" = EXCLUDED."Price", "IsAvailable" = EXCLUDED."IsAvailable",
    "ModifiedTimestamp" = '${NOW}';
SQL

ok "Availability: 4 core windows"

# =============================================================================
# 4. RESERVATION SERVICE – core reservations
# =============================================================================
info "Seeding reservation service (core)..."

psql_cmd hotelier_reservation <<SQL
INSERT INTO "Reservations" ("Id", "UserId", "AccommodationId", "HostId", "FromDate", "ToDate", "NumOfGuests", "Status", "CreatedBy", "ModifiedBy", "CreatedTimestamp", "ModifiedTimestamp")
VALUES
    ('${RES_PAST1_ID}', '${GUEST_USER_ID}', '${ACCOM1_ID}', '${HOST_USER_ID}',
     '2025-12-05', '2025-12-12', 2, 1,
     '${GUEST_USER_ID}', 'system:auto-approved', '2025-11-20T10:00:00Z', '2025-11-20T10:00:00Z'),
    ('${RES_PAST2_ID}', '${GUEST_USER_ID}', '${ACCOM2_ID}', '${HOST_USER_ID}',
     '2026-01-15', '2026-01-22', 3, 1,
     '${GUEST_USER_ID}', '${HOST_USER_ID}', '2025-12-30T14:00:00Z', '2025-12-31T09:00:00Z'),
    ('${RES_PAST3_ID}', '${GUEST2_USER_ID}', '${ACCOM1_ID}', '${HOST_USER_ID}',
     '2025-12-15', '2025-12-20', 4, 1,
     '${GUEST2_USER_ID}', 'system:auto-approved', '2025-11-28T16:00:00Z', '2025-11-28T16:00:00Z'),
    ('${RES_PENDING_ID}', '${GUEST_USER_ID}', '${ACCOM2_ID}', '${HOST_USER_ID}',
     '2026-05-01', '2026-05-07', 2, 0,
     '${GUEST_USER_ID}', 'seed', '${NOW}', '${NOW}'),
    ('${RES_FUTURE_ID}', '${GUEST2_USER_ID}', '${ACCOM1_ID}', '${HOST_USER_ID}',
     '2026-04-10', '2026-04-17', 3, 1,
     '${GUEST2_USER_ID}', 'system:auto-approved', '${NOW}', '${NOW}'),
    ('${RES_CANCELLED_ID}', '${GUEST_USER_ID}', '${ACCOM1_ID}', '${HOST_USER_ID}',
     '2026-03-20', '2026-03-25', 2, 3,
     '${GUEST_USER_ID}', '${GUEST_USER_ID}', '${NOW}', '${NOW}')
ON CONFLICT ("Id") DO UPDATE SET
    "Status" = EXCLUDED."Status", "FromDate" = EXCLUDED."FromDate",
    "ToDate" = EXCLUDED."ToDate", "ModifiedTimestamp" = '${NOW}';
SQL

ok "Reservation: 6 core reservations"

# =============================================================================
# 5. RATING SERVICE – core ratings
# =============================================================================
info "Seeding rating service (core)..."

psql_cmd hotelier_rating <<SQL
INSERT INTO "Ratings" ("Id", "GuestId", "TargetId", "TargetType", "Score", "Comment", "CreatedBy", "ModifiedBy", "CreatedTimestamp", "ModifiedTimestamp")
VALUES
    ('${RATING1_ID}', '${GUEST2_USER_ID}', '${ACCOM1_ID}', 0, 5,
     'Amazing seaside property! The pool was incredible and the view was breathtaking.',
     '${GUEST2_USER_ID}', '${GUEST2_USER_ID}', '2025-12-22T10:00:00Z', '2025-12-22T10:00:00Z')
ON CONFLICT ("Id") DO UPDATE SET
    "Score" = EXCLUDED."Score", "Comment" = EXCLUDED."Comment",
    "ModifiedTimestamp" = '${NOW}';
SQL

ok "Rating: 1 core review"

# =============================================================================
# 6. SEARCH SERVICE – core docs
# =============================================================================
info "Seeding search service (core)..."

mongo_cmd hotelier_search --eval "
db.accommodations.updateOne(
    { _id: '${ACCOM1_ID}' },
    { \$set: {
        HostId: '${HOST_USER_ID}', Name: 'Seaside Villa',
        Location: 'Dubrovnik, Croatia',
        Amenities: ['WiFi','Pool','Parking','Air Conditioning'],
        Pictures: [], MinGuests: 1, MaxGuests: 6, AutoApproval: true,
        AvailabilityWindows: [
            { FromDate: '2026-03-01', ToDate: '2026-06-30', Price: NumberDecimal('150.00'), PriceType: 'PerUnit', IsAvailable: true }
        ],
        AverageRating: 5.0, TotalRatings: 1, UpdatedAt: new Date()
    }},
    { upsert: true }
);
db.accommodations.updateOne(
    { _id: '${ACCOM2_ID}' },
    { \$set: {
        HostId: '${HOST_USER_ID}', Name: 'Mountain Cabin',
        Location: 'Plitvice Lakes, Croatia',
        Amenities: ['WiFi','Fireplace','Hiking Trails','BBQ'],
        Pictures: [], MinGuests: 2, MaxGuests: 4, AutoApproval: false,
        AvailabilityWindows: [
            { FromDate: '2026-04-01', ToDate: '2026-09-30', Price: NumberDecimal('95.00'), PriceType: 'PerGuest', IsAvailable: true }
        ],
        AverageRating: 0.0, TotalRatings: 0, UpdatedAt: new Date()
    }},
    { upsert: true }
);
print('Search: 2 core docs upserted');
"

ok "Search: 2 core documents"

# =============================================================================
# 7. NOTIFICATION SERVICE – core data
# =============================================================================
info "Seeding notification service (core)..."

mongo_cmd hotelier_notification --eval "
db.notification_preferences.updateOne(
    { _id: '${HOST_USER_ID}' },
    { \$set: { Preferences: { reservation_created: true, reservation_cancelled: true, rating_received: true } }},
    { upsert: true }
);
db.notification_preferences.updateOne(
    { _id: '${GUEST_USER_ID}' },
    { \$set: { Preferences: { reservation_approved: true, reservation_rejected: true } }},
    { upsert: true }
);
db.notifications.insertMany([
    { From: '${HOST_USER_ID}', To: '${GUEST_USER_ID}', Topic: 'Reservation Approved',
      Message: 'Your reservation at Mountain Cabin (Jan 15-22) has been approved!',
      IsRead: false, CreatedAt: new Date('2025-12-31T09:00:00Z') },
    { From: '${GUEST2_USER_ID}', To: '${HOST_USER_ID}', Topic: 'New Rating',
      Message: 'You received a 5-star rating from Alice Traveler for Seaside Villa.',
      IsRead: true, CreatedAt: new Date('2025-12-22T10:00:00Z') },
    { From: '${GUEST_USER_ID}', To: '${HOST_USER_ID}', Topic: 'Reservation Cancelled',
      Message: 'Jane Guest cancelled their reservation at Seaside Villa (Mar 20-25).',
      IsRead: false, CreatedAt: new Date() }
]);
print('Notifications: core data inserted');
"

ok "Notification: core data"

# =============================================================================
# CORE SUMMARY
# =============================================================================
echo ""
echo "  -- Core data -----------------------------------------"
echo "  Users: 3 | Accommodations: 2 | Availability: 4"
echo "  Reservations: 6 | Ratings: 1 | Notifications: 3"

# =============================================================================
# PLACEHOLDER IMAGE UPLOAD (only if -n > 0 and CDN is reachable)
# =============================================================================
PLACEHOLDER_URL=""

if (( EXTRA_COUNT > 0 )); then
    info "Uploading placeholder image for generated accommodations..."

    if [[ ! -f "$PLACEHOLDER_IMG" ]]; then
        warn "Placeholder image not found at ${PLACEHOLDER_IMG} — generated accommodations will have no pictures."
    else
        # Step 1: Log in as host1 to get a JWT
        LOGIN_RESP=$(curl -s -w "\n%{http_code}" -X POST "${IDENTITY_URL}/api/auth/login" \
            -H "Content-Type: application/json" \
            -d '{"username":"host1","password":"Test1234!"}' 2>/dev/null) || true

        HTTP_CODE=$(echo "$LOGIN_RESP" | tail -1)
        LOGIN_BODY=$(echo "$LOGIN_RESP" | sed '$d')

        if [[ "$HTTP_CODE" == "200" ]]; then
            ACCESS_TOKEN=$(echo "$LOGIN_BODY" | grep -o '"accessToken":"[^"]*"' | head -1 | cut -d'"' -f4)

            if [[ -n "$ACCESS_TOKEN" ]]; then
                # Step 2: Upload placeholder image to CDN
                UPLOAD_RESP=$(curl -s -w "\n%{http_code}" -X POST "${CDN_URL}/api/assets" \
                    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
                    -F "files=@${PLACEHOLDER_IMG};type=image/jpeg" 2>/dev/null) || true

                UPLOAD_CODE=$(echo "$UPLOAD_RESP" | tail -1)
                UPLOAD_BODY=$(echo "$UPLOAD_RESP" | sed '$d')

                if [[ "$UPLOAD_CODE" == "201" ]]; then
                    PLACEHOLDER_URL=$(echo "$UPLOAD_BODY" | grep -o '"url":"[^"]*"' | head -1 | cut -d'"' -f4)
                    if [[ -n "$PLACEHOLDER_URL" ]]; then
                        ok "Placeholder uploaded → ${PLACEHOLDER_URL}"
                    else
                        warn "Could not parse URL from CDN response — generated accommodations will have no pictures."
                    fi
                else
                    warn "CDN upload failed (HTTP ${UPLOAD_CODE}) — generated accommodations will have no pictures."
                fi
            else
                warn "Could not parse access token — generated accommodations will have no pictures."
            fi
        else
            warn "Identity login failed (HTTP ${HTTP_CODE}) — generated accommodations will have no pictures."
        fi
    fi
fi

# =============================================================================
# EXTRA GENERATED DATA (only if -n > 0)
# =============================================================================

if (( EXTRA_COUNT > 0 )); then
    echo ""
    info "Generating ${EXTRA_COUNT} extra batch(es) of data..."

    declare -a GEN_HOST_IDS=()
    declare -a GEN_GUEST_IDS=()
    declare -a GEN_ACCOM_IDS=()
    declare -a GEN_ACCOM_HOSTS=()

    TOTAL_USERS=0
    TOTAL_ACCOMS=0
    TOTAL_AVAILS=0
    TOTAL_RESERVATIONS=0
    TOTAL_RATINGS=0
    TOTAL_SEARCH=0
    TOTAL_NOTIFS=0

    # =========================================================================
    # Phase 1: Generate users (1 host + 2 guests per batch)
    # =========================================================================
    info "Phase 1/5: Generating users..."

    USER_SQL=""
    for (( i = 1; i <= EXTRA_COUNT; i++ )); do
        host_id=$(uuid_from "host" "$i")
        guest_a_id=$(uuid_from "guestA" "$i")
        guest_b_id=$(uuid_from "guestB" "$i")

        GEN_HOST_IDS+=("$host_id")
        GEN_GUEST_IDS+=("$guest_a_id" "$guest_b_id")

        h_first=$(rand_elem "${FIRST_NAMES[@]}")
        h_last=$(rand_elem "${LAST_NAMES[@]}")
        ga_first=$(rand_elem "${FIRST_NAMES[@]}")
        ga_last=$(rand_elem "${LAST_NAMES[@]}")
        gb_first=$(rand_elem "${FIRST_NAMES[@]}")
        gb_last=$(rand_elem "${LAST_NAMES[@]}")

        city=$(rand_elem "${CITIES[@]}")

        USER_SQL+="
INSERT INTO \"Users\" (\"Id\", \"Username\", \"PasswordHash\", \"Name\", \"LastName\", \"Email\", \"Address\", \"UserType\", \"NotificationPreferences\", \"CreatedBy\", \"ModifiedBy\", \"CreatedTimestamp\", \"ModifiedTimestamp\")
VALUES
    ('${host_id}', 'host_${i}', '${BCRYPT_HASH}', '${h_first}', '${h_last}', 'host_${i}@test.com', '${i} Host Rd, ${city}', 1,
     '{\"reservation_created\": true, \"reservation_cancelled\": true, \"rating_received\": true}',
     'seed', 'seed', '${NOW}', '${NOW}'),
    ('${guest_a_id}', 'guest_${i}a', '${BCRYPT_HASH}', '${ga_first}', '${ga_last}', 'guest_${i}a@test.com', '${i}A Guest St, ${city}', 0,
     '{\"reservation_approved\": true, \"reservation_rejected\": true}',
     'seed', 'seed', '${NOW}', '${NOW}'),
    ('${guest_b_id}', 'guest_${i}b', '${BCRYPT_HASH}', '${gb_first}', '${gb_last}', 'guest_${i}b@test.com', '${i}B Guest St, ${city}', 0,
     '{\"reservation_approved\": true, \"reservation_rejected\": true}',
     'seed', 'seed', '${NOW}', '${NOW}')
ON CONFLICT (\"Id\") DO UPDATE SET \"PasswordHash\" = EXCLUDED.\"PasswordHash\", \"ModifiedTimestamp\" = '${NOW}';
"
        TOTAL_USERS=$(( TOTAL_USERS + 3 ))
    done

    echo "$USER_SQL" | psql_cmd hotelier_identity
    ok "Users: ${TOTAL_USERS} extra"

    # =========================================================================
    # Phase 2: Generate accommodations (2 per batch) + availability
    # =========================================================================
    info "Phase 2/5: Generating accommodations & availability..."

    ACCOM_SQL=""
    AVAIL_SQL=""
    SEARCH_JS="var docs = [];"$'\n'

    # Build pictures JSON depending on whether placeholder was uploaded
    if [[ -n "$PLACEHOLDER_URL" ]]; then
        PG_PICTURES_JSON='["'"${PLACEHOLDER_URL}"'"]'
        MONGO_PICTURES_JS="['${PLACEHOLDER_URL}']"
    else
        PG_PICTURES_JSON='[]'
        MONGO_PICTURES_JS='[]'
    fi

    for (( i = 1; i <= EXTRA_COUNT; i++ )); do
        host_id="${GEN_HOST_IDS[$(( i - 1 ))]}"

        for j in 1 2; do
            accom_id=$(uuid_from "accom" "${i}-${j}")
            avail_past_id=$(uuid_from "avail-past" "${i}-${j}")
            avail_future_id=$(uuid_from "avail-future" "${i}-${j}")

            GEN_ACCOM_IDS+=("$accom_id")
            GEN_ACCOM_HOSTS+=("$host_id")

            adj=$(rand_elem "${ACCOM_ADJECTIVES[@]}")
            typ=$(rand_elem "${ACCOM_TYPES[@]}")
            city=$(rand_elem "${CITIES[@]}")
            name="${adj} ${typ}"
            min_g=$(rand_range 1 3)
            max_g=$(rand_range $(( min_g + 1 )) 10)
            auto_approve_int=$(( RANDOM % 2 ))
            auto_approve="false"
            (( auto_approve_int == 1 )) && auto_approve="true"
            price=$(rand_range 50 300)
            price_type=$(( RANDOM % 2 ))  # 0=PerGuest, 1=PerUnit
            amenities=$(rand_amenities)

            past_from=$(rand_date_between "2025-09-01" "2025-11-15")
            past_to=$(add_days "$past_from" "$(rand_range 30 90)")
            future_from=$(rand_date_between "2026-03-15" "2026-05-01")
            future_to=$(add_days "$future_from" "$(rand_range 60 180)")

            ACCOM_SQL+="
INSERT INTO \"Accommodations\" (\"Id\", \"Name\", \"Location\", \"Amenities\", \"Pictures\", \"MinGuests\", \"MaxGuests\", \"HostId\", \"AutoApproval\", \"CreatedBy\", \"ModifiedBy\", \"CreatedTimestamp\", \"ModifiedTimestamp\")
VALUES ('${accom_id}', '${name}', '${city}', '${amenities}', '${PG_PICTURES_JSON}', ${min_g}, ${max_g}, '${host_id}', ${auto_approve}, 'seed', 'seed', '${NOW}', '${NOW}')
ON CONFLICT (\"Id\") DO UPDATE SET \"Name\" = EXCLUDED.\"Name\", \"Pictures\" = EXCLUDED.\"Pictures\", \"ModifiedTimestamp\" = '${NOW}';
"
            AVAIL_SQL+="
INSERT INTO \"Availabilities\" (\"Id\", \"AccommodationId\", \"FromDate\", \"ToDate\", \"Price\", \"PriceType\", \"PriceModifiers\", \"IsAvailable\", \"CreatedBy\", \"ModifiedBy\", \"CreatedTimestamp\", \"ModifiedTimestamp\")
VALUES
    ('${avail_past_id}', '${accom_id}', '${past_from}', '${past_to}', ${price}.00, ${price_type}, '{}', true, 'seed', 'seed', '${NOW}', '${NOW}'),
    ('${avail_future_id}', '${accom_id}', '${future_from}', '${future_to}', ${price}.00, ${price_type}, '{}', true, 'seed', 'seed', '${NOW}', '${NOW}')
ON CONFLICT (\"Id\") DO UPDATE SET \"Price\" = EXCLUDED.\"Price\", \"ModifiedTimestamp\" = '${NOW}';
"
            price_type_str="PerUnit"
            (( price_type == 0 )) && price_type_str="PerGuest"

            SEARCH_JS+="
docs.push({ updateOne: {
    filter: { _id: '${accom_id}' },
    update: { \$set: {
        HostId: '${host_id}', Name: '${name}', Location: '${city}',
        Amenities: ${amenities}, Pictures: ${MONGO_PICTURES_JS}, MinGuests: ${min_g}, MaxGuests: ${max_g},
        AutoApproval: ${auto_approve},
        AvailabilityWindows: [
            { FromDate: '${future_from}', ToDate: '${future_to}', Price: NumberDecimal('${price}.00'), PriceType: '${price_type_str}', IsAvailable: true }
        ],
        AverageRating: 0.0, TotalRatings: 0, UpdatedAt: new Date()
    }},
    upsert: true
}});"$'\n'

            TOTAL_ACCOMS=$(( TOTAL_ACCOMS + 1 ))
            TOTAL_AVAILS=$(( TOTAL_AVAILS + 2 ))
            TOTAL_SEARCH=$(( TOTAL_SEARCH + 1 ))
        done
    done

    echo "$ACCOM_SQL" | psql_cmd hotelier_accommodation
    ok "Accommodations: ${TOTAL_ACCOMS} extra"

    echo "$AVAIL_SQL" | psql_cmd hotelier_availability
    ok "Availability: ${TOTAL_AVAILS} extra windows"

    SEARCH_JS+="if (docs.length > 0) { db.accommodations.bulkWrite(docs); }; print('Search: ' + docs.length + ' extra docs upserted');"
    mongo_cmd hotelier_search --eval "$SEARCH_JS"
    ok "Search: ${TOTAL_SEARCH} extra documents"

    # =========================================================================
    # Phase 3: Generate reservations
    # Per accommodation: 2-4 past (approved) + 1-2 future/pending
    # =========================================================================
    info "Phase 3/5: Generating reservations..."

    RES_SQL=""
    all_guests=("${GEN_GUEST_IDS[@]}" "$GUEST_USER_ID" "$GUEST2_USER_ID")
    num_all_guests=${#all_guests[@]}

    for (( a = 0; a < ${#GEN_ACCOM_IDS[@]}; a++ )); do
        accom_id="${GEN_ACCOM_IDS[$a]}"
        host_id="${GEN_ACCOM_HOSTS[$a]}"

        # 2-4 past approved/cancelled reservations
        past_count=$(rand_range 2 4)
        for (( r = 0; r < past_count; r++ )); do
            res_id=$(uuid_from "res-past" "${a}-${r}")
            guest_id="${all_guests[$(( RANDOM % num_all_guests ))]}"
            from=$(rand_date_between "2025-09-01" "2026-01-15")
            to=$(add_days "$from" "$(rand_range 3 14)")
            guests=$(rand_range 1 4)
            # 75% approved, 25% cancelled
            statuses=(1 1 1 3)
            status=${statuses[$(( RANDOM % 4 ))]}

            RES_SQL+="
INSERT INTO \"Reservations\" (\"Id\", \"UserId\", \"AccommodationId\", \"HostId\", \"FromDate\", \"ToDate\", \"NumOfGuests\", \"Status\", \"CreatedBy\", \"ModifiedBy\", \"CreatedTimestamp\", \"ModifiedTimestamp\")
VALUES ('${res_id}', '${guest_id}', '${accom_id}', '${host_id}', '${from}', '${to}', ${guests}, ${status}, '${guest_id}', 'seed', '${NOW}', '${NOW}')
ON CONFLICT (\"Id\") DO UPDATE SET \"Status\" = EXCLUDED.\"Status\", \"ModifiedTimestamp\" = '${NOW}';
"
            TOTAL_RESERVATIONS=$(( TOTAL_RESERVATIONS + 1 ))
        done

        # 1-2 future reservations (pending/approved)
        future_count=$(rand_range 1 2)
        for (( r = 0; r < future_count; r++ )); do
            res_id=$(uuid_from "res-future" "${a}-${r}")
            guest_id="${all_guests[$(( RANDOM % num_all_guests ))]}"
            from=$(rand_date_between "2026-04-01" "2026-08-01")
            to=$(add_days "$from" "$(rand_range 3 10)")
            guests=$(rand_range 1 4)
            statuses=(0 1)  # 50% pending, 50% approved
            status=${statuses[$(( RANDOM % 2 ))]}

            RES_SQL+="
INSERT INTO \"Reservations\" (\"Id\", \"UserId\", \"AccommodationId\", \"HostId\", \"FromDate\", \"ToDate\", \"NumOfGuests\", \"Status\", \"CreatedBy\", \"ModifiedBy\", \"CreatedTimestamp\", \"ModifiedTimestamp\")
VALUES ('${res_id}', '${guest_id}', '${accom_id}', '${host_id}', '${from}', '${to}', ${guests}, ${status}, '${guest_id}', 'seed', '${NOW}', '${NOW}')
ON CONFLICT (\"Id\") DO UPDATE SET \"Status\" = EXCLUDED.\"Status\", \"ModifiedTimestamp\" = '${NOW}';
"
            TOTAL_RESERVATIONS=$(( TOTAL_RESERVATIONS + 1 ))
        done
    done

    echo "$RES_SQL" | psql_cmd hotelier_reservation
    ok "Reservations: ${TOTAL_RESERVATIONS} extra"

    # =========================================================================
    # Phase 4: Generate ratings (1-3 per accommodation + 1 host rating)
    # =========================================================================
    info "Phase 4/5: Generating ratings..."

    RATING_SQL=""
    RATING_UPDATES_JS=""

    for (( a = 0; a < ${#GEN_ACCOM_IDS[@]}; a++ )); do
        accom_id="${GEN_ACCOM_IDS[$a]}"
        host_id="${GEN_ACCOM_HOSTS[$a]}"
        rating_count=$(rand_range 1 3)
        score_sum=0

        used_guests=()
        for (( r = 0; r < rating_count; r++ )); do
            attempts=0
            while true; do
                guest_id="${all_guests[$(( RANDOM % num_all_guests ))]}"
                is_dup=0
                for ug in "${used_guests[@]+"${used_guests[@]}"}"; do
                    [[ "$ug" == "$guest_id" ]] && is_dup=1 && break
                done
                (( is_dup == 0 )) && break
                (( ++attempts > 10 )) && break
            done
            used_guests+=("$guest_id")

            rating_id=$(uuid_from "rating" "${a}-${r}")
            score=$(rand_range 3 5)
            score_sum=$(( score_sum + score ))
            comment=$(rand_elem "${REVIEW_COMMENTS[@]}")

            RATING_SQL+="
INSERT INTO \"Ratings\" (\"Id\", \"GuestId\", \"TargetId\", \"TargetType\", \"Score\", \"Comment\", \"CreatedBy\", \"ModifiedBy\", \"CreatedTimestamp\", \"ModifiedTimestamp\")
VALUES ('${rating_id}', '${guest_id}', '${accom_id}', 0, ${score}, '${comment}', '${guest_id}', '${guest_id}', '${NOW}', '${NOW}')
ON CONFLICT (\"Id\") DO UPDATE SET \"Score\" = EXCLUDED.\"Score\", \"Comment\" = EXCLUDED.\"Comment\", \"ModifiedTimestamp\" = '${NOW}';
"
            TOTAL_RATINGS=$(( TOTAL_RATINGS + 1 ))
        done

        # Host rating
        host_rating_id=$(uuid_from "host-rating" "$a")
        host_score=$(rand_range 3 5)
        host_comment=$(rand_elem "${REVIEW_COMMENTS[@]}")
        h_guest="${all_guests[$(( RANDOM % num_all_guests ))]}"

        RATING_SQL+="
INSERT INTO \"Ratings\" (\"Id\", \"GuestId\", \"TargetId\", \"TargetType\", \"Score\", \"Comment\", \"CreatedBy\", \"ModifiedBy\", \"CreatedTimestamp\", \"ModifiedTimestamp\")
VALUES ('${host_rating_id}', '${h_guest}', '${host_id}', 1, ${host_score}, '${host_comment}', '${h_guest}', '${h_guest}', '${NOW}', '${NOW}')
ON CONFLICT (\"Id\") DO UPDATE SET \"Score\" = EXCLUDED.\"Score\", \"Comment\" = EXCLUDED.\"Comment\", \"ModifiedTimestamp\" = '${NOW}';
"
        TOTAL_RATINGS=$(( TOTAL_RATINGS + 1 ))

        avg_rating=$(echo "scale=1; ${score_sum} / ${rating_count}" | bc)
        RATING_UPDATES_JS+="
db.accommodations.updateOne({ _id: '${accom_id}' }, { \$set: { AverageRating: ${avg_rating}, TotalRatings: ${rating_count} } });"$'\n'
    done

    echo "$RATING_SQL" | psql_cmd hotelier_rating
    ok "Ratings: ${TOTAL_RATINGS} extra"

    if [[ -n "$RATING_UPDATES_JS" ]]; then
        mongo_cmd hotelier_search --eval "${RATING_UPDATES_JS} print('Search ratings updated');"
    fi

    # =========================================================================
    # Phase 5: Generate notifications
    # =========================================================================
    info "Phase 5/5: Generating notifications..."

    NOTIF_JS="var notifs = [];"$'\n'
    PREF_JS=""

    for (( i = 0; i < ${#GEN_HOST_IDS[@]}; i++ )); do
        hid="${GEN_HOST_IDS[$i]}"
        PREF_JS+="
db.notification_preferences.updateOne({ _id: '${hid}' },
    { \$set: { Preferences: { reservation_created: true, reservation_cancelled: true, rating_received: true } }},
    { upsert: true });"$'\n'

        NOTIF_JS+="
notifs.push({ From: '${all_guests[$(( RANDOM % num_all_guests ))]}', To: '${hid}',
    Topic: 'New Reservation', Message: 'You have a new reservation request.', IsRead: false, CreatedAt: new Date() });"$'\n'
        TOTAL_NOTIFS=$(( TOTAL_NOTIFS + 1 ))
    done

    for (( i = 0; i < ${#GEN_GUEST_IDS[@]}; i++ )); do
        gid="${GEN_GUEST_IDS[$i]}"
        PREF_JS+="
db.notification_preferences.updateOne({ _id: '${gid}' },
    { \$set: { Preferences: { reservation_approved: true, reservation_rejected: true } }},
    { upsert: true });"$'\n'

        if (( RANDOM % 2 == 0 )); then
            hid="${GEN_HOST_IDS[$(( RANDOM % ${#GEN_HOST_IDS[@]} ))]}"
            topics=("Reservation Approved" "Reservation Rejected")
            topic=$(rand_elem "${topics[@]}")
            NOTIF_JS+="
notifs.push({ From: '${hid}', To: '${gid}',
    Topic: '${topic}', Message: 'Your reservation has been processed.', IsRead: false, CreatedAt: new Date() });"$'\n'
            TOTAL_NOTIFS=$(( TOTAL_NOTIFS + 1 ))
        fi
    done

    NOTIF_JS+="if (notifs.length > 0) { db.notifications.insertMany(notifs); }; print('Notifications: ' + notifs.length + ' extra');"

    mongo_cmd hotelier_notification --eval "${PREF_JS} ${NOTIF_JS}"
    ok "Notifications: ${TOTAL_NOTIFS} extra"

    echo ""
    echo "  -- Extra data ----------------------------------------"
    echo "  Users: ${TOTAL_USERS} | Accommodations: ${TOTAL_ACCOMS}"
    echo "  Availability: ${TOTAL_AVAILS} | Reservations: ${TOTAL_RESERVATIONS}"
    echo "  Ratings: ${TOTAL_RATINGS} | Notifications: ${TOTAL_NOTIFS}"
    echo "  (usernames: host_1..host_${EXTRA_COUNT}, guest_1a..guest_${EXTRA_COUNT}b)"
fi

# =============================================================================
# Final summary
# =============================================================================
echo ""
echo "============================================================"
echo -e "  ${GREEN}Seed data loaded successfully!${NC}"
echo "============================================================"
echo ""
echo "  Test accounts (password for all: Test1234!):"
echo "  ┌----------┬--------------------------------------┬-------┐"
echo "  │ Username │ ID                                   │ Role  │"
echo "  ├----------┼--------------------------------------┼-------┤"
echo "  │ host1    │ ${HOST_USER_ID} │ Host  │"
echo "  │ guest1   │ ${GUEST_USER_ID} │ Guest │"
echo "  │ guest2   │ ${GUEST2_USER_ID} │ Guest │"
echo "  └----------┴--------------------------------------┴-------┘"
if (( EXTRA_COUNT > 0 )); then
echo "  + host_1..host_${EXTRA_COUNT} (Host) | guest_1a..guest_${EXTRA_COUNT}b (Guest)"
fi
echo ""
echo "  Key scenarios (core accounts):"
echo "  • guest1: 2 past stays → can review Seaside Villa, Mountain Cabin, host1"
echo "  • guest1: 1 pending reservation → host1 can approve/reject"
echo "  • guest2: 1 future approved → can cancel"
echo "  • guest1: 1 cancelled reservation → visible in history"
echo "  • guest2: has left a 5-star review for Seaside Villa"
echo ""
