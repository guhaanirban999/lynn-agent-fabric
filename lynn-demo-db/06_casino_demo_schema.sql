-- ============================================================
-- Casino Itinerary Agent Fabric Demo — casino_demo schema (v3)
-- 06_casino_demo_schema.sql
-- Faithful MySQL port of the BigQuery `casino_demo` reference model (full parity).
-- Differences from the reference (all intentional, MySQL-appropriate):
--   * BigQuery types mapped: STRING->VARCHAR, INT64->INT, NUMERIC->DECIMAL(12,2),
--     FLOAT64->DOUBLE, TIMESTAMP->DATETIME, BOOL->BOOLEAN, JSON->JSON.
--   * Foreign keys are ENFORCED (InnoDB) rather than NOT ENFORCED.
--   * reservation_access_audit gets a surrogate PK (audit_id) + occurred_at;
--     guest_interest gets captured_at default — the reference had no PK/default.
-- New database so the existing lynn_demo stays intact as a fallback.
-- ============================================================
CREATE DATABASE IF NOT EXISTS casino_demo
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE casino_demo;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS reservation_offer_recommendation, promotion, guest_interest, offering,
  venue, reservation_access_audit, guest_consent, stay_schedule_constraint, pre_booked_event,
  room_stay, reservation_guest, reservation, guest, offer_provider, interest_category, comp_tier;
SET FOREIGN_KEY_CHECKS = 1;

CREATE TABLE comp_tier (
  comp_tier_id     INT PRIMARY KEY,
  tier_code        VARCHAR(20) NOT NULL,
  tier_name        VARCHAR(60) NOT NULL,
  rank_order       INT NOT NULL,
  daily_comp_limit DECIMAL(12,2)
) ENGINE=InnoDB;

CREATE TABLE interest_category (
  category_id        INT PRIMARY KEY,
  category_code      VARCHAR(40) NOT NULL,
  category_name      VARCHAR(80) NOT NULL,
  parent_category_id INT NULL,
  is_age_restricted  BOOLEAN NOT NULL DEFAULT FALSE,
  description        VARCHAR(255),
  CONSTRAINT fk_ic_parent FOREIGN KEY (parent_category_id) REFERENCES interest_category(category_id)
) ENGINE=InnoDB;

CREATE TABLE offer_provider (
  provider_id      VARCHAR(36) PRIMARY KEY,
  provider_code    VARCHAR(40),
  provider_name    VARCHAR(120) NOT NULL,
  provider_type    VARCHAR(40),          -- owned | partner
  property_code    VARCHAR(20),
  partner_category VARCHAR(40),
  is_active        BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE=InnoDB;

CREATE TABLE guest (
  guest_id      VARCHAR(36) PRIMARY KEY,
  player_id     VARCHAR(20),
  first_name    VARCHAR(60) NOT NULL,
  last_name     VARCHAR(60) NOT NULL,
  email         VARCHAR(120),
  phone         VARCHAR(30),
  date_of_birth DATE,
  comp_tier_id  INT,
  home_city     VARCHAR(80),
  home_region   VARCHAR(80),
  country_code  VARCHAR(3),
  CONSTRAINT fk_guest_tier FOREIGN KEY (comp_tier_id) REFERENCES comp_tier(comp_tier_id)
) ENGINE=InnoDB;

CREATE TABLE reservation (
  reservation_id   VARCHAR(36) PRIMARY KEY,
  confirmation_code VARCHAR(20) UNIQUE,
  primary_guest_id VARCHAR(36) NOT NULL,
  property_code    VARCHAR(20),
  status           VARCHAR(20),
  check_in_date    DATE,
  check_out_date   DATE,
  arrival_time     TIME,
  departure_time   TIME,
  party_size       INT,
  comp_tier_id     INT,
  has_minors       BOOLEAN NOT NULL DEFAULT FALSE,
  booking_channel  VARCHAR(40),
  special_requests VARCHAR(500),
  CONSTRAINT fk_res_guest FOREIGN KEY (primary_guest_id) REFERENCES guest(guest_id),
  CONSTRAINT fk_res_tier  FOREIGN KEY (comp_tier_id)     REFERENCES comp_tier(comp_tier_id)
) ENGINE=InnoDB;

CREATE TABLE reservation_guest (
  reservation_guest_id VARCHAR(36) PRIMARY KEY,
  reservation_id       VARCHAR(36) NOT NULL,
  guest_id             VARCHAR(36),
  display_name         VARCHAR(120),
  age                  INT,
  age_band             VARCHAR(20),      -- adult | minor
  is_primary           BOOLEAN NOT NULL DEFAULT FALSE,
  relationship         VARCHAR(40),
  CONSTRAINT fk_rg_res   FOREIGN KEY (reservation_id) REFERENCES reservation(reservation_id),
  CONSTRAINT fk_rg_guest FOREIGN KEY (guest_id)       REFERENCES guest(guest_id)
) ENGINE=InnoDB;

CREATE TABLE room_stay (
  room_stay_id     VARCHAR(36) PRIMARY KEY,
  reservation_id   VARCHAR(36) NOT NULL,
  room_type_code   VARCHAR(40),
  room_number      VARCHAR(20),
  rate_plan_code   VARCHAR(40),
  nightly_rate     DECIMAL(12,2),
  is_comped        BOOLEAN NOT NULL DEFAULT FALSE,
  occupancy_adults INT,
  occupancy_minors INT,
  CONSTRAINT fk_rs_res FOREIGN KEY (reservation_id) REFERENCES reservation(reservation_id)
) ENGINE=InnoDB;

CREATE TABLE pre_booked_event (
  event_id       VARCHAR(36) PRIMARY KEY,
  reservation_id VARCHAR(36) NOT NULL,
  venue_id       VARCHAR(36) NULL,     -- ties a booking to a venue (for availability)
  offering_id    VARCHAR(36) NULL,     -- and to the offering it came from
  title          VARCHAR(120),
  segment        VARCHAR(40),
  venue_name     VARCHAR(120),
  starts_at      DATETIME,
  ends_at        DATETIME,
  party_count    INT,
  is_locked      BOOLEAN NOT NULL DEFAULT FALSE,
  source_system  VARCHAR(40),
  CONSTRAINT fk_pbe_res FOREIGN KEY (reservation_id) REFERENCES reservation(reservation_id)
) ENGINE=InnoDB;

CREATE TABLE stay_schedule_constraint (
  constraint_id  VARCHAR(36) PRIMARY KEY,
  reservation_id VARCHAR(36) NOT NULL,
  constraint_date DATE,
  earliest_start TIME,
  latest_end     TIME,
  quiet_window   VARCHAR(40),
  note           VARCHAR(255),
  CONSTRAINT fk_ssc_res FOREIGN KEY (reservation_id) REFERENCES reservation(reservation_id)
) ENGINE=InnoDB;

CREATE TABLE guest_consent (
  consent_id VARCHAR(36) PRIMARY KEY,
  guest_id   VARCHAR(36) NOT NULL,
  scope      VARCHAR(60),          -- e.g. pii:contact, marketing
  granted    BOOLEAN NOT NULL DEFAULT FALSE,
  granted_at DATETIME,
  expires_at DATETIME,
  source     VARCHAR(40),
  CONSTRAINT fk_gc_guest FOREIGN KEY (guest_id) REFERENCES guest(guest_id)
) ENGINE=InnoDB;

CREATE TABLE reservation_access_audit (
  audit_id        BIGINT AUTO_INCREMENT PRIMARY KEY,   -- surrogate (reference had none)
  reservation_id  VARCHAR(36),
  accessed_by     VARCHAR(120),
  mcp_tool        VARCHAR(80),
  action          VARCHAR(80),
  fields_returned JSON,
  request_context JSON,
  occurred_at     DATETIME DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_raa_res FOREIGN KEY (reservation_id) REFERENCES reservation(reservation_id)
) ENGINE=InnoDB;

CREATE TABLE guest_interest (
  guest_interest_id VARCHAR(36) PRIMARY KEY,
  guest_id          VARCHAR(36) NOT NULL,
  reservation_id    VARCHAR(36) NULL,        -- trip-scoped interest (nullable)
  category_id       INT NOT NULL,
  affinity_score    INT,                     -- 0..100 scale
  is_explicit       BOOLEAN NOT NULL DEFAULT TRUE,
  source            VARCHAR(40),
  captured_at       DATETIME DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_gi_guest FOREIGN KEY (guest_id)       REFERENCES guest(guest_id),
  CONSTRAINT fk_gi_res   FOREIGN KEY (reservation_id) REFERENCES reservation(reservation_id),
  CONSTRAINT fk_gi_cat   FOREIGN KEY (category_id)    REFERENCES interest_category(category_id)
) ENGINE=InnoDB;

CREATE TABLE venue (
  venue_id      VARCHAR(36) PRIMARY KEY,
  provider_id   VARCHAR(36),
  venue_name    VARCHAR(120) NOT NULL,
  category_id   INT,
  property_code VARCHAR(20),
  opens_time    TIME,
  closes_time   TIME,
  capacity      INT,
  min_age       INT,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT fk_venue_provider FOREIGN KEY (provider_id) REFERENCES offer_provider(provider_id),
  CONSTRAINT fk_venue_cat      FOREIGN KEY (category_id)  REFERENCES interest_category(category_id)
) ENGINE=InnoDB;

CREATE TABLE offering (
  offering_id         VARCHAR(36) PRIMARY KEY,
  venue_id            VARCHAR(36),
  provider_id         VARCHAR(36),
  title               VARCHAR(120) NOT NULL,
  category_id         INT,
  segment             VARCHAR(40),
  typical_start       TIME,
  duration_min        INT,
  base_price          DECIMAL(12,2),
  currency            VARCHAR(3),
  is_age_restricted   BOOLEAN NOT NULL DEFAULT FALSE,
  min_age             INT,
  is_bookable         BOOLEAN NOT NULL DEFAULT TRUE,
  availability_status VARCHAR(20),
  CONSTRAINT fk_off_venue    FOREIGN KEY (venue_id)    REFERENCES venue(venue_id),
  CONSTRAINT fk_off_provider FOREIGN KEY (provider_id) REFERENCES offer_provider(provider_id),
  CONSTRAINT fk_off_cat      FOREIGN KEY (category_id)  REFERENCES interest_category(category_id)
) ENGINE=InnoDB;

CREATE TABLE promotion (
  promo_id           VARCHAR(36) PRIMARY KEY,
  offering_id        VARCHAR(36),
  provider_id        VARCHAR(36),
  promo_code         VARCHAR(40),
  title              VARCHAR(120),
  comp_tier_required INT,
  discount_type      VARCHAR(20),          -- amount | percent
  discount_value     DECIMAL(12,2),
  redemption_rules   VARCHAR(255),
  valid_from         DATE,
  valid_to           DATE,
  is_active          BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT fk_promo_off      FOREIGN KEY (offering_id)        REFERENCES offering(offering_id),
  CONSTRAINT fk_promo_provider FOREIGN KEY (provider_id)        REFERENCES offer_provider(provider_id),
  CONSTRAINT fk_promo_tier     FOREIGN KEY (comp_tier_required) REFERENCES comp_tier(comp_tier_id)
) ENGINE=InnoDB;

CREATE TABLE reservation_offer_recommendation (
  rec_id              VARCHAR(36) PRIMARY KEY,
  reservation_id      VARCHAR(36) NOT NULL,
  offering_id         VARCHAR(36) NOT NULL,
  matched_category_id INT,
  match_score         DOUBLE,
  is_age_eligible     BOOLEAN,
  is_tier_eligible    BOOLEAN,
  suppressed_reason   VARCHAR(120),
  CONSTRAINT fk_ror_res FOREIGN KEY (reservation_id)      REFERENCES reservation(reservation_id),
  CONSTRAINT fk_ror_off FOREIGN KEY (offering_id)         REFERENCES offering(offering_id),
  CONSTRAINT fk_ror_cat FOREIGN KEY (matched_category_id) REFERENCES interest_category(category_id)
) ENGINE=InnoDB;

-- pre_booked_event -> venue/offering FKs (added here since those tables are created above)
ALTER TABLE pre_booked_event
  ADD CONSTRAINT fk_pbe_venue    FOREIGN KEY (venue_id)    REFERENCES venue(venue_id),
  ADD CONSTRAINT fk_pbe_offering FOREIGN KEY (offering_id) REFERENCES offering(offering_id);
