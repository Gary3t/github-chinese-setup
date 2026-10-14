#!/usr/bin/env bash
# Chrome 用户脚本环境部署（macOS，半自动）
#
# 用法:
#   ./setup-macos.sh                 # 交互式（会确认后再退出 Chrome）
#   ./setup-macos.sh --yes           # 跳过确认
#   ./setup-macos.sh --check         # 只诊断，不改动任何东西
#
# 安全约定（必读）:
#   * 全程只写 Preferences，绝不写 Secure Preferences（写了会被 HMAC 校验清掉并禁用扩展）
#   * 退出 Chrome 前会备份 Preferences 并记录当前标签页
#   * Chrome 138+ 的那道「允许用户脚本」开关无法自动化，脚本会打印精确指引

set -uo pipefail

EXT_ID="dhdgffkkebhmkfjojejmpbldmpobfkfo"   # 篡改猴
SCRIPT_URL="https://update.greasyfork.org/scripts/435208/GitHub%20%E4%B8%AD%E6%96%87%E5%8C%96%E6%8F%92%E4%BB%B6.user.js"
CHROME_APP="/Applications/Google Chrome.app"
CHROME_BIN="$CHROME_APP/Contents/MacOS/Google Chrome"
USER_DATA="$HOME/Library/Application Support/Google/Chrome"
EXT_DECL="$USER_DATA/External Extensions"
PROFILE="$USER_DATA/Default"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say()  { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*"; }

MODE="run"
case "${1:-}" in
  --yes)   MODE="yes" ;;
  --check) MODE="check" ;;
esac

# ---------- 0. 诊断 ----------
step "环境诊断"
if [ -x "$CHROME_BIN" ]; then
  VER="$("$CHROME_BIN" --version 2>/dev/null)"
  VER_NUM="$(printf '%s' "$VER" | grep -oE '[0-9]+' | head -1)"
  say "Chrome: $VER"
  if [ "${VER_NUM:-0}" -ge 138 ]; then
    NEED_SWITCH=1
    say "分支: >=138 → 必须打开「允许用户脚本」开关（下一步无法自动化）"
  else
    NEED_SWITCH=0
    say "分支: <138 → 开发者模式即可，无需额外开关"
  fi
else
  warn "未找到 Chrome，退出。"
  exit 1
fi

if command -v python3 >/dev/null 2>&1 && [ -f "$HERE/diagnose.py" ]; then
  say ""
  python3 "$HERE/diagnose.py" "$EXT_ID" | tail -12
fi

if [ "$MODE" = "check" ]; then
  say ""
  say "只做诊断，未改动任何文件。"
  exit 0
fi

# ---------- 1. 外部扩展声明（让 Chrome 自己从商店拉） ----------
step "写入外部扩展声明（零点击安装扩展）"
mkdir -p "$EXT_DECL"
printf '{\n  "external_update_url": "https://clients2.google.com/service/update2/crx"\n}\n' \
  > "$EXT_DECL/$EXT_ID.json"
say "已写入: $EXT_DECL/$EXT_ID.json"

# ---------- 2. 开发者模式（只动 Preferences） ----------
step "备份配置"
STAMP="$(date +%Y%m%d-%H%M%S)"
[ -f "$PROFILE/Preferences" ] && cp "$PROFILE/Preferences" "$PROFILE/Preferences.bak-$STAMP" \
  && say "已备份 Preferences.bak-$STAMP"

step "开启开发者模式（仅写 Preferences，无 HMAC）"
python3 - "$PROFILE/Preferences" <<'PY'
import json, os, sys
p = sys.argv[1]
if not os.path.isfile(p):
    print("Preferences 不存在，跳过")
    raise SystemExit(0)
d = json.load(open(p, encoding="utf-8", errors="ignore"))
d.setdefault("extensions", {}).setdefault("ui", {})["developer_mode"] = True
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False)
print("developer_mode = True")
PY

# ---------- 3. 记录当前标签页 ----------
step "记录当前标签页（重启后恢复）"
TABS_FILE="/tmp/chrome_tabs_$STAMP.txt"
python3 - "$PROFILE" "$TABS_FILE" <<'PY'
import glob, os, re, sys
prof, out = sys.argv[1], sys.argv[2]
files = sorted(glob.glob(os.path.join(prof, "Sessions", "Tabs_*"))) + \
        sorted(glob.glob(os.path.join(prof, "Sessions", "Session_*")))
pat = re.compile(r"https?://[^\x00-\x1f\"'<>\\\s]{8,160}")
skip = ("gstatic", "googleusercontent", "clients2.google", "schemas.",
        "w3.org", "googleapis.com/oauth", "127.0.0.1", "localhost")
seen, urls = set(), []
for f in files[-4:]:
    raw = open(f, "rb").read()
    for enc in ("utf-16-le", "utf-8"):
        for u in pat.findall(raw.decode(enc, errors="ignore")):
            u = u.split("\x00")[0].rstrip("\x00")
            if u in seen or any(s in u for s in skip):
                continue
            seen.add(u)
            urls.append(u)
open(out, "w").write("\n".join(urls[-20:]))
print(f"已记录 {len(urls[-20:])} 个标签页 -> {out}")
PY

# ---------- 4. 确认 ----------
if [ "$MODE" != "yes" ]; then
  printf '\n即将退出 Chrome 并重新打开（标签页已记录，稍后恢复）。继续? [y/N] '
  read -r ans </dev/tty || ans="n"
  case "$ans" in y|Y|yes|YES) ;; *) say "已取消。"; exit 0 ;; esac
fi

# ---------- 5. 重启 Chrome ----------
step "退出 Chrome"
osascript -e 'tell application "Google Chrome" to quit' >/dev/null 2>&1 || true
for _ in $(seq 1 12); do pgrep -x "Google Chrome" >/dev/null || break; sleep 1; done
if pgrep -x "Google Chrome" >/dev/null; then
  pkill -x "Google Chrome"; sleep 3
fi
pgrep -x "Google Chrome" >/dev/null && warn "Chrome 仍在运行，请手动退出后重试" || say "已退出"

step "重新打开"
open -a "$CHROME_APP" "https://github.com" "$SCRIPT_URL" >/dev/null 2>&1 \
  && say "已打开 GitHub + 脚本安装页"

if [ -s "$TABS_FILE" ]; then
  while IFS= read -r u; do
    [ -n "$u" ] && open -a "$CHROME_APP" "$u" >/dev/null 2>&1
  done < "$TABS_FILE"
  say "标签页已恢复"
fi

# ---------- 6. 人工步骤 ----------
cat <<EOF

──────────────────────────────────────────────────────────
接下来只能靠你点（浏览器安全设计，任何程序都绕不过）：

  1. 地址栏输入  chrome://extensions  回车
  2. 找到「篡改猴」卡片 → 打开开关（若弹出「启用扩展程序」就点它）
EOF

if [ "${NEED_SWITCH:-0}" -eq 1 ]; then
cat <<EOF
  3. 点「篡改猴」卡片上的「详情」→ 往下滚
     → 打开「允许用户脚本」    << 你那版 Chrome 的关键一步
EOF
fi

cat <<EOF
  4. 切到脚本安装页 → 点「安装此脚本」→ 弹窗点「安装」
  5. 回 GitHub 按 Cmd+R 刷新

点完执行验收:
  python3 "$HERE/diagnose.py"

提醒: 配置全对不等于页面生效，务必看一眼 GitHub 是不是中文了。
──────────────────────────────────────────────────────────
EOF
