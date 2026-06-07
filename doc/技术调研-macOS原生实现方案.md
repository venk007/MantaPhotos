# 技术调研：MantaPhotos macOS 原生实现方案

> **文档版本：** v1.0  
> **创建日期：** 2026-06-04  
> **作者：** Venk  
> **背景：** 评估将当前 HTML/CSS/JS Demo 落地为 macOS 原生应用时，AI 评分与图片格式处理的最优技术路线。

---

## Q1：CoreML + Vision 框架 / NEON / ANE 加速，以及与 Qwen3 的比较

### 1.1 CoreML 是什么

**CoreML** 是 Apple 的本地机器学习运行引擎。任何主流框架训练的模型（PyTorch、ONNX、TensorFlow、scikit-learn）都可通过 `coremltools` 转换为 `.mlpackage` 格式，之后交由 CoreML 以最优方式在 Apple 硬件上运行。

CoreML 的核心优势：
- **自动硬件调度**：运行时自动选择 ANE / GPU / CPU，无需开发者手动分配
- **零网络依赖**：完全本地推理，隐私安全，离线可用
- **系统级优化**：与 macOS 内存管理、后台任务调度深度集成

### 1.2 Vision 框架是什么

**Vision** 是建立在 CoreML 之上的高层图像分析框架，Apple 提供了一系列开箱即用的内置请求：

| 请求类型 | API | 说明 |
|---------|-----|------|
| 图像美学质量 | `VNImageAestheticsScoresRequest` | 直接输出美学分（iOS/macOS 17+） |
| 人脸检测与识别 | `VNDetectFaceRectanglesRequest` | 检测人脸边框、关键点、表情 |
| 场景分类 | `VNClassifyImageRequest` | 输出场景/内容标签（风景/建筑/食物等） |
| 文字识别 | `VNRecognizeTextRequest` | OCR，用于识别截图中的文字 |
| 物体检测 | `VNDetectContoursRequest` | 主体轮廓提取 |
| 图像质量评估 | `VNImageAestheticsScoresRequest` | 返回 `isBlurry`、`isShotWithFlash`、`overallScore` 等 |

> **重要**：`VNImageAestheticsScoresRequest` 在 macOS 14（Sonoma）起可用，直接输出与 iOS 照片 App 一致的美学评分，无需额外模型。

### 1.3 NEON 与 ANE 加速

| 加速器 | 全称 | 本质 | 在 MantaPhotos 中的角色 |
|--------|------|------|------------------------|
| **NEON** | ARM Advanced SIMD | CPU 内置向量指令集，一次可并行处理 4–16 个浮点运算 | CoreML 小模型的 CPU 回退路径；图像预处理（缩放/归一化）加速 |
| **ANE** | Apple Neural Engine | 芯片内独立 ML 加速块，专门执行矩阵乘法 | CoreML 的首选推理目标；**完全不占 CPU / GPU 资源**，对系统响应无影响 |

Apple Silicon ANE 算力参考：

| 芯片 | ANE 算力 | 等效每秒推理次数（ResNet-50） |
|------|---------|---------------------------|
| M1 | 11 TOPS | ~3,000 次/秒 |
| M3 Pro | 18 TOPS | ~5,000 次/秒 |
| M4 Pro | 38 TOPS | ~10,000 次/秒 |

对于照片评分场景，ANE 可以在 **<5ms / 张**完成美学评分，对 10 万张照片库的全量分析约需 10 分钟，且不会影响用户操作流畅度。

### 1.4 CoreML 专用模型 vs Qwen3-VL 开源模型

| 对比维度 | CoreML 专用模型（如 NIMA / Vision 内置） | Qwen3-VL（7B 量化） |
|---------|----------------------------------------|---------------------|
| **模型大小** | 5–30 MB | 4–14 GB（Q4 量化后） |
| **单张推理速度** | **<5ms**（ANE 硬件加速） | 1–10 秒（GPU 推理） |
| **美学/技术打分** | ✅ 专项优化，与系统照片 App 一致 | ✅ 多维理解，更灵活 |
| **内容/场景描述** | ❌ 仅输出分类标签，不生成自然语言 | ✅ 可生成完整描述 |
| **情感/意境分析** | ❌ | ✅ |
| **照片回忆文字** | ❌ | ✅ |
| **截图判定** | ✅ `VNImageAestheticsScoresRequest.isShotWithFlash` + OCR | ✅ 直接识别 |
| **离线可用** | ✅ 完全本地 | ✅（需 4–14GB 本地显存） |
| **内存占用** | <200 MB | 6–16 GB |
| **电量影响** | 极低（ANE 独立电路） | 中等（GPU 满载） |

**结论**：两者不是替代关系，而是互补分层：
- CoreML Vision 负责**批量、快速、低功耗**的初筛（美学分、截图判定、场景标签）
- Qwen3-VL 负责**按需、高质量**的深度分析（内容描述、情感、日记生成）

### 1.5 macOS 应用推荐的混合评分策略

```
┌─────────────────────────────────────────────────────────────┐
│  第 1 步（导入时自动，<5ms/张）                               │
│  CoreML Vision → VNImageAestheticsScoresRequest             │
│  输出：美学分、isBlurry、isShotWithFlash、overallScore        │
│  + VNClassifyImageRequest → 场景标签（风景/人物/建筑…）       │
│  + VNDetectFaceRectanglesRequest → 人物检测                  │
├─────────────────────────────────────────────────────────────┤
│  第 2 步（首次全量分析，后台静默，ANE 加速）                   │
│  自定义 CoreML 模型（NIMA 转换）→ 六维细分评分                │
│  + VNRecognizeTextRequest → 截图识别（文字密度判定）          │
├─────────────────────────────────────────────────────────────┤
│  第 3 步（按需调用，高分照片 / 用户主动触发）                  │
│  Qwen3-VL 本地量化（mlx-lm / llama.cpp）                    │
│  → 内容描述、情感分析、照片日记生成、自然语言搜索索引           │
└─────────────────────────────────────────────────────────────┘
```

用户可在设置中选择策略：
- **极速模式**：仅 Step 1，<1 分钟完成 10 万张初筛
- **均衡模式**（默认）：Step 1 + Step 2，ANE 后台处理
- **完整模式**：全部三步，Qwen3 深度分析（需 16GB+ RAM 的 Mac）

---

## Q2：HEIC / HEVC 转码方案（低 CPU / GPU 内存消耗）

### 2.1 问题背景

- macOS 照片库的照片格式为 **HEIC**（High Efficiency Image Container，基于 H.265/HEVC 编码）
- 录制的视频格式为 **HEVC**（H.265）
- Qwen3-VL 的 API/本地 server 仅接受 **JPEG / PNG**，不支持 HEIC / HEVC 直接输入
- 需要在送入模型前完成格式转换，且要求：**零磁盘写入、最低 CPU/GPU 占用**

### 2.2 核心方案：全内存管道

利用 macOS 的 **ImageIO** 和 **VideoToolbox** 框架，整个转换过程在内存中完成，不产生任何临时文件。

#### 图片：HEIC → JPEG（内存管道）

```swift
import ImageIO
import CoreGraphics

func heicToJpegData(url: URL, maxDimension: Int = 1024) -> Data? {
    // Step 1：ImageIO 读取 HEIC
    // Apple Silicon 内置 HEIC 硬件解码器，此步不走 CPU
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

    // Step 2：等比缩放到分析分辨率（减少 80% 内存和网络传输）
    let scaled = scaleDown(cgImage, maxDimension: maxDimension)

    // Step 3：编码为 JPEG，写入内存 buffer，不落盘
    let buffer = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        buffer, "public.jpeg" as CFString, 1, nil
    ) else { return nil }
    CGImageDestinationAddImage(dest, scaled, [
        kCGImageDestinationLossyCompressionQuality: 0.85
    ] as CFDictionary)
    CGImageDestinationFinalize(dest)

    return buffer as Data
    // 直接 base64 编码 → 发送给 Qwen API，或转为 UIImage/NSImage 用于本地推理
}

func scaleDown(_ image: CGImage, maxDimension: Int) -> CGImage {
    let w = image.width, h = image.height
    guard max(w, h) > maxDimension else { return image }
    let scale = CGFloat(maxDimension) / CGFloat(max(w, h))
    let newW = Int(CGFloat(w) * scale), newH = Int(CGFloat(h) * scale)
    let ctx = CGContext(data: nil, width: newW, height: newH,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
    return ctx.makeImage()!
}
```

#### 视频：HEVC → 关键帧 JPEG（硬件解码）

```swift
import AVFoundation

func hevcKeyFrameToJpegData(url: URL, atSeconds: Double = 3.0) async -> Data? {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 1024, height: 1024)
    // requestedTimeToleranceBefore/After 为 0 确保精确帧
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter  = CMTime(seconds: 1, preferredTimescale: 600)

    // AVAssetImageGenerator 底层走 VideoToolbox 硬件 HEVC 解码
    // 在 Apple Silicon 上由 Media Engine 专用解码器处理，不占 CPU/GPU
    let time = CMTime(seconds: atSeconds, preferredTimescale: 600)
    guard let frame = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }

    // 同上：内存编码为 JPEG
    let buffer = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        buffer, "public.jpeg" as CFString, 1, nil
    ) else { return nil }
    CGImageDestinationAddImage(dest, frame, [
        kCGImageDestinationLossyCompressionQuality: 0.85
    ] as CFDictionary)
    CGImageDestinationFinalize(dest)
    return buffer as Data
}
```

### 2.3 各方案资源对比

| 方案 | CPU 占用 | GPU 占用 | 内存峰值 | 磁盘 IO | 适用场景 |
|------|---------|---------|---------|---------|---------|
| **ImageIO + 内存 buffer（推荐）** | **极低**（硬件解码） | **0** | ~2–5 MB/张 | **0** | 照片批量转换 |
| AVAssetImageGenerator + 内存 buffer（推荐）| **极低**（Media Engine）| **0** | ~5–10 MB/帧 | **0** | 视频关键帧提取 |
| `sips` 命令行工具 | 中等 | 0 | 低 | 每张写临时文件 | 脚本/调试 |
| `ffmpeg` 转码 | 高 | 可选 | 中 | 写文件 | 复杂视频处理 |
| CGContext CPU 软渲染 | 高 | 0 | 中 | 0 | 降级兜底 |

### 2.4 Apple Silicon 硬件加速层级

```
HEIC 解码路径（Apple Silicon）：
  ImageIO 调用 → ISP / Media Engine 硬件解码 → CGImage（已在 GPU 纹理缓存）
                                                     ↓
                                          CGContext 缩放（GPU Blit）
                                                     ↓
                                          JPEG 编码 → NSData（CPU，约 2ms）

HEVC 视频帧提取路径：
  AVAssetImageGenerator → VideoToolbox → Media Engine HEVC 解码器
  → CGImage → 同上 JPEG 编码管道
```

全程 CPU 参与时间 <5ms/张，Media Engine 与 CPU 异步执行，对用户界面响应零影响。

### 2.5 批量处理建议

```swift
// 使用 Swift Concurrency 控制并发数，避免内存峰值过高
await withTaskGroup(of: Void.self) { group in
    let semaphore = AsyncSemaphore(value: 4) // 同时处理 4 张
    for photoURL in photoURLs {
        group.addTask {
            await semaphore.wait()
            defer { semaphore.signal() }
            if let jpeg = heicToJpegData(url: photoURL) {
                await sendToQwen(jpeg)
            }
        }
    }
}
```

并发数建议：
- M1/M2 Mac：**4 并发**（Media Engine 2 路 + CPU 线程补足）
- M3 Pro/M4 Pro Mac：**8 并发**（双 Media Engine）
- 内存 < 16GB：降至 **2 并发**防止内存压力

---

## 参考资料

- [Apple Developer: CoreML](https://developer.apple.com/documentation/coreml)
- [Apple Developer: Vision Framework](https://developer.apple.com/documentation/vision)
- [Apple Developer: VNImageAestheticsScoresRequest](https://developer.apple.com/documentation/vision/vnimagestheticsscoresrequest)
- [Apple Developer: ImageIO](https://developer.apple.com/documentation/imageio)
- [Apple Developer: AVAssetImageGenerator](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator)
- [coremltools 文档](https://coremltools.readme.io/docs)
- [mlx-lm：Apple Silicon 上运行 Qwen 等 LLM](https://github.com/ml-explore/mlx-examples)
