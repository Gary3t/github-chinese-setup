#!/usr/bin/env python3
"""
Chrome 用户脚本状态诊断。

用法:
    python3 diagnose.py                       # 查篡改猴
    python3 diagnose.py <扩展ID> [扩展ID...]   # 查指定扩展

跨平台: macOS / Windows / Linux。只用标准库。
退出码: 0 = 全部就绪; 1 = 有未完成项。
"""

import json
import os
import platform
import re
import subprocess
import sys
import glob

TAMPERMONKEY = "dhdgffkkebhmkfjojejmpbldmpobfkfo"

CHROME_BINARIES = {
    "Darwin": [
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Google Chrome Beta.app/Contents/MacOS/Google Chrome Beta",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
    ],
    "Windows": [
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    ],
    "Linux": ["/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser"],
}


def chrome_version():
    for b in CHROME_BINARIES.get(platform.system(), []):
        if os.path.exists(b):
            try:
                out = subprocess.run([b, "--version"], capture_output=True, text=True, timeout=15)
                txt = (out.stdout or out.stderr).strip()
                m = re.search(r"(\d+)\.", txt)
                return txt, (int(m.group(1)) if m else None)
            except Exception:
                return "(无法执行)", None
    return "(未找到 Chrome)", None


def user_data_dirs():
    s = platform.system()
    if s == "Darwin":
        base = os.path.expanduser("~/Library/Application Support/Google/Chrome")
    elif s == "Windows":
        base = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Google", "Chrome", "User Data")
    else:
        base = os.path.expanduser("~/.config/google-chrome")
    if not os.path.isdir(base):
        return []
    out = []
    for name in os.listdir(base):
        if name == "Default" or name.startswith("Profile "):
            if os.path.isfile(os.path.join(base, name, "Preferences")):
                out.append(os.path.join(base, name))
    return sorted(out)


def load_json(path):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return json.load(f)
    except Exception:
        return None


def storage_dirs(profile, ext_id):
    """扩展的本地存储目录（Local Extension Settings 就在 profile 目录内）"""
    return [
        os.path.join(profile, "Local Extension Settings", ext_id),
        os.path.join(profile, "Sync Extension Settings", ext_id),
        os.path.join(profile, "IndexedDB", ext_id),
    ]


def storage_size(profile, ext_id):
    total = 0
    for c in storage_dirs(profile, ext_id):
        if os.path.isdir(c):
            for dirpath, _, files in os.walk(c):
                for fn in files:
                    try:
                        total += os.path.getsize(os.path.join(dirpath, fn))
                    except OSError:
                        pass
    return total


def storage_has(profile, ext_id, needles):
    """在扩展存储里搜关键词，判断脚本是否在库"""
    d = os.path.join(profile, "Local Extension Settings", ext_id)
    hits = {}
    if not os.path.isdir(d):
        return hits
    blob = []
    for fn in os.listdir(d):
        p = os.path.join(d, fn)
        if not os.path.isfile(p):
            continue
        try:
            with open(p, "rb") as f:
                raw = f.read()
            blob.append(raw.decode("utf-8", errors="ignore"))
            blob.append(raw.decode("utf-16-le", errors="ignore"))
        except OSError:
            pass
    joined = "\n".join(blob)
    for n in needles:
        c = joined.count(n)
        if c:
            hits[n] = c
    return hits


def main():
    ext_ids = sys.argv[1:] or [TAMPERMONKEY]
    ver_txt, major = chrome_version()

    print("=" * 62)
    print("Chrome 用户脚本状态诊断")
    print("=" * 62)
    print(f"Chrome: {ver_txt}")
    if major:
        need_switch = major >= 138
        print(f"版本分支: {'≥138 → 需要「允许用户脚本」开关' if need_switch else '<138 → 开发者模式即可'}")

    profiles = user_data_dirs()
    if not profiles:
        print("\n未找到 Chrome 用户数据目录。")
        return 1

    print(f"配置文件: {len(profiles)} 个")

    all_ok = True
    for prof in profiles:
        prefs = load_json(os.path.join(prof, "Preferences")) or {}
        secure = load_json(os.path.join(prof, "Secure Preferences")) or {}

        # 扩展设置以 Secure Preferences 为准
        sset = ((secure.get("extensions") or {}).get("settings") or {}) or \
               ((prefs.get("extensions") or {}).get("settings") or {})

        names = []
        for _k, v in sset.items():
            nm = ((v.get("manifest") or {}).get("name") or "").lstrip("_")
            if re.fullmatch(r"__MSG_.*__", nm or ""):
                nm = "(本地化名称)"
            names.append((nm or "?", v.get("disable_reasons")))
        print("-" * 62)
        print(f"[{os.path.basename(prof)}] 扩展总数: {len(sset)}")
        for nm, dr in names:
            flag = "启用" if dr in (None, []) else f"停用{dr}"
            print(f"    {str(nm)[:44]:46s} {flag}")

        for eid in ext_ids:
            v = sset.get(eid)
            print()
            print(f"  >>> 目标扩展 {eid[:16]}…")
            if not v:
                print("      [ ] 未安装 —— 需要写 External Extensions 声明或手动安装")
                all_ok = False
                continue

            man = v.get("manifest") or {}
            dr = v.get("disable_reasons")
            enabled = dr in (None, [])
            ue = v.get("user_scripts_enabled")
            patterns = v.get("persistent_script_url_patterns")
            size = storage_size(prof, eid)

            print(f"      [{'x' if enabled else ' '}] 扩展已启用"
                  + ("" if enabled else f"  (disable_reasons={dr})"))
            print(f"      [{'x' if ue else ' '}] 允许用户脚本 (user_scripts_enabled={ue})")
            print(f"          注入范围: {patterns if patterns else '(未注册)'}")
            print(f"          版本: {man.get('version')}")
            print(f"          存储体积: {size / 1024:.0f} KB"
                  + ("   << 疑似为空，脚本可能已丢失" if size < 50 * 1024 else ""))

            hits = storage_has(prof, eid, ["435208", "github-chinese", "GitHub 中文化",
                                           "greasyfork", "Tampermonkey", "userscript"])
            print("          存储命中: " + (str(hits) if hits else "(无脚本痕迹)"))

            if not (enabled and ue and size > 50 * 1024):
                all_ok = False

    print("=" * 62)
    print("结论: " + ("全部就绪 ✅" if all_ok else "存在未完成项 ❌ 见上方 [ ] 标记"))
    if not all_ok:
        print("提醒: 需要人工点击的步骤无法自动化，请按 SKILL.md 阶段 3 的指引操作。")
    print("提醒: 配置全对 ≠ 页面生效，最后务必截屏确认。")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
