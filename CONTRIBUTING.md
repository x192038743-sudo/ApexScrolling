# 贡献指南

欢迎提交 Issue 与 PR。这个项目是纯客户端、无后端的 Flutter App，改动前建议先看
[docs/项目规划.md](docs/项目规划.md)（产品边界）与 [docs/数据源与合规.md](docs/数据源与合规.md)（内容源约定）。

## 开发环境

```bash
flutter pub get
flutter analyze
flutter test                    # 49 个离线测试，提交前必须全绿
flutter run                     # 连接真机/模拟器
```

跑真实网络的端到端用例（需要设备）：

```bash
flutter test integration_test/beta_acceptance_test.dart -d <device-id>
flutter test integration_test/feed_soak_test.dart -d <device-id>
```

> Android 模拟器请用 `-gpu host`：软件 GPU（`swiftshader_indirect`）下 Flutter 3.35 的
> Impeller 渲染器会把模拟器卡死。详见 [docs/测试版说明.md](docs/测试版说明.md)。

## 提交约定

1. **新增内容源**：在 `lib/data/adapters/` 实现 `CardAdapter`（统一返回 `Future<TextCard>`），
   在 `feed_repository.dart` 注册；必须用 fixture 写单测，并在卡片里带上署名/授权。
2. **抓取失败要能降级**：抛 `SourceException` 即可，信息流会换源重抽、熔断并回落缓存；
   不要把网络异常直接透传到 UI。
3. **隐私**：不引入账号、埋点、自建服务端；设置与缓存只落本机 `SharedPreferences`。
4. **异步**：Provider 里的异步逻辑在 `await` 之后要判断 `ref.mounted`，
   避免 `UnmountedRefException`（0.1.1 修过一次）。
5. 提交前跑 `flutter analyze` + `flutter test`；CI 也会跑同样两项。

## 许可

本项目以 MIT 许可证发布。你提交的代码将按同一许可证授权；
抓取到的第三方内容不随本项目授权，但请确保新内容源的授权允许这种使用方式并在卡片内署名。
