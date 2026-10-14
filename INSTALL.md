# 安装与首次使用

## 安装

1. 从 GitHub Release 下载 `WorkRhythm-v1.0.0-macOS-universal.zip`。
2. 使用同一 Release 中的 SHA-256 文件校验下载。
3. 解压，将 `WorkRhythm.app` 移入 `/Applications`。
4. 首次打开若被 Gatekeeper 拦截，在 Finder 中右键 App →“打开”并确认。

公开二进制使用 ad-hoc 签名且未经过 Apple 公证。不要关闭 Gatekeeper 或 SIP。

## 首次配置

1. 启动后点击菜单栏圆形图标。
2. 按需允许通知和登录启动。
3. 手动离开可使用：
   - 系统设置中配置为“锁屏”或“使显示器进入睡眠”的触发角；
   - `⌃⌘Q`；
   - Apple 菜单 →“锁定屏幕”。
4. 返回并解锁后，在时间线确认生成一条主动离开记录。
5. 自动锁屏、自然息屏、系统睡眠、屏保和合盖不应生成主动离开。

快捷键和菜单锁屏通过“锁屏前 5 秒内有聚合输入”推断为手动操作。macOS 不提供锁屏入口字段，因此这是启发式规则。

## 从源码构建

```bash
swift test
python3 Tools/generate_project.py
xcodebuild -project WorkRhythm.xcodeproj -scheme WorkRhythm \
  -configuration Release -derivedDataPath /tmp/WorkRhythm-build build
```

最低系统版本 macOS 14，构建产物同时包含 arm64 和 x86_64。

完整功能、隐私和限制见 [README.md](README.md)、[PRIVACY.md](PRIVACY.md) 和 [VALIDATION.md](VALIDATION.md)。
