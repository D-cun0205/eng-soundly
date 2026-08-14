#!/bin/bash
# Build EngSoundly for a physical iPhone and install it over cable.
#
# One-time setup (must be done by hand, needs your Apple ID):
#   1. Xcode > Settings > Accounts > '+' > Apple ID 로그인
#      (무료 계정도 가능 — 개인 기기 테스트용, 프로파일 7일 유효)
#   2. iPhone을 케이블로 연결하고 '이 컴퓨터를 신뢰' 허용
#   3. iPhone에서 설정 > 개인정보 보호 및 보안 > 개발자 모드 켜기 → 재부팅
#   4. 팀 ID 확인: https://developer.apple.com/account > Membership,
#      또는 Xcode Accounts 화면의 Team 이름 옆 (예: AB12CD34EF)
#
# Usage:
#   ./deploy_device.sh <TEAM_ID>
#   ./deploy_device.sh <TEAM_ID> <DEVICE_ID>   # 기기가 여러 대일 때
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="${1:?사용법: ./deploy_device.sh <TEAM_ID> — Xcode Accounts에서 확인}"
DEVICE_ID="${2:-}"

echo "▸ Building (Release, iphoneos, team $TEAM_ID)…"
xcodegen generate
xcodebuild -project EngSoundly.xcodeproj -target EngSoundly \
    -sdk iphoneos -configuration Release build \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    -allowProvisioningUpdates \
    | grep -E "error:|warning: [^l]|Signing|BUILD" || true

APP="build/Release-iphoneos/EngSoundly.app"
[ -d "$APP" ] || { echo "✗ 빌드 산출물이 없습니다: $APP"; exit 1; }

if [ -z "$DEVICE_ID" ]; then
    DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null \
        | awk '/connected/ {print $NF; exit}')
    [ -n "$DEVICE_ID" ] || { echo "✗ 연결된 기기가 없습니다. 케이블 연결 + 신뢰 허용 후 재시도."; exit 1; }
fi

echo "▸ Installing on device $DEVICE_ID…"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo "▸ Launching…"
xcrun devicectl device process launch --device "$DEVICE_ID" ai.univs.engsoundly || \
    echo "  (첫 실행은 기기에서 직접: 무료 계정이면 설정 > 일반 > VPN 및 기기 관리에서 개발자 신뢰 필요)"

echo "✓ 완료"
