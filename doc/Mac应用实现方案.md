# MantaPhotos Mac 应用实现方案

> 文档版本：v1.2  
> 创建日期：2026-06-06  
> 当前阶段：HTML/CSS/JS Demo 交互已可进入 Mac 原生实现  
> 关联文档：`SPEC.md`、`TECH.md`、`ROADMAP.md`、`doc/技术调研-macOS原生实现方案.md`

---

## 1. 目标与范围

当前 Demo 已完成照片主页、全局查找、快捷筛选、照片查看、时间线等核心交互设计，下一阶段目标是把这些已验证的产品行为落到 macOS 原生应用中。

Mac 应用第一阶段不追求一次性实现全部 AI 能力，而是先完成一个可运行、可导入、可浏览、可筛选、可持续扩展的原生骨架。阶段边界以 P0/P2 为准：**P0 不做 AI 相关开发；P1 实现打分能力，当前仅包含 Apple Vision 美学评分；P2 实现向量搜索能力；依赖自定义模型的打标签、人物分析、日记、独特性分析等能力放在 P4+，具体时间暂不承诺。**

- 接入系统照片库，读取照片、视频、Live Photo、截图等资产。
- 复刻 Demo 的照片主页、侧边栏快捷筛选、全局查找浮层、照片查看器。
- 建立本地数据库、筛选查询、缩略图缓存索引和后续分析所需的可扩展 schema。
- P1 使用 Apple Vision 做快速、低成本的美学评分。
- P2 接入 embedding、sqlite-vec 和向量检索，支持语义搜索基础能力。
- 为 MLX-VLM 深度分析、报告生成、自定义模型分析预留清晰接口。

---

## 2. 当前可实现功能基线

以下功能已经在 Demo 中完成交互验证，可直接作为 Mac 原生实现的功能基线。

| 功能模块 | Demo 状态 | Mac 原生实现目标 |
| --- | --- | --- |
| 照片主页 | 已完成 | 原生网格、7 级缩放、评分角标、排序、多选 |
| 侧边栏快捷筛选 | 已完成 | 类型、评分、时间、状态、设备、人物、标签实时过滤 |
| 全局查找浮层 | 已完成 | `⌘K` 唤起，自然语言 + 属性筛选统一入口 |
| 照片查看器 | 已完成 | 全屏查看、详情面板、快捷键、收藏/废片操作 |
| 时间线 | Demo 已完成主要交互（设计调整中） | Mac V1 仅创建导航菜单入口，完整时间线功能待 Demo 设计稳定后实现 |
| 报告页 | Demo 数据 | 先保留入口，后续接真实分析报告 |
| 设置页 | 已完成交互 | 模型、评分区间、权重、主题、并发设置 |
| 主题三态 | 已完成 | 跟随系统 / 浅色 / 深色 |

---

## 3. 技术选型结论

### 3.1 总体架构

```text
MantaPhotos.app
├── UI Layer
│   ├── SwiftUI：主界面、照片网格、设置、查找浮层
│   └── AppKit：窗口、菜单、快捷键、复杂滚动/选择优化
├── Domain Layer
│   ├── PhotoLibraryService：照片库访问与变化监听
│   ├── PhotoRepository：本地元数据读写
│   ├── FilterEngine：查找与快捷筛选
│   ├── AnalysisScheduler（actor）：后台分析任务调度，批量并发评分，内聚暂停状态
│   └── ScoringEngine：评分、标签、描述生成
├── AI Layer
│   ├── VisionAnalyzer：系统 Vision 快速分析
│   ├── CoreMLAnalyzer：可选自定义小模型
│   └── MLXVLMAnalyzer：可选深度多模态分析
└── Storage Layer
    ├── SQLite + GRDB：结构化元数据、任务、配置
    ├── FTS5：关键词搜索
    ├── sqlite-vec：向量检索，第二阶段接入
    └── Core Spotlight：系统级搜索索引，后置接入
```

### 3.2 UI 框架：SwiftUI + AppKit

**选择：SwiftUI 为主，AppKit 辅助。**

理由：

- SwiftUI 适合快速复刻 Demo 的声明式页面结构和设置类界面。
- macOS 原生窗口、菜单栏、快捷键、拖拽、右键菜单、滚动性能仍需要 AppKit 补位。
- 照片网格从 P0 开始直接使用 `NSCollectionView`，不使用 `LazyVGrid` 作为临时方案。

实现策略：

- SwiftUI 负责 App Shell、设置页、查找浮层、详情面板等声明式界面。
- `PhotoGridView` 从第一版开始就是 `NSViewControllerRepresentable` 包装的 `NSCollectionView`。
- 网格必须一次支持万级资产：复用 cell、可见区域加载、预取缩略图、取消过期请求、差量刷新。
- 未来不再从 SwiftUI 网格重构到 AppKit 网格，避免已有交互返工。

### 3.3 照片库接入：Photos Framework

**选择：Photos Framework 作为主入口，文件夹导入作为补充。**

核心 API：

- `PHAsset`：照片、视频、Live Photo 资产模型。
- `PHFetchResult`：分页/集合读取。
- `PHImageManager` / `PHCachingImageManager`：缩略图与原图请求。
- `PHPhotoLibraryChangeObserver`：监听系统照片库变化。
- `PHAssetChangeRequest`：收藏、删除等变更操作。

实现策略：

- 第一次启动请求照片权限。
- 首次导入只同步资产索引和关键元数据，不立即拉全尺寸原图。
- 缩略图按屏幕可见区域请求，使用 `PHCachingImageManager` 预热上下滚动区域。
- 原图、视频帧只在分析或查看详情时按需请求。
- 对 `.photoslibrary` 或普通文件夹导入，使用 Security-Scoped Bookmark 持久化用户授权。

### 3.4 本地存储：GRDB + SQLite

**选择：GRDB + SQLite，不优先使用 SwiftData。**

理由：

- 项目需要明确控制 schema、索引、批处理状态、迁移和查询性能。
- 搜索会用到 FTS5，后续向量检索需要 sqlite-vec 或同类 SQLite extension。
- 评分、筛选、报告、任务队列都适合直接建模为关系表。

核心表：

| 表 | 作用 |
| --- | --- |
| `photo_assets` | 照片资产元数据、状态、设备、媒体类型 |
| `photo_scores` | 美学、综合、技术、内容、情感、稀有、独特等维度分 |
| `tag_definitions` / `photo_tags` | 系统/用户标签字典与照片标签关联 |
| `person_entities` / `person_faces` / `photo_people` | 人物实体、脸部样本与照片人物关联 |
| `photo_locations` | 地点、经纬度、反向地理编码结果 |
| `albums` / `album_assets` | 相册与照片关联 |
| `analysis_tasks` | 待分析、运行中、失败、完成任务 |
| `search_filters` | 当前查找、侧边栏筛选、保存的常用筛选 |
| `photo_search_fts` | P1 关键词全文检索索引 |
| `media_segments` | 视频关键帧、片段、摘要的检索单位 |
| `photo_embeddings` | P2 向量元数据，接 sqlite-vec |
| `ai_models` / `analysis_runs` | AI 模型配置、分析批次、重分析追踪 |
| `app_settings` | 主题、语言、权重、分数档位、并发、模型配置 |
| `reports` | 分析报告与生成记录 |

### 3.5 搜索与筛选：结构化过滤优先，语义搜索后置

第一阶段先实现 Demo 中已验证的结构化过滤：

- 媒体类型：照片 / 视频 / Live / 截图 / RAW。
- 评分：美学 / 综合 / 技术 / 内容 / 情感 / 稀有 / 独特。
- 时间：今天 / 近 3 天 / 近一周 / 本月 / 近一月 / 本年。
- 状态：收藏 / 重复相似 / 废片篓。
- 设备与来源：手机 / Pocket / 运动相机 / 无人机 / 单反。
- 地点、人物、标签。

查询实现：

- UI 层维护 `SearchFilterState`。
- `FilterEngine` 将筛选状态转换为 SQL 查询。
- 关键词搜索走 FTS5。
- 自然语言第一阶段使用规则解析，P2 接本地 embedding + sqlite-vec，P4+ 再接 MLX/VLM 做语义增强。

### 3.6 向量搜索：1536 维语义空间 + sqlite-vec

**结论：MantaPhotos 需要向量搜索，默认语义 embedding 使用 1536 维；P0/P1 先完成结构化筛选和 FTS5，P2 接入 embedding、sqlite-vec 和向量搜索。依赖自定义模型的打标签、人物分析、日记、独特性分析等深度 AI 能力仍放在 P4+。**

原因：

- Demo 当前已经验证的是“照片主页 + 查找浮层 + 属性筛选”，这些用 SQL 条件和 FTS5 就能高质量实现。
- 向量搜索解决的是另一类问题：用户输入“像去年在海边那组照片”“有孤独感的夜景”“适合做封面的照片”这类语义查询。
- 向量能力依赖 embedding 生成和索引稳定性。P2 实现向量搜索所需的 embedding 生成、向量落库和检索；不在 P2 实现依赖自定义模型的标签、人物、日记、独特性等分析任务。

推荐路线：

| 阶段 | 搜索能力 | 技术 |
| --- | --- | --- |
| P0 | 基础列表、排序、类型/时间/状态过滤 | SQLite 普通索引 |
| P1 | 关键词、标签、地点、人物、设备、评分组合查询 | SQLite + FTS5 |
| P2 | 语义搜索、相似照片、按描述找照片 + 查询性能优化 | 1536 维 embedding + sqlite-vec + SQL rerank |
| P4+ | 自定义模型驱动的深度分析 | MLX/VLM + 自定义模型 Provider |

#### 是否需要 sqlite-vec

**建议使用 sqlite-vec，但要把它作为可替换的 Storage Adapter。**

sqlite-vec 的价值：

- 它是 SQLite extension，能和现有 SQLite 元数据表放在同一个本地数据库体系里。
- 支持 float / int8 / binary vectors，适合本地照片、视频、文本 embedding。
- 查询方式接近 KNN：给定 query embedding，返回距离最近的照片。
- 对 MantaPhotos 这种“本地、隐私、单机照片库”的产品，比单独引入向量数据库更轻。

需要注意：

- sqlite-vec 当前仍是 pre-v1，存在 API 变更风险。
- macOS App 打包时要处理 extension 加载、签名、公证和沙盒路径。
- 如果后续遇到上架或签名问题，要保留纯 Swift/SQLite BLOB 方案作为降级路径。

向量维度策略：

- **默认使用 1536 维**：作为 MantaPhotos 的主语义空间，覆盖文本、图像、视频片段的跨模态检索。
- **不把 768 维强行补到 1536 维**：不同维度代表不同 embedding space，不能混用或 padding。
- **按模型和维度建空间**：每个模型输出维度独立登记，查询时只在同一 `embedding_space` 内检索。
- **视频使用多粒度向量**：保存 `video_summary` 向量和关键帧 `video_frame` 向量，先召回视频，再定位关键帧。
- **Apple Vision feature print 单独存储**：用于视觉相似和去重，不和 1536 语义向量混在同一个 sqlite-vec 表。

建议抽象：

```swift
protocol VectorIndex {
    func upsert(_ item: VectorItem) async throws
    func search(_ request: VectorSearchRequest) async throws -> [VectorSearchHit]
    func delete(photoID: String, spaceID: String?) async throws
}

struct VectorItem {
    let photoID: String
    let segmentID: String?
    let spaceID: String
    let vector: [Float]
}

struct VectorSearchRequest {
    let spaceID: String
    let query: [Float]
    let limit: Int
    let filter: SearchFilterState?
}

struct VectorSearchHit {
    let photoID: String
    let segmentID: String?
    let distance: Double
}
```

实现：

- `VectorFeatureDisabledIndex`：仅表示向量功能未开启，不能用于生产搜索结果。
- `SQLiteVecIndex`：P2 正式接入 sqlite-vec，作为生产向量检索实现。
- `InMemoryVectorIndex`：仅用于单元测试和算法验证，不进入产品运行路径。

#### embedding 生成方案

照片向量建议分四类：

| 向量类型 | 来源 | 用途 |
| --- | --- | --- |
| `text_1536` | 描述、标签、地点、人物、回忆文本 | 自然语言找照片 |
| `image_1536` | 图像语义模型 | 图片语义搜索、以图搜图 |
| `video_1536` | 视频摘要/关键帧语义模型 | 视频语义搜索 |
| `vision_featureprint` | Apple Vision feature print | 视觉相似、重复/近重复检测 |

P2 可优先做 `text_1536` 和 `image_1536`：

- `text_1536` 先使用文件名、地点、时间、设备、媒体类型、已有用户/系统标签等确定性文本拼接生成。
- `image_1536` 使用 P2 选定的本地 embedding Provider 生成，不依赖用户自定义 VLM。
- P4+ 自定义模型生成的标签、人物、描述、日记等文本可作为后续增强输入，但不是 P2 向量搜索上线前置条件。
- 写入 sqlite-vec。

视频向量在 P2 后半段接入：先抽关键帧并生成 `video_1536`，再生成视频级摘要向量。

#### 数据表建议

结构化元数据仍放普通表，向量只保存可检索 embedding。

```sql
create table photo_embeddings (
  photo_id text not null,
  segment_id text,
  embedding_type text not null, -- text_1536 / image_1536 / video_1536 / vision_featureprint
  space_id text not null,
  model_id text not null,
  dimension integer not null,
  content_hash text not null,
  vector_rowid integer,
  updated_at text not null,
  primary key (photo_id, segment_id, embedding_type, model_id)
);

create table embedding_spaces (
  id text primary key,
  modality text not null,        -- text / image / video
  model_id text not null,
  dimension integer not null,
  metric text not null default 'cosine',
  active integer not null default 1,
  created_at text not null
);

-- sqlite-vec 虚拟表，P2 启用；不同维度/模型使用不同空间
create virtual table vec_text_1536 using vec0(
  embedding float[1536]
);

create virtual table vec_image_1536 using vec0(
  embedding float[1536]
);

create virtual table vec_video_1536 using vec0(
  embedding float[1536]
);
```

查询流程：

1. 用户输入自然语言。
2. 生成 query embedding。
3. 使用 sqlite-vec 取 Top K 候选照片。
4. 用 SQL 结构化筛选再次过滤：时间、评分、人物、设备、媒体类型等。
5. 结合距离、评分、时间新鲜度做 rerank。

#### 为什么不是只用 FTS5

FTS5 适合“关键词命中”，例如“南京”“海边”“截图”“猫”。

向量搜索适合“语义相近”，例如：

- “有电影感的夜景”
- “像壁纸一样干净的照片”
- “去年旅行里适合发朋友圈的照片”
- “找几张和这张构图类似的照片”

所以最终设计是 **SQL/FTS5 负责确定性条件，sqlite-vec 负责语义召回**。

### 3.7 GRDB 是什么

**GRDB 是 Swift 生态里成熟的 SQLite 工具库。**

它不是新的数据库，而是 Swift 应用访问 SQLite 的一层高质量封装：

- 管理 SQLite 连接、读写队列和事务。
- 提供类型安全的 SQL 查询和记录映射。
- 支持数据库迁移。
- 支持观察数据库变化，适合驱动 SwiftUI 列表刷新。
- 保留直接写 SQL 的能力，适合 FTS5、复杂筛选、后续 sqlite-vec。

在 MantaPhotos 里的定位：

```text
SwiftUI View
   ↓
PhotoRepository / SearchRepository
   ↓
GRDB
   ↓
SQLite / FTS5 / sqlite-vec
```

为什么不用 SwiftData 作为主存储：

- SwiftData 更适合常规对象持久化。
- MantaPhotos 需要大量手写 SQL、FTS5、向量扩展、批量任务、复杂索引和可控迁移。
- GRDB 更贴近 SQLite 本身，后续接 sqlite-vec 更自然。

### 3.8 AI 分析：P1 打分 + P2 向量搜索 + P4+ 自定义模型分析

**结论：P0 不做 AI 相关开发；P1 实现打分能力，当前仅使用 macOS 内置 Apple Vision 框架进行美学评分；P2 实现向量搜索，包括 embedding 生成、sqlite-vec 索引和语义检索。其他依赖自定义模型的 AI 分析能力，包括打标签、人物分析、照片日记、独特性分析、VLM 描述和自定义模型覆盖，统一放在 P4+，具体实现时间暂不确认。**

硬件加速原则：

- Apple Vision / Core ML 作为批量分析默认层，由系统调度 CPU、GPU、Neural Engine，目标是低功耗、低内存、后台可持续运行。
- 不在业务代码里手动绑定 ANE。Core ML/Vision 的运行时会根据模型、设备和系统状态选择合适 compute unit。
- 自定义 Core ML 小模型优先使用默认 compute units；当用户同时进行重 GPU 工作时，可在设置中提供“低干扰模式”，把自定义模型限制到 CPU/Neural Engine 组合。
- MLX / VLM 类自定义大模型不进入 P0/P1/P2 范围；后续 P4+ 即使启用，也默认不参与全量扫描，只对用户主动选择、高分候选、报告生成等任务按需运行。

Vision 与用户模型分工：

| 层级 | 默认模型 | 使用时机 | 目标 |
| --- | --- | --- | --- |
| 快速基础层 | Apple Vision 内置能力 | P1 后台扫描 | 美学评分 |
| 向量搜索层 | 本地 embedding Provider + sqlite-vec | P2 后台索引和查询 | 语义搜索、相似召回、向量与结构化筛选融合 |
| 个性化增强层 | 用户导入 Core ML / MLX 模型 | P4+，用户开启模型、局部重分析 | 自定义标签、个性化评分、特殊领域识别 |
| 深度理解层 | 本地 VLM / 外部自定义大模型 | P4+，高分照片、选中集合、报告生成 | 描述、回忆、保留建议、复杂语义 |

分析策略：

| 策略 | 默认任务 | 适用用户 | 资源特征 |
| --- | --- | --- | --- |
| `fast` 极速 | Vision 美学分 | P1 默认策略 | 低功耗，适合首次导入 |
| `balanced` 均衡 | Vision 美学分 + P2 向量索引 | P2 默认策略 | 兼顾搜索能力和性能 |
| `complete` 完整 | P4+ 待定义 | 后续确认 | 自定义模型能力启用后再定义 |

平台版本策略：

| 能力 | API | 策略 |
| --- | --- | --- |
| 美学评分 | `VNCalculateImageAestheticsScoresRequest`，结果读取 `VNImageAestheticsScoresObservation` | P1 实现；编译期和运行时都做 availability guard，不可用时关闭美学评分 |
| 向量搜索 | P2 本地 embedding Provider + sqlite-vec | P2 实现；不同模型、维度、模态必须隔离在不同 `embedding_space` |
| 图像分类 | `VNClassifyImageRequest` | P4+ 待确认 |
| OCR | `VNRecognizeTextRequest` | P4+ 待确认 |
| 人脸检测 | `VNDetectFaceRectanglesRequest` | P4+ 待确认 |
| 视觉相似 | `VNGenerateImageFeaturePrintRequest` 或 P2 image embedding | P2 可作为相似召回能力；人物/标签分析仍 P4+ |

产品最低版本决策：

- Mac 版以 **macOS Tahoe 26.5+ / Xcode 16.5+** 作为主技术栈和部署目标，后续可继续升级到更新甚至未发布的 macOS 技术栈。
- 不为旧版 macOS 牺牲主路径设计；如果后续需要兼容旧系统，只通过能力降级处理，不重写核心架构。

P1 实现：Apple Vision 美学评分：

| 能力 | 技术 | 输出 | 阶段 |
| --- | --- | --- | --- |
| AI 美学评分 | `VNCalculateImageAestheticsScoresRequest` | `photo_scores.aesthetic_score`、美学角标 | **P1** |
| 截图识别 | `PHAsset.mediaSubtype` | `photo_scores.is_screenshot`，强制 aesthetic_score = 0 | **P1** |
| 向量搜索 | 本地 embedding Provider + sqlite-vec | `embedding_spaces`、`photo_embeddings`、`vec_*_1536` | **P2** |
| 图像分类/自动标签 | `VNClassifyImageRequest` | `tag_definitions` + `photo_tags` | P4+ 待确认 |
| 人脸检测 | `VNDetectFaceRectanglesRequest` | `person_faces.bounding_box_json` | P4+ 待确认 |
| 人脸质量/可用性 | Vision face quality/landmark 相关 request | `person_faces.quality_score` | P4+ 待确认 |
| 人物归纳 | App 内聚类 + 用户确认 | `person_entities`、`photo_people` | P4+ 待确认 |
| OCR/截图内容识别 | `VNRecognizeTextRequest` | 标签、搜索文本 | P4+ 待确认 |
| 视觉相似/语义相似 | P2 image embedding / Vision feature print | 相似召回、以图搜图候选 | P2 |

#### 截图识别与美学评分强制为 0

P1 通过 Photos Framework 的资产元数据识别截图，无需额外 AI 推断：

- `PHAsset.mediaSubtype.contains(.photoScreenshot)`：系统识别的截图资产
- 导入 `photo_assets` 时写入 `photo_scores.is_screenshot = 1`
- 执行 Vision 美学评分时，若 `is_screenshot = 1`，强制将 `aesthetic_score` 覆盖为 `0.0`，忽略 `VNCalculateImageAestheticsScoresRequest` 返回值
- 此逻辑封装在 `AppleVisionProvider` 内部，对上层 `AnalysisScheduler` 透明

```swift
// AppleVisionProvider 内部伪代码
let isScreenshot = asset.mediaSubtype.contains(.photoScreenshot)
let rawScore = isScreenshot ? 0.0 : try await visionRequest.overallScore
await repository.writeScore(photoID: asset.id, aesthetic: rawScore, isScreenshot: isScreenshot)
```

#### 照片内容描述与照片回忆任务（设计预留，P4+ 待确认）

P4+ 之后可在策略接口基础上新增以下两个**独立的** VLM 分析任务，两者分别维护各自的任务类型、提示词和输出字段，不可合并；具体实现时间暂不确认：

**`vlmDescription`（照片内容描述，≤300字）**

- 任务触发时机：高分照片、用户手动选择、报告生成
- 提示词：描述拍摄主体与场景，补充植物/动物/食物等对象的简短科普信息
- 输出字段：`analysis_outputs` 中 `output_type = 'description'`，内容写入照片详情面板
- 字数限制：300字以内

**`vlmDiary`（照片回忆，≤200字）**

- 任务触发时机：与 `vlmDescription` 相同，但作为独立任务单独调度
- 提示词：基于同行人、时间、城市、行程生成当日叙事与心情分析
- 输出字段：`analysis_outputs` 中 `output_type = 'diary'`，内容写入照片详情面板
- 字数限制：200字以内
- 注意：`vlmDiary` 与 `vlmDescription` 是**完全独立的两个任务**，分别创建 `analysis_tasks` 记录，分别配置提示词，不共享上下文

人物识别说明（P4+ 待确认，P0/P1/P2 暂不实现）：

- Vision 可以高效检测人脸、质量、特征与相似性，但人物实体归纳要由 MantaPhotos 自己维护。
- 系统自动聚类会创建 `person_entities(source=system_cluster)`。
- 用户命名、合并、拆分后，`user_confirmed=1`，后续 AI 重分析不得覆盖用户确认结果。
- 用户导入模型可以生成新的 face embedding 或人物分类结果，但只能生成新的 `analysis_run` 和 `analysis_outputs`，由合并策略决定是否激活。

自定义模型覆盖能力（P4+ 待确认，P0/P1/P2 暂不实现）：

| 能力 | 用户模型形式 | 作用 |
| --- | --- | --- |
| 美学评分覆盖 | MLX-VLM（如 Qwen VL） | 覆盖 Apple Vision 美学评分结果 |
| 高级标签 | Core ML / MLX / GGUF 视觉模型 | 覆盖或增强 Apple Vision 标签 |
| 语义描述 | MLX-VLM | 生成照片描述、回忆、保留建议 |
| embedding | 本地 embedding 模型 | 生成 1536 维 text/image/video 向量 |
| 自定义评分 | 用户导入模型或 prompt | 生成个性化分数维度 |

策略模式：

```swift
protocol AIAnalysisProvider {
    var modelID: String { get }
    var providerKind: AIProviderKind { get }
    var supportedTasks: Set<AnalysisTaskType> { get }
    var outputSchemaVersion: Int { get }

    func analyze(_ request: AnalysisRequest) async throws -> AnalysisResult
}

enum AIProviderKind: String {
    case appleBuiltin
    case userImported
}

enum AnalysisTaskType: String {
    // P1 实现
    case visionAesthetics      // Apple Vision 美学评分（含截图强制为0）

    // P2 实现
    case textEmbedding1536
    case imageEmbedding1536
    case videoEmbedding1536

    // P4+ 待确认
    case classifyTags
    case detectFaces
    case clusterPeople
    case ocr
    case featurePrint
    case vlmDescription        // 照片内容描述（≤300字），独立任务
    case vlmDiary              // 照片回忆（≤200字），独立任务，与 vlmDescription 分开
}
```

Provider 规划：

| Provider | 阶段 | 职责 |
| --- | --- | --- |
| `AppleVisionProvider` | **P1** | 美学评分（含截图强制为0）；分类标签、人脸检测、OCR、feature print 等能力仅作为 P4+ 扩展点 |
| `EmbeddingProvider1536` | **P2** | 生成 text/image/video 1536 维向量，用于语义搜索和相似召回，不依赖用户自定义模型 |
| `PeopleClusterProvider` | P4+ 待确认 | 基于人脸样本进行聚类、合并建议 |
| `UserCoreMLProvider` | P4+ 待确认 | 用户导入 Core ML 模型 |
| `UserMLXProvider` | P4+ 待确认 | 用户导入 MLX / MLX-VLM 模型（美学评分覆盖、描述、回忆等） |

任务重跑与结果覆盖机制：

1. 每次分析都先创建 `analysis_runs`，记录 `task_type`、模型快照、配置快照、目标范围和触发原因。
2. `analysis_tasks` 必须绑定 `analysis_run_id`，唯一键为 `(analysis_run_id, photo_id, task_type)`，允许同一照片在不同批次中重新分析。
3. 调度器恢复时只领取 `pending` / 可重试 `failed` 任务；`completed` 任务不重复执行，保证中断恢复无需重跑已完成照片。
4. P1 美学评分结果先写入 `analysis_outputs(active=0)`，再在同一事务内更新 `photo_scores` 的 `analysis_run_id`、`analysis_output_id`、`model_id`、`score_version`、`scored_at`。
5. 同一照片同一 `output_type='score.aesthetic'` 只有一个 active 输出；新批次激活时将旧输出置为 `active=0` 并写入 `superseded_at`。
6. `photo_scores` 永远指向当前最新分数所属的批次和输出；需要追溯时通过 `analysis_run_id -> ai_models` 识别是哪个模型、什么配置、什么时间跑出的结果。
7. 如果用户未来回退模型或批次，可按 `analysis_outputs` 恢复上一批 active 输出，并同步回写 `photo_scores`。

覆盖策略：

| 数据类型 | 自动重分析是否可覆盖 | 规则 |
| --- | --- | --- |
| 美学/综合评分 | 可以 | 新 active run 覆盖旧 active run |
| AI 标签 | 可以 | 只覆盖同来源/同模型自动标签，不删用户标签 |
| 用户标签 | 不可以 | 永远保留，除非用户删除 |
| 人脸聚类 | 可新增建议 | 不覆盖用户确认的命名、合并、拆分 |
| 人物命名 | 不可以 | 用户命名优先 |
| embedding | 可以 | 按 `space_id + model_id + dimension` 并存 |
| 描述/回忆 | 可以 | 保留历史版本，可回滚 |

### 3.8.1 状态管理与评分调度（2026-06-07 评审整改）

原 `AppState` 同时管理路由、主题语言、网格、筛选、照片结果、导入进度、分析调度、暂停/恢复、查看器等，正在膨胀为 God Object。在 P2 起步前做架构清理：

- **采用 Observation 框架（`@Observable`）拆分状态**（Apple 在 macOS 14+ 的最新成熟方案，本工程目标 macOS 26）。`AppState` 退化为**组合根**，只负责 bootstrap、设置持久化、把数据库连接注入子对象，并持有三个职责单一的对象：
  - `NavigationState`：路由、主题、语言、网格密度、角标指标、侧栏/查找浮层呈现、`localized`。
  - `PhotoLibraryViewModel`：筛选条件、照片结果、分页、导入进度、查看器选择与收藏/废片/删除。
  - `AnalysisViewModel`：评分进度与发起/暂停/继续/停止/重试控制。
- 视图统一用 `@Environment(AppState.self)`，按 `appState.navigation/library/analysis` 访问；`@Observable` 的嵌套属性读取可被 SwiftUI 精确追踪，绑定处用 `@Bindable`。
- **`AnalysisScheduler` 由 `struct` 改为 `actor`**：暂停状态（`isPauseRequested`）内聚到调度器内部，移除 `AppState.isAnalysisPauseRequested`；获得编译器级隔离保证。上层通过 `await scheduler.pause()/resume()` 控制，不再传 `shouldPause` 闭包。
- **移除 `thumbnail_cache_index` 表**：`PHCachingImageManager` 已提供完整的内存/磁盘缩略图缓存与可见区预热，再维护该表只增加写库 IO 而无增量价值。p0CoreSQL 移除建表，新增 migration v4 `drop table if exists`。

### 3.8.2 批量评分性能方案（2026-06-07 评审整改）

旧实现逐张评分、每张都全量 `refreshPhotos()` 刷新照片墙，导致界面闪烁、吞吐低。新方案：

1. **跳过已评分**：建 `analysis_runs` 时按 `photo_scores` 过滤，已有美学分的照片不再入队（曾失败、无分数的照片会被重新入队）。截图强制 0 也会落库，故下次自动跳过；P4+ 的 AI 评分仍可被覆盖（切换模型 / 修改提示词后重评，不受美学跳过规则限制）。
2. **批量领取**：每批从数据库领取 `batchSize = 200` 个 `pending` 任务。
3. **批内并发评分**：用 `withThrowingTaskGroup` 以 `min(activeProcessorCount, 8)` 的并发度同时跑 `VNCalculateImageAestheticsScoresRequest`，配合 `Task.detached` 把 Vision 推理放到后台线程，充分利用 CPU/GPU/ANE。
4. **单事务批量落库**：一批结果在一个数据库事务内批量写 `analysis_outputs` + `photo_scores` + 任务状态（`AnalysisRepository.activateAestheticScores`），再按 run 统一刷新计数。
5. **整轮结束后只刷新一次界面（2026-06-08 修正）**：评分时进度条由 `progressHandler` 实时更新，但照片墙**不再逐批刷新**——`AnalysisViewModel` 不再传 `didScoreBatch`，改为在整轮（完成 / 取消 / 失败）结束后调用一次 `refreshPhotos()`。原因：每批 `refreshPhotos()` 会全量重查数据库并对所有可见 cell 重新发起缩略图请求，评分进行中持续重拉缩略图是主要卡顿来源。代价是评分过程中分数不再边评边显，整轮结束统一出现，换取评分期间的滚动流畅。
6. **暂停响应**：在每批边界检查 `isPauseRequested`；停止通过 Task 取消 + `cancelRun` 落库。

### 3.9 图片与视频处理

结论：HEIC 照片在 macOS 下提供给外部自定义大模型分析时，**最佳主路径是 ImageIO 全内存解码、缩放、编码为 JPEG Data，再直接传给模型客户端**。不能把 `sips`、`ffmpeg`、Photos 导出文件、全尺寸 CGContext 重绘作为主路径，否则万级图库分析会被磁盘 IO、临时文件清理和内存峰值拖垮。

选择：

- 图片解码：ImageIO。
- 视频关键帧：AVFoundation `AVAssetImageGenerator`。
- 缩略图：Photos Framework + `PHCachingImageManager`。
- 外部模型输入：`ExternalModelMediaPreprocessor` 统一生成 in-memory JPEG `Data`。

原则：

- 不把 HEIC/HEVC 原始资产批量转储到磁盘。
- AI 分析输入与 UI 缩略图缓存分离：AI 预处理默认零磁盘写入；UI 缩略图允许写入 App cache。
- 分析输入必须在解码阶段或解码后立即缩放到目标尺寸，禁止先解码全尺寸大图再统一缩放。
- 外部模型如果支持 `Data` / multipart / base64，必须直接使用内存 JPEG；只有模型进程硬性要求文件路径时，才创建短生命周期临时文件，并在任务结束后删除。
- 视频先抽关键帧，P0/P1 只建立封面/代表帧能力；P2 进行分段多帧采样与视频摘要向量。

#### 3.9.1 HEIC 照片到外部模型 JPEG 输入

主流程：

```text
PHAsset / file URL
  -> 原始图片 Data 或安全授权 URL
  -> CGImageSource
  -> CGImageSourceCreateThumbnailAtIndex(maxPixelSize, transform)
  -> CGImageDestination JPEG encode(to NSMutableData)
  -> ExternalModelClient.analyzeImage(jpegData)
```

推荐参数：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `maxPixelSize` | 1536 | 与默认 1536 维 embedding 策略匹配，兼顾图像语义与性能 |
| 快速模式 `maxPixelSize` | 1024 | 低内存或批量快速分析使用 |
| 高质量模式 `maxPixelSize` | 2048 | 用户手动深度分析或 OCR/细节敏感模型使用 |
| JPEG quality | 0.85 | 语义分析默认足够，减少传输与内存 |
| OCR/文字敏感 quality | 0.90 | 保留更多边缘细节 |
| `kCGImageSourceShouldCache` | false | 避免 ImageIO 提前缓存全尺寸图 |
| `kCGImageSourceCreateThumbnailWithTransform` | true | 处理 EXIF 方向 |

实现要求：

- `ExternalModelMediaPreprocessor` 必须封装 HEIC/JPEG/PNG/TIFF 等图片格式差异，上层 AI provider 只接收统一的 `ModelImageInput`。
- 使用 `CGImageSourceCreateThumbnailAtIndex` 控制最大边长，优先让 ImageIO 在解码路径完成下采样。
- 使用 `CGImageDestinationCreateWithData` 将缩放后的 `CGImage` 编码为 JPEG `Data`。
- 外部 HTTP 模型使用 multipart body 直接上传 `jpegData`；外部本地进程优先通过 stdin、Unix socket、HTTP localhost 或 SDK 传入 bytes。
- 临时文件只作为兼容 fallback，必须写入 `FileManager.default.temporaryDirectory/MantaPhotos/analysis/{taskId}.jpg`，任务完成、失败、取消都清理。

禁用主路径：

- 禁止 P0/P1 用 `sips` 批量转换 HEIC 到磁盘 JPEG。
- 禁止 P0/P1 用 `ffmpeg` 处理静态 HEIC。
- 禁止先导出原图再交给外部模型。
- 禁止对万级图库创建长期 JPEG 副本库。

#### 3.9.2 HEVC 视频到外部模型 JPEG 输入

主流程：

```text
PHAsset / video URL
  -> AVAsset
  -> AVAssetImageGenerator
  -> 按时间点抽取 CGImage
  -> CGImageDestination JPEG encode(to NSMutableData)
  -> ExternalModelClient.analyzeVideoFrames([jpegData])
```

推荐参数：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `appliesPreferredTrackTransform` | true | 保持视频方向正确 |
| `maximumSize` | 1536 长边 | 控制关键帧尺寸 |
| P1 抽帧 | 1-3 帧 | 封面帧、中间帧、结尾前帧 |
| P2 抽帧 | 分段采样 | 按视频长度和场景变化策略采样 |
| 并发 | 低于图片并发 | 视频解码更重，避免阻塞 UI 与照片分析 |

实现要求：

- 视频关键帧也走内存 JPEG，不把 HEVC 片段或关键帧批量写盘。
- P0/P1 只建立视频资产、封面和少量代表帧分析能力。
- P2 开始落库 `media_segments`、`media_frame_embeddings`，支持视频片段级搜索。
- `VideoToolbox` 作为系统硬件解码底层能力，由 AVFoundation 路径间接使用；只有遇到低层编解码控制需求时再直接引入。

#### 3.9.3 方案对比与结论

| 方案 | 是否主路径 | 性能 | 磁盘 IO | 适用场景 |
| --- | --- | --- | --- | --- |
| ImageIO `CGImageSource` + `CGImageDestination` | 是 | 高 | 无 | HEIC/JPEG/PNG 到外部模型 JPEG 输入 |
| AVFoundation `AVAssetImageGenerator` | 是 | 高 | 无 | HEVC/H.264 视频关键帧输入 |
| Photos Framework 缩略图缓存 | 是，但仅 UI | 高 | 有缓存 | 网格、预览、滚动复用 |
| Photos 导出原图到文件 | 否 | 中 | 高 | 用户明确导出、调试 |
| `sips` CLI 批量转换 | 否 | 中低 | 高 | 手工排查，不进入 App 主链路 |
| `ffmpeg` 批量转换 | 否 | 中 | 高 | 特殊格式兜底，不作为 P0/P1 依赖 |
| 全尺寸 CGContext 解码后缩放 | 否 | 低 | 无 | 小图 fallback，不用于批量图库 |

最终设计决定：

- **HEIC 照片外部模型分析**：ImageIO 全内存转换为 JPEG `Data` 是标准实现。
- **HEVC 视频外部模型分析**：AVFoundation 抽关键帧 + ImageIO 编码为 JPEG `Data` 是标准实现。
- **缩略图缓存与 AI 输入分离**：UI 可使用磁盘缓存保证滚动性能，AI 预处理不创建长期文件。
- **外部模型兼容层独立**：所有模型输入格式差异都在 `ExternalModelMediaPreprocessor` 和 `ExternalModelClient` 中消化，不污染 UI、数据库和调度器。

### 3.10 系统集成

| 能力 | 技术 | 阶段 |
| --- | --- | --- |
| 系统搜索 | Core Spotlight | P2 |
| 通知 | UserNotifications | P1 |
| 菜单栏状态 | AppKit / MenuBarExtra | P1 |
| 快捷键 | SwiftUI commands + AppKit event monitor | P0 |
| 权限跳转 | NSWorkspace 打开系统设置 | P0 |
| 文件夹授权 | Security-Scoped Bookmark | P1 |

---

## 4. P0/P2 数据库表设计

P0/P2 的数据库目标不是一次性覆盖全部 AI 能力，而是支撑 UI 框架、真实照片读取、照片主页、查找浮层、筛选交互、设置页、主题与语言切换、P1 Apple Vision 美学评分，以及 P2 向量搜索。表结构必须从第一天就可迁移、可扩展、可压测。

### 4.1 P0 建库原则

- **UI 优先**：表字段优先支撑列表、网格、筛选、排序、设置持久化。
- **轻量导入**：首次导入只写元数据，不写原图，不生成向量。
- **可增量分析**：P1 补齐美学评分，P2 补齐 embedding 与向量索引；标签、人物、日记、独特性等依赖自定义模型的 AI 能力放在 P4+。
- **可迁移**：所有 schema 变更必须走 GRDB migration。
- **中英双语兼容**：数据库保存稳定 key，不保存 UI 文案。文案走 String Catalog。
- **主题三态兼容**：设置中保存 `system` / `light` / `dark`，运行时映射到 SwiftUI `preferredColorScheme`。

### 4.2 P0/P2 建表清单

| 表 | 阶段 | 作用 |
| --- | --- | --- |
| `schema_migrations` | P0 | 记录数据库迁移版本 |
| `app_settings` | P0 | 语言、主题、网格列数、评分角标、并发等设置 |
| `photo_assets` | P0 | 系统照片资产基础元数据，含 App 内废片篓标记与 iCloud 状态字段 |
| `tag_definitions` | P0 | 系统/AI/用户标签字典；P0/P1 允许为空，保证筛选结构稳定 |
| `photo_tags` | P0 | 照片与标签的多对多关联；P0/P1 无数据时相关筛选返回空结果 |
| `person_entities` | P0 | 人物实体；P0/P1 无数据时相关筛选返回空结果 |
| `person_faces` | P0 | 人脸样本预留表；P0/P1 不做人脸检测 |
| `photo_people` | P0 | 照片与人物的多对多关联 |
| `photo_locations` | P0 | 地点筛选和时间线聚合 |
| `albums` | P0 | 系统相册/智能相册/用户导入集合 |
| `album_assets` | P0 | 相册与照片资产关联 |
| `search_filters` | P0 | 保存查找/筛选状态和常用查找 |
| ~~`thumbnail_cache_index`~~ | 已移除（2026-06-07） | 由 `PHCachingImageManager` 内置缓存与可见区预热替代，避免无谓写库 IO；migration v4 已 drop |
| `photo_search_documents` / `photo_search_fts` | P1 | 文件名、标签、人物、地点、AI 文本的全文检索 |
| `photo_scores` | P1 | 写入真实 Apple Vision 美学分，记录分数所属批次、模型和输出 |
| `ai_models` | P1 | 登记 Apple Vision 内置美学评分模型；用户模型放 P4+ |
| `analysis_runs` | P1 | 每次美学评分或重跑的分析批次 |
| `analysis_tasks` | P1 | 后台美学评分任务队列 |
| `analysis_outputs` | P1 | 美学评分输出的版本化结果，支持覆盖和回滚 |
| `media_segments` | P2 | 视频关键帧、片段和摘要向量的业务锚点 |
| `embedding_spaces` | P2 | 管理向量模型、维度、模态和启用状态 |
| `photo_embeddings` | P2 | 照片/视频片段到向量虚拟表 rowid 的元数据映射 |
| `vec_text_1536` | P2 | 1536 维文本语义向量检索 |
| `vec_image_1536` | P2 | 1536 维图像语义向量检索 |
| `vec_video_1536` | P2 | 1536 维视频语义向量检索 |
| `timeline_events` | P0 建空表 | 时间线页面骨架和后续事件聚合 |
| `reports` | P0 建空表 | 报告页骨架和后续报告生成 |

### 4.3 P0/P2 SQL 初版

```sql
create table schema_migrations (
  version integer primary key,
  name text not null,
  applied_at text not null
);

create table app_settings (
  key text primary key,
  value text not null,
  value_type text not null default 'string',
  updated_at text not null
);

create table photo_assets (
  id text primary key,
  local_identifier text not null unique,
  media_type text not null,            -- image / video / live / screenshot / raw / unknown
  media_subtypes integer not null default 0,
  filename text,
  uniform_type_identifier text,
  pixel_width integer not null default 0,
  pixel_height integer not null default 0,
  duration real,
  creation_date text,
  modification_date text,
  imported_at text not null,
  updated_at text not null,
  favorite integer not null default 0,
  hidden integer not null default 0,
  in_trash integer not null default 0,      -- App 内废片篓标记，不等同系统删除
  trashed_at text,
  source_type text not null default 'photos_library', -- photos_library / folder / file
  device_make text,
  device_model text,
  device_category text,                -- phone / camera / action_camera / drone / pocket / unknown
  location_id text,
  analysis_status text not null default 'pending',
  analysis_version integer not null default 0,
  thumbnail_state text not null default 'pending',
  icloud_state text not null default 'unknown', -- unknown / not_cloud / local / remote / downloading
  is_locally_available integer,
  resource_availability_checked_at text,
  is_deleted_locally integer not null default 0,
  system_deleted_at text
);

create index idx_photo_assets_media_type on photo_assets(media_type);
create index idx_photo_assets_creation_date on photo_assets(creation_date);
create index idx_photo_assets_favorite on photo_assets(favorite);
create index idx_photo_assets_in_trash on photo_assets(in_trash);
create index idx_photo_assets_device_category on photo_assets(device_category);
create index idx_photo_assets_analysis_status on photo_assets(analysis_status);
create index idx_photo_assets_icloud_state on photo_assets(icloud_state, is_locally_available);

create table photo_scores (
  photo_id text primary key references photo_assets(id) on delete cascade,
  overall_score real,
  aesthetic_score real,
  technical_score real,
  content_score real,
  emotion_score real,
  rarity_score real,
  uniqueness_score real,
  is_screenshot integer not null default 0,         -- 1 = 截图，aesthetic_score 强制为 0
  score_source text not null default 'placeholder', -- placeholder / vision / mlx_vlm / manual
  score_version integer not null default 0,
  analysis_run_id text,
  analysis_output_id text,
  model_id text,
  scored_at text,
  updated_at text not null
);

create index idx_photo_scores_overall on photo_scores(overall_score);
create index idx_photo_scores_aesthetic on photo_scores(aesthetic_score);
create index idx_photo_scores_run_id on photo_scores(analysis_run_id);

create table tag_definitions (
  id text primary key,
  tag_key text not null unique,
  display_name_zh text,
  display_name_en text,
  category text not null default 'general', -- scene / object / people / device / ai / user / general
  source text not null,                     -- system / vision / user / custom_model
  aliases_json text,
  created_by_user integer not null default 0,
  created_at text not null,
  updated_at text not null
);

create index idx_tag_definitions_category on tag_definitions(category);
create index idx_tag_definitions_source on tag_definitions(source);

create table photo_tags (
  id text primary key,
  photo_id text not null references photo_assets(id) on delete cascade,
  tag_id text not null references tag_definitions(id) on delete cascade,
  tag_source text not null,             -- system / vision / vlm / user
  confidence real,
  analysis_run_id text,
  user_confirmed integer not null default 0,
  created_at text not null,
  unique(photo_id, tag_id, tag_source)
);

create index idx_photo_tags_tag_id on photo_tags(tag_id);
create index idx_photo_tags_photo_id on photo_tags(photo_id);
create index idx_photo_tags_source on photo_tags(tag_source);

create table person_entities (
  id text primary key,
  person_key text not null,
  display_name text,
  source text not null,                  -- system_cluster / user / imported
  user_confirmed integer not null default 0,
  merge_target_id text,
  created_at text not null,
  updated_at text not null
);

create unique index idx_person_entities_key on person_entities(person_key);
create index idx_person_entities_display_name on person_entities(display_name);

create table person_faces (
  id text primary key,
  photo_id text not null references photo_assets(id) on delete cascade,
  person_id text references person_entities(id) on delete set null,
  face_cluster_id text,
  bounding_box_json text not null,
  quality_score real,
  featureprint_blob blob,
  confidence real,
  source text not null,                  -- vision / user / custom_model
  user_confirmed integer not null default 0,
  created_at text not null,
  updated_at text not null
);

create index idx_person_faces_photo_id on person_faces(photo_id);
create index idx_person_faces_person_id on person_faces(person_id);
create index idx_person_faces_cluster on person_faces(face_cluster_id);

create table photo_people (
  photo_id text not null references photo_assets(id) on delete cascade,
  person_id text not null references person_entities(id) on delete cascade,
  face_count integer not null default 1,
  confidence real,
  source text not null,                  -- vision / user / custom_model
  user_confirmed integer not null default 0,
  updated_at text not null,
  primary key(photo_id, person_id)
);

create index idx_photo_people_person_id on photo_people(person_id);
create index idx_photo_people_photo_id on photo_people(photo_id);

create table photo_locations (
  id text primary key,
  latitude real,
  longitude real,
  altitude real,
  country_code text,
  administrative_area text,
  locality text,
  sublocality text,
  place_name text,
  geocoded_at text
);

create index idx_photo_locations_place on photo_locations(country_code, administrative_area, locality);

create table albums (
  id text primary key,
  local_identifier text,
  title text not null,
  album_type text not null,             -- smart / user / folder / search
  subtype text,
  sort_order integer not null default 0,
  created_at text not null,
  updated_at text not null
);

create table album_assets (
  album_id text not null references albums(id) on delete cascade,
  photo_id text not null references photo_assets(id) on delete cascade,
  position integer,
  primary key(album_id, photo_id)
);

create index idx_album_assets_photo_id on album_assets(photo_id);

create table search_filters (
  id text primary key,
  name text,
  filter_kind text not null,            -- current / saved / sidebar / find_overlay
  payload_json text not null,
  locale text,
  created_at text not null,
  updated_at text not null
);

create table photo_search_documents (
  search_document_id integer primary key,
  photo_id text not null unique references photo_assets(id) on delete cascade,
  filename text not null default '',
  tags text not null default '',
  people text not null default '',
  place text not null default '',
  ai_text text not null default '',
  metadata text not null default '',
  updated_at text not null
);

create virtual table photo_search_fts using fts5(
  filename,
  tags,
  people,
  place,
  ai_text,
  metadata,
  content='photo_search_documents',
  content_rowid='search_document_id',
  tokenize='unicode61 remove_diacritics 2'
);

create trigger trg_photo_search_documents_ai after insert on photo_search_documents begin
  insert into photo_search_fts(rowid, filename, tags, people, place, ai_text, metadata)
  values (new.search_document_id, new.filename, new.tags, new.people, new.place, new.ai_text, new.metadata);
end;

create trigger trg_photo_search_documents_ad after delete on photo_search_documents begin
  insert into photo_search_fts(photo_search_fts, rowid, filename, tags, people, place, ai_text, metadata)
  values ('delete', old.search_document_id, old.filename, old.tags, old.people, old.place, old.ai_text, old.metadata);
end;

create trigger trg_photo_search_documents_au after update on photo_search_documents begin
  insert into photo_search_fts(photo_search_fts, rowid, filename, tags, people, place, ai_text, metadata)
  values ('delete', old.search_document_id, old.filename, old.tags, old.people, old.place, old.ai_text, old.metadata);
  insert into photo_search_fts(rowid, filename, tags, people, place, ai_text, metadata)
  values (new.search_document_id, new.filename, new.tags, new.people, new.place, new.ai_text, new.metadata);
end;

create table analysis_tasks (
  id text primary key,
  analysis_run_id text not null,
  photo_id text references photo_assets(id) on delete cascade,
  task_type text not null,              -- metadataImport / visionAesthetics / ocrDetect / embedding / vlmDescribe
  status text not null default 'pending',
  priority integer not null default 100,
  attempts integer not null default 0,
  max_attempts integer not null default 3,
  task_payload_json text,
  input_hash text,
  result_output_id text,
  error_code text,
  error_message text,
  lease_owner text,
  locked_at text,
  locked_until text,
  started_at text,
  completed_at text,
  created_at text not null,
  updated_at text not null,
  unique(analysis_run_id, photo_id, task_type)
);

create index idx_analysis_tasks_status_priority on analysis_tasks(status, priority, created_at);
create index idx_analysis_tasks_photo_id on analysis_tasks(photo_id);
create index idx_analysis_tasks_run_status on analysis_tasks(analysis_run_id, status);

create table ai_models (
  id text primary key,
  provider_kind text not null,          -- apple_builtin / user_imported
  model_role text not null,             -- aesthetics / face / tag / embedding / vlm
  display_name text not null,
  model_identifier text not null,
  version text,
  output_schema_version integer not null default 1,
  embedding_dimension integer,
  active integer not null default 0,
  config_json text,
  created_at text not null,
  updated_at text not null
);

create index idx_ai_models_role_active on ai_models(model_role, active);

create table analysis_runs (
  id text primary key,
  model_id text not null references ai_models(id),
  task_type text not null,               -- visionAesthetics / classifyTags / embedding / ...
  provider_kind text not null,
  model_identifier_snapshot text not null,
  model_version_snapshot text,
  output_schema_version integer not null default 1,
  config_hash text,
  config_snapshot_json text,
  run_type text not null,               -- initial / incremental / reanalyze / user_requested
  target_scope text not null,            -- all / album / filter / selected
  target_payload_json text,
  status text not null default 'pending',
  replaces_run_id text,
  total_tasks integer not null default 0,
  completed_tasks integer not null default 0,
  failed_tasks integer not null default 0,
  started_at text,
  completed_at text,
  created_at text not null,
  updated_at text not null
);

create index idx_analysis_runs_model_status on analysis_runs(model_id, status);
create index idx_analysis_runs_task_status on analysis_runs(task_type, status);

create table analysis_outputs (
  id text primary key,
  photo_id text not null references photo_assets(id) on delete cascade,
  analysis_run_id text not null references analysis_runs(id) on delete cascade,
  model_id text not null references ai_models(id),
  output_type text not null,             -- score.aesthetic / tag / face / embedding / description
  output_schema_version integer not null default 1,
  output_payload_json text,
  output_hash text,
  supersedes_output_id text,
  active integer not null default 0,
  activated_at text,
  superseded_at text,
  created_at text not null,
  unique(photo_id, analysis_run_id, output_type)
);

create index idx_analysis_outputs_photo_type on analysis_outputs(photo_id, output_type, active);
create index idx_analysis_outputs_run_id on analysis_outputs(analysis_run_id);
create index idx_analysis_outputs_model_type on analysis_outputs(model_id, output_type);

create table media_segments (
  id text primary key,
  photo_id text not null references photo_assets(id) on delete cascade,
  segment_type text not null,           -- video_summary / keyframe / clip
  start_time real,
  end_time real,
  representative_time real,
  thumbnail_cache_key text,
  description text,
  created_at text not null,
  updated_at text not null
);

create index idx_media_segments_photo_id on media_segments(photo_id);
create index idx_media_segments_type on media_segments(segment_type);

create table embedding_spaces (
  id text primary key,
  modality text not null,        -- text / image / video
  model_id text not null references ai_models(id),
  dimension integer not null,
  metric text not null default 'cosine',
  active integer not null default 1,
  config_hash text,
  created_at text not null,
  updated_at text not null
);

create index idx_embedding_spaces_model on embedding_spaces(model_id, modality, dimension, active);

create table photo_embeddings (
  photo_id text not null references photo_assets(id) on delete cascade,
  segment_id text references media_segments(id) on delete cascade,
  embedding_type text not null, -- text_1536 / image_1536 / video_1536 / vision_featureprint
  space_id text not null references embedding_spaces(id),
  model_id text not null references ai_models(id),
  dimension integer not null,
  content_hash text not null,
  vector_rowid integer,
  analysis_run_id text references analysis_runs(id),
  updated_at text not null,
  primary key (photo_id, segment_id, embedding_type, model_id)
);

create index idx_photo_embeddings_space on photo_embeddings(space_id, embedding_type);
create index idx_photo_embeddings_photo on photo_embeddings(photo_id);

-- sqlite-vec virtual tables, enabled in P2. Different dimensions and modalities must not share a table.
create virtual table vec_text_1536 using vec0(
  embedding float[1536]
);

create virtual table vec_image_1536 using vec0(
  embedding float[1536]
);

create virtual table vec_video_1536 using vec0(
  embedding float[1536]
);

create table thumbnail_cache_index (
  photo_id text not null references photo_assets(id) on delete cascade,
  size_key text not null,               -- grid_96 / grid_160 / viewer_1024
  cache_key text not null,
  width integer not null,
  height integer not null,
  cost integer not null default 0,
  updated_at text not null,
  primary key(photo_id, size_key)
);

create table timeline_events (
  id text primary key,
  title_key text,
  title_fallback text,
  start_date text not null,
  end_date text not null,
  location_id text,
  cover_photo_id text references photo_assets(id),
  asset_count integer not null default 0,
  event_type text not null default 'auto',
  created_at text not null,
  updated_at text not null
);

create index idx_timeline_events_date on timeline_events(start_date, end_date);

create table reports (
  id text primary key,
  title text not null,
  report_type text not null,            -- initial / weekly / manual
  content_markdown text,
  payload_json text,
  photo_count integer not null default 0,
  status text not null default 'draft',
  created_at text not null,
  updated_at text not null
);
```

### 4.4 FTS5 维护策略

P1 关键词搜索采用 `photo_search_documents` 作为物化搜索文档表，`photo_search_fts` 作为 external-content FTS5 虚表。Repository 不直接拼接散落字段查询 FTS，而是先把每张照片可检索文本汇总为一行搜索文档。

字段来源：

| FTS 字段 | 来源 | P0/P1 行为 |
| --- | --- | --- |
| `filename` | `photo_assets.filename`、原始文件名 | P1 可用 |
| `tags` | `tag_definitions` + `photo_tags` | P0/P1 可能为空，P4+ AI 标签落库后自动可搜 |
| `people` | `person_entities` + `photo_people` | P0/P1 可能为空，P4+ 人物能力落库后自动可搜 |
| `place` | `photo_locations` | 有 EXIF/GPS 时可用 |
| `ai_text` | `analysis_outputs` 中描述、OCR、回忆等文本 | P0/P1 为空，P4+ 后启用 |
| `metadata` | 设备、媒体类型、年份、来源等稳定 key | P1 可用 |

维护规则：

- `photo_search_documents` 是唯一写入入口；FTS5 虚表由 insert/update/delete trigger 同步。
- 资产导入、文件名变化、地点反查、标签/人物关系变化、未来 AI 文本变化后，统一调用 `SearchIndexRepository.upsertDocument(photoID:)` 重建该照片搜索文档。
- P1 查询流程为：先用 FTS5 匹配关键词得到候选 `photo_id`，再与 `SearchFilterState` 生成的结构化 SQL 条件做 `AND` 过滤。
- P0/P1 已实现人物、标签、地点等筛选查询；若对应维度暂无数据，查询结果为空，这是预期行为，不阻塞后续 AI 能力接入。
- 若 FTS 索引损坏或 schema 迁移，使用 `delete from photo_search_fts; insert into photo_search_fts(photo_search_fts) values('rebuild');` 基于 `photo_search_documents` 全量重建。
- 不把 FTS5 当作主筛选引擎；评分、媒体类型、时间、收藏、App 内废片篓、iCloud 状态、设备来源等高频条件必须走结构化列和索引。

### 4.5 P1 美学评分重跑与覆盖策略

P1 只实现 `visionAesthetics`。每次全量、增量或用户手动重跑都必须创建新的 `analysis_runs`，并为目标照片生成绑定该 run 的 `analysis_tasks`。

重跑规则：

- `analysis_tasks.unique(analysis_run_id, photo_id, task_type)` 允许同一照片跨批次重跑，也能防止同一批次重复入队。
- 应用重启或任务恢复时，跳过 `completed` 任务；只领取 `pending`、锁过期的 `running`、可重试的 `failed`。
- 新评分先写入 `analysis_outputs(active=0, output_type='score.aesthetic')`。
- 激活新评分时在同一事务中完成三步：旧 active 输出置为 inactive 并写入 `superseded_at`；新输出置为 active 并写入 `activated_at`；`photo_scores` 更新为新分数，并写入 `analysis_run_id`、`analysis_output_id`、`model_id`、`scored_at`。
- `photo_scores` 是读取当前分数的快速表；完整历史与批次追溯以 `analysis_outputs` 和 `analysis_runs` 为准。
- 截图资产仍创建任务和输出，但 `aesthetic_score` 固定为 0，`output_payload_json` 记录 `forced_zero_reason='screenshot'`。

### 4.6 中文表设计文档

| 表名 | 中文名 | 核心职责 | 数据来源 | 搜索/性能设计 |
| --- | --- | --- | --- | --- |
| `schema_migrations` | 数据库迁移记录表 | 记录已执行 migration，保证 schema 可升级 | App 内部 | 主键 `version` |
| `app_settings` | 应用设置表 | 保存语言、主题、网格、角标、并发、模型选择 | 用户设置/App 默认值 | 主键 `key`，启动时一次性加载 |
| `photo_assets` | 照片资产表 | 保存照片/视频基础元数据，是所有业务表的根表；`in_trash` 为 App 内废片篓标记，iCloud 字段仅设计和落库 | Photos Framework/文件导入 | 按媒体类型、时间、收藏、废片篓、设备、分析状态、iCloud 状态建索引 |
| `photo_scores` | 照片评分表 | P1 保存 Apple Vision 美学分和当前分数所属批次/模型/输出；其他维度 P4+ 待确认 | Apple Vision/后续用户模型/手动调整 | 按 `overall_score`、`aesthetic_score`、`analysis_run_id` 建索引，支撑评分筛选和结果追溯 |
| `tag_definitions` | 标签字典表 | 保存系统标签、AI 标签、用户自定义标签的稳定定义 | 系统预置/AI/用户 | `tag_key` 唯一，按分类和来源索引 |
| `photo_tags` | 照片标签关联表 | 建立照片与标签的多对多关系 | AI 自动添加/用户手动添加 | `photo_id`、`tag_id`、`tag_source` 索引，支撑大量照片标签筛选 |
| `person_entities` | 人物实体表 | 保存人物聚类、用户命名、合并关系 | Vision 聚类/用户创建 | `person_key` 唯一，`display_name` 索引支撑人物搜索 |
| `person_faces` | 人脸样本表 | 保存每张照片中的人脸框、质量、聚类、确认状态 | Vision/用户确认/用户模型 | 按照片、人物、聚类索引，支撑人物归纳与纠错 |
| `photo_people` | 照片人物关联表 | 建立照片与人物的多对多关系 | 人脸聚类/用户手动添加 | `(photo_id, person_id)` 主键，按人物和照片双向索引 |
| `photo_locations` | 地点表 | 保存经纬度和反向地理编码结果 | PHAsset location/CLGeocoder | 按国家、省市、地点索引，支撑地点筛选和时间线 |
| `albums` | 相册表 | 保存系统相册、智能相册、用户导入集合、保存搜索 | Photos Framework/用户 | 主键 `id`，后续可按类型索引 |
| `album_assets` | 相册照片关联表 | 建立相册与照片多对多关系 | Photos Framework/用户 | `(album_id, photo_id)` 主键，按 `photo_id` 反查 |
| `search_filters` | 搜索筛选状态表 | 保存当前查找、侧边栏状态、常用查找 | 用户操作 | `payload_json` 保存统一 `SearchFilterState` |
| `photo_search_documents` / `photo_search_fts` | 照片全文检索表 | 保存文件名、标签、人物、地点、AI 文本的全文索引 | Repository 同步生成 | materialized document + external-content FTS5，支撑关键词搜索，不替代结构化筛选 |
| `analysis_tasks` | 分析任务表 | P1 保存美学评分待分析/运行中/失败/完成任务 | AnalysisScheduler | `(status, priority, created_at)` 和 `(analysis_run_id, status)` 支撑队列调度和断点恢复 |
| `ai_models` | AI 模型配置表 | P1 登记 Apple Vision 内置美学评分模型；用户导入模型 P4+ 待确认 | 系统预置/用户导入 | `(model_role, active)` 索引支撑快速切换模型 |
| `analysis_runs` | 分析批次表 | 记录每次美学评分或重跑批次，保存模型和配置快照 | AnalysisUseCase | 按模型、任务类型和状态索引，支撑暂停/恢复/重分析 |
| `analysis_outputs` | AI 输出版本表 | 保存美学评分输出版本、覆盖、回滚关系 | AppleVisionProvider/后续 Provider | `(photo_id, output_type, active)` 索引支撑读取当前有效结果 |
| `media_segments` | 媒体片段表 | 保存视频摘要、关键帧、片段的检索单位 | P2 视频分析/关键帧抽取 | 按照片和片段类型索引，支撑视频语义搜索 |
| `embedding_spaces` | 向量空间表 | 保存向量模型、模态、维度、距离算法和启用状态 | P2 AIModelRegistry | 按 `id` 定位，避免 768/1536 或不同模型混查 |
| `photo_embeddings` | 照片向量元数据表 | 保存照片/视频片段与向量表 rowid 的映射 | P2 EmbeddingProvider | 主键包含照片、片段、类型、模型，支持多模型并存 |
| `vec_text_1536` | 文本向量虚拟表 | 存储 1536 维文本语义向量 | P2 sqlite-vec | 用于自然语言找照片 |
| `vec_image_1536` | 图像向量虚拟表 | 存储 1536 维图像语义向量 | P2 sqlite-vec | 用于图片语义搜索和以图搜图 |
| `vec_video_1536` | 视频向量虚拟表 | 存储 1536 维视频摘要/关键帧向量 | P2 sqlite-vec | 用于视频语义搜索 |
| `thumbnail_cache_index` | 缩略图缓存索引表 | 记录缩略图缓存 key 和尺寸，不保存图片本体 | PHCachingImageManager/本地缓存 | `(photo_id, size_key)` 主键 |
| `timeline_events` | 时间线事件表 | 保存自动聚合或用户确认的时间线事件 | 时间/地点/AI 聚类 | 按起止时间索引 |
| `reports` | 报告表 | 保存报告内容、统计数据和生成状态 | 报告生成器/AI | 按报告类型和状态后续补索引 |

标签与人物的规模化搜索策略：

- 标签和人物都采用“字典/实体表 + 关联表”，避免在照片表中存数组或逗号字符串。
- 系统自动添加和用户手动添加通过 `source`、`tag_source`、`user_confirmed` 区分，不互相覆盖。
- 用户确认的数据优先级高于 AI 自动生成的数据；AI 重分析只能 supersede 同一模型输出，不能覆盖用户确认项。
- 大量照片筛选时，先用 `photo_tags` / `photo_people` 找候选 `photo_id`，再回表 join `photo_assets`、`photo_scores`、`photo_locations`。
- 多条件筛选统一由 `SearchFilterState` 生成 SQL，避免侧边栏、查找浮层、保存搜索各自实现不同查询逻辑。

### 4.5 P0 默认设置

```text
appearance.theme = system          # system / light / dark
appearance.language = system       # system / zh-Hans / en
photos.gridLevel = 4               # 2/4/6/8/12/16/32 中的索引或列数
photos.badgeMetric = aesthetic     # aesthetic / overall / hidden
photos.scoreBounds = 80,60,40
photos.sortMode = creation_desc
sidebar.visible = true
find.lastFilter = null
analysis.maxConcurrency = 2
analysis.visionEnabled = false     # P0 默认不主动分析，P1 开启
ui.bottomBarVisible = true
```

---

## 5. P0-P5 全功能架构设计

### 5.1 分层架构

```text
Presentation
├── AppShell：窗口、导航、快捷键、主题、语言
├── PhotosPage：照片主页、网格、工具栏、多选
├── Sidebar：快捷筛选面板
├── FindOverlay：搜索/筛选统一浮层
├── TimelinePage：时间线与事件浏览
├── ReportsPage：报告列表与阅读
└── SettingsPage：语言、主题、模型、评分、性能设置

Application
├── PhotoLibraryUseCase：授权、导入、同步
├── SearchUseCase：查找、筛选、排序、保存常用条件
├── AnalysisUseCase：P1 美学评分任务创建、调度、进度、暂停/恢复
├── ViewerUseCase：查看、收藏、废片篓、元数据
├── TimelineUseCase：事件聚合、年份索引、搜索
└── SettingsUseCase：设置读取、更新、广播

Domain
├── PhotoAsset / PhotoScore / PhotoTag / SearchFilterState
├── ThemeMode / AppLanguage / GridLevel / SortMode
├── AnalysisTask / AnalysisResult / Report
└── VectorSearchHit / TimelineEvent

Infrastructure
├── Photos Framework Adapter
├── GRDB SQLite Repository
├── Vision Analyzer（P1 仅美学评分）
├── VectorIndex Adapter（P2）
├── MLX-VLM Provider（P4+ 待确认）
├── String Catalog Localization
└── Thumbnail Cache
```

### 5.2 P0-P5 能力矩阵

| 能力 | P0 | P1 | P2 | P4+ |
| --- | --- | --- | --- | --- |
| App 壳层 | SwiftUI 主窗口、导航、基础路由 | 菜单栏分析进度 | 多窗口/深链、打包前检查 | 按需扩展 |
| 语言 | 系统/中文/英文切换 | 完整文案覆盖 | 翻译质量回归 | 报告/AI 文案多语言 |
| 主题 | 跟随系统/浅色/深色 | 主题细节补齐 | 高对比/无障碍适配 | 按需扩展 |
| 照片主页 | `NSCollectionView` 万级网格 + 1:1 复刻 Demo 工具栏 | 真实美学评分角标 | 10 万图库优化 | 相似组/AI 入口 |
| 侧边栏筛选 | 1:1 复刻 Demo 交互和 SQL 基础筛选 | SQL/FTS5 全量生效 | 筛选性能压测 + 向量召回融合 | 自定义模型语义增强 |
| 查找浮层 | 1:1 复刻 Demo UI 和状态 | FTS5/规则解析 | embedding 语义搜索 | 自定义模型语义增强 |
| 照片查看器 | 全屏查看、详情壳层 | 真实元数据/美学评分 | 视频/Live 基础体验深化 + 相似照片入口 | AI 描述/回忆 |
| 时间线 | 导航菜单入口（占位） | 保持入口 | 完整时间线实现（待 Demo 设计稳定后） | 事件自动聚类/地图优化 |
| 报告页 | 页面骨架 | 基础统计骨架 | 真实非 AI 统计报告 | AI 生成报告 |
| 设置页 | 语言、主题、网格、角标 | Vision/并发 | 诊断/性能工具 | MLX/自定义模型管理 |
| 数据库 | P0 基础表结构 + 中文表设计 | FTS5/美学评分/分析批次 | sqlite-vec 1536 维 embedding + 迁移/修复工具 | 自定义模型结果表扩展 |
| AI 分析 | 不开发 AI | Apple Vision 美学评分 | embedding 生成与向量搜索 | 用户模型、OCR、人脸、标签、日记、独特性、VLM 等待确认 |

### 5.3 P0 UI 优先原则

P0 的优先级调整为：**先完成 Mac 原生 UI 框架和 Demo 1:1 交互复刻，不做 AI 相关开发。**

说明：当前 Demo 从 v0.0.11 起已将独立“搜索页/筛选页”合并为全局“查找”浮层。Mac 版 P0 不恢复旧的独立搜索 Tab，而是按 Demo 最新产品定义实现：**查找浮层 = 搜索页面 + 筛选页面的统一原生形态**。

P0 必须完成的 UI 页面：

| 页面 | P0 要求 |
| --- | --- |
| 照片页 | `NSCollectionView` 顶栏、工具栏、7 级网格、角标显示/隐藏、排序、多选、空状态 |
| 侧边栏 | 类型/评分/时间/状态/设备/人物/标签区块，展开/收起、清空、实时联动 |
| 查找浮层 | `⌘K` 唤起，Spotlight 风格，筛选分区，实时更新照片墙 |
| 设置页 | 语言切换、主题三态、网格/角标/分数区间、性能基础设置 |
| 时间线页 | **Mac V1 仅创建导航菜单入口**，不复刻 Demo 完整时间线 UI；Demo 时间线设计尚未稳定，完整功能待后续版本实现 |
| 报告页 | 1:1 复刻 Demo UI 与报告列表/阅读/空状态，数据可先使用占位 provider |
| 照片查看器 | 全屏查看壳层、详情面板、快捷键、真实缩略图/预览图 |

### 5.4 Demo 1:1 复刻映射

| Demo 功能 | Mac 原生实现 |
| --- | --- |
| 顶栏 4 Tab + 搜索胶囊 | `AppShellView` + `TopBarView` + `FindOverlayCoordinator` |
| 底部功能栏 | `BottomNavigationView`，设置中可隐藏 |
| 侧边栏 overlay | `SidebarView` 叠加在 `PhotosPage` 上，不挤压主网格 |
| 滚动隐藏侧边栏 | `ScrollPhaseObserver` 或 AppKit scroll event bridge |
| 网格 7 级缩放 | `NSCollectionViewCompositionalLayout` + `PhotoGridLevel` |
| 角标四档颜色 | `ScoreBadgeView` + `ScoreTierSettings` |
| 分段控件再点隐藏角标 | `BadgeMetricState` 支持 `hidden` |
| 排序联动评分维度 | `SortMode` 与 `badgeMetric` 组合生成查询 |
| 查找浮层实时更新照片墙 | `SearchFilterState` 单一状态源 |
| 查找关闭后保留条件 | `search_filters` 保存 current filter |
| 人物/标签搜索 | 本地状态过滤 + SQL 查询 |
| 主题三态 | `ThemeManager` + `.preferredColorScheme` |
| 中英文切换 | `LocalizationManager` + `.environment(\.locale, ...)` |

### 5.5 国际化设计

**目标：Mac 版同时支持中文和英文，用户可在设置中切换。**

技术方案：

- 使用 Xcode String Catalog：`Localizable.xcstrings`。
- 支持语言：`zh-Hans`、`en`。
- 设置项：`system`、`zh-Hans`、`en`。
- SwiftUI 通过 `Locale` environment 切换界面语言。
- 数据库只保存稳定 key，例如 `tag.landscape`、`device.drone`、`sort.creation_desc`，不保存“风景/Drone”这类展示文案。
- 用户生成内容、文件名、地点名保留原文，不强制翻译。

核心模型：

```swift
enum AppLanguage: String, Codable, CaseIterable {
    case system
    case zhHans = "zh-Hans"
    case en = "en"
}

@MainActor
final class LocalizationManager: ObservableObject {
    @Published var language: AppLanguage

    var locale: Locale {
        switch language {
        case .system: Locale.autoupdatingCurrent
        case .zhHans: Locale(identifier: "zh-Hans")
        case .en: Locale(identifier: "en")
        }
    }
}
```

验收标准：

- 设置页切换语言后，顶栏、侧边栏、查找浮层、照片页、时间线、报告页、设置页立即更新。
- 所有枚举类文案从 key 映射，不在业务层硬编码中文。
- 日期、数字、分数格式跟随当前 locale。

### 5.6 主题设计

**目标：支持亮色模式、暗色模式、跟随系统。**

技术方案：

- 设置项：`system`、`light`、`dark`。
- SwiftUI 根视图使用 `.preferredColorScheme(theme.colorScheme)`。
- 设计令牌集中在 `DesignSystem`，不要在页面里散落颜色常量。
- 液态玻璃效果基于 macOS 原生 material，避免用大面积自绘模糊造成卡顿。

**液态玻璃令牌（`DesignSystem.Glass`，2026-06-08 落地）：**

- `hairline` / `hairlineWidth`：玻璃表面统一发丝描边，所有浮层、侧栏、搜索条共用。
- `activeTint`：选中态统一用系统强调色 `Color.accentColor`，贴近 macOS source list / 工具栏选择语义，避免每个 active 态都像独立品牌按钮。
- `scrimLight` / `scrimDark`：浮层遮罩，刻意偏轻（0.12 / 0.22），不把玻璃压暗。
- `viewerBackdrop`：查看器整屏底色（黑 0.9），深而不死黑，给悬浮 chrome 留层次。
- `brandGradient`：**唯一保留**的品牌渐变，仅用于少数信号性强调态（当前为照片页角标指标段控），不再铺满所有选中态。
- 圆角令牌 `Radius.chip / card / overlay` 取代页面里手写的魔法圆角。

**macOS 27 半透明度滑块前瞻适配（2026-06-09，material-first）：**

WWDC 2026 的 macOS 27「Golden Gate」新增了 Liquid Glass 半透明度 / 着色滑块。为确保新系统发布后无需改动即可适配，遵循以下原则：

- **一切浮层 chrome 用系统 `Material`**（`.regularMaterial` / `.ultraThinMaterial` / `.thinMaterial`）。系统 Material 会自动跟随半透明度滑块、浅/深色与系统强调色，无需我们做任何事。
- **不放固定颜色的自绘 chrome**：已移除固定白色发丝描边（改 `Color.primary.opacity`，自适应外观）与唯一的品牌渐变（角标段控改系统强调色）。选中态一律 `Color.accentColor`。
- **保留的固定色仅限非 chrome**：阴影（与玻璃浓淡无关）、查看器深底（内容呈现）、评分色阶（数据可视化）。
- **未来采用 `.glassEffect()`（macOS 26+）是本地化改动**：因为浮层背景已统一收口为 `DesignSystem.Glass` + `.background(.regularMaterial, in:)`，届时只需在这些集中点替换，不触碰业务代码。

核心模型：

```swift
enum ThemeMode: String, Codable, CaseIterable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
```

验收标准：

- 三态切换即时生效。
- 跟随系统时，系统外观变化后 UI 自动刷新。
- 评分角标、浮层、侧边栏、按钮、空状态在亮/暗模式下均满足可读性。

---

## 6. 模块设计

### 6.1 PhotoLibraryService

职责：

- 请求照片权限。
- 枚举系统照片库资产。
- 监听照片库变化。
- 提供缩略图、预览图、原图数据请求。
- 封装收藏、删除、恢复等系统变更。

关键输出：

- `PhotoAssetSnapshot`：轻量资产快照，用于同步数据库。
- `PhotoImageRequest`：缩略图/预览图/分析图请求。

### 6.1.1 首次使用性能优化

大规模照片图库（万级甚至五万级以上）的首次加载是体验关键。设计原则：**快速响应优先，后台完整同步**。

**分阶段导入策略：**

| 阶段 | 内容 | 目标耗时 |
|------|------|---------|
| 第一阶段 | 拉取最近 3,000 张照片的元数据，写入数据库 | < 5 秒（可见照片墙） |
| 后台继续 | 遍历剩余照片，补全完整图库元数据 | 1~5 分钟（视图库规模） |

**避免阻塞的操作：**

- `PHAssetResource.assetResources(for:)` 逐张查询文件名会触发大量 I/O，54 K 图库下耗时可达 30 分钟以上。**文件名在首次导入时跳过**，改为在用户打开具体照片的查看器时再通过 `PHAsset.fetchAssets(withIdentifier:)` 惰性获取。
- 照片库授权状态通过 `requestAuthorization(for: .readWrite)` 以 async 方式请求，不阻塞主线程。

**GRDB 批量写入：**


`PhotoAssetRepository.upsert(_:)` 在单次数据库事务内完成 chunk（默认 500 条）的 `INSERT ON CONFLICT DO UPDATE`，而非逐条提交事务。相比逐条写入，批量事务可减少 10~50 倍的写入开销。

**代码示例：**

```swift
// PhotoLibraryImportUseCase.swift
@discardableResult
func importAll(
    initialLimit: Int? = 3000,  // 第一阶段：优先显示最近 3,000 张
    progressHandler: (@MainActor @Sendable (Progress) -> Void)? = nil
) async throws -> Summary {
    // 第一阶段：拉取有限数量资产（快）
    let assets = await MainActor.run { adapter.fetchAssets(limit: initialLimit) }

    // 分 chunk 批量写入 DB（每次 500 条，单事务）
    while index < total {
        let end = min(index + pageSize, total)
        let chunk = Array(assets[index..<end])
        try repository.upsert(chunk)  // 单次事务
        index = end
        await progressHandler(snapshot)  // 实时更新 UI 进度
    }
}
```

**体验保障：**
- 用户在第一阶段结束后（< 5 秒）即可在照片墙看到前 3,000 张照片，并可立即发起评分任务。
- 后台继续遍历期间，底部状态栏实时显示 "Importing X of Y"。
- 用户可随时切换到其他 Tab，后台导入不受影响。


职责：

- 管理 SQLite 数据库。
- 提供照片列表、筛选、搜索、排序查询。
- 保存评分、标签、任务状态、报告、设置。
- 处理数据库迁移。

建议：

- 所有 UI 列表只读取轻量 DTO，不直接暴露数据库行对象。
- 写入走事务，分析任务批量提交，减少 UI 卡顿。
- **批量写入参数**：chunk 大小建议 500 条/事务，与 PhotoLibraryImportUseCase 的 pageSize 对齐，避免单次事务过大导致 DB 锁竞争。
- **元数据轻量原则**：首次导入只写 `id / localIdentifier / filename(null) / mediaType / creationDate / width / height / isFavorite / isHidden`，不拉原图文件路径、不写 `PHAssetResource`，这些信息在用户打开查看器时按需获取。

### 6.3 AnalysisScheduler

职责：

- 管理后台分析队列。
- 控制并发数。
- 支持暂停、继续、重试、失败记录。
- 避免同一照片被多个任务同时分析。
- P1 调度 `visionAesthetics`；P2 调度 `textEmbedding1536`、`imageEmbedding1536`、`videoEmbedding1536`；P4+ 再扩展依赖自定义模型的任务类型、并发策略和外部模型调用范围。

任务类型：

| 任务 | 阶段 | 说明 |
| --- | --- | --- |
| `metadataImport` | **P0** | 首次同步元数据，含截图标识检测（`PHAsset.mediaSubtype`） |
| `thumbnailWarmup` | **P0** | 预热缩略图 |
| `visionAesthetics` | **P1** | Apple Vision 美学评分；若检测到截图则强制 aesthetic_score = 0 |
| `textEmbedding1536` | **P2** | 基于确定性文本生成 1536 维文本向量 |
| `imageEmbedding1536` | **P2** | 基于本地图像 embedding Provider 生成 1536 维图像向量 |
| `videoEmbedding1536` | **P2** | 基于视频摘要/关键帧生成 1536 维视频向量 |
| `vlmDescription` | P4+ 待确认 | 照片内容描述（≤300字）；独立 VLM 任务，详见 3.8 |
| `vlmDiary` | P4+ 待确认 | 照片回忆（≤200字）；独立 VLM 任务，与 `vlmDescription` 分开调度，详见 3.8 |
| `classifyTags` | P4+ 待确认 | 图像分类/自动标签 |
| `detectFaces` | P4+ 待确认 | 人脸检测与人物归纳 |
| `ocrDetect` | P4+ 待确认 | OCR 识别 |
| `featurePrint` | P4+ 待确认 | 视觉相似特征，用于重复检测 |
| `embedding` | **P2** | 向量生成和 sqlite-vec 索引维护 |

策略参数：

| 策略 | Vision 并发 | HEIC→JPEG 并发 | 外部/VLM 并发 | 默认范围 |
| --- | --- | --- | --- | --- |
| `fast` | 4-8 | 0 | 0 | P1 全图库美学评分 |
| `balanced` | 2-6 | 1-2 | 0 | P1 美学评分 + P2 embedding 索引 |
| `complete` | P4+ 待定义 | P4+ 待定义 | P4+ 待定义 | 后续确认 |

调度原则：

- 外部自定义大模型任务放在 P4+，默认不全量跑，必须由策略或用户范围限定。
- P1 Vision 美学评分优先直接使用 Photos/Vision 可接受的图像输入；P2 embedding Provider 如需 JPEG/关键帧输入，复用内存管道，不落长期临时文件。
- 任务失败要记录 `error_message` 和 `attempts`，支持按 `analysis_run_id` 重试。

### 6.4 FilterEngine

职责：

- 将侧边栏和查找浮层条件合并为统一查询状态。
- 生成 SQL 查询。
- 计算筛选摘要，用于 UI 顶部横幅。
- 管理“侧边栏快捷筛选”和“全局查找”的优先级关系。

建议规则：

- 快捷筛选和查找浮层共享同一份 `SearchFilterState`。
- UI 可以展示不同入口，但底层状态只有一套。
- 自然语言 query 与属性筛选以 AND 叠加。

### 6.5 PhotoGrid

职责：

- 展示照片网格。
- 支持 2/4/6/8/12/16/32 七级缩放。
- 展示评分角标。
- 支持排序、多选、键盘操作、右键菜单。

性能策略：

- P0 直接使用 `NSCollectionView`，不使用 `LazyVGrid`。
- 使用 `NSCollectionViewDiffableDataSource` 做差量刷新。
- 使用 `NSCollectionViewCompositionalLayout` 或自定义 layout 支撑 7 级缩放。
- 只加载可见区域缩略图，并预热前后缓冲区。
- cell 复用时取消旧的 `PHImageRequestID`，避免快速滚动堆积过期请求。
- 滚动时降低非必要动画，停止滚动后恢复角标和细节刷新。
- 16/32 列隐藏角标，优先保证密度与流畅度。
- P0 验收必须覆盖 1 万资产；P3 覆盖 10 万资产。

**滚动预热与触底加载优化（2026-06-08）：**

- 预热节流：滚动通知不再每帧重算预热。`scrollViewBoundsDidChange` 改为合并同一 runloop 内的多次通知（`pendingPreheat` 标志），且滚动距离不足半个 item 高度时跳过重算。
- 去掉每帧强制布局：预热不再每次 `layoutSubtreeIfNeeded()`，flow 布局属性按需可得，省掉高频强制布局开销。
- 触底加载用更小增量页：`loadMorePhotosIfNeeded` 的增量页从首屏的 3000 降为 `loadMorePageSize = 800`，单次 diffable 快照 apply 体量更小，滚动到底更平滑（首屏页大小不变，保证首屏快速铺满）。

### 6.6 FindOverlay

职责：

- `⌘K` 打开/关闭。
- 输入自然语言查询。
- 展示媒体类型、评分、时间、状态、设备、地点、人物、标签筛选。
- 实时更新照片墙。

实现重点：

- 浮层是控制面板，照片页是实时结果画布。
- 关闭浮层后筛选条件仍保留。
- 顶部横幅显示当前查找摘要，并提供清除入口。

液态玻璃细化（2026-06-08）：背后遮罩用 `Glass.scrimLight/Dark`，权重刻意调轻；计数条与底部摘要条的黑色半透明背景改为系统 `.quaternary` 材质；浮层圆角/描边走 `Radius.overlay` + `Glass.hairline`；所有 active chip 统一为 `Glass.activeTint`（系统强调色）。

搜索入口（2026-06-08 P1）：顶部栏不再放搜索胶囊，主搜索入口改为**底部液态玻璃导航坞右侧的独立圆形 🔍 按钮**（`LiquidGlassDock`），与 `⌘K` 等价。导航坞同时承载四个分区的快速跳转，顶部分区标签保留。

### 6.7 PhotoViewer

职责：

- 全屏查看照片/视频。
- `i` 切换详情面板。
- 左右键切换上一张/下一张。
- 展示元数据、评分、维度、标签、描述、建议。
- 提供收藏、移入废片篓、恢复等操作。

液态玻璃细化（2026-06-08）：整屏底色用 `Glass.viewerBackdrop`（深而不死黑）；顶部关闭/翻页按钮收进悬浮玻璃胶囊，底部操作条改为内缩的悬浮圆角玻璃条（`.ultraThinMaterial` + `Glass.hairline`）；`VideoPlayer`、`PHLivePhotoView` 与媒体请求逻辑保持不动。

快捷键（2026-06-08 P1，对齐 Apple 照片）：上一/下一张 `←`/`→`，播放暂停 `空格`，收藏 `.`，查看信息 `⌘I`，删除到系统照片 `⌘⌫`，废片篓（App 软删除，自定义）`T`，关闭 `Esc`；网格缩放 `⌘+`/`⌘-`（菜单栏 View 命令），`⌘K` 打开 Find。

手势（2026-06-08 P1，作用于静态图）：捏合缩放 1×–6×、放大后拖拽平移、双击在适配与 2.5× 间切换、未放大时左右滑动切换上一/下一张；切换照片自动复位缩放，视频与播放中的 Live Photo 用方向键/按钮切换。网格捏合改变缩放级别（既有）。

---

## 7. 开发进度记录

状态说明：

- `✅ Demo 完成`：HTML Demo 中交互已完成，可照此实现。
- `🟡 方案确定`：技术路线已确定，尚未进入原生编码。
- `⬜ 待实现`：尚未开始 Mac 原生实现。
- `🧪 待验证`：需要真实图库或性能测试验证。

| 模块 | 当前状态 | 下一步 |
| --- | --- | --- |
| 产品规格 `SPEC.md` | ✅ Demo 完成 | 持续随功能更新 |
| 技术规格 `TECH.md` | 🟡 方案确定 | 后续同步本方案的最终选型 |
| 照片主页 Demo | ✅ Demo 完成 | `NSCollectionView` 复刻网格与工具栏 |
| 侧边栏快捷筛选 Demo | ✅ Demo 完成 | 抽象 `SearchFilterState` |
| 全局查找浮层 Demo | ✅ Demo 完成 | 实现 `FindOverlay` 原生组件 |
| 照片查看器 Demo | ✅ Demo 完成 | 实现全屏查看与详情面板 |
| 时间线 Demo | ✅ Demo 完成（设计调整中） | Mac V1 仅菜单入口，Demo 设计稳定后再实现完整原生时间线 |
| 报告页 Demo | ✅ Demo 完成 | P2 接真实非 AI 统计报告，AI 报告 P4+ 待确认 |
| 设置页 Demo | ✅ Demo 完成 | P0 实现基础设置 |
| Photos Framework 接入 | 🟡 方案确定 | 请求权限、枚举 PHAsset |
| SQLite/GRDB 存储 | 🟡 方案确定 | 建库、迁移、Repository |
| Vision 基础评分 | 🟡 方案确定 | 封装 `VisionAnalyzer` |
| 外部模型媒体预处理 | 🟡 方案确定 | P2 为 embedding Provider 建立内存媒体输入；P4+ 复用到自定义模型 |
| MLX-VLM 深度分析 | ⬜ 待实现 | P4+ 待确认 |
| 向量检索 | ⬜ 待实现 | P2 接 sqlite-vec + 1536 维 text/image/video 空间 |
| Core Spotlight | ⬜ 待实现 | P2 同步高价值索引 |
| 大图库性能 | 🧪 待验证 | 1 万 / 10 万资产压测 |
| 中英文语言切换 | 🟡 方案确定 | P0 接入 String Catalog 和设置项 |
| 主题三态 | 🟡 方案确定 | P0 接入根视图 `preferredColorScheme` |
| P0 数据库表结构 | 🟡 方案确定 | 按本文 SQL 建 migration |

---

## 8. 实施路线

### P0：应用框架 + Demo 1:1 原生复刻

目标：先完成 Mac 原生应用框架、基础架构和 Demo 核心交互复刻，让照片主页、查找、筛选、设置等页面达到可开发、可演示、可持续接入真实数据的标准。**P0 不做 AI 相关开发。**

P0 拆分为 4 个短里程碑，避免一次性交付过大：

| 子阶段 | 目标 | 交付物 |
| --- | --- | --- |
| P0-A | 原生 App 壳层 | `AppShellView`、顶部栏、底部栏、页面路由、快捷键、主题/语言管理器 |
| P0-B | Demo UI 1:1 复刻 | `NSCollectionView` 照片页、侧边栏、查找浮层、设置页、报告页、照片查看器；时间线仅导航菜单入口占位 |
| P0-C | P0 数据框架 | GRDB、migration、P0 基础表结构、中文表设计、设置持久化、筛选状态持久化 |
| P0-D | 真实照片接入 | Photos 权限、`PHAsset` 枚举、缩略图加载、基础 SQL 查询、1 万资产流畅性验证 |

任务：

- 新建 `MantaPhotosMac` Xcode 工程。
- 建立 SwiftUI 主窗口、顶部栏、底部栏、页面路由、快捷键系统。
- 完成照片页、报告页、设置页的原生页面框架；时间线页仅创建导航入口，不实现完整 UI。
- 完成侧边栏 overlay、滚动隐藏、展开/收起、清空筛选等交互。
- 完成全局查找浮层：`⌘K` 唤起、筛选分区、实时更新照片墙、关闭后保留条件。
- 完成设置页：语言切换、主题三态、网格级别、角标维度、分数区间、底部栏显隐。
- 建立 String Catalog：`zh-Hans` / `en`。
- 建立 ThemeManager 和 LocalizationManager。
- 建立 GRDB 数据库，完成 P0 基础表结构 migration。
- 接入 Photos Framework 权限和资产枚举。
- 实现 `NSCollectionView` 缩略图加载、7 级网格、评分角标占位、排序、多选。
- P0 仅实现全局 `⌘K` 唤起查找；`T`、`F`、`Space`、`Esc`、`i`、`←`、`→`、`⌘D` 均限定为照片查看器快捷键，照片页和查找浮层的其他快捷键后续另行设计。

验收：

- Mac 原生 UI 视觉和交互与 Demo 核心行为 1:1 对齐。
- 设置页可切换中文/英文，界面即时刷新。
- 设置页可切换跟随系统/浅色/深色，界面即时刷新。
- 首次启动能请求照片权限，授权后能显示真实系统照片缩略图。
- 照片页缩放、排序、角标显示、多选、侧边栏筛选、查找浮层可用。
- 1 万条资产元数据导入后，页面滚动无明显卡顿；不允许再以“后续替换网格技术”为前提验收。

P0 开发完成定义：

- 所有页面没有阻塞式同步 IO。
- 缩略图请求取消与 cell 复用逻辑完整，快速滚动不堆积过期请求。
- 所有可见文案可在中文/英文之间切换。
- 所有颜色、阴影、material、角标色来自 `DesignSystem`。
- 所有筛选入口写入同一份 `SearchFilterState`。
- P0 SQL migration 可从空数据库稳定创建，重复启动不报错。
- 标签、人物等筛选维度可查询；如果暂无数据，返回空结果。

### P1：搜索、筛选与 Apple Vision 美学评分

目标：Demo 中照片主页、搜索、筛选功能进入可用状态，并完成唯一 AI 能力：Apple Vision 美学评分。

任务：

- 实现 `SearchFilterState`。
- 实现侧边栏快捷筛选。
- 实现全局查找浮层。
- 实现 SQL 过滤和 FTS5 关键词搜索。
- 建立 P1 分析表、`ai_models` Apple Vision 内置模型记录、`analysis_runs`、`analysis_tasks`、`analysis_outputs`。
- 实现 Apple Vision 美学评分（`visionAesthetics` 任务）：含截图识别和评分强制为 0 逻辑。
- 实现美学评分重跑、覆盖旧分数、批次追溯和中断恢复。
- 实现分析任务进度条（菜单栏）与暂停/继续。
- 实现照片查看器详情面板（美学评分展示）。
- **P1 暂不实现：** 场景标签、人脸检测、OCR、feature print、综合评分及其他维度分。

验收：

- 查找浮层与侧边栏筛选能实时更新照片墙。
- FTS5 与结构化 SQL 组合查询稳定，人物/标签等暂无数据维度返回空结果。
- Vision 美学评分写入数据库并显示评分角标；截图的美学评分显示为 0。
- 新批次美学评分可覆盖旧分数，`photo_scores` 可追溯到当前分数所属 `analysis_run_id`、`analysis_output_id` 和 `model_id`。
- 应用重启后只恢复未完成任务，不重复跑已完成照片。
- 照片查看器能展示真实元数据和美学评分结果。

### P2：向量搜索 + 性能同步基础

目标：在 P0/P1 可用基础上接入向量搜索，并提升大图库稳定性、同步一致性和真实产品可用性。P2 包含 embedding 生成、sqlite-vec 索引和语义检索；不包含依赖自定义模型的打标签、人物分析、日记、独特性分析等能力。

任务：

- 1 万 / 10 万照片库性能压测。
- 优化 `NSCollectionView` 布局、预取、diff、缩略图缓存和请求取消。
- 完善照片库变化监听与增量同步。
- 实现 `EmbeddingProvider1536`、`VectorIndex`、`SQLiteVecIndex`。
- 实现 `embedding_spaces`、`photo_embeddings`、`vec_text_1536`、`vec_image_1536`、`vec_video_1536` migration。
- 实现 text/image/video embedding 任务、断点恢复、重跑和索引更新。
- 实现向量搜索查询：KNN 召回 + `SearchFilterState` 结构化条件过滤 + 距离/评分/时间 rerank。
- 实现相似照片和以图搜图的基础入口。
- 完善 iCloud 状态字段落库和查询展示；具体下载/分析流程后续再开发。
- 完善 App 内废片篓标记、恢复、清空和真正删除前确认流程。
- 接入 Core Spotlight 的非 AI 基础索引。
- 实现真实非 AI 统计报告。
- 实现完整时间线页面（待 Demo 设计稳定后启动）。

验收：

- 10 万资产下列表浏览、筛选、查找无明显卡顿。
- 用户可用自然语言或相似照片入口召回相关照片，结果可继续叠加时间、评分、人物、标签、设备等结构化筛选。
- sqlite-vec extension 加载、签名、公证路径有降级策略；不可用时向量搜索关闭但 SQL/FTS5 不受影响。
- embedding 任务重启后不重复跑已完成照片，模型/维度/空间变更后可重建对应向量空间。
- 照片库增量变化可稳定同步。
- App 内废片篓与真正删除语义清晰，恢复和删除状态一致。
- 报告页展示真实非 AI 统计报告。
- 时间线页原生实现与 Demo 最终版对齐。

### P3：性能与生产化

目标：支撑大图库，具备长期使用能力。

任务：

- 1 万 / 10 万照片库压测。
- 优化 `NSCollectionView` 布局、预取、diff 和缓存策略。
- 完善数据库迁移和崩溃恢复。
- 增量同步照片库变化。
- 完善错误处理、权限引导和用户通知。
- 打包、签名、公证。

验收：

- 10 万资产下列表浏览不卡顿。
- 应用重启后分析进度可恢复。
- 删除、恢复、收藏等操作与系统照片库状态一致。

---

## 9. 风险与应对

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| 大图库缩略图加载卡顿 | 影响核心体验 | P0 直接使用 `NSCollectionView` + `PHCachingImageManager` + 请求取消 |
| SwiftUI 网格万级性能不足 | 滚动掉帧 | 不使用 `LazyVGrid` 承载照片墙，SwiftUI 只负责壳层和面板 |
| Vision API 版本差异 | 评分不可用 | 做可用性检测，低版本降级为标签/清晰度启发式 |
| macOS 版本能力差异 | 用户设备上部分能力不可用 | 主技术栈为 macOS Tahoe 26.5+ / Xcode 16.5+，每个 Vision request 都做 availability guard |
| MLX-VLM 内存占用高 | 低内存 Mac 不稳定 | 默认关闭，按需启用，模型分级 |
| 外部模型分析输入产生大量临时文件 | 磁盘 IO 高、清理风险 | 主路径使用 ImageIO/AVAssetImageGenerator 全内存 JPEG Data |
| 照片权限受限 | 资产不完整 | 提供权限状态页和系统设置跳转 |
| 删除操作不可逆风险 | 用户信任风险 | 第一阶段只移入系统照片废纸篓，所有删除前二次确认 |
| 数据库 schema 快速变化 | 迁移成本 | 从第一版开始建立 migration 机制 |
| UI 复刻偏离 Demo | 产品体验回退 | P0 建立 Demo 对照清单，每个交互逐项验收 |
| 语言切换遗漏硬编码 | 中英文体验不完整 | 禁止 View 中硬编码展示文案，统一走 String Catalog |
| 主题颜色散落 | 暗色/亮色不一致 | 页面禁止直接写颜色，统一通过 DesignSystem token |
| sqlite-vec 打包风险 | P2 语义搜索延期 | `VectorIndex` 抽象 + embedding 元数据先落库，sqlite-vec 作为可替换 adapter |
| 768/1536 向量混用 | 搜索结果失真 | 按 `embedding_spaces` 隔离模型、维度和模态，不同维度不混查 |
| AI 重分析覆盖用户数据 | 用户信任风险 | `analysis_outputs` 版本化，用户确认标签/人物永不被自动覆盖 |

---

## 10. 性能层设计审核

本轮审核目标：确认技术选型一次到位，不采用性能低、后续必然重构的临时方案。

| 审核项 | 结论 | 设计决定 |
| --- | --- | --- |
| 照片网格 | 原方案 `LazyVGrid` 起步不合格 | P0 直接使用 `NSCollectionView` |
| 缩略图加载 | 必须支持快速滚动和请求取消 | `PHCachingImageManager` + `PHImageRequestID` 取消 |
| Core ML/Vision 批量分析 | 需要低功耗和系统调度 | 使用 Apple Vision/Core ML 默认硬件调度，不手写 ANE 绑定 |
| HEIC 外部模型输入 | 不能批量导出临时 JPEG | ImageIO 全内存 HEIC→JPEG Data |
| HEVC 视频输入 | 不能用 ffmpeg 作为主路径 | AVAssetImageGenerator 抽关键帧 + 内存 JPEG |
| 大量标签/人物筛选 | 单表数组或字符串不合格 | 字典/实体表 + 关联表 + 索引 |
| 向量维度 | 768 对跨模态图片/视频语义搜索偏保守 | 默认 1536 维，按 space 隔离不同模型 |
| AI 输出覆盖 | 直接覆盖旧数据不合格 | `analysis_runs` + `analysis_outputs` 版本化 |
| 用户确认数据 | 自动模型不得覆盖 | 用户标签/人物命名/合并优先级最高 |
| 用户模型切换 | UI 直接绑定模型不合格 | `AIAnalysisProvider` 策略模式 |
| 数据库查询 | JSON 全表扫不合格 | 高频条件全部结构化表和索引，JSON 只保存低频配置 |
| 视频搜索 | 只按文件级标签不够 | 视频摘要向量 + 关键帧向量 |
| 未来扩展 | 单一 embedding 表不够 | `embedding_spaces` 管理模型、维度、模态 |

审核结论：当前方案已移除临时网格方案，AI、向量、标签、人物、重分析机制均有长期架构支撑，可以进入开发。

---

## 11. 建议目录结构

```text
MantaPhotosMac/
├── MantaPhotosMac.xcodeproj
├── MantaPhotosMac/
│   ├── App/
│   │   ├── MantaPhotosApp.swift
│   │   └── AppCommands.swift
│   ├── Localization/
│   │   ├── Localizable.xcstrings
│   │   └── LocalizationManager.swift
│   ├── Design/
│   │   ├── DesignSystem.swift
│   │   └── ThemeManager.swift
│   ├── Models/
│   │   ├── PhotoAsset.swift
│   │   ├── PhotoScore.swift
│   │   └── SearchFilterState.swift
│   ├── Services/
│   │   ├── PhotoLibraryService.swift
│   │   ├── AnalysisScheduler.swift
│   │   ├── VisionAnalyzer.swift
│   │   ├── PeopleClusterProvider.swift
│   │   └── FilterEngine.swift
│   ├── Storage/
│   │   ├── Database.swift
│   │   ├── Migrations/
│   │   └── Repositories/
│   ├── AI/
│   │   ├── AIModelProvider.swift
│   │   ├── AppleVisionProvider.swift
│   │   ├── UserCoreMLProvider.swift
│   │   ├── UserMLXProvider.swift
│   │   ├── ExternalModelMediaPreprocessor.swift
│   │   ├── ExternalModelClient.swift
│   │   ├── EmbeddingProvider1536.swift
│   │   └── AIModelRegistry.swift
│   ├── Vector/
│   │   ├── VectorIndex.swift
│   │   ├── VectorFeatureDisabledIndex.swift
│   │   └── SQLiteVecIndex.swift
│   └── Views/
│       ├── Shell/
│       ├── Photos/
│       │   ├── PhotoGridView.swift
│       │   ├── PhotoCollectionViewController.swift
│       │   └── PhotoCollectionCell.swift
│       ├── Find/
│       ├── Timeline/
│       ├── Reports/
│       └── Settings/
└── Tests/
    ├── FilterEngineTests.swift
    ├── LocalizationTests.swift
    ├── ThemeManagerTests.swift
    ├── ScoringEngineTests.swift
    └── DatabaseMigrationTests.swift
```

---

## 12. 第一批开发任务清单

建议按以下顺序开工：

1. 创建 `MantaPhotosMac` Xcode 工程和基础目录。
2. 建立 `DesignSystem`、`ThemeManager`、`LocalizationManager`。
3. 建立 `Localizable.xcstrings`，录入中文和英文基础文案。
4. 搭建 `AppShellView`：顶部栏、底部栏、页面路由、快捷键。
5. 搭建 `NSCollectionView` 照片墙：`PhotoCollectionViewController`、cell 复用、layout、diffable data source。
6. 复刻照片页工具栏：缩放、角标维度、排序、多选。
7. 复刻侧边栏快捷筛选：类型、评分、时间、状态、设备、人物、标签。
8. 复刻全局查找浮层，接入统一 `SearchFilterState`。
9. 搭建报告页、设置页、照片查看器壳层；时间线页仅创建导航菜单入口（占位），不复刻 Demo UI。
10. 引入 GRDB，建立数据库初始化和 P0 migration。
11. 实现 `PhotoLibraryService` 权限请求与 `PHAsset` 枚举。
12. 实现 `PhotoRepository`，把资产快照写入 `photo_assets` 表。
13. 实现真实缩略图加载、`PHCachingImageManager` 预热和请求取消。
14. 实现基础 SQL 筛选、排序和当前筛选状态持久化。
15. P0 验收：中英文、主题三态、照片主页、查找、筛选、设置页、1 万资产滚动逐项对照 Demo。
16. P1 建立 `AIModelRegistry`、`AppleVisionProvider`、`analysis_runs`、`analysis_tasks`、`analysis_outputs`。
17. P1 实现 `visionAesthetics` 任务：截图识别（`PHAsset.mediaSubtype`）+ Vision 美学评分 + 截图强制为 0。
18. P1 验收：FTS5/SQL 查询、美学评分重跑与覆盖、任务中断恢复、查看器真实评分展示。

---

## 15. 参考资料

- Apple Photos Framework：`https://developer.apple.com/documentation/photos`
- `PHPhotoLibraryChangeObserver`：`https://developer.apple.com/documentation/photos/phphotolibrarychangeobserver`
- `PHAsset`：`https://developer.apple.com/documentation/photos/phasset`
- `PHCachingImageManager`：`https://developer.apple.com/documentation/photos/phcachingimagemanager`
- Apple Vision：`https://developer.apple.com/documentation/vision`
- `VNCalculateImageAestheticsScoresRequest`：`https://developer.apple.com/documentation/vision/vncalculateimageaestheticsscoresrequest`
- `VNGenerateImageFeaturePrintRequest`：`https://developer.apple.com/documentation/vision/vngenerateimagefeatureprintrequest`
- Vision Selfie / Face Analysis Sample：`https://developer.apple.com/documentation/vision/analyzing-a-selfie-and-visualizing-its-content`
- ImageIO / `CGImageSource`：`https://developer.apple.com/documentation/imageio/cgimagesource`
- ImageIO / `CGImageDestination`：`https://developer.apple.com/documentation/imageio/cgimagedestination`
- AVFoundation / `AVAssetImageGenerator`：`https://developer.apple.com/documentation/avfoundation/avassetimagegenerator`
- VideoToolbox：`https://developer.apple.com/documentation/videotoolbox`
- Core ML：`https://developer.apple.com/documentation/coreml`
- Core Spotlight：`https://developer.apple.com/documentation/corespotlight`
- String Catalog：`https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog`
- SwiftUI Locale Environment：`https://developer.apple.com/documentation/swiftui/environmentvalues/locale`
- SwiftUI ColorScheme：`https://developer.apple.com/documentation/swiftui/colorscheme`
- SwiftData：`https://developer.apple.com/documentation/swiftdata`
- GRDB.swift：`https://github.com/groue/GRDB.swift`
- MLX Swift：`https://github.com/ml-explore/mlx-swift`
- sqlite-vec：`https://github.com/asg017/sqlite-vec`
- 本地技术调研：`doc/技术调研-macOS原生实现方案.md`
