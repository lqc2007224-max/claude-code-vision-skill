---
name: vision-backup
description: Backup image analysis using Qwen-VL via DashScope API. Use when Gemini vision skill hits quota limit (429/RESOURCE_EXHAUSTED).
allowed-tools: Bash(bash:vision-backup.sh) Bash(cat:*) Bash(base64:*)
---

# Vision Backup Skill — Qwen-VL via DashScope

This is the **fallback** vision skill. It uses **Qwen-VL-Max** via Alibaba DashScope API when the primary Gemini vision skill runs out of quota.

## When to Use

Invoke this skill ONLY when:
1. The primary Gemini `vision` skill returns a **429** error or `RESOURCE_EXHAUSTED` message
2. The Gemini API is unavailable (network error to Google)
3. The user explicitly requests using the domestic/backup vision model

Do NOT invoke this as the primary vision skill — always try the Gemini `vision` skill first.

## How to Use

Run the helper script, then parse the JSON response:

```bash
bash .claude/skills/vision-backup/vision-backup.sh "<image_path>" "<prompt>" [model]
```

### Parameters
- `image_path` (required): Absolute or relative path to the image file
- `prompt` (optional): What to ask about the image. Be specific! Default is a general description.
- `model` (optional): Defaults to `qwen-vl-max`. Also available: `qwen-vl-plus`, `qwen2.5-vl-72b-instruct`

### Environment
- `DASHSCOPE_API_KEY`: Your DashScope API key (get one at https://dashscope.console.aliyun.com/)
- `DASHSCOPE_HTTPS_PROXY`: Optional proxy for DashScope API (usually NOT needed for domestic access)

## Parsing the Response

The script outputs raw JSON. Extract the text response from:
```
.choices[0].message.content
```

For errors, check:
```
.error.message
```

## Best Practices

1. **Be specific in your prompt** — "What error dialog is shown in this screenshot?" works better than "Describe this."
2. **For UI screenshots** — Ask about layout, text content, buttons, error states, or specific elements.
3. **For diagrams/charts** — Ask about data, trends, or specific labeled elements.
4. **For text extraction** — Say "Extract ALL text from this image, preserving the layout."

## Supported Formats

PNG, JPEG/JPG, GIF, WebP, BMP, SVG
