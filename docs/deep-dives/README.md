# Deep Dive Guides

Detailed explanations of each technology in this project. Read these alongside the actual config files to understand the WHAT, WHY, and HOW.

## Available Guides

| # | Topic | Key Question It Answers |
|---|-------|------------------------|
| 01 | [Service Architecture](./01-service-architecture.md) | How do the microservices talk to each other? |
| 02 | [Kafka Event Streaming](./02-kafka-event-streaming.md) | How is Kafka different from SNS/SQS? Why do we need it? |
| 03 | [Istio Service Mesh](./03-istio-service-mesh.md) | How does Istio provide security and traffic management? |
| 04 | [Vault Secrets Management](./04-vault-secrets-management.md) | How do services get database passwords safely? |
| 05 | [ProxySQL Database Proxy](./05-proxysql-database-proxy.md) | How do you scale MySQL and handle failover? |
| 06 | [Terraform Multi-Cloud](./06-terraform-multi-cloud.md) | How do the modules compose across 4 clouds? |
| 07 | [CI/CD Pipeline](./07-cicd-pipeline.md) | How does code go from git push to production? |
| 08 | [Kafka Operations & Roles](./08-kafka-operations-roles.md) | Who creates topics and users? What's the workflow? |

## Reading Order

If you're new to cloud engineering, read them in this order:
1. Service Architecture (understand what we're deploying)
2. Kafka (understand how services communicate)
3. ProxySQL (understand the data layer)
4. Vault (understand security)
5. Istio (understand the networking layer)
6. Terraform (understand infrastructure provisioning)
7. CI/CD (understand deployment automation)
