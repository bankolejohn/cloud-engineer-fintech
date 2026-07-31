-- ==============================================================================
-- FinFlow Database Schema
-- MySQL 8.0 - Transactions, accounts, and audit tables
-- ==============================================================================

CREATE DATABASE IF NOT EXISTS finflow
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE finflow;

-- Accounts table
CREATE TABLE accounts (
    id VARCHAR(36) PRIMARY KEY,
    owner_name VARCHAR(255) NOT NULL,
    balance DECIMAL(18, 2) NOT NULL DEFAULT 0.00,
    currency CHAR(3) NOT NULL DEFAULT 'NGN',
    status ENUM('active', 'frozen', 'closed') NOT NULL DEFAULT 'active',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_owner (owner_name),
    INDEX idx_status (status),
    INDEX idx_currency (currency)
) ENGINE=InnoDB;

-- Transactions table (partitioned by month for performance)
CREATE TABLE transactions (
    id VARCHAR(36) NOT NULL,
    sender_account VARCHAR(36) NOT NULL,
    receiver_account VARCHAR(36) NOT NULL,
    amount DECIMAL(18, 2) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'NGN',
    type ENUM('transfer', 'deposit', 'withdrawal') NOT NULL,
    status ENUM('pending', 'processing', 'completed', 'failed', 'reversed') NOT NULL DEFAULT 'pending',
    description TEXT,
    fraud_score DECIMAL(5, 4) DEFAULT NULL,
    fraud_flags JSON DEFAULT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    PRIMARY KEY (id, created_at),
    INDEX idx_sender (sender_account, created_at),
    INDEX idx_receiver (receiver_account, created_at),
    INDEX idx_status (status, created_at),
    INDEX idx_type_status (type, status),
    INDEX idx_fraud_score (fraud_score)
) ENGINE=InnoDB
PARTITION BY RANGE (UNIX_TIMESTAMP(created_at)) (
    PARTITION p_2024_01 VALUES LESS THAN (UNIX_TIMESTAMP('2024-02-01')),
    PARTITION p_2024_02 VALUES LESS THAN (UNIX_TIMESTAMP('2024-03-01')),
    PARTITION p_2024_03 VALUES LESS THAN (UNIX_TIMESTAMP('2024-04-01')),
    PARTITION p_2024_04 VALUES LESS THAN (UNIX_TIMESTAMP('2024-05-01')),
    PARTITION p_2024_05 VALUES LESS THAN (UNIX_TIMESTAMP('2024-06-01')),
    PARTITION p_2024_06 VALUES LESS THAN (UNIX_TIMESTAMP('2024-07-01')),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);

-- Audit log (immutable)
CREATE TABLE audit_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    entity_type VARCHAR(50) NOT NULL,
    entity_id VARCHAR(36) NOT NULL,
    action VARCHAR(50) NOT NULL,
    actor VARCHAR(100) NOT NULL,
    changes JSON,
    ip_address VARCHAR(45),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_entity (entity_type, entity_id),
    INDEX idx_actor (actor, created_at),
    INDEX idx_created (created_at)
) ENGINE=InnoDB;

-- Notification log
CREATE TABLE notifications (
    id VARCHAR(36) PRIMARY KEY,
    recipient_id VARCHAR(36) NOT NULL,
    channel ENUM('email', 'sms', 'push', 'webhook') NOT NULL,
    type VARCHAR(50) NOT NULL,
    status ENUM('queued', 'sent', 'failed', 'delivered') NOT NULL DEFAULT 'queued',
    title VARCHAR(255),
    message TEXT,
    metadata JSON,
    sent_at TIMESTAMP NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_recipient (recipient_id, created_at),
    INDEX idx_status (status),
    INDEX idx_channel_status (channel, status)
) ENGINE=InnoDB;

-- ProxySQL monitoring user
CREATE USER IF NOT EXISTS 'proxysql_monitor'@'%' IDENTIFIED BY 'CHANGE_VIA_VAULT';
GRANT REPLICATION CLIENT ON *.* TO 'proxysql_monitor'@'%';

-- Application user
CREATE USER IF NOT EXISTS 'finflow_app'@'%' IDENTIFIED BY 'CHANGE_VIA_VAULT';
GRANT SELECT, INSERT, UPDATE, DELETE ON finflow.* TO 'finflow_app'@'%';

-- Read-only user for analytics
CREATE USER IF NOT EXISTS 'finflow_readonly'@'%' IDENTIFIED BY 'CHANGE_VIA_VAULT';
GRANT SELECT ON finflow.* TO 'finflow_readonly'@'%';
