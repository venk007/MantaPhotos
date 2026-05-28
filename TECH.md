# MantaPhotos - 技术设计与实现规格

> **文档版本:** v0.0.7  
> **创建日期:** 2026-05-26  
> **最后更新:** 2026-05-28  
> **作者:** Venk
> **状态:** 待评审  
> **关联文档:** [SPEC.md](SPEC.md)（产品需求与交互规格）

---

## 一、技术架构

### 1.1 技术栈总览

```
┌─────────────────────────────────────────────────────────┐
│                    macOS Tahoe 26.5                      │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────┐    │
│  │         SwiftUI (UI Layer, 液态玻璃风格)         │    │
│  │      AppKit (系统集成、窗口管理)                  │    │
│  └─────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────┐    │
│  │              Business Logic (Swift 6.0)           │    │
│  │ TaskScheduler │ PhotoAnalyzer │ ScoringEngine │    │
│  │ ReportManager │ SearchEngine │ DuplicateDetector │   │
│  └─────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────┐    │
│  │           ML Engine (MLX + CoreML)               │    │
│  │    MLX-VLM (Qwen) │ Vision │ NaturalLanguage    │    │
│  └─────────────────────────────────────────────────┘    │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐              │
│  │  Photos  │ │  SQLite  │ │ Spotlight│              │
│  │ Framework│ │   .swift │ │   Index  │              │
│  └──────────┘ └──────────┘ └──────────┘              │
└─────────────────────────────────────────────────────────┘
```

### 1.2 技术选型详表

| 技术模块 | 选型方案 | 版本要求 | 说明 |
|----------|----------|----------|------|
| **操作系统** | macOS Tahoe | 26.5+ | 2026年最新正式版 |
| **开发语言** | Swift | 6.0+ | macOS 26 捆绑 |
| **UI 框架** | SwiftUI | 5.0+ | macOS 原生 UI，液态玻璃风格 |
| **设计语言** | Apple Liquid Glass | 最新 | macOS Tahoe 最新设计语言 |
| **IDE** | Xcode | 16.5+ | macOS 26 开发必备 |
| **照片库访问** | Photos Framework | 最新 | 原生系统框架 |
| **AI 推理引擎** | **MLX-VLM** | 最新 | Apple Silicon 专用，支持 Qwen 系列 |
| **Vision 框架** | VisionKit | 最新 | 图像分析基础能力 |
| **自然语言处理** | NaturalLanguage | 最新 | 文本分析、搜索匹配 |
| **矢量存储** | SQLite.swift | 0.15+ | 本地元数据存储 |
| **系统搜索集成** | Core Spotlight | 最新 | 接入 macOS 搜索 |
| **并发任务** | Swift Concurrency | 最新 | async/await + actors |
| **进程间通信** | AppKit (NSApplication) | 最新 | 菜单栏、托盘图标 |
| **Markdown 渲染** | MarkdownUI / SwiftMarkdown | 最新 | 内嵌报告阅读器 |

### 1.3 MLX-VLM 技术说明

**什么是 MLX-VLM：**
- Apple 开源的 Apple Silicon 专用 ML 推理框架
- 官方支持 Qwen2-VL、Qwen2.5-VL、Qwen3-VL 系列
- 利用 Neural Engine + GPU 联合加速
- 内存效率高，支持模型流式加载

**模型下载源：**
- 官方源：`https://huggingface.co/mlx-community`
- 示例：`https://huggingface.co/mlx-community/Qwen3-VL-30B-A3B-Thinking-4bit`
- 推荐下载格式：`*.safetensors` + `*.json` 配置（BF16/FP16，**非 FP8/非 GGUF**）

**模型存储路径：** `~/Library/Application Support/MantaPhotos/Models/`

**模型运行能力参考（M3 Max 测试）：**

| 模型 | 照片分析速度 | 内存占用 | 推荐场景 |
|------|-------------|----------|----------|
| Qwen2.5-VL-3B | ~8 张/秒 | ~6GB | 日常快速处理 |
| Qwen2.5-VL-7B | ~4 张/秒 | ~12GB | 高质量分析 |
| Qwen3-VL-4B | ~6 张/秒 | ~8GB | ✅ **默认首选** |
| Qwen3-VL-8B | ~3 张/秒 | ~14GB | 高质量需求 |
| Qwen3-VL-30B-A3B | ~2 张/秒 | ~18GB | 最高质量（M3 Max） |

### 1.4 数据存储架构

```
┌─────────────────────────────────────────────────────────┐
│                    SQLite 数据库                         │
│            (~/Library/Application Support/              │
│             MantaPhotos/photos.db)                │
├─────────────────────────────────────────────────────────┤
│  表: photos                                             │
│  ├── id (TEXT, PRIMARY KEY) - Photos Framework 资源标识│
│  ├── local_identifier (TEXT)                             │
│  ├── ai_score (INTEGER) - 综合评分 0-100                 │
│  ├── aesthetics_score (REAL)                             │
│  ├── technical_score (REAL)                               │
│  ├── content_score (REAL)                               │
│  ├── emotion_score (REAL)                               │
│  ├── rarity_score (REAL)                               │
│  ├── uniqueness_score (REAL)                            │
│  ├── analysis_status (TEXT) - pending/running/done/failed│
│  ├── analysis_version (INTEGER) - 分析版本号             │
│  ├── created_at (TEXT)                                  │
│  ├── modified_at (TEXT)                                  │
│  └── is_duplicate (INTEGER) - 是否重复照片               │
├─────────────────────────────────────────────────────────┤
│  表: tags                                               │
│  ├── id (INTEGER PRIMARY KEY)                           │
│  ├── photo_id (TEXT, FK)                                │
│  ├── tag_category (TEXT) - 标签大类                     │
│  ├── tag_name (TEXT) - 标签名                           │
│  └── confidence (REAL) - 置信度 0-1                    │
├─────────────────────────────────────────────────────────┤
│  表: duplicate_groups                                   │
│  ├── group_id (TEXT PRIMARY KEY)                        │
│  ├── representative_id (TEXT) - 保留照片 ID             │
│  └── similarity_score (REAL)                            │
├─────────────────────────────────────────────────────────┤
│  表: analysis_tasks                                     │
│  ├── id (TEXT PRIMARY KEY)                              │
│  ├── photo_id (TEXT, FK)                                │
│  ├── task_type (TEXT) - score/tag/person/location/event │
│  ├── status (TEXT) - pending/running/done/failed        │
│  ├── priority (INTEGER)                                 │
│  ├── attempts (INTEGER) - 重试次数                       │
│  ├── error_message (TEXT)                               │
│  └── created_at / started_at / completed_at             │
├─────────────────────────────────────────────────────────┤
│  表: custom_tasks                                       │
│  ├── id (TEXT PRIMARY KEY)                              │
│  ├── name (TEXT) - 任务名称                             │
│  ├── prompt (TEXT) - 用户自定义提示词                   │
│  ├── result_example (TEXT) - 结果示例 JSON               │
│  ├── metric_fields (TEXT) - 指标字段 JSON 数组          │
│  │   [{ "name": "landmark_score", "type": "number" }]   │
│  ├── enabled (INTEGER) - 是否启用                      │
│  ├── created_at (TEXT)                                  │
│  └── updated_at (TEXT)                                  │
├─────────────────────────────────────────────────────────┤
│  表: custom_task_results                                │
│  ├── id (TEXT PRIMARY KEY)                              │
│  ├── photo_id (TEXT, FK)                                │
│  ├── custom_task_id (TEXT, FK)                          │
│  ├── results (TEXT) - 分析结果 JSON                     │
│  ├── created_at (TEXT)                                  │
│  └── UNIQUE(photo_id, custom_task_id)                   │
├─────────────────────────────────────────────────────────┤
│  表: reports                                            │
│  ├── id (TEXT PRIMARY KEY)                              │
│  ├── title (TEXT)                                       │
│  ├── content (TEXT) - Markdown 内容                      │
│  ├── report_type (TEXT) - initial/weekly/manual         │
│  ├── photo_count (INTEGER)                              │
│  ├── video_count (INTEGER)                              │
│  ├── avg_score (REAL)                                   │
│  ├── waste_suggestion_count (INTEGER)                   │
│  ├── created_at (TEXT)                                  │
│  └── updated_at (TEXT)                                  │
├─────────────────────────────────────────────────────────┤
│  表: scoring_weights_config                             │
│  ├── id (TEXT PRIMARY KEY)                              │
│  ├── dimension (TEXT) - 美学/技术/内容/情感/稀有/独特   │
│  ├── weight (REAL) - 权重 0.0-1.0                      │
│  └── updated_at (TEXT)                                  │
├─────────────────────────────────────────────────────────┤
│  表: settings                                           │
│  ├── key (TEXT PRIMARY KEY)                             │
│  └── value (TEXT)                                       │
└─────────────────────────────────────────────────────────┘
```

### 1.5 系统集成

| 集成项 | 实现方式 | 说明 |
|----------|----------|------|
| **菜单栏** | NSApplication / SwiftUI | 显示分析进度、暂停/继续 |
| **照片库监听** | PHPhotoLibraryChangeObserver | 实时增量更新 |
| **废纸篓** | PHAssetChangeRequest.deleteAssets() | 使用系统删除 |
| **Spotlight** | Core Spotlight API | 搜索结果同步 |
| **通知** | UserNotifications | 分析完成通知 |
| **系统设置** | System Settings（通过 deep link）| 权限设置 |

### 1.6 应用权限

| 权限 | Info.plist Key | 使用场景 |
|------|---------------|----------|
| 照片库 | NSPhotoLibraryUsageDescription | 读取/管理照片 |
| 照片库扩展 | NSPhotoLibraryAdditionsUsageDescription | 保存照片 |
| 通知 | (自动申请) | 分析完成通知 |

---

## 二、核心模块实现设计

> 本节对应 [SPEC.md](SPEC.md) 第二章中的功能需求，描述具体实现方案。

### 2.1 任务调度器 (TaskScheduler)

```
┌─────────────────────────────────────────────────────────┐
│                    任务调度器 (TaskScheduler)            │
├─────────────────────────────────────────────────────────┤
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐   │
│  │ 并行1   │  │ 并行2   │  │ 并行3   │  │ 并行4   │   │
│  │ 照片A   │  │ 照片C   │  │         │  │         │   │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘   │
│                                                         │
│  可配置: 1~4 个并行（默认2）                            │
│  优先级: P0 > P1 > P2                                  │
│  同一资源: 不同任务类型不能同时执行                       │
└─────────────────────────────────────────────────────────┘
```

**实现要点：**
- 使用 Swift `Actor` 封装调度器，保证线程安全
- 默认并行数 **2**，可配置范围 **1~4**（设置 → 分析设置 → 并行任务数）
- 同一照片资源上，不同任务类型串行执行，避免并发推理冲突
- 失败任务采用指数退避重试

**任务状态机：**

| 状态 | 行为 |
|------|------|
| ⏸️ 暂停 | 当前任务完成后停止取新任务 |
| ▶️ 继续 | 从队列暂停位置恢复 |
| ⏹️ 停止 | 清空队列，当前任务标记未完成 |
| 🔄 重试 | 对 `failed` 状态任务重新入队 |

### 2.2 首次分析与断点续传

**首次启动分析流程（实现逻辑）：**

```
1. 检测照片库规模
   ├── < 1000 项 → 直接全量分析
   └── >= 1000 项 → 进入分批策略

2. 分批策略（默认）
   ├── Step 1: 分析当年照片和视频
   ├── Step 2: 完成后弹出询问对话框
   └── Step 3: 用户确认后分析全量历史

3. 后台执行
   ├── 任务标记为 utility / userInitiated
   └── 菜单栏 + 侧边栏同步进度
```

**断点续传：**
- `photos.analysis_status` 与 `analysis_tasks` 表持久化进度
- 应用退出/崩溃后重启，跳过 `done` 状态资源
- 模型切换后递增 `analysis_version`，标记需重新分析的资源

### 2.3 评分引擎 (ScoringEngine)

**加权计算公式：**

```
final_score = Σ (dimension_score × weight)
```

默认权重见 [SPEC.md 附录 7.1](SPEC.md#71-默认评分权重可直接复制)，存储于 `scoring_weights_config` 表。

**权重变更后：** 提示用户选择全量/增量重新打分，结果写回 `photos` 表各维度字段。

### 2.4 重复照片检测 (DuplicateDetector)

```
检测逻辑：
1. 使用感知哈希（pHash）计算照片特征向量
2. 特征向量汉明距离 < 阈值(15) → 判定为相似/重复
3. 相似组内，美学分数最高的照片保留原分
4. 其他相似照片分数 = max(原分, 美学分) × 0.3（大幅降分）
5. 重复照片标记 is_duplicate = true，写入 duplicate_groups 表
```

### 2.5 AI 推理管线 (PhotoAnalyzer)

| 阶段 | 实现 |
|------|------|
| 输入 | Photos Framework 读取缩略图/原件（本地可用资源） |
| 推理 | MLX-VLM 多模态推理，按任务类型加载对应 Prompt |
| 解析 | JSON Schema 校验 + 容错解析 |
| 存储 | 写入 `photos` / `tags` / `custom_task_results` |
| 索引 | 更新 Core Spotlight 条目（Phase 8） |

### 2.6 模型下载管理器

| 能力 | 实现 |
|------|------|
| 下载源 | HuggingFace `mlx-community` 仓库 |
| 格式校验 | 仅接受 `.safetensors` + JSON 配置 |
| 存储 | `~/Library/Application Support/MantaPhotos/Models/{model_id}/` |
| 手动导入 | 文件选择器 + 目录结构校验 |
| 切换模型 | 卸载当前推理上下文，流式加载新模型 |

---

## 三、性能优化

### 3.1 内存优化

| 策略 | 说明 |
|------|------|
| **模型流式加载** | 不一次性加载整个模型到内存 |
| **批处理** | 多个照片合并为一个推理请求（batch） |
| **内存监控** | 内存紧张时自动降低并行数 |
| **虚拟内存** | 避免在 Apple Silicon 以外设备运行 |

### 3.2 CPU/GPU 优化

| 策略 | 说明 |
|------|------|
| **Neural Engine** | 优先使用 ANE 处理推理 |
| **GPU 加速** | Metal GPU 并行计算 |
| **任务优先级** | 用户前台任务优先于后台分析 |

### 3.3 后台执行优化

| 策略 | 说明 |
|------|------|
| **后台任务标签** | 标记为 `userInitiated` 或 `utility` |
| **低电量模式** | 电量低于 20% 时暂停分析 |
| **Mac 睡眠** | 睡眠时暂停，唤醒后继续 |
| **屏幕保护程序** | 激活时降低优先级 |

---

## 四、待开发任务（TODO）

### Phase 1：项目基础架构

- [ ] Xcode 项目创建（XcodeGen + project.yml）
- [ ] 项目目录结构设计
- [ ] SQLite 数据库层封装（建表、CRUD）
- [ ] Photos Framework 集成与授权
- [ ] SwiftUI 应用入口 + 窗口结构（液态玻璃风格）
- [ ] 菜单栏集成（进度显示、暂停/继续）
- [ ] Light/Dark Mode 支持

### Phase 2：AI 推理引擎

- [ ] MLX-VLM 集成（Core MLX-VLM 包接入）
- [ ] 模型下载管理器（HuggingFace mlx-community）
- [ ] 模型切换功能（设置页）
- [ ] 模型手动导入功能
- [ ] 照片打分 Prompt 解析引擎
- [ ] 照片标签 Prompt 解析引擎
- [ ] 人物识别逻辑引擎
- [ ] 地理位置解析引擎
- [ ] 时间/事件分析引擎
- [ ] 视频内容分析引擎

### Phase 3：自定义提示词与任务

- [ ] 提示词配置存储层（SQLite）
- [ ] 内置提示词默认内容生成与存储
- [ ] 用户自定义提示词编辑界面
- [ ] 自定义分析任务创建界面
- [ ] 自定义任务 Prompt 解析器
- [ ] 自定义任务结果存储（custom_task_results 表）
- [ ] 自定义指标字段与 AI 筛选集成

### Phase 4：评分系统

- [ ] 评分引擎核心（6维度加权计算）
- [ ] 评分权重配置界面
- [ ] 权重修改后重新打分流程
- [ ] 重复照片检测（pHash 感知哈希）
- [ ] 重复组管理 + 降分机制
- [ ] 重复照片展示视图

### Phase 5：任务调度系统

- [ ] 任务调度器核心（Actor 模型）
- [ ] 任务优先级队列（P0/P1/P2）
- [ ] 并行任务控制（1~4 可配置）
- [ ] 暂停/继续/停止功能
- [ ] 断点续传（状态持久化到 SQLite）
- [ ] 首次启动当年优先策略 + 询问弹窗
- [ ] 照片库变化监听（PHPhotoLibraryChangeObserver）
- [ ] 失败重试机制（指数退避）
- [ ] iCloud 资源状态检测 + 提示

### Phase 6：用户界面开发

- [ ] 照片网格视图（主视图，液态玻璃卡片）
- [ ] 照片详情视图（含所有 AI 分析结果标签）
- [ ] 时间线视图（旅行事件标注）
- [ ] 自然语言搜索页
- [ ] AI 筛选器（内置 + 自定义指标滑块）
- [ ] 删除功能（三步确认流程）
- [ ] 批量操作功能
- [ ] 侧边栏（标签过滤 + 分析进度）
- [ ] 设置页面
  - [ ] 模型选择 + 下载管理
  - [ ] 并行任务数配置
  - [ ] 首次分析策略配置
  - [ ] 评分权重配置（6维度滑块）
  - [ ] AI 提示词配置（每个任务类型可编辑）
  - [ ] 自定义任务管理

> UI 交互规格以 [SPEC.md 第八章](SPEC.md#八界面交互规范demo-实现版) 及 [`demo/`](demo/) 原型为准。

### Phase 7：报告系统

- [ ] 报告生成器（Markdown 格式）
- [ ] 报告数据库存储（reports 表）
- [ ] 报告列表视图
- [ ] Markdown 内嵌阅读器
- [ ] 报告删除功能

### Phase 8：系统集成

- [ ] 通知中心集成
- [ ] Spotlight 搜索集成（Core Spotlight）
- [ ] 废纸篓集成（Photos Framework API）
- [ ] 应用图标 + SF Symbols

### Phase 9：测试与优化

- [ ] 内存泄漏检测（Instruments）
- [ ] 性能基准测试
- [ ] 大库测试（10万+ 照片）
- [ ] Apple Silicon 优化
- [ ] 构建打包（.app + Homebrew Cask）

---

## 五、风险与挑战

| 风险 | 应对方案 |
|------|----------|
| 模型推理速度慢 | 优化 Prompt 长度，批量处理，降低并行 |
| 照片库太大，首次分析太长 | 分年分批，首次优先今年，随时可暂停 |
| 内存占用过高 | 可配置并行数，内存监控自动降级 |
| 模型切换后结果不一致 | 分析版本号管理，切换后标记需重新分析 |
| 自定义提示词格式错误 | 提供结果示例解析校验，错误时提示用户 |
| macOS 未来版本 API 变化 | 保持 targeting 最新 + 1 版本，优雅降级 |

---

## 六、开发计划估算

| 阶段 | 任务 | 预估工时 |
|------|------|----------|
| Phase 1 | 项目基础架构 | 2 天 |
| Phase 2 | AI 推理引擎 | 3 天 |
| Phase 3 | 自定义提示词与任务 | 2 天 |
| Phase 4 | 评分系统 | 2 天 |
| Phase 5 | 任务调度系统 | 3 天 |
| Phase 6 | 用户界面开发 | 4 天 |
| Phase 7 | 报告系统 | 1 天 |
| Phase 8 | 系统集成 | 1 天 |
| Phase 9 | 测试与优化 | 2 天 |
| **总计** | | **20 天** |

> 注：按每天 8 小时估算，实际进度会受模型调试、bug 修复和 UI 细节影响。

---

## 七、附录

### 7.1 HuggingFace mlx-community 模型参考地址

> ⚠️ 以下地址基于公开信息整理，实际地址以 HuggingFace 官方为准。下载前请确认模型格式为 `.safetensors`（非 FP8/非 GGUF）。

| 模型 | 参考下载地址 |
|------|------------|
| Qwen2.5-VL-3B | `https://huggingface.co/mlx-community/Qwen2.5-VL-3B` |
| Qwen2.5-VL-7B | `https://huggingface.co/mlx-community/Qwen2.5-VL-7B` |
| Qwen3-VL-4B | `https://huggingface.co/mlx-community/Qwen3-VL-4B` |
| Qwen3-VL-8B | `https://huggingface.co/mlx-community/Qwen3-VL-8B` |
| Qwen3-VL-30B-A3B | `https://huggingface.co/mlx-community/Qwen3-VL-30B-A3B-Thinking-4bit` |

### 7.2 Demo 原型 → SwiftUI 正式版映射

| Demo 文件 | 正式版目标 |
|-----------|------------|
| `demo/index.html` | SwiftUI 视图结构、导航路由 |
| `demo/css/style.css` | Liquid Glass 设计 Token、组件样式 |
| `demo/js/app.js` | ViewModel 状态与业务逻辑（筛选/时间线/配置） |

### 7.3 文档索引

```
MantaPhotos/
├── SPEC.md                    # 产品需求与交互规格
├── TECH.md                    # 本文档（技术设计与实现）
├── README.md                  # 项目介绍
├── demo/                      # 可交互 HTML 原型
├── docs/                      # 扩展设计文档（待创建）
└── src/                       # 项目代码（待创建）
```

### 7.4 文档版本记录

| 版本 | 日期 | 说明 |
|------|------|------|
| v0.0.1 | 2026-05-25 | 技术方案基线 |
| v0.0.2 | 2026-05-26 | 技术架构与模块边界成稿 |
| v0.0.3 | 2026-05-26 | 数据模型与存储方案成稿 |
| v0.0.4 | 2026-05-27 | 调度、评分与分析流程成稿 |
| v0.0.5 | 2026-05-27 | 搜索、筛选与报告实现方案成稿 |
| v0.0.6 | 2026-05-27 | Demo 到 SwiftUI 映射规范成稿 |
| v0.0.7 | 2026-05-28 | 当前评审版（与 SPEC、Demo 对齐） |

---

*文档由 Eliza (AI 助手) 生成，与 SPEC.md 配套使用。*
