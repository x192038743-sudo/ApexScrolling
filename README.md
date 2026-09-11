# ApexScrolling

替代短视频的**纯文字信息流** App：上滑随机刷到一张极简文字卡片——学术冷门词条、哲学观点、经典选段、短篇小说/散文、实用技能教程、诗词名句。无账号、无后端、无算法推荐，全部内容由客户端直连公开开放资源。

Flutter 3.35（Android + iOS）· Riverpod · 全离线设置与缓存。

## 快速开始

```bash
flutter pub get
flutter test          # 49 个单测 + Widget 测试（全部离线，用 fixture）
flutter run           # 连接真机/模拟器运行
dart run tool/smoke.dart   # 可选：真实网络冒烟，输出 build/smoke_report.txt
flutter test integration_test/beta_acceptance_test.dart -d <device>   # 真机端到端验收
```

构建（**当前测试版 APK 即由此产出**）：

```bash
flutter build apk --release                    # 通用 APK（含三种 ABI）
flutter build apk --release --split-per-abi    # 按 ABI 拆分，体积更小
flutter build ios --release        # iOS（需 macOS + Xcode）
```

产物路径：`build/app/outputs/flutter-apk/app-release.apk`。安装与验收清单见 [docs/测试版说明.md](docs/测试版说明.md)。

iOS（IPA）无法在 Windows 上编译，仓库已内置两条出包路径：GitHub Actions
（`.github/workflows/ios-unsigned-ipa.yml`，无需 Mac）与 macOS 本地脚本
（`./tool/build_ipa.sh`），产出的未签名 IPA 可直接用 Sideloadly 安装。
步骤见 [docs/iOS打包与Sideloadly.md](docs/iOS打包与Sideloadly.md)。

> Android 已声明 `INTERNET` 权限；iOS 全部接口走 HTTPS，无需额外 ATS 例外。
>
> 若所在网络无法直连 `maven.google.com`，`android/gradle.properties` 里的
> `apex.cnMirrors=true`（默认）会让 Gradle 优先走华为云 / 腾讯云 / 阿里云镜像；
> Flutter 引擎资源镜像可用 `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn` 指定。

## 交互（核心体验）

| 操作 | 行为 |
|---|---|
| 上滑 / 下滑（卡片态） | 下一张 / 上一张 |
| 点击卡片 | 进入展开态：正文完整呈现，卡片内可滚动阅读 |
| 展开态上滑 | 先滚动正文；**滑到底后继续上滑直接切下一张**（衔接滑动惯性） |
| 展开态再点一次 | 收起回卡片态（底部署名区不响应点击，避免误触） |
| 点词条内链 | 在当前位置插入新卡片（兔子洞，深度上限 5 层） |

卡片态排版：顶部粗体标题 + 小字来源署名，正文向底部渐变透明淡出，单屏固定、卡片内不可滚动、无任何图片/按钮/红点。

## 已实现能力

- **六源信息流**：等权随机抽源、逐源开关、预取后 3 张、已看可回滑。
- **自适应抓取**：单源失败自动换源重抽；同一源连续失败 2 次熔断 60 秒；全部失败回落本地缓存卡片并提示。
- **首卡竞速**：每次并发抓 2 个源，先成功者立刻出卡，后成功者进入就绪队列（下一张秒出）；词条源的 SPARQL 候选池一次取 12 条复用，避免连续等 10s+。
- **阅读排版**：衬线字体（英文 Georgia，中文思源宋体/霞鹜文楷回退链）、行距 1.8、字号三档、深浅主题（跟随系统或手动）。
- **隐私**：无账号、无埋点、无自建服务器；设置与卡片缓存仅存本机 `SharedPreferences`。

## 目录结构

```
lib/
  core/endpoints.dart          # 所有数据源地址、UA、超时/熔断策略
  models/                      # TextCard / CardLink / AppSettings
  data/
    net_client.dart            # HTTP 封装（UA、超时、编码、错误类型）
    text_cleaner.dart          # HTML/wikitext → 纯文本、段落切分、300–600 字选段
    feed_repository.dart       # 抽源、竞速、换源、熔断、离线兜底
    card_cache.dart            # 卡片本地缓存（离线可读）
    presets.dart               # 公版书单 / 作者 / 技能检索词
    adapters/                  # 六个内容源适配器（统一 Future<TextCard>）
  state/                       # Riverpod providers / 设置 / 信息流控制器
  ui/
    feed_page.dart             # PageView 信息流 + 顶部极简操作区
    card_view.dart             # 卡片态 / 展开态、渐隐、滑到底透传切卡
    settings_page.dart         # 源开关、字号、主题、冷门档位、缓存清理
    theme.dart                 # 配色与衬线排版
test/                          # 49 个测试（fixture 驱动，不依赖网络）
tool/smoke.dart                # 真实网络冒烟脚本
tool/make_icon.py              # 生成 Android/iOS 应用图标（Pillow）
assets/branding/               # 图标源图（1024px，不参与打包）
dist/                          # 测试版 APK 产物与校验值（不入库）
docs/                          # 项目规划、数据源与合规说明
```

## 数据源与网络说明

六个源分别是维基百科（Wikidata 筛选冷门学术词条）、斯坦福哲学百科、维基文库 + 古登堡计划（经典/小说/散文）、wikiHow（不可达时回落维基教科书）、今日诗词。

实测中国大陆网络下 `*.wikipedia.org` 不可达，因此**维基正文统一走 `api.wikimedia.org`**；wikiHow 不可达时自动切换维基教科书并同步署名/授权。细节、接口与授权见 [docs/数据源与合规.md](docs/数据源与合规.md)，产品规划见 [docs/项目规划.md](docs/项目规划.md)。

## 字体说明

默认使用系统衬线字体（英文 Georgia × 中文思源宋体/宋体回退链）。若要内置「霞鹜文楷」：

1. 下载 `LXGWWenKai-Regular.ttf` 放到 `assets/fonts/`；
2. 在 `pubspec.yaml` 的 `flutter:` 下加入：

   ```yaml
   fonts:
     - family: LXGW WenKai
       fonts:
         - asset: assets/fonts/LXGWWenKai-Regular.ttf
   ```

`lib/ui/theme.dart` 的 `serifFallback` 已把 `LXGW WenKai` 放在首位，字体加入后自动生效。

## 已知限制

- wikiHow 在部分网络（含开发环境所在网络）不可达，此时技能卡由维基教科书提供，风格偏教程而非 wikiHow 步骤卡。
- 维基百科条目导语普遍较短（1–4 段），词条卡内容量天然小于小说/散文卡。
- 首次冷启动若抽到词条源，需要等待一次 Wikidata 查询（约 10–15s）；此后候选池复用，出卡恢复到 1–2s。可通过关闭该源获得即时首卡。
- 古登堡全文按需下载（数百 KB–1MB），首次抽到某本书会稍慢，之后内存缓存复用。
