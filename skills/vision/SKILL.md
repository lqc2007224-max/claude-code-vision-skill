---
name: vision
description: Analyze images using Google Gemini vision model when the current model lacks multimodal capabilities. Invoke with an image path to get AI-powered image descriptions, text extraction, or visual analysis.
allowed-tools: Bash(bash:vision.sh) Bash(cat:*) Bash(base64:*)
---

# Vision Skill — External Multimodal Image Analysis

This skill uses **Gemini 2.5 Flash** (free tier, 250 req/day) via Google AI Studio API to analyze images when the primary model cannot process visual content natively.

## When to Use

Invoke this skill whenever the user:
- Provides an image path and asks you to describe, analyze, or extract information from it
- Asks "what's in this image/screenshot/photo?"
- Needs text extracted from a screenshot or UI
- Wants to understand a diagram, chart, or design mockup
- Appends an image file and expects visual understanding

## How to Use

Run the helper script, then parse the JSON response:

```bash
bash .claude/skills/vision/vision.sh "<image_path>" "<prompt>" [model]
```

### Parameters
- `image_path` (required): Absolute or relative path to the image file
- `prompt` (optional): What to ask about the image. Be specific! Default is a general description.
- `model` (optional): Defaults to `gemini-2.5-flash`. Also available: `gemini-2.5-pro`, `gemini-3.1-flash-lite`

### Environment
- `GEMINI_API_KEY`: Your Google Gemini API key (get one free at https://aistudio.google.com/apikey)
- `HTTPS_PROXY`: Falls back to `http://127.0.0.1:7897` (Clash Verge)

## Parsing the Response

The script outputs raw JSON. Extract the text response from:
```
.candidates[0].content.parts[0].text
```

For errors, check:
```
.error.message
```

## Fallback — When Gemini Quota is Exhausted

If the Gemini API returns **HTTP 429** or an error message containing `RESOURCE_EXHAUSTED`, the daily free quota (250 req/day) has been used up. In this case, **automatically fall back** to the backup vision skill:

```bash
bash .claude/skills/vision-backup/vision-backup.sh "<image_path>" "<prompt>"
```

The backup skill uses **Qwen-VL-Max** via DashScope API. It accepts the same parameters and returns a similar JSON response. Parse the result from `.choices[0].message.content`.

**Important:** Always try Gemini first, only use the backup when Gemini is unavailable or quota-exhausted.

## Best Practices

1. **Be specific in your prompt** — "What error dialog is shown in this screenshot?" works better than "Describe this."
2. **For UI screenshots** — Ask about layout, text content, buttons, error states, or specific elements.
3. **For diagrams/charts** — Ask about data, trends, or specific labeled elements.
4. **For text extraction** — Say "Extract ALL text from this image, preserving the layout."
5. **Embedded images in conversation** — If the user references an image file in their message, read it using the Read tool first to confirm it exists, then pass the path to the script.

## Supported Formats

PNG, JPEG/JPG, GIF, WebP, BMP, SVG
