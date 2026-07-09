
CREATE DATABASE IF NOT EXISTS ups_logistics;
USE ups_logistics;

-- ============================================================
-- TABLE CREATION
-- ============================================================

DROP TABLE IF EXISTS shipment_tracking;
DROP TABLE IF EXISTS delivery_agents;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS routes;
DROP TABLE IF EXISTS warehouses;

CREATE TABLE routes (
    Route_ID VARCHAR(10) PRIMARY KEY,
    Start_Location VARCHAR(100),
    End_Location VARCHAR(100),
    Distance_KM DECIMAL(10,2),
    Average_Travel_Time_Min INT,
    Traffic_Delay_Min INT
);

CREATE TABLE warehouses (
    Warehouse_ID VARCHAR(10) PRIMARY KEY,
    Location VARCHAR(100),
    Processing_Time_Min INT,
    Dispatch_Time TIME
);

CREATE TABLE orders (
    Order_ID VARCHAR(10),
    Customer_ID VARCHAR(10),
    Warehouse_ID VARCHAR(10),
    Route_ID VARCHAR(10),
    Order_Date DATE,
    Expected_Delivery_Date DATE,
    Actual_Delivery_Date DATE,
    Delivery_Status VARCHAR(20),
    FOREIGN KEY (Warehouse_ID) REFERENCES warehouses(Warehouse_ID),
    FOREIGN KEY (Route_ID) REFERENCES routes(Route_ID)
);

CREATE TABLE delivery_agents (
    Agent_ID VARCHAR(10) PRIMARY KEY,
    Route_ID VARCHAR(10),
    Shift_Hours INT,
    Avg_Speed_KM_HR INT,
    On_Time_Percentage DECIMAL(5,2),
    FOREIGN KEY (Route_ID) REFERENCES routes(Route_ID)
);

CREATE TABLE shipment_tracking (
    Shipment_ID VARCHAR(15),
    Order_ID VARCHAR(10),
    Checkpoint VARCHAR(30),
    Checkpoint_Time DATE,
    Delay_Reason VARCHAR(50)
);


-- ============================================================
-- TASK 1: DATA CLEANING & PREPARATION 
-- ============================================================

-- 1a. Identify and delete duplicate Order_ID records
-- First identify duplicates:
SELECT Order_ID, COUNT(*) AS cnt
FROM orders
GROUP BY Order_ID
HAVING COUNT(*) > 1;

-- Delete duplicates keeping the first occurrence:
DELETE o1
FROM orders o1
INNER JOIN orders o2
  ON o1.Order_ID = o2.Order_ID
  AND o1.Order_Date > o2.Order_Date;


-- 1b. Replace NULL Traffic_Delay_Min with the average delay for that route
-- Check for NULLs first:
SELECT Route_ID, Traffic_Delay_Min
FROM routes
WHERE Traffic_Delay_Min IS NULL;

-- Replace NULLs with overall average (since each route has one row):
UPDATE routes
SET Traffic_Delay_Min = (SELECT AVG(Traffic_Delay_Min) FROM (SELECT Traffic_Delay_Min FROM routes WHERE Traffic_Delay_Min IS NOT NULL) AS tmp)
WHERE Traffic_Delay_Min IS NULL;

-- 1c. Convert all date columns into YYYY-MM-DD format
-- Verify current format:
SELECT Order_ID, Order_Date, Expected_Delivery_Date, Actual_Delivery_Date
FROM orders
LIMIT 5;

-- Ensure proper DATE format 
UPDATE orders
SET Order_Date = DATE_FORMAT(STR_TO_DATE(Order_Date, '%Y-%m-%d'), '%Y-%m-%d'),
    Expected_Delivery_Date = DATE_FORMAT(STR_TO_DATE(Expected_Delivery_Date, '%Y-%m-%d'), '%Y-%m-%d'),
    Actual_Delivery_Date = DATE_FORMAT(STR_TO_DATE(Actual_Delivery_Date, '%Y-%m-%d'), '%Y-%m-%d');

-- 1d. Flag records where Actual_Delivery_Date is before Order_Date
SELECT Order_ID, Order_Date, Actual_Delivery_Date,
       CASE 
           WHEN Actual_Delivery_Date < Order_Date THEN 'FLAGGED - Invalid'
           ELSE 'Valid'
       END AS Date_Validity
FROM orders
WHERE Actual_Delivery_Date < Order_Date;

-- Add a flag column for permanent marking:
ALTER TABLE orders ADD COLUMN Date_Flag VARCHAR(20) DEFAULT 'Valid';

UPDATE orders
SET Date_Flag = 'FLAGGED'
WHERE Actual_Delivery_Date < Order_Date;

-- Verify flags:
SELECT Date_Flag, COUNT(*) AS record_count
FROM orders
GROUP BY Date_Flag;


-- ============================================================
-- TASK 2: DELIVERY DELAY ANALYSIS 
-- ============================================================

-- 2a. Calculate delivery delay (in days) for each order
SELECT 
    Order_ID,
    Order_Date,
    Expected_Delivery_Date,
    Actual_Delivery_Date,
    DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date) AS Delay_Days,
    Delivery_Status
FROM orders
ORDER BY Delay_Days DESC;

-- 2b. Find Top 10 delayed routes based on average delay days
SELECT 
    o.Route_ID,
    r.Start_Location,
    r.End_Location,
    ROUND(AVG(DATEDIFF(o.Actual_Delivery_Date, o.Expected_Delivery_Date)), 2) AS Avg_Delay_Days,
    COUNT(*) AS Total_Orders
FROM orders o
JOIN routes r ON o.Route_ID = r.Route_ID
WHERE DATEDIFF(o.Actual_Delivery_Date, o.Expected_Delivery_Date) > 0
GROUP BY o.Route_ID, r.Start_Location, r.End_Location
ORDER BY Avg_Delay_Days DESC
LIMIT 10;

-- 2c. Rank all orders by delay within each warehouse using window functions
SELECT 
    Order_ID,
    Warehouse_ID,
    DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date) AS Delay_Days,
    RANK() OVER (PARTITION BY Warehouse_ID ORDER BY DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date) DESC) AS Delay_Rank
FROM orders
ORDER BY Warehouse_ID, Delay_Rank;


-- ============================================================
-- TASK 3: ROUTE OPTIMIZATION INSIGHTS (10 Marks)
-- ============================================================

-- 3a. For each route: Avg delivery time, Avg traffic delay, efficiency ratio
SELECT 
    r.Route_ID,
    r.Start_Location,
    r.End_Location,
    ROUND(AVG(DATEDIFF(o.Actual_Delivery_Date, o.Order_Date)), 2) AS Avg_Delivery_Days,
    r.Traffic_Delay_Min AS Avg_Traffic_Delay_Min,
    ROUND(r.Distance_KM / r.Average_Travel_Time_Min, 2) AS Efficiency_Ratio,
    COUNT(o.Order_ID) AS Total_Orders
FROM routes r
LEFT JOIN orders o ON r.Route_ID = o.Route_ID
GROUP BY r.Route_ID, r.Start_Location, r.End_Location, r.Traffic_Delay_Min, 
         r.Distance_KM, r.Average_Travel_Time_Min
ORDER BY Efficiency_Ratio ASC;

-- 3b. Identify 3 routes with the worst efficiency ratio
SELECT 
    Route_ID,
    Start_Location,
    End_Location,
    Distance_KM,
    Average_Travel_Time_Min,
    ROUND(Distance_KM / Average_Travel_Time_Min, 2) AS Efficiency_Ratio
FROM routes
ORDER BY Efficiency_Ratio ASC
LIMIT 3;

-- 3c. Find routes with >20% delayed shipments
SELECT 
    o.Route_ID,
    r.Start_Location,
    r.End_Location,
    COUNT(*) AS Total_Shipments,
    SUM(CASE WHEN o.Delivery_Status = 'Delayed' THEN 1 ELSE 0 END) AS Delayed_Shipments,
    ROUND(SUM(CASE WHEN o.Delivery_Status = 'Delayed' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS Delay_Percentage
FROM orders o
JOIN routes r ON o.Route_ID = r.Route_ID
GROUP BY o.Route_ID, r.Start_Location, r.End_Location
HAVING Delay_Percentage > 20
ORDER BY Delay_Percentage DESC;

-- 3d. Recommendation: Routes needing optimization (high delay %, low efficiency)
SELECT 
    r.Route_ID,
    r.Start_Location,
    r.End_Location,
    ROUND(r.Distance_KM / r.Average_Travel_Time_Min, 2) AS Efficiency_Ratio,
    ROUND(SUM(CASE WHEN o.Delivery_Status = 'Delayed' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS Delay_Pct,
    r.Traffic_Delay_Min
FROM routes r
JOIN orders o ON r.Route_ID = o.Route_ID
GROUP BY r.Route_ID, r.Start_Location, r.End_Location, r.Distance_KM, 
         r.Average_Travel_Time_Min, r.Traffic_Delay_Min
HAVING Delay_Pct > 40
   OR Efficiency_Ratio < 0.5
ORDER BY Delay_Pct DESC, Efficiency_Ratio ASC;


-- ============================================================
-- TASK 4: WAREHOUSE PERFORMANCE 
-- ============================================================

-- 4a. Top 3 warehouses with highest average processing time
SELECT 
    Warehouse_ID,
    Location,
    Processing_Time_Min
FROM warehouses
ORDER BY Processing_Time_Min DESC
LIMIT 3;

-- 4b. Total vs delayed shipments for each warehouse
SELECT 
    o.Warehouse_ID,
    w.Location,
    COUNT(*) AS Total_Shipments,
    SUM(CASE WHEN o.Delivery_Status = 'Delayed' THEN 1 ELSE 0 END) AS Delayed_Shipments,
    SUM(CASE WHEN o.Delivery_Status = 'On Time' THEN 1 ELSE 0 END) AS OnTime_Shipments,
    ROUND(SUM(CASE WHEN o.Delivery_Status = 'Delayed' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS Delay_Rate_Pct
FROM orders o
JOIN warehouses w ON o.Warehouse_ID = w.Warehouse_ID
GROUP BY o.Warehouse_ID, w.Location
ORDER BY Delay_Rate_Pct DESC;

-- 4c. CTE to find bottleneck warehouses (processing time > global average)
WITH Global_Avg AS (
    SELECT AVG(Processing_Time_Min) AS Avg_Processing
    FROM warehouses
),
Warehouse_Stats AS (
    SELECT 
        w.Warehouse_ID,
        w.Location,
        w.Processing_Time_Min,
        COUNT(o.Order_ID) AS Total_Orders,
        SUM(CASE WHEN o.Delivery_Status = 'Delayed' THEN 1 ELSE 0 END) AS Delayed_Orders
    FROM warehouses w
    LEFT JOIN orders o ON w.Warehouse_ID = o.Warehouse_ID
    GROUP BY w.Warehouse_ID, w.Location, w.Processing_Time_Min
)
SELECT 
    ws.Warehouse_ID,
    ws.Location,
    ws.Processing_Time_Min,
    (SELECT Avg_Processing FROM Global_Avg) AS Global_Avg_Processing,
    ws.Total_Orders,
    ws.Delayed_Orders,
    'BOTTLENECK' AS Status
FROM Warehouse_Stats ws
WHERE ws.Processing_Time_Min > (SELECT Avg_Processing FROM Global_Avg)
ORDER BY ws.Processing_Time_Min DESC;

-- 4d. Rank warehouses by on-time delivery percentage
SELECT 
    o.Warehouse_ID,
    w.Location,
    COUNT(*) AS Total_Deliveries,
    SUM(CASE WHEN o.Delivery_Status = 'On Time' THEN 1 ELSE 0 END) AS OnTime_Deliveries,
    ROUND(SUM(CASE WHEN o.Delivery_Status = 'On Time' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS OnTime_Pct,
    RANK() OVER (ORDER BY SUM(CASE WHEN o.Delivery_Status = 'On Time' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) DESC) AS Ranking
FROM orders o
JOIN warehouses w ON o.Warehouse_ID = w.Warehouse_ID
GROUP BY o.Warehouse_ID, w.Location
ORDER BY Ranking;


-- ============================================================
-- TASK 5: DELIVERY AGENT PERFORMANCE 
-- ============================================================

-- 5a. Rank agents (per route) by on-time delivery percentage
SELECT 
    Agent_ID,
    Route_ID,
    On_Time_Percentage,
    RANK() OVER (PARTITION BY Route_ID ORDER BY On_Time_Percentage DESC) AS Agent_Rank
FROM delivery_agents
ORDER BY Route_ID, Agent_Rank;

-- 5b. Find agents with on-time % < 80%
SELECT 
    Agent_ID,
    Route_ID,
    On_Time_Percentage,
    Avg_Speed_KM_HR,
    Shift_Hours
FROM delivery_agents
WHERE On_Time_Percentage < 80
ORDER BY On_Time_Percentage ASC;

-- 5c. Compare average speed of top 5 vs bottom 5 agents using subqueries
SELECT 
    'Top 5 Agents' AS Category,
    ROUND(AVG(Avg_Speed_KM_HR), 2) AS Avg_Speed
FROM (
    SELECT Avg_Speed_KM_HR
    FROM delivery_agents
    ORDER BY On_Time_Percentage DESC
    LIMIT 5
) AS Top5

UNION ALL

SELECT 
    'Bottom 5 Agents' AS Category,
    ROUND(AVG(Avg_Speed_KM_HR), 2) AS Avg_Speed
FROM (
    SELECT Avg_Speed_KM_HR
    FROM delivery_agents
    ORDER BY On_Time_Percentage ASC
    LIMIT 5
) AS Bottom5;


-- ============================================================
-- TASK 6: SHIPMENT TRACKING ANALYTICS 
-- ============================================================

-- 6a. For each order, list the last checkpoint and time
SELECT 
    st.Order_ID,
    st.Checkpoint AS Last_Checkpoint,
    st.Checkpoint_Time AS Last_Checkpoint_Time
FROM shipment_tracking st
INNER JOIN (
    SELECT Order_ID, MAX(Checkpoint_Time) AS Max_Time
    FROM shipment_tracking
    GROUP BY Order_ID
) latest ON st.Order_ID = latest.Order_ID AND st.Checkpoint_Time = latest.Max_Time
GROUP BY st.Order_ID, st.Checkpoint, st.Checkpoint_Time
ORDER BY st.Order_ID;

-- Alternative using window function:
WITH RankedCheckpoints AS (
    SELECT 
        Order_ID,
        Checkpoint,
        Checkpoint_Time,
        Delay_Reason,
        ROW_NUMBER() OVER (PARTITION BY Order_ID ORDER BY Checkpoint DESC) AS rn
    FROM shipment_tracking
)
SELECT Order_ID, Checkpoint AS Last_Checkpoint, Checkpoint_Time, Delay_Reason
FROM RankedCheckpoints
WHERE rn = 1
ORDER BY Order_ID;

-- 6b. Find most common delay reasons (excluding None/NULL)
SELECT 
    Delay_Reason,
    COUNT(*) AS Occurrence_Count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM shipment_tracking WHERE Delay_Reason IS NOT NULL), 2) AS Percentage
FROM shipment_tracking
WHERE Delay_Reason IS NOT NULL
  AND Delay_Reason != 'None'
GROUP BY Delay_Reason
ORDER BY Occurrence_Count DESC;

-- 6c. Identify orders with >2 delayed checkpoints
SELECT 
    Order_ID,
    COUNT(*) AS Delayed_Checkpoints,
    GROUP_CONCAT(DISTINCT Delay_Reason ORDER BY Delay_Reason SEPARATOR ', ') AS Delay_Reasons
FROM shipment_tracking
WHERE Delay_Reason IS NOT NULL
  AND Delay_Reason != 'None'
GROUP BY Order_ID
HAVING COUNT(*) > 2
ORDER BY Delayed_Checkpoints DESC;


-- ============================================================
-- TASK 7: ADVANCED KPI REPORTING 
-- ============================================================

-- 7a. Average Delivery Delay per Region (Start_Location)
SELECT 
    r.Start_Location AS Region,
    COUNT(o.Order_ID) AS Total_Orders,
    ROUND(AVG(DATEDIFF(o.Actual_Delivery_Date, o.Expected_Delivery_Date)), 2) AS Avg_Delay_Days,
    SUM(CASE WHEN o.Delivery_Status = 'Delayed' THEN 1 ELSE 0 END) AS Delayed_Orders
FROM orders o
JOIN routes r ON o.Route_ID = r.Route_ID
GROUP BY r.Start_Location
ORDER BY Avg_Delay_Days DESC;

-- 7b. On-Time Delivery Percentage (Overall)
SELECT 
    COUNT(*) AS Total_Deliveries,
    SUM(CASE WHEN Delivery_Status = 'On Time' THEN 1 ELSE 0 END) AS OnTime_Deliveries,
    ROUND(SUM(CASE WHEN Delivery_Status = 'On Time' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS OnTime_Delivery_Pct
FROM orders;

-- On-Time Delivery % by Route:
SELECT 
    o.Route_ID,
    r.Start_Location,
    r.End_Location,
    COUNT(*) AS Total_Deliveries,
    SUM(CASE WHEN o.Delivery_Status = 'On Time' THEN 1 ELSE 0 END) AS OnTime_Deliveries,
    ROUND(SUM(CASE WHEN o.Delivery_Status = 'On Time' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS OnTime_Pct
FROM orders o
JOIN routes r ON o.Route_ID = r.Route_ID
GROUP BY o.Route_ID, r.Start_Location, r.End_Location
ORDER BY OnTime_Pct DESC;

-- 7c. Average Traffic Delay per Route
SELECT 
    Route_ID,
    Start_Location,
    End_Location,
    Traffic_Delay_Min,
    Distance_KM,
    ROUND(Traffic_Delay_Min * 100.0 / Average_Travel_Time_Min,
            2) AS Traffic_Delay_Pct_of_Travel
FROM
    routes
ORDER BY Traffic_Delay_Min DESC;



