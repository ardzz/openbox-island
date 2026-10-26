#!/usr/bin/env bash
set -euo pipefail

extension_id=${1:-${YTM_BRIDGE_EXT_ID:-}}
if [[ -z $extension_id ]]; then
  printf '%s\n' \
    'Buka edge://extensions dan aktifkan Mode pengembang.' \
    'Pilih Muat yang dibongkar (Load unpacked), lalu pilih folder browser/ytm-bridge.' \
    'Salin ID ekstensi, lalu jalankan ulang: ./install.sh ID_EKSTENSI' >&2
  exit 1
fi

repo=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)
destination="$HOME/.config/microsoft-edge/NativeMessagingHosts"
mkdir -p "$destination"
jq -n --arg path "$repo/eww/scripts/lib/ytm/bridge-host.sh" \
  --arg origin "chrome-extension://$extension_id/" '{
    name: "com.openbox_island.ytm_bridge",
    description: "Metadata YouTube Music untuk openbox-island",
    path: $path,
    type: "stdio",
    allowed_origins: [$origin]
  }' > "$destination/com.openbox_island.ytm_bridge.json"
printf '%s\n' 'Bridge terpasang. Muat ulang ekstensi dan tab YouTube Music.'
