# TODO - Hotelier Platform (DevOps Project)

## Functional Requirements

### 1.1 Registration (NK - Unregistered User)
- [ ] Create host or guest account
- [ ] Unique username validation
- [ ] Required fields: name, surname, email, address

### 1.2 Login (NK)
- [ ] Authentication system
- [ ] Support for host and guest roles

### 1.3 Account Management (H, G)
- [ ] Update personal information
- [ ] Update credentials (username, password)

### 1.4 Account Deletion (H, G)
- [ ] Guest: Delete account if no active reservations
- [ ] Host: Delete account if no future reservations on any accommodation
- [ ] Auto-delete all host accommodations when host account is deleted

### 1.5 Accommodation Creation (H)
- [ ] Name, location, amenities (wifi, kitchen, AC, parking, etc.)
- [ ] Upload photos
- [ ] Define min/max number of guests

### 1.6 Availability & Pricing (H)
- [ ] Define availability periods
- [ ] Define pricing (per guest or per unit)
- [ ] Support variable pricing (seasonal, weekend, holiday)
- [ ] Prevent changes if reservations exist in the period

### 1.7 Search Accommodations (NK, H, G)
- [ ] Search by location, number of guests, check-in/out dates
- [ ] Display total price for stay
- [ ] Display unit price (per person/night or per unit/night)
- [ ] Show only available accommodations for specified dates

### 1.8 Reservation Requests (G)
- [ ] Create reservation request (accommodation, dates, num guests)
- [ ] Guest can delete request before approval
- [ ] Support multiple pending requests with overlapping dates

### 1.9 Cancel Reservation (G)
- [ ] Guest can cancel approved reservation
- [ ] Cancellation allowed until 1 day before start date
- [ ] Accommodation becomes available again after cancellation

### 1.10 Reservation Approval (H)
- [ ] Automatic approval mode
- [ ] Manual approval mode
  - [ ] Show guest cancellation history
  - [ ] Approve or reject request
- [ ] Auto-reject overlapping requests when one is approved

### 1.11 Rate Hosts (G)
- [ ] Guest can rate host (1-5 stars)
- [ ] Only if guest had completed reservation at host's accommodation
- [ ] Edit or delete rating
- [ ] View individual ratings with author and date
- [ ] View average rating

### 1.12 Rate Accommodations (G)
- [ ] Guest can rate accommodation (1-5 stars)
- [ ] Only if guest stayed there in the past
- [ ] Edit or delete rating
- [ ] View individual ratings with author and date
- [ ] View average rating

### 1.13 Notifications (H, G)
- [ ] Host notifications:
  - [ ] New reservation request created
  - [ ] Reservation cancelled
  - [ ] Host rating received
  - [ ] Accommodation rating received
- [ ] Guest notifications:
  - [ ] Host responded to reservation request
- [ ] User settings to enable/disable each notification type

## Non-Functional Requirements

### 1.14 Tracing
- [ ] Implement distributed tracing across all microservices
- [ ] Integrate visualization tool (e.g., Jaeger, Zipkin)
- [ ] Trace request flow across services

### 1.15 Logging
- [ ] Implement log aggregation across all microservices
- [ ] Use centralized logging solution (e.g., ELK/Loki)
- [ ] Visualize logs using appropriate tool

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
- [ ] **Web Traffic Metrics** (last 24h):
  - [ ] Total HTTP requests
  - [ ] Successful requests (2xx, 3xx)
  - [ ] Failed requests (4xx, 5xx)
  - [ ] Unique visitors (by IP, timestamp, browser)
  - [ ] 404 errors with endpoints
  - [ ] Total traffic in GB
- [ ] Visualize metrics using dashboard tool (e.g., Grafana)

## DevOps Requirements

### 1.17 Git Repository Configuration
- [ ] **Feature Branch Workflow**
  - [ ] Setup branch protection rules
  - [ ] Require PR approval from at least 1 team member
- [ ] **PR Pipeline**
  - [ ] Trigger on PR creation and updates
  - [ ] Build application
  - [ ] Run unit tests
  - [ ] Run integration tests
  - [ ] Block merge if pipeline fails
- [ ] **Branch Configuration**
  - [ ] Enable linear history on master branch
  - [ ] Enable linear history on develop branch
- [ ] **Commit Standards**
  - [ ] Enforce Conventional Commits format
  - [ ] Setup commit linting
- [ ] **Repository Structure**
  - [ ] Separate repository for each microservice

### 1.18 CI/CD Pipeline Configuration
- [ ] **CI Pipeline** (trigger on develop & master)
  - [ ] Build application
  - [ ] Run unit tests
  - [ ] Run integration tests
  - [ ] Use Testcontainers or docker-compose for test infrastructure
- [ ] **Code Analysis**
  - [ ] Integrate SonarCloud (or similar)
  - [ ] Implement on at least one microservice
- [ ] **Container Management**
  - [ ] Build container images
  - [ ] Use Semantic Versioning for image tags
  - [ ] Publish to DockerHub (or container registry)
- [ ] **Pipeline Optimization**
  - [ ] Cache dependencies
  - [ ] Use build image with pre-installed tools/dependencies

## Grading & Project Phases

### Phase 1: First Set (15 points - Grade 6)
**Requirements:** 1.1-1.10, 1.17, 1.18
- [ ] Implement all functional requirements 1.1-1.10
- [ ] Implement Git configuration (1.17)
- [ ] Implement CI/CD pipelines (1.18)
- [ ] Use NoSQL database on at least one service
- [ ] Run all services in Docker containers
- [ ] Create docker-compose.yml for local deployment

### Phase 2A: Docker Swarm Path (25 points - Max Grade 9)
**Requirements:** 1.11-1.16 + Docker Swarm
- [ ] Implement ratings (1.11, 1.12)
- [ ] Implement notifications (1.13)
- [ ] Implement tracing (1.14)
- [ ] Implement logging (1.15)
- [ ] Implement metrics (1.16)
- [ ] Deploy infrastructure using Docker Swarm
- [ ] Configure Docker Secrets
- [ ] Configure Docker Configs

### Phase 2B: Kubernetes Path (35 points - Max Grade 10)
**Requirements:** 1.11-1.16 + Kubernetes
- [ ] Implement ratings (1.11, 1.12)
- [ ] Implement notifications (1.13)
- [ ] Implement tracing (1.14)
- [ ] Implement logging (1.15)
- [ ] Implement metrics (1.16)
- [ ] Deploy to Kubernetes cluster (e.g., minikube)
- [ ] Use Kaniko for building container images
- [ ] Use Helm for infrastructure deployment
- [ ] Create Helm charts for all services

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
  - Surname
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
- [ ] Microservices architecture (backend)
- [ ] Frontend application
- [ ] At least one NoSQL database
- [ ] Message broker (for notifications)
- [ ] Docker & Docker Compose
- [ ] Git with Feature Branch Workflow
- [ ] CI/CD platform (GitHub Actions, GitLab CI, etc.)

### Monitoring & Observability
- [ ] Tracing: Jaeger or Zipkin
- [ ] Logging: ELK Stack or Loki+Promtail
- [ ] Metrics & Visualization: Prometheus + Grafana
- [ ] Container monitoring

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