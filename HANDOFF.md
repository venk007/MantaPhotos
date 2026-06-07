# HANDOFF —— 评审整改后的编译验证与修复

> 给本机 Claude Code 的执行说明。目标：把最近一次评审整改的改动**编译通过、测试通过**，再生成正式 `.xcodeproj` 并构建出 `.app`。**全程自动进行，不要等待用户确认**（仅照片权限弹窗需要用户点击，见末尾）。

## 0. 角色与硬约束

- 你的任务是**让现有改动编译/测试通过**，不是重新设计。修复时**保留**以下架构决策，不要回退：
  - 状态层已用 **Observation（`@Observable`）** 拆分为 `AppState`（组合根）+ `NavigationState` + `PhotoLibraryViewModel` + `AnalysisViewModel`；视图用 `@Environment(AppState.self)`，绑定处用 `@Bindable`。
  - `AnalysisScheduler` 已改为 **`actor`**，暂停状态内聚其中。
  - 评分管线为「每批 200 张 + 批内并发 + 单事务批量落库 + 每批刷新一次界面 + 跳过已评美学分照片」。
  - 已删除 `thumbnail_cache_index` 表（migration v4 drop）。
- 出现编译错误时，优先用**最小改动**修复（补 `Sendable` / `@Sendable` / 显式 `self` / 类型标注 / `await` / 隔离标注等），不要为了绕过错误而改变上述行为或删功能。
- 改完每一处后**重新编译验证**，循环直到全绿。

## 1. 工程位置

- 仓库根目录：本文件所在目录。
- SwiftPM 包目录：`MantaPhotos/`（`Package.swift` 在此）。
- 目标平台：macOS 26，Swift 6（`swift-tools-version: 6.0`，启用严格并发）。

## 2. 本次改动涉及的文件（排查范围优先看这些）

新增：
- `MantaPhotos/Sources/MantaPhotosMac/App/NavigationState.swift`
- `MantaPhotos/Sources/MantaPhotosMac/App/PhotoLibraryViewModel.swift`
- `MantaPhotos/Sources/MantaPhotosMac/App/AnalysisViewModel.swift`
- `MantaPhotos/project.yml`、`MantaPhotos/Xcode/Info.plist`、`MantaPhotos/Xcode/MantaPhotosMac.entitlements`、`MantaPhotos/Xcode/generate-xcodeproj.sh`

改写：
- `MantaPhotos/Sources/MantaPhotosMac/App/AppState.swift`（退化为组合根 + 保留各枚举/值类型）
- `MantaPhotos/Sources/MantaPhotosMac/App/MantaPhotosMacApp.swift`（`@State` + `.environment(appState)`）
- `MantaPhotos/Sources/MantaPhotosMac/Domain/AnalysisScheduler.swift`（actor + 批量并发）
- `MantaPhotos/Sources/MantaPhotosMac/Infrastructure/Database/AnalysisRepository.swift`（批量方法 + 建 run 跳过已评分）
- `MantaPhotos/Sources/MantaPhotosMac/Infrastructure/Database/DatabaseMigrator.swift`（移除建表 + migration v4）
- 全部 Presentation 视图：`Shell/AppShellView.swift`、`Shell/SidebarView.swift`、`Photos/PhotosPageView.swift`、`Photos/PhotoViewerView.swift`、`Find/FindOverlayView.swift`、`Settings/SettingsPageView.swift`（迁移到 `@Environment` / `@Bindable`，属性路径改为 `appState.navigation/library/analysis.*`）
- `MantaPhotos/Tests/MantaPhotosMacTests/DatabaseMigratorTests.swift`（迁移数量断言 3→4）

## 3. 执行步骤（全部在仓库根目录运行）

```bash
# 1) 编译核心库与可执行目标
swift build --package-path MantaPhotos

# 2) 逻辑自检（迁移、FTS5、SQL 筛选、评分激活、暂停/继续/取消）
swift run --package-path MantaPhotos MantaPhotosChecks

# 3) 单元测试（Swift Testing）
swift test --package-path MantaPhotos
```

- 若步骤 1 报错：逐条读 `error:`，按第 0 节原则最小化修复，然后**重跑步骤 1**，直到通过。
- 步骤 1 通过后跑步骤 2、3；若失败同样定位修复并重跑，直到三步全绿。
- 常见可疑点（仅供参考，不要无脑套用）：
  - Swift 6 严格并发：`@Sendable` 闭包捕获、跨 actor 边界传递、`@MainActor` 隔离标注、闭包内显式 `self`。
  - Observation：`@Observable` 嵌套对象的读取/绑定、`@Bindable` 局部变量位置、`@Environment(AppState.self)` 注入是否齐全。
  - actor：`AnalysisScheduler` 内 `withThrowingTaskGroup` 的捕获与 `static func score` 调用。

## 4. 生成正式 .xcodeproj 并构建 .app

三步全绿后：

```bash
# 安装 XcodeGen（若未安装）
brew install xcodegen

# 生成 MantaPhotos.xcodeproj
cd MantaPhotos && ./Xcode/generate-xcodeproj.sh && cd ..

# 命令行构建 .app（验证 Info.plist / entitlements / Hardened Runtime 配置可用）
xcodebuild -project MantaPhotos/MantaPhotos.xcodeproj \
  -scheme MantaPhotosMac \
  -configuration Debug \
  -derivedDataPath MantaPhotos/.xcodebuild \
  build
```

- 若 `xcodebuild` 报签名相关错误且只为本地验证，可临时加 `CODE_SIGNING_ALLOWED=NO`。
- 构建产物 `.app` 在 `MantaPhotos/.xcodebuild/Build/Products/Debug/` 下。

## 5. 运行与回归重点

用 Xcode 打开 `MantaPhotos/MantaPhotos.xcodeproj` 并 Run，或直接 `open` 上面的 `.app`。重点回归：

1. **批量评分无闪烁**：点击 Score → 已加载照片 / 全部匹配；评分时照片墙不应整墙刷新闪烁，分数应**成批**出现（每 200 张刷新一次），用户基本无感。
2. **跳过已评分**：对已评过美学分的照片再次评分时不应重复评分（任务数应只含未评分照片）。
3. **暂停 / 继续 / 停止**：进度条与按钮状态正确，停止后任务标记 cancelled。
4. **CPU/GPU 利用**：长跑时观察是否并发跑满（活动监视器 / Instruments）。

## 6. 完成后

- 在 `MantaPhotos/开发进度.md` 的「验证记录」追加一行：日期、执行的命令、结果（通过/失败要点）。
- 如对源码做了修复，简述改了什么、为什么。

## 7. 权限说明（唯一需要用户参与处）

- App 首次运行会弹出**照片图库访问授权**弹窗，需要用户点「允许」。除此之外的编译、测试、生成工程、构建均自动进行，无需用户确认。
