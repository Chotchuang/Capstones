# Design Document

By Chotchuang Chotnapalai

Video overview: <https://youtu.be/F_fad5amnyk>

## Scope

In this section you should answer the following questions:

* What is the purpose of your database?
- A lightweight CRM + investing/loan tracking store. It models users, clients, the linkage between them, user investing activity and summaries, and client loans.

* Which people, places, things, etc. are you including in the scope of your database?
- Users (login + balances); Clients (KYC-ish profile + credit/loan attributes); User↔Client links; Investing orders & daily summaries; Loans; Read-optimized views for dashboards.

* Which people, places, things, etc. are *outside* the scope of your database?
- Authentication/authorization flows, payment gateway details, audit logs, reporting pipelines/materialized views, analytics beyond the two provided views, and any domain beyond clients/investing/loans. (Your queries.sql also includes DROP statements for teardown; that’s dev-only.)

## Functional Requirements

In this section you should answer the following questions:

* What should a user be able to do with your database?
- Create/update Users and Clients; enforce unique usernames/emails and status/type checks.
- Link clients to users (many-to-many).
- Record investing orders and transaction summaries; query open orders, portfolio breakdowns, KPIs, and timeseries.
- Record client loans, compute overdue status, and aggregate totals/KPIs.
- Use dashboard queries and views

* What's beyond the scope of what a user should be able to do with your database?
- Full text search, workflow engines, audit/version history, granular permissions, or external integrations.

## Representation

### Entities

In this section you should answer the following questions:

* Which entities will you choose to represent in your database?
- users — id (PK), username (UNIQUE), password_hash, cash_cents, holding_amount_cents, ticker_status (CHECK in buy|hold|sell), created_at|updated_at.
Rationale: Money stored as integer cents to avoid floating errors; small “enum” via CHECK increases portability and timestamps as TEXT

* What attributes will those entities have?
- Users: id, username, password_hash, cash_cents, holding_amount_cents, ticker_status, created_at, updated_at.
- Clients: id, name, surname, title, email, status, loan_amount_cents, credit_amount_cents, risk_appetite, market_timing, credit_score, profit_target_cents, cutloss_cents, created_at, updated_at.
- Investing: id, user_id (FK), ticker, order_status, volume, total_amount_cents, correctness, created_at, updated_at.
- Transaction_Invest: id, user_id (FK), investing_id (FK), total_cash_cents, total_buy_cents, total_sell_cents, created_at, updated_at.
- Loan: id, client_id (FK), amount_cents, interest_bps, start_date, end_date, loan_type, paid, default_days, correctness, created_at, updated_at.

* Why did you choose the types you did?
- INTEGER cents: Safe financial calculations, avoids floating-point rounding.
- TEXT timestamps: SQLite stores ISO8601 strings, easy to query with datetime().
- TEXT + CHECK enums: Simple way to enforce controlled values (status, loan_type).
- BOOLEAN (0–1): For probability-like metrics (correctness).
- Composite PK: For many-to-many relationships (user_client).

* Why did you choose the constraints you did?
- NOT NULL + DEFAULT: Ensure required values, safe defaults (0, now).
- UNIQUE: Prevent duplicates (username, email).
- CHECK: Validate domain values (non-negative amounts, correctness between 0–1, enums).
- FOREIGN KEY + ON DELETE CASCADE: Keep referential integrity, avoid orphan rows.
- Triggers: Auto-update updated_at on changes.
- Indexes: Optimize common queries (by status, created_at, approved email).

### Relationships

In this section you should include your entity relationship diagram and describe the relationships between the entities in your database.

- users ↔ user_client ↔ client: M:N via link table; cascades on delete.
- users → investing: 1:N (one user, many orders).
- investing → transaction_invest: 1:N summaries per order.
- client → loan: 1:N (a client may have multiple loans).


## Optimizations

In this section you should answer the following questions:

* Which optimizations (e.g., indexes, views) did you create? Why?
- Clients by status/name/score/email including partial index improves search (status='approved' AND email IS NOT NULL)
- Investing by user_id, created_at, and by order_status.
- Transactions by (user_id, created_at); Loans by client_id and end_date. These match dashboard/search/time-series queries in queries.sql (approved lists, LIKE search, open orders, timeseries, top-N, KPIs).
- Views to simplify common joins/aggregations (v_user_portfolio, v_client_overview).
- Search queries on client improves search performance when filtering by email with status='approved'. It does not optimize LIKE queries on name/surname.

## Limitations

In this section you should answer the following questions:

* What are the limitations of your design?
- Triggers: Implemented as "AFTER UPDATE" triggers that set updated_at by PK with a guard WHEN NEW.updated_at = OLD.updated_at to avoid recursion and unnecessary writes.
- Foreign key enforcement requires PRAGMA: You enable it in queries (PRAGMA foreign_keys = ON;), but every new connection must do so, or FKs won’t enforce.

* What might your database not be able to represent very well?
- Dev-only cleanup now targets staging tables (e.g., staging_client_import) rather than core schema. Keep such steps out of production runs.
- Engine constraints: No native enums/materialized views; dates are TEXT; no native FULL OUTER JOIN; scaling beyond single-file DB will need sharding or migration to a server RDBMS.
