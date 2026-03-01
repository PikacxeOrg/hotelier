# TODO - Hotelier Platform (DevOps Project)

## Functional Requirements

### 1.1 Registration (NK - Unregistered User)
- [X] Create host or guest account
- [X] Unique username validation
- [X] Required fields: name, lastaname, email, address

### 1.2 Login (NK)
- [X] Authentication system
- [X] Support for host and guest roles

### 1.3 Account Management (H, G)
- [X] Update personal information
- [X] Update credentials (username, password)

### 1.4 Account Deletion (H, G)
- [X] Guest: Delete account if no active reservations
- [X] Host: Delete account if no future reservations on any accommodation
- [X] Auto-delete all host accommodations when host account is deleted

### 1.5 Accommodation Creation (H)
- [X] Name, location, amenities (wifi, kitchen, AC, parking, etc.)
- [X] Upload photos
- [X] Define min/max number of guests

### 1.6 Availability & Pricing (H)
- [X] Define availability periods
- [X] Define pricing (per guest or per unit)
- [X] Support variable pricing (seasonal, weekend, holiday)
- [X] Prevent changes if reservations exist in the period

### 1.7 Search Accommodations (NK, H, G)
- [X] Search by location, number of guests, check-in/out dates
- [X] Display total price for stay
- [X] Display unit price (per person/night or per unit/night)
- [X] Show only available accommodations for specified dates

### 1.8 Reservation Requests (G)
- [X] Create reservation request (accommodation, dates, num guests)
- [X] Guest can delete request before approval
- [X] Support multiple pending requests with overlapping dates

### 1.9 Cancel Reservation (G)
- [X] Guest can cancel approved reservation
- [X] Cancellation allowed until 1 day before start date
- [X] Accommodation becomes available again after cancellation

### 1.10 Reservation Approval (H)
- [X] Automatic approval mode
- [X] Manual approval mode
  - [X] Show guest cancellation history
  - [X] Approve or reject request
- [X] Auto-reject overlapping requests when one is approved

### 1.11 Rate Hosts (G)
- [X] Guest can rate host (1-5 stars)
- [X] Only if guest had completed reservation at host's accommodation
- [X] Edit or delete rating
- [X] View individual ratings with author and date
- [X] View average rating

### 1.12 Rate Accommodations (G)
- [X] Guest can rate accommodation (1-5 stars)
- [X] Only if guest stayed there in the past
- [X] Edit or delete rating
- [X] View individual ratings with author and date
- [X] View average rating

### 1.13 Notifications (H, G)
- [X] Host notifications:
  - [X] New reservation request created
  - [X] Reservation cancelled
  - [X] Host rating received
  - [X] Accommodation rating received
- [X] Guest notifications:
  - [X] Host responded to reservation request
- [X] User settings to enable/disable each notification type

## Non-Functional Requirements

### 1.14 Tracing
- [ ] Implement distributed tracing across all microservices
- [ ] Integrate visualization tool (e.g., Jaeger, Zipkin)
- [ ] Trace request flow across services

### 1.15 Logging
- [X] Implement log aggregation across all microservices (promtail)
- [X] Use centralized logging solution (e.g., ELK/Loki)
- [X] Visualize logs using appropriate tool (grafana)

### 1.16 Metrics
- [ ] **OS Metrics** - Host machine metrics:
  - [ ] CPU usage
  - [ ] RAM usage
  - [ ] File system usage
  - [ ] Network traffic throughput
- [ ] **Container Metrics**:
  - [ ] CPU usage per container
  - [ ] RAM usage per container
  - [ ] File system usage per container
  - [ ] Network traffic per container
- [X] **Web Traffic Metrics** (last 24h):
  - [X] Total HTTP requests
  - [X] Successful requests (2xx, 3xx)
  - [X] Failed requests (4xx, 5xx)
  - [ ] Unique visitors (by IP, timestamp, browser)
  - [X] 404 errors with endpoints
  - [X] Total traffic in GB
- [X] Visualize metrics using dashboard tool (e.g., Grafana)

## DevOps Requirements

### 1.17 Git Repository Configuration
- [X] **Feature Branch Workflow**
  - [X] Setup branch protection rules
  - [X] Require PR approval from at least 1 team member
- [X] **PR Pipeline**
  - [X] Trigger on PR creation and updates
  - [X] Build application
  - [X] Run unit tests
  - [X] Run integration tests
  - [X] Block merge if pipeline fails
- [X] **Branch Configuration**
  - [X] Enable linear history on master branch
  - [X] Enable linear history on develop branch
- [X] **Commit Standards**
  - [X] Enforce Conventional Commits format
  - [X] Setup commit linting
- [X] **Repository Structure**
  - [X] Separate repository for each microservice

### 1.18 CI/CD Pipeline Configuration
- [X] **CI Pipeline** (trigger on develop & master)
  - [X] Build application
  - [X] Run unit tests
  - [X] Run integration tests
  - [X] Use Testcontainers or docker-compose for test infrastructure
- [X] **Code Analysis**
  - [X] Integrate SonarCloud (or similar)
  - [X] Implement on at least one microservice
- [X] **Container Management**
  - [X] Build container images
  - [X] Use Semantic Versioning for image tags
  - [X] Publish to DockerHub (or container registry)
- [X] **Pipeline Optimization**
  - [X] Cache dependencies
  - [X] Use build image with pre-installed tools/dependencies

## Grading & Project Phases

### Phase 1: First Set (15 points - Grade 6)
**Requirements:** 1.1-1.10, 1.17, 1.18
- [X] Implement all functional requirements 1.1-1.10
- [X] Implement Git configuration (1.17)
- [X] Implement CI/CD pipelines (1.18)
- [X] Use NoSQL database on at least one service
- [X] Run all services in Docker containers
- [X] Create docker-compose.dev.yml for local deployment

### Phase 2A: Docker Swarm Path (25 points - Max Grade 9)
**Requirements:** 1.11-1.16 + Docker Swarm
- [X] Implement ratings (1.11, 1.12)
- [X] Implement notifications (1.13)
- [ ] Implement tracing (1.14)
- [X] Implement logging (1.15)
- [X] Implement metrics (1.16)
- [X] Deploy infrastructure using Docker Swarm
- [X] Configure Docker Secrets
- [X] Configure Docker Configs

### Phase 2B: Kubernetes Path (35 points - Max Grade 10)
**Requirements:** 1.11-1.16 + Kubernetes
- [X] Implement ratings (1.11, 1.12)
- [X] Implement notifications (1.13)
- [ ] Implement tracing (1.14)
- [X] Implement logging (1.15)
- [X] Implement metrics (1.16)
- [X] Deploy to Kubernetes cluster (e.g., minikube)
- [X] Use Kaniko for building container images
- [X] Use Helm for infrastructure deployment
- [X] Create Helm charts for all services

## Data Models

- TrackableEntity (Root)
  - Id
  - CreatedBy
  - ModifiedBy
  - CreatedTimestamp
  - ModifiedTimestamp

- User
  - Username (unique)
  - Password
  - Name
  - LastName
  - Email
  - Address
  - UserType
  
- Accommodation
  - Name
  - Address
  - Attributes (Wifi, Kitchen, AC, Parking etc)
  - Pictures
  - Max num of guests
  - Min num of guests
  
- Availabilty
  - AccommodationId
  - FromDate
  - ToDate
  - Price
  - PriceType
  - PriceModifiers (Seasonal, Weekend...)
  - IsAvailable

- Reservation
  - UserId
  - AccommodationId
  - HostId
  - FromDate
  - ToDate
  - NumOfGuests
  - Status (Pending, Approved, Denied, Cancelled)

- Rating
  - ReservationId
  - GuestRating
  - HostRating
  - AccommodationRating
  
- Notification
  - From
  - To
  - Topic
  - Message

## Technical Stack & Tools

### Required Technologies
- [X] Microservices architecture (backend)
- [X] Frontend application
- [X] At least one NoSQL database
- [X] Message broker (for notifications)
- [X] Docker & Docker Compose
- [X] Git with Feature Branch Workflow
- [X] CI/CD platform (GitHub Actions, GitLab CI, etc.)

### Monitoring & Observability
- [ ] Tracing: Jaeger or Zipkin
- [X] Logging: ELK Stack or Loki+Promtail
- [X] Metrics & Visualization: Prometheus + Grafana
- [X] Container monitoring

### Deployment Options
- **Option A (Grade 9):** Docker Swarm + Docker Secrets/Configs
- **Option B (Grade 10):** Kubernetes + Kaniko + Helm

## Reference Links

- [Feature Branch Workflow](https://www.atlassian.com/git/tutorials/comparing-workflows/feature-branch-workflow)
- [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
- [Testcontainers](https://golang.testcontainers.org/)
- [Semantic Versioning](https://semver.org/)
- [Docker Secrets](https://docs.docker.com/engine/swarm/secrets/)
- [Docker Configs](https://docs.docker.com/engine/swarm/configs/)
- [Minikube](https://minikube.sigs.k8s.io/docs/)
- [Kaniko](https://github.com/GoogleContainerTools/kaniko)
- [Helm](https://helm.sh/)
- [System Design Example](https://medium.com/nerd-for-tech/system-design-architecture-for-hotel-booking-apps-like-airbnb-oyo-6efb4f4dddd7)

## Important Notes

- **Repository Structure:** Each microservice must have its own repository
- **Linear History:** Required for master and develop branches
- **PR Approval:** At least 1 team member must approve before merge
- **Pipeline Blocking:** PRs cannot be merged if pipeline fails