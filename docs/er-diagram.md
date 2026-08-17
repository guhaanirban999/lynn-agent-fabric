# Casino Itinerary — ER Diagram (`casino_demo`, v3)

Entity-relationship diagram for the live Aiven **`casino_demo`** database — the full-parity
MySQL port of the BigQuery `casino_demo` reference (`06_casino_demo_schema.sql` +
`07_casino_demo_seed.sql`). 16 tables, enforced FKs. Grouped by MCP owner.

```mermaid
erDiagram
    comp_tier ||--o{ guest        : "tier"
    comp_tier ||--o{ reservation  : "tier"
    comp_tier ||--o{ promotion    : "required"
    guest ||--o{ reservation      : "primary"
    guest ||--o{ reservation_guest: "is"
    guest ||--o{ guest_consent    : "grants"
    guest ||--o{ guest_interest   : "has"
    reservation ||--o{ reservation_guest        : "party"
    reservation ||--o{ room_stay                : "rooms"
    reservation ||--o{ pre_booked_event         : "events"
    reservation ||--o{ stay_schedule_constraint : "windows"
    reservation ||--o{ reservation_access_audit : "audited"
    reservation ||--o{ guest_interest           : "trip-scoped"
    reservation ||--o{ reservation_offer_recommendation : "recs"
    room_type ||--o{ room_stay : "inventory"
    interest_category ||--o{ interest_category : "parent"
    interest_category ||--o{ guest_interest    : "categorizes"
    interest_category ||--o{ venue             : "categorizes"
    interest_category ||--o{ offering          : "categorizes"
    interest_category ||--o{ reservation_offer_recommendation : "matched"
    offer_provider ||--o{ venue     : "operates"
    offer_provider ||--o{ offering  : "supplies"
    offer_provider ||--o{ promotion : "sponsors"
    venue    ||--o{ offering  : "hosts"
    venue    ||--o{ pre_booked_event : "booked at"
    offering ||--o{ promotion : "promoted by"
    offering ||--o{ pre_booked_event : "booked as"
    offering ||--o{ reservation_offer_recommendation : "recommended"

    comp_tier {
        int comp_tier_id PK
        varchar tier_code
        varchar tier_name
        int rank_order
        decimal daily_comp_limit
    }
    guest {
        varchar guest_id PK
        varchar player_id
        varchar first_name
        varchar last_name
        varchar email
        varchar phone
        date date_of_birth
        int comp_tier_id FK
        varchar home_city
        varchar home_region
        varchar country_code
    }
    reservation {
        varchar reservation_id PK
        varchar confirmation_code UK
        varchar primary_guest_id FK
        varchar property_code
        varchar status
        date check_in_date
        date check_out_date
        time arrival_time
        time departure_time
        int party_size
        int comp_tier_id FK
        bool has_minors
        varchar booking_channel
        varchar special_requests
    }
    reservation_guest {
        varchar reservation_guest_id PK
        varchar reservation_id FK
        varchar guest_id FK
        varchar display_name
        int age
        varchar age_band
        bool is_primary
        varchar relationship
    }
    room_stay {
        varchar room_stay_id PK
        varchar reservation_id FK
        varchar room_type_code FK
        varchar room_number
        varchar rate_plan_code
        decimal nightly_rate
        bool is_comped
        int occupancy_adults
        int occupancy_minors
    }
    room_type {
        varchar room_type_code PK
        varchar room_type_name
        varchar property_code
        varchar description
        decimal base_nightly_rate
        int max_occupancy
        int total_inventory
    }
    pre_booked_event {
        varchar event_id PK
        varchar reservation_id FK
        varchar venue_id FK
        varchar offering_id FK
        varchar title
        varchar segment
        varchar venue_name
        datetime starts_at
        datetime ends_at
        int party_count
        bool is_locked
        varchar source_system
    }
    stay_schedule_constraint {
        varchar constraint_id PK
        varchar reservation_id FK
        date constraint_date
        time earliest_start
        time latest_end
        varchar quiet_window
        varchar note
    }
    guest_consent {
        varchar consent_id PK
        varchar guest_id FK
        varchar scope
        bool granted
        datetime granted_at
        datetime expires_at
        varchar source
    }
    reservation_access_audit {
        bigint audit_id PK
        varchar reservation_id FK
        varchar accessed_by
        varchar mcp_tool
        varchar action
        json fields_returned
        json request_context
        datetime occurred_at
    }
    interest_category {
        int category_id PK
        varchar category_code
        varchar category_name
        int parent_category_id FK
        bool is_age_restricted
        varchar description
    }
    guest_interest {
        varchar guest_interest_id PK
        varchar guest_id FK
        varchar reservation_id FK
        int category_id FK
        int affinity_score "0..100"
        bool is_explicit
        varchar source
        datetime captured_at
    }
    offer_provider {
        varchar provider_id PK
        varchar provider_code
        varchar provider_name
        varchar provider_type "owned|partner"
        varchar property_code
        varchar partner_category
        bool is_active
    }
    venue {
        varchar venue_id PK
        varchar provider_id FK
        varchar venue_name
        int category_id FK
        varchar property_code
        time opens_time
        time closes_time
        int capacity
        int min_age
        bool is_active
    }
    offering {
        varchar offering_id PK
        varchar venue_id FK
        varchar provider_id FK
        varchar title
        int category_id FK
        varchar segment
        time typical_start
        int duration_min
        decimal base_price
        varchar currency
        bool is_age_restricted
        int min_age
        bool is_bookable
        varchar availability_status
    }
    promotion {
        varchar promo_id PK
        varchar offering_id FK
        varchar provider_id FK
        varchar promo_code
        varchar title
        int comp_tier_required FK
        varchar discount_type
        decimal discount_value
        varchar redemption_rules
        date valid_from
        date valid_to
        bool is_active
    }
    reservation_offer_recommendation {
        varchar rec_id PK
        varchar reservation_id FK
        varchar offering_id FK
        int matched_category_id FK
        double match_score
        bool is_age_eligible
        bool is_tier_eligible
        varchar suppressed_reason
    }
```

## Notes
- **MCP ownership:**
  - **MCP-A Reservation Context + Lodging** → `comp_tier`, `guest`, `reservation`,
    `reservation_guest`, `room_type`, `room_stay`, `pre_booked_event`,
    `stay_schedule_constraint`, `guest_consent`, `reservation_access_audit`.
  - **MCP-B Entertainment Interests** → `interest_category`, `guest_interest`.
  - **MCP-C Casino & Partner Offers** → `offer_provider`, `venue`, `offering`, `promotion`,
    `reservation_offer_recommendation`.
- **Booking path:** there is no generic "offering_reservations" table — `reserveOffering`
  writes a **`pre_booked_event`** row on the reservation, so newly booked items feed
  `getScheduleConstraints` conflict detection automatically.
- **Age gating** is taxonomy-driven (`interest_category.is_age_restricted`) plus per-row
  `offering.min_age` / `venue.min_age`; suppression outcomes persist in
  `reservation_offer_recommendation.suppressed_reason`.
- **PII** is governed by `guest_consent` (scope `pii:contact`), not a request header.
- IDs are STRING (`GST-000x`, `RES-000x`, `OFR-000x`, `PRV-*`, `VEN-000x`); `comp_tier_id`
  and `category_id` are INT. `PK`/`FK`/`UK` = primary/foreign/unique key.
