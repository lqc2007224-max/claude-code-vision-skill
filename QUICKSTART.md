# 快速上手：3 分钟跑通视觉 Skill

> 不想看原理？照做就行。复制 → 粘贴 → 回车 → 搞定。

---

## 前提

- 装了 Claude Code
- 系统有 Git Bash（Windows）或 bash（macOS/Linux）
- 开着代理（Clash Verge 默认 `127.0.0.1:7897`）

---

## 第一步：拿 API Key（3 分钟）

### Gemini Key（主力，免费）

1. 浏览器打开 https://aistudio.google.com/apikey
2. 登录 Google 账号 → **Create API Key**
3. 复制保存

### DashScope Key（备用，可选但推荐）

1. 浏览器打开 https://dashscope.console.aliyun.com/
2. 开通"模型服务" → 找到"通义千问VL"
3. 复制 API Key

---

## 第二步：安装（1 分钟）

```bash
# 克隆仓库
git clone https://github.com/lqc2007224-max/claude-code-vision-skill.git

# 复制到 Claude Code skills 目录
mkdir -p ~/.claude/skills
cp -r claude-code-vision-skill/skills/* ~/.claude/skills/
chmod +x ~/.claude/skills/vision/vision.sh
chmod +x ~/.claude/skills/vision-backup/vision-backup.sh

# 配置 API Key（二选一）
# 方式 A：环境变量
export GEMINI_API_KEY="你的Gemini-Key"
export DASHSCOPE_API_KEY="你的DashScope-Key"

# 方式 B：直接改脚本里的默认值
# 编辑 ~/.claude/skills/vision/vision.sh
# 把 YOUR_GEMINI_API_KEY 换成你的 Key
# 编辑 ~/.claude/skills/vision-backup/vision-backup.sh
# 把 YOUR_DASHSCOPE_API_KEY 换成你的 Key
```

---

## 第三步：跑通测试（30 秒）

```bash
# 找一张测试图片（任意 PNG/JPG 都行）
bash ~/.claude/skills/vision/vision.sh "test.png" "这张图里有什么？"
```

看到 `[vision] HTTP 200` 就是成功了。

---

## 第四步：在 Claude Code 里用

直接正常对话，Claude 自动识别：

> "帮我看看 D:\截图\error.png 里有什么"

---

## 故障排查

| 症状 | 原因 | 解决 |
|------|------|------|
| `HTTP 429` | Gemini 今日免费额度用完 | 等明天，或手动调 backup：`bash vision-backup.sh test.png` |
| `Failed to connect` | 代理没开 | 检查 Clash Verge 是否运行，端口是否 7897 |
| `File not found` | 图片路径写错了 | 用绝对路径，比如 `D:\pics\test.png` |
| `command not found` | 没装 bash | Windows 装 Git Bash，macOS/Linux 自带 |
