# ADR-002: Istio as Service Mesh

## Status
Accepted

## Context
With 5+ microservices communicating across multiple clusters and clouds, we need:
- Mutual TLS for zero-trust security
- Traffic management for progressive delivery
- Observability without application code changes
- Resilience patterns (circuit breaking, retries)

## Decision
Adopt Istio as the service mesh because:
- Native multi-cluster support for our multi-cloud architecture
- Rich traffic management (canary, A/B, fault injection)
- Built-in mTLS rotation without application awareness
- Integration with Prometheus, Jaeger, and Kiali for observability
- Wide adoption and community support

## Alternatives Considered
- **Linkerd** — Simpler but lacks advanced traffic management features we need
- **Consul Connect** — Good HashiCorp integration but less mature K8s support
- **No mesh** — Too much application-level code needed for mTLS and observability

## Consequences
- Sidecar proxies add ~10ms latency (acceptable for our SLOs)
- Memory overhead per pod (~50MB for Envoy sidecar)
- Operational complexity in mesh upgrades
- Gain: Zero-trust security, progressive delivery, multi-cluster routing
