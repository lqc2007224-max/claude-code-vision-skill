#!/bin/bash
# Vision Backup skill - call Qwen-VL (DashScope) API to analyze images
# Usage: vision-backup.sh <image_path> [prompt] [model]
# Domestic API, no proxy needed by default

set -euo pipefail

API_KEY="${DASHSCOPE_API_KEY:-YOUR_DASHSCOPE_API_KEY}"
MODEL="${3:-qwen-vl-max}"
# Domestic API — only use proxy if explicitly set
PROXY="${DASHSCOPE_HTTPS_PROXY:-}"

if [ $# -lt 1 ]; then
  echo '{"error": "Usage: vision-backup.sh <image_path> [prompt] [model]"}'
  exit 1
fi

IMAGE_FILE="$1"
PROMPT="${2:-Describe this image in detail, including all text visible in the image.}"

if [ ! -f "$IMAGE_FILE" ]; then
  echo "{\"error\": \"File not found: $IMAGE_FILE\"}"
  exit 1
fi

# Detect MIME type
ext="${IMAGE_FILE##*.}"
ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
case "$ext_lower" in
  png)  mime="image/png" ;;
  jpg|jpeg) mime="image/jpeg" ;;
  gif)  mime="image/gif" ;;
  webp) mime="image/webp" ;;
  bmp)  mime="image/bmp" ;;
  svg)  mime="image/svg+xml" ;;
  *)    mime="image/png" ;;
esac

>&2 echo "[vision-backup] Encoding $IMAGE_FILE ($mime)..."

# Encode to base64
B64=$(base64 -w0 "$IMAGE_FILE" 2>/dev/null || base64 "$IMAGE_FILE" | tr -d '\n')
>&2 echo "[vision-backup] Encoded ${#B64} base64 chars"

# Build data URL
DATA_URL="data:$mime;base64,$B64"

# Escape prompt for JSON
ESC_PROMPT=$(printf '%s' "$PROMPT" | sed 's/\\/\\\\/g; s/"/\\"/g')

# Build JSON payload — OpenAI-compatible format
TMPDIR="${TMPDIR:-/tmp}"
PAYLOAD_FILE="${TMPDIR}/vision_backup_payload_$$.json"

cat > "$PAYLOAD_FILE" << EOF
{
  "model": "$MODEL",
  "messages": [
    {
      "role": "user",
      "content": [
        {"type": "image_url", "image_url": {"url": "$DATA_URL"}},
        {"type": "text", "text": "$ESC_PROMPT"}
      ]
    }
  ]
}
EOF

>&2 echo "[vision-backup] Payload $(wc -c < "$PAYLOAD_FILE") bytes, calling $MODEL..."

# Build curl command — proxy is optional for domestic API
CURL_OPTS="-s --max-time 120 --connect-timeout 15"
if [ -n "$PROXY" ]; then
  CURL_OPTS="$CURL_OPTS -x $PROXY"
fi

HTTP_CODE=$(curl $CURL_OPTS \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -w "%{http_code}" \
  -o "${TMPDIR}/vision_backup_resp_$$.txt" \
  "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions" \
  -d "@${PAYLOAD_FILE}")

>&2 echo "[vision-backup] HTTP $HTTP_CODE, response $(wc -c < "${TMPDIR}/vision_backup_resp_$$.txt") bytes"

# Output response
cat "${TMPDIR}/vision_backup_resp_$$.txt"

# Cleanup
rm -f "$PAYLOAD_FILE" "${TMPDIR}/vision_backup_resp_$$.txt"
