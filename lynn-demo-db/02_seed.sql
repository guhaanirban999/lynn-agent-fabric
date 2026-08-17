-- ============================================================
-- Lynn Las Vegas Agent Fabric Demo — Seed data
-- 02_seed.sql   (run AFTER 01_schema.sql)
-- ============================================================
USE lynn_demo;

-- Guests 1..8. Hero VIP = Alex Carter (Black, guest_id 1, LR-100002).
INSERT INTO guests (first_name,last_name,email,phone,lynn_rewards_id,tier,points_balance,credit_line) VALUES
 ('Alex','Carter','alex.carter@example.com','+1-702-555-0102','LR-100002','Black',185000,250000.00),
 ('Priya','Nair','priya.nair@example.com','+1-702-555-0101','LR-100001','Chairman',520000,1000000.00),
 ('Marcus','Lee','marcus.lee@example.com','+1-702-555-0103','LR-100003','Red',12000,0.00),
 ('Sofia','Rossi','sofia.rossi@example.com','+1-702-555-0104','LR-100004','Black',96000,100000.00),
 ('David','Kim','david.kim@example.com','+1-702-555-0105','LR-100005','Red',3000,0.00),
 ('Elena','Petrova','elena.petrova@example.com','+1-702-555-0106','LR-100006','Chairman',640000,1500000.00),
 ('James','O''Brien','james.obrien@example.com','+1-702-555-0107','LR-100007','Black',140000,200000.00),
 ('Aisha','Khan','aisha.khan@example.com','+1-702-555-0108','LR-100008','Red',22000,0.00);

-- Room types 1..8
INSERT INTO room_types (name,tower,description,base_nightly_rate,max_occupancy,total_inventory) VALUES
 ('Resort Room','Lynn','Signature Lynn room, Strip or mountain view',329.00,2,60),
 ('Deluxe Panoramic View King','Lynn','Floor-to-ceiling Strip views',459.00,2,40),
 ('Panoramic View King Suite','Lynn','Separate living area, panoramic views',629.00,3,25),
 ('Lynn Tower Suite Salon','Lynn','Tower Suites tier with dedicated lobby',999.00,4,12),
 ('Encore Resort King','Encore','Bright corner-style Encore room',359.00,2,50),
 ('Encore Parlor Suite','Encore','Spacious one-bedroom Encore suite',749.00,4,20),
 ('Encore Tower Suite Parlor','Encore','Tower Suites parlor, premium service',1099.00,4,10),
 ('Duplex Panoramic Suite','Encore','Two-story top-tier suite',2499.00,6,4);

-- Restaurants 1..10
INSERT INTO restaurants (name,cuisine,venue,price_tier,opens,closes,daily_capacity,description) VALUES
 ('Mizumi','Japanese','Lynn','$$$$','17:30:00','22:00:00',50,'Japanese with waterfall garden'),
 ('SW Steakhouse','Steakhouse','Lynn','$$$$','17:30:00','22:00:00',60,'Prime steaks lakeside'),
 ('Lakeside','Seafood','Lynn','$$$$','17:30:00','22:00:00',45,'Seafood on the Lake of Dreams'),
 ('Wing Lei','Chinese','Lynn','$$$$','17:30:00','22:00:00',40,'Cantonese fine dining'),
 ('Costa di Mare','Italian Seafood','Lynn','$$$$','17:30:00','22:00:00',40,'Coastal Italian seafood'),
 ('The Country Club','American','Lynn','$$$','11:00:00','22:00:00',55,'American classics by the golf course'),
 ('Tableau','American','Lynn','$$$','07:00:00','14:00:00',40,'Atrium breakfast & brunch'),
 ('Delilah','Supper Club','Lynn','$$$$','17:00:00','23:00:00',70,'1930s-style supper club'),
 ('Sinatra','Italian','Encore','$$$$','17:30:00','22:00:00',50,'Classic Italian'),
 ('Jardin','American','Encore','$$$','07:00:00','22:00:00',60,'Garden-inspired all-day dining');

-- Gaming tables 1..8
INSERT INTO gaming_tables (game_type,location,min_bet,max_bet,seats) VALUES
 ('Baccarat','High-Limit',500.00,50000.00,9),
 ('Baccarat','Salon Prive',2000.00,150000.00,7),
 ('Blackjack','Main Casino',25.00,5000.00,7),
 ('Blackjack','High-Limit',200.00,25000.00,7),
 ('Roulette','Main Casino',10.00,2000.00,8),
 ('Roulette','High-Limit',100.00,10000.00,8),
 ('Craps','Main Casino',15.00,3000.00,12),
 ('Poker','Main Casino',5.00,1000.00,9);

-- Existing reservations (consume some inventory; leave the demo weekend open)
INSERT INTO room_reservations (guest_id,room_type_id,check_in,check_out,num_guests,rate_quoted,status) VALUES
 (2,4,'2026-09-12','2026-09-14',2,999.00,'confirmed'),
 (4,3,'2026-09-18','2026-09-20',2,629.00,'confirmed'),
 (7,6,'2026-09-25','2026-09-27',3,749.00,'confirmed');

INSERT INTO dining_reservations (guest_id,restaurant_id,reservation_datetime,party_size,status) VALUES
 (2,4,'2026-09-12 19:30:00',2,'confirmed'),
 (4,1,'2026-09-18 20:00:00',2,'confirmed'),
 (7,2,'2026-09-25 19:00:00',4,'confirmed');

INSERT INTO table_reservations (guest_id,table_id,reservation_datetime,party_size,status) VALUES
 (2,2,'2026-09-12 22:00:00',1,'confirmed'),
 (6,1,'2026-09-19 21:30:00',2,'confirmed');

INSERT INTO comps (guest_id,comp_type,value,status,reason) VALUES
 (1,'dining',500.00,'issued','Black tier anniversary dining credit'),
 (2,'room',2000.00,'issued','Chairman tier — 2 nights Tower Suite'),
 (1,'show',300.00,'evaluated','Eligible for Awakening tickets based on recent play');
