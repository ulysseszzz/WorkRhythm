# WorkRhythm v1.0.0

首个公开版本。

## 主要功能

- 原生 macOS 菜单栏工作节奏时间线
- 触发角、`⌃⌘Q` 和 Apple 菜单手动锁屏的主动离开识别
- 小时色块、倒序明细、日/周/月统计
- 与离开、锁屏、合盖和睡眠联动的专注计时
- 六类饮品、四档容量滑杆和十二种花园配方
- 本地 SQLite、备份、CSV 和诊断导出

## 安装

1. 下载 `WorkRhythm-v1.0.0-macOS-universal.zip`。
2. 对照 `WorkRhythm-v1.0.0-SHA256.txt` 校验文件。
3. 解压并将 `WorkRhythm.app` 移入 `/Applications`。

本版本二进制使用 ad-hoc 签名，未经过 Apple 公证。首次打开可能需要在 Finder 中右键 App →“打开”并确认。不要关闭 Gatekeeper 或 SIP。

## 锁屏识别说明

macOS 不公开锁屏入口。快捷键/菜单锁屏通过“锁屏前 5 秒内有聚合输入”推断为手动操作；自动锁屏、屏保、系统睡眠和合盖使用独立状态。该规则具有启发式误判边界，详见 README。

完整变更见 [CHANGELOG.md](CHANGELOG.md)。
