# ProxySQL — Database Proxy Deep Dive

> How ProxySQL sits between your app and MySQL to provide connection pooling, read/write splitting, query caching, and automatic failover.

---

## What ProxySQL Is (One Line)

A middleman between your application and MySQL that makes your database faster, smarter, and more resilient — without changing application code.

---

## The Problem Without ProxySQL

```
50 pods × 10 connections each = 500 connections to MySQL
- MySQL struggles above ~500 connections
- ALL queries (reads AND writes) go to one server
- If primary dies, everything breaks
- Bad queries from one pod affect everyone
```

## The Solution With ProxySQL

```
50 pods → ProxySQL → 20 actual MySQL connections
  - Connection pooling (50 app connections → 20 DB connections)
  - SELECTs → Replicas (80% of traffic offloaded)
  - INSERT/UPDATE/DELETE → Primary only
  - Query caching (repeated SELECTs served from memory)
  - Auto-failover (primary dies → replica promoted)
```

---

## Key Concepts

### 1. Connection Pooling (Multiplexing)
50 pods share 20 actual database connections. ProxySQL grabs a free connection, sends the query, returns it to the pool. MySQL stays healthy.

### 2. Read/Write Splitting
```
SELECT balance FROM accounts WHERE id='acct-001'  → Replica (read)
INSERT INTO transactions (amount) VALUES (50000)   → Primary (write)
SELECT status FROM transactions WHERE id='txn-123' → Replica (read)
UPDATE accounts SET balance=balance-50000          → Primary (write)

Primary handles 2 queries (writes only).
Replica handles 2 queries (reads).
Primary is 50% less loaded.
```

### 3. Hostgroups
```
Hostgroup 10 = WRITERS (Primary MySQL)
Hostgroup 20 = READERS (Replicas)

ProxySQL routes queries based on SQL pattern:
  ^SELECT           → Hostgroup 20 (readers)
  ^SELECT.*FOR UPDATE → Hostgroup 10 (writer, because it locks rows)
  ^INSERT|UPDATE|DELETE → Hostgroup 10 (writer)
```

### 4. Query Rules (The Smart Part)

ProxySQL reads every SQL statement and applies rules:

| Rule | Pattern | Action |
|------|---------|--------|
| Account lookups | `SELECT.*FROM accounts WHERE id` | Cache for 5 seconds |
| Dangerous DDL | `^(DROP\|TRUNCATE\|ALTER)` | BLOCK with error message |
| Expensive scans | `SELECT.*FROM transactions WHERE.*created_at` | Add 100ms delay (rate limit) |
| Normal reads | `^SELECT` | Route to replicas |
| All writes | `^(INSERT\|UPDATE\|DELETE)` | Route to primary |

### 5. Query Caching
```
First request:  SELECT balance FROM accounts WHERE id='acct-001' → MySQL (3ms)
Next 5 seconds: Same query → ProxySQL memory (0.1ms) ⚡
After 5s:       Cache expires → MySQL again

At 10,000 req/s: Only 200 hit MySQL (once per 5s per unique query).
```

### 6. Automatic Failover
```
ProxySQL pings primary every 5 seconds.
3 failed pings → Primary marked DOWN.
Replica promoted to writer hostgroup.
Application sees ~15 seconds of write unavailability.
No code change needed — app talks to ProxySQL, not directly to MySQL.
```

---

## How Your App Connects

```
Without ProxySQL: DB_HOST=mysql-primary:3306 (direct)
With ProxySQL:    DB_HOST=proxysql:6033     (through proxy)

Your app uses the same MySQL driver. Same queries. Same everything.
ProxySQL speaks the MySQL protocol — it impersonates MySQL.
The app doesn't know ProxySQL exists.
```

---

## Monitoring

```sql
-- See backend server status
SELECT hostgroup_id, hostname, status, Queries FROM stats_mysql_connection_pool;

-- See which query rules are being hit
SELECT rule_id, hits, match_digest FROM stats_mysql_query_rules;

-- Connection efficiency
-- Client_Connections_connected: 47 (app pods)
-- Server_Connections_connected: 18 (actual MySQL) ← The magic
```

---

## Key Files in This Repo

```
proxysql/proxysql.cnf  → Full config (hostgroups, query rules, caching, failover)
mysql/schema.sql       → Database schema (partitioned transactions table)
```
