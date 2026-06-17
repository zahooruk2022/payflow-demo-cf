# PayFlow — Cloud Foundry Edition

Real-time interbank payment processing demo — same Spring Boot + RabbitMQ + Redis + PostgreSQL + React architecture, deployed as a **single `cf push`** on Tanzu Application Service (TAS) or any Cloud Foundry foundation.

## PayFlow demo suite

| Repo | Stack | Purpose |
|---|---|---|
| [payflow-demo](https://github.com/zahooruk2022/payflow-demo) | Spring Boot · Docker Compose | Local dev — PostgreSQL, RabbitMQ, Redis, Prometheus, Grafana |
| **payflow-demo-cf** ← you are here | Spring Boot · CF managed services | Tanzu/TAS — single `cf push`, VCAP_SERVICES auto-wiring |
| [payflow-ai](https://github.com/zahooruk2022/payflow-ai) | Spring AI · Tanzu GenAI | AI payment analyst — tool-calling chat + semantic transaction search |

> **Interactive architecture diagram:** open `architecture.html` in a browser.

---

## Table of Contents

1. [How it works on CF](#how-it-works-on-cf)
2. [Prerequisites](#prerequisites)
3. [Step 1 — Create CF services](#step-1--create-cf-services)
4. [Step 2 — Build](#step-2--build)
5. [Step 3 — Push](#step-3--push)
6. [Verifying the deployment](#verifying-the-deployment)
7. [Architecture](#architecture)
8. [What changed from the Docker version](#what-changed-from-the-docker-version)
9. [Configuration](#configuration)
10. [API Reference](#api-reference)
11. [Fraud Detection Rules](#fraud-detection-rules)
12. [Monitoring on CF](#monitoring-on-cf)
13. [Demo Script](#demo-script)

---

## How it works on CF

The React frontend is **embedded inside the Spring Boot jar** — no separate frontend app, no nginx, no CORS.

```
./build.sh
│
├─ npm run build  →  frontend built  →  backend/src/main/resources/static/
│                                       (bundled into the jar as static assets)
└─ mvn package   →  backend/target/payflow.jar
                              ↓
                         cf push
                              ↓
                  ┌────────────────────────┐
                  │  payflow-demo (CF app)  │
                  │  java_buildpack / JDK21 │
                  │  1 GB · 1 instance      │
                  └──────────┬─────────────┘
                             │ VCAP_SERVICES — auto-wired by java-cfenv-boot
                  ┌──────────┼───────────────┐
                  ▼          ▼               ▼
            payflow-      payflow-       payflow-
            postgres     rabbitmq         redis
```

`java-cfenv-boot` reads `VCAP_SERVICES` at startup and automatically configures:
- `spring.datasource.*` from the PostgreSQL binding
- `spring.rabbitmq.*` from the RabbitMQ binding
- `spring.data.redis.*` from the Redis binding

No code changes required for CF — the same `application.yml` local dev values are overridden at runtime by the CF bindings.

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| CF CLI | v8+ | `brew install cloudfoundry/tap/cf-cli@8` |
| Java (JDK) | 21 | `brew install temurin@21` |
| Maven | 3.x | `brew install maven` |
| Node.js | 20 LTS+ | `nvm install --lts` |

```bash
# Log in to your CF foundation
cf login -a https://api.<your-domain> --sso

# Confirm target org and space
cf target
```

---

## Step 1 — Create CF services

Run these once. They provision the managed service instances that the app binds to on `cf push`.

> **Discover available brokers and plans on your foundation:**
> ```bash
> cf marketplace
> cf marketplace -e p.postgres     # plans for a specific broker
> ```

### PostgreSQL

```bash
# Tanzu Postgres for VMs (standard on TAS)
cf create-service p.postgres on-demand-postgres-db payflow-postgres

# Cloud Service Broker — AWS
# cf create-service csb-aws-postgresql small payflow-postgres

# Cloud Service Broker — Azure
# cf create-service csb-azure-postgresql small payflow-postgres
```

### RabbitMQ

```bash
# Tanzu RabbitMQ for VMs (standard on TAS)
cf create-service p.rabbitmq single-node payflow-rabbitmq

# Cloud Service Broker — AWS SQS
# cf create-service csb-aws-sqs standard payflow-rabbitmq
```

### Redis

```bash
# Tanzu Redis for VMs (standard on TAS)
cf create-service p.redis cache-small payflow-redis

# Older Pivotal Redis tile
# cf create-service p-redis shared-vm payflow-redis

# Cloud Service Broker — AWS ElastiCache
# cf create-service csb-aws-redis basic payflow-redis
```

### Wait for services to be ready

On-demand services (p.postgres, p.rabbitmq, p.redis) take 2–5 minutes to provision:

```bash
# Watch until all three show "create succeeded"
watch cf services
```

---

## Step 2 — Build

```bash
./build.sh
```

What the script does:
1. `npm install && npm run build` inside `frontend/` — outputs to `backend/src/main/resources/static/`
2. `mvn clean package -DskipTests` inside `backend/` — produces `backend/target/payflow.jar`

---

## Step 3 — Push

```bash
cf push
```

CF reads `manifest.yml`, uploads `backend/target/payflow.jar`, binds all three services, and starts the app with JDK 21.

```bash
# Follow the startup logs
cf logs payflow-demo --recent

# Get the assigned URL
cf app payflow-demo
```

Look for `Started PayFlowApplication in X.XXX seconds` in the logs, then open the URL.

---

## Verifying the deployment

```bash
# App status and URL
cf app payflow-demo

# All three services bound
cf services

# Health (should show PostgreSQL, RabbitMQ, Redis all UP)
curl https://<route>/actuator/health | python3 -m json.tool

# Live Prometheus metrics
curl https://<route>/actuator/prometheus | grep payflow
```

### Useful operational commands

```bash
# Scale horizontally (show HA during the demo)
cf scale payflow-demo -i 2
cf scale payflow-demo -i 1

# View bound environment (shows VCAP_SERVICES)
cf env payflow-demo

# SSH into the running container
cf ssh payflow-demo

# Stream live application logs
cf logs payflow-demo

# Restart without re-staging
cf restart payflow-demo

# Recent events (crashes, restarts, scaling)
cf events payflow-demo
```

---

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│  Internet / Corporate Network                                       │
│                                                                     │
│  Browser (React SPA + WebSocket)                                    │
│      │  HTTPS                                                       │
│      ▼                                                              │
│  Gorouter  ──────────────────────────────▶  payflow-demo.apps.*    │
│      ◀── WebSocket /topic/*  ─────────────────────────────────┘    │
└────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│  Cloud Foundry Foundation (Tanzu Application Service)               │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  payflow-demo  (Diego Cell)                                  │   │
│  │  java_buildpack · JDK 21 · 1 GB memory                      │   │
│  │                                                              │   │
│  │  Spring Boot 3.5                                             │   │
│  │  ├── REST API          /api/*                                │   │
│  │  ├── WebSocket broker  /ws  →  /topic/transactions           │   │
│  │  │                          →  /topic/fraud-alerts           │   │
│  │  │                          →  /topic/stats                  │   │
│  │  ├── RabbitMQ consumer @RabbitListener(payment.queue)        │   │
│  │  ├── Fraud engine      Redis INCR rapid:<accountId> EXPIRE   │   │
│  │  ├── Actuator          /actuator/health  /actuator/prometheus│   │
│  │  └── Static files      React frontend embedded in jar        │   │
│  └─────────────────────────────────────────────────────────────┘   │
│           │                                                          │
│           │  VCAP_SERVICES  (java-cfenv-boot auto-wires at startup) │
│           ├─────────────────────────────────────────────────────┐   │
│           ▼                    ▼                      ▼          │   │
│  ┌──────────────────┐  ┌─────────────────┐  ┌──────────────┐   │   │
│  │  payflow-postgres │  │ payflow-rabbitmq │  │ payflow-redis│   │   │
│  │  (p.postgres)    │  │ (p.rabbitmq)     │  │ (p.redis)    │   │   │
│  │  accounts        │  │ payment.queue    │  │ rapid:<id>   │   │   │
│  │  transactions    │  │ payment.dlq      │  │ TTL: 60s     │   │   │
│  │  fraud_alerts    │  └─────────────────┘  └──────────────┘   │   │
│  └──────────────────┘                                            │   │
└────────────────────────────────────────────────────────────────────┘
```

---

## What changed from the Docker version

| Concern | Docker version | CF version |
|---|---|---|
| **Deployment** | 3 terminals + docker compose | `./build.sh && cf push` |
| **Services** | Docker containers (local) | CF managed service instances |
| **Frontend** | Vite dev server :5173 (separate) | Embedded in Spring Boot jar |
| **Service config** | Explicit localhost in application.yml | java-cfenv-boot reads VCAP_SERVICES |
| **Port** | Fixed :8080 | `${PORT}` — assigned by CF |
| **WebSocket URL** | `http://localhost:8080/ws` | `window.location.origin + /ws` |
| **Monitoring** | Grafana + Prometheus docker containers | TAS Apps Manager / external Prometheus |
| **Scaling** | Manual | `cf scale payflow-demo -i N` |

---

## Configuration

### Fraud thresholds

Override any setting with CF environment variables — no rebuild needed:

```bash
cf set-env payflow-demo PAYFLOW_FRAUD_HIGH_AMOUNT_THRESHOLD 100000
cf restart payflow-demo
```

| Setting | Default | CF env var |
|---|---|---|
| High amount threshold | 50000 (£) | `PAYFLOW_FRAUD_HIGH_AMOUNT_THRESHOLD` |
| Rapid succession window | 60 (seconds) | `PAYFLOW_FRAUD_RAPID_SUCCESSION_WINDOW_SECONDS` |
| Rapid succession count | 3 | `PAYFLOW_FRAUD_RAPID_SUCCESSION_COUNT` |
| Round number threshold | 5000 (£) | `PAYFLOW_FRAUD_ROUND_NUMBER_THRESHOLD` |
| Flag score threshold | 60 | `PAYFLOW_FRAUD_HIGH_RISK_THRESHOLD` |

### JPA schema

`ddl-auto: create-drop` (default) — schema is recreated on every restart. For persistent data, set:
```bash
cf set-env payflow-demo SPRING_JPA_HIBERNATE_DDL_AUTO update
cf restart payflow-demo
```

---

## API Reference

All endpoints are at `https://<your-cf-route>`.

```
GET  /api/accounts               6 UK bank accounts
GET  /api/payments?limit=50      Recent transactions
POST /api/payments               Submit payment (async via RabbitMQ)
GET  /api/dashboard/stats        Aggregated KPIs
GET  /api/dashboard/alerts       Recent fraud alerts
GET  /actuator/health            Service health (DB / MQ / Redis)
GET  /actuator/prometheus        Prometheus metrics
```

---

## Fraud Detection Rules

| Rule | Trigger | Score | Technology |
|---|---|---|---|
| High Amount | > £50,000 | +60 | In-memory |
| Rapid Succession | 3+ from same account in 60s | +70 | Redis INCR + EXPIRE |
| Round Number | Exact whole-£ amount > £5,000 | +20 | In-memory |

Score ≥ 60 → **FLAGGED**. Scores are additive (max 100).

---

## Monitoring on CF

The backend exposes `/actuator/prometheus` in standard Prometheus text format.

**TAS Apps Manager** — built-in metrics (CPU, memory, requests) at your foundation's Apps Manager URL.

**External Prometheus** — add a scrape target:
```yaml
scrape_configs:
  - job_name: payflow
    scheme: https
    static_configs:
      - targets: ['payflow-demo.apps.<domain>']
    metrics_path: /actuator/prometheus
```

**Custom metrics:**

| Metric | Type |
|---|---|
| `payflow_payments_submitted_total` | Counter |
| `payflow_payments_completed_total` | Counter |
| `payflow_payments_flagged_total` | Counter |
| `payflow_payment_volume_gbp_total` | Counter |
| `payflow_payment_processing_seconds` | Timer (p50/p95/p99) |

---

## Demo Script

### Setup

```bash
cf app payflow-demo    # confirm it's running, copy the URL
```

Open the URL in Chrome. Confirm the green **Live** indicator is visible.

---

### 1. Introduce the platform (1 min)

Open **Dashboard** tab.

> *"This is PayFlow — a real-time interbank payment network. The entire stack is deployed on Cloud Foundry as a single application bound to three managed services: PostgreSQL for durable storage, RabbitMQ for reliable async processing, and Redis for real-time fraud detection. No VMs to configure, no containers to wire up."*

---

### 2. Show the bindings (1 min)

```bash
cf services
```

> *"Three CF managed services — provisioned, patched, and backed up by the platform. The app receives connection details automatically at startup through Cloud Foundry's service binding mechanism."*

---

### 3. Submit a clean payment (2 min)

**Send Payment** → Vantage Bank → Meridian Bank → £15,000 → **Send Payment**

Switch to **Dashboard**.

> *"PENDING → PROCESSING → COMPLETED. Every state change arrives via WebSocket — no polling, no page refresh. The chart ticks, balances update, KPIs refresh on every connected screen simultaneously."*

---

### 4. Trigger fraud (2 min)

**Send Payment** → red **£60K fraud test** → **Send Payment** → **Fraud Alerts** tab.

> *"Sixty thousand pounds, above our fifty thousand threshold. Scored 60 on our fraud model. The Redis counter in the CF managed Redis instance tracked this in a 60-second sliding window. The payment was quarantined before touching any balances."*

---

### 5. Scale live (1 min)

```bash
cf scale payflow-demo -i 2
```

> *"Two instances, one command. RabbitMQ distributes queue work across both — each payment is processed exactly once. This is how you move from a demo to production load."*

```bash
cf scale payflow-demo -i 1
```

---

### Close

> *"PostgreSQL, RabbitMQ, Redis — all managed by the platform. The application code has zero knowledge of hostnames, passwords, or infrastructure. Cloud Foundry injects everything at runtime. One build, one push, production-grade from day one."*
