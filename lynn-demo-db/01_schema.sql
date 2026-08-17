-- ============================================================
-- Lynn Las Vegas Agent Fabric Demo — Schema (Aiven Cloud MySQL 8)
-- 01_schema.sql
-- ------------------------------------------------------------
-- Aiven note: run as `avnadmin`. If your user cannot CREATE DATABASE,
-- delete the CREATE DATABASE / USE lines and run inside `defaultdb`.
-- ============================================================

CREATE DATABASE IF NOT EXISTS lynn_demo
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE lynn_demo;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS comps, table_reservations, dining_reservations,
                     room_reservations, gaming_tables, restaurants,
                     room_types, guests;
SET FOREIGN_KEY_CHECKS = 1;

CREATE TABLE guests (
  guest_id        INT AUTO_INCREMENT PRIMARY KEY,
  first_name      VARCHAR(60)  NOT NULL,
  last_name       VARCHAR(60)  NOT NULL,
  email           VARCHAR(120) UNIQUE,
  phone           VARCHAR(30),
  lynn_rewards_id VARCHAR(20)  UNIQUE,
  tier            ENUM('Red','Black','Chairman') NOT NULL DEFAULT 'Red',
  points_balance  INT           NOT NULL DEFAULT 0,
  credit_line     DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  created_at      TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE room_types (
  room_type_id      INT AUTO_INCREMENT PRIMARY KEY,
  name              VARCHAR(80) NOT NULL,
  tower             ENUM('Lynn','Encore') NOT NULL,
  description       VARCHAR(255),
  base_nightly_rate DECIMAL(10,2) NOT NULL,
  max_occupancy     INT NOT NULL,
  total_inventory   INT NOT NULL
) ENGINE=InnoDB;

CREATE TABLE restaurants (
  restaurant_id  INT AUTO_INCREMENT PRIMARY KEY,
  name           VARCHAR(80) NOT NULL,
  cuisine        VARCHAR(50) NOT NULL,
  venue          ENUM('Lynn','Encore') NOT NULL,
  price_tier     ENUM('$$','$$$','$$$$') NOT NULL DEFAULT '$$$',
  opens          TIME,
  closes         TIME,
  daily_capacity INT NOT NULL DEFAULT 40,
  description    VARCHAR(255)
) ENGINE=InnoDB;

CREATE TABLE gaming_tables (
  table_id  INT AUTO_INCREMENT PRIMARY KEY,
  game_type ENUM('Baccarat','Blackjack','Roulette','Craps','Poker') NOT NULL,
  location  ENUM('Main Casino','High-Limit','Salon Prive') NOT NULL,
  min_bet   DECIMAL(10,2) NOT NULL,
  max_bet   DECIMAL(10,2) NOT NULL,
  seats     INT NOT NULL DEFAULT 7
) ENGINE=InnoDB;

CREATE TABLE room_reservations (
  reservation_id INT AUTO_INCREMENT PRIMARY KEY,
  guest_id       INT NOT NULL,
  room_type_id   INT NOT NULL,
  check_in       DATE NOT NULL,
  check_out      DATE NOT NULL,
  num_guests     INT NOT NULL DEFAULT 1,
  rate_quoted    DECIMAL(10,2),
  status         ENUM('held','confirmed','cancelled') NOT NULL DEFAULT 'confirmed',
  created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_rr_guest    FOREIGN KEY (guest_id)     REFERENCES guests(guest_id),
  CONSTRAINT fk_rr_roomtype FOREIGN KEY (room_type_id) REFERENCES room_types(room_type_id),
  INDEX idx_rr_dates (room_type_id, check_in, check_out)
) ENGINE=InnoDB;

CREATE TABLE dining_reservations (
  reservation_id       INT AUTO_INCREMENT PRIMARY KEY,
  guest_id             INT NOT NULL,
  restaurant_id        INT NOT NULL,
  reservation_datetime DATETIME NOT NULL,
  party_size           INT NOT NULL,
  status               ENUM('held','confirmed','cancelled') NOT NULL DEFAULT 'confirmed',
  created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_dr_guest FOREIGN KEY (guest_id)      REFERENCES guests(guest_id),
  CONSTRAINT fk_dr_rest  FOREIGN KEY (restaurant_id) REFERENCES restaurants(restaurant_id),
  INDEX idx_dr_slot (restaurant_id, reservation_datetime)
) ENGINE=InnoDB;

CREATE TABLE table_reservations (
  reservation_id       INT AUTO_INCREMENT PRIMARY KEY,
  guest_id             INT NOT NULL,
  table_id             INT NOT NULL,
  reservation_datetime DATETIME NOT NULL,
  party_size           INT NOT NULL DEFAULT 1,
  status               ENUM('held','confirmed','cancelled') NOT NULL DEFAULT 'confirmed',
  created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_tr_guest FOREIGN KEY (guest_id) REFERENCES guests(guest_id),
  CONSTRAINT fk_tr_table FOREIGN KEY (table_id) REFERENCES gaming_tables(table_id),
  INDEX idx_tr_slot (table_id, reservation_datetime)
) ENGINE=InnoDB;

CREATE TABLE comps (
  comp_id    INT AUTO_INCREMENT PRIMARY KEY,
  guest_id   INT NOT NULL,
  comp_type  ENUM('dining','room','show','spa') NOT NULL,
  value      DECIMAL(10,2) NOT NULL,
  status     ENUM('evaluated','issued','denied') NOT NULL DEFAULT 'evaluated',
  reason     VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_comp_guest FOREIGN KEY (guest_id) REFERENCES guests(guest_id)
) ENGINE=InnoDB;
