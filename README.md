# YBH · 义编会 WordPress 博客客户端

多平台 Flutter 应用，内嵌 WordPress 博客站点：<https://www.yibianhui.cn>

- **当前重点：Android APK**（已构建、可安装）
- 其他平台：iOS（已生成工程，需 macOS/Xcode 构建）、Web（已构建 PWA）、Windows/macOS/Linux（桌面壳，跳转系统浏览器）

> 版本号采用 `0.0.X` 格式：X 每进行一次小改动 +1（当前 0.0.9）。

## 功能

- **三栏外壳**：「文章」（REST 原生列表）+「整站」（WebView 完整体验）+「我的」
- **原生文章列表**：分类筛选、卡片式布局（随机封面/标题/摘要/日期/标签）、下拉刷新、骨架屏、错误重试
  - **分类联网获取**：分类由 WordPress REST API（`/wp-json/wp/v2/categories`）实时拉取，按文章数降序
  - **分类排序页**：在「我的 → 分类排序」中可拖拽调整筛选条分类的显示顺序，顺序仅保存在本机，
    不影响服务器；实现见 `lib/src/data/category_order.dart`、`lib/src/ui/category_order_page.dart`
- **原生文章详情**：移动端用 WebView 阅读器完整渲染正文（站点 CSS 样式 /
  自定义字体 base64 内嵌 / 图片自适应与懒加载 / Ruby 振假名 / 代码块语言标签与复制），
  支持选中复制，分享 / 浏览器打开；无法使用 WebView 的平台（Web/桌面）退回 flutter_html 排版
- **抽屉菜单**：文章列表 / 整站 / 关于 / 分享 / 浏览器打开 / 复制地址 / 夜间模式开关
- 整站 WebView：加载进度条、页内返回、回首页/刷新/分享/系统浏览器打开
- 站外链接自动转交系统浏览器，站内链接始终留在应用内
- **旧设备性能模式**：整站页面加载后自动关闭站点动画/毛玻璃/固定背景/粒子 canvas 等重特效
- **检查更新**：启动自动检查 + 「我的」页手动检查，发现新版本弹窗提醒并跳转下载
  （更新清单 URL 见 `lib/src/app_config.dart` 的 `updateManifestUrl`，模板与部署说明见 `YBH-blog-release/update/`）
- **「我的」个人中心**：用站点账号「用户名 + 密码」登录（默认 JWT，站点已安装 JWT Authentication 插件，最方便；
  若 JWT 不可用则自动回退到 WordPress 核心「应用密码」Basic Auth，无需插件、需 HTTPS），
  登录后可查看「我的文章」并在应用内写文章发布；实现见 `lib/src/data/wp_auth.dart`、`lib/src/ui/profile_tab.dart`、`lib/src/ui/editor_page.dart`
- **登录态跨端同步**：App 登录成功后，「整站」WebView 用内存中的最新凭据自动完成
  wp-login 表单登录（本站服务端只信任真实浏览器指纹的会话，应用内 HTTP 客户端
  拿到的 Cookie 无效，故必须由 WebView 自身登录；凭据仅存内存、不落盘），
  退出登录同步清空整站 Cookie；实现见 `lib/src/data/wp_auth.dart`、`lib/src/webview_impl.dart`
- 文章正文 WebView 阅读器：图片自适应整行宽度、保持比例、原生懒加载；Ruby 振假名原生排版；
  代码块自动标注语言并提供复制按钮；视频/音频/iframe 内嵌播放
- 应用图标与启动屏来自工作区 `ybh-lo.png` 圆角裁剪版，主题色沿用站点 `#505050`

## 平台承载方式

| 平台 | 实现 |
| --- | --- |
| Android | 原生外壳 + REST 文章列表 + `webview_flutter`（整站） |
| iOS | 原生外壳 + REST 文章列表 + `webview_flutter`（WKWebView） |
| Web | 品牌启动页 + 自动跳转博客整站 |
| macOS | 原生外壳 + REST + WKWebView |
| Windows / Linux | 桌面壳，点击跳转系统浏览器打开站点 |

核心结构：

- `lib/src/shell/home_shell.dart` —— 三栏外壳 + 抽屉菜单
- `lib/src/ui/posts_tab.dart` / `post_detail_page.dart` —— 原生文章列表与详情
- `lib/src/data/blog_api.dart` —— WordPress REST 数据层
- `lib/src/webview_impl.dart` —— 整站 WebView 页
- `lib/src/blog_host.dart` —— 平台分发

## 构建产物

- Android APK：`build/app/outputs/flutter-apk/app-release.apk`
- Web：`build/web/`

## 构建 Android APK

```powershell
# 环境（本机工具链）
$env:PUB_CACHE='E:\dsh\.tools\pub-cache'
$env:ANDROID_HOME='E:\dsh\.tools\android-sdk'
$env:ANDROID_SDK_ROOT='E:\dsh\.tools\android-sdk'
flutter build apk --release
```

分 ABI 包（更小）：

```powershell
flutter build apk --split-per-abi
```

构建 Web：

```powershell
flutter build web --release
```

构建 iOS（需要 macOS + Xcode）：

```bash
flutter build ios --release
```

## 发布签名（Android）

- 已生成发布密钥库：`android/app/ybh-release.jks`
- 签名参数：`android/key.properties`（已加入 `.gitignore`）
- 别名 `ybh-blog`，密码 `YBH-Blog-2026-Release-Key`（请妥善保管；正式上架前建议重新生成自己的密钥库）
- 应用 ID：`cn.yibianhui.blog`，应用名：`YBH`，版本 `0.0.9 (9)`

## 常见开发命令

```powershell
flutter analyze
flutter test
dart run flutter_launcher_icons      # 重新生成应用图标
dart run flutter_native_splash:create # 重新生成启动屏
```

## 备注

- 站点地址与域名白名单集中在 `lib/src/app_config.dart`。
- 项目首次构建时 Gradle 已通过腾讯云镜像下载并缓存；若换机器构建网络较慢，可自行修改 `android/gradle/wrapper/gradle-wrapper.properties` 的 `distributionUrl` 指向镜像。

## 开源与许可证

本项目以 **MIT 许可证** 开源，详见 [LICENSE](./LICENSE)。

- 仓库地址（GitHub）：<https://github.com/Yibianhui/YBH-Blog-App>
- 欢迎通过 Issue / Pull Request 参与贡献。提交前请运行：

```powershell
flutter analyze
flutter test
```

- 分类顺序等用户偏好仅保存在本机 `SharedPreferences`，不会上传。
- 发布构建产物（APK / Web / 源码包）归档在同级目录 `YBH-blog-release/`，不纳入本源码仓库。

## 同步到 GitHub

首次推送前先添加远端（把 `<用户名>/<仓库名>` 换成你的仓库）：

```powershell
git remote add origin git@github.com:<用户名>/<仓库名>.git
# 或 HTTPS：
# git remote add origin https://github.com/<用户名>/<仓库名>.git
git push -u origin main
```

之后每次本地有改动要同步，运行仓库根目录的脚本即可（会自动拉取、提交、推送）：

```powershell
pwsh ./sync_to_github.ps1 -Message "本次更新说明"
```

> 注意：`sync_to_github.ps1` 会先 `git pull --rebase` 再推送，避免非快进冲突；如有冲突需手动解决后重跑。

