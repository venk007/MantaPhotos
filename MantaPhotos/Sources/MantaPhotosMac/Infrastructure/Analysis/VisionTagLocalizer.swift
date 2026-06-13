import Foundation

/// 把 Vision `VNClassifyImageRequest` 的英文 identifier 本地化为当前语言的展示名。
///
/// Vision 的分类标识是语言无关的英文 taxonomy（如 "beach"），作为稳定 `tag_key` 保留；
/// 展示名按当前语言解析：中文用内置词表映射，命中不到则回退英文整理名；英文直接整理 identifier。
///
/// 单语言策略（v4）：中文环境下不应出现「无中文对应、随便整理大小写的英文单词」标签
/// （例如 "Abacus"），这类标签直接丢弃，不写入标签表；只有当英文本身就是业界公认的
/// 术语 / 缩写（如 RAW、HDR、4K、GPS）时才保留并按英文展示——这类词汇本身没有更自然
/// 的中文译法，中文用户也会直接使用英文原词。
///
/// 说明：内置中文词表覆盖常见场景 / 物体，非穷尽；未覆盖且非公认术语的项会被丢弃。
/// 后续 M4 的零样本中文词表会提供更完整、可维护的中文标签体系，届时本映射可并入或替换。
enum VisionTagLocalizer {
    /// 是否中文环境（按当前 locale 标识判断）。
    static func isChinese(localeIdentifier: String) -> Bool {
        localeIdentifier.lowercased().hasPrefix("zh")
    }

    /// 将 identifier 本地化为展示名；返回 `nil` 表示该标签在当前语言下不应展示，
    /// 调用方应丢弃该标签（不写入标签表）。
    static func displayName(forIdentifier identifier: String, localeIdentifier: String) -> String? {
        if isChinese(localeIdentifier: localeIdentifier) {
            let key = identifier.lowercased()
            if let zh = chineseMap[key] { return zh }
            if let term = recognizedEnglishTerms[key] { return term }
            return nil // 无中文对应、也非公认英文术语 —— 丢弃，避免中文环境出现英文标签
        }
        return prettifyEnglish(identifier)
    }

    /// 业界公认、即使在中文环境下也直接使用英文原词的术语 / 缩写（小写键 → 展示形式）。
    /// 这类词本身就是「中文用户也会直接说的英文词」，不属于「未翻译的英文标签」。
    private static let recognizedEnglishTerms: [String: String] = [
        "raw": "RAW", "hdr": "HDR", "gif": "GIF", "pdf": "PDF",
        "vr": "VR", "ar": "AR", "ai": "AI", "gps": "GPS",
        "led": "LED", "usb": "USB", "wifi": "Wi-Fi", "dna": "DNA",
        "logo": "Logo", "app": "App", "qr code": "QR Code", "qrcode": "QR Code"
    ]

    /// 英文整理：下划线 / 连字符转空格，首字母大写。
    private static func prettifyEnglish(_ identifier: String) -> String {
        let spaced = identifier
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return spaced
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// 常见 Vision identifier → 中文（小写键）。覆盖人物 / 动物 / 自然 / 城市 / 食物 / 室内 / 媒体类型等高频类目。
    private static let chineseMap: [String: String] = [
        // 人物
        "people": "人物", "person": "人物", "group": "合影", "crowd": "人群",
        "portrait": "人像", "selfie": "自拍", "baby": "婴儿", "child": "儿童", "wedding": "婚礼",
        // 动物
        "animal": "动物", "dog": "狗", "cat": "猫", "bird": "鸟", "fish": "鱼",
        "horse": "马", "insect": "昆虫", "butterfly": "蝴蝶", "wildlife": "野生动物",
        // 自然 / 风景
        "nature": "自然", "landscape": "风景", "sky": "天空", "cloud": "云",
        "sunset": "日落", "sunrise": "日出", "beach": "海滩", "ocean": "海洋", "sea": "海",
        "water": "水", "lake": "湖泊", "river": "河流", "waterfall": "瀑布",
        "mountain": "山", "hill": "丘陵", "snow": "雪", "forest": "森林", "tree": "树",
        "plant": "植物", "flower": "花", "grass": "草地", "garden": "花园", "desert": "沙漠",
        "rainbow": "彩虹", "fog": "雾", "rock": "岩石", "field": "田野", "park": "公园",
        // 城市 / 建筑
        "city": "城市", "building": "建筑", "structure": "建筑", "architecture": "建筑",
        "skyline": "城市天际线", "street": "街道", "road": "道路", "bridge": "桥",
        "house": "房屋", "interior": "室内", "indoor": "室内", "outdoor": "户外",
        "room": "房间", "kitchen": "厨房", "office": "办公室", "tower": "塔",
        "monument": "纪念碑", "church": "教堂", "temple": "寺庙",
        // 交通工具
        "vehicle": "交通工具", "car": "汽车", "bicycle": "自行车", "motorcycle": "摩托车",
        "boat": "船", "ship": "船", "airplane": "飞机", "train": "火车", "bus": "公交车",
        // 食物
        "food": "食物", "meal": "餐食", "beverage": "饮品", "drink": "饮品",
        "coffee": "咖啡", "fruit": "水果", "vegetable": "蔬菜", "dessert": "甜点",
        "cake": "蛋糕", "bread": "面包",
        // 活动 / 物体
        "sport": "运动", "music": "音乐", "concert": "演唱会", "art": "艺术",
        "painting": "绘画", "furniture": "家具", "book": "书籍", "toy": "玩具",
        "clothing": "服饰", "jewelry": "珠宝", "electronics": "电子产品",
        // 媒体 / 文档
        "text": "文字", "document": "文档", "screenshot": "截图", "poster": "海报",
        "sign": "标识", "map": "地图", "night": "夜景", "fireworks": "烟花",
        "light": "灯光", "abstract": "抽象"
    ]
}
