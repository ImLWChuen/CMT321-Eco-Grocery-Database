-- ECO GROCERY / CMT321
-- Complete 18-table schema and fictional sample data based on ERD_v2(1).pdf.
-- Target: MySQL 8.4 (not MariaDB). Run once in a NEW development database.
-- No DROP DATABASE and no disabling foreign-key checks.
-- If this database already exists, STOP and choose another development name
-- in both CREATE DATABASE and USE. Do not run against an existing populated DB.
-- Workbench: open this file, enable stop-on-error, execute from top to bottom.
-- CLI: mysql -u YOUR_USER -p < Eco_Grocery_MySQL_Schema_and_Sample_Data.sql
-- DDL commits independently. Only the sample INSERT section is transactional.
-- Requires CREATE DATABASE/TABLE/VIEW/ROUTINE permissions in the dev environment.
--
-- SCOPE / POLICIES
-- One retailer, one inventory pool, MYR, fixed packs/bundles/bottles/bags.
-- QUANTITY means number of selling units, not arbitrary kg. For loose weighed
-- groceries use DECIMAL quantities consistently in all quantity-bearing tables.
-- No batch/expiry tracking, refunds, split shipments, stock losses or returns.
-- These are future extensions, not capabilities of this schema.
-- Loyalty: 1 point per full RM of net merchandise on completed orders;
-- redemption (if enabled): 100 points = RM1, in multiples of 100 points.
-- DISCOUNT_AMOUNT is the TOTAL frozen monetary deduction, including points.
-- No points are redeemed in the seed; no separate deduction is subtracted twice.
-- Membership thresholds: cumulative completed net-merchandise spending.
-- Bronze RM0, Silver RM500, Gold RM1500; benefits here are descriptive only.
-- Prices and thresholds are MYR; supplier ratings are 1.00 through 5.00.
-- Date/time examples are UTC. Discount date boundaries are inclusive UTC dates.
-- Seed contacts/addresses are fictional. example.com emails are demonstration data.
-- Password placeholders are NOT hashes or usable login credentials. Replace them
-- with application-generated Argon2id/bcrypt hashes before authentication tests.
--
-- IMPLEMENTATION ADDITIONS (not new business entities)
-- CART.ACTIVE_CUSTOMER_ID and PAYMENT.SUCCESSFUL_ORDER_ID are generated helper
-- columns with UNIQUE constraints for conditional uniqueness. Never insert them.
-- V_ORDER_TOTAL is a calculated view, not a nineteenth table.
-- Corrected ERD spellings: AGREEMENT_START_DATE, SUPPLIER_ID, TRACKING_NUMBER.
--
-- ENFORCEMENT LIMITS
-- Row constraints/FKs do not enforce: nonempty confirmed orders, checkout price
-- freezing, discount eligibility/calculation, point conversion/balance updates,
-- valid status transitions, equal payment/order totals, sellable inventory rows,
-- receipt deduplication, agreement-date eligibility, or stock deduction on sale.
-- Implement those in transactional routines/application logic before live use.
-- In particular, an INSERT into RESTOCK_RECORD does not automatically add stock.
-- Receipt+stock updates, checkout+stock updates, cancellation and points updates
-- must each be atomic; lock affected rows in a consistent order and retry deadlocks.
-- A real external payment cannot be undone with SQL ROLLBACK. Use a payment
-- simulator for the assignment's simple atomic checkout demonstration.
-- APP_USER.ROLE is application metadata, not MySQL GRANT-based access control.

CREATE DATABASE eco_grocery_cmt321
  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE eco_grocery_cmt321;
SET NAMES utf8mb4;
SET time_zone = '+00:00';
SET SESSION sql_mode = 'STRICT_TRANS_TABLES,ONLY_FULL_GROUP_BY,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

-- ============================================================
-- LAYER 1: INDEPENDENT TABLES
-- ============================================================

-- 01. Login accounts. Usernames/emails use case-insensitive uniqueness.
CREATE TABLE APP_USER (
  USER_ID INT UNSIGNED NOT NULL AUTO_INCREMENT,
  USERNAME VARCHAR(50) NOT NULL,
  LOGIN_EMAIL VARCHAR(254) NOT NULL,
  PASSWORD_HASH VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  ROLE VARCHAR(20) NOT NULL DEFAULT 'customer',
  FULL_NAME VARCHAR(150) NOT NULL,
  LAST_LOGIN DATETIME NULL,
  CONSTRAINT pk_app_user PRIMARY KEY (USER_ID),
  CONSTRAINT uq_user_username UNIQUE (USERNAME),
  CONSTRAINT uq_user_email UNIQUE (LOGIN_EMAIL),
  CONSTRAINT ck_user_role CHECK (ROLE IN ('customer','staff','admin')),
  CONSTRAINT ck_user_username CHECK (CHAR_LENGTH(TRIM(USERNAME)) > 0),
  CONSTRAINT ck_user_email CHECK (CHAR_LENGTH(TRIM(LOGIN_EMAIL)) > 0),
  CONSTRAINT ck_user_name CHECK (CHAR_LENGTH(TRIM(FULL_NAME)) > 0)
) ENGINE=InnoDB;

-- 02. Membership tier definitions.
CREATE TABLE MEMBERSHIP_TYPE (
  MEMBERSHIP_ID INT UNSIGNED NOT NULL AUTO_INCREMENT,
  TYPE_NAME VARCHAR(50) NOT NULL,
  BENEFITS TEXT NULL,
  MIN_PURCHASE DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  UPGRADE_PURCHASE DECIMAL(12,2) NULL,
  CONSTRAINT pk_membership PRIMARY KEY (MEMBERSHIP_ID),
  CONSTRAINT uq_membership_name UNIQUE (TYPE_NAME),
  CONSTRAINT ck_membership_name CHECK (CHAR_LENGTH(TRIM(TYPE_NAME)) > 0),
  CONSTRAINT ck_membership_min CHECK (MIN_PURCHASE >= 0),
  CONSTRAINT ck_membership_upgrade CHECK (UPGRADE_PURCHASE IS NULL OR UPGRADE_PURCHASE > MIN_PURCHASE)
) ENGINE=InnoDB;

-- 03. Product categories.
CREATE TABLE CATEGORY (
  CATEGORY_ID INT UNSIGNED NOT NULL AUTO_INCREMENT,
  CATEGORY_NAME VARCHAR(100) NOT NULL,
  CATEGORY_DESCRIPTION TEXT NULL,
  CONSTRAINT pk_category PRIMARY KEY (CATEGORY_ID),
  CONSTRAINT uq_category_name UNIQUE (CATEGORY_NAME),
  CONSTRAINT ck_category_name CHECK (CHAR_LENGTH(TRIM(CATEGORY_NAME)) > 0)
) ENGINE=InnoDB;

-- 04. Promotions. 0.1000 = 10%.
CREATE TABLE DISCOUNT (
  DISCOUNT_ID INT UNSIGNED NOT NULL AUTO_INCREMENT,
  DISCOUNT_NAME VARCHAR(100) NOT NULL,
  RATE DECIMAL(5,4) NOT NULL,
  START_DATE DATE NOT NULL,
  END_DATE DATE NOT NULL,
  CONSTRAINT pk_discount PRIMARY KEY (DISCOUNT_ID),
  CONSTRAINT ck_discount_name CHECK (CHAR_LENGTH(TRIM(DISCOUNT_NAME)) > 0),
  CONSTRAINT ck_discount_rate CHECK (RATE BETWEEN 0 AND 1),
  CONSTRAINT ck_discount_dates CHECK (END_DATE >= START_DATE)
) ENGINE=InnoDB;

-- 05. Fictional supplier master records.
CREATE TABLE SUPPLIER (
  SUPPLIER_ID INT UNSIGNED NOT NULL AUTO_INCREMENT,
  SUPPLIER_NAME VARCHAR(150) NOT NULL,
  CONTACT VARCHAR(100) NOT NULL,
  ADDRESS VARCHAR(500) NOT NULL,
  SUPPLIER_RATING DECIMAL(3,2) NULL,
  CONSTRAINT pk_supplier PRIMARY KEY (SUPPLIER_ID),
  CONSTRAINT ck_supplier_name CHECK (CHAR_LENGTH(TRIM(SUPPLIER_NAME)) > 0),
  CONSTRAINT ck_supplier_contact CHECK (CHAR_LENGTH(TRIM(CONTACT)) > 0),
  CONSTRAINT ck_supplier_address CHECK (CHAR_LENGTH(TRIM(ADDRESS)) > 0),
  CONSTRAINT ck_supplier_rating CHECK (SUPPLIER_RATING IS NULL OR SUPPLIER_RATING BETWEEN 1 AND 5)
) ENGINE=InnoDB;

-- ============================================================
-- LAYER 2: CUSTOMER AND PRODUCT
-- All integer FK types match the referenced INT UNSIGNED PK.
-- Omitted ON DELETE/ON UPDATE actions use restrictive defaults.
-- ============================================================

-- 06. A user has at most one customer profile.
CREATE TABLE CUSTOMER (
  CUSTOMER_ID INT UNSIGNED NOT NULL AUTO_INCREMENT,
  USER_ID INT UNSIGNED NOT NULL,
  MEMBERSHIP_ID INT UNSIGNED NULL,
  CONTACT VARCHAR(30) NOT NULL,
  REGISTRATION_DATE DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  POINTS_BALANCE INT NOT NULL DEFAULT 0,
  LAST_EVALUATION_DATE DATETIME NULL,
  CONSTRAINT pk_customer PRIMARY KEY (CUSTOMER_ID),
  CONSTRAINT uq_customer_user UNIQUE (USER_ID),
  CONSTRAINT fk_customer_user FOREIGN KEY (USER_ID) REFERENCES APP_USER (USER_ID),
  CONSTRAINT fk_customer_membership FOREIGN KEY (MEMBERSHIP_ID) REFERENCES MEMBERSHIP_TYPE (MEMBERSHIP_ID),
  CONSTRAINT ck_customer_contact CHECK (CHAR_LENGTH(TRIM(CONTACT)) > 0),
  CONSTRAINT ck_customer_points CHECK (POINTS_BALANCE >= 0),
  CONSTRAINT ck_customer_evaluation CHECK (LAST_EVALUATION_DATE IS NULL OR LAST_EVALUATION_DATE >= REGISTRATION_DATE)
) ENGINE=InnoDB;

-- 07. Stock is held separately in INVENTORY.
CREATE TABLE PRODUCT (
  PRODUCT_ID INT UNSIGNED NOT NULL AUTO_INCREMENT,
  CATEGORY_ID INT UNSIGNED NOT NULL,
  SKU VARCHAR(40) NOT NULL,
  PRODUCT_NAME VARCHAR(150) NOT NULL,
  DESCRIPTION TEXT NULL,
  CURRENT_PRICE DECIMAL(10,2) NOT NULL,
  UNIT_MEASURE VARCHAR(40) NOT NULL,
  IS_ACTIVE BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT pk_product PRIMARY KEY (PRODUCT_ID),
  CONSTRAINT uq_product_sku UNIQUE (SKU),
  CONSTRAINT fk_product_category FOREIGN KEY (CATEGORY_ID) REFERENCES CATEGORY (CATEGORY_ID),
  CONSTRAINT ck_product_price CHECK (CURRENT_PRICE >= 0),
  CONSTRAINT ck_product_active CHECK (IS_ACTIVE IN (0,1)),
  CONSTRAINT ck_product_name CHECK (CHAR_LENGTH(TRIM(PRODUCT_NAME)) > 0),
  CONSTRAINT ck_product_sku CHECK (CHAR_LENGTH(TRIM(SKU)) > 0),
  CONSTRAINT ck_product_unit CHECK (CHAR_LENGTH(TRIM(UNIT_MEASURE)) > 0),
  INDEX ix_product_name (PRODUCT_NAME)
) ENGINE=InnoDB;

-- ============================================================
-- LAYER 3: TABLES DEPENDING ON LAYERS 1 AND 2
-- ============================================================

-- 08. Generated key permits many old carts but only one active per customer.
CREATE TABLE CART (
  CART_ID INT UNSIGNED NOT NULL AUTO_INCREMENT,
  CUSTOMER_ID INT UNSIGNED NOT NULL,
  STATUS VARCHAR(20) NOT NULL DEFAULT 'active',
  CREATED_AT DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UPDATED_AT DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  ACTIVE_CUSTOMER_ID INT UNSIGNED GENERATED ALWAYS AS
    (CASE WHEN STATUS = 'active' THEN CUSTOMER_ID ELSE NULL END) STORED,
  CONSTRAINT pk_cart PRIMARY KEY (CART_ID),
  CONSTRAINT fk_cart_customer FOREIGN KEY (CUSTOMER_ID) REFERENCES CUSTOMER (CUSTOMER_ID),
  CONSTRAINT uq_cart_active_customer UNIQUE (ACTIVE_CUSTOMER_ID),
  CONSTRAINT ck_cart_status CHECK (STATUS IN ('active','converted','abandoned')),
  CONSTRAINT ck_cart_dates CHECK (UPDATED_AT >= CREATED_AT)
) ENGINE=InnoDB;

-- 09. Totals are calculated from immutable confirmed order lines, not stored here.
CREATE TABLE SALES_ORDER (
  ORDER_ID INT UNSIGNED NOT NULL AUTO_INCREMENT,
  CUSTOMER_ID INT UNSIGNED NOT NULL,
  DISCOUNT_ID INT UNSIGNED NULL,
  ORDERED_AT DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  STATUS VARCHAR(20) NOT NULL DEFAULT 'draft',
  CURRENCY CHAR(3) NOT NULL DEFAULT 'MYR',
  DISCOUNT_AMOUNT DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  SHIPPING_FEE DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  POINTS_EARNED INT NOT NULL DEFAULT 0,
  POINTS_REDEEMED INT NOT NULL DEFAULT 0,
  CONSTRAINT pk_order PRIMARY KEY (ORDER_ID),
  CONSTRAINT fk_order_customer FOREIGN KEY (CUSTOMER_ID) REFERENCES CUSTOMER (CUSTOMER_ID),
  CONSTRAINT fk_order_discount FOREIGN KEY (DISCOUNT_ID) REFERENCES DISCOUNT (DISCOUNT_ID),
  CONSTRAINT ck_order_status CHECK (STATUS IN ('draft','pending_payment','confirmed','completed','cancelled')),
  CONSTRAINT ck_order_currency CHECK (CURRENCY = 'MYR'),
  CONSTRAINT ck_order_discount CHECK (DISCOUNT_AMOUNT >= 0),
  CONSTRAINT ck_order_shipping CHECK (SHIPPING_FEE >= 0),
  CONSTRAINT ck_order_points CHECK (POINTS_EARNED >= 0 AND POINTS_REDEEMED >= 0),
  INDEX ix_order_customer_date (CUSTOMER_ID, ORDERED_AT)
) ENGINE=InnoDB;

-- 10. General store feedback (not a verified product review).
CREATE TABLE FEEDBACK (
  FEEDBACK_ID INT UNSIGNED NOT NULL AUTO_INCREMENT,
  CUSTOMER_ID INT UNSIGNED NOT NULL,
  RATING TINYINT NOT NULL,
  FEEDBACK_COMMENT TEXT NULL,
  FEEDBACK_DATE DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_feedback PRIMARY KEY (FEEDBACK_ID),
  CONSTRAINT fk_feedback_customer FOREIGN KEY (CUSTOMER_ID) REFERENCES CUSTOMER (CUSTOMER_ID),
  CONSTRAINT ck_feedback_rating CHECK (RATING BETWEEN 1 AND 5)
) ENGINE=InnoDB;

-- 11. Shared PK/FK: at most one stock balance per product.
CREATE TABLE INVENTORY (
  PRODUCT_ID INT UNSIGNED NOT NULL,
  QUANTITY_ON_HAND INT NOT NULL DEFAULT 0,
  REORDER_LEVEL INT NOT NULL DEFAULT 10,
  UPDATED_AT DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT pk_inventory PRIMARY KEY (PRODUCT_ID),
  CONSTRAINT fk_inventory_product FOREIGN KEY (PRODUCT_ID) REFERENCES PRODUCT (PRODUCT_ID),
  CONSTRAINT ck_inventory_quantity CHECK (QUANTITY_ON_HAND >= 0),
  CONSTRAINT ck_inventory_reorder CHECK (REORDER_LEVEL >= 0)
) ENGINE=InnoDB;

-- 12. A supplier/product pair occurs once; agreement history is outside scope.
CREATE TABLE SUPPLIER_PRODUCT (
  PRODUCT_ID INT UNSIGNED NOT NULL,
  SUPPLIER_ID INT UNSIGNED NOT NULL,
  SUPPLIER_PRICE DECIMAL(10,2) NOT NULL,
  AGREEMENT_START_DATE DATE NOT NULL,
  AGREEMENT_END_DATE DATE NULL,
  CONSTRAINT pk_supplier_product PRIMARY KEY (PRODUCT_ID, SUPPLIER_ID),
  CONSTRAINT fk_sp_product FOREIGN KEY (PRODUCT_ID) REFERENCES PRODUCT (PRODUCT_ID),
  CONSTRAINT fk_sp_supplier FOREIGN KEY (SUPPLIER_ID) REFERENCES SUPPLIER (SUPPLIER_ID),
  CONSTRAINT ck_sp_price CHECK (SUPPLIER_PRICE >= 0),
  CONSTRAINT ck_sp_dates CHECK (AGREEMENT_END_DATE IS NULL OR AGREEMENT_END_DATE >= AGREEMENT_START_DATE)
) ENGINE=InnoDB;

-- ============================================================
-- LAYER 4: ITEMS, PAYMENT ATTEMPTS, DOCUMENTS AND RECEIPTS
-- ============================================================

-- 13. One row per product in a cart.
CREATE TABLE CART_ITEM (
  CART_ID INT UNSIGNED NOT NULL,
  PRODUCT_ID INT UNSIGNED NOT NULL,
  QUANTITY INT NOT NULL,
  CONSTRAINT pk_cart_item PRIMARY KEY (CART_ID, PRODUCT_ID),
  CONSTRAINT fk_ci_cart FOREIGN KEY (CART_ID) REFERENCES CART (CART_ID) ON DELETE CASCADE,
  CONSTRAINT fk_ci_product FOREIGN KEY (PRODUCT_ID) REFERENCES PRODUCT (PRODUCT_ID),
  CONSTRAINT ck_ci_quantity CHECK (QUANTITY > 0)
) ENGINE=InnoDB;

-- 14. Historical purchase prices, independent of PRODUCT.CURRENT_PRICE.
CREATE TABLE ORDER_ITEM (
  ORDER_ID INT UNSIGNED NOT NULL,
  PRODUCT_ID INT UNSIGNED NOT NULL,
  QUANTITY INT NOT NULL,
  UNIT_PRICE_AT_SALE DECIMAL(10,2) NOT NULL,
  CONSTRAINT pk_order_item PRIMARY KEY (ORDER_ID, PRODUCT_ID),
  CONSTRAINT fk_oi_order FOREIGN KEY (ORDER_ID) REFERENCES SALES_ORDER (ORDER_ID),
  CONSTRAINT fk_oi_product FOREIGN KEY (PRODUCT_ID) REFERENCES PRODUCT (PRODUCT_ID),
  CONSTRAINT ck_oi_quantity CHECK (QUANTITY > 0),
  CONSTRAINT ck_oi_price CHECK (UNIT_PRICE_AT_SALE >= 0)
) ENGINE=InnoDB;

-- 15. Multiple attempts; at most one successful full payment per order.
-- Provider references assume a single provider namespace in this prototype.
CREATE TABLE PAYMENT (
  PAYMENT_ID INT UNSIGNED NOT NULL AUTO_INCREMENT,
  ORDER_ID INT UNSIGNED NOT NULL,
  ATTEMPT_KEY VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  PROVIDER_REFERENCE VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NULL,
  AMOUNT DECIMAL(12,2) NOT NULL,
  STATUS VARCHAR(20) NOT NULL DEFAULT 'pending',
  METHOD VARCHAR(30) NOT NULL,
  CREATED_AT DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PAID_AT DATETIME NULL,
  SUCCESSFUL_ORDER_ID INT UNSIGNED GENERATED ALWAYS AS
    (CASE WHEN STATUS = 'succeeded' THEN ORDER_ID ELSE NULL END) STORED,
  CONSTRAINT pk_payment PRIMARY KEY (PAYMENT_ID),
  CONSTRAINT fk_payment_order FOREIGN KEY (ORDER_ID) REFERENCES SALES_ORDER (ORDER_ID),
  CONSTRAINT uq_payment_attempt UNIQUE (ATTEMPT_KEY),
  CONSTRAINT uq_payment_provider UNIQUE (PROVIDER_REFERENCE),
  CONSTRAINT uq_payment_success UNIQUE (SUCCESSFUL_ORDER_ID),
  CONSTRAINT ck_payment_amount CHECK (AMOUNT >= 0),
  CONSTRAINT ck_payment_status CHECK (STATUS IN ('pending','failed','succeeded')),
  CONSTRAINT ck_payment_method CHECK (METHOD IN ('fpx','card','ewallet')),
  CONSTRAINT ck_payment_paid CHECK (
    (STATUS = 'succeeded' AND PAID_AT IS NOT NULL AND PAID_AT >= CREATED_AT)
    OR (STATUS IN ('pending','failed') AND PAID_AT IS NULL)
  )
) ENGINE=InnoDB;

-- 16. One invoice per order; billing snapshot is independent of current profile.
CREATE TABLE INVOICE (
  INVOICE_ID INT UNSIGNED NOT NULL AUTO_INCREMENT,
  ORDER_ID INT UNSIGNED NOT NULL,
  INVOICE_NUMBER VARCHAR(50) NOT NULL,
  ISSUED_AT DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  BILLED_NAME VARCHAR(150) NOT NULL,
  BILLED_ADDRESS VARCHAR(500) NOT NULL,
  CONSTRAINT pk_invoice PRIMARY KEY (INVOICE_ID),
  CONSTRAINT uq_invoice_order UNIQUE (ORDER_ID),
  CONSTRAINT uq_invoice_number UNIQUE (INVOICE_NUMBER),
  CONSTRAINT fk_invoice_order FOREIGN KEY (ORDER_ID) REFERENCES SALES_ORDER (ORDER_ID)
) ENGINE=InnoDB;

-- 17. One delivery per order (no split shipments).
CREATE TABLE DELIVERY (
  DELIVERY_ID INT UNSIGNED NOT NULL AUTO_INCREMENT,
  ORDER_ID INT UNSIGNED NOT NULL,
  RECIPIENT_NAME VARCHAR(150) NOT NULL,
  PHONE VARCHAR(30) NOT NULL,
  ADDRESS_SNAPSHOT VARCHAR(500) NOT NULL,
  STATUS VARCHAR(20) NOT NULL DEFAULT 'pending',
  CARRIER VARCHAR(100) NULL,
  TRACKING_NUMBER VARCHAR(100) NULL,
  SHIPPED_AT DATETIME NULL,
  DELIVERED_AT DATETIME NULL,
  CONSTRAINT pk_delivery PRIMARY KEY (DELIVERY_ID),
  CONSTRAINT uq_delivery_order UNIQUE (ORDER_ID),
  CONSTRAINT fk_delivery_order FOREIGN KEY (ORDER_ID) REFERENCES SALES_ORDER (ORDER_ID),
  CONSTRAINT ck_delivery_status CHECK (STATUS IN ('pending','shipped','delivered','cancelled')),
  CONSTRAINT ck_delivery_dates CHECK (
    DELIVERED_AT IS NULL OR (SHIPPED_AT IS NOT NULL AND DELIVERED_AT >= SHIPPED_AT)
  ),
  CONSTRAINT ck_delivery_state CHECK (
    (STATUS = 'pending' AND SHIPPED_AT IS NULL AND DELIVERED_AT IS NULL)
    OR (STATUS = 'shipped' AND SHIPPED_AT IS NOT NULL AND DELIVERED_AT IS NULL)
    OR (STATUS = 'delivered' AND SHIPPED_AT IS NOT NULL AND DELIVERED_AT IS NOT NULL)
    OR (STATUS = 'cancelled' AND SHIPPED_AT IS NULL AND DELIVERED_AT IS NULL)
  )
) ENGINE=InnoDB;

-- 18. ONE composite FK references the complete supplier-product pair.
CREATE TABLE RESTOCK_RECORD (
  RESTOCK_ID INT UNSIGNED NOT NULL AUTO_INCREMENT,
  PRODUCT_ID INT UNSIGNED NOT NULL,
  SUPPLIER_ID INT UNSIGNED NOT NULL,
  UNIT_COST DECIMAL(10,2) NOT NULL,
  RECEIVED_AT DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  QUANTITY_ADDED INT NOT NULL,
  CONSTRAINT pk_restock PRIMARY KEY (RESTOCK_ID),
  CONSTRAINT fk_restock_pair FOREIGN KEY (PRODUCT_ID, SUPPLIER_ID)
    REFERENCES SUPPLIER_PRODUCT (PRODUCT_ID, SUPPLIER_ID),
  CONSTRAINT ck_restock_cost CHECK (UNIT_COST >= 0),
  CONSTRAINT ck_restock_quantity CHECK (QUANTITY_ADDED > 0)
) ENGINE=InnoDB;

-- Calculated totals: aggregates order lines separately to avoid multiplying
-- amounts when an order has multiple payment attempts.
CREATE VIEW V_ORDER_TOTAL AS
SELECT o.ORDER_ID, o.CUSTOMER_ID, o.STATUS, o.CURRENCY,
       COALESCE(l.SUBTOTAL, 0.00) AS SUBTOTAL,
       o.DISCOUNT_AMOUNT, o.SHIPPING_FEE,
       COALESCE(l.SUBTOTAL, 0.00) - o.DISCOUNT_AMOUNT + o.SHIPPING_FEE AS TOTAL_AMOUNT
FROM SALES_ORDER AS o
LEFT JOIN (
  SELECT ORDER_ID, SUM(QUANTITY * UNIT_PRICE_AT_SALE) AS SUBTOTAL
  FROM ORDER_ITEM GROUP BY ORDER_ID
) AS l ON l.ORDER_ID = o.ORDER_ID;

-- ============================================================
-- SAMPLE DATA: one transaction with automatic rollback on failure.
-- Fixed IDs are deliberate for readable, reproducible teaching examples.
-- Only run on the fresh tables above. Auto_increment remains available later.
-- ============================================================
DELIMITER $$
CREATE PROCEDURE seed_eco_grocery()
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;
  START TRANSACTION;

  INSERT INTO APP_USER
    (USER_ID,USERNAME,LOGIN_EMAIL,PASSWORD_HASH,ROLE,FULL_NAME,LAST_LOGIN)
  VALUES
    (1,'eco_admin','admin@example.com','!DEMO_NO_LOGIN_ADMIN','admin','Eco Grocery Demo Admin',NULL),
    (2,'eco_staff','staff@example.com','!DEMO_NO_LOGIN_STAFF','staff','Eco Grocery Demo Staff',NULL),
    (3,'demo_aina','aina@example.com','!DEMO_NO_LOGIN_AINA','customer','Aina Demo','2026-10-17 00:30:00'),
    (4,'demo_daniel','daniel@example.com','!DEMO_NO_LOGIN_DANIEL','customer','Daniel Demo','2026-10-17 01:00:00'),
    (5,'demo_mei','mei@example.com','!DEMO_NO_LOGIN_MEI','customer','Mei Demo',NULL);

  INSERT INTO MEMBERSHIP_TYPE
    (MEMBERSHIP_ID,TYPE_NAME,BENEFITS,MIN_PURCHASE,UPGRADE_PURCHASE)
  VALUES
    (1,'Bronze','Entry membership; access to the loyalty programme.',0.00,500.00),
    (2,'Silver','Access to selected member offers.',500.00,1500.00),
    (3,'Gold','Access to selected premium member offers.',1500.00,NULL);

  INSERT INTO CATEGORY (CATEGORY_ID,CATEGORY_NAME,CATEGORY_DESCRIPTION)
  VALUES
    (1,'Grains and Staples','Rice, oats and other pantry staples in fixed-size packs.'),
    (2,'Fresh Vegetables','Vegetables sold as fixed-size bundles.'),
    (3,'Fresh Fruit','Fruit sold as fixed-size packs.'),
    (4,'Household Refills','Household products sold in fixed-size refill bottles.'),
    (5,'Reusable Essentials','Reusable shopping accessories.');

  INSERT INTO DISCOUNT (DISCOUNT_ID,DISCOUNT_NAME,RATE,START_DATE,END_DATE)
  VALUES
    (1,'October Eco Basket',0.1000,'2026-10-01','2026-10-31'),
    (2,'November Pantry Offer',0.1500,'2026-11-01','2026-11-30'),
    (3,'September Offer - Expired',0.0500,'2026-09-01','2026-09-30');

  INSERT INTO SUPPLIER (SUPPLIER_ID,SUPPLIER_NAME,CONTACT,ADDRESS,SUPPLIER_RATING)
  VALUES
    (1,'Demo Pantry Supply','pantry@example.com','Fictional Supplier Address A, Penang',4.50),
    (2,'Demo Fresh Produce','produce@example.com','Fictional Supplier Address B, Kedah',4.20),
    (3,'Demo Refill Supply','refill@example.com','Fictional Supplier Address C, Perak',4.70),
    (4,'Demo Reusable Goods','reusable@example.com','Fictional Supplier Address D, Selangor',NULL);

  INSERT INTO CUSTOMER
    (CUSTOMER_ID,USER_ID,MEMBERSHIP_ID,CONTACT,REGISTRATION_DATE,POINTS_BALANCE,LAST_EVALUATION_DATE)
  VALUES
    (1,3,1,'DEMO-PHONE-001','2026-10-01 00:00:00',31,'2026-10-17 02:00:00'),
    (2,4,1,'DEMO-PHONE-002','2026-10-02 00:00:00',0,'2026-10-02 00:00:00'),
    (3,5,NULL,'DEMO-PHONE-003','2026-10-03 00:00:00',0,NULL);

  -- Product rows start inactive. Activate after inventory exists below.
  INSERT INTO PRODUCT
    (PRODUCT_ID,CATEGORY_ID,SKU,PRODUCT_NAME,DESCRIPTION,CURRENT_PRICE,UNIT_MEASURE,IS_ACTIVE)
  VALUES
    (1,1,'ECO-RICE-1KG','Brown Rice 1 kg','Fixed 1 kg pack of brown rice.',12.90,'1 kg pack',0),
    (2,1,'ECO-OATS-500G','Rolled Oats 500 g','Fixed 500 g pack of rolled oats.',8.50,'500 g pack',0),
    (3,2,'ECO-SPIN-250G','Spinach 250 g','Fixed 250 g bundle of spinach.',4.50,'250 g bundle',0),
    (4,3,'ECO-BANA-1KG','Bananas 1 kg','Fixed 1 kg pack of bananas.',6.90,'1 kg pack',0),
    (5,4,'ECO-DISH-500ML','Dishwashing Liquid Refill 500 ml','Refill sold as a fixed 500 ml bottle.',9.90,'500 ml bottle',0),
    (6,5,'ECO-TOTE-001','Reusable Shopping Bag','Reusable bag; environmental savings are not quantified.',5.90,'bag',0);

  INSERT INTO CART (CART_ID,CUSTOMER_ID,STATUS,CREATED_AT,UPDATED_AT)
  VALUES
    (1,1,'converted','2026-10-15 00:30:00','2026-10-15 01:00:00'),
    (2,2,'converted','2026-10-17 00:30:00','2026-10-17 01:01:00'),
    (3,3,'active','2026-10-17 01:30:00','2026-10-17 02:00:00'),
    (4,1,'active','2026-10-17 03:00:00','2026-10-17 03:00:00'),
    (5,2,'abandoned','2026-10-10 01:00:00','2026-10-11 01:00:00');

  INSERT INTO SALES_ORDER
    (ORDER_ID,CUSTOMER_ID,DISCOUNT_ID,ORDERED_AT,STATUS,CURRENCY,DISCOUNT_AMOUNT,SHIPPING_FEE,POINTS_EARNED,POINTS_REDEEMED)
  VALUES
    (1,1,1,'2026-10-15 01:00:00','completed','MYR',3.48,5.00,31,0),
    (2,2,NULL,'2026-10-17 01:00:00','confirmed','MYR',0.00,5.00,0,0),
    (3,3,NULL,'2026-10-17 02:00:00','pending_payment','MYR',0.00,5.00,0,0);

  INSERT INTO FEEDBACK (FEEDBACK_ID,CUSTOMER_ID,RATING,FEEDBACK_COMMENT,FEEDBACK_DATE)
  VALUES
    (1,1,5,'The fixed pack sizes were easy to understand.','2026-10-17 03:00:00'),
    (2,2,4,'Please add more pantry products.','2026-10-17 03:05:00'),
    (3,3,4,NULL,'2026-10-17 03:10:00');

  -- Snapshot seed balances = receipts below minus items on confirmed/completed orders.
  -- Pending order 3 and active cart contents do not reduce stock.
  INSERT INTO INVENTORY (PRODUCT_ID,QUANTITY_ON_HAND,REORDER_LEVEL,UPDATED_AT)
  VALUES
    (1,98,20,'2026-10-15 01:01:00'),
    (2,77,20,'2026-10-17 01:01:00'),
    (3,48,10,'2026-10-15 01:01:00'),
    (4,60,15,'2026-10-14 00:00:00'),
    (5,39,10,'2026-10-17 01:01:00'),
    (6,29,30,'2026-10-17 01:01:00');

  UPDATE PRODUCT SET IS_ACTIVE = 1 WHERE PRODUCT_ID IN (1,2,3,4,5,6);

  INSERT INTO SUPPLIER_PRODUCT
    (PRODUCT_ID,SUPPLIER_ID,SUPPLIER_PRICE,AGREEMENT_START_DATE,AGREEMENT_END_DATE)
  VALUES
    (1,1,8.00,'2026-01-01','2026-12-31'),
    (2,1,5.00,'2026-01-01','2026-12-31'),
    (3,2,2.50,'2026-01-01',NULL),
    (4,2,4.00,'2026-01-01',NULL),
    (5,3,6.00,'2026-01-01','2026-12-31'),
    (6,4,3.00,'2026-01-01',NULL),
    (1,2,8.30,'2026-01-01',NULL);

  INSERT INTO CART_ITEM (CART_ID,PRODUCT_ID,QUANTITY)
  VALUES (1,1,2),(1,3,2),(2,2,3),(2,5,1),(2,6,1),(3,4,2),(4,2,1),(5,6,2);

  INSERT INTO ORDER_ITEM (ORDER_ID,PRODUCT_ID,QUANTITY,UNIT_PRICE_AT_SALE)
  VALUES (1,1,2,12.90),(1,3,2,4.50),(2,2,3,8.50),(2,5,1,9.90),(2,6,1,5.90),(3,4,2,6.90);

  INSERT INTO PAYMENT
    (PAYMENT_ID,ORDER_ID,ATTEMPT_KEY,PROVIDER_REFERENCE,AMOUNT,STATUS,METHOD,CREATED_AT,PAID_AT)
  VALUES
    (1,1,'eco-order1-attempt1','DEMO-FAILED-001',36.32,'failed','fpx','2026-10-15 01:00:10',NULL),
    (2,1,'eco-order1-attempt2','DEMO-PAID-001',36.32,'succeeded','fpx','2026-10-15 01:00:30','2026-10-15 01:01:00'),
    (3,2,'eco-order2-attempt1','DEMO-PAID-002',46.30,'succeeded','ewallet','2026-10-17 01:00:10','2026-10-17 01:01:00'),
    (4,3,'eco-order3-attempt1',NULL,18.80,'pending','card','2026-10-17 02:00:10',NULL);

  INSERT INTO INVOICE (INVOICE_ID,ORDER_ID,INVOICE_NUMBER,ISSUED_AT,BILLED_NAME,BILLED_ADDRESS)
  VALUES
    (1,1,'ECO-2026-0001','2026-10-15 01:02:00','Aina Demo','Fictional Customer Address A, Penang'),
    (2,2,'ECO-2026-0002','2026-10-17 01:02:00','Daniel Demo','Fictional Customer Address B, Penang');

  INSERT INTO DELIVERY
    (DELIVERY_ID,ORDER_ID,RECIPIENT_NAME,PHONE,ADDRESS_SNAPSHOT,STATUS,CARRIER,TRACKING_NUMBER,SHIPPED_AT,DELIVERED_AT)
  VALUES
    (1,1,'Aina Demo','DEMO-PHONE-001','Fictional Customer Address A, Penang','delivered','Demo Local Delivery','DEMO-TRACK-001','2026-10-16 00:00:00','2026-10-17 02:00:00'),
    (2,2,'Daniel Demo','DEMO-PHONE-002','Fictional Customer Address B, Penang','pending',NULL,NULL,NULL,NULL),
    (3,3,'Mei Demo','DEMO-PHONE-003','Fictional Customer Address C, Penang','pending',NULL,NULL,NULL,NULL);

  INSERT INTO RESTOCK_RECORD
    (RESTOCK_ID,PRODUCT_ID,SUPPLIER_ID,UNIT_COST,RECEIVED_AT,QUANTITY_ADDED)
  VALUES
    (1,1,1,8.00,'2026-10-14 00:00:00',100),
    (2,2,1,5.00,'2026-10-14 00:00:00',80),
    (3,3,2,2.50,'2026-10-14 00:00:00',50),
    (4,4,2,4.00,'2026-10-14 00:00:00',60),
    (5,5,3,6.00,'2026-10-14 00:00:00',40),
    (6,6,4,3.00,'2026-10-14 00:00:00',30);

  COMMIT;
END$$
DELIMITER ;
CALL seed_eco_grocery();
DROP PROCEDURE seed_eco_grocery;

-- ============================================================
-- READ-ONLY VERIFICATION / DEMONSTRATION QUERIES
-- ============================================================

-- Expected: 18 base tables (the calculated view is separate).
SELECT COUNT(*) AS BASE_TABLE_COUNT
FROM information_schema.tables
WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE';

-- Expected counts: 5,3,5,3,4,3,6,5,3,3,6,7,8,6,4,2,3,6.
SELECT 'APP_USER' AS ENTITY,COUNT(*) AS ROW_COUNT FROM APP_USER
UNION ALL SELECT 'MEMBERSHIP_TYPE',COUNT(*) FROM MEMBERSHIP_TYPE
UNION ALL SELECT 'CATEGORY',COUNT(*) FROM CATEGORY
UNION ALL SELECT 'DISCOUNT',COUNT(*) FROM DISCOUNT
UNION ALL SELECT 'SUPPLIER',COUNT(*) FROM SUPPLIER
UNION ALL SELECT 'CUSTOMER',COUNT(*) FROM CUSTOMER
UNION ALL SELECT 'PRODUCT',COUNT(*) FROM PRODUCT
UNION ALL SELECT 'CART',COUNT(*) FROM CART
UNION ALL SELECT 'SALES_ORDER',COUNT(*) FROM SALES_ORDER
UNION ALL SELECT 'FEEDBACK',COUNT(*) FROM FEEDBACK
UNION ALL SELECT 'INVENTORY',COUNT(*) FROM INVENTORY
UNION ALL SELECT 'SUPPLIER_PRODUCT',COUNT(*) FROM SUPPLIER_PRODUCT
UNION ALL SELECT 'CART_ITEM',COUNT(*) FROM CART_ITEM
UNION ALL SELECT 'ORDER_ITEM',COUNT(*) FROM ORDER_ITEM
UNION ALL SELECT 'PAYMENT',COUNT(*) FROM PAYMENT
UNION ALL SELECT 'INVOICE',COUNT(*) FROM INVOICE
UNION ALL SELECT 'DELIVERY',COUNT(*) FROM DELIVERY
UNION ALL SELECT 'RESTOCK_RECORD',COUNT(*) FROM RESTOCK_RECORD;

-- Expected totals: order 1 = 36.32, order 2 = 46.30, order 3 = 18.80 MYR.
SELECT * FROM V_ORDER_TOTAL ORDER BY ORDER_ID;

-- Expected: both successful payments MATCH their order total.
SELECT p.PAYMENT_ID,p.ORDER_ID,p.AMOUNT,t.TOTAL_AMOUNT,
       CASE WHEN p.AMOUNT=t.TOTAL_AMOUNT THEN 'MATCH' ELSE 'MISMATCH' END AS RESULT
FROM PAYMENT p JOIN V_ORDER_TOTAL t ON t.ORDER_ID=p.ORDER_ID
WHERE p.STATUS='succeeded';

-- Expected: every row MATCH. Valid for this seed's zero opening stock,
-- no returns/losses/cancellations, and stock deducted on confirmed/completed orders.
SELECT p.PRODUCT_ID,p.PRODUCT_NAME,i.QUANTITY_ON_HAND,
       COALESCE(r.RECEIVED,0)-COALESCE(s.SOLD,0) AS EXPECTED_STOCK,
       CASE WHEN i.QUANTITY_ON_HAND=COALESCE(r.RECEIVED,0)-COALESCE(s.SOLD,0)
            THEN 'MATCH' ELSE 'MISMATCH' END AS RESULT
FROM PRODUCT p JOIN INVENTORY i ON i.PRODUCT_ID=p.PRODUCT_ID
LEFT JOIN (SELECT PRODUCT_ID,SUM(QUANTITY_ADDED) AS RECEIVED
           FROM RESTOCK_RECORD GROUP BY PRODUCT_ID) r ON r.PRODUCT_ID=p.PRODUCT_ID
LEFT JOIN (SELECT oi.PRODUCT_ID,SUM(oi.QUANTITY) AS SOLD
           FROM ORDER_ITEM oi JOIN SALES_ORDER o ON o.ORDER_ID=oi.ORDER_ID
           WHERE o.STATUS IN ('confirmed','completed') GROUP BY oi.PRODUCT_ID) s
  ON s.PRODUCT_ID=p.PRODUCT_ID
ORDER BY p.PRODUCT_ID;

-- Expected low-stock alert: reusable bag (29 remaining; threshold 30).
SELECT p.SKU,p.PRODUCT_NAME,i.QUANTITY_ON_HAND,i.REORDER_LEVEL
FROM PRODUCT p JOIN INVENTORY i ON i.PRODUCT_ID=p.PRODUCT_ID
WHERE i.QUANTITY_ON_HAND<=i.REORDER_LEVEL;

-- Expected: zero rows (no non-draft, non-cancelled order is empty).
SELECT o.ORDER_ID FROM SALES_ORDER o
WHERE o.STATUS NOT IN ('draft','cancelled')
AND NOT EXISTS (SELECT 1 FROM ORDER_ITEM oi WHERE oi.ORDER_ID=o.ORDER_ID);

-- Expected: zero rows (no excessive merchandise discount).
SELECT * FROM V_ORDER_TOTAL WHERE DISCOUNT_AMOUNT>SUBTOTAL;

-- Invoice display joins immutable order prices through the total view.
SELECT i.INVOICE_NUMBER,i.BILLED_NAME,t.SUBTOTAL,t.DISCOUNT_AMOUNT,
       t.SHIPPING_FEE,t.TOTAL_AMOUNT,t.CURRENCY
FROM INVOICE i JOIN V_ORDER_TOTAL t ON t.ORDER_ID=i.ORDER_ID;

-- Inspect generated keys and composite FK definitions.
SHOW CREATE TABLE CART;
SHOW CREATE TABLE PAYMENT;
SHOW CREATE TABLE RESTOCK_RECORD;
