
PRAGMA foreign_keys = ON;
PRAGMA recursive_triggers = OFF;

-- ========== USERS TABLE ==========
-- USERS are for online payment
CREATE TABLE IF NOT EXISTS users (
  id                      INTEGER PRIMARY KEY,
  username                TEXT NOT NULL UNIQUE,
  password_hash           TEXT NOT NULL,
  cash_cents              INTEGER NOT NULL DEFAULT 0,
  holding_amount_cents    INTEGER NOT NULL DEFAULT 0,
  ticker_status           TEXT NOT NULL CHECK (ticker_status IN ('buy','hold','sell')),
  created_at              TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at              TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ========== CLIENTS TABLE ==========
CREATE TABLE IF NOT EXISTS client (
  id                      INTEGER PRIMARY KEY,
  name                    TEXT NOT NULL,
  surname                 TEXT NOT NULL,
  title                   TEXT CHECK (title IN ('MR','MS','MRS','NON')),
  email                   TEXT NOT NULL UNIQUE,
  status                  TEXT NOT NULL CHECK (status IN ('approved','pending','disapproved')),
  loan_amount_cents       INTEGER,
  credit_amount_cents     INTEGER,
  risk_appetite           INTEGER,
  market_timing           INTEGER,
  credit_score            INTEGER,
  profit_target_cents     INTEGER,
  cutloss_cents           INTEGER,
  created_at              TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at              TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ========== INVESTING TABLE ==========
CREATE TABLE IF NOT EXISTS investing (
  id                      INTEGER PRIMARY KEY,
  user_id                 INTEGER NOT NULL,
  ticker                  TEXT NOT NULL,
  order_status            TEXT NOT NULL CHECK (order_status IN ('open','pending','closed')),
  volume                  INTEGER NOT NULL CHECK (volume > 0),
  total_amount_cents      INTEGER NOT NULL CHECK (total_amount_cents >= 0),
  correctness             BOOLEAN NOT NULL CHECK (correctness BETWEEN 0.0 AND 1.0),
  created_at              TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at              TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ========== TRANSACTION SUMMARY TABLE ==========
CREATE TABLE IF NOT EXISTS transaction_invest (
  id                      INTEGER PRIMARY KEY,
  user_id                 INTEGER NOT NULL,
  investing_id            INTEGER NOT NULL,
  total_cash_cents        INTEGER NOT NULL DEFAULT 0,
  total_buy_cents         INTEGER NOT NULL DEFAULT 0,
  total_sell_cents        INTEGER NOT NULL DEFAULT 0,
  created_at              TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at              TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (investing_id) REFERENCES investing(id) ON DELETE CASCADE
);

-- ========== LOAN TABLE ==========
CREATE TABLE IF NOT EXISTS loan (
  id                      INTEGER PRIMARY KEY,
  client_id               INTEGER NOT NULL,
  amount_cents            INTEGER NOT NULL CHECK (amount_cents >= 0),
  interest_bps            INTEGER NOT NULL CHECK (interest_bps >= 0),
  start_date              TEXT,
  end_date                TEXT,
  loan_type               TEXT CHECK (loan_type IN ('personal','home')),
  paid                    INTEGER NOT NULL DEFAULT 0 CHECK (paid IN (0,1)),
  default_days            INTEGER,
  correctness             BOOLEAN NOT NULL CHECK (correctness BETWEEN 0.0 AND 1.0),
  created_at              TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at              TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (client_id) REFERENCES client(id) ON DELETE CASCADE
);

-- ========== TABLE USER <-> CLIENT (Connections) ==========
CREATE TABLE IF NOT EXISTS user_client (
  user_id                 INTEGER NOT NULL,
  client_id               INTEGER NOT NULL,
  created_at              TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, client_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (client_id) REFERENCES client(id) ON DELETE CASCADE
);

-- ========== INDEXES  ==========
-- CLIENT
DROP INDEX IF EXISTS idx_client_name;
CREATE INDEX IF NOT EXISTS client_idx_name_surname ON client(name, surname);

DROP INDEX IF EXISTS idx_client_status;
CREATE INDEX IF NOT EXISTS client_idx_status ON client(status);

DROP INDEX IF EXISTS idx_client_credit_score;
CREATE INDEX IF NOT EXISTS client_idx_credit_score ON client(credit_score);

DROP INDEX IF EXISTS idx_client_email_approved;
CREATE INDEX IF NOT EXISTS client_idx_email_approved
ON client(email COLLATE NOCASE)
WHERE status = 'approved' AND email IS NOT NULL;

-- INVESTING
DROP INDEX IF EXISTS idx_investing_user_time;
CREATE INDEX IF NOT EXISTS investing_idx_user_created_at ON investing(user_id, created_at);

DROP INDEX IF EXISTS idx_investing_status;
CREATE INDEX IF NOT EXISTS investing_idx_order_status ON investing(order_status);

DROP INDEX IF EXISTS idx_investing_ticker;
CREATE INDEX IF NOT EXISTS investing_idx_ticker ON investing(ticker);

-- TRANSACTION_INVEST
DROP INDEX IF EXISTS idx_tx_user_time;
CREATE INDEX IF NOT EXISTS txinv_idx_user_created_at ON transaction_invest(user_id, created_at);

-- LOAN
DROP INDEX IF EXISTS idx_loan_client;
CREATE INDEX IF NOT EXISTS loan_idx_client_id ON loan(client_id);

DROP INDEX IF EXISTS idx_loan_due;
CREATE INDEX IF NOT EXISTS loan_idx_end_date ON loan(end_date);



-- =====================================================
--                        TRIGGERS
-- =====================================================

-- ===== USERS =====
DROP TRIGGER IF EXISTS users_touch_updated_at;
CREATE TRIGGER users_touch_updated_at
AFTER UPDATE ON users
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at  -- ผู้ใช้ไม่ได้ตั้งค่าเอง
BEGIN
  UPDATE users
  SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE id = NEW.id;
END;

-- ===== CLIENT =====
DROP TRIGGER IF EXISTS client_touch_updated_at;
CREATE TRIGGER client_touch_updated_at
AFTER UPDATE ON client
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE client
  SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE id = NEW.id;
END;

-- ===== INVESTING =====
DROP TRIGGER IF EXISTS investing_touch_updated_at;
CREATE TRIGGER investing_touch_updated_at
AFTER UPDATE ON investing
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE investing
  SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE id = NEW.id;
END;

-- ===== TRANSACTION_INVEST =====
DROP TRIGGER IF EXISTS transaction_invest_touch_updated_at;
CREATE TRIGGER transaction_invest_touch_updated_at
AFTER UPDATE ON transaction_invest
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE transaction_invest
  SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE id = NEW.id;
END;

-- ===== LOAN =====
DROP TRIGGER IF EXISTS loan_touch_updated_at;
CREATE TRIGGER loan_touch_updated_at
AFTER UPDATE ON loan
FOR EACH ROW
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE loan
  SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE id = NEW.id;
END;

-- ========== VIEWS ==========
DROP VIEW IF EXISTS v_client_overview;
CREATE VIEW v_client_overview AS
SELECT
  c.id AS client_id,
  c.name || ' ' || c.surname AS full_name,
  c.email,
  c.status,
  IFNULL(c.loan_amount_cents, 0) AS loan_amount_cents,
  IFNULL(c.credit_amount_cents, 0) AS credit_amount_cents,
  c.credit_score,
  c.created_at
FROM client c;

DROP VIEW IF EXISTS v_user_portfolio;
CREATE VIEW v_user_portfolio AS
SELECT
  u.id AS user_id,
  u.username,
  u.cash_cents,
  u.holding_amount_cents,
  IFNULL(SUM(i.total_amount_cents), 0) AS invested_cents
FROM users u
LEFT JOIN investing i ON i.user_id = u.id
GROUP BY u.id, u.username, u.cash_cents, u.holding_amount_cents;

-- ========== FINISH ==========
