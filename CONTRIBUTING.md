# 贡献指南

感谢你愿意为**义编会（YBH）博客客户端**出一份力。这份文档说明如何搭建环境、提交改动，以及本项目在代码风格上的约定。

## 开发环境

- **Flutter SDK**：Dart `^3.13.1`（见 `pubspec.yaml` 的 `environment`）
- **Android**：JDK 17、Android SDK（`minSdk`/`targetSdk` 由 Flutter 默认值决定）
- **iOS / macOS 构建**：需要 macOS + Xcode
- **Web / 桌面**：Flutter 桌面与 Web 支持已启用

```bash
git clone https://github.com/Yibianhui/YBH-Blog-App.git
cd YBH-Blog-App
flutter pub get
```

> Windows 用户若把工具链放在自定义目录，可参考 README「构建 Android APK」一节设置
> `PUB_CACHE` / `ANDROID_HOME` / `ANDROID_SDK_ROOT`。

## 日常命令

```bash
dart format .          # 格式化（建议跑；仓库含历史遗留文件，CI 暂不强制）
flutter analyze        # 静态分析（CI 以 --fatal-infos 运行）
flutter test           # 单元测试
flutter run            # 运行调试版
```

> 格式化说明：仓库中部分历史文件尚未统一格式，CI 目前只卡 `analyze` 与 `test`。
> 若你改动了某个文件，欢迎顺手 `dart format <该文件>`，但请不要把「只改格式」的
> 大规模改动和功能改动混在同一个 PR 里。

## 提交流程

1. **Fork 仓库**并基于 `main` 新建分支，建议命名：
   - `feat/分类排序置顶`
   - `fix/正文图片超屏`
   - `docs/补充贡献指南`
2. 完成改动后，确保 `flutter analyze`、`flutter test` 两项全绿（CI 会强制校验）。
3. 提交信息建议遵循 [Conventional Commits](https://www.conventionalcommits.org/)：
   - `feat: 新增…`、`fix: 修复…`、`docs: …`、`refactor: …`、`chore: …`、`test: …`
   - 中文描述即可，本项目现有提交也是中英混排。
4. 发起 Pull Request，填写 PR 模板中的自查清单；UI 改动请附前后对比截图。

CI（`.github/workflows/ci.yml`）会在每次 PR 上运行 format / analyze / test，需全部通过才会合并。

## 代码约定

- **架构分层**：数据层放 `lib/src/data/`，页面放 `lib/src/ui/`，平台分发放 `lib/src/`，外壳导航放 `lib/src/shell/`。
- **纯逻辑要可测试**：类似 `lib/src/data/category_order.dart` 的合并/排序算法，请写成不依赖 Flutter 绑定的纯函数，并在 `test/` 下补单测。
- **站点地址**统一取自 `lib/src/app_config.dart`，不要在业务代码里硬编码域名。
- **用户偏好**（分类顺序、夜间模式等）存 `SharedPreferences`，仅在本地生效，不上传服务器。
- **凭据**：登录凭据只存内存，不落盘；签名密钥（`android/key.properties`、`*.jks`）已加入 `.gitignore`，请勿提交。

## 版本号

- `pubspec.yaml` 的 `version` 形如 `0.0.9+9`，`+` 前是版本名、后是构建号。
- 每次发布需同步更新 `pubspec.yaml`、README 版本号说明与 `YBH-blog-release/` 下的更新清单。
- 推送 `v*` 标签会触发 `.github/workflows/release.yml` 自动构建 split APK 并创建 Release。

## 提 Issue

- 缺陷请用「缺陷反馈」模板，务必填写 App 版本、设备型号与 Android 版本。
- 新想法请用「功能建议」模板，重点描述**想解决的问题**，而不只是方案。

## 行为准则

请保持友好、就事论事。对事不对人，讨论技术方案时给出依据或实测结果。

## 许可证

贡献即表示你同意你的代码以本项目采用的 **MIT 许可证** 发布。
