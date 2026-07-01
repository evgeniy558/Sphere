#!/usr/bin/env bash
# Build Node (Sphere) and install on a USB-connected iPhone via devicectl.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="Sphere.xcodeproj"
SCHEME="Sphere"
CONFIG="${SPHERE_CONFIG:-Debug}"
DERIVED="${SPHERE_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData}"
BUNDLE_ID="${SPHERE_BUNDLE_ID:-com.nodex.node}"
WAIT_SECONDS="${SPHERE_DEVICE_WAIT_SECONDS:-180}"

log() { printf '[install-iphone] %s\n' "$*" >&2; }
fail() { log "ERROR: $*"; exit 1; }

detect_development_team() {
  if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    printf '%s' "$DEVELOPMENT_TEAM"
    return 0
  fi
  # Prefer team from a fresh Xcode-managed profile (personal Apple ID in Xcode).
  local team prov
  prov="$(find "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" -name '*.mobileprovision' 2>/dev/null | head -1 || true)"
  if [[ -n "$prov" ]]; then
    team="$(security cms -D -i "$prov" 2>/dev/null | plutil -extract TeamIdentifier.0 raw - 2>/dev/null || true)"
    [[ -n "$team" ]] && printf '%s' "$team" && return 0
  fi
  security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Apple Development' | grep -v REVOKED | tail -1 | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p'
}

newest_apple_development_hash() {
  security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Apple Development' | grep -v REVOKED | tail -1 | awk '{print $2}'
}

profile_expiration_epoch() {
  local prov="$1"
  security cms -D -i "$prov" 2>/dev/null \
    | plutil -extract ExpirationDate raw - 2>/dev/null \
    | xargs -I{} date -j -f '%Y-%m-%dT%H:%M:%SZ' '{}' '+%s' 2>/dev/null \
    || echo 0
}

find_valid_provisioning_profile() {
  local team="${1:-}"
  local want_bundle="${2:-$BUNDLE_ID}"
  local now epoch prov team_in app_id
  now="$(date '+%s')"
  while IFS= read -r prov; do
    [[ -f "$prov" ]] || continue
    epoch="$(profile_expiration_epoch "$prov")"
    [[ "$epoch" -gt "$now" ]] || continue
    team_in="$(security cms -D -i "$prov" 2>/dev/null | plutil -extract TeamIdentifier.0 raw - 2>/dev/null || true)"
    if [[ -n "$team" && -n "$team_in" && "$team_in" != "$team" ]]; then
      continue
    fi
    app_id="$(security cms -D -i "$prov" 2>/dev/null | plutil -extract Entitlements:application-identifier raw - 2>/dev/null || true)"
    [[ "$app_id" == *".${want_bundle}" ]] || continue
    printf '%s' "$prov"
    return 0
  done < <(find "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
    "$HOME/Library/MobileDevice/Provisioning Profiles" \
    -name '*.mobileprovision' 2>/dev/null)
  return 1
}

connected_device_ref() {
  if [[ -n "${SPHERE_IOS_DEVICE:-}" ]]; then
    printf '%s' "$SPHERE_IOS_DEVICE"
    return 0
  fi
  local udid name
  if command -v idevice_id >/dev/null 2>&1; then
    udid="$(idevice_id -l 2>/dev/null | head -1 || true)"
    if [[ -n "$udid" ]]; then
      name="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null \
        | grep "id:${udid}" | sed -n 's/.*name:\([^}]*\).*/\1/p' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)"
      printf '%s' "${name:-$udid}"
      return 0
    fi
  fi
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null \
    | grep -E 'platform:iOS, arch:arm64' | grep -v Simulator | head -1 \
    | sed -n 's/.*name:\([^}]*\).*/\1/p' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

wait_for_device() {
  local ref waited=0
  while (( waited < WAIT_SECONDS )); do
    ref="$(connected_device_ref || true)"
    if [[ -n "$ref" ]]; then
      local state
      state="$(xcrun devicectl list devices 2>/dev/null | awk -v n="$ref" '$1==n {print $5}' || true)"
      if [[ "$state" == "available" || -n "$(idevice_id -l 2>/dev/null | head -1 || true)" ]]; then
        printf '%s' "$ref"
        return 0
      fi
      log "iPhone «$ref» найден, но недоступен — разблокируй, нажми «Доверять» и оставь USB."
    else
      log "Жду iPhone по USB… (${waited}s / ${WAIT_SECONDS}s)"
    fi
    sleep 5
    waited=$((waited + 5))
  done
  return 1
}

find_built_app() {
  local latest="" candidate
  for candidate in "$DERIVED"/Sphere-*/Build/Products/Debug-iphoneos/Sphere.app; do
    [[ -d "$candidate" ]] || continue
    if [[ -z "$latest" || "$candidate" -nt "$latest" ]]; then
      latest="$candidate"
    fi
  done
  [[ -n "$latest" ]] && printf '%s' "$latest"
}

build_unsigned_device() {
  local logfile app
  logfile="$(mktemp)"
  log "Сборка $SCHEME (unsigned, iphoneos) …"
  if ! SKIP_DEVICE_INSTALL=1 xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination 'generic/platform=iOS' \
    ENABLE_DEBUG_DYLIB=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build >"$logfile" 2>&1; then
    tail -25 "$logfile" >&2
    rm -f "$logfile"
    exit 1
  fi
  tail -3 "$logfile" >&2
  rm -f "$logfile"
  app="$(find_built_app || true)"
  [[ -n "$app" ]] || fail "Sphere.app не найден после сборки."
  printf '%s' "$app"
}

try_xcode_sign() {
  local logfile team app device dest
  team="$(detect_development_team || true)"
  [[ -n "$team" ]] || return 1
  device="$(connected_device_ref || true)"
  # A connected device lets Xcode register it and mint profiles for app + extensions.
  [[ -n "$device" ]] || return 1
  dest="platform=iOS,name=${device}"
  logfile="$(mktemp)"
  log "Автоподпись Xcode (team $team, $device) …"
  if SKIP_DEVICE_INSTALL=1 xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination "$dest" \
    ENABLE_DEBUG_DYLIB=NO \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$team" \
    build >"$logfile" 2>&1; then
    rm -f "$logfile"
    app="$(find_built_app || true)"
    [[ -n "$app" && -f "$app/embedded.mobileprovision" ]] || return 1
    printf '%s' "$app"
    return 0
  fi
  if grep -q 'No Accounts\|no devices from which to generate' "$logfile" 2>/dev/null; then
    log "Подключи iPhone по USB (разблокируй, «Доверять») — Xcode создаст provisioning profile для com.nodex.node."
  else
    tail -12 "$logfile" >&2
  fi
  rm -f "$logfile"
  return 1
}

sign_for_device() {
  local app="$1"
  local team hash prov ent bundle_for_sign app_id_prefix now epoch
  team="$(detect_development_team || true)"
  hash="$(newest_apple_development_hash || true)"
  [[ -n "$hash" ]] || fail "Нет сертификата Apple Development в Keychain."

  prov="$(find_valid_provisioning_profile "$team" "$BUNDLE_ID" || true)"
  if [[ -z "$prov" ]]; then
    fail "Нет profile для $BUNDLE_ID. Подключи iPhone по USB и собери в Xcode (⌘B) — профиль создастся автоматически."
  fi

  now="$(date '+%s')"
  epoch="$(profile_expiration_epoch "$prov")"
  if [[ "$epoch" -le "$now" ]]; then
    fail "Provisioning profile истёк. Добавь Apple ID в Xcode → Settings → Accounts и пересобери."
  fi

  app_id_prefix="$(security cms -D -i "$prov" 2>/dev/null | plutil -extract Entitlements:application-identifier raw - 2>/dev/null || true)"
  bundle_for_sign="$BUNDLE_ID"
  if [[ "$app_id_prefix" == *"."* && "$app_id_prefix" != *"$BUNDLE_ID"* ]]; then
    bundle_for_sign="${app_id_prefix#*.}"
    log "Profile покрывает $bundle_for_sign — временно меняю bundle id для установки."
  fi

  ent="$(mktemp)"
  printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0"><dict>' \
    "<key>application-identifier</key><string>${app_id_prefix:-${team}.${bundle_for_sign}}</string>" \
    "<key>com.apple.developer.team-identifier</key><string>${team}</string>" \
    '<key>get-task-allow</key><true/>' \
    '</dict></plist>' >"$ent"

  log "Подпись для установки ($bundle_for_sign) …"
  rm -rf "$app/PlugIns"
  rm -f "$app/__preview.dylib" "$app/Sphere.debug.dylib"
  if otool -L "$app/Sphere" 2>/dev/null | grep -q 'Sphere.debug.dylib'; then
    rm -f "$ent"
    fail "Бинарник ссылается на Sphere.debug.dylib — пересобери с ENABLE_DEBUG_DYLIB=NO."
  fi
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle_for_sign" "$app/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $bundle_for_sign" "$app/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Node" "$app/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Node" "$app/Info.plist"
  cp "$prov" "$app/embedded.mobileprovision"
  for fw in "$app"/Frameworks/*.framework; do
    [[ -d "$fw" ]] || continue
    codesign -f -s "$hash" --timestamp=none "$fw"
  done
  codesign -f -s "$hash" --timestamp=none --entitlements "$ent" "$app/Sphere"
  codesign -f -s "$hash" --timestamp=none --entitlements "$ent" "$app"
  rm -f "$ent"
}

prepare_signed_app() {
  local app signed
  if app_signed="$(try_xcode_sign 2>/dev/null || true)" && [[ -n "$app_signed" ]]; then
    log "Использую Xcode-signed build."
    printf '%s' "$app_signed"
    return 0
  fi
  app="$(build_unsigned_device)"
  sign_for_device "$app"
  printf '%s' "$app"
}

install_app() {
  local app="$1"
  local device bundle
  device="$(wait_for_device || true)"
  [[ -n "$device" ]] || fail "iPhone не подключён. Подключи USB, разблокируй, нажми «Доверять этому компьютеру»."
  bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
  log "Установка → $device ($bundle) …"
  xcrun devicectl device install app --device "$device" "$app"
  log "Готово. Открой «Node» на iPhone."
}

case "${1:-}" in
  --from-xcode)
    app="$2"
    if [[ ! -f "$app/embedded.mobileprovision" ]]; then
      sign_for_device "$app"
    fi
    install_app "$app"
    ;;
  --install-only)
    app="$(find_built_app || true)"
    [[ -n "$app" ]] || fail "Нет iphoneos билда. Запусти: $0"
    if [[ ! -f "$app/embedded.mobileprovision" ]]; then
      sign_for_device "$app"
    fi
    install_app "$app"
    ;;
  --build-only)
    prepare_signed_app >/dev/null
    ;;
  "")
    install_app "$(prepare_signed_app)"
    ;;
  *)
    fail "Usage: $0 [--from-xcode <Sphere.app>] | [--install-only] | [--build-only]"
    ;;
esac
