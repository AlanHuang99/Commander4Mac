#!/usr/bin/env bash
# Credentials are passed only through the release step environment.
set -euo pipefail
ACTION="${1:?usage: ci_signing.sh setup|cleanup}"
SIGNING_DIR="${RUNNER_TEMP:?GitHub runner temporary directory required}/commander-signing"
KEYCHAIN="$SIGNING_DIR/release.keychain-db"
if [[ "$ACTION" == cleanup ]]; then
  STATUS=0
  if [[ -f "$KEYCHAIN" ]]; then security delete-keychain "$KEYCHAIN" || STATUS=$?; fi
  rm -rf "$SIGNING_DIR"
  exit "$STATUS"
fi
[[ "$ACTION" == setup ]] || { echo 'Unknown signing action' >&2; exit 2; }
umask 077
mkdir -p "$SIGNING_DIR"
for variable in MACOS_CERT_P12_BASE64 MACOS_CERT_P12_PASSWORD MACOS_KEYCHAIN_PASSWORD MACOS_NOTARY_API_KEY_P8_BASE64 MACOS_NOTARY_API_KEY_ID MACOS_NOTARY_ISSUER_ID MACOS_TEAM_ID SPARKLE_ED_PRIVATE_KEY; do
  [[ -n "${!variable:-}" ]] || { echo "Missing encrypted secret: $variable" >&2; exit 1; }
done
[[ "$MACOS_TEAM_ID" == 66LBY954DT ]] || { echo 'Unexpected release team' >&2; exit 1; }
python3 - "$SIGNING_DIR" <<'PY'
import base64,os,sys
from pathlib import Path
directory=Path(sys.argv[1])
for variable,filename in [('MACOS_CERT_P12_BASE64','identity.p12'),('MACOS_NOTARY_API_KEY_P8_BASE64','AuthKey.p8')]:
    (directory/filename).write_bytes(base64.b64decode(os.environ[variable],validate=True))
update_key=os.environ['SPARKLE_ED_PRIVATE_KEY'].strip()
if len(base64.b64decode(update_key,validate=True)) not in (32,96):
    raise SystemExit('Invalid encrypted Sparkle signing-key format')
(directory/'sparkle.key').write_text(update_key+'\n')
PY
security create-keychain -p "$MACOS_KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 7200 "$KEYCHAIN"
security unlock-keychain -p "$MACOS_KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$SIGNING_DIR/identity.p12" -P "$MACOS_CERT_P12_PASSWORD" -t cert -f pkcs12 \
  -k "$KEYCHAIN" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$MACOS_KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN"
security find-identity -v -p codesigning "$KEYCHAIN"
xcrun notarytool store-credentials Commander4Mac-notary --keychain "$KEYCHAIN" \
  --key "$SIGNING_DIR/AuthKey.p8" --key-id "$MACOS_NOTARY_API_KEY_ID" --issuer "$MACOS_NOTARY_ISSUER_ID" >/dev/null
rm -f "$SIGNING_DIR/identity.p12" "$SIGNING_DIR/AuthKey.p8"
echo 'Release signing identity and notarization profile ready in the temporary keychain.'
