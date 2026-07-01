#!/usr/bin/env bash
# Creates or refreshes the shared Kirby test user on the Sphere Go backend.
set -euo pipefail

BASE="${SPHERE_BACKEND_URL:-https://sphere-backend-8ssb.onrender.com}"
EMAIL="${SPHERE_TEST_EMAIL:-kirby.test@sphere.app}"
PASSWORD="${SPHERE_TEST_PASSWORD:-sphere_kirby_test_autopass}"
NAME="${SPHERE_TEST_NAME:-Kirby Test}"

echo "→ POST $BASE/auth/register"
code=$(curl -sS -o /tmp/sphere-test-reg.json -w "%{http_code}" \
  -X POST "$BASE/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"name\":\"$NAME\"}")

if [[ "$code" == "201" ]]; then
  echo "✓ Created $EMAIL"
elif [[ "$code" == "409" ]]; then
  echo "• Already exists — trying login"
  curl -sS -X POST "$BASE/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" | head -c 200
  echo ""
else
  echo "✗ HTTP $code"
  cat /tmp/sphere-test-reg.json
  exit 1
fi

echo ""
echo "Login in the app:"
echo "  Email:    $EMAIL"
echo "  Password: $PASSWORD"
echo "Or tap «Тестовый аккаунт (Kirby)» on the login screen."
