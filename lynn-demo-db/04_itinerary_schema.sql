-- ============================================================
-- Casino Itinerary Agent Fabric Demo — Schema migration (v2)
-- 04_itinerary_schema.sql  — EXTENDS lynn_demo (run after 01_schema.sql)
-- Adds: party composition/ages, canonical taxonomy, entertainment
--       interests (+inferred +history), unified offerings/partners/
--       promotions, offering bookings, and an audit log.
-- Nevada rule: gaming & alcohol age = 21 -> age_band/min_age use 21.
-- ============================================================
USE lynn_demo;

-- ---------- Epic 1: Reservation Context ----------
-- Anchor a stay by a human-facing confirmation code; capture schedule window.
ALTER TABLE room_reservations
  ADD COLUMN confirmation_code VARCHAR(12) UNIQUE AFTER reservation_id,
  ADD COLUMN arrival_time  TIME NULL,
  ADD COLUMN departure_time TIME NULL,
  ADD COLUMN comp_tier ENUM('None','Red','Black','Chairman') NOT NULL DEFAULT 'None';

-- Per-guest party composition with derived age band (21 = adult for gaming).
CREATE TABLE IF NOT EXISTS party_members (
  member_id      INT AUTO_INCREMENT PRIMARY KEY,
  reservation_id INT NOT NULL,
  full_name      VARCHAR(120),
  age            INT NOT NULL,
  age_band       ENUM('adult','minor')
                   AS (IF(age >= 21, 'adult', 'minor')) STORED,
  is_primary     BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT fk_pm_res FOREIGN KEY (reservation_id)
    REFERENCES room_reservations(reservation_id)
) ENGINE=InnoDB;

-- Epic 1.4 / 4.3: audit trail for governed access (PII-sensitive calls).
CREATE TABLE IF NOT EXISTS audit_log (
  audit_id          BIGINT AUTO_INCREMENT PRIMARY KEY,
  occurred_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  actor             VARCHAR(120),   -- itinerary-agent / broker client_id
  action            VARCHAR(80),    -- getReservation, getInterests, ...
  resource_type     VARCHAR(60),
  resource_id       VARCHAR(60),
  guest_id          INT NULL,
  pii_masked        BOOLEAN NOT NULL DEFAULT TRUE,
  gateway_client_id VARCHAR(120),
  detail            JSON NULL
) ENGINE=InnoDB;

-- ---------- Epic 2: Entertainment Interests ----------
-- Canonical taxonomy shared with the Offers MCP (Epic 2.4).
CREATE TABLE IF NOT EXISTS taxonomy_categories (
  category_code VARCHAR(20) PRIMARY KEY,
  display_name  VARCHAR(60) NOT NULL,
  description   VARCHAR(255)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS guest_interests (
  interest_id   INT AUTO_INCREMENT PRIMARY KEY,
  guest_id      INT NOT NULL,
  category_code VARCHAR(20) NOT NULL,
  affinity      DECIMAL(3,2) NOT NULL DEFAULT 0.50,     -- 0..1 ranked weight
  source        ENUM('explicit','inferred') NOT NULL DEFAULT 'explicit',
  version       INT NOT NULL DEFAULT 1,
  updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_gi_guest FOREIGN KEY (guest_id)      REFERENCES guests(guest_id),
  CONSTRAINT fk_gi_cat   FOREIGN KEY (category_code) REFERENCES taxonomy_categories(category_code),
  UNIQUE KEY uq_guest_cat_src (guest_id, category_code, source)
) ENGINE=InnoDB;

-- Epic 2.3: writes are versioned -> keep prior values here.
CREATE TABLE IF NOT EXISTS guest_interests_history (
  hist_id       BIGINT AUTO_INCREMENT PRIMARY KEY,
  guest_id      INT NOT NULL,
  category_code VARCHAR(20),
  affinity      DECIMAL(3,2),
  source        ENUM('explicit','inferred'),
  version       INT,
  changed_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ---------- Epic 3: Casino & Partner Offers ----------
CREATE TABLE IF NOT EXISTS partners (
  partner_id INT AUTO_INCREMENT PRIMARY KEY,
  name       VARCHAR(120) NOT NULL,
  type       VARCHAR(60),                -- show | tour | retail | restaurant
  terms      VARCHAR(255)
) ENGINE=InnoDB;

-- Unified catalog for NON dining/gaming offerings (shows, tours, retail,
-- spa, nightlife) + partner assets. Dining/gaming stay in their own tables
-- and are folded in via v_offerings below.
CREATE TABLE IF NOT EXISTS offerings (
  offering_id   INT AUTO_INCREMENT PRIMARY KEY,
  name          VARCHAR(120) NOT NULL,
  source        ENUM('owned','partner') NOT NULL DEFAULT 'owned',
  partner_id    INT NULL,
  category_code VARCHAR(20) NOT NULL,
  subcategory   VARCHAR(40),            -- show | tour | retail | spa | nightclub
  location      VARCHAR(80),
  opens         TIME, closes TIME,
  capacity      INT NOT NULL DEFAULT 50,
  min_age       INT NULL,               -- 21 for alcohol/nightlife; NULL = all ages
  price_from    DECIMAL(10,2),
  description   VARCHAR(255),
  CONSTRAINT fk_off_partner FOREIGN KEY (partner_id)    REFERENCES partners(partner_id),
  CONSTRAINT fk_off_cat     FOREIGN KEY (category_code) REFERENCES taxonomy_categories(category_code)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS offering_reservations (
  reservation_id       INT AUTO_INCREMENT PRIMARY KEY,
  guest_id             INT NOT NULL,
  offering_id          INT NOT NULL,
  reservation_datetime DATETIME NOT NULL,
  party_size           INT NOT NULL DEFAULT 1,
  status               ENUM('held','confirmed','cancelled') NOT NULL DEFAULT 'confirmed',
  created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_or_guest FOREIGN KEY (guest_id)    REFERENCES guests(guest_id),
  CONSTRAINT fk_or_off   FOREIGN KEY (offering_id) REFERENCES offerings(offering_id),
  INDEX idx_or_slot (offering_id, reservation_datetime)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS promotions (
  promotion_id     INT AUTO_INCREMENT PRIMARY KEY,
  name             VARCHAR(120) NOT NULL,
  category_code    VARCHAR(20) NOT NULL,
  min_tier         ENUM('Red','Black','Chairman') NOT NULL DEFAULT 'Red',
  value            DECIMAL(10,2),
  redemption_rules VARCHAR(255),
  valid_from       DATE, valid_to DATE,
  min_age          INT NULL,
  CONSTRAINT fk_promo_cat FOREIGN KEY (category_code) REFERENCES taxonomy_categories(category_code)
) ENGINE=InnoDB;

-- One catalog surface for getOfferings across ALL categories.
-- offering_ref is prefixed: R=restaurant, G=gaming table, O=offerings row.
CREATE OR REPLACE VIEW v_offerings AS
  SELECT CONCAT('R', restaurant_id) AS offering_ref, name, 'owned' AS source,
         CAST(NULL AS UNSIGNED) AS partner_id, 'dining' AS category_code,
         'restaurant' AS subcategory, venue AS location, opens, closes,
         daily_capacity AS capacity, CAST(NULL AS SIGNED) AS min_age,
         CAST(NULL AS DECIMAL(10,2)) AS price_from, description
  FROM restaurants
  UNION ALL
  SELECT CONCAT('G', table_id), CONCAT(game_type,' — ',location), 'owned',
         NULL, 'gaming', 'table', location, NULL, NULL, seats, 21, min_bet, NULL
  FROM gaming_tables
  UNION ALL
  SELECT CONCAT('O', offering_id), name, source, partner_id, category_code,
         subcategory, location, opens, closes, capacity, min_age, price_from, description
  FROM offerings;
