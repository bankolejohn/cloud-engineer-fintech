# CI/CD Pipeline — Deep Dive

> How code goes from a developer's `git push` to running in production with zero downtime.

---

## What CI/CD Means (Plain English)

```
CI = Continuous Integration
     "Every time someone pushes code, automatically:
      build it, test it, scan it for vulnerabilities"

CD = Continuous Delivery / Deployment
     "After CI passes, automatically deploy to staging/production
      with canary rollouts and auto-rollback"
```

---

## The 3 Tools We Use (and Why All 3)

| Tool | Role | Why Not Just One Tool? |
|------|------|----------------------|
| **Jenkins** | BUILD — compiles code, runs tests, builds Docker images, pushes to registry | Great at CI. Flexible. Huge plugin ecosystem. |
| **ArgoCD** | DEPLOY — watches Git, syncs K8s clusters to match manifests | GitOps native. Declarative. Self-healing. |
| **Harness** | ORCHESTRATE — multi-stage deployments with approval gates, canary verification | Enterprise deployment management. Approval workflows. |

**Why not just Jenkins for everything?**
Jenkins is great for building. But for deploying to Kubernetes, ArgoCD's GitOps model is superior — the cluster self-heals if someone manually changes something.

**Why not just ArgoCD?**
ArgoCD deploys but doesn't build. You need Jenkins (or similar) to compile code, run tests, and push images.

**Why Harness too?**
Harness adds enterprise features: approval gates ("VP must approve prod deploy"), canary verification with automatic analysis, and audit trails for compliance.

---

## The Full Pipeline (End to End)

```
Developer pushes code to GitHub
        │
        ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  JENKINS (CI — Build & Test)                                              │
│                                                                           │
│  1. Detect which services changed (git diff)                              │
│  2. Build: Compile Go / lint Python                                       │
│  3. Test: Unit tests with coverage                                        │
│  4. SAST Scan: SonarQube checks code quality + vulnerabilities            │
│  5. Docker Build: Multi-stage image (distroless)                          │
│  6. Container Scan: Trivy finds vulnerable OS packages                    │
│  7. Push Image: gcr.io/finflow/transaction-api:main-abc123-42             │
│  8. Update Git: Change image tag in kubernetes/overlays/prod              │
│                                                                           │
│  Time: ~5 minutes                                                         │
└──────────────────────────────────────┬───────────────────────────────────┘
                                       │
                              Git commit with new image tag
                                       │
                                       ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  ARGOCD (CD — GitOps Deployment)                                          │
│                                                                           │
│  1. Detects: "Git changed! Image tag is now main-abc123-42"               │
│  2. Compares: What's in Git vs what's in the cluster                      │
│  3. Syncs: Updates Deployment to use new image                            │
│  4. Rolls out: Rolling update (zero downtime)                             │
│  5. Self-heals: If someone manually changes cluster → reverts to Git     │
│                                                                           │
│  Time: ~2 minutes                                                         │
└──────────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
                           New version running in production!
                           Total time: ~7 minutes from git push
```

---

## Jenkins — The Build Phase (Detailed)

### How Jenkins Knows What to Build

We don't rebuild ALL 5 services for every push. We only build what changed:

```groovy
// jenkins/shared-library/vars/detectChangedServices.groovy

// Compare current commit to previous:
changedFiles = sh("git diff --name-only HEAD~1 HEAD")

// Map changed files to services:
if (file.startsWith('services/transaction-api/'))  → build transaction-api
if (file.startsWith('services/fraud-detection/'))  → build fraud-detection
if (file.startsWith('kubernetes/'))                → rebuild ALL (shared config changed)
```

**Example:** Developer changes `services/fraud-detection/app.py`
→ Only `fraud-detection` gets rebuilt, tested, and deployed. Other services untouched.

### The Jenkinsfile Explained

```groovy
// jenkins/Jenkinsfile (simplified)

pipeline {
    agent {
        kubernetes {
            // Jenkins runs build INSIDE Kubernetes (not on a Jenkins server)
            // Each build gets fresh containers:
            yaml """
            containers:
              - name: golang    # For compiling Go services
              - name: python    # For testing Python services
              - name: docker    # For building Docker images
              - name: trivy     # For security scanning
              - name: kubectl   # For updating manifests
            """
        }
    }

    stages {
        stage('Build & Test') {
            parallel {
                // Go services and Python services build AT THE SAME TIME
                stage('Go Services') {
                    steps {
                        sh 'go test -race ./...'        // Run tests
                        sh 'go build -o /tmp/app .'     // Compile
                    }
                }
                stage('Python Services') {
                    steps {
                        sh 'flake8 .'                   // Lint
                        sh 'bandit -r . -ll'            // Security scan
                        sh 'pytest tests/ -v'           // Tests
                    }
                }
            }
        }

        stage('SAST - SonarQube') {
            // Static analysis: finds bugs, code smells, vulnerabilities
            // "You have SQL injection on line 45"
            // "This function has cyclomatic complexity of 25 (too complex)"
        }

        stage('Build Images') {
            steps {
                // Build Docker image with commit SHA as tag
                sh 'docker build -t gcr.io/finflow/transaction-api:${IMAGE_TAG} .'
            }
        }

        stage('Container Security Scan') {
            steps {
                // Trivy scans the image for known CVEs
                // "alpine:3.18 has CVE-2024-1234 (HIGH) — upgrade to 3.19"
                sh 'trivy image --severity HIGH,CRITICAL --exit-code 1 ${IMAGE}'
                // exit-code 1 = if HIGH/CRITICAL CVEs found, FAIL the build
            }
        }

        stage('Push Images') {
            // Only on main branch (not feature branches)
            when { branch 'main' }
            steps {
                sh 'docker push gcr.io/finflow/transaction-api:${IMAGE_TAG}'
            }
        }

        stage('Update GitOps Manifests') {
            // Change the image tag in kustomization.yaml and commit
            // This triggers ArgoCD to deploy
            when { branch 'main' }
            steps {
                sh 'kustomize edit set image gcr.io/finflow/transaction-api=${IMAGE_TAG}'
                sh 'git commit -m "ci: update image to ${IMAGE_TAG}"'
                sh 'git push'
            }
        }
    }
}
```

---

## ArgoCD — The GitOps Deployment (Detailed)

### What is GitOps?

```
Traditional deployment:
  Developer: "Hey Jenkins, deploy version 2.3.1 to production"
  Jenkins: runs kubectl apply (imperative — "do this")
  
  Problem: If someone runs kubectl manually → cluster state differs from Git
  Problem: No audit trail of WHAT changed
  Problem: How do you roll back? Re-run an old Jenkins job?

GitOps:
  Git IS the source of truth.
  ArgoCD watches Git. If Git says "image: v2.3.1" → cluster MUST have v2.3.1
  If someone manually changes the cluster → ArgoCD REVERTS it to match Git
  
  Deploy = merge PR to main
  Rollback = revert the Git commit (git revert)
  Audit trail = git log
```

### How ArgoCD Works

```
┌─────────────────────┐         ┌────────────────────────┐
│   Git Repository     │         │   Kubernetes Cluster    │
│                      │         │                         │
│  kubernetes/         │         │  finflow namespace:     │
│  overlays/prod/      │◀──────▶│    transaction-api      │
│  kustomization.yaml  │ compare │    (image: v1.0.0)     │
│  (image: v1.0.0) ✅ │  match! │                         │
└─────────────────────┘         └────────────────────────┘

Developer merges PR that updates image tag to v2.0.0:

┌─────────────────────┐         ┌────────────────────────┐
│   Git Repository     │         │   Kubernetes Cluster    │
│                      │         │                         │
│  kubernetes/         │         │  finflow namespace:     │
│  overlays/prod/      │◀── ✘ ─▶│    transaction-api      │
│  kustomization.yaml  │ DRIFT!  │    (image: v1.0.0)     │
│  (image: v2.0.0) ⚠️ │ differ  │                         │
└─────────────────────┘         └────────────────────────┘

ArgoCD detects drift → automatically syncs:
  kubectl set image deployment/transaction-api=gcr.io/finflow/transaction-api:v2.0.0

┌─────────────────────┐         ┌────────────────────────┐
│   Git Repository     │         │   Kubernetes Cluster    │
│                      │         │                         │
│  (image: v2.0.0) ✅  │◀──────▶│  (image: v2.0.0) ✅     │
│                      │  match! │                         │
└─────────────────────┘         └────────────────────────┘
```

### Self-Healing

```
3 AM: Someone (or a script) accidentally runs:
  kubectl scale deployment/transaction-api --replicas=1

ArgoCD notices: "Git says 3 replicas, cluster has 1"
ArgoCD action: Scales back to 3 replicas automatically.
No human needed. Cluster always matches Git.
```

### App of Apps Pattern

Instead of creating each ArgoCD Application manually, we have ONE root app that manages all others:

```
argocd/app-of-apps.yaml (root)
  │
  ├── argocd/apps/transaction-api.yaml → manages transaction-api deployment
  ├── argocd/apps/payment-processor.yaml → manages payment-processor
  ├── argocd/apps/infrastructure.yaml → manages Kafka, monitoring, Istio
  └── ... (add new service = add new file, ArgoCD picks it up)
```

### Multi-Cluster Deployment

```yaml
# Deploy to GCP (primary)
spec:
  destination:
    server: https://kubernetes.default.svc    # GCP cluster
    namespace: finflow

# Deploy SAME service to AWS (secondary)
spec:
  destination:
    server: https://eks-finflow-prod.us-east-1.eks.amazonaws.com  # AWS cluster
    namespace: finflow
```

One repo → two clusters → ArgoCD keeps both in sync.

---

## Harness — Enterprise Deployment Management

Harness adds what Jenkins and ArgoCD don't have: multi-stage pipelines with approval gates and automated canary analysis.

### The Harness Pipeline Stages

```
┌─────────────────────────────────────────────────────────────────────┐
│  Stage 1: BUILD & TEST (like Jenkins)                                │
│  → Compile, test, build image, security scan                         │
└──────────────────────────────────┬──────────────────────────────────┘
                                   │ auto
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Stage 2: DEPLOY TO DEV                                              │
│  → Rolling deploy to dev cluster                                     │
│  → Health check: GET /health returns 200?                            │
└──────────────────────────────────┬──────────────────────────────────┘
                                   │ auto
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Stage 3: INTEGRATION TESTS                                          │
│  → Run Postman/Newman API tests against dev                          │
│  → Verify end-to-end flows work                                      │
└──────────────────────────────────┬──────────────────────────────────┘
                                   │ auto
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Stage 4: DEPLOY TO STAGING (Canary)                                 │
│  → Deploy 1 canary pod (25% traffic)                                 │
│  → Automated verification (5 min):                                   │
│    • Error rate < 5%? ✅                                             │
│    • P99 latency < 500ms? ✅                                        │
│    • No crashes? ✅                                                  │
│  → If all pass → full rolling deploy                                 │
│  → If any fail → automatic rollback                                  │
└──────────────────────────────────┬──────────────────────────────────┘
                                   │ BLOCKED — needs human approval
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Stage 5: APPROVAL GATE                                              │
│                                                                       │
│  "Approve deployment of transaction-api v2.0.0 to PRODUCTION?"       │
│                                                                       │
│  Approvers: Platform leads + SRE team                                │
│  Minimum: 2 people must approve                                       │
│  Timeout: 4 hours (if no one approves, pipeline cancelled)           │
│                                                                       │
│  ✅ Approved by @adebayo (Platform Lead)                             │
│  ✅ Approved by @chioma (SRE)                                        │
└──────────────────────────────────┬──────────────────────────────────┘
                                   │ approved
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Stage 6: DEPLOY TO PRODUCTION (Blue-Green)                          │
│                                                                       │
│  → Deploy to "green" environment (new version)                       │
│  → Run production verification (10 min):                             │
│    • Monitor real traffic metrics                                    │
│    • Compare against baseline                                         │
│  → If verification passes: swap traffic from blue → green           │
│  → If fails: swap back to blue (instant rollback)                    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Deployment Strategies Compared

### Rolling Update (Default Kubernetes)
```
Start: pod-v1, pod-v1, pod-v1
Step 1: pod-v1, pod-v1, pod-v2  ← One new pod added
Step 2: pod-v1, pod-v2, pod-v2  ← One old pod removed
Step 3: pod-v2, pod-v2, pod-v2  ← Complete

Pros: Simple, no extra resources
Cons: If v2 is broken, some users hit it before you notice
```

### Canary (What We Use for Critical Services)
```
Start:  pod-v1, pod-v1, pod-v1 (100% traffic to v1)
Step 1: pod-v1, pod-v1, pod-v1, pod-v2 (10% traffic to v2)
        Monitor for 2 minutes...
Step 2: pod-v1, pod-v1, pod-v1, pod-v2 (25% traffic to v2)
        Monitor for 2 minutes...
Step 3: pod-v1, pod-v1, pod-v1, pod-v2 (50% traffic to v2)
        Monitor for 5 minutes...
Step 4: Full rollout to v2

If error rate spikes at any step → traffic back to 0% v2 instantly.

How: Istio VirtualService weight changes controlled by ArgoCD Rollouts.
```

### Blue-Green (For Production Final Deploy)
```
Blue (current):  pod-v1, pod-v1, pod-v1  ← Serves all traffic
Green (new):     pod-v2, pod-v2, pod-v2  ← Running, but NO traffic

Verification: Send test traffic to green. Check metrics.
Swap: Load balancer points to green. Instant. All traffic on v2.
Rollback: Point back to blue. Instant. (Blue is still running!)

After confidence: Delete blue pods.

Pros: Instant rollback (both versions exist simultaneously)
Cons: Double the resources during deploy
```

---

## Security Scanning in the Pipeline

Three types of scanning happen before code reaches production:

```
┌─────────────────────────────────────────────────────────────────────┐
│  1. SAST (Static Application Security Testing) — SonarQube          │
│                                                                       │
│  Scans SOURCE CODE (without running it)                              │
│  Finds:                                                               │
│  - SQL injection: "query = 'SELECT * WHERE id=' + user_input"       │
│  - Hardcoded secrets: "api_key = 'sk_live_abc123'"                  │
│  - Insecure crypto: "md5(password)" instead of bcrypt               │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│  2. Container Scan — Trivy                                           │
│                                                                       │
│  Scans DOCKER IMAGE (OS packages + libraries)                        │
│  Finds:                                                               │
│  - "openssl 3.0.2 has CVE-2024-1234 (CRITICAL) — upgrade to 3.0.13"│
│  - "python requests 2.28.0 has vulnerability — upgrade to 2.31.0"   │
│                                                                       │
│  If CRITICAL found → build FAILS (code doesn't reach production)    │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│  3. Dependency Scan — Safety (Python) / govulncheck (Go)            │
│                                                                       │
│  Checks libraries in requirements.txt / go.mod against CVE databases│
│  "kafka-python 2.0.1 has a known deserialization vulnerability"      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## The GitOps Loop (How It All Connects)

```
Developer                Jenkins                    Git                    ArgoCD                  Cluster
   │                        │                        │                       │                      │
   │── git push ──────────▶│                        │                       │                      │
   │                        │── build, test, scan ──▶│                       │                      │
   │                        │── build image ────────▶│ (pushed to GCR)      │                      │
   │                        │── update image tag ───▶│                       │                      │
   │                        │                        │── commit detected ───▶│                      │
   │                        │                        │                       │── compare to cluster ▶│
   │                        │                        │                       │── sync (apply) ──────▶│
   │                        │                        │                       │                      │── new pods running
   │                        │                        │                       │◀── health check ─────│
   │                        │                        │                       │── status: Synced ✅  │
   │                        │                        │                       │                      │
```

---

## Rollback Scenarios

### Bad deploy detected by canary:
```
ArgoCD Rollouts detects error rate > 5% on canary pod
→ Automatically sets v2 weight to 0%
→ Scales down canary pod
→ Marks rollout as "Degraded"
→ Slack notification: "🔴 Rollout failed for transaction-api v2.0.0"
→ No human action needed. Production stays on v1.
```

### Bad deploy detected after full rollout:
```
Option 1: git revert (GitOps way)
  git revert HEAD  → removes the image tag change
  ArgoCD detects → syncs back to previous image
  Time: ~3 minutes

Option 2: ArgoCD UI
  Click "Rollback" → select previous revision
  ArgoCD reverts deployment
  Time: ~30 seconds (but Git is now out of sync — fix it after)
```

---

## Key Files in This Repo

```
jenkins/Jenkinsfile                                → Main CI pipeline
jenkins/shared-library/vars/detectChangedServices.groovy → Smart change detection
jenkins/shared-library/vars/deployToKubernetes.groovy    → Deploy helper with rollback
jenkins/shared-library/vars/notifySlack.groovy           → Notification helper

harness/pipeline-deploy.yaml  → Full multi-stage deployment with approval gates

argocd/app-of-apps.yaml                → Root application (manages all others)
argocd/project.yaml                    → RBAC, sync windows, allowed resources
argocd/apps/transaction-api.yaml       → Per-service app with Argo Rollouts canary
argocd/apps/payment-processor.yaml     → Multi-cluster deployment (GCP + AWS)
argocd/apps/infrastructure.yaml        → Kafka, monitoring, Istio, Vault apps
```

---

## Interview Questions You Can Now Answer

1. **"Walk me through your CI/CD pipeline."**
   → Push to Git → Jenkins builds/tests/scans → Docker image pushed → Git manifest updated → ArgoCD detects change → syncs cluster → rolling/canary deployment → automated verification → production.

2. **"What is GitOps?"**
   → Git is the single source of truth for cluster state. ArgoCD continuously reconciles: if cluster drifts from Git, it's reverted. Deploy = merge PR. Rollback = git revert.

3. **"How do you deploy without downtime?"**
   → Rolling updates (always have healthy pods serving). For critical services: canary via Istio (10% → 25% → 50% → 100%) with automated metric verification. Rollback = set canary weight to 0.

4. **"How do you handle security in the pipeline?"**
   → Three-layer scanning: SAST (source code), container scan (OS packages), dependency scan (libraries). CRITICAL findings block the build. No vulnerable code reaches production.

5. **"How do you deploy to multiple clusters/regions?"**
   → ArgoCD Applications with different destination servers. Same Git source, multiple targets. Changes sync to all clusters. Locality-aware traffic management via Istio.

6. **"How do you handle a failed deployment?"**
   → Canary: automatic rollback via Argo Rollouts if error rate exceeds threshold. Full rollout: git revert or ArgoCD manual rollback. Blue-green: swap back to blue (instant, both versions exist).
