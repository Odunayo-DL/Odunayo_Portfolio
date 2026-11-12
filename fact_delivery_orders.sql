-- Database preparation--
CREATE DATABASE logistic_project;
-- importing data through table wizard
SELECT * 
FROM logistic_project.fact_delivery_orders;

-- DATA CLEANING --
SELECT * 
FROM fact_delivery_orders;

-- date variable from integer to date data type--
-- adding new DATE column before dropping previous ones--
ALTER TABLE fact_delivery_orders
ADD COLUMN Dispatch_Date DATE,
ADD COLUMN Promised_Date DATE,
ADD COLUMN Delivery_Date DATE;

-- Temporarily disabling Safe Update Mode
SET SQL_SAFE_UPDATES = 0;
-- Convert the integer values (YYYYMMDD)--
UPDATE fact_delivery_orders
SET 
Dispatch_Date = STR_TO_DATE(CAST(DispatchDateKey AS CHAR), '%Y%m%d'),
Promised_Date = STR_TO_DATE(CAST(PromisedDateKey AS CHAR), '%Y%m%d'),
Delivery_Date = STR_TO_DATE(CAST(DeliveryDateKey AS CHAR), '%Y%m%d'); 

-- re-enable Safe Update Mode --
SET SQL_SAFE_UPDATES = 1;

--  Drop the old INT columns--
ALTER TABLE fact_delivery_orders
DROP COLUMN DispatchDateKey,
DROP COLUMN PromisedDateKey,
DROP COLUMN DeliveryDateKey;

-- checking --
SELECT *
FROM fact_delivery_orders;

-- Changing "OnTime" data type from TEXT to BOOLEAN
-- Temporarily disabling Safe Update Mode
SET SQL_SAFE_UPDATES = 0;

UPDATE fact_delivery_orders
SET OnTime = CASE
    WHEN UPPER(TRIM(OnTime)) = 'TRUE' THEN '1'
    WHEN UPPER(TRIM(OnTime)) = 'FALSE' THEN '0'
END;

ALTER TABLE fact_delivery_orders
MODIFY COLUMN OnTime BOOLEAN;

-- re-enable Safe Update Mode --
SET SQL_SAFE_UPDATES = 1;

-- checking --
SELECT *
FROM fact_delivery_orders;

-- now the OnTime column is set to BOOLEAN but I want to view as 'True/False' instead '0/1'--
SELECT
    CASE
        WHEN OnTime = 1 THEN 'True'
        ELSE 'False'
    END AS OnTime
FROM fact_delivery_orders;
-- But this is no permanent--

-- checking for missing values--
SELECT COUNT(OrderID), COUNT(ActualHours), COUNT(DeliveryStatus)
FROM fact_delivery_orders;
-- Nice missing values 

-- Checking for duplicates ---
SELECT
    OrderID,
    COUNT(*) AS occurrence
FROM fact_delivery_orders
GROUP BY OrderID
HAVING COUNT(*) > 1
ORDER BY occurrence DESC;
-- Nice no duplicate information

SELECT
    OrderID,
    ActualHours,
    Delivery_Date,
    COUNT(*) AS duplicate_count
FROM fact_delivery_orders
GROUP BY
    OrderID,
    ActualHours,
    Delivery_Date
HAVING COUNT(*) > 1;
-- Nice no duplicate information

-- duplicating this table before calculation
CREATE TABLE fact_delivery_orders_copy AS
SELECT *
FROM fact_delivery_orders;

-- Creating calculation columns/fields--
-- (Distance_Variance_Km, Time_variance, Cost_variance, Fuel_efficiency and Cost_per_km)
-- checking --
SELECT *
FROM fact_delivery_orders;

-- DATA TRANSFORMATION --
-- CALCULATION FIELDS --
-- Adding new column to fact_delivery_orders table --
ALTER TABLE fact_delivery_orders
ADD COLUMN Total_cost DECIMAL(10,2),
ADD COLUMN Distance_Variance_Km DECIMAL(10,2),
ADD COLUMN Time_variance DECIMAL(10,2),
ADD COLUMN Cost_variance DECIMAL(10,2),
ADD COLUMN Fuel_efficiency DECIMAL(10,2),
ADD COLUMN Cost_per_km DECIMAL(10,2)
;

-- Populating the new columns--
-- Temporarily disabling Safe Update Mode
SET SQL_SAFE_UPDATES = 0;

UPDATE fact_delivery_orders
SET
Total_cost = FuelCostSAR + DriverCostSAR + OtherCostSAR,
Distance_Variance_Km =   ActualDistanceKm - PlannedDistanceKm,
Time_variance = ActualHours - PlannedHours,
Cost_variance = FuelCostSAR + DriverCostSAR + OtherCostSAR - PlannedCostSAR,

 -- Fuel efficiency
Fuel_efficiency   =
        CASE
            WHEN ActualDistanceKm > 0
            THEN FuelLitres / ActualDistanceKm
            ELSE NULL
        END,

    -- Cost per kilometre
Cost_per_km =
        CASE
            WHEN ActualDistanceKm > 0
            THEN (
                FuelCostSAR +
                DriverCostSAR +
                OtherCostSAR
            ) / ActualDistanceKm
            ELSE NULL
        END;

-- re-enable Safe Update Mode --
SET SQL_SAFE_UPDATES = 1;

-- I got some warning with the calculated fields...let's check--
-- EDA --
DESCRIBE fact_delivery_orders;

SELECT
    MIN(Distance_Variance_Km),
    MAX(Distance_Variance_Km),
    MIN(Time_variance),
    MAX(Time_variance),
    MIN(Cost_variance),
    MAX(Cost_variance),
    MIN(Fuel_efficiency),
    MAX(Fuel_efficiency),
    MIN(Cost_per_km),
    MAX(Cost_per_km),
    MIN(Total_cost),
    MAX(Total_cost)
FROM fact_delivery_orders;
-- all seems good and fall within limit--

-- checking the updated table --
SELECT *
FROM fact_delivery_orders;

-- checking rows with NULL--
SELECT *
FROM fact_delivery_orders
WHERE VehicleID IS NULL
   OR Units IS NULL
   OR Total_cost IS NULL
   OR TimeWindow IS NULL
   OR Time_variance IS NULL
   OR RouteID IS NULL
   OR Promised_Date IS NULL
   OR PlannedHours IS NULL
   OR PlannedDistanceKm IS NULL
   OR PlannedCostSAR IS NULL
   OR OtherCostSAR IS NULL
   OR OrderID IS NULL
   OR OnTime IS NULL
   OR LoadKg IS NULL
   OR FuelLitres IS NULL
   OR FuelCostSAR IS NULL
   OR Fuel_efficiency IS NULL
   OR DriverID IS NULL
   OR DriverCostSAR IS NULL
   OR Distance_Variance_Km IS NULL
   OR Dispatch_Date IS NULL
   OR DepotID IS NULL;
   
 -- checking for empty space in 'TimeWindow' 
SELECT *
FROM fact_delivery_orders
WHERE TimeWindow = '';

-- checking for 0's in varaiables
SELECT *
FROM fact_delivery_orders
WHERE FuelLitres = 0
   OR FuelCostSAR = 0
   OR PlannedHours = 0
   OR PlannedDistanceKm = 0
   OR PlannedCostSAR = 0;

-- Investigating the reliability of the OnTime field
-- All order that was flagged as late
SELECT 
	COUNT(*) AS Total_Orders_Flag_late
FROM fact_delivery_orders
WHERE OnTime = 0;
-- Total of order flagged as late were (8782)

-- Breakdown of those flagged late --
SELECT
    COUNT(*) AS Total_Delivered_Orders,
    SUM(
        CASE
            WHEN Delivery_Date <= Promised_Date THEN 1
            ELSE 0
        END
    ) AS Delivered_By_Promised_Date,

    SUM(
        CASE
            WHEN Delivery_Date > Promised_Date THEN 1
            ELSE 0
        END
    ) AS Delivered_After_Promised_Date,

    SUM(
        CASE
            WHEN OnTime = 1
            AND Delivery_Date > Promised_Date THEN 1
            ELSE 0
        END
    ) AS OnTime_Flag_But_LateDate,

    SUM(
        CASE
            WHEN OnTime = 0
            AND Delivery_Date <= Promised_Date THEN 1
            ELSE 0
        END
    ) AS Late_Flag_But_OnTimeDate

FROM fact_delivery_orders
WHERE DeliveryStatus = 'Delivered';
-- some were delivered within the promised date (8483) while others were delivered after promised date (299)

-- First investigation: Break down for those delivered within the promised date by TimeWindow --
SELECT
    TimeWindow,
    COUNT(*) AS Total_Mismatches,
    SUM(CASE
        WHEN OnTime = 0 THEN 1
        ELSE 0
    END) AS Flagged_As_Late,
    ROUND(AVG(DelayHours), 2) AS Average_Delay_Hours,
    ROUND(MAX(DelayHours), 2) AS Maximum_Delay_Hours

FROM fact_delivery_orders
WHERE DeliveryStatus = 'Delivered'
    AND OnTime = 0
    AND Delivery_Date <= Promised_Date
GROUP BY TimeWindow
ORDER BY Total_Mismatches DESC;
-- this query result shows 'false' in OnTime field for those delivered within the promised date only

-- Second investigation: Those flagged late and were delivered after the promised date
-- 1. Checking those that were delivered after the promised date
SELECT
    OrderID, RouteID, DriverID, TimeWindow, Promised_Date, Delivery_Date, 
    OnTime, DelayHours, PlannedHours, ActualHours,
    CASE
        WHEN OnTime = 1 THEN 'True'
        WHEN OnTime = 0 THEN 'False'
        ELSE 'Unknown'
    END AS OnTime_Status

FROM fact_delivery_orders
WHERE DeliveryStatus = 'Delivered'
    AND Delivery_Date > Promised_Date
ORDER BY Delivery_Date DESC;

-- 2. Let's check if they were flagged according as late - OnTime: 'False'
SELECT
    COUNT(*) AS Total_Delivered_After_Promised_Date,
    SUM(CASE
        WHEN OnTime = 1 THEN 1
        ELSE 0
    END) AS Flagged_As_OnTime,

    SUM(CASE
        WHEN OnTime = 0 THEN 1
        ELSE 0
    END) AS Flagged_As_Late,

    SUM(CASE
        WHEN OnTime IS NULL THEN 1
        ELSE 0
    END) AS Missing_OnTime_Flag

FROM fact_delivery_orders
WHERE DeliveryStatus = 'Delivered'
    AND Delivery_Date > Promised_Date;
-- Nice!...all were correct

-- Let's check number of delivery...numnber of delivered order--
SELECT DeliveryStatus,
COUNT(*) AS total
FROM fact_delivery_orders
GROUP BY DeliveryStatus;
-- All was delivered

-- ANALYSIS-- 
-- 1. Monthly on-time delivery performance
-- Objective:To identifies monthly trends and helps establish whether 
-- delivery reliability is improving or deteriorating

CREATE TABLE monthly_onTime_delivery_analysis AS
SELECT
    DATE_FORMAT(Dispatch_Date, '%Y-%m-01') AS Delivery_Month,
    COUNT(*) AS Total_Orders,
    SUM(
        CASE
            WHEN DeliveryStatus = 'Delivered' THEN 1
            ELSE 0
        END
    ) AS Completed_Orders,

    SUM(
        CASE
            WHEN DeliveryStatus = 'Delivered'
            AND OnTime = 1 THEN 1
            ELSE 0
        END
    ) AS OnTime_Orders,

    SUM(
        CASE
            WHEN DeliveryStatus = 'Delivered'
            AND OnTime = 0 THEN 1
            ELSE 0
        END
    ) AS Late_Orders,

    CASE
        WHEN SUM(
            CASE
                WHEN DeliveryStatus = 'Delivered'
                AND OnTime = 1 THEN 1
                ELSE 0
            END
        ) > 0 THEN 'True'
        ELSE 'False'
    END AS OnTime_Status,

    ROUND(
        SUM(
            CASE
                WHEN DeliveryStatus = 'Delivered'
                AND OnTime = 1 THEN 1
                ELSE 0
            END
        ) * 100.0
        /
        NULLIF(
            SUM(
                CASE
                    WHEN DeliveryStatus = 'Delivered' THEN 1
                    ELSE 0
                END
            ), 0
        ),
        2
    ) AS OnTime_Rate

FROM fact_delivery_orders
GROUP BY DATE_FORMAT(Dispatch_Date, '%Y-%m-01')
ORDER BY Delivery_Month;

-- Average delay by month --
-- shows the month with highest delay
CREATE TABLE monthly_delay_order AS
SELECT
    DATE_FORMAT(Dispatch_Date, '%Y-%m-01') AS Delivery_Month,
    COUNT(*) AS Total_Orders,
    ROUND(AVG(DelayHours),2) AS Average_Delay_Hours,
    ROUND(MAX(DelayHours),2) AS Maximum_Delay_Hours,
    ROUND(SUM(DelayHours),2) AS Total_Delay_Hours

FROM fact_delivery_orders
WHERE DeliveryStatus = 'Delivered'
GROUP BY DATE_FORMAT(Dispatch_Date, '%Y-%m-01')
ORDER BY Delivery_Month;

-- 2. Route efficiency
-- Objective: To evaluate how efficiently each delivery route is performing in 
-- terms of distance, time and delivery reliability. 
-- Route analysis identify inefficient routes, excessive travelling distances 
-- and opportunities to improve delivery scheduling.alter

-- Number of route
SELECT
	COUNT(DISTINCT RouteID) AS total_route
FROM fact_delivery_orders;
-- a. 
CREATE TABLE route_efficiency AS
SELECT
    RouteID,
    COUNT(*) AS Total_Orders,
    ROUND(AVG(PlannedDistanceKm),2) AS Avg_Planned_Distance,
    ROUND(AVG(ActualDistanceKm),2) AS Avg_Actual_Distance,
    ROUND(AVG(Distance_Variance_Km),2) AS Avg_Distance_Variance,
    ROUND(AVG(PlannedHours),2) AS Avg_Planned_Hours,
    ROUND(AVG(ActualHours),2) AS Avg_Actual_Hours,
    ROUND(AVG(Time_variance),2) AS Avg_Time_Variance,
    ROUND(AVG(FuelLitres), 2) AS Avg_Fuel_Litres,
    ROUND(
        SUM(FuelLitres) / NULLIF(SUM(ActualDistanceKm), 0),
        2) AS Fuel_Litres_Per_Km,
    ROUND(
        SUM(
            CASE
                WHEN OnTime = 1 THEN 1
                ELSE 0
            END
        ) * 100.0 / NULLIF(COUNT(*), 0),
        2
    ) AS OnTimeRate

FROM fact_delivery_orders
WHERE DeliveryStatus = 'Delivered'
GROUP BY RouteID
ORDER BY Avg_Distance_Variance DESC;

-- routes with the highest distance overruns (highest distance variance)---
CREATE TABLE route_overruns AS
SELECT
    RouteID,
    COUNT(*) AS TotalDeliveries,
    ROUND(SUM(PlannedDistanceKm), 2) AS Total_Planned_Km,
    ROUND(SUM(ActualDistanceKm), 2) AS Total_Actual_Km,
    ROUND(SUM(Distance_Variance_Km), 2) AS Total_Extra_Km,
    ROUND(
        SUM(Distance_Variance_Km)
        / NULLIF(SUM(PlannedDistanceKm), 0) * 100,
        2
    ) AS Distance_Overrun_Percentage

FROM fact_delivery_orders
WHERE DeliveryStatus = 'Delivered'
GROUP BY RouteID
HAVING SUM(PlannedDistanceKm) > 0
ORDER BY Distance_Overrun_Percentage DESC;

-- checking --
SELECT *
FROM route_overruns;

-- route with highest fuel consumption--
SELECT 
	RouteID, Total_Orders, Avg_Actual_Distance, Avg_Fuel_Litres, Fuel_Litres_Per_Km
FROM route_efficiency 
ORDER BY Fuel_Litres_Per_Km DESC;

-- operational performance by route --
SELECT
    RouteID, Total_Orders, Avg_Actual_Hours, OnTimeRate,
    RANK() OVER (
        ORDER BY OnTimeRate DESC
    ) AS Route_Rank

FROM route_efficiency
ORDER BY Route_Rank;
-- I found that OnTimeRate for route 3 is 0, 
-- could it be that it has never be any early delivery there?, let's find out
-- Checking OnTime_Status for each order on Route 3

SELECT
    OrderID,
    RouteID,
    CASE
        WHEN DeliveryStatus = 'Delivered'
             AND OnTime = 1 THEN 'True'
        ELSE 'False'
    END AS OnTime_Status

FROM fact_delivery_orders
WHERE RouteID = 3
ORDER BY OrderID;

-- Let's make this easier by checking Route 3 with OnTime is 'True' and DeliveryStatus 'Delivered'
SELECT OrderID, RouteID,DeliveryStatus,OnTime
FROM fact_delivery_orders
WHERE RouteID = 3
AND DeliveryStatus = 'Delivered'
AND OnTime = 1;
-- Clarified Route 3 never meet up with delivery time

-- Analysis 3: Vehicle utilization--
-- Objective: To understand how effectively the available delivery vehicles are being utilized.
-- Number of vehicle
SELECT
	COUNT(DISTINCT VehicleID) AS total_vehicle
FROM fact_delivery_orders;
    
-- vehicle utilization indicators
CREATE TABLE vehicle_indicator AS
SELECT 
    VehicleID,
    COUNT(*) AS Total_Deliveries,
    ROUND(SUM(LoadKg), 2) AS Total_LoadKg,
    ROUND(AVG(LoadKg), 2) AS Average_LoadKg,
    ROUND(SUM(ActualDistanceKm), 2) AS Total_DistanceKm,
    ROUND(AVG(ActualDistanceKm), 2) AS Average_DistanceKm,
    ROUND(SUM(FuelLitres), 2) AS Total_Fuel_Litres,
    ROUND(AVG(FuelLitres), 2) AS Average_Fuel_Litres,
    ROUND(SUM(DeliveredUnits), 2) AS Total_Units_Delivered,
    ROUND(SUM(Total_cost), 2) AS Total_Vehicle_Cost,
    ROUND(
        SUM(FuelLitres) / NULLIF(SUM(ActualDistanceKm), 0),
        2) AS Fuel_Litres_Per_Km,
    ROUND(
        SUM(DeliveredUnits) / NULLIF(COUNT(*), 0),
        2) AS Units_Per_Delivery,
    ROUND(
        SUM(ActualDistanceKm) / NULLIF(COUNT(*), 0),
        2) AS Km_Per_Delivery,
    ROUND(
        SUM(ActualHours) / NULLIF(COUNT(*), 0),
        2) AS Hours_Per_Delivery

FROM fact_delivery_orders
WHERE DeliveryStatus = 'Delivered'
GROUP BY VehicleID
ORDER BY Total_LoadKg DESC;
-- checking
SELECT *
FROM vehicle_indicator;

 -- vehicles with high fuel consumption
 SELECT 
 VehicleID, Total_Deliveries, Average_Fuel_Litres, Average_DistanceKm, Fuel_Litres_Per_Km
 FROM vehicle_indicator
 ORDER BY Fuel_Litres_Per_Km DESC;
 
 -- delivery productivity per vehicle
 SELECT 
 VehicleID,Total_Deliveries, Units_Per_Delivery, Km_Per_Delivery, Hours_Per_Delivery
 FROM vehicle_indicator
 ORDER BY Units_Per_Delivery DESC;
 
 -- vehicle with highest speed...those that deliver early with lowest hour
 SELECT 
 VehicleID,Total_Deliveries, Units_Per_Delivery, Km_Per_Delivery, Hours_Per_Delivery
 FROM vehicle_indicator
 ORDER BY Hours_Per_Delivery ASC;
 
 -- 4. Delivery Cost Analysis --
 -- Total Delivery Costs --
 
SELECT
    ROUND(SUM(PlannedCostSAR), 2) AS Total_Planned_Cost,
    ROUND(SUM(FuelCostSAR), 2) AS Total_Fuel_Cost,
    ROUND(SUM(DriverCostSAR), 2) AS Total_Driver_Cost,
    ROUND(SUM(OtherCostSAR), 2) AS Total_Other_Cost,
    ROUND(SUM(Total_cost), 2) AS Total_Actual_Cost,
    ROUND(SUM(Cost_variance),2) AS Total_Cost_Variance,
	ROUND(
        SUM(FuelCostSAR) / NULLIF(SUM(Total_cost), 0) * 100,
        2) AS Fuel_Cost_Percentage,
    ROUND(
        SUM(DriverCostSAR) / NULLIF(SUM(Total_cost), 0) * 100,
        2) AS Driver_Cost_Percentage,
    ROUND(
        SUM(OtherCostSAR) / NULLIF(SUM(Total_cost), 0) * 100,
        2) AS Other_Cost_Percentage,
    ROUND(
        SUM(Total_cost) / NULLIF(SUM(DeliveredUnits), 0),
        2) AS Cost_Per_Delivered_Unit,
    ROUND(
        SUM(Total_cost) / NULLIF(SUM(ActualDistanceKm), 0),
        2) AS Cost_Per_Km
        
FROM fact_delivery_orders
WHERE DeliveryStatus = 'Delivered';

-- Cost Variance by Route --
CREATE TABLE route_cost_analysis AS
SELECT
    RouteID,
    COUNT(*) AS Total_Deliveries,
    ROUND(SUM(PlannedCostSAR), 2) AS Planned_Cost,
    ROUND(SUM(Total_cost), 2) AS Actual_Cost,
    ROUND(SUM(Cost_variance), 2) AS Cost_Variance,
    ROUND(
        SUM(Cost_variance)
        / NULLIF(SUM(PlannedCostSAR), 0) * 100,
        2) AS Cost_Overrun_Percentage

FROM fact_delivery_orders
WHERE DeliveryStatus = 'Delivered'
GROUP BY RouteID
ORDER BY Cost_Overrun_Percentage DESC;

-- checking
SELECT *
FROM route_cost_analysis;

-- Route 3 is the most expensive with highest Cost_Overrun_Percentage
-- it is expected because delivery to route 3 has been always late with high Distance_Overrun_Percentage
-- Route 12 also has high Distance_Overrun_Percentage and has second Cost_Overrun_Percentage
-- confirm the result below
SELECT
	RouteID, Total_Extra_Km, Distance_Overrun_Percentage
FROM route_overruns
ORDER BY Distance_Overrun_Percentage DESC;

-- Finally, Let's check the most expensive deliveries --
SELECT
    OrderID, RouteID, DepotID, VehicleID, DriverID,
	ActualDistanceKm,FuelLitres,
	FuelCostSAR,DriverCostSAR,OtherCostSAR,
    Total_cost, PlannedCostSAR, Cost_Variance

FROM fact_delivery_orders
WHERE DeliveryStatus = 'Delivered'
ORDER BY Total_cost DESC
LIMIT 50;

