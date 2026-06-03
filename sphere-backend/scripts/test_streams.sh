#!/usr/bin/env bash
# Smoke-test search + /stream + /audio for each provider against a running Sphere API.
# Usage: BASE_URL=http://127.0.0.1:8080 ./scripts/test_streams.sh
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8080}"
QUERY="${QUERY:-blinding lights}"

providers=(spotify soundcloud youtube deezer yandex vk)

echo "==> health $BASE_URL"
curl -fsS -m 30 "$BASE_URL/health" | head -c 80
echo ""

for prov in "${providers[@]}"; do
  echo ""
  echo "=== $prov search ==="
  json=$(curl -fsS -m 60 "$BASE_URL/search?q=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$QUERY'))")&provider=$prov&limit=1" || echo '{}')
  id=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); t=(d.get('tracks') or [None])[0]; print(t['id'] if t else '')" 2>/dev/null || true)
  if [[ -z "$id" ]]; then
    echo "SKIP: no track (check API keys on server)"
    continue
  fi
  echo "track id=$id"
  echo -n "  /stream: "
  curl -fsS -m 120 "$BASE_URL/tracks/$prov/$id/stream" | head -c 120 || echo "FAIL"
  echo ""
  echo -n "  /audio: "
  code=$(curl -sS -m 120 -o /tmp/sphere-audio.bin -w "%{http_code}" -r 0-4095 "$BASE_URL/tracks/$prov/$id/audio" || echo "000")
  ctype=$(file -b /tmp/sphere-audio.bin 2>/dev/null || echo "?")
  echo "HTTP $code ($ctype)"
done

echo ""
echo "Done."
