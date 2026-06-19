# 从零开始：Claude Code 自定义视觉 Skill 制作教程

> 用两个 Shell 脚本，给你的 Claude Code 装上眼睛。

---

## 学完你能得到什么？

- 理解 Claude Code 的 Skill 机制怎么工作
- 拥有一个**双引擎**视觉系统：主力免费（Gemini）+ 备用直连（Qwen-VL）
- 学会几个 Shell 脚本的实用技巧
- 掌握从零写自定义 Skill 的完整方法

**需要的前置知识**：会用终端、写过 Hello World 级别的 Shell 脚本就够了。

---

## 第一章 为什么要做这个？

### 1. AI 看不见

我用 DeepSeek-V4 模型跑 Claude Code。文本能力很强，但有一个硬伤——**没有视觉能力**，不能"看到"图片。

我拖一张报错截图进去，说"帮我看看这个报错"，它只能看到文件路径，读不懂图片内容。截图里的报错信息、UI 界面、表格数据——对它来说全是空白。

### 2. 解决思路

既然模型本身看不到，就给它接一个外部视觉 API：

```
用户发一张图片
    → Claude Code 发现"这是图片分析任务"
    → 自动调用脚本，把图片发给视觉 API
    → API 返回图片里的文字描述
    → Claude Code 读描述，回答用户
```

用户感觉模型突然"能看见"了，背后发生了什么完全透明。

### 3. 为什么选 Gemini + Qwen-VL？

市面上多模态 API 不少，我做了一个对比：

| API | 免费额度 | 国内直连 | 图片理解 |
|-----|---------|---------|---------|
| Google Gemini | **250次/天** | 需要代理 | 顶级 |
| Qwen-VL（通义千问） | 付费 | **能直连** | 优秀 |
| OpenAI GPT-4V | 无免费 | 需要代理 | 顶级 |

我的逻辑很简单：

- **主力用 Gemini** ——免费，质量高，每天 250 次足够
- **备用用 Qwen-VL** ——国内直连，Gemini 挂掉自动顶上

这就是"双引擎 + 自动切换"策略。

---

## 第二章 先理解 Skill 怎么工作

动手写代码之前，花 5 分钟搞懂 Skill 机制，事半功倍。

### 1. 一个 Skill 就两个文件

```
.claude/skills/
└── vision/
    ├── SKILL.md       ← "说明书"：告诉 Claude 什么时候触发
    └── vision.sh      ← "发动机"：真正干活的脚本
```

### 2. SKILL.md —— 决定触发时机

SKILL.md 带一个 YAML 头，三个字段：

```yaml
---
name: vision                    # 技能唯一ID
description: ...                # 最重要！决定何时触发
allowed-tools: Bash(...)        # 安全白名单
---
```

**`description` 最关键**——Claude 靠这句话判断"现在该不该用这个 Skill"。

```yaml
# ✅ 好的 description —— 覆盖各种触发场景
description: Analyze images using Google Gemini vision model
  when the current model lacks multimodal capabilities.

# ❌ 差的 description —— Claude 不知道该什么时候用
description: A tool for images.
```

**`allowed-tools` 是安全白名单**——不在这里的命令，脚本写了也执行不了。

### 3. 为什么用 Shell 而不是 Python？

**零依赖**。Windows 装 Git Bash 就能跑，macOS/Linux 自带 bash。分享给别人不用先配环境。

---

## 第三章 写 Gemini 视觉引擎（主力）

打开终端，开始写。

### 第一步：创建文件

```bash
mkdir -p ~/.claude/skills/vision
touch ~/.claude/skills/vision/vision.sh
chmod +x ~/.claude/skills/vision/vision.sh
```

### 第二步：获取 API Key

打开 [Google AI Studio](https://aistudio.google.com/apikey) → 登录 Google → Create API Key → 复制。

**免费**，每天 250 次。

### 第三步：写脚本头部

```bash
#!/bin/bash
set -euo pipefail

API_KEY="${GEMINI_API_KEY:-你的Key}"
PROXY="${HTTPS_PROXY:-http://127.0.0.1:7897}"
MODEL="${3:-gemini-2.5-flash}"
```

解释：
- `set -euo pipefail`：三个安全开关。出错立即停、未定义变量报错、管道失败算失败
- `${变量:-默认值}`：用户设了环境变量就用用户的，没设用默认值。**开箱即用 + 可覆盖**

### 第四步：读取参数

```bash
if [ $# -lt 1 ]; then
  echo '{"error": "Usage: vision.sh <image_path> [prompt] [model]"}'
  exit 1
fi

IMAGE_FILE="$1"
PROMPT="${2:-Describe this image in detail, including all text visible.}"

# 防御性检查：文件在不在？
if [ ! -f "$IMAGE_FILE" ]; then
  echo "{\"error\": \"File not found: $IMAGE_FILE\"}"
  exit 1
fi
```

第一个参数（图片路径）必须给。第二个（提示词）可选，有默认值。**先检查文件存在，别等到后面才发现**。

### 第五步：识别图片格式

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
  *)        mime="image/png" ;;   # 不认识就当 PNG
esac
```

Gemini API 需要知道图片 MIME 类型（`image/png` 等）。通过扩展名推断，覆盖六种常见格式，不认识的默认 PNG。

`${IMAGE_FILE##*.}` 是 Shell 字符串截取——删掉最后一个 `.` 之前的所有内容，只留扩展名。

### 第六步：图片转 Base64（核心中的核心）

**这是整个脚本最关键的一步，踩坑最多的地方。**

要把图片变成 Base64 字符串嵌到 JSON 里发给 API。但一张 4K 截图的 Base64 可能几百万字符——直接放命令行会触发 **"Argument list too long"** 错误。

**解决**：写到临时文件，让 curl 从文件读。

```bash
TMPDIR="${TMPDIR:-/tmp}"
B64_FILE="${TMPDIR}/vision_b64_$$.txt"         # 放 Base64
PAYLOAD_FILE="${TMPDIR}/vision_payload_$$.json" # 放完整 JSON

# 编码 + 跨平台兼容
base64 -w0 "$IMAGE_FILE" > "$B64_FILE" 2>/dev/null || {
  base64 "$IMAGE_FILE" | tr -d '\n' > "$B64_FILE"
}
```

这段做了**跨平台兼容**：
- Linux（GNU base64）支持 `-w0` 不换行
- macOS（BSD base64）不支持 `-w0`，每 76 字符换行
- 先试 Linux 方式，失败换 macOS 方式（`base64 | tr -d '\n'` 删掉换行）

**`$$` 是当前进程 PID**——用来生成唯一临时文件名，避免多实例互相覆盖。

### 第七步：拼接 JSON（分段写入）

Gemini API 要求的格式：

```json
{"contents":[{"parts":[{"text":"提示词"},{"inline_data":{"mime_type":"image/png","data":"base64数据..."}}]}]}
```

重点：Base64 数据嵌套在 JSON 的 `data` 字段里。不能直接把数据放命令行。所以**分段写入文件**：

```bash
# 第1段：JSON 开头
cat > "$PAYLOAD_FILE" << 'JSONHEAD'
{"contents":[{"parts":[{"text":"
JSONHEAD

# 第2段：转义后的提示词
printf '%s' "$PROMPT" | sed 's/\\/\\\\/g; s/"/\\"/g' >> "$PAYLOAD_FILE"

# 第3段：mime_type
cat >> "$PAYLOAD_FILE" << 'JSONMID'
"},{"inline_data":{"mime_type":"
JSONMID
printf '%s' "$mime" >> "$PAYLOAD_FILE"

# 第4段：data 字段开始
cat >> "$PAYLOAD_FILE" << 'JSONMID2'
","data":"
JSONMID2

# 第5段：大块的 Base64 数据（从文件读，不经过命令行）
cat "$B64_FILE" >> "$PAYLOAD_FILE"

# 第6段：JSON 结尾
cat >> "$PAYLOAD_FILE" << 'JSONFOOT'
"}}]}]}
JSONFOOT
```

**为什么分 6 段？** 每段都很小（几十字符），用 heredoc 直接写文件。只有 Base64 那一段大——但它用 `cat file >> payload`，也是文件到文件，完全不经过命令行。

**第 2 段为什么用 sed？** 提示词里可能有 `"` 或 `\`，直接放 JSON 会破坏结构。sed 把它们转义成 `\"` 和 `\\`。

### 第八步：调 API

```bash
HTTP_CODE=$(curl -s --max-time 120 --connect-timeout 15 \
  -x "$PROXY" \
  -H "Content-Type: application/json" \
  -w "%{http_code}" \
  -o "${TMPDIR}/vision_resp_$$.txt" \
  "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${API_KEY}" \
  -d "@${PAYLOAD_FILE}")
```

curl 参数：

| 参数 | 作用 |
|------|------|
| `-s` | 不输出进度条（输出会被 Claude 读到） |
| `--max-time 120` | 最多等 2 分钟（大图上传+推理慢） |
| `--connect-timeout 15` | 15 秒连不上就放弃 |
| `-x "$PROXY"` | 走代理（国内访问 Google 必须） |
| `-w "%{http_code}"` | 把 HTTP 状态码存到变量 |
| `-d @file` | **从文件读请求体**（不经过命令行） |

### 第九步：输出结果

```bash
# stderr → 给人看的日志
>&2 echo "[vision] HTTP $HTTP_CODE"

# stdout → 给程序读的 JSON（Claude 只读这个）
cat "${TMPDIR}/vision_resp_$$.txt"

# 清理
rm -f "$PAYLOAD_FILE" "$B64_FILE" "${TMPDIR}/vision_resp_$$.txt"
```

**关键设计**：日志和结果分开输出。
- stderr（`>&2`）：`[vision] Encoding test.png...` → 给人看
- stdout：API 返回的原始 JSON → Claude 读

混在一起 Claude 就得从日志里翻 JSON，容易出错。分开就干净了。

### 第十步：写 SKILL.md

```yaml
---
name: vision
description: Analyze images using Google Gemini vision model
  when the current model lacks multimodal capabilities.
allowed-tools: Bash(bash:vision.sh) Bash(cat:*) Bash(base64:*)
---
```

---

## 第四章 写 Qwen-VL 备胎引擎

主力写完了。备用引擎结构几乎一样，我只讲差异。

### 为什么需要备胎？

Gemini 两个可能的故障：
1. 免费额度用完 → HTTP 429
2. 代理挂了 → 网络不通

这两个情况都不会报错给用户——备胎自动顶上。

### 和 Gemini 的核心差异

| | Gemini | Qwen-VL |
|---|---|---|
| API 格式 | Gemini 自己的 | 跟 ChatGPT 一模一样 |
| 图片传递 | `inline_data` + mime_type | Data URL |
| 认证 | URL 参数 `?key=xxx` | Header `Authorization: Bearer xxx` |
| 代理 | **要** | **不要**（国内直连） |

### 图片传递：Data URL

```bash
B64=$(base64 -w0 "$IMAGE_FILE" 2>/dev/null || base64 "$IMAGE_FILE" | tr -d '\n')
DATA_URL="data:$mime;base64,$B64"
```

前端同学应该很熟。格式就是 `data:image/png;base64,<数据>`，一个字符串，放 messages 里。

### Payload 是 OpenAI 格式

```json
{
  "model": "qwen-vl-max",
  "messages": [{
    "role": "user",
    "content": [
      {"type": "image_url", "image_url": {"url": "data:image/png;base64,..."}},
      {"type": "text", "text": "请描述"}
    ]
  }]
}
```

和 ChatGPT API 一模一样。好处是**通用**——以后加 GPT-4V 几乎不用改 Payload。

### 代理是可选的

```bash
CURL_OPTS="-s --max-time 120 --connect-timeout 15"
if [ -n "$PROXY" ]; then
  CURL_OPTS="$CURL_OPTS -x $PROXY"
fi
```

不写死 `-x`，先检查有没有设代理。阿里云国内直连，默认不用走。

### 自动降级怎么实现？

**不需要写额外调度代码**。SKILL.md 里写了：当 Gemini 返回 HTTP 429 或连接失败，Claude 自己去调 backup。它能读 HTTP 状态码，看到 429 就知道切备胎。整个过程用户无感。

---

## 第五章 部署

### 1. 放文件

```
~/.claude/skills/
├── vision/
│   ├── SKILL.md
│   └── vision.sh          # chmod +x
└── vision-backup/
    ├── SKILL.md
    └── vision-backup.sh    # chmod +x
```

不需要安装任何依赖。Claude Code 启动自动发现。

### 2. 配 Key

二选一：

**方式 A：环境变量**
```bash
export GEMINI_API_KEY="你的Key"
export DASHSCOPE_API_KEY="你的Key"
```

**方式 B：改脚本默认值**（分享给别人时推荐）
打开 `vision.sh`，把 `YOUR_GEMINI_API_KEY` 换成真的 Key。

### 3. 测试

```bash
bash ~/.claude/skills/vision/vision.sh "test.png" "这张图里有什么？"
```

看到 `[vision] HTTP 200` 即成功。

### 4. 使用

在 Claude Code 里直接说话：

> "帮我看看 D:\截图\error.png"

自动识别、自动调 Skill、自动返回结果。

---

## 第六章 四个关键技术点

### 1. 大文件：为什么用临时文件

直接放命令行：`curl -d "{\"data\":\"$(base64 img.png)\"}"` → 报错 `Argument list too long`。

操作系统限制单个命令行参数长度（一般 128KB~2MB），4K 截图 Base64 约 500 万字符，远超限制。

**必须写到文件，curl `-d @file` 读。**

### 2. 跨平台：GNU vs BSD

macOS 和 Linux 的 `base64` 不一样。macOS 不支持 `-w0`。

解决：**先试一种，失败用另一种**。

### 3. JSON 转义

用户输入 `"` 或 `\` 会破坏 JSON。必须先转义。

### 4. 超时

连接超时短（15s），整体超时长（120s）。分开设，快失败 + 给足时间。

---

## 第七章 四个我踩过的坑

### 坑 1：Argument list too long

大图编码后 curl 报错。原因：Base64 放命令行参数里。解决：临时文件 + `-d @file`。

### 坑 2：macOS 报 `illegal option -- w`

macOS 的 base64 不支持 `-w0`。原因：BSD 版和 GNU 版参数不一样。解决：兼容处理。

### 坑 3：JSON 解析错误

API 返回 `Invalid JSON`。原因：prompt 里特殊字符没转义。解决：sed 转义后再拼 JSON。

### 坑 4：连不上 Google

curl 超时。原因：国内 Google 被阻断。解决：走 Clash Verge 代理 `-x http://127.0.0.1:7897`。

---

## 第八章 扩展方向

**加第三个引擎**：照抄 backup.sh，改 endpoint 和认证。因为已经是 OpenAI 格式，加 GPT-4V 几乎不用动。

**分析视频**：ffmpeg 抽帧 → vision.sh。

**批量处理**：一个 for 循环。

**场景化 Prompt**：截图自动问 UI，图表自动问数据，照片自动问场景。

---

## 附录

### 文件清单

| 文件 | 说明 |
|------|------|
| `skills/vision/SKILL.md` | Gemini 引擎说明书 |
| `skills/vision/vision.sh` | Gemini API 脚本 |
| `skills/vision-backup/SKILL.md` | Qwen-VL 引擎说明书 |
| `skills/vision-backup/vision-backup.sh` | Qwen-VL API 脚本 |

### 参考资源

- Google AI Studio：`aistudio.google.com/apikey`（免费 Key）
- 阿里云 DashScope：`dashscope.console.aliyun.com`（Qwen-VL Key）
- Gemini 视觉文档：`ai.google.dev/gemini-api/docs/vision`
- Claude Code Skills 文档：`docs.anthropic.com/en/docs/claude-code/skills`
