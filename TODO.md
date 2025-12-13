# TODO

### Defines

- NK - unregistered user
  - [ ] Register as host/guest

- H - host
  - [ ] Create accommodation
  - [ ] Manage accommodation
    - [ ] Manage accommodation availability
    - [ ] Define price (per guest, per day, seasonal, weekend)
    - [ ] Price can be changed only if no pending reservations are present for that period
  - [ ] Approve reservation
    - [ ] Approving reservation automatically cancels all overlapping pending reservations
    - [ ] Automatic
    - [ ] Manual
      - [ ] Show guest history cancels

- G - guest
  - [ ] Make a reservation
    - [ ] Define Start and end Date, num of guest
    - [ ] Delete reservation unless already approved
    - [ ] Only in available time frame
  - [ ] Cancel reservation (before due date)
  - [ ] Rate host / accommodation
    - [ ] See all ratings given
    - [ ] See average ratings given
    - [ ] Must have completed reservation associated with host
    - [ ] Rate 1-5
    - [ ] Edit rating
    - [ ] Delete rating

- Shared (G, H)
  - [ ] Login
  - [ ] Search accommodation
    - [ ] Filters (Location, Num of guests, Start date, End Date)
  - [ ] Manage personal info
  - [ ] Manage credentials
  - [ ] Delete account
    - [ ] If host has no pending reservations (remove all associated accommodations)
    - [ ] If guest has no active reservations
  - [ ] Notifcations
    - [ ] Manage notification for user
      - [ ] Turn off each notification by type
    - [ ] Reservation creation
    - [ ] Cancel reservation
    - [ ] Rating received for host
    - [ ] Rating received for accommodation
    - [ ] Host responded to reservation (Confirm or Cancel)

## Models

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