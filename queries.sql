
-- =====================================================
-- 1) READ / DASHBOARD QUERIES
-- =====================================================

PRAGMA foreign_keys = ON;
-- 1.1 Approved clients

SELECT id, name, surname, email, status, credit_score, created_at
FROM client
WHERE status = 'approved'
ORDER BY created_at DESC
LIMIT :limit OFFSET :offset;

-- 1.2 Search clients by name/surname/email (LIKE)

SELECT id, name, surname, email, status, credit_score
FROM client
WHERE status = 'approved'
  AND (name LIKE :q OR surname LIKE :q OR email LIKE :q)
ORDER BY credit_score DESC, created_at DESC
LIMIT :limit OFFSET :offset;

-- 1.3 Clients with unpaid loans

SELECT
  c.id AS client_id,
  c.name || ' ' || c.surname AS full_name,
  l.id AS loan_id,
  l.amount_cents,
  l.interest_bps,
  l.start_date,
  l.end_date,
  l.paid
FROM loan l
JOIN client c ON c.id = l.client_id
WHERE l.paid = 0
ORDER BY l.end_date ASC;

-- 1.4 Overdue loans

SELECT
  c.id AS client_id,
  c.name || ' ' || c.surname AS full_name,
  l.id AS loan_id,
  l.amount_cents,
  l.end_date,
  CAST(julianday('now') - julianday(l.end_date) AS INTEGER) AS days_overdue
FROM loan l
JOIN client c ON c.id = l.client_id
WHERE l.paid = 0 AND l.end_date IS NOT NULL AND date(l.end_date) < date('now')
ORDER BY days_overdue DESC;

-- 1.5 User portfolio (prebuilt view)

SELECT * FROM v_user_portfolio
ORDER BY invested_cents DESC;

-- 1.6 Open orders for a user

SELECT id, ticker, volume, total_amount_cents, created_at
FROM investing
WHERE user_id = :user_id AND order_status = 'open'
ORDER BY created_at DESC;

-- 1.7 Portfolio breakdown by ticker for a user

SELECT
  ticker,
  SUM(total_amount_cents) AS invested_cents
FROM investing
WHERE user_id = :user_id
GROUP BY ticker
ORDER BY invested_cents DESC;

-- 1.8 Daily invested amount for a user

SELECT
  date(created_at) AS day,
  SUM(total_amount_cents) AS invested_cents
FROM investing
WHERE user_id = :user_id
  AND date(created_at) >= date('now', printf('-%d days', :days_back))
GROUP BY day
ORDER BY day ASC;

-- 1.9 Top-N clients by total loan amount

SELECT
  c.id AS client_id,
  c.name || ' ' || c.surname AS full_name,
  SUM(l.amount_cents) AS total_loan_cents
FROM client c
JOIN loan l ON l.client_id = c.id
GROUP BY c.id
ORDER BY total_loan_cents DESC
LIMIT :limit OFFSET :offset;

-- 1.10 Loan KPIs: outstanding total, number of clients unpaid, average interest in bps.
SELECT
  IFNULL(SUM(CASE WHEN paid = 0 THEN amount_cents END), 0) AS outstanding_loan_cents,
  COUNT(DISTINCT CASE WHEN paid = 0 THEN client_id END)    AS num_clients_unpaid,
  ROUND(AVG(interest_bps), 2)                               AS avg_interest_bps
FROM loan;

-- 1.11 Users and number of linked clients
SELECT
  u.id AS user_id,
  u.username,
  COUNT(uc.client_id) AS num_clients
FROM users u
LEFT JOIN user_client uc ON uc.user_id = u.id
GROUP BY u.id, u.username
ORDER BY num_clients DESC;

-- =====================================================
-- 2) WRITE / MAINTENANCE QUERIES
-- =====================================================

BEGIN TRANSACTION;

INSERT INTO client (name, surname, title, email, status, loan_amount_cents, credit_amount_cents, risk_appetite, market_timing, credit_score, profit_target_cents, cutloss_cents)
VALUES
('Benjamas','Siriwat',    'MS',  'benjamas.s@example.com',  'pending',      0,        5000000,  5, 4, 650,  800000, 200000),
('Anan',    'Kittipong',  'MR',  'anan.k@example.com',      'approved',     25000000, 10000000, 7, 6, 720, 1500000, 300000),
('Chai',    'Rattanakorn','MR',  'chai.r@example.com',      'approved',     50000000, 15000000, 8, 7, 760, 2500000, 400000),
('Duangjai','Prasert',    'MRS', 'duangjai.p@example.com',  'approved',     12000000, 7000000,  6, 6, 710, 1200000, 300000),
('Eakkachai','Boonsong',  'MR',  'eakkachai.b@example.com', 'disapproved',  NULL,     2000000,  3, 3, 520,  300000, 100000),
('Fah',     'Nimman',     'MS',  'fah.n@example.com',       'approved',     8000000,  3000000,  6, 5, 690, 1000000, 200000),
('Gawin',   'Somsak',     'MR',  'gawin.s@example.com',     'pending',      6000000,  0,        4, 5, 610,  700000, 150000),
('Hathai',  'Suksan',     'MS',  'hathai.s@example.com',    'approved',     30000000, 12000000, 7, 7, 740, 2000000, 350000),
('Itthipol','Chaowalit',  'MR',  'itthipol.c@example.com',  'approved',     NULL,     9000000,  5, 6, 700, 1100000, 250000),
('Jintana', 'Phrom',      'MS',  'jintana.p@example.com',   'disapproved',  0,        0,        2, 2, 480,  200000,  50000),
('Krit',    'Thammarat',  'MR',  'krit.t@example.com',      'approved',     45000000, 13000000, 8, 8, 780, 3000000, 500000),
('Lalida',  'Chaiyatham', 'MS',  'lalida.c@example.com',    'pending',      10000000, 4000000,  5, 4, 640,  900000, 200000),
('Montri',  'Kongthai',   'MR',  'montri.k@example.com',    'approved',     16000000, 6000000,  6, 6, 705, 1300000, 250000),
('Nattaporn','Saelee',    'MS',  'nattaporn.s@example.com', 'approved',     NULL,     3000000,  5, 5, 695,  950000, 220000),
('Orawan',  'Ying',       'MRS', 'orawan.y@example.com',    'approved',     9000000,  5000000,  6, 5, 715, 1150000, 230000);

COMMIT;
-- 2.1 Link a client to a user (idempotent)
-- Params: :user_id, :client_id
INSERT OR IGNORE INTO user_client (user_id, client_id) VALUES (:user_id, :client_id);

-- 2.2 Insert a new open order (investing)
-- Params: :user_id, :ticker, :volume, :total_amount_cents
INSERT INTO investing (user_id, ticker, order_status, volume, total_amount_cents, correctness)
VALUES (:user_id, :ticker, 'open', :volume, :total_amount_cents, 1.0);

-- 2.3 Close an order
-- Params: :investing_id
UPDATE investing
SET order_status = 'closed'
WHERE id = :investing_id;

-- 2.4 Insert a transaction summary row
-- Params: :user_id, :investing_id, :cash_cents, :buy_cents, :sell_cents
INSERT INTO transaction_invest (user_id, investing_id, total_cash_cents, total_buy_cents, total_sell_cents)
VALUES (:user_id, :investing_id, :cash_cents, :buy_cents, :sell_cents);

-- 2.5 Adjust a user's cash balance (delta)
-- Params: :delta_cents, :user_id
UPDATE users
SET cash_cents = cash_cents + :delta_cents
WHERE id = :user_id;

-- 2.6 Mark a loan as paid
-- Params: :loan_id
UPDATE loan
SET paid = 1
WHERE id = :loan_id;

-- 2.7 Update client email/status (safe example)
-- Params: :email, :status, :client_id
UPDATE client
SET email  = :email,
    status = :status
WHERE id = :client_id;



-- =====================================================
-- 3) DATA QUALITY / VALIDATION QUERIES
-- =====================================================

-- 3.1 Orphan references: investing.user_id without matching users.id
SELECT i.id, i.user_id
FROM investing i
LEFT JOIN users u ON u.id = i.user_id
WHERE u.id IS NULL;

-- 3.2 Orphan references: loan.client_id without matching client.id
SELECT l.id, l.client_id
FROM loan l
LEFT JOIN client c ON c.id = l.client_id
WHERE c.id IS NULL;

-- 3.3 Duplicate client emails (should not happen due to UNIQUE, but validate)
SELECT email, COUNT(*) AS n
FROM client
GROUP BY email
HAVING COUNT(*) > 1;

-- 3.4 Invalid loan dates (end_date < start_date)
SELECT id, client_id, start_date, end_date
FROM loan
WHERE end_date IS NOT NULL
  AND start_date IS NOT NULL
  AND date(end_date) < date(start_date);

-- =====================================================
-- 4) EXPLAIN / TUNING
-- =====================================================
-- Use EXPLAIN QUERY PLAN to check index usage, e.g.:
-- EXPLAIN QUERY PLAN
-- SELECT id, name, surname FROM client WHERE status='approved' ORDER BY created_at DESC;


DROP VIEW  IF EXISTS v_user_portfolio;
DROP VIEW  IF EXISTS v_client_overview;
DROP TABLE IF EXISTS transaction_invest;
DROP TABLE IF EXISTS investing;
DROP TABLE IF EXISTS user_client;
DROP TABLE IF EXISTS loan;
DROP TABLE IF EXISTS client;
DROP TABLE IF EXISTS users;
PRAGMA foreign_keys = ON;

-- =====================================================
-- 5) JOIN ... ON (INNER JOIN): users ↔ user_client ↔ client
-- =====================================================
-- Return all user-client links (only pairs that exist)
SELECT
  u.id   AS user_id,
  u.username,
  c.id   AS client_id,
  c.name || ' ' || c.surname AS client_full_name,
  c.status
FROM users u
JOIN user_client uc ON uc.user_id = u.id
JOIN client c       ON c.id = uc.client_id
ORDER BY u.username, client_full_name;

-- =====================================================
-- 6) LEFT OUTER JOIN: list all users and their client (if any)
-- =====================================================
-- Users without clients will show NULL in client columns
SELECT
  u.id   AS user_id,
  u.username,
  c.id   AS client_id,
  c.name || ' ' || c.surname AS client_full_name
FROM users u
LEFT JOIN user_client uc ON uc.user_id = u.id
LEFT JOIN client c       ON c.id = uc.client_id
ORDER BY u.username, client_full_name;

-- =====================================================
-- 7) FULL OUTER JOIN (emulation for SQLite)
-- =====================================================
--   A) left side with LEFT JOIN
--   B) right side "anti-join" (rows in client not linked to any user)

WITH left_side AS (
  SELECT
    u.id   AS user_id,
    u.username,
    c.id   AS client_id,
    c.name || ' ' || c.surname AS client_full_name,
    'LEFT' AS source
  FROM users u
  LEFT JOIN user_client uc ON uc.user_id = u.id
  LEFT JOIN client c       ON c.id = uc.client_id
),
right_only AS (
  SELECT
    NULL  AS user_id,
    NULL  AS username,
    c.id  AS client_id,
    c.name || ' ' || c.surname AS client_full_name,
    'RIGHT_ONLY' AS source
  FROM client c
  WHERE NOT EXISTS (
    SELECT 1
    FROM user_client uc
    WHERE uc.client_id = c.id
  )
)
SELECT * FROM left_side
UNION ALL
SELECT * FROM right_only
ORDER BY username IS NULL, username, client_full_name;

-- =====================================================
-- 8) MERGE-like UPSERT (link a client to a user)
-- =====================================================
-- SQLite supports ON CONFLICT. This creates/keeps the link idempotently.
-- Params: :user_id, :client_id
INSERT INTO user_client (user_id, client_id)
VALUES (:user_id, :client_id)
ON CONFLICT(user_id, client_id) DO NOTHING;

-- =====================================================
-- 9) DELETE FROM with JOIN condition (use EXISTS in SQLite)
-- =====================================================
-- Example: delete clients that are 'disapproved' AND have no loans
DELETE FROM client AS c
WHERE c.status = 'disapproved'
  AND NOT EXISTS (SELECT 1 FROM loan l WHERE l.client_id = c.id);

-- Another example: remove a user-client link for a specific pair
-- Params: :user_id, :client_id
DELETE FROM user_client
WHERE user_id = :user_id AND client_id = :client_id;

-- =====================================================
-- 10) WITH ... AS ... (CTE) for readable pipelines
-- =====================================================
-- Example: pre-filter approved clients then join to users and rank
WITH approved_clients AS (
  SELECT id, name, surname, email, credit_score
  FROM client
  WHERE status = 'approved'
),
linked AS (
  SELECT
    u.id AS user_id,
    u.username,
    ac.id AS client_id,
    ac.name || ' ' || ac.surname AS client_full_name,
    ac.credit_score
  FROM users u
  JOIN user_client uc ON uc.user_id = u.id
  JOIN approved_clients ac ON ac.id = uc.client_id
)
SELECT *
FROM linked
ORDER BY credit_score DESC, username;

-- =====================================================
-- 11) COUNTIF emulation (conditional counts) + HAVING COUNT
-- =====================================================
-- Count approved/pending/disapproved clients per user
-- HAVING: keep users who have at least :min_clients clients linked
-- Params: :min_clients
SELECT
  u.id AS user_id,
  u.username,
  COUNT(uc.client_id) AS total_clients,
  SUM(CASE WHEN c.status='approved'     THEN 1 ELSE 0 END) AS approved_clients,
  SUM(CASE WHEN c.status='pending'      THEN 1 ELSE 0 END) AS pending_clients,
  SUM(CASE WHEN c.status='disapproved'  THEN 1 ELSE 0 END) AS disapproved_clients
FROM users u
LEFT JOIN user_client uc ON uc.user_id = u.id
LEFT JOIN client c       ON c.id = uc.client_id
GROUP BY u.id, u.username
HAVING COUNT(uc.client_id) >= :min_clients
ORDER BY total_clients DESC, u.username;

-- =====================================================
-- 12) LIMIT and OR filters
-- =====================================================
-- Search clients by name or email
-- Params: :q (e.g., '%term%')
SELECT id, name, surname, email, status, credit_score
FROM client
WHERE status = 'approved'
  AND (name LIKE :q OR surname LIKE :q OR email LIKE :q)
ORDER BY credit_score DESC, created_at DESC
LIMIT :limit OFFSET :offset;

-- =====================================================
-- 13) IF / CASE expressions
-- =====================================================
-- SQLite has IIF(expr, true_val, false_val) in modern versions, but CASE is portable.
-- Classify credit_score into risk tiers
SELECT
  id,
  name || ' ' || surname AS full_name,
  credit_score,
  CASE
    WHEN credit_score >= 760 THEN 'Prime+'
    WHEN credit_score >= 700 THEN 'Prime'
    WHEN credit_score >= 640 THEN 'Near-Prime'
    ELSE 'Subprime'
  END AS risk_tier
FROM client
ORDER BY credit_score DESC, full_name;

-- Conditional flag (IF-like) using CASE
-- Flag clients who are approved OR have loan_amount_cents >= 10,000,000
SELECT
  id,
  email,
  status,
  IFNULL(loan_amount_cents, 0) AS loan_amount_cents,
  CASE
    WHEN status='approved' OR IFNULL(loan_amount_cents,0) >= 10000000
    THEN 1 ELSE 0
  END AS is_priority
FROM client
ORDER BY is_priority DESC, created_at DESC;

-- =====================================================
-- 14) DROP TABLE (cleanup patterns)
-- =====================================================
-- Safe drop of a temporary or staging table (if exists)
DROP TABLE IF EXISTS staging_client_import;

-- Example: rebuild a staging table
CREATE TABLE staging_client_import (
  email TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  surname TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('approved','pending','disapproved'))
);

-- Merge staging into client via UPSERT (simulate MERGE)
-- Note: For updates on conflict, use DO UPDATE; here we only insert new emails
INSERT INTO client (name, surname, email, status)
SELECT sci.name, sci.surname, sci.email, sci.status
FROM staging_client_import sci
ON CONFLICT(email) DO UPDATE SET
  name    = excluded.name,
  surname = excluded.surname,
  status  = excluded.status;

-- End of file
