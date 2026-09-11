# iOS 测试版打包（IPA）与 Sideloadly 安装

## 0. 为什么不能在 Windows 上直接产出 IPA

iOS 应用的编译链是 **Xcode 独占**的：`clang` 编译 Swift/Objective-C、`actool` 处理图标、
`codesign` 处理签名、链接 iOS SDK —— 这些都只随 macOS + Xcode 提供。
Sideloadly 的作用是**签名并安装** IPA，它不会编译代码。

所以要在 Windows 上拿到 IPA，只能“借一台 macOS 的编译结果”，仓库里已经准备好两条现成的路：

| 路线 | 你需要什么 | 耗时 |
|---|---|---|
| A. GitHub Actions（推荐） | 一个 GitHub 账号（免费） | 首次约 10 分钟 |
| B. 任意一台 Mac | macOS + Xcode + Flutter | 约 5 分钟 |

两条路产出的都是**未签名 IPA**，正好交给 Sideloadly 用你的 Apple ID 签名安装。

---

## 1. 路线 A：GitHub Actions 出 IPA（无需 Mac）

### 1.1 把仓库推上 GitHub

```bash
cd <本仓库目录>
git remote add origin https://github.com/<你的用户名>/ApexScrolling.git
git branch -M main
git push -u origin main
```

> 若用命令行建仓库：装好 `gh` 后 `gh repo create ApexScrolling --private --source=. --push`。
> 私有仓库同样能跑 Actions（每月有免费额度）。

### 1.2 运行工作流

推上去后，`.github/workflows/ios-unsigned-ipa.yml` 会自动触发；也可以在
**Actions → iOS 未签名 IPA → Run workflow** 手动触发。

构建完成后：

1. 进入该次运行页面；
2. 页面底部 **Artifacts** 下载 `ApexScrolling-ipa`（是个 zip）；
3. 解压得到 `ApexScrolling-unsigned.ipa`；
4. 页面顶部还能看到构建摘要里的版本号与 SHA256 校验值。

工作流做的事就是：装 Flutter 3.35.3 → `pod install`（Flutter 自动生成 Podfile）→
`flutter build ios --release --no-codesign` → 把 `Runner.app` 装进 `Payload/` 打成 `.ipa` → 上传。

---

## 2. 路线 B：任意一台 Mac 本地打包

```bash
git clone <仓库地址> && cd ApexScrolling
./tool/build_ipa.sh              # 未签名 IPA（给 Sideloadly 用）
./tool/build_ipa.sh --signed     # 若已配好团队/证书，直接导出已签名 IPA
```

前置要求：macOS + Xcode（命令行工具齐全）、Flutter 3.35.x、CocoaPods
（`sudo gem install cocoapods`）。产物为 `build/ApexScrolling-unsigned.ipa`，同时输出 SHA256。

---

## 3. 用 Sideloadly 装到 iPhone

1. Windows 上安装 Sideloadly（官网版）与 **iTunes（非 Microsoft Store 版）**，用于提供 Apple 驱动；
2. 数据线连接 iPhone，手机上点“信任此电脑”；
3. Sideloadly 里 **IPA 选 `ApexScrolling-unsigned.ipa`**；
4. **Apple ID 填你的 Apple ID**（免费账号即可，会生成 7 天有效的个人证书）；
5. 点 Start，输入 Apple ID 密码（建议在 appleid.apple.com 生成 App 专用密码）；
6. 安装完成后，在 iPhone **设置 → 通用 → VPN与设备管理** 里信任该开发者证书；
7. iOS 16+ 若提示需要在 **设置 → 隐私与安全性 → 开发者模式** 打开并重启手机。

### 使用限制（免费 Apple ID）

- 证书 **7 天**过期，到期后用同样步骤重装即可（Sideloadly 支持一键续签）；
- 同一台设备同时最多 3 个自签应用、每周最多 10 个 App ID；
- 桌面图标、Bundle ID 为 `com.apexscrolling.apexScrolling`；
  若与其他应用冲突，可在 `ios/Runner.xcodeproj` 里改 `PRODUCT_BUNDLE_IDENTIFIER`，
  或直接在 Sideloadly 里改 Bundle ID。

---

## 4. iOS 侧已就绪的配置

| 项 | 值 |
|---|---|
| Bundle ID | `com.apexscrolling.apexScrolling` |
| 显示名 | ApexScrolling |
| 部署目标 | iOS 13.0 |
| 版本 | 0.1.0（`CFBundleShortVersionString` 取自 pubspec） |
| 图标 | 已用 `python tool/make_icon.py` 生成全套 AppIcon |
| 启动画面 | 底色 #0F0F11，与深色主题一致，无白屏闪烁 |
| 网络 | 全部接口为 HTTPS，无需 ATS 例外 |
| 权限 | 不需要任何隐私权限（无账号、无定位、无相册） |

## 5. 常见问题

- **`pod install` 报错 / 找不到 Podfile**：首次构建时 Flutter 会自动生成
  `ios/Podfile`，确认执行过 `flutter pub get` 即可；必要时先 `flutter clean`。
- **Xcode 提示签名错误**：路线 A/B 的默认产物**不签名**，交给 Sideloadly 处理；
  若要用 Xcode 直接跑真机，需要在 `ios/Runner.xcodeproj` 里选自己的 Team。
- **安装后打不开**：先确认已信任证书；再确认开发者模式已开启；
  仍失败时用 Sideloadly 重新签名安装（不要用第三方“去广告版”IPA 工具）。
- **想上架 TestFlight**：需要付费开发者账号（$99/年）+ 已签名归档，
  `flutter build ipa --release` 后通过 Xcode Organizer 或 Transporter 上传。
