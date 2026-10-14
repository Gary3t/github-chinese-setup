#!/usr/bin/env bash
# 把本 skill 导出成"任何 agent 都能用"的通用形态。
#
# 用法:
#   ./export-for-agents.sh <目标目录>
#
# 产出:
#   <目标目录>/AGENTS.md          去掉 frontmatter 的正文（Codex / Gemini CLI /
#                                 Aider / Cline / Cursor 都能直接读）
#   <目标目录>/GEMINI.md
#   <目标目录>/userscript-setup/  脚本与参考资料副本
#   <目标目录>/README.txt         怎么用

set -euo pipefail

DEST="${1:-}"
if [ -z "$DEST" ]; then
  echo "用法: $0 <目标目录>" >&2
  exit 1
fi

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$DEST/userscript-setup"

# 1. 正文（去掉 YAML frontmatter）
awk 'NR==1 && $0=="---" {infm=1; next} infm && $0=="---" {infm=0; next} !infm {print}' \
  "$SRC/SKILL.md" > "$DEST/AGENTS.md"

cp "$DEST/AGENTS.md" "$DEST/GEMINI.md"

# 2. 脚本与资料
cp -R "$SRC/scripts" "$DEST/userscript-setup/"
cp -R "$SRC/references" "$DEST/userscript-setup/"
chmod +x "$DEST/userscript-setup/scripts/"*.sh "$DEST/userscript-setup/scripts/"*.py 2>/dev/null || true

# 3. 使用说明
cat > "$DEST/README.txt" <<'EOF'
Chrome 用户脚本部署 —— 通用形态
================================

这里的内容不依赖任何特定 agent，可以被下列任一方式使用：

  Claude Code / CodeBuddy   → 把本目录当 skills 目录，或直接把 AGENTS.md 内容
                              贴进项目说明
  Cursor                    → 新建 .cursor/rules/userscripts.mdc，
                              frontmatter 写 description + alwaysApply: true，
                              正文用 AGENTS.md
  Codex / Gemini CLI / Aider→ 读 AGENTS.md / GEMINI.md（放在仓库根目录即可）
  Cline / Roo Code          → 复制到 .clinerules/
  没有任何 agent            → 看 AGENTS.md 当操作手册，手动跑下面的脚本

脚本
----
  userscript-setup/scripts/diagnose.py      状态诊断（macOS / Windows / Linux）
  userscript-setup/scripts/setup-macos.sh   macOS 半自动部署

  诊断:  python3 userscript-setup/scripts/diagnose.py
  部署:  bash userscript-setup/scripts/setup-macos.sh

注意
----
无论交给谁执行，最后都有 2~3 步必须由本人点击（浏览器安全设计，绕不过去）。
脚本会把该点哪里打印清楚。
EOF

echo "已导出到: $DEST"
ls -1 "$DEST"
