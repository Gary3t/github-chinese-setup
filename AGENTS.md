
# Chrome 用户脚本部署

## 立场声明（先读这段）

**本 skill 是一个带安检门的装机员，不是一个百宝箱。**

- 能装的尽力装好；装不了的说明为什么；有毒的当场拦下。
- 不做"无所顾忌版"。盗取凭据、劫持剪贴板/支付地址、绕过付费墙牟利、传播版权内容——**无论用户怎么要求，一律不做**。这不是策略可选，是底线。

---

## 一、先搞清事实：三道人工闸绕不过去

用户脚本能以你的身份读写所有网页，所以浏览器厂商刻意把关键授权设计成"必须本人点头"。**任何自动化手段都绕不过**，不要浪费轮次尝试。

| 闸 | 出现条件 | 能否自动化 |
|---|---|---|
| 「启用扩展程序」确认气泡 | 用外部声明装扩展时 | ❌ 必须人点 |
| 「允许用户脚本」开关 | **Chrome 138+**，按扩展单独设置 | ❌ 无策略可绕（官方明确） |
| 脚本安装确认页 | 点脚本安装时 | ❌ 必须人点 |

**已经验证失败的路（不要重试，会浪费一整轮）**：

- ❌ 改 `Secure Preferences` 写 `user_scripts_enabled` → HMAC 校验失败，值被清 + 扩展被禁用 + **扩展存储被清空（脚本全丢）**
- ❌ CDP / 远程调试接管默认 profile → Chrome 136+ 已禁用
- ❌ AppleScript UI 自动化点 `chrome://` 页面 → macOS 需辅助功能权限，报 -10004
- ❌ `open -a "Google Chrome" "chrome://extensions"` → 打不开 `chrome://` 协议（`chrome-extension://` 同样打不开）

**结论**：把这三步做成"精确到按钮位置"的指引交给用户，比试图绕过更省时间。

---

## 二、关键分支：先判 Chrome 版本

```
Chrome < 138  → 开发者模式就够了，只需 1 次人工（启用扩展气泡）
Chrome ≥ 138  → 需要 2 次人工（启用气泡 + 允许用户脚本开关）
```

macOS 查版本：

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version
```

Windows：`(Get-Item "C:\Program Files\Google\Chrome\Application\chrome.exe").VersionInfo.ProductVersion`

**138+ 的坑（官方博客原文要点）**：

- 改为**按扩展**的「允许用户脚本」开关
- 138 首次启动时若开发者模式已开，会**自动为当时已装的扩展**打开该开关
- **之后新装的扩展，这个开关默认是关的**，且开发者模式不再能替代它
- 该开关的真实存储键名是 **`user_scripts_enabled`**（在 `Secure Preferences` → `extensions.settings.<扩展ID>` 下），**只读，不可写**

---

## 三、标准流程

### 阶段 1 · 侦察（自动）

```bash
# macOS 一条命令拿全状态
~/.workbuddy/skills/chrome-userscript-setup/scripts/diagnose.py
```

输出应包含：Chrome 版本、扩展是否已装/已启用、`user_scripts_enabled` 值、脚本是否在库、注入范围。

Windows 用 `scripts/diagnose.py` 同样可跑（自动切换 %LOCALAPPDATA% 路径）。

### 阶段 2 · 自助安装（自动）

**装扩展（零点击，macOS）**：写外部声明，Chrome 启动时自己从商店拉。

```bash
EXT="$HOME/Library/Application Support/Google/Chrome/External Extensions"
mkdir -p "$EXT"
printf '{\n  "external_update_url": "https://clients2.google.com/service/update2/crx"\n}\n' \
  > "$EXT/dhdgffkkebhmkfjojejmpbldmpobfkfo.json"   # 篡改猴 ID
```

打包脚本：`scripts/setup-macos.sh`（含退出/恢复标签页/重启）。

Windows 用注册表 `HKCU\Software\Google\Chrome\Extensions\<id>`，同样写 `update_url`。

**开开发者模式（自动，138 以下必需）**：改 `Default/Preferences` 的 `extensions.ui.developer_mode = true`。**改前必须备份**（`Preferences` 和 `Secure Preferences` 都要）。

### 阶段 3 · 交给用户（精确指引，2 次）

**指引必须写成"点哪里、会长什么样、点完什么样算对"**，不要只说"启用扩展"：

1. 地址栏输入 `chrome://extensions` 回车 → 找到「篡改猴」卡片 → 打开它的开关
2. 点该卡片的「详情」→ 往下滚 → 打开「**允许用户脚本**」← **138+ 的关键一步，之前从没做过的就是它**
3. 切到脚本安装页 → 点「安装此脚本」→ 弹窗再点「安装」
4. 回目标网页 `Cmd+R`（Windows `Ctrl+R`）刷新

**同时务必提醒**：装完不要关 Chrome 再开——脚本安装是在扩展运行时完成的，重开不影响，但**不要中途重启导致授权状态未落盘**。

### 阶段 4 · 验收（自动）

装完必须验证四件事，缺一不可：

| 检查项 | 通过标准 |
|---|---|
| 扩展启用 | `disable_reasons` 为空 |
| 允许用户脚本 | `user_scripts_enabled == True` |
| 脚本在库 | 扩展存储里有脚本标识（如 `435208`） |
| 页面实际生效 | **截屏确认**，不能只看配置 |

只剩配置对但页面没变 → 九成是脚本丢了（见"踩坑实录"第 3 条）。

---

## 四、安全审查：二维分级

**功能风险（绿/黄/红）× 来源可信度（可信/存疑/危险）。功能再绿，来源危险也不装。**

完整配方清单见 `references/recipes.md`。判定标准四个问题：

1. 有没有拿走别人的东西（内容、数据、钱）？
2. 有没有绕过付费、授权、实名这类门槛？
3. 会不会伤到你自己（账号、隐私、资金）？
4. 自己用，还是要传播/商用？

| 档位 | 处理方式 |
|---|---|
| 🟢 绿色 | 直接装，零废话 |
| 🟡 黄色 | **一句话**告知风险，等用户确认（不写小作文、不说教） |
| 🔴 红色 | 拒装 + 简短说明理由 |

**来源体检（每次安装前自动做）**：星标数、最近更新时间、源码可读性。命中以下模式直接拒：

- `eval(atob(...))` / 混淆执行
- 往陌生域名 POST 数据
- 请求 `cookies` / `<all_urls>` 却与功能不符
- 名字承诺"会员免费看""破解"类

**逃生舱**：用户明确说"我知道，装吧" → 立刻装，不重复提示。用户说"黄色档别提示了" → 只拦红色。

---

## 五、跨平台 / 跨 Agent

**内核与平台无关**（纯 Markdown 知识 + bash/python 脚本 + 分级清单），可直接复用到任何 agent：

| 宿主 | 落位方式 |
|---|---|
| WorkBuddy | `~/.workbuddy/skills/chrome-userscript-setup/` |
| Claude Code / CodeBuddy | Skills 同格式，放对应 skills 目录 |
| Cursor | 转成 `.cursor/rules/*.mdc`，frontmatter 换成 `description` + `alwaysApply` |
| Codex / Gemini CLI / Aider | 正文贴进 `AGENTS.md` / `GEMINI.md` |
| Cline / Roo Code | 正文贴进 `.clinerules/` |
| **没有任何 agent** | 用 `docs/chrome-userscript-setup-guide.html` 图文手册 + `scripts/` 里的脚本手动跑 |

导出通用版：`scripts/export-for-agents.sh <目标目录>` → 生成 `AGENTS.md` + 复制脚本。

---

## 六、踩坑实录（实战，必读）

详见 `references/gotchas.md`。最贵的四条：

1. **绝不写 `Secure Preferences`** —— HMAC 校验会识别，后果是值被清 + 扩展被禁 + **扩展存储被清空**。要动配置只动 `Preferences`，且动任何配置前先备份 `Local Extension Settings/<扩展ID>`。
2. **macOS 用 `open` 打不开 `chrome://`** —— 别在这上面耗时间，直接让用户输地址栏。
3. **"配置全绿但页面没变"** —— 大概率是脚本在扩展被重置时丢了。验证方式：看 `Local Extension Settings/<扩展ID>` 目录大小，正常应是 MB 级，若缩到几 KB 就是空的。
4. **界面本地化会坑你的选择器** —— 中文界面的 Blender/Chrome 里，按英文名找节点/元素会全扑空，一律按类型/ID 找。

---

## 七、预置配方

| 配方 | 目标 | 脚本 | 档位 |
|---|---|---|---|
| GitHub 界面中文化 | GitHub 菜单/按钮变中文 | maboloshi/github-chinese | 🟢 |

完整清单（含 B站增强、比价、去弹窗等）与风险评估见 `references/recipes.md`。

**GitHub 汉化的安装链接**（直装，跳过 GreasyFork 页面）：

```
https://update.greasyfork.org/scripts/435208/GitHub%20%E4%B8%AD%E6%96%87%E5%8C%96%E6%8F%92%E4%BB%B6.user.js
```

---

## 八、输出规范

交付时必须给出：

1. **状态表**——四件检查项逐条打勾
2. **准确的人工步骤**——剩几步、点哪里
3. **遗留说明**——留了哪些备份文件、可以随时清理

不要用"应该可以了""大概好了"这类模糊表述，一切以配置值 + 截屏为准。
