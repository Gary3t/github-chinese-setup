# 踩坑实录

> 全部来自 2026-10-13 一次真实的 macOS + Chrome 154 排障，耗时约一小时。照这份抄，下次省掉整轮试错。

## 1. 绝不写 `Secure Preferences`（最贵的一课）

**症状**：往 `Secure Preferences` 的扩展条目里加 `user_scripts_allowed: true` → Chrome 的 HMAC 防篡改校验识别出外部修改 → 值被清除、扩展被禁用、**并且扩展的 `Local Extension Settings` 被当成"全新安装"重置清空**，里面装的用户脚本全丢。

**正确做法**：

- 只读不写 `Secure Preferences`。它是判定的**唯一可信来源**，不是配置入口。
- 要动配置，只动 `Preferences`（无 HMAC），且动之前**同时备份这两个文件 + `Local Extension Settings/<扩展ID>` 整个目录**。
- 认命：`user_scripts_enabled` 只能由用户点。

**恢复方式**：备份文件回滚（`cp Secure\ Preferences.bak3 Secure\ Preferences`），但**扩展存储恢复不了**——脚本必须重装。

## 2. macOS 上 `open` 打不开 `chrome://`

`open -a "Google Chrome" "chrome://extensions"` 静默失败。`chrome-extension://` 内部页同样打不开。AppleScript 的 `open location` 和 System Events keystroke 都被 macOS 隐私权限挡死（error -10004）。

**正确做法**：把地址**用文字给用户**，让他粘贴到地址栏。一句话的事，别试三种自动化。

## 3. "配置全绿但页面还是英文"

**原因**：脚本丢了。上一条的连锁反应——扩展被重置时脚本一起清空，此时开关开了、扩展启用了，**屋里却没人**。

**判定**：看扩展存储目录大小。

```bash
du -sh ~/Library/Application\ Support/Google/Chrome/Default/Local\ Extension\ Settings/<扩展ID>
```

正常是 MB 级（脚本本体存在这里）；缩到几 KB 就是空的。

```bash
strings .../000003.log | grep -oE '"scripts":[0-9]+'   # 0 = 没脚本
```

**修复**：重装脚本。装完**重新验收页面**，不要只看配置。

## 4. 中途重启 Chrome 不解决问题

如果闸本身是关的，重启一百次也没用。**重启只对"权限已改但进程未重载"有效**，不要把它当成万能药。

## 5. Chrome 138 迁移的时间窗

官方博客明确：138 首次启动时开发者模式若已开，会为**当时已装的扩展**自动打开新开关。迁移之后新装的扩展默认是关的。

所以：**开发者模式开着 ≠ 开关开着**。查 `user_scripts_enabled` 的实际值，别靠推断。

## 6. 界面语言会坑你的选择器

如果系统语言是中文，Chrome/Blender 等应用的界面元素和默认命名会本地化。按英文名查找（如 `"Principled BSDF"`、菜单项文本）会全部扑空。

**正确做法**：按**类型 / ID / role** 定位，不按显示名。

## 7. 别把外部扩展声明和商店安装混为一谈

`External Extensions/<id>.json` 只对**商店扩展**有效（`external_update_url` 指向 `clients2.google.com`）。自签名 crx 的 `update_url` **不允许 `file://`**，想走这条路得常驻一个本地服务——比点两下脆得多，不划算。

## 8. 验收必须看屏幕

配置值全对不代表页面生效。**最后一步一定要截屏确认**，否则会出现"我这边显示全部成功，用户那边还是英文"的尴尬。

## 9. 标签页别丢

退出 Chrome 前把当前标签页 URL 提取出来（`Sessions/` 目录下 `Tabs_*` / `Session_*`，UTF-16LE 或 UTF-8 编码，正则捞 `https?://`），重启后重新 `open` 回去。用户会记得你弄丢了他的标签页。

## 10. 别碰的自动化尝试（已验证失败，勿重试）

| 尝试 | 结果 |
|---|---|
| 写 `Secure Preferences` 开关值 | HMAC 失败，扩展被禁 + 存储被清 |
| CDP / `--remote-debugging-port` 接管默认 profile | Chrome 136+ 已禁用 |
| AppleScript 点击 / 输入 `chrome://` 页面 | -10004 无权限 |
| `open` 命令打开 `chrome://` 或 `chrome-extension://` | 静默失败 |
| 从 Chrome 二进制里 grep 出开关的真实键名 | 字符串被内部压缩，挖不出（最后是从用户点完后 diff 配置拿到的） |
