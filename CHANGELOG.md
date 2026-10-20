# Changelog

## Unreleased

- Migrate realtime transport and texture rendering to Agora RTC 4.6.4 through the Flutter 6.6.4 plugin.
- Replace the model catalog with `x2.1.1-preview-cn` and `x2.1.1-preview-us`, including model-specific realtime endpoints and strict RTC credential parsing.
- Add ordered, rate-limited DataStream signaling with Unicode-safe fragmentation and pending-trajectory coalescing.
- Confirm generation from published robot video after sending the start signal; remove the previous SEI handshake.
- Normalize interaction coordinates to the resolved media dimensions while retaining 30 Hz sampling.
- Add independent adaptive uplink/downlink quality, recovery cooldowns, one-hour model-specific history, and four-pixel-aligned return sizes.
- Add public video-statistics listeners, XLab statistics, and face restoration for clothing references.
- Replace `resolveModelInputSize` with media, generation, and return-size resolution methods. Remove `stopGeneration` from the public manager interface; use `disconnect` to stop remote generation.

## 1.0.2

- 新增 X2.0-PRO 模型支持，X2.0 默认采集帧率调整为 30 fps，并完善分辨率、码率及编码偏好配置。
- 新增服务环境配置、运行环境信息和 XLab 全页面国际化。
- 完善实时状态、房间信令、音量契约、任务切换及异常后的资源清理。
- 新增原生日志输出、日志国际化、媒体元数据和生成启动耗时统计。
- 修复远端首帧显示延迟和停止生成时的黑帧；新增 `XmaxRealtimeVideoView.onRemoteVideoReady`，供接入方在远端画面开始显示时收起加载遮罩。
- 优化 XLab 相册选择、加载状态和快速切换参考图的处理。

### API Changes

- 删除 `setErrorListener` 和 `setCameraPreviewReadyListener`；改用 `setStateListener` 的 `ready` 状态及 `state.reason?.error`，主动调用错误仍通过 Future 抛出。
- 删除 `XmaxError.severity`；新增音量读取属性和 `disconnect(reason:)`。
- 创建摄像头流后远端音量默认为 `0`；需要声音时，请在创建流后调用 `setRemoteAudioVolume`。

## 1.0.1

- 修复使用新版腾讯 COS 依赖时 Android Release 构建的 R8 缺失类型错误。
- 完善 Android 宿主的 R8 配置说明，确保 pub.dev、Git 和本地 path 接入可正常构建。

## 1.0.0

- SDK Dart 文件名与 iOS 对齐为首字母大写驼峰，Example 保持 Flutter snake_case。
- 实现与 iOS 对齐的 XmaxClient、实时 Manager、Session 和状态机。
- 接入火山 RTC 摄像头采集、本地/远端渲染及视频发布。
- 实现多点轨迹采集、坐标映射、默认效果和自定义 Renderer。
- 实现腾讯 COS 图片/视频上传、图片安全检测、下载和进度回调。
- 完成 iOS/Android XLab、平台配置、单元测试和双端 Debug 构建验证。
- 初始化 XmaxSDK Flutter Package 和 iOS/Android Example 工程。
- 固定 Flutter、火山 RTC 与腾讯 COS 依赖基线。
