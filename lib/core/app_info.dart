/// 应用元信息（与 pubspec.yaml 的 version 保持一致）。
class AppInfo {
  const AppInfo._();

  static const String name = 'ApexScrolling';

  /// 当前为测试版（beta）：功能完整但未做上架准备。
  static const bool isBeta = true;

  static const String version = '0.1.0';
  static const String buildNumber = '1';

  static String get versionLabel =>
      'v$version+$buildNumber${isBeta ? ' · 测试版' : ''}';
}
