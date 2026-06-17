#!/usr/bin/env bash
# PayFlow — CF build script
# Produces a single jar containing the React frontend as static resources.
# Run this before every cf push.
set -euo pipefail

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  PayFlow — Cloud Foundry Build           ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Step 1: React frontend ─────────────────────────────────────────────────
echo "▶ [1/2] Building React frontend..."
echo "        Output → backend/src/main/resources/static/"
echo ""

cd frontend
npm install --silent
npm run build
cd ..

echo ""
echo "  ✓ Frontend built ($(find backend/src/main/resources/static -type f | wc -l | tr -d ' ') files)"

# ── Step 2: Spring Boot jar ────────────────────────────────────────────────
echo ""
echo "▶ [2/2] Building Spring Boot jar..."
echo ""

cd backend
mvn clean package -DskipTests -q
cd ..

JAR="backend/target/payflow.jar"
SIZE=$(du -sh "$JAR" | cut -f1)

echo ""
echo "  ✓ Built: $JAR ($SIZE)"
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  Build complete — ready to deploy        ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Next step:"
echo "    cf push"
echo ""
