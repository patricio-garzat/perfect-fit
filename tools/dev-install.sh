#!/bin/bash
# Instala "Perfect Fit Dev" en el iPhone conectado (por cable o Wi-Fi), sin pasar por App Store Connect.
# Es una app aparte (com.blubergames.perfectfit.dev, ícono con franja DEV).
# Firma con el equipo CGW77RJS5Q usando la clave de API de ~/.appstoreconnect/cubeswipe.env (la misma del estudio).
# Uso: tools/dev-install.sh            → compila en Release con los últimos cambios y la instala
set -euo pipefail
cd "$(dirname "$0")/.."
source "$HOME/.appstoreconnect/cubeswipe.env"

DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/available \(paired\)/ && /iPhone/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F-]{36}$/) {print $i; exit}}')
[ -n "$DEVICE" ] || { echo "No encontré un iPhone conectado y disponible. Conéctalo y desbloquéalo."; exit 1; }
UDID=$(xcrun devicectl device info details --device "$DEVICE" 2>/dev/null | awk '/udid:/ {print $NF; exit}')
echo "iPhone: $DEVICE ($UDID)"

command -v xcodegen >/dev/null && xcodegen generate >/dev/null
DD="${PF_DERIVED_DATA:-build/DerivedData-dev}"
AUTH=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
xcodebuild -project PerfectFit.xcodeproj -scheme PerfectFit -configuration Release \
  -destination "id=$UDID" -derivedDataPath "$DD" "${AUTH[@]}" \
  BUNDLE_ID_SUFFIX=.dev APP_DISPLAY_NAME="Perfect Fit Dev" APP_ICON_SUFFIX=-Dev \
  build | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'

APP="$DD/Build/Products/Release-iphoneos/PerfectFit.app"
xcrun devicectl device install app --device "$DEVICE" "$APP" | grep -E -i 'installed|error' || true
xcrun devicectl device process launch --device "$DEVICE" com.blubergames.perfectfit.dev >/dev/null 2>&1 || true
echo "Listo: Perfect Fit Dev instalada en tu iPhone."
