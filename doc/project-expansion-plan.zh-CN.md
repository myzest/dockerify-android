# Dockerify Android 项目拓展规划

## 项目定位

Dockerify Android 当前已经不只是一个 Docker 化 Android Emulator 项目。它已经具备设备画像、macOS 原生运行、rootAVD、GApps、ARM translation、Web 控制和审计脚本等能力。

后续更适合把项目定位为：

> 一个可复现、可审计、可批量运行的 Android 测试设备平台。

围绕这个定位，项目拓展应优先服务于三个目标：

- 让不同宿主环境都能稳定启动和验证 Android 设备。
- 让设备画像更加接近真实设备，并能量化差距。
- 让开发者可以批量安装、测试、观测 APK。

## 拓展方向

### 1. 设备画像 Profile 生态

当前项目已有 `pixel_5_android_11` profile 和通用模板。下一步可以把 profile 体系扩展成项目的核心能力。

可落地方向：

- 增加更多常见设备 profile，例如 Pixel 4、Pixel 6、Pixel 7、Samsung Galaxy、OnePlus 等。
- 为不同 Android 版本维护独立 profile，例如 Android 11、12、13、14。
- 增加 profile 元数据文件，记录设备来源、Android 版本、适配状态、已知边界。
- 支持从真机或已有 AVD 采集信息并生成 profile 草稿。
- 增加 profile lint，提前检查字段缺失、系统版本不匹配、属性冲突等问题。

建议优先级：高。

价值：

- 提升项目差异化。
- 降低用户新增设备画像的门槛。
- 为后续批量测试和审计评分打基础。

### 2. 多 Android 版本镜像矩阵

当前 Docker 镜像主要围绕 Android 11 / API 30。后续应逐步支持更多 Android 版本。

可落地方向：

- 支持 Android 12、13、14 的 Docker 构建参数。
- 将 `ANDROID_API_LEVEL`、`ANDROID_RELEASE`、`ANDROID_SYSTEM_IMAGE` 抽象成版本矩阵。
- 为每个版本提供最小可用 profile。
- 在 CI 中构建并发布版本化镜像标签。
- 明确每个系统版本对 root、GApps、ARM translation 的支持状态。

建议优先级：高。

价值：

- 覆盖更多真实 App 兼容性场景。
- 让项目从单一镜像升级为可维护的设备矩阵。
- 方便接入自动化测试和回归测试。

### 3. Profile 审计 JSON 报告与评分

项目已有 `verify-profile.sh` 和 `audit-real-device-fidelity.sh`，可以进一步升级为结构化审计系统。

可落地方向：

- 输出 JSON 报告，便于 CI、Web UI 和自动化系统消费。
- 将审计项分类为可控项、半可控项、模拟器固有边界、风险项。
- 给 profile 输出拟真度评分。
- 支持保存历史报告并比较两次启动的差异。
- 将失败项映射到修复建议。

建议优先级：最高。

价值：

- 和现有代码贴合度最高。
- 可以快速形成项目专业感。
- 能反向指导 profile 和运行时能力的下一步改造。

建议审计分类：

- Build 属性：品牌、型号、设备名、fingerprint、security patch。
- Framework 状态：locale、timezone、device name、battery、network、animation。
- ABI 能力：x86、arm64、native bridge、ndk_translation。
- Root 与完整性：Magisk、su、build tags、boot state、ADB。
- Emulator 边界：QEMU、ranchu、SwiftShader、cpufreq、传感器、TEE、StrongBox。

### 4. macOS Native Runner 产品化

Docker Desktop for macOS 通常无法把 KVM 暴露给容器。当前 macOS native runner 是项目的重要差异化能力，应继续打磨成稳定入口。

可落地方向：

- 增加 `macos-up.sh`、`macos-down.sh`、`macos-reset.sh` 等统一命令。
- 将 bootstrap、doctor、run、verify、rootAVD 串成更顺滑的体验。
- 增加多 profile 多端口运行管理。
- 增加日志目录清理和状态查看命令。
- 明确 Apple Silicon 与 Intel Mac 的系统镜像选择策略。

建议优先级：中高。

价值：

- 解决 macOS 用户最现实的运行问题。
- 让项目不依赖 Docker Desktop 的 KVM 能力。
- 提升本地开发体验。

### 5. 多实例编排与矩阵运行

README 已经提供多实例 Compose 示例，可以进一步封装为批量运行能力。

可落地方向：

- 增加 profile matrix 配置文件。
- 一键启动多个 profile 实例。
- 自动分配 ADB 端口、Web 端口、数据目录和容器名。
- 提供统一状态查询命令。
- 支持批量执行安装 APK、拉取 logcat、运行审计。

建议优先级：中。

价值：

- 支撑兼容性测试和回归测试。
- 让项目从单设备工具升级为小型设备池。
- 方便 CI/CD 接入。

### 6. APK 测试工作流

当前项目提供了运行设备的基础能力，后续可以增加面向 App 的测试入口。

可落地方向：

- 安装 APK 并自动识别 package name。
- 启动主 Activity 并记录启动耗时。
- 捕获崩溃、ANR、logcat、截图。
- 检查 ABI 兼容性和 native library 加载失败。
- 输出单次 APK smoke test 报告。

建议优先级：中。

价值：

- 更贴近日常 App 开发和测试需求。
- 让 Dockerify Android 从环境项目变成测试工具。
- 有利于吸引 CI、QA、自动化测试用户。

### 7. Web 控制台

项目已集成 scrcpy-web。可以在此基础上增加一个轻量控制台，用来展示设备状态和常用操作。

可落地方向：

- 展示当前 profile、Android 版本、ADB serial、boot 状态。
- 展示 root、GApps、ARM translation 状态。
- 展示最近一次审计报告。
- 提供重启、拉取 logcat、安装 APK、截图等操作。
- 与 scrcpy-web 入口联动。

建议优先级：中低。

价值：

- 降低非命令行用户的使用门槛。
- 让项目演示效果更完整。
- 适合后续做团队共享或远程调试入口。

## 推荐实施顺序

### 第一阶段：审计能力结构化

目标：

- 将 profile 审计结果输出为 JSON。
- 给每个检查项增加分类、严重级别和修复建议。
- 保留当前文本输出，避免破坏已有使用方式。

验收标准：

- `audit-real-device-fidelity.sh` 支持 `--json`。
- JSON 中包含 profile、serial、宿主类型、检查项、结果、摘要。
- CI 或本地脚本可以读取 JSON 并判断是否通过。

### 第二阶段：Profile 工程化

目标：

- 增加 profile 元数据和 lint。
- 增加至少 2 个新设备 profile。
- 编写 profile 编写指南。

验收标准：

- 新 profile 可以通过 lint。
- 每个 profile 都有 Android 版本声明、设备来源说明和已知边界。
- profile 文档能指导用户新增自己的设备。

### 第三阶段：多 Android 版本

目标：

- 支持至少一个新的 Android 主版本。
- 为新版本提供最小可用 Docker 镜像和 profile。

验收标准：

- Docker build 支持按版本构建。
- 对应 profile 可以启动并通过基础审计。
- README 明确版本支持矩阵。

### 第四阶段：macOS 与多实例体验

目标：

- 封装 macOS 常用生命周期命令。
- 封装 Compose 多实例运行。

验收标准：

- macOS 用户可以通过一组固定命令完成 doctor、bootstrap、启动、验证、停止。
- 多实例脚本能自动分配端口和数据目录。

### 第五阶段：APK 测试与 Web 控制台

目标：

- 增加基础 APK smoke test。
- 增加轻量状态控制台。

验收标准：

- 用户可以传入 APK 并获得安装、启动、截图、logcat、崩溃摘要。
- Web 页面可以看到设备状态和最近一次审计结果。

## 近期可执行任务

- 为 `audit-real-device-fidelity.sh` 增加 `--json` 输出。
- 新增 `scripts/profile-lint.sh`。
- 为 profile 增加 `profile.meta` 或 `profile.json`。
- 新增一个非 Pixel profile，用来验证 profile 模板的通用性。
- 增加 `doc/profile-authoring.zh-CN.md`。
- 增加 `scripts/macos-up.sh` 聚合 macOS 启动流程。
- 增加多实例 Compose 示例脚本。

## 风险与边界

- Android Emulator 无法完全模拟真实硬件，例如 TEE、StrongBox、baseband、真实传感器噪声、GPU、CPU 频率和底层 QEMU 痕迹。
- root、GApps、ARM translation 在不同 Android 版本上的可用性不同，需要逐版本验证。
- macOS Docker 运行时缺少 KVM 是宿主限制，不能通过普通容器参数彻底解决。
- 设备画像应强调测试一致性和兼容性，不应承诺绕过硬件级完整性校验。

## 总结

短期最值得做的是 Profile 审计 JSON 报告与评分系统。它复用现有脚本，改造成本低，但可以显著提升项目的专业度和可维护性。

中期应扩展设备 profile 和 Android 版本矩阵。长期可以把 Dockerify Android 打造成一个跨 Docker、macOS、CI 的 Android 设备池与 APK 测试平台。
