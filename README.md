# Eco-Grocery Database (CMT321)

This project contains the complete 18-table relational database schema, seed data, and verification queries for the **Eco-Grocery CMT321** assignment based on MySQL 8.0+.

---

## ⚡ Quick Start for Teammates (Direct in MySQL Workbench)

1. **Download the file from GitHub:**
   - Go directly to: [Eco_Grocery_MySQL_Schema_and_Sample_Data.sql on GitHub](https://github.com/ImLWChuen/CMT321-Eco-Grocery-Database/blob/main/Eco_Grocery_MySQL_Schema_and_Sample_Data.sql)
   - Click the **Download raw file** button (icon at the top-right of the file viewer).

2. **Open it in MySQL Workbench:**
   - Open MySQL Workbench and connect to your MySQL server.
   - Click **File** > **Open SQL Script...** and select the downloaded `.sql` file.

3. **Click Run:**
   - Click the **Lightning Bolt (⚡)** icon to execute from top to bottom.
   - Click the **Refresh (🔄)** icon on the left under **Schemas** to see `eco_grocery_cmt321` and all 18 tables ready to use!

---

## 📁 Repository Files

- [Eco_Grocery_MySQL_Schema_and_Sample_Data.sql](file:///c:/CMT321%20-%20Eco-Grocery%20Database/Eco_Grocery_MySQL_Schema_and_Sample_Data.sql) — Main SQL script containing DDL (18 tables + 1 view), transactional seed procedure (`seed_eco_grocery()`), and verification queries.
- [connect_mysql_cli.cmd](file:///c:/CMT321%20-%20Eco-Grocery%20Database/connect_mysql_cli.cmd) — Windows batch helper to connect to Docker MySQL with formatted CLI output.

---

## 🏗️ Schema Architecture (18 Tables + 1 View)

The schema is organized into 4 dependency layers:

### Layer 1: Independent Master Tables
1. `APP_USER` — User accounts with role-based access (`customer`, `staff`, `admin`) and case-insensitive unique constraints.
2. `MEMBERSHIP_TYPE` — Tier definitions (`Bronze`, `Silver`, `Gold`) with spending thresholds.
3. `CATEGORY` — Product categories.
4. `DISCOUNT` — Date-bounded promotions and percentage rates.
5. `SUPPLIER` — Supplier directory with rating limits [1.00 - 5.00].

### Layer 2: Customer & Product Profiles
6. `CUSTOMER` — Customer profiles linked 1:1 to `APP_USER`, with point balances and tier references.
7. `PRODUCT` — Catalog items with SKU, unit price, pack definitions, and active status flag.

### Layer 3: Relational Entities & Inventory
8. `CART` — Shopping carts with conditional uniqueness helper column `ACTIVE_CUSTOMER_ID` ensuring at most one active cart per customer.
9. `SALES_ORDER` — Order headers capturing status, frozen discount amount, shipping fee, points earned/redeemed.
10. `FEEDBACK` — Customer ratings [1 - 5] and comments.
11. `INVENTORY` — Stock level per product (`PRODUCT_ID` as shared PK/FK) with reorder thresholds.
12. `SUPPLIER_PRODUCT` — Composite pair (`PRODUCT_ID`, `SUPPLIER_ID`) defining active supplier pricing and agreement dates.

### Layer 4: Order Items, Transactions & Fulfillment
13. `CART_ITEM` — Items in cart with composite PK (`CART_ID`, `PRODUCT_ID`).
14. `ORDER_ITEM` — Line items on confirmed orders freezing `UNIT_PRICE_AT_SALE`.
15. `PAYMENT` — Payment attempts with conditional uniqueness helper `SUCCESSFUL_ORDER_ID` ensuring at most one successful payment per order.
16. `INVOICE` — 1:1 invoice records with frozen billing snapshots.
17. `DELIVERY` — 1:1 shipment records tracking status and delivery milestones.
18. `RESTOCK_RECORD` — Inbound stock receipts referencing the composite `SUPPLIER_PRODUCT` pair.

### Calculated View
- `V_ORDER_TOTAL` — Aggregates order item subtotals, subtracts discounts, and adds shipping fees without row multiplication.

---

## 🚀 Execution & Viewing Instructions

### Docker Setup (Currently Active Container: `mysql-local`)
- **Container Name**: `mysql-local`
- **Host Port**: `3307`
- **User**: `root`
- **Password**: `rootpassword`
- **Database**: `eco_grocery_cmt321`

#### Method 1: Interactive Terminal (CLI)
Double-click [connect_mysql_cli.cmd](file:///c:/CMT321%20-%20Eco-Grocery%20Database/connect_mysql_cli.cmd) or run:
```powershell
docker exec -it mysql-local mysql -u root -prootpassword eco_grocery_cmt321
```

Inside the MySQL prompt:
```sql
-- View all 18 tables and 1 view
SHOW FULL TABLES;

-- Inspect products and inventory
SELECT p.PRODUCT_ID, p.SKU, p.PRODUCT_NAME, p.CURRENT_PRICE, i.QUANTITY_ON_HAND
FROM PRODUCT p JOIN INVENTORY i ON p.PRODUCT_ID = i.PRODUCT_ID;

-- View calculated order totals
SELECT * FROM V_ORDER_TOTAL;

-- Exit the prompt
EXIT;
```

#### Method 2: MySQL Workbench (Complete Step-by-Step Guide)

You can use **MySQL Workbench 8.0** as a visual GUI to inspect tables, view rows in spreadsheet grids, run queries, and generate visual ER diagrams.

##### 1. Connect to the Database
1. Open **MySQL Workbench**.
2. Click the **`+`** icon next to **MySQL Connections** on the home screen.
3. Configure the connection parameters:
   - **Connection Name**: `Docker Eco-Grocery`
   - **Connection Method**: `Standard (TCP/IP)`
   - **Hostname**: `127.0.0.1`
   - **Port**: `3307` *(Important: port 3307 is mapped to your Docker container)*
   - **Username**: `root`
   - **Password**: Click **Store in Vault...**, enter `rootpassword`, and click **OK**.
4. Click **Test Connection**.
   > [!NOTE]
   > **Version Warning**: Workbench 8.0 may display a dialog stating:  
   > *"Unsupported server version: MySQL ... MySQL Workbench was tested with MySQL version 8.0..."*  
   > This is completely normal because Docker pulls the latest MySQL build. Check **"Don't show this warning again"** and click **Continue Anyway**.
5. Click **OK** to save the connection tile, then double-click the **Docker Eco-Grocery** tile to open the SQL IDE.

---

##### 2. Browse Tables & View Data in a Grid
1. In the left sidebar:
   - If you see **Administration**, click the **Schemas** tab at the bottom-left of that sidebar.
   - If `eco_grocery_cmt321` does not appear right away, click the **Refresh icon (🔄)** next to the word **SCHEMAS**.
2. Expand **`eco_grocery_cmt321`** > **`Tables`**.
3. You will see all 18 tables (`APP_USER`, `PRODUCT`, `SALES_ORDER`, `INVENTORY`, `PAYMENT`, etc.).
4. **To view table data**:
   - Hover over any table (e.g., `PRODUCT`) and click the small **Table Grid icon** on the right side.
   - *Or* right-click the table and choose **Select Rows - Limit 1000**.
   - An Excel-style spreadsheet will display all rows and columns with sorting and cell inspection.

---

##### 3. Run Custom SQL Queries
1. Click the **New SQL Tab (📄+)** icon in the top toolbar.
2. Paste or write any SQL query, for example:
   ```sql
   USE eco_grocery_cmt321;

   -- 1. Check order totals and discounts from the calculated view
   SELECT * FROM V_ORDER_TOTAL;

   -- 2. Inspect stock balances against reorder thresholds
   SELECT p.SKU, p.PRODUCT_NAME, i.QUANTITY_ON_HAND, i.REORDER_LEVEL
   FROM PRODUCT p
   JOIN INVENTORY i ON p.PRODUCT_ID = i.PRODUCT_ID;

   -- 3. Check payment reconciliation (succeeded payments vs order total)
   SELECT p.PAYMENT_ID, p.ORDER_ID, p.AMOUNT, t.TOTAL_AMOUNT,
          CASE WHEN p.AMOUNT = t.TOTAL_AMOUNT THEN 'MATCH' ELSE 'MISMATCH' END AS STATUS
   FROM PAYMENT p
   JOIN V_ORDER_TOTAL t ON t.ORDER_ID = p.ORDER_ID
   WHERE p.STATUS = 'succeeded';
   ```
3. Click the **Lightning Bolt (⚡)** icon (or press `Ctrl + Shift + Enter`) to execute. Results appear immediately in the **Result Grid** below.

---

##### 4. How to Re-Run the Complete SQL Script in Workbench
If you ever want to re-run or inspect the schema file from scratch:
1. In MySQL Workbench, go to **File** > **Open SQL Script...**
2. Select [Eco_Grocery_MySQL_Schema_and_Sample_Data.sql](file:///c:/CMT321%20-%20Eco-Grocery%20Database/Eco_Grocery_MySQL_Schema_and_Sample_Data.sql).
3. Ensure **Stop on Error** is enabled.
4. Click the **Execute (Lightning Bolt ⚡)** button to run the script from top to bottom.

---

##### 5. Generate a Visual ER Diagram (EER Model)
You can automatically visualize all 18 tables and their foreign key relationships:
1. From the top menu, select **Database** > **Reverse Engineer...**
2. Choose your `Docker Eco-Grocery` connection and click **Next**.
3. Check the **`eco_grocery_cmt321`** schema and click **Next**.
4. Select all tables and click **Execute** > **Next** > **Finish**.
5. Workbench will generate an interactive, drag-and-drop Entity-Relationship Diagram showing all tables, primary keys, and foreign key connections.
