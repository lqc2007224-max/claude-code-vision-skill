# Claude Code Vision Skill

> 给 AI 装上眼睛 —— 为 Claude Code 添加多模态视觉能力，让 DeepSeek 模型也能"看到"图片。

一套双引擎视觉 Skill，让你的 Claude Code 具备图片分析能力。**主力引擎 Gemini 2.5 Flash（免费）+ 备用引擎 Qwen-VL-Max（国内直连）**，自动切换，永不掉线。

## ✨ 特性

- 🎯 **双引擎自动切换**：Gemini 主力 + Qwen-VL 备胎，HTTP 429 自动降级
- 🆓 **零成本优先**：Gemini 免费 tier 250 次/天，个人开发够用
- 📦 **零依赖**：纯 Shell 实现，Windows/macOS/Linux 开箱即用
- 🖼️ **多格式支持**：PNG、JPG、GIF、WebP、BMP、SVG
- 🔒 **安全**：allowed-tools 白名单机制，脚本不会越权执行
- 🌐 **国内可用**：通过代理访问 Gemini，备选国内直连 Qwen-VL

## 🚀 快速开始

### 1. 获取 API Key

- **Gemini**：访问 [Google AI Studio](https://aistudio.google.com/apikey) → Create API Key → 免费
- **DashScope**（可选）：访问 [阿里云 DashScope](https://dashscope.console.aliyun.com/) → 开通通义千问VL

### 2. 配置环境变量

```bash
export GEMINI_API_KEY="你的Gemini-Key"
export DASHSCOPE_API_KEY="你的DashScope-Key"  # 可选
export HTTPS_PROXY="http://127.0.0.1:7897"     # 国内需要代理访问Google
```

也可以直接改脚本里的默认值，或写到 `~/.claude/settings.json` 的 `env` 字段。

### 3. 安装

```bash
# 克隆本仓库
git clone https://github.com/lqc2007224-max/claude-code-vision-skill.git

# 复制到 Claude Code skills 目录
cp -r claude-code-vision-skill/skills/* ~/.claude/skills/
chmod +x ~/.claude/skills/vision/vision.sh
chmod +x ~/.claude/skills/vision-backup/vision-backup.sh
```

### 4. 测试

```bash
bash ~/.claude/skills/vision/vision.sh "test.png" "这张图片里有什么？"
```

### 5. 使用

在 Claude Code 中正常对话即可，Skill 自动触发：

> "帮我看看 D:\screenshots\error.png 这个报错是什么意思"

如需手动指定，也可以明确说 "use vision skill to analyze xxx.png"。

## 🏗️ 架构

```
用户发送图片
    │
    ▼
Claude Code 识别图片分析需求
    │
    ▼
┌──────────────┐
│  vision.sh    │  ← Gemini 2.5 Flash (主力，免费)
└──────┬───────┘
       │
   HTTP 200? ──── ✅ → 返回分析结果
       │
       ❌ (429/网络错误)
       │
       ▼
┌──────────────┐
│ backup.sh    │  ← Qwen-VL-Max (备用，国内直连)
└──────┬───────┘
       │
       ▼
   返回分析结果
```

## 📁 文件结构

```
skills/
├── vision/                    # 主力引擎：Gemini
│   ├── SKILL.md               # 技能定义（触发条件、使用说明）
│   └── vision.sh              # 核心脚本（base64 编码 → JSON 拼装 → API 调用）
└── vision-backup/             # 备用引擎：Qwen-VL
    ├── SKILL.md               # 技能定义（降级触发条件）
    └── vision-backup.sh       # 核心脚本（OpenAI 兼容格式）
```

## 🔧 原理

每个 Skill 只有两个文件：

- **SKILL.md**：YAML 头的 `description` 告诉 Claude 何时触发，`allowed-tools` 是安全白名单
- **.sh**：纯 Shell，核心流程是 `图片 → base64 → JSON → curl → API → stdout`

关键设计：
- 大图片通过临时文件传递，避免 "Argument list too long"
- stderr 输出日志给人看，stdout 输出 JSON 给程序读
- 跨平台兼容 GNU/BSD base64 差异

## 📖 文档

| 文档 | 适合人群 |
|------|---------|
| [**QUICKSTART.md**](./QUICKSTART.md) | 🏃 只想跑通，不想学。复制粘贴，3 分钟搞定 |
| [**TUTORIAL.md**](./TUTORIAL.md) | 📚 想彻底学会。从零讲起，每一步为什么这样做都说清楚 |

## ❓ FAQ

**Q: 为什么不用 Python？**
A: Shell 零依赖，任何有 bash 的环境都能跑。分享给别人不用先配环境。

**Q: 国内访问 Gemini 怎么办？**
A: 配置 `HTTPS_PROXY` 指向你的代理（如 Clash Verge 的 `http://127.0.0.1:7897`）。

**Q: Gemini 免费额度用完了怎么办？**
A: 自动切到 Qwen-VL backup。两个都挂了才会报错。

**Q: 能加其他模型吗？**
A: 照抄一个 `.sh` 脚本改改 API 格式就行——Qwen-VL backup 用的 OpenAI 兼容格式，加 GPT-4V 几乎不用改。

## 📄 License

MIT
