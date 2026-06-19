# Claude Code 自定义视觉 Skill 制作教程

> **目标**：为 Claude Code 打造一套"眼睛"——让没有多模态能力的模型也能看懂图片、截图、图表。
>
> **成果**：双引擎视觉系统 —— Google Gemini（主力）+ 通义千问 Qwen-VL（备胎），自动切换，稳定可靠。
>
> **适用读者**：有基础 Shell 编程经验，想扩展 Claude Code 能力的开发者。

---

## 目录

1. [问题背景：DeepSeek 模型"看不见"](#1-问题背景deepseek-模型看不见)
2. [方案设计：双引擎 + 自动切换](#2-方案设计双引擎--自动切换)
3. [Skill 机制解析：SKILL.md + Shell 脚本](#3-skill-机制解析skillmd--shell-脚本)
4. [Skill 一：Gemini Vision（主力引擎）](#4-skill-一gemini-vision主力引擎)
5. [Skill 二：Qwen-VL Backup（备用引擎）](#5-skill-二qwen-vl-backup备用引擎)
6. [关键技术细节](#6-关键技术细节)
7. [部署与配置](#7-部署与配置)
8. [使用演示](#8-使用演示)
9. [踩坑记录与最佳实践](#9-踩坑记录与最佳实践)
10. [扩展思路](#10-扩展思路)

---

## 1. 问题背景：DeepSeek 模型"看不见"

### 1.1 现状

Claude Code 如果使用 **DeepSeek-V4** 系列模型作为后端，虽然文本能力强大，但**不具备原生的视觉/多模态能力**——无法直接"看到"图片内容。

当你拖入一张截图问"这个报错是什么意思？"，或者贴一张架构图说"帮我分析这个设计"，模型只能看到文件路径，读不懂图像。

### 1.2 需求分析

需要构建一个外部视觉能力补丁，满足以下条件：

| 需求 | 说明 |
|------|------|
| 🔌 无缝集成 | 在 Claude Code 对话中直接调用，无需切换工具 |
| 🖼️ 多格式支持 | 支持 PNG、JPG、GIF、WebP、BMP、SVG 等常见格式 |
| 🌐 网络可达 | 国内环境能正常访问 API（需考虑代理） |
| 💰 成本可控 | 优先使用免费 API，备选付费方案 |
| 🔄 高可用 | 主 API 挂了或配额耗尽时能自动切换备用方案 |
| 📝 易维护 | 纯 Shell 实现，零依赖，修改方便 |

### 1.3 候选 API 对比

| API | 免费额度 | 国内直连 | 视觉能力 | 决策 |
|-----|---------|---------|---------|------|
| Google Gemini | 250 req/天 | ❌ 需代理 | ⭐⭐⭐⭐⭐ | 🥇 主力 |
| Qwen-VL (DashScope) | 付费 | ✅ 直连 | ⭐⭐⭐⭐ | 🥈 备用 |
| OpenAI GPT-4V | 无 | ❌ 需代理 | ⭐⭐⭐⭐⭐ | ❌ 太贵 |
| Claude Vision | 无 | ❌ 需代理 | ⭐⭐⭐⭐⭐ | ❌ 已有 |

**最终方案**：Gemini 2.5 Flash 作为主力（免费 + 质量高），Qwen-VL-Max 作为自动降级备用（国内直连 + 稳定）。

---

## 2. 方案设计：双引擎 + 自动切换

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────┐
│                    Claude Code                        │
│                                                       │
│  用户: "帮我看看这张截图里的报错"  ──┐                │
│                                     │                 │
│                              ┌──────▼────────┐       │
│                              │  Vision Skill  │       │
│                              │  (SKILL.md)    │       │
│                              └──────┬────────┘       │
│                                     │                 │
│                          ┌──────────▼──────────┐     │
│                          │  vision.sh           │     │
│                          │  (Gemini API)        │     │
│                          └──────────┬──────────┘     │
│                                     │                 │
│                           ┌──── HTTP 200? ────┐      │
│                           │ ✅ 是             │ ❌ 否 │
│                           ▼                    ▼      │
│                    返回分析结果    ┌─────────────────┐│
│                                   │vision-backup.sh ││
│                                   │(Qwen-VL API)    ││
│                                   └────────┬────────┘│
│                                            │          │
│                                    返回分析结果      │
└─────────────────────────────────────────────────────┘
```

### 2.2 为什么是双引擎？

- **Gemini** 免费额度 250 次/天，个人使用足够，图片理解能力顶级
- **Qwen-VL** 作为兜底：当 Gemini 配额用完（HTTP 429）或 Google 服务不可达时自动顶上
- Claude 能从两种 API 的不同 JSON 结构中自动提取文字内容

### 2.3 Skill 文件结构

```
.claude/skills/
├── vision/                    # 主力：Gemini 视觉
│   ├── SKILL.md               # 技能定义 + 使用说明
│   └── vision.sh              # 核心执行脚本
└── vision-backup/             # 备用：Qwen-VL 视觉
    ├── SKILL.md               # 技能定义（标注为 fallback）
    └── vision-backup.sh       # 核心执行脚本
```

---

## 3. Skill 机制解析：SKILL.md + Shell 脚本

Claude Code 的 Skill 系统由两个文件组成，理解这套机制是创建任何自定义 Skill 的基础。

### 3.1 SKILL.md —— 技能的"说明书"

```yaml
---
name: vision                    # 技能名称（唯一标识）
description: ...                # 一句话描述（决定何时触发）
allowed-tools: Bash(bash:vision.sh) Bash(cat:*) Bash(base64:*)
---
```

**三个关键字段**：

| 字段 | 作用 |
|------|------|
| `name` | 技能的唯一 ID，Claude 通过它识别和调用 Skill |
| `description` | 最重要的字段。Claude 根据这个描述判断何时自动触发 Skill。要写清楚触发场景 |
| `allowed-tools` | 白名单：这个 Skill 允许执行哪些 Bash 命令。安全机制，防止脚本越权 |

**description 的写法很关键**，它决定了 Skill 的触发准确率：

```yaml
# ✅ 好的 description（触发准确）
description: Analyze images using Google Gemini vision model when
  the current model lacks multimodal capabilities. Invoke with an
  image path to get AI-powered image descriptions, text extraction,
  or visual analysis.

# ❌ 差的 description（可能误触发或不触发）
description: A tool for images.
```

### 3.2 vision.sh —— 技能的"发动机"

Shell 脚本负责实际的 API 调用。选择 Shell 而非 Python 的原因：

- **零依赖**：Windows 上有 Git Bash / WSL，macOS/Linux 自带 bash
- **轻量**：不需要 virtual environment 或 pip install
- **可分享**：别人拿到就能用，不用先折腾环境

---

## 4. Skill 一：Gemini Vision（主力引擎）

### 4.1 API 选型

选择 **Gemini generateContent API** (`v1beta`)，原因：
- v1beta 支持最新模型（如 gemini-2.5-flash）
- 免费层级：250 req/天，个人使用够用
- 图片输入方式：inline_data（base64），不需要先上传到存储桶

### 4.2 获取 API Key

1. 访问 [Google AI Studio](https://aistudio.google.com/apikey)
2. 用 Google 账号登录
3. 点击 "Create API Key"
4. 复制 key 备用

### 4.3 脚本头部：变量定义与参数解析

```bash
#!/bin/bash
set -euo pipefail

API_KEY="${GEMINI_API_KEY:-你的默认Key}"
PROXY="${HTTPS_PROXY:-http://127.0.0.1:7897}"
MODEL="${3:-gemini-2.5-flash}"
```

`set -euo pipefail` 是 Shell 最佳实践：`-e` 任何命令失败立即退出，`-u` 引用未定义变量时报错，`-o pipefail` 管道中任一命令失败都算失败。

`${VAR:-默认值}` 这个模式让用户可通过环境变量覆盖，没设置时用默认值，开箱即用。

```bash
IMAGE_FILE="$1"
PROMPT="${2:-Describe this image in detail, including all text visible in the image.}"

# 防御性检查
if [ ! -f "$IMAGE_FILE" ]; then
  echo '{"error": "File not found"}'
  exit 1
fi
```

必选参数（图片路径）+ 可选参数（提示词、模型），每个都有合理默认值。先检查文件存在性，避免后续奇怪错误。

### 4.4 MIME 类型检测

```bash
ext="${IMAGE_FILE##*.}"
ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
case "$ext_lower" in
  png)      mime="image/png" ;;
  jpg|jpeg) mime="image/jpeg" ;;
  gif)      mime="image/gif" ;;
  webp)     mime="image/webp" ;;
  bmp)      mime="image/bmp" ;;
  svg)      mime="image/svg+xml" ;;
  *)        mime="image/png" ;;        # 未知格式默认按 PNG 处理
esac
```

Gemini API 需要知道图片的 MIME 类型，通过文件扩展名推断，覆盖了常见格式。不认识的统一按 PNG 处理。

### 4.5 核心难点：大图片的 Base64 编码

这是整个脚本中最容易踩坑的地方。

**问题**：当图片较大时（如 4K 截图），base64 字符串可能有几百万字符。直接拼在命令行参数里会触发 **"Argument list too long"** 错误。

**解决方案**：分段写入临时文件，再用 `-d @file` 传给 curl。

```bash
# Step 1: 将图片 base64 编码写入临时文件
B64_FILE="${TMPDIR}/vision_b64_$$.txt"
base64 -w0 "$IMAGE_FILE" > "$B64_FILE" 2>/dev/null || {
  base64 "$IMAGE_FILE" | tr -d '\n' > "$B64_FILE"
}
```

`base64 -w0`（GNU 版，Linux）失败时回退到 `base64 | tr -d '\n'`（macOS/BSD 版），做兼容处理。`$$` 是当前进程 PID，用于生成唯一临时文件名，避免多实例冲突。

```bash
# Step 2: 分段拼接 JSON payload
PAYLOAD_FILE="${TMPDIR}/vision_payload_$$.json"

# 写入 JSON 头部
cat > "$PAYLOAD_FILE" << 'JSONHEAD'
{"contents":[{"parts":[{"text":"
JSONHEAD

# 追加 prompt（转义特殊字符）
printf '%s' "$PROMPT" | sed 's/\\/\\\\/g; s/"/\\"/g' >> "$PAYLOAD_FILE"

# 追加中间部分
cat >> "$PAYLOAD_FILE" << 'JSONMID'
"},{"inline_data":{"mime_type":"
JSONMID
printf '%s' "$mime" >> "$PAYLOAD_FILE"

cat >> "$PAYLOAD_FILE" << 'JSONMID2'
","data":"
JSONMID2

# 追加 base64 数据（这部分可能很大）
cat "$B64_FILE" >> "$PAYLOAD_FILE"

# 追加 JSON 尾部
cat >> "$PAYLOAD_FILE" << 'JSONFOOT'
"}}]}]}
JSONFOOT
```

**设计要点**：
- 使用 heredoc 分段写入，每段都很小，不会触发命令行长度限制
- prompt 中的特殊字符（`\`、`"`）需要 JSON 转义，否则 API 返回解析错误
- 最终 payload 是一个完整的 Gemini API JSON 请求体

### 4.6 API 调用

```bash
HTTP_CODE=$(curl -s --max-time 120 --connect-timeout 15 \
  -x "$PROXY" \
  -H "Content-Type: application/json" \
  -w "%{http_code}" \
  -o "${TMPDIR}/vision_resp_$$.txt" \
  "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${API_KEY}" \
  -d "@${PAYLOAD_FILE}")

>&2 echo "[vision] HTTP $HTTP_CODE"
cat "${TMPDIR}/vision_resp_$$.txt"
rm -f "$PAYLOAD_FILE" "$B64_FILE" "${TMPDIR}/vision_resp_$$.txt"
```

**curl 参数说明**：

| 参数 | 作用 |
|------|------|
| `-s` | 静默模式，不输出进度条 |
| `--max-time 120` | 整体超时 120 秒，大图上传+推理可能较慢 |
| `--connect-timeout 15` | 连接超时 15 秒，网络不通时快速失败 |
| `-x "$PROXY"` | 通过代理访问（国内需翻墙访问 Google） |
| `-w "%{http_code}"` | 捕获 HTTP 状态码，方便判断成功/降级 |
| `-d @<file>` | 从文件读取请求体，避免命令行参数过长 |

所有日志输出到 stderr（`>&2`），最终结果输出到 stdout——Claude 读到的就是纯净的 JSON 响应。

### 4.7 响应解析

Gemini API 成功响应结构：

```json
{
  "candidates": [{
    "content": {
      "parts": [
        {"text": "这张图片显示了一个登录界面，包含用户名和密码输入框..."}
      ]
    }
  }]
}
```

提取文本：`jq -r '.candidates[0].content.parts[0].text'`

错误响应（如配额耗尽）：

```json
{
  "error": {
    "code": 429,
    "message": "Resource has been exhausted..."
  }
}
```

---

## 5. Skill 二：Qwen-VL Backup（备用引擎）

### 5.1 与 Gemini Skill 的关键差异

| 对比维度 | Gemini (vision) | Qwen-VL (vision-backup) |
|---------|-----------------|------------------------|
| API 格式 | Gemini 原生格式 | OpenAI 兼容格式 |
| 认证方式 | URL 参数 `?key=xxx` | Header `Authorization: Bearer xxx` |
| 图片传递 | inline_data + mime_type | data URL (`data:image/png;base64,...`) |
| 代理需求 | 需要（国内访问 Google） | 通常不需要（阿里云国内） |
| 触发时机 | 默认首选 | 仅当 Gemini 失败时 |
| 响应解析 | `.candidates[0].content.parts[0].text` | `.choices[0].message.content` |

### 5.2 获取 API Key

1. 访问 [阿里云 DashScope](https://dashscope.console.aliyun.com/)
2. 开通"模型服务" → 找到"通义千问VL"
3. 获取 API Key

### 5.3 关键代码差异

**Data URL 方式传递图片**（OpenAI 兼容格式的特点）：

```bash
B64=$(base64 -w0 "$IMAGE_FILE" 2>/dev/null || base64 "$IMAGE_FILE" | tr -d '\n')
DATA_URL="data:$mime;base64,$B64"
```

这是标准的 Data URL 格式——`data:image/png;base64,<数据>`，直接把图片嵌入在请求 JSON 中，不需要先上传到 OSS。

**Payload 构建**（OpenAI 多模态格式）：

```json
{
  "model": "qwen-vl-max",
  "messages": [{
    "role": "user",
    "content": [
      {"type": "image_url", "image_url": {"url": "data:image/png;base64,..."}},
      {"type": "text", "text": "请描述这张图片"}
    ]
  }]
}
```

和 ChatGPT API 结构完全一致——一个 messages 数组，content 数组同时包含 image_url 和 text。

**代理是可选的**：

```bash
CURL_OPTS="-s --max-time 120 --connect-timeout 15"
if [ -n "$PROXY" ]; then
  CURL_OPTS="$CURL_OPTS -x $PROXY"
fi
```

国内网络通常直连阿里云，只有特殊环境才需要代理。这一点和 Gemini 相反。

### 5.4 响应解析

Qwen-VL 返回 OpenAI 兼容格式：

```json
{
  "choices": [{
    "message": {
      "content": "这张图片显示了一个登录界面..."
    }
  }]
}
```

提取：`jq -r '.choices[0].message.content'`

### 5.5 自动降级如何工作

backup skill 不需要自己写调度逻辑。在 SKILL.md 中说明了触发条件——当 Gemini 返回 HTTP 429 或连接失败时，Claude 自己会判断"主引擎挂了，该切备胎"，自动调用 backup。整个降级过程对用户透明。

---

## 6. 关键技术细节

### 6.1 为什么用临时文件而不是管道？

```bash
# ❌ 不工作：base64 数据太大，命令行放不下
base64 image.png | curl ... -d @-
```

有两层问题：
1. 如果用 `-d "data:image/png;base64,$(base64 image.png)"`，命令行参数长度有限制
2. Gemini 的 JSON 结构需要 base64 数据嵌套在 `inline_data.data` 字段里，不能直接传裸数据

**正确的方案**：分段写入临时文件 → curl `-d @file` 读取。

### 6.2 跨平台兼容：macOS 与 Linux

macOS 使用 BSD 版 base64，不支持 `-w0`（wrap=0）参数：

```bash
# 先尝试 GNU 方式，失败则降级到 BSD 方式
base64 -w0 "$IMAGE_FILE" 2>/dev/null || {
  base64 "$IMAGE_FILE" | tr -d '\n'
}
```

### 6.3 JSON 特殊字符转义

prompt 中如果包含双引号或反斜杠，直接拼接到 JSON 中会破坏 JSON 结构，导致 API 返回解析错误：

```bash
printf '%s' "$PROMPT" | sed 's/\\/\\\\/g; s/"/\\"/g'
```

### 6.4 stderr 与 stdout 分离

```bash
>&2 echo "[vision] Encoding $IMAGE_FILE ($mime)..."    # stderr → 给人看
>&2 echo "[vision] HTTP $HTTP_CODE"                     # stderr → 给人看
cat "${TMPDIR}/vision_resp_$$.txt"                      # stdout → 给程序读
```

- stderr 的日志只给人类看，不影响 Claude 解析
- stdout 是纯净的 JSON，方便用 jq 或 Python 解析

### 6.5 超时策略

```
--max-time 120 --connect-timeout 15
```

- 连接超时 15 秒：代理挂了或网络不通，快速失败而非死等
- 整体超时 120 秒：大图片的 base64 上传 + API 推理可能需要 30-60 秒

---

## 7. 部署与配置

### 7.1 文件放置

将以下文件放到 `~/.claude/skills/`：

```
.claude/skills/
├── vision/
│   ├── SKILL.md
│   └── vision.sh        # chmod +x
└── vision-backup/
    ├── SKILL.md
    └── vision-backup.sh  # chmod +x
```

不需要安装任何依赖，Claude Code 启动时会自动发现新的 Skill。

### 7.2 环境变量（可选）

在 `~/.claude/settings.json` 中配置：

```json
{
  "env": {
    "GEMINI_API_KEY": "你的Gemini-Key",
    "DASHSCOPE_API_KEY": "你的DashScope-Key",
    "HTTPS_PROXY": "http://127.0.0.1:7897"
  }
}
```

### 7.3 验证部署

```bash
# 测试 Gemini
bash ~/.claude/skills/vision/vision.sh "test.png" "What do you see?"

# 测试 Qwen-VL
bash ~/.claude/skills/vision-backup/vision-backup.sh "test.png" "描述这张图"
```

### 7.4 在对话中使用

部署完成后，在 Claude Code 中像平常一样发送消息：

> "帮我看看 D:\screenshots\error.png 这个报错是什么意思"

Claude 会自动识别、自动调用 Skill、自动解析结果——整个过程用户感觉不到 Skill 的存在，就像模型本身就会看图片。

---

## 8. 使用演示

### 场景 1：分析报错截图

```
用户：分析 D:\error.png 里的报错信息

Claude → 调用 vision.sh → Gemini 返回：
"这是一个 Python ImportError，提示找不到 'torch' 模块..."
```

### 场景 2：提取图中文字

```
用户：把这张表格截图里的数据提取出来 D:\table.png

Claude → 调用 vision.sh（带特定 prompt）→ 返回完整表格数据
```

### 场景 3：Gemini 配额耗尽，自动切换

```
用户：分析 D:\diagram.png

Claude → vision.sh → HTTP 429 (RESOURCE_EXHAUSTED)
       → 检测到配额耗尽
       → 自动调用 vision-backup.sh → Qwen-VL 返回结果
```

---

## 9. 踩坑记录与最佳实践

### 踩坑 #1：Argument list too long

- **现象**：大图片（>2MB）编码后 base64 字符串太大，curl 报 `Argument list too long`
- **原因**：直接把 base64 数据放在命令行参数中
- **解决**：使用临时文件 + `-d @file` 方式传参

### 踩坑 #2：macOS 与 Linux base64 不兼容

- **现象**：macOS 上 `base64 -w0` 报错 `illegal option -- w`
- **原因**：macOS 使用 BSD 版 base64，不支持 `-w0` 参数
- **解决**：做兼容处理，先尝试 `-w0`，失败则 `base64 | tr -d '\n'`

```bash
base64 -w0 "$IMAGE_FILE" 2>/dev/null || {
  base64 "$IMAGE_FILE" | tr -d '\n'
}
```

### 踩坑 #3：JSON 特殊字符未转义

- **现象**：prompt 中包含双引号或反斜杠时，API 返回 JSON 解析错误
- **原因**：直接拼接字符串到 JSON 中，没有转义
- **解决**：用 sed 对 prompt 做 JSON 转义

```bash
printf '%s' "$PROMPT" | sed 's/\\/\\\\/g; s/"/\\"/g'
```

### 踩坑 #4：国内无法访问 Google API

- **现象**：curl 连接超时，报 `Failed to connect`
- **原因**：Google 服务在国内被阻断
- **解决**：通过 Clash Verge 代理（`-x http://127.0.0.1:7897`）

### 最佳实践清单

- ✅ 优先免费 API：Gemini 免费 tier 对个人开发完全够用
- ✅ 双保险设计：主力 + 备用，总有能用的
- ✅ Shell 而非 Python：零依赖，跨平台，易调试
- ✅ stderr 打日志，stdout 出结果：干净的输出 = 可靠的解析
- ✅ 合理的超时：连接 15s + 整体 120s，兼顾体验和大图
- ✅ 防御性编程：检查文件存在、MIME 类型、HTTP 状态码
- ✅ 临时文件用 PID：避免多实例冲突

---

## 10. 扩展思路

### 10.1 添加更多视觉引擎

按照同样的模式，可以轻松添加第三个、第四个视觉引擎：

```
.claude/skills/
├── vision/           # Gemini
├── vision-backup/    # Qwen-VL
└── vision-openai/    # GPT-4V（需要时）
    ├── SKILL.md
    └── vision-openai.sh
```

因为 backup skill 已经用了 OpenAI 兼容格式，加 GPT-4V 只需改 endpoint 和认证方式，Payload 结构不动。

### 10.2 支持视频帧分析

用 `ffmpeg` 提取视频关键帧，然后送给 vision skill：

```bash
ffmpeg -i video.mp4 -vf "fps=1" frames/frame_%04d.png
bash vision.sh frames/frame_0001.png "描述这一帧的内容"
```

### 10.3 批量图片处理

```bash
for img in screenshots/*.png; do
  echo "=== $img ==="
  bash vision.sh "$img" "提取所有文字"
done
```

### 10.4 场景化 Prompt 触发

在 SKILL.md 中编写更精细的触发规则，让 Claude 在不同场景下使用不同的默认 prompt：

- 看到截图 → "提取所有 UI 元素和文字"
- 看到图表 → "分析数据趋势和关键数值"
- 看到照片 → "详细描述场景内容"

---

## 附录

### A. 完整文件清单

| 文件 | 大小 | 用途 |
|------|------|------|
| `.claude/skills/vision/SKILL.md` | ~2KB | 技能定义（YAML + Markdown） |
| `.claude/skills/vision/vision.sh` | ~3KB | Gemini API 调用脚本 |
| `.claude/skills/vision-backup/SKILL.md` | ~2KB | 备用技能定义 |
| `.claude/skills/vision-backup/vision-backup.sh` | ~3KB | Qwen-VL API 调用脚本 |

### B. API 端点速查

| Skill | API Endpoint |
|-------|-------------|
| vision | `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}` |
| vision-backup | `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions` |

### C. 参考链接

- [Google AI Studio](https://aistudio.google.com/) — 获取 Gemini API Key
- [Gemini API 文档](https://ai.google.dev/gemini-api/docs/vision)
- [阿里云 DashScope](https://dashscope.console.aliyun.com/) — 获取 Qwen-VL API Key
- [通义千问 VL 文档](https://help.aliyun.com/zh/model-studio/tongyi-qianwen-vl)
- [Claude Code Skills 文档](https://docs.anthropic.com/en/docs/claude-code/skills)

---

> **写在最后**：这个双引擎视觉系统虽然只有 ~200 行 Shell 代码，但它解决了"AI 看不见"这个根本问题。Skill 机制的精妙之处在于——它让 Claude Code 具备了"调用外部工具"的能力，而这正是 AI Agent 的核心。希望这篇教程能帮到你，也期待看到基于这个模式做出更多有趣的扩展。
