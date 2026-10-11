USE OlistProject;
GO

-- ===================================================
-- SECTION 1: Exploratory Data Analysis (EDA) & Data Checks
-- ===================================================

-- 1.1 Top categories by revenue
SELECT TOP 10
    t.product_category_name_english AS category,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    ROUND(SUM(oi.price / 100.0), 2) AS total_revenue,
    ROUND(AVG(oi.price / 100.0), 2) AS avg_product_price
FROM olist_order_items_dataset oi
JOIN olist_products_dataset p 
    ON oi.product_id = p.product_id
JOIN product_category_name_translation t 
    ON p.product_category_name = t.product_category_name
JOIN olist_orders_dataset o
    ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY t.product_category_name_english
ORDER BY total_revenue DESC;


-- 1.2 Delivery performance & delay metrics
SELECT 
    COUNT(*) AS total_delivered_orders,
    AVG(DATEDIFF(day, order_purchase_timestamp, order_delivered_customer_date)) AS avg_delivery_time_days,
    AVG(DATEDIFF(day, order_delivered_customer_date, order_estimated_delivery_date)) AS avg_days_early,
    SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1 ELSE 0 END) AS delayed_order_count,
    ROUND(100.0 * SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1 ELSE 0 END) / COUNT(*), 2) AS delay_rate_pct
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;


-- ===================================================
-- SECTION 2: Core Business Analysis & Customer Insights
-- ===================================================

-- 2.1 Geographic revenue breakdown (Top states)
WITH order_totals AS (
    SELECT o.order_id, c.customer_state,
           SUM(oi.price / 100.0) AS order_total
    FROM olist_orders_dataset o
    JOIN olist_customers_dataset c 
        ON o.customer_id = c.customer_id
    JOIN olist_order_items_dataset oi 
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id, c.customer_state
)
SELECT TOP 5
    customer_state AS state,
    COUNT(*) AS total_order_count,
    ROUND(SUM(order_total), 2) AS total_revenue,
    ROUND(AVG(order_total), 2) AS avg_basket_amount
FROM order_totals
GROUP BY customer_state
ORDER BY total_revenue DESC;


-- 2.2 Payment method breakdown
SELECT 
    payment_type,
    COUNT(DISTINCT order_id) AS total_order_count,
    ROUND(SUM(payment_value / 100.0), 2) AS total_payment_amount,
    ROUND(AVG(payment_value / 100.0), 2) AS avg_payment_amount,
    MAX(payment_installments) AS max_installments
FROM olist_order_payments_dataset
WHERE payment_type != 'not_defined'
GROUP BY payment_type
ORDER BY total_payment_amount DESC;


-- 2.3 Delivery status vs Satisfaction scores
WITH one_review_per_order AS (
    SELECT order_id, review_score,
           ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_creation_date DESC) AS rn
    FROM olist_order_reviews_dataset
)
SELECT
    CASE
        WHEN c.order_delivered_customer_date <= c.order_estimated_delivery_date
            THEN 'On-time / Early'
        WHEN c.order_delivered_customer_date > c.order_estimated_delivery_date
            THEN 'Delayed'
    END AS delivery_status,
    COUNT(DISTINCT c.order_id) AS order_count,
    ROUND(AVG(CAST(b.review_score AS DECIMAL(10,2))), 2) AS avg_customer_satisfaction
FROM olist_orders_dataset c
JOIN one_review_per_order b 
    ON c.order_id = b.order_id AND b.rn = 1
WHERE c.order_status = 'delivered'
  AND c.order_delivered_customer_date IS NOT NULL
  AND c.order_estimated_delivery_date IS NOT NULL
GROUP BY
    CASE
        WHEN c.order_delivered_customer_date <= c.order_estimated_delivery_date
            THEN 'On-time / Early'
        WHEN c.order_delivered_customer_date > c.order_estimated_delivery_date
            THEN 'Delayed'
    END
ORDER BY avg_customer_satisfaction DESC;


-- 2.4 Average spending by installment count
SELECT
    CASE
        WHEN payment_installments = 1 THEN '1 installment'
        WHEN payment_installments BETWEEN 2 AND 3 THEN '2-3 installments'
        WHEN payment_installments BETWEEN 4 AND 6 THEN '4-6 installments'
        WHEN payment_installments BETWEEN 7 AND 9 THEN '7-9 installments'
        WHEN payment_installments >= 10 THEN '10+ installments'
    END AS installment_group,
    COUNT(DISTINCT order_id) AS order_count,
    ROUND(AVG(CAST(payment_value / 100.0 AS DECIMAL(10,2))), 2) AS avg_payment_amount
FROM olist_order_payments_dataset
WHERE payment_type = 'credit_card'
  AND payment_installments >= 1
GROUP BY
    CASE
        WHEN payment_installments = 1 THEN '1 installment'
        WHEN payment_installments BETWEEN 2 AND 3 THEN '2-3 installments'
        WHEN payment_installments BETWEEN 4 AND 6 THEN '4-6 installments'
        WHEN payment_installments BETWEEN 7 AND 9 THEN '7-9 installments'
        WHEN payment_installments >= 10 THEN '10+ installments'
    END
ORDER BY MIN(payment_installments);


-- 2.5 Customer retention (One-time vs Repeat buyers)
SELECT
    CASE
        WHEN order_count = 1 THEN 'One-time customer'
        WHEN order_count >= 2 THEN 'Repeat customer'
    END AS customer_type,
    COUNT(*) AS customer_count
FROM
(
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS order_count
    FROM olist_orders_dataset o
    JOIN olist_customers_dataset c
        ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
) AS customer_orders
GROUP BY
    CASE
        WHEN order_count = 1 THEN 'One-time customer'
        WHEN order_count >= 2 THEN 'Repeat customer'
    END;


-- 2.6 Satisfaction score by product category
WITH order_category AS (
    SELECT DISTINCT oi.order_id, t.product_category_name_english AS category
    FROM olist_order_items_dataset oi
    JOIN olist_products_dataset p
        ON oi.product_id = p.product_id
    JOIN product_category_name_translation t
        ON p.product_category_name = t.product_category_name
    JOIN olist_orders_dataset o
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
),
one_review_per_order AS (
    SELECT order_id, review_score,
           ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_creation_date DESC) AS rn
    FROM olist_order_reviews_dataset
)
SELECT
    oc.category,
    COUNT(DISTINCT oc.order_id) AS order_count,
    ROUND(AVG(CAST(r.review_score AS DECIMAL(10,2))), 2) AS avg_satisfaction
FROM order_category oc
JOIN one_review_per_order r
    ON oc.order_id = r.order_id AND r.rn = 1
GROUP BY oc.category
ORDER BY avg_satisfaction DESC;