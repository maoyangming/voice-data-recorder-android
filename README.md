# 语音数字记录 — 实验室数据录入助手

> 专为生化环材等实验室场景设计：对着手机说数字，自动记录到 CSV，告别手写笔记。

---

## 功能特性

- **持续语音监听** — 点一次按钮，自动循环监听，无需反复操作
- **智能数字识别** — 支持阿拉伯数字（`3.45`）和中文数字（`三点四五`）
- **语音撤销** — 说"删除"/"撤销"立即删除上一条记录
- **自动保存 CSV** — 每次会话生成带时间戳的 CSV 文件，含序号、数值、时间三列
- **一键分享** — 顶部分享按钮，直接发送到微信、邮件、钉钉等
- **完全离线** — 使用 Android 系统内置语音识别，无需网络，无需 API Key

---

## 截图

| 空状态 | 录音中 | 数据记录 |
|:---:|:---:|:---:|
| 点击按钮开始 | 蓝色脉冲动画 | 蓝色数字列表 |

---

## 安装

### 直接安装 APK（推荐）

1. 在 [Releases](https://github.com/maoyangming/voice-data-recorder-android/releases) 页面下载最新的 `语音数据记录_vX.X.apk`
2. 手机打开下载的 APK 文件
3. 如提示"安装未知来源应用"，进入设置允许即可
4. 安装完成后打开，授予麦克风权限

### 从源码构建

**环境要求：**
- Flutter 3.10+
- Android SDK（minSdk 21，即 Android 5.0+）
- JDK 17+

```bash
git clone https://github.com/maoyangming/voice-data-recorder-android.git
cd voice-data-recorder-android
flutter pub get
flutter build apk --release
# APK 输出路径：build/app/outputs/flutter-apk/app-release.apk
```

---

## 使用方法

1. **开始录音** — 点击底部大圆形按钮，按钮变红、出现脉冲动画
2. **说数字** — 直接报出数值，如 `"3.45"`、`"零点零一"`、`"负二十三"`
3. **查看记录** — 每条识别成功的数值即时出现在列表中
4. **撤销** — 说 `"删除"` 或 `"撤销"` 删除最后一条
5. **导出** — 点击右上角分享图标，发送 CSV 文件
6. **新建会话** — 点击右上角 `+` 按钮，开始新的 CSV 文件

**支持的撤销关键词：** 删除 / 撤销 / 删掉 / 取消 / 删了

---

## CSV 格式示例

```
序号,数值,时间
1,3.45,09:12:03
2,0.01,09:12:15
3,23.8,09:13:02
```

---

## 项目结构

```
lib/
├── main.dart           # 应用入口
├── home_screen.dart    # 主界面（UI + 语音逻辑）
├── number_parser.dart  # 数字识别与中文转换
└── csv_manager.dart    # CSV 读写管理
```

---

## 技术栈

| 组件 | 用途 |
|---|---|
| [Flutter](https://flutter.dev) | 跨平台 UI 框架 |
| [speech_to_text](https://pub.dev/packages/speech_to_text) | 调用 Android 系统 SpeechRecognizer |
| [path_provider](https://pub.dev/packages/path_provider) | 获取外部存储路径 |
| [share_plus](https://pub.dev/packages/share_plus) | 系统分享 CSV 文件 |
| [permission_handler](https://pub.dev/packages/permission_handler) | 运行时申请麦克风权限 |

---

## 相关项目

本项目是 [voice_recorder](https://github.com/maoyangming/voice_recorder) 的 Android 独立 App 版本。桌面版（macOS/Windows）使用 faster-whisper 本地模型，精度更高；手机版使用系统 ASR，速度更快、无需额外依赖。

---

## License

MIT
