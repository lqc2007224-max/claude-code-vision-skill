#!/bin/bash
# Vision skill - call Gemini API to analyze images
# Usage: vision.sh <image_path> [prompt] [model]
# Proxy: 127.0.0.1:7897 (Clash Verge default)

set -euo pipefail

API_KEY="${GEMINI_API_KEY:-YOUR_GEMINI_API_KEY}"
PROXY="${HTTPS_PROXY:-http://127.0.0.1:7897}"
MODEL="${3:-gemini-2.5-flash}"

if [ $# -lt 1 ]; then
  echo '{"error": "Usage: vision.sh <image_path> [prompt] [model]"}'
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

>&2 echo "[vision] Encoding $IMAGE_FILE ($mime)..."

# Temp directory for payload files
TMPDIR="${TMPDIR:-/tmp}"
PAYLOAD_FILE="${TMPDIR}/vision_payload_$$.json"

# Step 1: Write base64 data to a file
B64_FILE="${TMPDIR}/vision_b64_$$.txt"
base64 -w0 "$IMAGE_FILE" > "$B64_FILE" 2>/dev/null || {
  base64 "$IMAGE_FILE" | tr -d '\n' > "$B64_FILE"
}
>&2 echo "[vision] Encoded $(wc -c < "$B64_FILE") base64 chars"

# Step 2: Build the JSON payload in parts, avoiding "Argument list too long"
# Write JSON header
cat > "$PAYLOAD_FILE" << 'JSONHEAD'
{"contents":[{"parts":[{"text":"
JSONHEAD

# Append the prompt (escaped for JSON)
printf '%s' "$PROMPT" | sed 's/\\/\\\\/g; s/"/\\"/g' >> "$PAYLOAD_FILE"

# Append the middle section
cat >> "$PAYLOAD_FILE" << 'JSONMID'
"},{"inline_data":{"mime_type":"
JSONMID

printf '%s' "$mime" >> "$PAYLOAD_FILE"

cat >> "$PAYLOAD_FILE" << 'JSONMID2'
","data":"
JSONMID2

# Append the base64 data
cat "$B64_FILE" >> "$PAYLOAD_FILE"

# Append JSON footer
cat >> "$PAYLOAD_FILE" << 'JSONFOOT'
"}}]}]}
JSONFOOT

>&2 echo "[vision] Payload $(wc -c < "$PAYLOAD_FILE") bytes, calling $MODEL..."

# Step 3: Call the API
HTTP_CODE=$(curl -s --max-time 120 --connect-timeout 15 \
  -x "$PROXY" \
  -H "Content-Type: application/json" \
  -w "%{http_code}" \
  -o "${TMPDIR}/vision_resp_$$.txt" \
  "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${API_KEY}" \
  -d "@${PAYLOAD_FILE}")

>&2 echo "[vision] HTTP $HTTP_CODE, response $(wc -c < "${TMPDIR}/vision_resp_$$.txt") bytes"

# Output response
cat "${TMPDIR}/vision_resp_$$.txt"

# Cleanup
rm -f "$PAYLOAD_FILE" "$B64_FILE" "${TMPDIR}/vision_resp_$$.txt"
