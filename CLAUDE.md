# CLAUDE.md — PayFlow Demo (Cloud Foundry edition)

Cloud Foundry deployment of the PayFlow banking demo. React frontend is embedded
inside the Spring Boot jar — single `cf push`, no separate frontend app.
Services (Postgres, RabbitMQ, Redis) are CF managed and auto-wired via VCAP_SERVICES.
GitHub: https://github.com/zahooruk2022/payflow-demo-cf

**Docker/local version:** `../payflow-demo/` — uses docker-compose, separate frontend dev server.

---

## Commands

```bash
# Build everything (React → static resources → embedded in jar)
./build.sh

# Deploy to CF (requires ./build.sh first)
cf push

# Tail live logs
cf logs payflow-demo

# Check app status
cf app payflow-demo

# Scale
cf scale payflow-demo -i 2
```

**CF service setup (one-time):**
```bash
cf create-service postgres   <plan> payflow-postgres
cf create-service rabbitmq   <plan> payflow-rabbitmq
cf create-service redis      <plan> payflow-redis
```

---

## How the build works

```
./build.sh
├─ cd frontend && npm ci && npm run build
│    └─ output → backend/src/main/resources/static/   ← served as static assets by Spring Boot
└─ cd backend && mvn clean package -DskipTests
     └─ backend/target/payflow.jar  ← uploaded by cf push
```

`frontend/vite.config.js` sets `build.outDir: '../backend/src/main/resources/static'`.
`backend/src/main/resources/static/` is in `.gitignore` — regenerated on every build.

---

## Key files

| File | Purpose |
|---|---|
| `build.sh` | Build script — run before every `cf push` |
| `manifest.yml` | CF manifest — memory, buildpack, health check, service bindings |
| `backend/pom.xml` | Includes `java-cfenv-boot 3.1.5` for VCAP_SERVICES auto-wiring |
| `backend/src/main/resources/application.yml` | Local dev defaults (overridden at runtime by CF bindings) |
| `backend/src/main/resources/data.sql` | Seed: 6 fictional bank accounts |
| `backend/src/main/java/.../config/RedisSslFixPostProcessor.java` | CF compatibility shim — see note below |
| `backend/src/main/resources/META-INF/spring.factories` | Registers RedisSslFixPostProcessor |
| `frontend/src/hooks/useWebSocket.js` | Uses `window.location.origin` (not hardcoded localhost) |
| `frontend/vite.config.js` | `build.outDir` points into backend static resources |
| `architecture.html` | CF-specific interactive architecture diagram |

---

## CF service binding

`java-cfenv-boot` reads `VCAP_SERVICES` and auto-configures:
- `spring.datasource.*` ← PostgreSQL binding (`payflow-postgres`)
- `spring.rabbitmq.*` ← RabbitMQ binding (`payflow-rabbitmq`)
- `spring.data.redis.*` ← Redis binding (`payflow-redis`)

`server.port: ${PORT:8080}` — CF sets `$PORT` dynamically; `8080` is the local fallback.

---

## Known compatibility fix

**Problem:** `java-cfenv-boot` 3.1.x sets `spring.data.redis.ssl=true` as a plain String.
Spring Boot 3.3+ changed `RedisProperties.ssl` from a boolean to a nested `Ssl` record,
so the String-to-object coercion throws `ConverterNotFoundException` at startup.

**Fix:** `RedisSslFixPostProcessor` — an `EnvironmentPostProcessor` registered in
`META-INF/spring.factories` that runs at `LOWEST_PRECEDENCE` (after cfenv), detects
the scalar property, and inserts `spring.data.redis.ssl.enabled=<value>` at highest
priority so Spring Boot's binder uses the structured sub-property path instead.

Do **not** remove `RedisSslFixPostProcessor` or `META-INF/spring.factories` unless
upgrading to a `java-cfenv-boot` version that natively supports Spring Boot 3.3+.

---

## Important notes

- **Fictional banks only** — seed data uses made-up names (Albion, Meridian, Crestfield, Harrington, Caledonian, Vantage). Do not introduce real bank names.
- **DDL auto: create-drop** — database schema and seed data are recreated on every app restart.
- **Offline buildpack** — this TAS foundation uses `java_buildpack_offline`. JDK 21 is specified via `JBP_CONFIG_OPEN_JDK_JRE: '{ jre: { version: 21.+ } }'` in the manifest.
- **CF API transient 404** — this foundation occasionally returns 404 during `cf push` post-staging. If the CLI fails with `Requested route does not exist`, check `cf app payflow-demo` — the app may already be running. If not, run `cf set-droplet` with the latest staged droplet GUID, then `cf start`.
