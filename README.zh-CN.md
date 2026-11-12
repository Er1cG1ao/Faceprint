<p align="center">
  <img src="Branding/Faceprint.png" width="128" alt="Faceprint 应用图标">
</p>

# Faceprint

**看一眼，少输一次密码。**

一个原生 macOS 菜单栏应用：识别你的脸，将保存的 Mac 密码填入受支持的系统弹窗。打开密码输入框，看向摄像头，再确认当前请求。灵动岛会显示识别进度与结果。

[English](README.md) · **简体中文**

[下载](https://github.com/Er1cG1ao/faceprint/releases/latest) · [使用教程](Docs/TUTORIAL.zh-CN.md) · [开发说明](Docs/DEVELOPMENT.md) · [反馈问题](https://github.com/Er1cG1ao/faceprint/issues)

基于 [**Jonathan Zhou 的 Glance**](https://github.com/jonnyoo/glance) 开发，直接复用了人脸识别、多方位录入、灵动岛相关代码与素材。软件内及[第三方声明](THIRD_PARTY_NOTICES.md)保留了原作者署名和许可证。

## 能做什么

- **九方向人脸录入：** 通过 Glance 的引导圆环与摄像头预览采集 18 个样本，使用相同的 ArcFace 模型。
- **填写系统密码弹窗：** 支持可识别的原生 Mac 账户授权，包括“隐私与安全性”、Finder、安装器及 Dia 的原生 Passwords AutoFill 弹窗。
- **灵动岛状态反馈：** 提供 Original 与 Minimal 两种动画样式，兼容有刘海和无刘海的显示器。
- **自主选择提交方式：** 默认填完后手动确认，也可开启验证填入后自动回车。
- **本地加密保存：** 密码和人脸模板在本机加密，通过 macOS 验证打开受 Secure Enclave 保护的会话。
- **便于日常使用：** 首次权限申请、权限状态提示、摄像头选择，以及可选的登录时启动。

使用 Swift、SwiftUI、AppKit、AVFoundation 和 Core ML 构建，人脸处理在本机完成。软件界面目前为英文，文档提供英文和简体中文。

### 当前正式版：1.2.1

扩大原生授权场景，修复 System Settings → Privacy & Security 密码框接续，并优化识别、填写和灵动岛的响应。新增 **Copy diagnostics**，可复制最近一次操作的阶段耗时。**Scan Touch ID prompts** 与 **Press Return after filling** 仍独立控制、新安装默认关闭。详见[版本说明](RELEASE_NOTES.md)和[性能说明](Docs/PERFORMANCE.md)。

## 安装与开始使用

需要 **Apple Silicon（M 系列）Mac、macOS 15 或更新版本**，目前不提供 Intel 安装包。

1. 在 [最新发布页](https://github.com/Er1cG1ao/faceprint/releases/latest)的 **Assets** 中下载 `Faceprint-1.2.1-macos-arm64.zip`。
2. 退出旧版，解压 ZIP，将 `Faceprint.app` 放入 **Applications（应用程序）**，然后再授权或启用开机自启。
3. 打开 Faceprint，允许**摄像头**与**辅助功能**权限。点击 **Unlock to edit**，完成 macOS 身份验证。
4. 在 **Camera** 选择摄像头，在 **Your Face** 按九方向引导录入人脸，在 **Password** 保存 Mac 登录密码。
5. 在 **Recognition** 保持自动回车关闭，然后在 **General** 启用填写。打开支持的系统弹窗，必要时先点 **Use Password…**，让空密码框获得焦点。
6. 再次锁定设置，已启用的自动填充会继续运行。识别后检查请求和已填入的密码框，再自行确认或取消。

使用时保持 Faceprint 运行。关闭设置窗口后应用仍留在菜单栏；退出应用会停止识别并锁定会话。设置在启动时默认锁定。若此前已启用自动填充，启动后会通过一次 macOS 验证准备受保护的数据；此验证不会解锁设置以供修改。会话、自动回车、照片检查和排错方法见[使用教程](Docs/TUTORIAL.zh-CN.md)。

发布版本使用临时签名，**尚未经过 Apple 公证**。

## 支持范围与隐私

- 仅支持指定的 Apple 系统密码弹窗。默认由你打开密码输入界面；开启指纹提示扫描后，软件会在扫脸通过后选择 Use Password，再填写。它不会替换 macOS Touch ID、解锁锁屏或提供 Face ID 硬件。
- 使用普通 RGB 摄像头，**照片或回放视频也可能通过识别**。可选的 Glance Light 照片检查能拒绝部分明显的冒充，也可能误判真人，无法可靠防住所有回放。
- 原生“密码”AutoFill 匹配目前依赖英文弹窗文字。填入验证检查输入长度；密码是否正确、操作是否成功，由 macOS 决定。
- 自动回车**默认关闭**。开启后可能直接确认具有管理员权限的设置修改。
- 摄像头画面仅在内存中处理，保存的人脸特征和密码在本机加密。设置在关闭窗口或 5 分钟后锁定；锁屏、睡眠、切换用户会话、退出应用或 30 分钟未使用加密数据后，运行中的加密数据重新锁定，可通过 Resume autofill 或下一个支持的弹窗再次验证。详见[本地数据与隐私](Docs/TUTORIAL.zh-CN.md#本地数据与隐私)。
- InsightFace 预训练权重适用独立的**非商业研究条款**，代码的 MIT 许可证不赋予额外的模型使用权。详见[第三方声明](THIRD_PARTY_NOTICES.md)。

## 从源码构建

在 Apple Silicon Mac 上安装当前版本的 Apple Command Line Tools，并在本机安装 Glance，以导入其已编译模型和动画素材。

```sh
git clone https://github.com/Er1cG1ao/faceprint.git
cd faceprint
bash setup-resources.sh
bash build.sh
bash test.sh
```

输出为 `Faceprint.app`，构建不会自动安装或发布应用。资源导入、源码结构、测试及打包方式见[开发说明（英文）](Docs/DEVELOPMENT.md)。

## 反馈与参与

欢迎通过 [Issues](https://github.com/Er1cG1ao/faceprint/issues) 反馈，附上 Faceprint 版本、macOS 版本、摄像头型号、复现步骤，以及预期和实际结果。分享日志或截图前请移除私人信息，**不要上传密码、人脸模板、摄像头录像或本地 vault 文件**。

[中文教程](Docs/TUTORIAL.zh-CN.md) · [English guide](Docs/TUTORIAL.md) · [开发说明](Docs/DEVELOPMENT.md) · [版本说明](RELEASE_NOTES.md)

## 许可证与项目来源

Faceprint 代码采用 [MIT](LICENSE) 许可证，复用部分保留 [Glance 原始 MIT 声明](LICENSE-Glance.txt)。感谢 **Jonathan Zhou** 开发 Glance，感谢 **InsightFace 作者**提供人脸识别模型。图标最初由 AI 图像生成工具创作，当前圆角版本由项目作者通过 Icon Composer 导出，图稿位于 [`Branding/Faceprint.png`](Branding/Faceprint.png)。上游版本与模型条款见[第三方声明](THIRD_PARTY_NOTICES.md)。
