# Phase 6 Lab: ArgoCD (GitOps)

> After this lab you'll understand GitOps — deploying by merging PRs, not running kubectl. And be able to answer: "How do you deploy to production?"

---

## What is GitOps (One Paragraph)

Git is the single source of truth for your cluster state. ArgoCD continuously watches your Git repo and ensures the cluster matches exactly what's in Git. If someone manually changes the cluster, ArgoCD reverts it. Deploy = merge PR. Rollback = git revert. Audit trail = git log. No one runs `kubectl apply` in production.

---

## Why GitOps (The Problem It Solves)

```
WITHOUT GitOps:
  Developer: "Hey, can you deploy my service?"
  DevOps: *SSHes into bastion* → *runs kubectl apply* → "Done"
  
  3 AM: Something is broken.
  Team: "Who changed what? When?"
  Everyone: *shrugs*
  
  Result: No audit trail. No reproducibility. Snowflake clusters.

WITH GitOps (ArgoCD):
  Developer: Merges PR that updates image tag
  ArgoCD: Detects change → syncs cluster automatically
  
  3 AM: Something is broken.
  Team: "git log --since='3 hours ago'" → "Ah, this PR changed the config at 2:45 AM"
  Fix: "git revert <commit>" → ArgoCD deploys previous version
  
  Result: Full audit trail. Reproducible. Self-healing.
```

---

## What We Built

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ArgoCD watches your GitHub repo every 3 minutes:                         │
│                                                                           │
│  GitHub Repo (local-dev branch)                                          │
│  └── local-dev/k8s/                                                      │
│       ├── 00-namespace.yaml                                              │
│       ├── 01-config.yaml                                                 │
│       ├── 02-services.yaml                                               │
│       ├── 03-service-monitor.yaml                                        │
│       └── 04-kafka.yaml                                                  │
│                                                                           │
│  ArgoCD compares Git state vs cluster state:                             │
│  ┌─────────────┐     ┌──────────────────┐                               │
│  │ Git (desired)│     │ Cluster (actual)  │                               │
│  │ replicas: 1  │ === │ replicas: 1       │  → Synced ✅                  │
│  │ image: v1.0.0│ === │ image: v1.0.0     │  → Synced ✅                  │
│  └─────────────┘     └──────────────────┘                               │
│                                                                           │
│  If someone manually changes cluster:                                    │
│  ┌─────────────┐     ┌──────────────────┐                               │
│  │ Git (desired)│     │ Cluster (actual)  │                               │
│  │ replicas: 1  │ !== │ replicas: 3       │  → DRIFT DETECTED ⚠️         │
│  └─────────────┘     └──────────────────┘                               │
│  ArgoCD action: Reverts cluster back to replicas: 1 (self-heal)          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Lab Steps

### Step 1: Install ArgoCD

```bash
# Create namespace
kubectl create namespace argocd --context kind-finflow

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --context kind-finflow

# Wait for pods to be ready (~2 minutes)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/part-of=argocd \
  -n argocd --context kind-finflow --timeout=300s

# Get the admin password
kubectl get secret argocd-initial-admin-secret -n argocd --context kind-finflow \
  -o jsonpath="{.data.password}" | base64 -d && echo ""
```

### Step 2: Access the ArgoCD UI

```bash
# Port-forward to access the web UI
kubectl port-forward svc/argocd-server 8443:443 -n argocd --context kind-finflow

# Open: https://localhost:8443
# Login: admin / <password from step 1>
# (Accept the self-signed certificate warning)
```

### Step 3: Create the ArgoCD Application

```bash
kubectl apply -f local-dev/argocd/finflow-app.yaml --context kind-finflow
```

**What this tells ArgoCD:**
```yaml
source:
  repoURL: https://github.com/bankolejohn/cloud-engineer-fintech.git
  targetRevision: local-dev     # Watch this branch
  path: local-dev/k8s           # Deploy files from this folder

destination:
  server: https://kubernetes.default.svc   # Deploy to this cluster
  namespace: finflow                        # In this namespace

syncPolicy:
  automated:
    prune: true       # Delete resources if removed from Git
    selfHeal: true    # Revert manual changes to match Git
```

### Step 4: Verify Sync Status

```bash
kubectl get application finflow-services -n argocd --context kind-finflow
# Should show: SYNC STATUS = Synced, HEALTH STATUS = Healthy
```

### Step 5: Test Self-Healing (THE KEY DEMO)

```bash
# See current state (1 replica, as defined in Git)
kubectl get deploy transaction-api -n finflow --context kind-finflow

# Manually scale to 3 (simulating someone doing something they shouldn't)
kubectl scale deployment/transaction-api --replicas=3 -n finflow --context kind-finflow

# Check immediately: 3 replicas
kubectl get deploy transaction-api -n finflow --context kind-finflow

# Wait 30-60 seconds for ArgoCD to detect and revert...
sleep 60

# Check again: Back to 1 replica!
kubectl get deploy transaction-api -n finflow --context kind-finflow
# ArgoCD reverted it because Git says replicas=1
```

**This is the magic.** Nobody can make unauthorized changes to production. The cluster always matches Git.

### Step 6: Deploy via Git (The GitOps Way)

To change something in the cluster, you change Git:

```bash
# Example: Scale transaction-api to 2 replicas via Git

# 1. Edit the file locally
# In local-dev/k8s/02-services.yaml, change:
#   replicas: 1  →  replicas: 2

# 2. Commit and push
git add local-dev/k8s/02-services.yaml
git commit -m "scale: transaction-api to 2 replicas"
git push

# 3. Wait for ArgoCD to detect (up to 3 minutes) or force sync:
kubectl exec -n argocd deploy/argocd-server --context kind-finflow -- \
  argocd app sync finflow-services --insecure

# 4. Verify: Now 2 replicas (deployed via Git, not kubectl)
kubectl get deploy transaction-api -n finflow --context kind-finflow
```

### Step 7: Rollback via Git

```bash
# Something went wrong? Revert the commit:
git revert HEAD
git push

# ArgoCD detects → syncs → cluster reverts to previous state
# No "kubectl rollout undo" needed. Git IS the rollback mechanism.
```

---

## Key Concepts

### Sync vs Self-Heal

| Feature | What it does | When it triggers |
|---------|-------------|-----------------|
| **Sync** | Applies changes from Git to cluster | When Git changes (new commit) |
| **Self-Heal** | Reverts unauthorized cluster changes | When cluster state differs from Git |

### Prune

```
If you DELETE a file from Git (e.g., remove a service):
  prune: true  → ArgoCD DELETES the resource from the cluster
  prune: false → ArgoCD leaves orphaned resources in the cluster

Production: Always prune=true (keep cluster clean)
```

### The Deployment Flow (How Teams Actually Deploy)

```
Developer: "I want to deploy transaction-api v2.0.0"

1. Developer opens PR:
   - Changes image tag in kubernetes/overlays/prod/kustomization.yaml:
     images:
       - name: gcr.io/finflow/transaction-api
         newTag: v2.0.0

2. PR is reviewed by Platform team

3. PR is merged to main

4. ArgoCD detects the change (within 3 minutes)

5. ArgoCD syncs: Updates the Deployment image to v2.0.0

6. Kubernetes does rolling update (zero downtime)

7. ArgoCD reports: Synced ✅, Healthy ✅

Nobody ran kubectl. Nobody SSHed anywhere. 
Full audit trail: "PR #42 by @tunde, approved by @you, deployed at 14:32 UTC"
```

---

## Lab Exercises

### Exercise 1: Watch ArgoCD Sync in Real-Time

```bash
# Terminal 1: Watch pods
kubectl get pods -n finflow --context kind-finflow -w

# Terminal 2: Make a change in Git and push
# (Edit 02-services.yaml, change replicas or an env var)
git add . && git commit -m "test: change config" && git push

# Watch Terminal 1: pods update automatically after ArgoCD syncs
```

### Exercise 2: Force a Sync

```bash
# Instead of waiting 3 minutes, force sync now
kubectl exec -n argocd deploy/argocd-server --context kind-finflow -- \
  argocd app sync finflow-services --insecure 2>&1 | head -10

# Or use the ArgoCD CLI (if installed):
# argocd app sync finflow-services
```

### Exercise 3: View Sync History

```bash
# See all sync operations (who deployed what, when)
kubectl get application finflow-services -n argocd --context kind-finflow \
  -o jsonpath='{.status.history}' | python3 -m json.tool
```

---

## Interview Questions You Can Now Answer

1. **"How do you deploy to production?"**
   → GitOps with ArgoCD. Developers merge PRs that update image tags. ArgoCD detects the change and syncs the cluster. Rolling update happens automatically. No one runs kubectl in production.

2. **"What is self-healing in ArgoCD?"**
   → If someone (or something) manually changes the cluster state to differ from Git, ArgoCD detects the drift and reverts it. The cluster always matches Git. This prevents configuration drift and unauthorized changes.

3. **"How do you rollback a bad deployment?"**
   → `git revert <commit>` and push. ArgoCD syncs the reverted state to the cluster. Takes 1-3 minutes. Alternatively, ArgoCD UI has a "Rollback" button for immediate action.

4. **"How do you audit who deployed what?"**
   → `git log`. Every deployment is a Git commit. PR author, reviewer, timestamp, what changed — all in Git history. ArgoCD also logs sync events with timestamps.

5. **"Why not just use kubectl apply in CI/CD?"**
   → No self-healing (manual changes persist). No drift detection. No audit trail beyond CI logs. No single source of truth. ArgoCD provides continuous reconciliation — the cluster is ALWAYS correct.

---

## What's Running After This Lab

```
argocd namespace:
  ✅ argocd-server (API + UI)
  ✅ argocd-application-controller (watches Git, syncs cluster)
  ✅ argocd-repo-server (clones Git repos)
  ✅ argocd-redis (caching)
  ✅ argocd-dex-server (SSO authentication)
  ✅ argocd-notifications-controller (Slack/email alerts)
  ✅ argocd-applicationset-controller (generates apps from templates)

Application: finflow-services
  Source: github.com/bankolejohn/cloud-engineer-fintech (local-dev branch)
  Path: local-dev/k8s/
  Sync: Automated (prune + self-heal)
  Status: Synced ✅
```

---

## Access Quick Reference

```bash
# ArgoCD UI
kubectl port-forward svc/argocd-server 8443:443 -n argocd --context kind-finflow
# → https://localhost:8443 (admin / <password>)

# Get admin password
kubectl get secret argocd-initial-admin-secret -n argocd --context kind-finflow \
  -o jsonpath="{.data.password}" | base64 -d && echo ""

# Check app status
kubectl get application -n argocd --context kind-finflow

# Force sync
kubectl exec -n argocd deploy/argocd-server --context kind-finflow -- \
  argocd app sync finflow-services --insecure
```
