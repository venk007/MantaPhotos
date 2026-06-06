// ========== 数据 ==========
var weightConfig = [
    {id:'aesthetics',name:'美学评分',icon:'fa-palette',desc:'构图/清晰度/色彩/光线',weight:30},
    {id:'technical',name:'技术质量',icon:'fa-cog',desc:'清晰度/噪点/曝光/抖动',weight:30},
    {id:'content',name:'内容价值',icon:'fa-star',desc:'活动/旅行/聚会/人物',weight:15},
    {id:'emotion',name:'情感价值',icon:'fa-heart',desc:'表情/回忆感/人物亲密',weight:10},
    {id:'rarity',name:'稀有性',icon:'fa-gem',desc:'时间/地点稀有程度',weight:10},
    {id:'uniqueness',name:'独特性',icon:'fa-fingerprint',desc:'照片重复度',weight:5},
];
var promptTasks = [
    {id:'score',name:'综合评分',badge:'内置',prompt:'你是照片质量评估助手。请基于美学评分（aesthetic_score）与其他维度分（technical/content/emotion/rarity/uniqueness）计算综合评分（final_score），输出JSON。'},
    {id:'aestheticsStrict',name:'美学评分（严格）',badge:'系统锁定',locked:true,prompt:'你是严格摄影美学评审员。仅从摄影美学维度打分（构图、光线、色彩、主体层次）。若检测到截图/录屏/界面截取内容，aesthetic_score 必须为 0，不可例外。输出 JSON: {"aesthetic_score":0-100,"is_screenshot":true|false,"reason":"一句话说明"}。'},
    {id:'tag',name:'内容标签',badge:'内置',prompt:'请分析照片内容，输出场景/物品/人物/活动等标签数组。'},
    {id:'person',name:'人物识别',badge:'内置',prompt:'请分析照片中的人物数量、表情、是否有自拍特征。'},
    {id:'location',name:'地理位置',badge:'内置',prompt:'请分析照片的地理位置、是否为旅行照。'},
    {id:'description',name:'照片内容描述（≤300字）',badge:'内置',outputLimit:300,prompt:'请在300字以内描述照片内容，包含拍摄主体、场景信息，以及植物/动物/食物等可识别对象的简短科普信息。输出 JSON: {"description":"..."}。'},
    {id:'diary',name:'照片回忆（≤200字）',badge:'内置',outputLimit:200,prompt:'请在200字以内生成照片回忆，包含：同行好友、拍摄时间、旅行第几天、城市、拍摄前后活动、拍摄时心情分析。输出 JSON: {"diary":"..."}。'},
];
var reports = [
    { id: 1, title: '首次分析报告', date: '2026-05-25', type: 'initial', photoCount: 45678, videoCount: 3214, avgScore: 68.5, wasteCount: 12345 },
    { id: 2, title: '周度分析报告', date: '2026-05-20', type: 'weekly', photoCount: 1234, videoCount: 89, avgScore: 72.3, wasteCount: 234 },
    { id: 3, title: '旅行照片专项报告', date: '2026-05-15', type: 'manual', photoCount: 3456, videoCount: 156, avgScore: 81.2, wasteCount: 456 },
];
// 预设事件（type='event'）与月份回忆（type='memory'）混合使用
// year/month 字段用于排序与分组；photos 为缩略图数组；allPhotoIds 为真实 photo.id 列表（运行时填充）
var timelineEvents = [
    // 2026 — 仅月份回忆（由照片数据动态生成，见 buildTimelineData）
    // 2025 — 事件 + 月份回忆
    { year: 2025, month: 8, type: 'event', title: '三亚之旅', icon: 'fa-umbrella-beach', isTravel: true,
      desc: '5天4夜的海岛度假，浮潜、日落、海鲜大排档。',
      photos: ['https://picsum.photos/seed/t1/240/160','https://picsum.photos/seed/t2/240/160','https://picsum.photos/seed/t3/240/160','https://picsum.photos/seed/t4/240/160'] },
    { year: 2025, month: 8, type: 'memory', title: '8月回忆', icon: 'fa-calendar-alt', isTravel: false,
      desc: '三亚度假之外的日常片段。',
      photos: ['https://picsum.photos/seed/t21/240/160','https://picsum.photos/seed/t22/240/160'] },
    { year: 2025, month: 7, type: 'event', title: '张家界登山', icon: 'fa-mountain', isTravel: true,
      desc: '挑战天门山玻璃栈道，俯瞰云雾缭绕的峰林。',
      photos: ['https://picsum.photos/seed/t5/240/160','https://picsum.photos/seed/t6/240/160','https://picsum.photos/seed/t7/240/160'] },
    { year: 2025, month: 6, type: 'event', title: '北京美食周', icon: 'fa-utensils', isTravel: false,
      desc: '探访王府井小吃街、南锣鼓巷咖啡馆，拍了一百多张美食照。',
      photos: ['https://picsum.photos/seed/t8/240/160','https://picsum.photos/seed/t9/240/160','https://picsum.photos/seed/t23/240/160'] },
    { year: 2025, month: 5, type: 'event', title: '五一宠物运动会', icon: 'fa-dog', isTravel: false,
      desc: '小区举办的宠物运动会，柴柴拿了障碍赛冠军🏆',
      photos: ['https://picsum.photos/seed/t10/240/160','https://picsum.photos/seed/t11/240/160','https://picsum.photos/seed/t12/240/160','https://picsum.photos/seed/t13/240/160'] },
    { year: 2025, month: 3, type: 'event', title: '成都骑行', icon: 'fa-bicycle', isTravel: true,
      desc: '骑行天府绿道，锦城湖边的油菜花海正值盛放。',
      photos: ['https://picsum.photos/seed/t24/240/160','https://picsum.photos/seed/t25/240/160','https://picsum.photos/seed/t26/240/160'] },
    { year: 2025, month: 1, type: 'memory', title: '1月回忆', icon: 'fa-calendar-alt', isTravel: false,
      desc: '新年第一批照片，家人聚会。',
      photos: ['https://picsum.photos/seed/t27/240/160','https://picsum.photos/seed/t28/240/160'] },
    // 2024
    { year: 2024, month: 12, type: 'event', title: '圣诞聚会', icon: 'fa-snowflake', isTravel: false,
      desc: '朋友们在家中举办的圣诞晚餐，交换礼物、拍了大量合影。',
      photos: ['https://picsum.photos/seed/t14/240/160','https://picsum.photos/seed/t15/240/160','https://picsum.photos/seed/t16/240/160'] },
    { year: 2024, month: 10, type: 'event', title: '厦门秋游', icon: 'fa-water', isTravel: true,
      desc: '国庆假期在厦门鼓浪屿骑行，留下大量街拍与海景。',
      photos: ['https://picsum.photos/seed/t17/240/160','https://picsum.photos/seed/t18/240/160','https://picsum.photos/seed/t29/240/160'] },
    { year: 2024, month: 10, type: 'memory', title: '10月回忆', icon: 'fa-calendar-alt', isTravel: false,
      desc: '厦门之行以外的秋日片段。',
      photos: ['https://picsum.photos/seed/t30/240/160','https://picsum.photos/seed/t31/240/160'] },
    { year: 2024, month: 8, type: 'event', title: '黄山云海徒步', icon: 'fa-cloud', isTravel: true,
      desc: '凌晨4点出发看日出，云海翻腾，快门按到手软。',
      photos: ['https://picsum.photos/seed/t32/240/160','https://picsum.photos/seed/t33/240/160','https://picsum.photos/seed/t34/240/160','https://picsum.photos/seed/t35/240/160'] },
    { year: 2024, month: 6, type: 'event', title: '毕业季合影', icon: 'fa-graduation-cap', isTravel: false,
      desc: '好友毕业，在学校各个角落拍了最后一批"校园照"。',
      photos: ['https://picsum.photos/seed/t36/240/160','https://picsum.photos/seed/t37/240/160','https://picsum.photos/seed/t38/240/160'] },
    { year: 2024, month: 4, type: 'event', title: '杭州赏樱', icon: 'fa-tree', isTravel: true,
      desc: '太子湾公园的樱花正盛，人潮涌动但拍到了满意的空镜。',
      photos: ['https://picsum.photos/seed/t39/240/160','https://picsum.photos/seed/t40/240/160','https://picsum.photos/seed/t41/240/160'] },
    { year: 2024, month: 2, type: 'event', title: '春节家宴', icon: 'fa-fire', isTravel: false,
      desc: '大年三十的年夜饭，全家出动拍了一桌子菜的大合影。',
      photos: ['https://picsum.photos/seed/t42/240/160','https://picsum.photos/seed/t43/240/160','https://picsum.photos/seed/t44/240/160'] },
];

// ========== 状态管理 ==========
var currentPage = 'photos';
var selectMode = false;
var selectedPhotos = new Set();
var activeSidebarTag = 'all';
var activeQuickFilter = 'none';
var currentModel = 'Qwen3-VL-8B';
var pendingDeleteIds = [];
var pendingDeleteMode = 'normal';  // 'normal' | 'emptyTrash'
var firstAnalysisStrategies = ['仅今年', '近三年', '全量'];
var firstAnalysisStrategyIndex = 0;
var currentSortMode = 'dateDesc';
var currentDetailPhotoId = null;
var scoreBadgeMode = 'aesthetic';
var _viewerPhotoSet = null;   // null = 使用 getVisiblePhotos()，非 null = 事件页专用集合
var currentTimelineEvent = null;

// ========== 统一「查找」状态（搜索 + 筛选合一） ==========
function createEmptyFindState() {
    return {
        query: '',
        mediaTypes: [],   // ['photo','video','live','screenshot','raw']
        devices: [],      // 设备来源：['Pocket','运动相机','无人机','单反相机']
        scoreCond: { metric: 'aesthetics', op: 'gt', value: 0 }, // 单条实时评分条件；默认 美学>0 即不过滤
        dateRange: null,  // {start,end} | {holidays:true}
        dateLabel: '',
        locations: [],
        people: [],
        tags: [],
        isFavorite: false,
        isProDevice: false,
        isProEdited: false,
        isDuplicate: false,
        isNewMonth: false,
        isICloud: false,
        isInTrash: false
    };
}
var findState = createEmptyFindState();
var findAppliedToWall = false;   // 查找条件是否已投射到照片墙

// 照片网格尺寸：7级，对应每行列数；level 越大列越多（照片越小）
// − 按钮 = 缩小(+1 level) ; + 按钮 = 放大(-1 level)
var gridColLevels = [2, 4, 6, 8, 12, 16, 32];
var gridGapLevels = [14, 12, 10, 8, 6, 4, 2];
var gridSizeLevel = 3; // 默认8列

// 侧边栏悬浮触发
var sidebarHoverEnabled = true;
var sidebarHoverDelay = 0.5; // 固定 0.5 秒，不开放配置
var _sidebarHoverTimer = null;
// 滚动自动隐藏状态
var _preScrollSidebarVisible = true;  // 滚动前的展开状态
var _scrollDebounceTimer = null;
var _scrollHiddenByScroll = false;    // 是否是被滚动隐藏的

var scoreMetricLabels = {
    aesthetics: '美学评分',
    composite: '综合评分',
    technical: '技术质量',
    content: '内容价值',
    emotion: '情感价值',
    rarity: '稀有性',
    uniqueness: '独特性'
};
// 宠物/夜景已提升为默认可见标签（HTML中），这里只保留"更多"中的扩展标签
var hiddenSidebarTags = [
    { tag: '宠物', icon: 'fa-paw', count: 7 },
    { tag: '夜景', icon: 'fa-moon', count: 6 },
    { tag: '亲子', icon: 'fa-users', count: 3 },
    { tag: '运动', icon: 'fa-person-running', count: 5 },
    { tag: '花草', icon: 'fa-seedling', count: 4 },
    { tag: '海边', icon: 'fa-water', count: 2 }
];
var areExtraTagsVisible = false;

// ===== 侧边栏快捷筛选状态 =====
var DEMO_TODAY = new Date(2026, 5, 4); // demo 的"今天" = 2026-06-04
var sidebarTimeKey = null;             // 时间单选：null=不限
var sidebarMediaType = null;           // 类型单选：null=不限
var sidebarSource = null;              // 设备与来源（单选 key）
var sidebarPeople = [];                // 人物（多选）
var sidebarPeopleQuery = '';           // 人物搜索关键词

var mediaTypeQuickDefs = [
    { key: 'photo',      label: '照片', icon: 'fas fa-image' },
    { key: 'video',      label: '视频', icon: 'fas fa-video' },
    { key: 'live',       label: 'Live', icon: 'fas fa-bolt' },
    { key: 'screenshot', label: '截图', icon: 'fas fa-mobile-alt' },
    { key: 'raw',        label: 'RAW',  icon: 'fas fa-file-image' }
];
var timeQuickDefs = [
    { key: 'today',  label: '今天',   icon: 'fas fa-calendar-day' },
    { key: '3days',  label: '近3天',  icon: 'fas fa-calendar-day' },
    { key: 'week',   label: '近一周', icon: 'fas fa-calendar-week' },
    { key: 'month',  label: '本月',   icon: 'fas fa-calendar-alt' },
    { key: 'month1', label: '近一月', icon: 'fas fa-calendar-alt' },
    { key: 'year',   label: '本年',   icon: 'fas fa-calendar' }
];
var timeDefaultKeys = ['today', '3days', 'week']; // 默认展示今天/近3天/近一周
var timeExpanded = false;
var sourceExpanded = false;
var peopleExpanded = false;

function fmtLocalDate(d) {
    var m = String(d.getMonth() + 1).padStart(2, '0');
    var day = String(d.getDate()).padStart(2, '0');
    return d.getFullYear() + '-' + m + '-' + day;
}
function timeRangeFor(key) {
    var end = fmtLocalDate(DEMO_TODAY);
    function back(days) { var d = new Date(DEMO_TODAY); d.setDate(d.getDate() - days); return fmtLocalDate(d); }
    if (key === 'today')  return { start: end, end: end };
    if (key === '3days')  return { start: back(2), end: end };
    if (key === 'week')   return { start: back(6), end: end };
    if (key === 'month')  return { start: fmtLocalDate(new Date(2026, 5, 1)), end: end };
    if (key === 'month1') return { start: back(29), end: end };
    if (key === 'year')   return { start: fmtLocalDate(new Date(2026, 0, 1)), end: end };
    return null;
}

var analysisState = 'running';
var hotSearchPool = [
    { icon: 'fa-water', text: '去年夏天在海边拍的照片' },
    { icon: 'fa-dog', text: '有狗狗的照片' },
    { icon: 'fa-utensils', text: '旅行中的美食' },
    { icon: 'fa-mountain', text: '最近一次登山的风景' },
    { icon: 'fa-city', text: '在上海拍的夜景' },
    { icon: 'fa-camera-retro', text: '美学评分大于90' },
    { icon: 'fa-heart', text: '和家人的合照' },
    { icon: 'fa-plane', text: '去年旅行第3天的照片' }
];

// ========== 模拟照片数据 ==========
var photos = [];
// 四档配色分界：必须在数据生成循环和 buildRetentionAdvice 之前声明
var scoreTierBounds = { t1: 80, t2: 60, t3: 40 };
var tagPool = ['风景', '人物', '建筑', '美食', '旅行', '宠物', '夜景'];
var lowQualityTagPool = ['模糊', '曝光过度', '欠曝', '构图失衡', '主体缺失', '噪点过多', '画面杂乱'];
var locationPool = ['北京', '上海', '厦门', '南京', '杭州', '三亚', '成都', '西安', '广州', '深圳'];
var friendPool = ['小林', '阿泽', 'Mia', '可可', '安妮', '家人'];
var peoplePool = ['小林', '阿泽', 'Mia', '可可', '安妮'];
var moodPool = ['轻松', '兴奋', '平静', '满足', '惊喜', '治愈'];
var beforeActivityPool = ['早起散步', '在咖啡店规划路线', '逛了当地早市', '从博物馆出来', '刚结束一段车程'];
var afterActivityPool = ['去附近餐馆补给', '继续下一段城市漫步', '回到酒店整理照片', '和朋友复盘当天行程', '赶去看夜景'];
var datePool = [
    '2026-06-04', '2026-06-03', '2026-06-02', '2026-06-01', // 近期：今天 / 本周 / 近一月
    '2026-05-20', '2026-05-18', '2026-05-10', '2026-04-28',
    '2026-03-19', '2026-02-14', '2026-01-02', '2025-12-25',
    '2025-10-01', '2025-08-15', '2025-07-20', '2025-06-10',
    '2025-05-18', '2025-03-25', '2025-01-20', '2024-12-11',
    '2024-10-05', '2024-09-18'
];

function clampScore(num) {
    return Math.max(0, Math.min(100, Math.round(num)));
}

function calculateCompositeScoreFromDimensions(dimensions) {
    var weighted = weightConfig.reduce(function(sum, item) {
        var value = dimensions[item.id] || 0;
        return sum + value * item.weight / 100;
    }, 0);
    return clampScore(weighted);
}

function getMetricLabel(metric) {
    return scoreMetricLabels[metric] || '美学评分';
}

function getMetricScore(photo, metric) {
    if (!photo) return 0;
    if (metric === 'aesthetics') return photo.aestheticScore;
    if (metric === 'composite') return photo.score;
    if (metric === 'technical') return photo.dimensions.technical;
    if (metric === 'content') return photo.dimensions.content;
    if (metric === 'emotion') return photo.dimensions.emotion;
    if (metric === 'rarity') return photo.dimensions.rarity;
    if (metric === 'uniqueness') return photo.dimensions.uniqueness;
    return photo.aestheticScore;
}

function getBadgeScore(photo) {
    return scoreBadgeMode === 'composite' ? photo.score : photo.aestheticScore;
}

function getBadgeScoreLabelPrefix() {
    return scoreBadgeMode === 'composite' ? '综' : '美';
}

function buildContentDescription(meta) {
    if (meta.isScreenshot) {
        return '该图片判定为截图内容，画面主要为界面信息而非摄影场景。根据规则，截图在美学评分任务中固定为0分。可识别元素包括文字区块、图标与布局层级，建议按信息归档，不参与摄影精选。';
    }
    var text = '照片主体围绕「' + meta.tags.join('、') + '」展开，拍摄地点在' + meta.location + '，时间为' + meta.date + '。画面中可见的内容具有较明确的场景信息：若出现植物，可补充其季节与生态特征；若出现动物，可说明习性与活动环境；若出现食物，可简述食材来源与常见做法。整体描述以事实为主，并保持在300字以内。';
    return text.slice(0, 300);
}

function buildPhotoDiary(meta) {
    if (meta.isScreenshot) {
        return ('这张截图记录了我和' + meta.friend + '在' + meta.city + '行程中的信息节点。时间是' + meta.date + '，本次旅行第' + meta.tripDay + '天。拍摄前我们在整理路线，拍摄后继续推进计划。当下心情偏' + meta.mood + '，更像一次行程备忘。').slice(0, 200);
    }
    var text = '今天是' + meta.date + '，在' + meta.city + '旅行的第' + meta.tripDay + '天，我和' + meta.friend + '一起记录下这张照片。拍摄前我们' + meta.beforeActivity + '，拍摄后' + meta.afterActivity + '。这张照片让我感到' + meta.mood + '，像把当天的节奏、人物关系和城市温度都定格了下来。';
    return text.slice(0, 200);
}

function buildRetentionAdvice(photo) {
    if (photo.score >= 85 && !photo.isDuplicate) {
        return { level: 'keep', text: '高质量且不重复，建议长期保留并加入精选。' };
    }
    if (photo.aestheticScore < scoreTierBounds.t3 || photo.isDuplicate) {
        return { level: 'clean', text: photo.isDuplicate ? '存在重复，建议与原片对比后清理。' : '美学分处于最低档（粉色区间），建议进入待清理列表。' };
    }
    return { level: 'review', text: '质量中等，建议人工复核后再决定是否保留。' };
}

for (var i = 1; i <= 128; i++) {
    var firstTag = tagPool[Math.floor(Math.random() * tagPool.length)];
    var secondTag = tagPool[Math.floor(Math.random() * tagPool.length)];
    var isProDevice = Math.random() < 0.35;
    var isICloud = Math.random() < 0.45;
    var isDuplicate = Math.random() < 0.2;
    var photoDate = datePool[Math.floor(Math.random() * datePool.length)];
    // 拍摄时刻（时:分:秒），mock 随机生成
    var shotHour = Math.floor(Math.random() * 24);
    var shotMin = Math.floor(Math.random() * 60);
    var shotSec = Math.floor(Math.random() * 60);
    var photoTime = String(shotHour).padStart(2, '0') + ':' + String(shotMin).padStart(2, '0') + ':' + String(shotSec).padStart(2, '0');
    var photoLocation = locationPool[Math.floor(Math.random() * locationPool.length)];
    var isScreenshot = Math.random() < 0.10;
    // 低质量非截图照片（构图/画面问题）：约10%，分数落在 15~38 区间
    var isLowQuality = !isScreenshot && Math.random() < 0.10;
    var baseScore = isLowQuality
        ? Math.floor(Math.random() * 24) + 15   // 15~38
        : Math.floor(Math.random() * 35) + 55;  // 55~89
    var aestheticsScore = isScreenshot ? 0 : clampScore(baseScore + (Math.random() * 16 - 8));
    var dimensions = {
        aesthetics: aestheticsScore,
        technical: clampScore(baseScore + (Math.random() * 18 - 9)),
        content: clampScore(baseScore + (Math.random() * 20 - 10)),
        emotion: clampScore(baseScore + (Math.random() * 22 - 11)),
        rarity: clampScore(baseScore + (Math.random() * 24 - 12)),
        uniqueness: clampScore(baseScore + (Math.random() * 26 - 13))
    };
    var score = calculateCompositeScoreFromDimensions(dimensions);
    var duplicateGroup = isDuplicate ? ('DG-' + String(Math.floor((i - 1) / 4) + 1).padStart(2, '0')) : null;
    var friend = friendPool[Math.floor(Math.random() * friendPool.length)];
    var mood = moodPool[Math.floor(Math.random() * moodPool.length)];
    var beforeActivity = beforeActivityPool[Math.floor(Math.random() * beforeActivityPool.length)];
    var afterActivity = afterActivityPool[Math.floor(Math.random() * afterActivityPool.length)];
    var tripDay = Math.floor(Math.random() * 7) + 1;
    var tags = isScreenshot
        ? ['截图', firstTag]
        : isLowQuality
            ? [lowQualityTagPool[Math.floor(Math.random() * lowQualityTagPool.length)], firstTag]
            : [firstTag, secondTag];
    var mediaType;
    if (isScreenshot) {
        mediaType = 'screenshot';
    } else {
        var mr = Math.random();
        if (mr < 0.12) mediaType = 'video';
        else if (mr < 0.22) mediaType = 'live';
        else if (mr < 0.30) mediaType = 'raw';
        else mediaType = 'photo';
    }
    var people = [];
    if (!isScreenshot && Math.random() < 0.55) {
        var peopleCount = Math.random() < 0.5 ? 1 : 2;
        for (var pp = 0; pp < peopleCount; pp++) {
            var personName = peoplePool[Math.floor(Math.random() * peoplePool.length)];
            if (people.indexOf(personName) === -1) people.push(personName);
        }
    }
    var deviceType;
    if (isScreenshot) {
        deviceType = '手机';
    } else {
        var dr = Math.random();
        if (dr < 0.45) deviceType = '手机';
        else if (dr < 0.65) deviceType = '单反相机';
        else if (dr < 0.80) deviceType = '运动相机';
        else if (dr < 0.92) deviceType = '无人机';
        else deviceType = 'Pocket';
    }
    // 生成模拟文件名
    var fnNum = String(10000 + i).slice(1);
    var fnDate = photoDate.replace(/-/g, '');
    var filename;
    if (isScreenshot) {
        filename = 'Screenshot_' + fnDate + '_' + fnNum + '.PNG';
    } else if (mediaType === 'video') {
        filename = 'VID_' + fnDate + '_' + fnNum + '.MP4';
    } else if (mediaType === 'raw') {
        filename = deviceType === '单反相机' ? ('DSC_' + fnNum + '.ARW') : ('RAW_' + fnNum + '.DNG');
    } else if (deviceType === '单反相机') {
        filename = 'DSC_' + fnNum + '.JPG';
    } else if (deviceType === '运动相机') {
        filename = 'GOPR' + fnNum + '.JPG';
    } else if (deviceType === '无人机') {
        filename = 'DJI_' + fnNum + '.JPG';
    } else {
        filename = 'IMG_' + fnNum + '.HEIC';
    }
    var contentDescription = buildContentDescription({
        isScreenshot: isScreenshot,
        tags: tags,
        location: photoLocation,
        date: photoDate
    });
    var photoDiary = buildPhotoDiary({
        isScreenshot: isScreenshot,
        friend: friend,
        city: photoLocation,
        date: photoDate,
        tripDay: tripDay,
        beforeActivity: beforeActivity,
        afterActivity: afterActivity,
        mood: mood
    });
    photos.push({
        id: i,
        filename: filename,
        time: photoTime,
        url: 'https://picsum.photos/seed/' + i + '/400/400',
        score: score,
        comprehensiveScore: score,
        aestheticScore: aestheticsScore,
        isScreenshot: isScreenshot,
        date: photoDate,
        location: photoLocation,
        tags: tags,
        isProDevice: isProDevice,
        deviceType: deviceType,
        isProEdited: Math.random() < 0.25,
        isDuplicate: isDuplicate,
        duplicateGroup: duplicateGroup,
        duplicateRank: isDuplicate ? (Math.floor(Math.random() * 3) + 1) : null,
        isNewMonth: Math.random() < 0.2,
        isICloud: isICloud,
        isFavorite: Math.random() < 0.3,
        isInTrash: Math.random() < 0.05,
        mediaType: mediaType,
        people: people,
        dimensions: dimensions,
        contentDescription: contentDescription,
        photoDiary: photoDiary
    });
    photos[i - 1].retentionAdvice = buildRetentionAdvice(photos[i - 1]);
}

// ========== 初始化 ==========
function init() {
    initTheme();
    initNavigation();
    initSidebarExtraTags();
    initSidebarTagSearch();
    initTimelineYearOptions();
    renderPhotos();
    renderReports();
    initSidebarCollapse();
    updateAnalysisProgressUI();
    updateBadgeScoreModeDisplay(); // 同时初始化排序选项文案
    updateModelButtons();
    renderScoreTierConfig();
    syncSsfDimLabel();
    updateSsfSliderTrack();
    renderSidebarFilters();
    updateAnalysisProgressNumbers();
    startAnalysisSimulation();
    applyGridSize(); // 初始化网格尺寸
    // 初始化侧边栏展开状态（默认照片页展开）
    var group = document.getElementById('sidebarGroup');
    if (group) group.classList.toggle('expanded', sidebarVisible);
}

// ========== 侧边栏折叠 ==========
var sidebarVisible = true;

function initSidebarCollapse() {
    // tab 的点击/悬浮已在 HTML 声明，这里仅初始化滚动行为
    initScrollSidebarBehavior();
}

/** 公开切换：用户手动触发 */
function toggleSidebar() {
    setSidebarVisible(!sidebarVisible);
    // 手动操作后重置"被滚动隐藏"状态
    _scrollHiddenByScroll = false;
    _preScrollSidebarVisible = sidebarVisible;
}

/** 相机图标点击：根据当前状态切换侧边栏（按钮本身无视觉动画） */
function toggleSidebarInstant() {
    toggleSidebar();
}

/** 统一状态设置（避免重复操作）*/
function setSidebarVisible(show) {
    if (sidebarVisible === show) return;
    sidebarVisible = show;
    var group = document.getElementById('sidebarGroup');
    if (group) group.classList.toggle('expanded', show);
    var tabLeft = document.getElementById('sidebarTabLeft');
    if (tabLeft) tabLeft.title = show ? '折叠侧边栏' : '展开侧边栏';
}

// ========== 滚动自动隐藏 ==========
function initScrollSidebarBehavior() {
    var mainContent = document.querySelector('.main-content');
    if (!mainContent) return;
    // 以"侧边栏可见时的起始滚动位置"为基准，累计滚动超过阈值即隐藏。
    // 旧实现用单次 scroll 事件的 delta 判断，平滑滚动每次仅 1-3px，几乎无法达到 10px → 不灵敏。
    var SCROLL_HIDE_THRESHOLD = 10;
    var baseScrollTop = mainContent.scrollTop;

    mainContent.addEventListener('scroll', function() {
        var scrollTop = mainContent.scrollTop;

        // 侧边栏可见：累计相对基准的位移超过阈值即隐藏
        if (sidebarVisible) {
            if (Math.abs(scrollTop - baseScrollTop) >= SCROLL_HIDE_THRESHOLD) {
                _preScrollSidebarVisible = true;
                _scrollHiddenByScroll = true;
                setSidebarVisible(false);
            }
        } else {
            // 隐藏期间持续刷新基准，恢复后重新累计
            baseScrollTop = scrollTop;
        }

        // 滚动停止检测（150ms 防抖）
        clearTimeout(_scrollDebounceTimer);
        _scrollDebounceTimer = setTimeout(function() {
            baseScrollTop = mainContent.scrollTop; // 停止后重置基准
            // 停止后：若是被滚动隐藏的，延迟恢复
            if (_scrollHiddenByScroll && _preScrollSidebarVisible && !sidebarVisible) {
                setTimeout(function() {
                    if (_scrollHiddenByScroll && !sidebarVisible) {
                        _scrollHiddenByScroll = false;
                        setSidebarVisible(true);
                        baseScrollTop = mainContent.scrollTop;
                    }
                }, 500);
            }
        }, 150);
    }, { passive: true });
}

// ========== 悬浮触发 ==========
// 无论展开还是折叠，悬停 n 秒均自动切换到相反状态
function startSidebarHoverTimer() {
    if (!sidebarHoverEnabled) return;
    var delay = sidebarHoverDelay * 1000;
    var targetVisible = !sidebarVisible; // 切换到相反状态
    if (delay <= 0) {
        setSidebarVisible(targetVisible);
        if (targetVisible) _scrollHiddenByScroll = false;
        return;
    }
    _sidebarHoverTimer = setTimeout(function() {
        // 再次确认状态未被手动改变
        if (sidebarVisible !== targetVisible) {
            setSidebarVisible(targetVisible);
            if (targetVisible) _scrollHiddenByScroll = false;
        }
    }, delay);
}

function cancelSidebarHoverTimer() {
    clearTimeout(_sidebarHoverTimer);
    _sidebarHoverTimer = null;
}

// ========== 悬浮触发设置 ==========
function onHoverEnabledChange() {
    var checkbox = document.getElementById('hoverTriggerEnabled');
    sidebarHoverEnabled = checkbox ? checkbox.checked : true;
}

// ========== 底部导航显示开关 ==========
var scoreBadgeVisible = true; // 由照片页 美学/综合 分段按钮控制：再次点击当前模式即隐藏

// ========== 照片源：本地目录管理 ==========
var localDirs = []; // [{ name, fileCount, photos }]
var localPhotoIdBase = 10000; // 与 mock 数据 id 区分
var localFileKeys = new Set(); // 去重：dirName/filename
var localDirPanelOpen = false;

function pickLocalDirectory() {
    if (localDirs.length >= 20) { showToast('最多支持 20 个本地目录'); return; }
    document.getElementById('dirPicker').value = '';
    document.getElementById('dirPicker').click();
}

function toggleLocalDirPanel() {
    localDirPanelOpen = !localDirPanelOpen;
    var list = document.getElementById('localDirList');
    var btn = document.getElementById('manageDirBtn');
    if (list) list.style.display = localDirPanelOpen ? '' : 'none';
    if (btn) {
        btn.innerHTML = localDirPanelOpen
            ? '<i class="fas fa-chevron-up"></i> 收起'
            : '<i class="fas fa-list"></i> 管理目录';
    }
}

// 随机为导入照片生成 demo 分数/标签/描述
function mockAnalyzeImportedPhoto(fileName) {
    var isVideo = /\.(mp4|mov|m4v|avi|mkv|webm)$/i.test(fileName);
    var baseScore = Math.floor(Math.random() * 45) + 42; // 42~86
    var ae = clampScore(baseScore + (Math.random() * 16 - 8));
    var dims = {
        aesthetics: ae,
        technical: clampScore(baseScore + (Math.random() * 14 - 7)),
        content:   clampScore(baseScore + (Math.random() * 18 - 9)),
        emotion:   clampScore(baseScore + (Math.random() * 20 - 10)),
        rarity:    clampScore(baseScore + (Math.random() * 22 - 11)),
        uniqueness:clampScore(baseScore + (Math.random() * 24 - 12))
    };
    var tag1 = tagPool[Math.floor(Math.random() * tagPool.length)];
    var tag2 = tagPool[Math.floor(Math.random() * tagPool.length)];
    var loc = locationPool[Math.floor(Math.random() * locationPool.length)];
    return {
        score: calculateCompositeScoreFromDimensions(dims),
        aestheticScore: ae,
        dimensions: dims,
        tags: [tag1, tag2],
        location: loc,
        isAnalyzed: true,
        deviceType: '本地导入'
    };
}

function onDirSelected(input) {
    var allFiles = Array.from(input.files).filter(function(f) {
        return /\.(jpe?g|png|gif|webp|heic|heif|tiff?|bmp|raw|arw|cr2|nef|orf|dng|mp4|mov|m4v|avi|mkv|webm)$/i.test(f.name);
    });
    if (!allFiles.length) { showToast('未找到照片或视频文件'); return; }

    // 取根目录名（webkitRelativePath = "dirname/file.jpg"）
    var dirName = allFiles[0].webkitRelativePath.split('/')[0] || '本地目录';
    if (localDirs.some(function(d) { return d.name === dirName; })) {
        showToast('该目录已添加：' + dirName); return;
    }
    if (localDirs.length >= 20) { showToast('最多支持 20 个本地目录'); return; }

    // 去重过滤（路径+文件名作为唯一键）
    var skipped = 0;
    var files = allFiles.filter(function(f) {
        var key = (f.webkitRelativePath || (dirName + '/' + f.name));
        if (localFileKeys.has(key)) { skipped++; return false; }
        localFileKeys.add(key);
        return true;
    });
    if (!files.length) { showToast('所有文件已存在，无新增内容'); return; }

    var todayStr = new Date().toISOString().slice(0, 10);
    var now = new Date();
    var nowTime = String(now.getHours()).padStart(2, '0') + ':' + String(now.getMinutes()).padStart(2, '0') + ':' + String(now.getSeconds()).padStart(2, '0');
    var dirPhotos = files.map(function(f) {
        var mock = mockAnalyzeImportedPhoto(f.name);
        // Demo 中默认使用今天日期，方便在「今天/本周/近一月」快捷筛选中看到效果
        // 正式版应读取照片 EXIF 中的 DateTimeOriginal 字段
        return Object.assign({
            id: localPhotoIdBase++,
            url: URL.createObjectURL(f),
            name: f.name,
            filename: f.name,
            time: nowTime,
            size: f.size,
            mediaType: /\.(mp4|mov|m4v|avi|mkv|webm)$/i.test(f.name) ? 'video' : 'photo',
            date: todayStr,
            isScreenshot: false,
            isProDevice: false,
            isInTrash: false,
            isICloud: false,
            isDuplicate: false,
            duplicateGroup: null,
            isFavorite: false,
            people: []
        }, mock);
    });

    localDirs.push({ name: dirName, fileCount: files.length, photos: dirPhotos });
    photos = photos.concat(dirPhotos);
    renderLocalDirList();
    renderPhotos();
    var msg = '已导入「' + dirName + '」' + files.length + ' 个文件';
    if (skipped > 0) msg += '（跳过重复 ' + skipped + ' 个）';
    showToast(msg);
}

function removeLocalDir(dirName) {
    var dir = localDirs.find(function(d) { return d.name === dirName; });
    if (!dir) return;
    // 释放 Object URL 并清除去重键
    dir.photos.forEach(function(p) {
        if (p.url && p.url.startsWith('blob:')) URL.revokeObjectURL(p.url);
        var key = dirName + '/' + p.name;
        localFileKeys.delete(key);
    });
    var removedIds = new Set(dir.photos.map(function(p) { return p.id; }));
    localDirs = localDirs.filter(function(d) { return d.name !== dirName; });
    photos = photos.filter(function(p) { return !removedIds.has(p.id); });
    if (!localDirs.length) localDirPanelOpen = false;
    renderLocalDirList();
    renderPhotos();
    showToast('已移除目录：' + dirName);
}

function renderLocalDirList() {
    var list = document.getElementById('localDirList');
    var desc = document.getElementById('localDirDesc');
    var addBtn = document.getElementById('addDirBtn');
    var manageBtn = document.getElementById('manageDirBtn');
    if (!list) return;
    var total = localDirs.reduce(function(s, d) { return s + d.fileCount; }, 0);
    if (addBtn) addBtn.disabled = localDirs.length >= 20;
    if (manageBtn) {
        manageBtn.style.display = localDirs.length ? '' : 'none';
        manageBtn.innerHTML = localDirPanelOpen
            ? '<i class="fas fa-chevron-up"></i> 收起'
            : '<i class="fas fa-list"></i> 管理目录 (' + localDirs.length + ')';
    }
    if (desc) desc.textContent = localDirs.length
        ? '已添加 ' + localDirs.length + ' 个目录，共 ' + total + ' 个文件'
        : '未添加目录 · 选择后扫描并导入目录下全部照片/视频';
    list.style.display = (localDirPanelOpen && localDirs.length) ? '' : 'none';
    list.innerHTML = localDirs.map(function(d) {
        return '<div class="local-dir-item">'
            + '<div class="local-dir-info"><i class="fas fa-folder"></i>'
            + '<span class="local-dir-name">' + d.name + '</span>'
            + '<span class="local-dir-count">' + d.fileCount + ' 个文件</span></div>'
            + '<button class="local-dir-remove" onclick="removeLocalDir(\'' + d.name.replace(/'/g, "\\'") + '\')" title="移除此目录"><i class="fas fa-times"></i></button>'
            + '</div>';
    }).join('');
}

var bottomNavVisible = true;
function onBottomNavToggle() {
    var checkbox = document.getElementById('bottomNavEnabled');
    bottomNavVisible = checkbox ? checkbox.checked : true;
    var nav = document.querySelector('.bottom-nav');
    if (nav) nav.style.display = bottomNavVisible ? '' : 'none';
    var main = document.querySelector('main');
    if (main) main.style.paddingBottom = bottomNavVisible ? '' : '20px';
    showToast(bottomNavVisible ? '底部功能栏已显示' : '底部功能栏已隐藏');
}

function initSidebarTagSearch() {
    var input = document.getElementById('tagSearch');
    if (!input) return;
    input.addEventListener('input', function() {
        var keyword = input.value.trim().toLowerCase();
        document.querySelectorAll('#tagCloud .sidebar-tag-item').forEach(function(item) {
            var tag = item.dataset.tag || '';
            if (tag === 'all') return;
            var visible = tag.toLowerCase().indexOf(keyword) !== -1;
            if (item.classList.contains('extra-tag') && !areExtraTagsVisible && !keyword) {
                visible = false;
            }
            item.style.display = visible ? '' : 'none';
        });
    });
}

function initSidebarExtraTags() {
    var tagCloud = document.getElementById('tagCloud');
    if (!tagCloud) return;
    if (tagCloud.querySelector('.sidebar-tag-item.extra-tag')) return;
    // 扩展标签插在「更多」按钮之前，使展开后更多按钮仍在最末
    var moreBtn = document.getElementById('sidebarMoreBtn');
    hiddenSidebarTags.forEach(function(item) {
        var el = document.createElement('span');
        el.className = 'sidebar-tag-item extra-tag';
        el.dataset.tag = item.tag;
        el.style.display = 'none';
        el.innerHTML = '<i class="fas ' + item.icon + '"></i> ' + item.tag + ' <span class="count">' + item.count + '</span>';
        el.onclick = function() { toggleSidebarTag(el); };
        if (moreBtn) tagCloud.insertBefore(el, moreBtn);
        else tagCloud.appendChild(el);
    });
}

function toggleSidebarTag(el) {
    var tag = el.dataset.tag;
    if (!tag) return;
    // 单选：再次点击同一标签 = 清空
    if (activeSidebarTag === tag) {
        activeSidebarTag = 'all';
    } else {
        activeSidebarTag = tag;
    }
    document.querySelectorAll('#tagCloud .sidebar-tag-item').forEach(function(item) {
        item.classList.toggle('active', item.dataset.tag === activeSidebarTag);
    });
    var clearBtn = document.getElementById('sidebarTagClear');
    if (clearBtn) clearBtn.style.display = activeSidebarTag !== 'all' ? '' : 'none';
    if (currentPage !== 'photos') navigateToPage('photos');
    findAppliedToWall = false;
    updateFindBanner();
    renderPhotos();
    updateMultiSelectToolbar();
    if (activeSidebarTag === 'all') showToast('已清空标签筛选');
    else showToast('已切换标签：' + activeSidebarTag);
}
function clearSidebarTag() {
    activeSidebarTag = 'all';
    document.querySelectorAll('#tagCloud .sidebar-tag-item').forEach(function(item) {
        item.classList.remove('active');
    });
    var clearBtn = document.getElementById('sidebarTagClear');
    if (clearBtn) clearBtn.style.display = 'none';
    renderPhotos();
    showToast('已清空标签筛选');
}

function applyQuickFilter(type) {
    // 单选：再次点击同一项则清空
    activeQuickFilter = (activeQuickFilter === type) ? 'none' : type;
    activeSidebarTag = 'all';
    document.querySelectorAll('#tagCloud .sidebar-tag-item').forEach(function(item) {
        item.classList.remove('active');
    });
    document.querySelectorAll('.sidebar-item[data-quick]').forEach(function(item) {
        item.classList.toggle('active', item.dataset.quick === activeQuickFilter);
    });
    var clearBtn = document.getElementById('sidebarStatusClear');
    if (clearBtn) clearBtn.style.display = activeQuickFilter !== 'none' ? '' : 'none';
    findAppliedToWall = false;
    if (currentPage !== 'photos') navigateToPage('photos');
    selectedPhotos.clear();
    updateFindBanner();
    renderPhotos();
    updateMultiSelectToolbar();
    var textMap = {
        favorite: '我的收藏',
        highScore: '高分照片',
        waste: '废片篓',
        duplicate: '重复/相似',
        trash: '废片篓'
    };
    if (activeQuickFilter === 'none') showToast('已清空状态筛选');
    else showToast('已应用状态筛选：' + (textMap[activeQuickFilter] || ''));
}
function clearQuickFilter() {
    applyQuickFilter(activeQuickFilter); // 再次点击当前激活项 = 切回 none
}

// ========== 侧边栏迷你评分滑块筛选 ==========
var ssfOp = 'gt';    // 'gt' | 'lt'
var ssfValue = 0;    // 0 = 不过滤

var SSF_TRACK_COLOR = 'rgba(94,92,230,0.85)';
var SSF_TRACK_EMPTY = 'rgba(255,255,255,0.12)';

function updateSsfSliderTrack() {
    var slider = document.getElementById('ssfSlider');
    if (!slider) return;
    var pct = ssfValue; // min=0 max=100, so pct === value directly
    var left, right;
    if (ssfOp === 'gt') {
        // 大于：右边（高分区）染色
        left  = SSF_TRACK_EMPTY;
        right = SSF_TRACK_COLOR;
        slider.style.background = 'linear-gradient(to right, ' + left + ' ' + pct + '%, ' + right + ' ' + pct + '%)';
    } else {
        // 小于：左边（低分区）染色
        left  = SSF_TRACK_COLOR;
        right = SSF_TRACK_EMPTY;
        slider.style.background = 'linear-gradient(to right, ' + left + ' ' + pct + '%, ' + right + ' ' + pct + '%)';
    }
}

function setSsfOp(op) {
    ssfOp = op;
    document.getElementById('ssfOpGt').classList.toggle('active', op === 'gt');
    document.getElementById('ssfOpLt').classList.toggle('active', op === 'lt');
    updateSsfSliderTrack();
    renderPhotos();
}

function onSsfSlider(val) {
    ssfValue = parseInt(val, 10);
    document.getElementById('ssfValueDisplay').textContent = ssfValue;
    var resetBtn = document.getElementById('ssfResetBtn');
    if (resetBtn) resetBtn.style.opacity = ssfValue > 0 ? '1' : '0.3';
    updateSsfSliderTrack();
    renderPhotos();
}

function resetSsf() {
    // lt 模式"不过滤"语义是 100（小于100即全部），gt 模式是 0（大于0即全部）
    ssfValue = (ssfOp === 'lt') ? 100 : 0;
    var slider = document.getElementById('ssfSlider');
    if (slider) slider.value = ssfValue;
    document.getElementById('ssfValueDisplay').textContent = ssfValue;
    var resetBtn = document.getElementById('ssfResetBtn');
    if (resetBtn) resetBtn.style.opacity = '0.3';
    updateSsfSliderTrack();
    renderPhotos();
}

// 评分快捷：高分照片 / 低分照片 — 同步滑块与操作符
function setSsfQuickScore(type) {
    var targetOp, targetVal;
    if (type === 'highScore') {
        targetOp  = 'gt';
        targetVal = scoreTierBounds.t1;  // ≥ 最高档下限（默认 80）
    } else if (type === 'lowScore') {
        targetOp  = 'lt';
        targetVal = scoreTierBounds.t3;  // < 最低档上限（默认 40）
    } else { return; }
    setSsfOp(targetOp);
    ssfValue = targetVal;
    var slider = document.getElementById('ssfSlider');
    if (slider) slider.value = targetVal;
    document.getElementById('ssfValueDisplay').textContent = targetVal;
    var resetBtn = document.getElementById('ssfResetBtn');
    if (resetBtn) resetBtn.style.opacity = '1';
    updateSsfSliderTrack();
    renderPhotos();
}

// 根据当前 scoreBadgeMode 更新维度标签与图标
function syncSsfDimLabel() {
    var label = document.getElementById('ssfDimLabel');
    var icon  = document.getElementById('ssfDimIcon');
    var isComposite = scoreBadgeMode === 'composite';
    if (label) label.textContent = isComposite ? '综合' : '美学';
    if (icon) icon.className = 'fas ' + (isComposite ? 'fa-chart-line' : 'fa-camera-retro') + ' ssf-dim-icon';
}

// ========== AI 分析进度模拟 ==========
var analysisTotal    = 45678;
var analysisAnalyzed = 12345;
var analysisTimer    = null;

function startAnalysisSimulation() {
    if (analysisTimer) return;
    analysisTimer = setInterval(function() {
        if (analysisState !== 'running') return;
        var batch = Math.floor(Math.random() * 51) + 100; // 100~150 张
        analysisAnalyzed = Math.min(analysisAnalyzed + batch, analysisTotal);
        updateAnalysisProgressNumbers();
        if (analysisAnalyzed >= analysisTotal) {
            analysisState = 'done';
            clearInterval(analysisTimer);
            analysisTimer = null;
            updateAnalysisProgressUI();
        }
    }, 5000);
}

function updateAnalysisProgressNumbers() {
    var fill   = document.getElementById('aiProgressFill');
    var nums   = document.getElementById('aiProgressNumbers');
    var pct    = document.getElementById('aiProgressPct');
    var ratio  = analysisTotal > 0 ? analysisAnalyzed / analysisTotal : 0;
    var pctStr = (ratio * 100).toFixed(1) + '%';
    if (fill) fill.style.width = pctStr;
    if (nums) nums.textContent = analysisAnalyzed.toLocaleString() + ' / ' + analysisTotal.toLocaleString();
    if (pct)  pct.textContent  = pctStr;
    // 顶部精简版
    var miniFill = document.getElementById('aiMiniFill');
    var miniPct  = document.getElementById('aiMiniPct');
    if (miniFill) miniFill.style.width = pctStr;
    if (miniPct)  miniPct.textContent  = pctStr;
}

function updateAnalysisProgressUI() {
    var card = document.getElementById('aiProgressCard');
    var statusEl = document.getElementById('aiProgressStatus');
    var stateIcon = document.getElementById('aiProgressStateIcon');
    var pauseIcon = document.getElementById('aiPauseBtnIcon');
    var pauseText = document.getElementById('aiPauseBtnText');
    if (!card || !statusEl || !stateIcon || !pauseIcon || !pauseText) return;
    var widget    = document.getElementById('aiProgressWidget');
    var miniIcon  = document.getElementById('aiMiniStateIcon');
    var miniPause = document.getElementById('aiMiniPauseIcon');
    function syncMini(stateCls, iconCls, pauseCls) {
        if (widget) {
            widget.classList.remove('state-running', 'state-paused', 'state-stopped', 'state-done');
            widget.classList.add(stateCls);
        }
        if (miniIcon)  miniIcon.className  = iconCls + ' ai-mini-state';
        if (miniPause) miniPause.className = pauseCls;
    }

    card.classList.remove('state-running', 'state-paused', 'state-stopped', 'state-done');
    var ctrlBtn = card.querySelector('.ai-control-btn');
    if (ctrlBtn) ctrlBtn.style.display = '';
    if (analysisState === 'paused') {
        card.classList.add('state-paused');
        statusEl.textContent = '已暂停';
        stateIcon.className = 'fas fa-pause-circle';
        pauseIcon.className = 'fas fa-play';
        pauseText.textContent = '继续';
        syncMini('state-paused', 'fas fa-pause-circle', 'fas fa-play');
        return;
    }
    if (analysisState === 'stopped') {
        card.classList.add('state-stopped');
        statusEl.textContent = '已停止';
        stateIcon.className = 'fas fa-stop-circle';
        pauseIcon.className = 'fas fa-play';
        pauseText.textContent = '开始';
        syncMini('state-stopped', 'fas fa-stop-circle', 'fas fa-play');
        return;
    }
    if (analysisState === 'done') {
        card.classList.add('state-done');
        statusEl.textContent = '已完成';
        stateIcon.className = 'fas fa-check-circle';
        if (ctrlBtn) ctrlBtn.style.display = 'none';
        syncMini('state-done', 'fas fa-check-circle', 'fas fa-pause');
        return;
    }
    card.classList.add('state-running');
    statusEl.textContent = '分析中';
    stateIcon.className = 'fas fa-spinner fa-spin';
    pauseIcon.className = 'fas fa-pause';
    pauseText.textContent = '暂停';
    syncMini('state-running', 'fas fa-spinner fa-spin', 'fas fa-pause');
}

function startAnalysis() {
    if (analysisState === 'done') return;
    analysisState = 'running';
    updateAnalysisProgressUI();
    startAnalysisSimulation();
    showToast('AI 分析已启动');
}

function togglePauseAnalysis() {
    if (analysisState === 'running') {
        analysisState = 'paused';
        updateAnalysisProgressUI();
        showToast('分析已暂停');
        return;
    }
    if (analysisState === 'paused' || analysisState === 'stopped') {
        analysisState = 'running';
        updateAnalysisProgressUI();
        startAnalysisSimulation();
        showToast('分析继续进行');
    }
}

function stopAnalysis() {
    analysisState = 'stopped';
    if (analysisTimer) { clearInterval(analysisTimer); analysisTimer = null; }
    updateAnalysisProgressUI();
    showToast('分析已停止');
}

// ========== 导航 ==========
function initNavigation() {
    document.querySelectorAll('.nav-tab').forEach(function(tab) {
        tab.addEventListener('click', function() {
            var page = tab.dataset.page;
            navigateToPage(page);
        });
    });
    document.querySelectorAll('.nav-item').forEach(function(item) {
        if (!item.dataset.page) return; // 查找入口无 data-page，由 onclick 唤起浮层
        item.addEventListener('click', function() {
            var page = item.dataset.page;
            navigateToPage(page);
        });
    });
}

function navigateToPage(page) {
    currentPage = page;
    document.querySelectorAll('.nav-tab').forEach(function(tab) {
        tab.classList.toggle('active', tab.dataset.page === page);
    });
    document.querySelectorAll('.nav-item').forEach(function(item) {
        item.classList.toggle('active', item.dataset.page === page);
    });
    document.querySelectorAll('.page').forEach(function(p) {
        p.classList.toggle('active', p.id === 'page-' + page);
    });

    // 渲染页面内容
    if (page === 'timeline') renderTimeline();
    if (page === 'reports') renderReports();
    if (page === 'settings') renderSettings();
    if (page === 'event') applyGridSize();

    // 年份快速索引：仅在时间线页显示
    var yearIndex = document.getElementById('tlYearIndex');
    if (yearIndex) yearIndex.classList.toggle('visible', page === 'timeline');

    // 侧边栏组（仅在照片页显示；overlay 模式，不影响主内容宽度）
    var sidebarGroup = document.getElementById('sidebarGroup');
    if (sidebarGroup) {
        sidebarGroup.style.display = (page === 'photos') ? '' : 'none';
    }
}

function getVisiblePhotos() {
    var list = getBasePhotosForFilter();
    if (findAppliedToWall) {
        list = computeFindFilter(list);
    }
    if (currentSortMode === 'scoreDesc') {
        list.sort(function(a, b) { return getBadgeScore(b) - getBadgeScore(a); });
    } else if (currentSortMode === 'scoreAsc') {
        list.sort(function(a, b) { return getBadgeScore(a) - getBadgeScore(b); });
    } else if (currentSortMode === 'dateAsc') {
        list.sort(function(a, b) { return a.date.localeCompare(b.date); });
    } else {
        list.sort(function(a, b) { return b.date.localeCompare(a.date); });
    }
    return list;
}

function getBasePhotosForFilter() {
    var list = photos.slice();
    // 类型快捷筛选（单选）
    if (sidebarMediaType) {
        list = list.filter(function(photo) { return photo.mediaType === sidebarMediaType; });
    }
    if (activeSidebarTag !== 'all') {
        list = list.filter(function(photo) {
            return photo.tags.indexOf(activeSidebarTag) !== -1;
        });
    }
    // 迷你评分滑块筛选（gt: value>0 才生效；lt: value<100 才生效）
    var ssfActive = (ssfOp === 'gt' && ssfValue > 0) || (ssfOp === 'lt' && ssfValue < 100);
    if (ssfActive) {
        list = list.filter(function(photo) {
            var score = scoreBadgeMode === 'composite' ? photo.score : photo.aestheticScore;
            return ssfOp === 'gt' ? score >= ssfValue : score <= ssfValue;
        });
    }
    if (activeQuickFilter === 'favorite') {
        list = list.filter(function(photo) { return photo.isFavorite; });
    } else if (activeQuickFilter === 'waste') {
        // 废片篓 = 美学分落在最低档（粉色区间，低于 t3）
        // t3 由用户在「分数区间配色」中配置，默认 40；与重复照片概念独立
        list = list.filter(function(photo) { return photo.aestheticScore < scoreTierBounds.t3; });
    } else if (activeQuickFilter === 'highScore') {
        // 高分照片 = 美学分处于最高档（蓝色区间，>= t1），与废片篓对称
        list = list.filter(function(photo) { return photo.aestheticScore >= scoreTierBounds.t1; });
    } else if (activeQuickFilter === 'duplicate') {
        list = list.filter(function(photo) { return photo.isDuplicate; });
    } else if (activeQuickFilter === 'trash') {
        list = list.filter(function(photo) { return !!photo.isInTrash; });
    }
    // 时间快捷筛选（单选）
    if (sidebarTimeKey) {
        var range = timeRangeFor(sidebarTimeKey);
        if (range) {
            list = list.filter(function(photo) {
                return photo.date >= range.start && photo.date <= range.end;
            });
        }
    }
    // 设备与来源快捷筛选（单选）
    if (sidebarSource) {
        var srcDef = sourceDefs.filter(function(d) { return d.key === sidebarSource; })[0];
        if (srcDef) {
            list = list.filter(function(photo) {
                return srcDef.kind === 'flag' ? !!photo[srcDef.key] : photo.deviceType === sidebarSource;
            });
        }
    }
    // 人物快捷筛选（多选 OR）
    if (sidebarPeople.length) {
        list = list.filter(function(photo) {
            return (photo.people || []).some(function(p) { return sidebarPeople.indexOf(p) !== -1; });
        });
    }
    return list;
}

// 统一查找过滤：自然语言 query 与所有属性芯片以 AND 叠加
function computeFindFilter(list) {
    var s = findState;
    return list.filter(function(photo) {
        if (s.mediaTypes.length && s.mediaTypes.indexOf(photo.mediaType) === -1) return false;
        if (s.devices.length && s.devices.indexOf(photo.deviceType) === -1) return false;
        if (s.isFavorite && !photo.isFavorite) return false;
        if (s.locations.length && s.locations.indexOf(photo.location) === -1) return false;
        if (s.people.length) {
            var hitPerson = (photo.people || []).some(function(p) { return s.people.indexOf(p) !== -1; });
            if (!hitPerson) return false;
        }
        if (s.tags.length) {
            var hitTag = s.tags.some(function(t) { return photo.tags.indexOf(t) !== -1; });
            if (!hitTag) return false;
        }
        if (s.isProDevice && !photo.isProDevice) return false;
        if (s.isProEdited && !photo.isProEdited) return false;
        if (s.isDuplicate && !photo.isDuplicate) return false;
        if (s.isNewMonth && !photo.isNewMonth) return false;
        if (s.isICloud && !photo.isICloud) return false;
        if (s.isInTrash && !photo.isInTrash) return false;
        if (isScoreCondActive(s.scoreCond)) {
            var c = s.scoreCond;
            var sc = getMetricScore(photo, c.metric);
            if (c.op === 'gt' && !(sc > c.value)) return false;
            if (c.op === 'lt' && !(sc < c.value)) return false;
        }
        if (s.dateRange) {
            if (s.dateRange.holidays) {
                var month = new Date(photo.date).getMonth() + 1;
                if ([1, 5, 10].indexOf(month) === -1) return false;
            } else if (s.dateRange.start && s.dateRange.end) {
                if (photo.date < s.dateRange.start || photo.date > s.dateRange.end) return false;
            }
        }
        if (s.query && !matchesQuery(photo, s.query)) return false;
        return true;
    });
}

// ========== 照片网格 ==========
// 四档配色分界：蓝 >= t1 > 绿 >= t2 > 黄 >= t3 > 粉；区间互斥且覆盖 0-100
function getScoreClass(score) {
    if (score >= scoreTierBounds.t1) return 'tier-blue';
    if (score >= scoreTierBounds.t2) return 'tier-green';
    if (score >= scoreTierBounds.t3) return 'tier-yellow';
    return 'tier-pink';
}

function renderPhotos() {
    var grid = document.getElementById('photoGrid');
    if (!grid) return;
    // 废片篓工具栏：仅当当前处于废片篓快捷筛选时显示
    var trashBanner = document.getElementById('trashBanner');
    if (trashBanner) {
        var inTrashView = activeQuickFilter === 'trash';
        trashBanner.classList.toggle('show', inTrashView);
        if (inTrashView) {
            var cnt = document.getElementById('trashBannerCount');
            if (cnt) cnt.textContent = getTrashPhotos().length;
        }
    }
    var visiblePhotos = getVisiblePhotos();
    if (visiblePhotos.length === 0) {
        grid.innerHTML = '<div class="timeline-empty" style="grid-column: 1 / -1;"><i class="fas fa-images"></i><h3>没有符合条件的照片</h3><p>尝试调整筛选条件或清空快捷筛选</p></div>';
        updatePhotoCount(0);
        return;
    }
    grid.innerHTML = visiblePhotos.map(function(photo) {
        var badgeScore = getBadgeScore(photo);
        var scoreClass = getScoreClass(badgeScore);
        var icon = scoreBadgeMode === 'composite' ? 'fa-chart-line' : 'fa-camera-retro';
        return '<div class="photo-card' + (selectedPhotos.has(photo.id) ? ' selected' : '') + '" data-id="' + photo.id + '" onclick="openPhotoDetail(' + photo.id + ')"><img src="' + photo.url + '" alt="照片" loading="lazy"><div class="photo-score ' + scoreClass + '"><i class="fas ' + icon + '"></i> ' + getBadgeScoreLabelPrefix() + ' ' + badgeScore + '</div><div class="photo-checkbox" onclick="togglePhotoSelection(event, ' + photo.id + ')"><i class="fas fa-check"></i></div></div>';
    }).join('');
    updatePhotoCount(visiblePhotos.length);
    updateSidebarCounts();
    // 渲染后重新应用尺寸（CSS var 在 grid 元素上，DOM 重建后无需重新设置，但 gap 需要）
    applyGridSize();
}

function updateSidebarCounts() {
    var all = photos; // 以全量数据为基准统计（不受当前筛选影响）
    // --- 标签云：全部 + 各标签 ---
    var tagCountMap = {};
    all.forEach(function(p) {
        (p.tags || []).forEach(function(t) {
            tagCountMap[t] = (tagCountMap[t] || 0) + 1;
        });
    });
    document.querySelectorAll('#tagCloud .sidebar-tag-item').forEach(function(el) {
        var tag = el.dataset.tag;
        var countEl = el.querySelector('.count');
        if (!countEl) return;
        if (tag === 'all') {
            countEl.textContent = all.length;
        } else if (tagCountMap[tag] !== undefined) {
            countEl.textContent = tagCountMap[tag];
        }
    });
    // --- 快捷操作：收藏 / 废片 / 高分 ---
    var favoriteCount  = all.filter(function(p) { return p.isFavorite; }).length;
    var wasteCount     = all.filter(function(p) { return p.aestheticScore < scoreTierBounds.t3; }).length;
    var highScoreCount  = all.filter(function(p) { return p.aestheticScore >= scoreTierBounds.t1; }).length;
    var duplicateCount  = all.filter(function(p) { return p.isDuplicate; }).length;
    function setQuickCount(quick, val) {
        var el = document.querySelector('.sidebar-item[data-quick="' + quick + '"] .count');
        if (el) el.textContent = val;
    }
    setQuickCount('favorite',  favoriteCount);
    setQuickCount('waste',     wasteCount);
    setQuickCount('highScore',  highScoreCount);
    setQuickCount('duplicate',  duplicateCount);
}

// ===== 侧边栏快捷筛选：时间 / 设备与来源 / 人物 =====
function getPeopleRanked() {
    var map = {};
    photos.forEach(function(p) {
        (p.people || []).forEach(function(name) { map[name] = (map[name] || 0) + 1; });
    });
    return Object.keys(map).map(function(name) { return { name: name, count: map[name] }; })
        .sort(function(a, b) { return b.count - a.count; });
}

function sidebarMoreChip(section, expanded) {
    return '<button class="sidebar-qf-more" onclick="toggleSidebarSection(\'' + section + '\')">'
        + '<i class="fas fa-chevron-' + (expanded ? 'up' : 'down') + '"></i> ' + (expanded ? '收起' : '更多')
        + '</button>';
}
function toggleSidebarSection(section) {
    if (section === 'time')   timeExpanded   = !timeExpanded;
    if (section === 'source') sourceExpanded = !sourceExpanded;
    if (section === 'people') peopleExpanded = !peopleExpanded;
    renderSidebarFilters();
}

function renderSidebarMediaType() {
    var c = document.getElementById('sidebarMediaTypeChips');
    if (!c) return;
    c.innerHTML = mediaTypeQuickDefs.map(function(d) {
        var active = sidebarMediaType === d.key;
        return '<span class="sidebar-qf-chip' + (active ? ' active' : '') + '" onclick="toggleSidebarMediaType(\'' + d.key + '\')">'
            + '<i class="' + d.icon + '"></i> ' + d.label + '</span>';
    }).join('');
    var clr = document.getElementById('sidebarMediaTypeClear');
    if (clr) clr.style.display = sidebarMediaType ? '' : 'none';
}
function toggleSidebarMediaType(key) {
    sidebarMediaType = (sidebarMediaType === key) ? null : key;
    renderSidebarMediaType();
    renderPhotos();
}
function clearSidebarMediaType() { sidebarMediaType = null; renderSidebarMediaType(); renderPhotos(); }

function renderSidebarTime() {
    var c = document.getElementById('sidebarTimeChips');
    if (!c) return;
    // 全部 6 个时间项始终展示，无"更多"按钮
    c.innerHTML = timeQuickDefs.map(function(d) {
        var active = sidebarTimeKey === d.key;
        return '<span class="sidebar-qf-chip' + (active ? ' active' : '') + '" onclick="toggleSidebarTime(\'' + d.key + '\')">'
            + '<i class="' + (d.icon || 'fas fa-calendar-day') + '"></i> ' + d.label + '</span>';
    }).join('');
}
function toggleSidebarTime(key) {
    sidebarTimeKey = (sidebarTimeKey === key) ? null : key;
    renderSidebarFilters();
    renderPhotos();
}
function clearSidebarTime() { sidebarTimeKey = null; renderSidebarFilters(); renderPhotos(); }

function renderSidebarSource() {
    var c = document.getElementById('sidebarSourceChips');
    if (!c) return;
    // 全部 6 个设备与来源项始终展示，无"更多"按钮
    c.innerHTML = sourceDefs.map(function(d) {
        var active = sidebarSource === d.key;
        return '<span class="sidebar-qf-chip' + (active ? ' active' : '') + '" onclick="toggleSidebarSource(\'' + d.key + '\')">'
            + '<i class="' + d.icon + '"></i> ' + d.label + '</span>';
    }).join('');
}
function toggleSidebarSource(key) {
    // 单选：再次点击同一项 = 清空
    sidebarSource = (sidebarSource === key) ? null : key;
    renderSidebarFilters();
    renderPhotos();
}
function clearSidebarSource() { sidebarSource = null; renderSidebarFilters(); renderPhotos(); }

function onSidebarPeopleSearch(query) {
    sidebarPeopleQuery = (query || '').trim();
    renderSidebarPeople();
}
function renderSidebarPeople() {
    var c = document.getElementById('sidebarPeopleChips');
    if (!c) return;
    var ranked = getPeopleRanked();
    var filtered = sidebarPeopleQuery
        ? ranked.filter(function(d) { return d.name.indexOf(sidebarPeopleQuery) !== -1; })
        : ranked;
    var PEOPLE_DEFAULT = 5;
    var defs = sidebarPeopleQuery
        ? filtered  // 有搜索词时显示全部匹配
        : (peopleExpanded ? filtered : filtered.slice(0, PEOPLE_DEFAULT));
    var html = defs.map(function(d) {
        var active = sidebarPeople.indexOf(d.name) !== -1;
        return '<span class="sidebar-qf-chip' + (active ? ' active' : '') + '" onclick="toggleSidebarPerson(\'' + d.name + '\')">'
            + '<i class="fas fa-user"></i> ' + d.name + '</span>';
    }).join('');
    if (!sidebarPeopleQuery && filtered.length > PEOPLE_DEFAULT) html += sidebarMoreChip('people', peopleExpanded);
    if (!html) html = '<span style="font-size:11px;color:var(--text-secondary);">无匹配人物</span>';
    c.innerHTML = html;
}
function toggleSidebarPerson(name) {
    var i = sidebarPeople.indexOf(name);
    if (i === -1) sidebarPeople.push(name); else sidebarPeople.splice(i, 1);
    renderSidebarFilters();
    renderPhotos();
}
function clearSidebarPeople() {
    sidebarPeople = [];
    sidebarPeopleQuery = '';
    var inp = document.getElementById('sidebarPeopleSearch');
    if (inp) inp.value = '';
    renderSidebarFilters();
    renderPhotos();
}

function renderSidebarFilters() {
    renderSidebarMediaType();
    renderSidebarTime();
    renderSidebarSource();
    renderSidebarPeople();
    function setClear(id, show) {
        var el = document.getElementById(id);
        if (el) el.style.display = show ? '' : 'none';
    }
    setClear('sidebarTimeClear', !!sidebarTimeKey);
    setClear('sidebarSourceClear', !!sidebarSource);
    setClear('sidebarPeopleClear', sidebarPeople.length > 0);
}

function togglePhotoSelection(event, id) {
    event.stopPropagation();
    if (selectedPhotos.has(id)) {
        selectedPhotos.delete(id);
    } else {
        selectedPhotos.add(id);
    }
    renderPhotos();
    updateMultiSelectToolbar();
}

function updatePhotoCount(count) {
    var countEl = document.getElementById('photoCount');
    if (countEl) countEl.textContent = count + ' 张照片';
}

function setSortMode(mode) {
    currentSortMode = mode;
    renderPhotos();
    showToast('已更新排序方式');
}

// ========== 照片网格尺寸调节 ==========
function applyGridSize() {
    var cols = gridColLevels[gridSizeLevel];
    var gap = gridGapLevels[gridSizeLevel];
    var photoGrid = document.getElementById('photoGrid');
    var eventGrid = document.getElementById('eventPhotoGrid');
    var target = currentPage === 'event' ? eventGrid : photoGrid;
    if (!photoGrid && !eventGrid) return;
    // 同时更新两个网格的 CSS 变量
    [photoGrid, eventGrid].forEach(function(grid) {
        if (!grid) return;
        grid.style.gap = gap + 'px';
        var colWidth = 'calc((100% - ' + ((cols - 1) * gap) + 'px) / ' + cols + ')';
        grid.style.setProperty('--photo-col-width', colWidth);
        var radiusMap = { 2: '14px', 4: '12px', 6: '10px', 8: '8px', 12: '6px', 16: '4px', 32: '2px' };
        grid.style.setProperty('--photo-card-radius', radiusMap[cols] || '8px');
    });
    var hideByZoom = gridSizeLevel >= gridColLevels.length - 2;
    if (photoGrid) photoGrid.classList.toggle('hide-score', !scoreBadgeVisible || hideByZoom);
    if (eventGrid) eventGrid.classList.toggle('hide-score', !scoreBadgeVisible || hideByZoom);
    if (!target) target = photoGrid;
    if (!target) return;
    // scale pulse：0.995→1，0.1s，走 compositor 线程，不触发 layout
    target.style.transition = 'none';
    target.style.transform = 'scale(0.995)';
    requestAnimationFrame(function() {
        target.style.transition = 'transform 0.1s ease-out';
        target.style.transform = 'scale(1)';
    });
    var outBtn = document.getElementById('zoomOutBtn');
    var inBtn = document.getElementById('zoomInBtn');
    if (outBtn) outBtn.disabled = (gridSizeLevel === gridColLevels.length - 1);
    if (inBtn) inBtn.disabled = (gridSizeLevel === 0);
}

function adjustGridSize(delta) {
    var newLevel = gridSizeLevel + delta;
    if (newLevel < 0 || newLevel >= gridColLevels.length) return;
    gridSizeLevel = newLevel;
    applyGridSize();
}


// ====== 全屏照片查看器 ======
var viewerInfoOpen = false;

function getScoreTierClass(score) {
    if (score >= scoreTierBounds.t1) return 'tier-blue';
    if (score >= scoreTierBounds.t2) return 'tier-green';
    if (score >= scoreTierBounds.t3) return 'tier-yellow';
    return 'tier-pink';
}

// 当前用户时区文本（如 UTC+8 / UTC-5:30）
function getUserTimezoneLabel() {
    var offsetMin = -new Date().getTimezoneOffset(); // 东区为正
    var sign = offsetMin >= 0 ? '+' : '-';
    var abs = Math.abs(offsetMin);
    var h = Math.floor(abs / 60);
    var m = abs % 60;
    return 'UTC' + sign + h + (m ? ':' + String(m).padStart(2, '0') : '');
}

// 拍摄时间完整展示：YYYY / MM / DD HH:MM:SS UTC+8
function formatShotDateTime(photo) {
    if (!photo.date) return '--';
    var datePart = photo.date.replace(/-/g, ' / ');
    var timePart = photo.time || '00:00:00';
    return datePart + ' ' + timePart + ' ' + getUserTimezoneLabel();
}

function renderViewerContent(photo) {
    var headEl = document.getElementById('viewerDetailHead');
    var scoreEl = document.getElementById('viewerScoreSection');
    var tagsEl = document.getElementById('viewerTagsSection');
    var descEl = document.getElementById('viewerDescSection');
    var adviceEl = document.getElementById('viewerAdviceSection');
    if (!headEl) return;

    // ---- 文件名 + 元数据 ----
    var mediaTypeLabels = { photo: '照片', video: '视频', live: 'Live 照片', screenshot: '截图', raw: 'RAW' };
    var mediaIconMap = { photo: 'fa-image', video: 'fa-video', live: 'fa-bolt', screenshot: 'fa-mobile-alt', raw: 'fa-file-image' };
    var typeIcon = mediaIconMap[photo.mediaType] || 'fa-image';
    var typeLabel = mediaTypeLabels[photo.mediaType] || photo.mediaType;
    var headHtml = '<div class="viewer-detail-fname">' + (photo.filename || ('照片 #' + photo.id)) + '</div>'
        + '<div class="viewer-meta-row"><i class="fas fa-clock"></i>' + formatShotDateTime(photo) + '</div>'
        + '<div class="viewer-meta-row"><i class="fas fa-map-marker-alt"></i>' + (photo.location || '未知位置') + '</div>'
        + '<div class="viewer-meta-row"><i class="fas ' + typeIcon + '"></i>' + typeLabel
        + (photo.deviceType ? ' · ' + photo.deviceType : '') + '</div>';
    if (photo.people && photo.people.length) {
        headHtml += '<div class="viewer-people-row">'
            + photo.people.map(function(p) { return '<span class="viewer-person-chip"><i class="fas fa-user"></i>' + p + '</span>'; }).join('')
            + '</div>';
    }
    headEl.innerHTML = headHtml;

    // ---- 评分 + 维度 ----
    var aeClass = getScoreTierClass(photo.aestheticScore);
    var cpClass = getScoreTierClass(photo.score);
    var pillStyle = {
        'tier-blue':   'background: linear-gradient(135deg, rgba(108,160,220,0.65), rgba(108,160,220,0.45)), rgba(0,0,0,0.18);',
        'tier-green':  'background: linear-gradient(135deg, rgba(102,194,148,0.65), rgba(102,194,148,0.45)), rgba(0,0,0,0.18);',
        'tier-yellow': 'background: linear-gradient(135deg, rgba(232,196,86,0.65), rgba(232,196,86,0.45)), rgba(0,0,0,0.18);',
        'tier-pink':   'background: linear-gradient(135deg, rgba(232,140,158,0.65), rgba(232,140,158,0.45)), rgba(0,0,0,0.2);'
    };
    var dims = [
        { name: '美学', value: photo.dimensions.aesthetics },
        { name: '技术', value: photo.dimensions.technical },
        { name: '内容', value: photo.dimensions.content },
        { name: '情感', value: photo.dimensions.emotion },
        { name: '稀有', value: photo.dimensions.rarity },
        { name: '独特', value: photo.dimensions.uniqueness }
    ];
    scoreEl.innerHTML = '<div class="viewer-section-label">评分</div>'
        + '<div class="viewer-score-pills">'
        + '<span class="viewer-score-pill" style="' + (pillStyle[aeClass] || '') + '"><i class="fas fa-camera-retro"></i> 美学 ' + photo.aestheticScore + '</span>'
        + '<span class="viewer-score-pill" style="' + (pillStyle[cpClass] || '') + '"><i class="fas fa-chart-line"></i> 综合 ' + photo.score + '</span>'
        + '</div>'
        + '<div class="viewer-section-label">维度</div>'
        + '<div class="viewer-dim-list">' + dims.map(function(d) {
            return '<div class="viewer-dim-item"><div class="viewer-dim-head"><span>' + d.name + '</span><strong>' + d.value + '</strong></div>'
                + '<div class="viewer-dim-track"><div class="viewer-dim-fill" style="width:' + d.value + '%"></div></div></div>';
        }).join('') + '</div>';

    // ---- 标签 ----
    tagsEl.innerHTML = '';
    if (photo.tags && photo.tags.length) {
        tagsEl.innerHTML = '<div class="viewer-section-label">标签</div>'
            + '<div class="viewer-tag-cloud">' + photo.tags.map(function(t) { return '<span class="viewer-tag">' + t + '</span>'; }).join('') + '</div>';
    }

    // ---- 描述 + 日记 ----
    descEl.innerHTML = '';
    if (photo.contentDescription) {
        descEl.innerHTML += '<div class="viewer-section-label">内容描述</div>'
            + '<p class="viewer-desc-text">' + photo.contentDescription + '</p>';
    }
    if (photo.photoDiary) {
        descEl.innerHTML += '<div class="viewer-section-label">照片回忆</div>'
            + '<p class="viewer-desc-text">' + photo.photoDiary + '</p>';
    }

    // ---- 保留建议 + 相似组 ----
    adviceEl.innerHTML = '';
    if (photo.retentionAdvice) {
        adviceEl.innerHTML += '<div class="viewer-section-label">保留建议</div>'
            + '<div class="viewer-advice-box ' + photo.retentionAdvice.level + '">' + photo.retentionAdvice.text + '</div>';
    }
    if (photo.isDuplicate && photo.duplicateGroup) {
        adviceEl.innerHTML += '<div class="viewer-section-label">相似组</div>'
            + '<p class="viewer-desc-text">相似组：<strong style="color:rgba(255,255,255,0.82)">' + photo.duplicateGroup + '</strong>（组内质量排名第 ' + photo.duplicateRank + '）</p>';
    }

    // 更新收藏按钮状态
    var favBtn = document.getElementById('viewerFavBtn');
    if (favBtn) {
        favBtn.innerHTML = photo.isFavorite
            ? '<i class="fas fa-heart" style="color:#ff453a"></i> 已收藏'
            : '<i class="fas fa-heart"></i> 收藏';
    }
    // 更新废片篓按钮状态
    updateViewerTrashBtn(photo);
}

function openPhotoViewer(id) {
    var photo = photos.find(function(item) { return item.id === id; });
    if (!photo) return;
    currentDetailPhotoId = id;

    var viewer = document.getElementById('photoViewer');
    var img = document.getElementById('viewerImg');
    var fnEl = document.getElementById('viewerFilename');
    if (!viewer) return;

    if (img) {
        img.src = 'https://picsum.photos/seed/' + photo.id + '/1200/900';
        img.alt = photo.filename || ('照片 #' + photo.id);
    }
    if (fnEl) fnEl.textContent = photo.filename || ('照片 #' + photo.id);

    setupViewerMedia(photo);
    updateViewerNavButtons();
    renderViewerContent(photo);

    // 关闭详情面板（默认仅显示照片）
    viewerInfoOpen = false;
    viewer.classList.remove('detail-open');
    var infoBtn = document.getElementById('viewerInfoBtn');
    if (infoBtn) infoBtn.classList.remove('active');

    viewer.classList.add('show');
    document.body.style.overflow = 'hidden';
}

// 兼容旧调用
function openPhotoDetail(id) { openPhotoViewer(id); }

function closePhotoViewer() {
    stopViewerPlayback();
    var viewer = document.getElementById('photoViewer');
    if (viewer) viewer.classList.remove('show');
    document.body.style.overflow = '';
    currentDetailPhotoId = null;
    viewerInfoOpen = false;
    // 退出事件页查看器时，清除临时照片集
    _viewerPhotoSet = null;
}
function closePhotoDetail() { closePhotoViewer(); }

function toggleViewerInfo() {
    viewerInfoOpen = !viewerInfoOpen;
    var viewer = document.getElementById('photoViewer');
    var btn = document.getElementById('viewerInfoBtn');
    if (viewer) viewer.classList.toggle('detail-open', viewerInfoOpen);
    if (btn) btn.classList.toggle('active', viewerInfoOpen);
    // 重新渲染内容（确保最新收藏状态）
    if (viewerInfoOpen && currentDetailPhotoId) {
        var photo = photos.find(function(p) { return p.id === currentDetailPhotoId; });
        if (photo) renderViewerContent(photo);
    }
}

function updateViewerNavButtons() {
    var visible = getViewerPhotoSet();
    var idx = -1;
    for (var i = 0; i < visible.length; i++) { if (visible[i].id === currentDetailPhotoId) { idx = i; break; } }
    var prev = document.getElementById('viewerPrev');
    var next = document.getElementById('viewerNext');
    if (prev) prev.disabled = idx <= 0;
    if (next) next.disabled = idx < 0 || idx >= visible.length - 1;
}

function navigateViewer(dir) {
    var visible = getViewerPhotoSet();
    var idx = -1;
    for (var i = 0; i < visible.length; i++) { if (visible[i].id === currentDetailPhotoId) { idx = i; break; } }
    var newIdx = idx + dir;
    if (newIdx < 0 || newIdx >= visible.length) return;
    var newPhoto = visible[newIdx];
    currentDetailPhotoId = newPhoto.id;
    var img = document.getElementById('viewerImg');
    var fnEl = document.getElementById('viewerFilename');
    if (img) { img.src = 'https://picsum.photos/seed/' + newPhoto.id + '/1200/900'; img.alt = newPhoto.filename || ''; }
    if (fnEl) fnEl.textContent = newPhoto.filename || ('照片 #' + newPhoto.id);
    setupViewerMedia(newPhoto);
    if (viewerInfoOpen) renderViewerContent(newPhoto);
    updateViewerNavButtons();
}

function toggleFavoriteCurrent() {
    if (!currentDetailPhotoId) return;
    var photo = photos.find(function(item) { return item.id === currentDetailPhotoId; });
    if (!photo) return;
    photo.isFavorite = !photo.isFavorite;
    showToast(photo.isFavorite ? '已加入收藏' : '已取消收藏');
    var favBtn = document.getElementById('viewerFavBtn');
    if (favBtn) {
        favBtn.innerHTML = photo.isFavorite
            ? '<i class="fas fa-heart" style="color:#ff453a"></i> 已收藏'
            : '<i class="fas fa-heart"></i> 收藏';
    }
}

// ===== 视频 / Live 照片播放（模拟） =====
var _viewerPlaying = false;
var _viewerPlayTimer = null;

// 根据照片媒体类型，配置查看器内的播放控制与角标
function setupViewerMedia(photo) {
    stopViewerPlayback();
    var badge = document.getElementById('viewerMediaBadge');
    var playBtn = document.getElementById('viewerPlayBtn');
    var playbar = document.getElementById('viewerPlaybar');
    var isVideo = photo.mediaType === 'video';
    var isLive = photo.mediaType === 'live';
    if (badge) {
        if (isVideo) { badge.style.display = ''; badge.innerHTML = '<i class="fas fa-video"></i> 视频'; }
        else if (isLive) { badge.style.display = ''; badge.innerHTML = '<i class="fas fa-bolt"></i> LIVE'; }
        else { badge.style.display = 'none'; }
    }
    if (playBtn) playBtn.style.display = (isVideo || isLive) ? '' : 'none';
    if (playbar) playbar.style.display = 'none';
}

function toggleViewerPlayback() {
    if (_viewerPlaying) { stopViewerPlayback(); }
    else { startViewerPlayback(); }
}

function startViewerPlayback() {
    var photo = photos.find(function(p) { return p.id === currentDetailPhotoId; });
    if (!photo || (photo.mediaType !== 'video' && photo.mediaType !== 'live')) return;
    _viewerPlaying = true;
    var icon = document.getElementById('viewerPlayIcon');
    var playBtn = document.getElementById('viewerPlayBtn');
    var playbar = document.getElementById('viewerPlaybar');
    var fill = document.getElementById('viewerPlaybarFill');
    if (icon) icon.className = 'fas fa-pause';
    if (playBtn) playBtn.classList.add('playing');
    // Live 照片时长较短（约 3s），视频较长（约 12s）
    var duration = photo.mediaType === 'live' ? 3000 : 12000;
    var start = Date.now();
    if (playbar) playbar.style.display = '';
    if (fill) fill.style.width = '0%';
    clearInterval(_viewerPlayTimer);
    _viewerPlayTimer = setInterval(function() {
        var pct = Math.min(100, (Date.now() - start) / duration * 100);
        if (fill) fill.style.width = pct + '%';
        if (pct >= 100) { stopViewerPlayback(); }
    }, 50);
}

function stopViewerPlayback() {
    _viewerPlaying = false;
    clearInterval(_viewerPlayTimer);
    _viewerPlayTimer = null;
    var icon = document.getElementById('viewerPlayIcon');
    var playBtn = document.getElementById('viewerPlayBtn');
    if (icon) icon.className = 'fas fa-play';
    if (playBtn) playBtn.classList.remove('playing');
}

// 直接硬删除一组照片（不弹确认框），并刷新 UI；返回删除数量
function hardDeletePhotoIds(ids) {
    if (!ids || !ids.length) return 0;
    var idSet = {};
    ids.forEach(function(id) { idSet[id] = true; });
    photos = photos.filter(function(photo) { return !idSet[photo.id]; });
    ids.forEach(function(id) { selectedPhotos.delete(id); });
    renderPhotos();
    updateFindBanner();
    if (isFindOpen()) runFind();
    updateMultiSelectToolbar();
    return ids.length;
}

// 查看器内：直接删除当前照片（无二次确认）
function deleteCurrentPhoto() {
    if (!currentDetailPhotoId) return;
    var id = currentDetailPhotoId;
    // 先尝试在当前结果集中切到下一张，保证删除后查看器仍有内容
    var visible = getViewerPhotoSet();
    var idx = -1;
    for (var i = 0; i < visible.length; i++) { if (visible[i].id === id) { idx = i; break; } }
    var nextPhoto = null;
    if (visible.length > 1) {
        nextPhoto = visible[idx + 1] || visible[idx - 1] || null;
    }
    hardDeletePhotoIds([id]);
    showToast('已删除照片');
    if (nextPhoto) {
        openPhotoViewer(nextPhoto.id);
    } else {
        closePhotoViewer();
    }
}

// 查看器内：将当前照片移入 / 移出废片篓
function moveCurrentToTrash() {
    if (!currentDetailPhotoId) return;
    var photo = photos.find(function(item) { return item.id === currentDetailPhotoId; });
    if (!photo) return;
    var wasInTrash = photo.isInTrash;
    photo.isInTrash = !photo.isInTrash;
    showToast(photo.isInTrash ? '已移入废片篓' : '已移出废片篓');
    updateViewerTrashBtn(photo);

    // 若当前处于废片篓快捷筛选视图，且该照片被移出废片篓，
    // 则该照片会从当前视图消失 → 切到相邻照片或关闭查看器
    if (activeQuickFilter === 'trash' && wasInTrash) {
        var visible = getVisiblePhotos().filter(function(p) { return p.id !== currentDetailPhotoId; });
        renderPhotos();
        if (visible.length > 0) {
            openPhotoViewer(visible[0].id);
        } else {
            closePhotoViewer();
        }
    } else {
        renderPhotos();
    }
    if (isFindOpen()) runFind();
}

// 更新查看器废片篓按钮的文案/图标（依据当前是否在废片篓）
function updateViewerTrashBtn(photo) {
    var btn = document.getElementById('viewerTrashBtn');
    if (!btn || !photo) return;
    if (photo.isInTrash) {
        btn.innerHTML = '<i class="fas fa-trash-arrow-up"></i> 移出';
        btn.title = '移出废片篓 (T)';
        btn.classList.add('in-trash');
    } else {
        btn.innerHTML = '<i class="fas fa-trash-can"></i> 废片篓';
        btn.title = '移入废片篓 (T)';
        btn.classList.remove('in-trash');
    }
}

// ===== 废片篓批量操作 =====
function getTrashPhotos() {
    return photos.filter(function(p) { return p.isInTrash; });
}

// 全部移出废片篓
function restoreAllTrash() {
    var trash = getTrashPhotos();
    if (!trash.length) { showToast('废片篓为空'); return; }
    var count = trash.length;
    trash.forEach(function(p) { p.isInTrash = false; });
    // 移出后废片篓筛选结果为空 → 退出废片篓快捷筛选，回到全部视图
    if (activeQuickFilter === 'trash') {
        activeQuickFilter = 'none';
        document.querySelectorAll('.sidebar-item[data-quick]').forEach(function(item) {
            item.classList.remove('active');
        });
        var clearBtn = document.getElementById('sidebarStatusClear');
        if (clearBtn) clearBtn.style.display = 'none';
    }
    // 清除多选状态，避免遗留"已选 N 张"工具栏
    selectedPhotos.clear();
    updateMultiSelectToolbar();
    renderPhotos();
    updateFindBanner();
    if (isFindOpen()) runFind();
    showToast('已将 ' + count + ' 项移出废片篓');
}

// 清空废片篓（二次确认后永久删除全部）
function emptyTrash() {
    var trash = getTrashPhotos();
    if (!trash.length) { showToast('废片篓为空'); return; }
    pendingDeleteIds = trash.map(function(p) { return p.id; });
    pendingDeleteMode = 'emptyTrash';
    var countEl = document.getElementById('deleteCount');
    if (countEl) countEl.textContent = pendingDeleteIds.length;
    var titleEl = document.getElementById('deleteModalTitle');
    if (titleEl) titleEl.innerHTML = '<i class="fas fa-trash-can" style="color:var(--danger)"></i> 清空废片篓';
    var bodyEl = document.getElementById('deleteModalBody');
    if (bodyEl) bodyEl.innerHTML = '确定要永久删除废片篓中的 <strong>' + pendingDeleteIds.length + '</strong> 项吗？此操作不可撤销。';
    document.getElementById('deleteModal').classList.add('show');
}

function updateMultiSelectToolbar() {
    var toolbar = document.querySelector('.multi-select-toolbar');
    var countEl = document.querySelector('.selected-count');
    if (selectedPhotos.size > 0) {
        toolbar.classList.add('show');
        countEl.textContent = '已选 ' + selectedPhotos.size + ' 张';
    } else {
        toolbar.classList.remove('show');
    }
}

// ========== 时间线 ==========

// 从 photos 数据生成 2026 的月份回忆条目
function buildMonthlyMemories(year) {
    var yearStr = String(year);
    var yearPhotos = photos.filter(function(p) { return p.date && p.date.indexOf(yearStr + '-') === 0; });
    if (!yearPhotos.length) return [];
    var monthMap = {};
    yearPhotos.forEach(function(p) {
        var m = parseInt(p.date.slice(5, 7), 10);
        if (!monthMap[m]) monthMap[m] = { photos: [], ids: [], hasTravel: false };
        if (monthMap[m].photos.length < 4) monthMap[m].photos.push(p.url);
        monthMap[m].ids.push(p.id);
        if (p.tags && p.tags.indexOf('旅行') !== -1) monthMap[m].hasTravel = true;
    });
    return Object.keys(monthMap).map(function(m) {
        return {
            year: year, month: parseInt(m, 10), type: 'memory',
            title: m + '月回忆', icon: 'fa-calendar-alt',
            isTravel: monthMap[m].hasTravel,
            desc: year + ' 年 ' + m + ' 月的照片集锦。',
            photos: monthMap[m].photos,
            allPhotoIds: monthMap[m].ids
        };
    });
}

// 合并预设事件和月份回忆，按时间倒序排列
function buildFullTimeline() {
    var allItems = timelineEvents.slice();
    // 为 2026 生成月份回忆（照片数据驱动）
    var months2026 = buildMonthlyMemories(2026);
    allItems = allItems.concat(months2026);
    // 为预设事件生成 allPhotoIds（从照片池中按标题关键词匹配，demo 中随机分配几张）
    allItems.forEach(function(item) {
        if (!item.allPhotoIds) {
            // 用 photos 中同月份的前 N 张作为事件关联照片（demo 近似处理）
            var candidates = photos.filter(function(p) {
                return p.date && parseInt(p.date.slice(0, 4), 10) === item.year
                    && parseInt(p.date.slice(5, 7), 10) === item.month;
            });
            item.allPhotoIds = candidates.map(function(p) { return p.id; });
        }
    });
    // 按 year 降序，同年按 month 降序，同月事件排在回忆前面
    allItems.sort(function(a, b) {
        if (b.year !== a.year) return b.year - a.year;
        if (b.month !== a.month) return b.month - a.month;
        if (a.type === 'event' && b.type !== 'event') return -1;
        if (b.type === 'event' && a.type !== 'event') return 1;
        return 0;
    });
    return allItems;
}

// 时间线数据缓存（用于 onclick 传参，避免 JSON 注入问题）
var _tlItemStore = {};
var _tlSearchQuery = '';

// ===== 时间线搜索 =====
function searchTimeline(query) {
    _tlSearchQuery = (query || '').trim().toLowerCase();
    var clearBtn = document.getElementById('tlSearchClear');
    if (clearBtn) clearBtn.classList.toggle('visible', !!_tlSearchQuery);
    renderTimeline();
}

function clearTimelineSearch() {
    _tlSearchQuery = '';
    var input = document.getElementById('tlSearchInput');
    if (input) input.value = '';
    var clearBtn = document.getElementById('tlSearchClear');
    if (clearBtn) clearBtn.classList.remove('visible');
    renderTimeline();
}

// 时间线条目是否匹配搜索词
function tlItemMatchesQuery(item, q) {
    if (!q) return true;
    var monthNames = ['','一月','二月','三月','四月','五月','六月','七月','八月','九月','十月','十一月','十二月'];
    var text = [
        item.title, item.desc || '',
        String(item.year), item.month + '月',
        monthNames[item.month] || '',
        item.year + '年', item.year + '年' + item.month + '月',
        item.type === 'event' ? '事件' : '回忆',
        item.isTravel ? '旅行' : ''
    ].join(' ').toLowerCase();
    return text.indexOf(q) !== -1;
}

function renderTimeline() {
    var container = document.getElementById('timelineContainer');
    if (!container) return;

    var allItems = buildFullTimeline();
    _tlItemStore = {};

    // 搜索过滤
    var items = _tlSearchQuery
        ? allItems.filter(function(item) { return tlItemMatchesQuery(item, _tlSearchQuery); })
        : allItems;

    // 统计
    var eventCount = allItems.filter(function(i) { return i.type === 'event'; }).length;
    var memoryCount = allItems.filter(function(i) { return i.type === 'memory'; }).length;
    var cnt = document.getElementById('timelinePhotoCount');
    if (cnt) cnt.textContent = eventCount + ' 个事件 · ' + memoryCount + ' 个回忆';

    if (items.length === 0) {
        container.innerHTML = _tlSearchQuery
            ? '<div class="tl-search-empty"><i class="fas fa-search"></i><h3>未找到相关事件</h3><p>试试搜索其他地名、年份或关键词</p></div>'
            : '<div class="timeline-empty"><i class="fas fa-clock"></i><h3>暂无时间线记录</h3><p>开始拍摄后，照片将自动出现在时间线中</p></div>';
        _renderYearIndex([]);
        return;
    }

    // 按年份分组
    var yearGroups = {};
    var yearOrder = [];
    items.forEach(function(item, globalIdx) {
        var y = item.year;
        if (!yearGroups[y]) { yearGroups[y] = []; yearOrder.push(y); }
        var storeKey = 'tl_' + globalIdx;
        _tlItemStore[storeKey] = item;
        yearGroups[y].push({ item: item, key: storeKey });
    });
    yearOrder.sort(function(a, b) { return b - a; });

    container.innerHTML = yearOrder.map(function(year) {
        var groupItems = yearGroups[year];
        var evtCount = groupItems.filter(function(e) { return e.item.type === 'event'; }).length;
        var memCount = groupItems.filter(function(e) { return e.item.type === 'memory'; }).length;
        var statsText = [];
        if (evtCount) statsText.push(evtCount + ' 个事件');
        if (memCount) statsText.push(memCount + ' 个回忆');

        var itemsHtml = groupItems.map(function(entry) {
            var item = entry.item;
            var storeKey = entry.key;
            var isEvent = item.type === 'event';
            var itemClass = isEvent ? 'tl-item-event' : 'tl-item-memory';
            var photoCount = item.allPhotoIds ? item.allPhotoIds.length : 0;

            // 顶部 badges
            var typeTag = isEvent
                ? '<span class="tl-type-badge tl-type-event"><i class="fas ' + (item.icon || 'fa-star') + '"></i> 事件</span>'
                : '<span class="tl-type-badge tl-type-memory"><i class="fas fa-calendar-alt"></i> 回忆</span>';
            var travelBadge = item.isTravel ? '<span class="travel-event-badge"><i class="fas fa-plane"></i> 旅行</span>' : '';
            var topRow = '<div class="tl-card-top">'
                + '<div class="tl-card-badges">' + typeTag + travelBadge + '</div>'
                + '<span class="tl-month-chip">' + item.month + ' 月</span>'
                + '</div>';

            // 标题
            var titleRow = '<div class="tl-card-title-row">'
                + '<i class="fas ' + (item.icon || 'fa-images') + ' tl-card-icon"></i>'
                + '<span class="tl-card-name">' + item.title + '</span>'
                + '</div>';

            // 描述
            var descRow = item.desc ? '<p class="tl-desc">' + item.desc + '</p>' : '';

            // 照片条（底部）— 去除 tl-card-count，仅用 tl-more-chip 表达多余张数
            var photosHtml = '';
            if (item.photos && item.photos.length > 0) {
                var imgs = item.photos.slice(0, 4).map(function(url) {
                    return '<img src="' + url + '" class="timeline-photo" alt="">';
                }).join('');
                var moreChip = photoCount > 4
                    ? '<span class="tl-more-chip">+' + (photoCount - 4) + '<small>张</small></span>'
                    : '';
                photosHtml = '<div class="tl-card-photos">' + imgs + moreChip + '</div>';
            } else if (photoCount > 0) {
                photosHtml = '<div class="tl-card-photos-empty"><div class="tl-card-photos-empty-inner"><i class="fas fa-images"></i></div></div>';
            }

            return '<div class="timeline-item tl-clickable ' + itemClass + '" onclick="openTimelineEvent(\'' + storeKey + '\')">'
                + topRow + titleRow + descRow + photosHtml + '</div>';
        }).join('');

        return '<div class="tl-year-section" id="tl-year-' + year + '">'
            + '<div class="tl-year-header">'
            + '<span class="tl-year-label">' + year + '</span>'
            + '<span class="tl-year-stats">' + statsText.join(' · ') + '</span>'
            + '</div>'
            + '<div class="timeline">' + itemsHtml + '</div>'
            + '</div>';
    }).join('');

    _renderYearIndex(yearOrder);
    // 延迟初始化 observer（等待 DOM 渲染完成）
    setTimeout(_initTlYearObserver, 80);
}

// 渲染右侧年份快速跳转索引
function _renderYearIndex(yearOrder) {
    var el = document.getElementById('tlYearIndex');
    if (!el) return;
    if (!yearOrder || yearOrder.length <= 1) {
        el.classList.remove('visible');
        el.innerHTML = '';
        return;
    }
    el.classList.add('visible');
    el.innerHTML = yearOrder.map(function(y) {
        return '<span class="tl-yi-item" onclick="tlJumpToYear(' + y + ')">' + y + '</span>';
    }).join('');
}

function tlJumpToYear(year) {
    var sec = document.getElementById('tl-year-' + year);
    if (!sec) return;
    // 滚动：手动计算滚动位置，考虑 sticky 年份标题高度（约 48px）
    var mc = document.querySelector('.main-content');
    if (mc) {
        var containerRect = mc.getBoundingClientRect();
        var secRect = sec.getBoundingClientRect();
        mc.scrollTop += secRect.top - containerRect.top - 56;
    } else {
        sec.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
    setTlYiActive(year);
}

function setTlYiActive(year) {
    document.querySelectorAll('.tl-yi-item').forEach(function(el) {
        el.classList.toggle('active', parseInt(el.textContent, 10) === year);
    });
}

// IntersectionObserver：自动高亮当前可见的年份
var _tlYearObserver = null;
function _initTlYearObserver() {
    if (_tlYearObserver) _tlYearObserver.disconnect();
    var mc = document.querySelector('.main-content');
    if (!mc) return;
    var sections = document.querySelectorAll('.tl-year-section[id^="tl-year-"]');
    if (!sections.length) return;
    _tlYearObserver = new IntersectionObserver(function(entries) {
        entries.forEach(function(entry) {
            if (entry.isIntersecting) {
                var y = parseInt(entry.target.id.replace('tl-year-', ''), 10);
                setTlYiActive(y);
            }
        });
    }, { root: mc, rootMargin: '-52px 0px -60% 0px', threshold: 0 });
    sections.forEach(function(sec) { _tlYearObserver.observe(sec); });
}

// 兼容旧函数
function initTimelineYearOptions() {}
function navigateYear() {}
function selectYear() {}

// ========== 事件详情页 ==========

function openTimelineEvent(storeKey) {
    var item = _tlItemStore[storeKey];
    if (!item) return;
    currentTimelineEvent = item;

    var titleEl = document.getElementById('eventPageTitle');
    if (titleEl) titleEl.textContent = item.title;

    var countEl = document.getElementById('eventPhotoCount');
    // 从真实 photos 数组中取关联照片
    var eventPhotos = item.allPhotoIds && item.allPhotoIds.length
        ? photos.filter(function(p) { return item.allPhotoIds.indexOf(p.id) !== -1; })
        : [];
    if (countEl) countEl.textContent = eventPhotos.length + ' 张照片';

    var grid = document.getElementById('eventPhotoGrid');
    if (grid) {
        if (eventPhotos.length === 0) {
            grid.innerHTML = '<div class="timeline-empty" style="grid-column:1/-1"><i class="fas fa-images"></i><h3>暂无照片</h3><p>该事件尚未关联照片</p></div>';
        } else {
            grid.innerHTML = eventPhotos.map(function(photo) {
                var badgeScore = getBadgeScore(photo);
                var scoreClass = getScoreClass(badgeScore);
                var icon = scoreBadgeMode === 'composite' ? 'fa-chart-line' : 'fa-camera-retro';
                return '<div class="photo-card" data-id="' + photo.id + '" onclick="openEventPhoto(' + photo.id + ')">'
                    + '<img src="' + photo.url + '" alt="照片" loading="lazy">'
                    + '<div class="photo-score ' + scoreClass + '"><i class="fas ' + icon + '"></i> ' + getBadgeScoreLabelPrefix() + ' ' + badgeScore + '</div>'
                    + '</div>';
            }).join('');
            applyGridSize();
        }
    }

    navigateToPage('event');
}

// 事件页照片点击 → 打开查看器（使用事件照片集作为导航集）
var eventPhotoSet = [];
function openEventPhoto(id) {
    if (!currentTimelineEvent) { openPhotoViewer(id); return; }
    // 构建当前事件的照片集
    eventPhotoSet = currentTimelineEvent.allPhotoIds && currentTimelineEvent.allPhotoIds.length
        ? photos.filter(function(p) { return currentTimelineEvent.allPhotoIds.indexOf(p.id) !== -1; })
        : [];
    openPhotoViewerInSet(id, eventPhotoSet);
}

// 支持指定照片集的查看器（事件页用）
function openPhotoViewerInSet(id, set) {
    _viewerPhotoSet = set && set.length ? set : null;
    openPhotoViewer(id);
}

function getViewerPhotoSet() {
    return _viewerPhotoSet || getVisiblePhotos();
}


// ========== 报告 ==========
function renderReports() {
    var container = document.getElementById('reportList');
    if (!container) return;
    container.innerHTML = reports.map(function(report) {
        return '<div class="report-card" onclick="openReport(' + report.id + ')"><div class="report-icon"><i class="fas fa-file-alt"></i></div><div class="report-info"><div class="report-title">' + report.title + '</div><div class="report-meta">' + report.date + ' · ' + report.photoCount.toLocaleString() + ' 张照片 · 平均分 ' + report.avgScore + '</div></div><div class="report-actions"><button class="toolbar-btn" onclick="event.stopPropagation(); showToast(\'查看报告\')"><i class="fas fa-eye"></i></button><button class="toolbar-btn danger" onclick="event.stopPropagation(); deleteReport(' + report.id + ')"><i class="fas fa-trash"></i></button></div></div>';
    }).join('');
}

function generateReport() { showToast('正在生成报告...'); setTimeout(function() { showToast('报告生成成功'); }, 1500); }
function openReport(id) { showToast('打开报告 ' + id); }
function deleteReport(id) { showToast('删除报告 ' + id); }

// ========== 统一「查找」浮层（搜索 + 筛选合一） ==========
var mediaTypeDefs = [
    { key: 'photo', label: '照片', icon: 'fa-image' },
    { key: 'video', label: '视频', icon: 'fa-video' },
    { key: 'live', label: 'Live', icon: 'fa-bolt' },
    { key: 'screenshot', label: '截图', icon: 'fa-mobile-screen-button' },
    { key: 'raw', label: 'RAW', icon: 'fa-file' }
];
// 状态（布尔标志）
var statusDefs = [
    { key: 'isFavorite', label: '我的收藏', icon: 'fa-heart' },
    { key: 'isDuplicate', label: '重复/相似', icon: 'fa-copy' },
    { key: 'isNewMonth', label: '近一月新增', icon: 'fa-clock' },
    { key: 'isICloud', label: '已存 iCloud', icon: 'fa-cloud' },
    { key: 'isInTrash', label: '废片篓', icon: 'fa-trash-can' }
];
// 设备与来源（后 6 项）：kind=flag 为布尔标志；kind=device 匹配 photo.deviceType。icon 含完整前缀
var sourceDefs = [
    { key: 'isProDevice', label: '专业设备', icon: 'fas fa-camera-retro', kind: 'flag' },
    { key: 'isProEdited', label: '专业软件', icon: 'fas fa-magic', kind: 'flag' },
    { key: 'Pocket', label: 'Pocket', icon: 'fab fa-get-pocket', kind: 'device' },
    { key: '运动相机', label: '运动相机', icon: 'fas fa-person-running', kind: 'device' },
    { key: '无人机', label: '无人机', icon: 'fas fa-helicopter', kind: 'device' },
    { key: '单反相机', label: '单反相机', icon: 'fas fa-camera', kind: 'device' }
];
var deviceTypePool = ['手机', '单反相机', '运动相机', '无人机', 'Pocket'];
var metricShortLabels = {
    aesthetics: '美学', composite: '综合', technical: '技术',
    content: '内容', emotion: '情感', rarity: '稀有', uniqueness: '独特'
};

function mediaLabel(key) {
    var def = mediaTypeDefs.find(function(m) { return m.key === key; });
    return def ? def.label : key;
}
function metricShort(metric) { return metricShortLabels[metric] || metric; }

// ----- 打开 / 关闭 -----
// 查找浮层打开时：以照片页为实时画布，浮层只承载筛选控件与计数，照片墙随条件实时更新
function openFind() {
    // 切到照片页作为实时结果画布，并清空侧边栏标签/快捷筛选，让查找成为唯一筛选维度
    activeSidebarTag = 'all';
    activeQuickFilter = 'none';
    sidebarMediaType = null;
    sidebarTimeKey = null;
    sidebarSource = null;
    sidebarPeople = [];
    sidebarPeopleQuery = '';
    document.querySelectorAll('#tagCloud .sidebar-tag-item').forEach(function(item) {
        item.classList.toggle('active', item.dataset.tag === 'all');
    });
    document.querySelectorAll('.sidebar-item[data-quick]').forEach(function(item) {
        item.classList.remove('active');
    });
    renderSidebarFilters();
    selectedPhotos.clear();
    navigateToPage('photos');
    // 隐藏照片页侧边栏，给实时照片墙一个干净画布
    var sidebarGroup = document.getElementById('sidebarGroup');
    if (sidebarGroup) sidebarGroup.style.display = 'none';

    findAppliedToWall = true; // 浮层开启期间照片墙始终反映当前条件
    renderFindFilters();
    syncFindScoreEditor();
    runFind();

    var ov = document.getElementById('findOverlay');
    if (ov) ov.classList.add('show');
    window.setTimeout(function() {
        var input = document.getElementById('findInput');
        if (input) input.focus();
    }, 60);
}
function closeFind() {
    var ov = document.getElementById('findOverlay');
    if (ov) ov.classList.remove('show');
    // 关闭后：有条件则保留在照片墙生效并显示横幅，无条件则恢复全部
    findAppliedToWall = findHasConditions();
    var sidebarGroup = document.getElementById('sidebarGroup');
    if (sidebarGroup) sidebarGroup.style.display = (currentPage === 'photos') ? '' : 'none';
    renderPhotos();
    updateFindBanner();
    updateMultiSelectToolbar();
}
function isFindOpen() {
    var ov = document.getElementById('findOverlay');
    return !!(ov && ov.classList.contains('show'));
}

// ----- 自然语言输入 -----
function onFindQueryInput() {
    var input = document.getElementById('findInput');
    findState.query = input ? input.value.trim() : '';
    runFind();
}
function clearFindQuery() {
    findState.query = '';
    var input = document.getElementById('findInput');
    if (input) { input.value = ''; input.focus(); }
    runFind();
}

// ----- 渲染筛选芯片 -----
function renderFindFilters() {
    renderFindMediaChips();
    renderFindLocationChips();
    renderFindPeopleChips();
    renderFindTagChips();
    renderFindStatusChips();
}

// 评分条件是否构成实际过滤（默认 美学>0 不过滤）
function isScoreCondActive(c) {
    if (!c) return false;
    return !(c.op === 'gt' && c.value <= 0);
}

function countPhotos(predicate) { return photos.filter(predicate).length; }

function renderFindMediaChips() {
    var c = document.getElementById('findMediaChips');
    if (!c) return;
    c.innerHTML = mediaTypeDefs.map(function(m) {
        var n = countPhotos(function(p) { return p.mediaType === m.key; });
        var active = findState.mediaTypes.indexOf(m.key) !== -1;
        return '<button class="find-chip' + (active ? ' active' : '') + '" onclick="toggleFindMedia(\'' + m.key + '\')"><i class="fas ' + m.icon + '"></i> ' + m.label + ' <span class="count">' + n + '</span></button>';
    }).join('');
    var clr = document.getElementById('findMediaClear');
    if (clr) clr.style.display = findState.mediaTypes.length ? '' : 'none';
}
function toggleFindMedia(key) {
    var i = findState.mediaTypes.indexOf(key);
    if (i === -1) findState.mediaTypes.push(key); else findState.mediaTypes.splice(i, 1);
    renderFindMediaChips();
    runFind();
}
function clearFindMedia() {
    findState.mediaTypes = [];
    renderFindMediaChips();
    runFind();
}

function renderFindLocationChips() {
    var c = document.getElementById('findLocationChips');
    if (!c) return;
    c.innerHTML = locationPool.map(function(loc) {
        var n = countPhotos(function(p) { return p.location === loc; });
        if (n === 0) return '';
        var active = findState.locations.indexOf(loc) !== -1;
        return '<button class="find-chip' + (active ? ' active' : '') + '" onclick="toggleFindLocation(\'' + loc + '\')">' + loc + ' <span class="count">' + n + '</span></button>';
    }).join('');
    var clr = document.getElementById('findLocationClear');
    if (clr) clr.style.display = findState.locations.length ? '' : 'none';
}
function toggleFindLocation(loc) {
    var i = findState.locations.indexOf(loc);
    if (i === -1) findState.locations.push(loc); else findState.locations.splice(i, 1);
    renderFindLocationChips();
    runFind();
}
function clearFindLocations() {
    findState.locations = [];
    renderFindLocationChips();
    runFind();
}

function renderFindPeopleChips() {
    var c = document.getElementById('findPeopleChips');
    if (!c) return;
    c.innerHTML = peoplePool.map(function(person) {
        var n = countPhotos(function(p) { return (p.people || []).indexOf(person) !== -1; });
        if (n === 0) return '';
        var active = findState.people.indexOf(person) !== -1;
        return '<button class="find-chip' + (active ? ' active' : '') + '" onclick="toggleFindPerson(\'' + person + '\')"><i class="fas fa-user"></i> ' + person + ' <span class="count">' + n + '</span></button>';
    }).join('');
    var clr = document.getElementById('findPeopleClear');
    if (clr) clr.style.display = findState.people.length ? '' : 'none';
}
function toggleFindPerson(person) {
    var i = findState.people.indexOf(person);
    if (i === -1) findState.people.push(person); else findState.people.splice(i, 1);
    renderFindPeopleChips();
    runFind();
}
function clearFindPeople() {
    findState.people = [];
    renderFindPeopleChips();
    runFind();
}

function renderFindTagChips() {
    var c = document.getElementById('findTagChips');
    if (!c) return;
    c.innerHTML = tagPool.map(function(tag) {
        var n = countPhotos(function(p) { return p.tags.indexOf(tag) !== -1; });
        var active = findState.tags.indexOf(tag) !== -1;
        return '<button class="find-chip' + (active ? ' active' : '') + '" onclick="toggleFindTag(\'' + tag + '\')">' + tag + ' <span class="count">' + n + '</span></button>';
    }).join('');
    var clr = document.getElementById('findTagClear');
    if (clr) clr.style.display = findState.tags.length ? '' : 'none';
}
function toggleFindTag(tag) {
    var i = findState.tags.indexOf(tag);
    if (i === -1) findState.tags.push(tag); else findState.tags.splice(i, 1);
    renderFindTagChips();
    runFind();
}
function clearFindTags() {
    findState.tags = [];
    renderFindTagChips();
    runFind();
}

function findStatusActiveCount() {
    return statusDefs.filter(function(s) { return !!findState[s.key]; }).length;
}
function findSourceActiveCount() {
    return sourceDefs.filter(function(d) {
        return d.kind === 'flag' ? !!findState[d.key] : findState.devices.indexOf(d.key) !== -1;
    }).length;
}
function renderFindStatusChips() {
    var c = document.getElementById('findStatusChips');
    if (!c) return;
    c.innerHTML = statusDefs.map(function(s) {
        var n = countPhotos(function(p) { return !!p[s.key]; });
        var active = !!findState[s.key];
        return '<button class="find-chip' + (active ? ' active' : '') + '" onclick="toggleFindStatus(\'' + s.key + '\')"><i class="fas ' + s.icon + '"></i> ' + s.label + ' <span class="count">' + n + '</span></button>';
    }).join('');
    var clr = document.getElementById('findStatusClear');
    if (clr) clr.style.display = findStatusActiveCount() ? '' : 'none';
    renderFindSourceChips();
}
function toggleFindStatus(key) {
    findState[key] = !findState[key];
    renderFindStatusChips();
    runFind();
}
function clearFindStatus() {
    statusDefs.forEach(function(s) { findState[s.key] = false; });
    renderFindStatusChips();
    runFind();
}
function renderFindSourceChips() {
    var c = document.getElementById('findSourceChips');
    if (!c) return;
    c.innerHTML = sourceDefs.map(function(d) {
        var n = d.kind === 'flag'
            ? countPhotos(function(p) { return !!p[d.key]; })
            : countPhotos(function(p) { return p.deviceType === d.key; });
        var active = d.kind === 'flag' ? !!findState[d.key] : findState.devices.indexOf(d.key) !== -1;
        return '<button class="find-chip' + (active ? ' active' : '') + '" onclick="toggleFindSource(\'' + d.key + '\')"><i class="' + d.icon + '"></i> ' + d.label + ' <span class="count">' + n + '</span></button>';
    }).join('');
    var clr = document.getElementById('findSourceClear');
    if (clr) clr.style.display = findSourceActiveCount() ? '' : 'none';
}
function toggleFindSource(key) {
    var def = sourceDefs.filter(function(d) { return d.key === key; })[0];
    if (!def) return;
    if (def.kind === 'flag') {
        findState[key] = !findState[key];
    } else {
        var i = findState.devices.indexOf(key);
        if (i === -1) findState.devices.push(key); else findState.devices.splice(i, 1);
    }
    renderFindSourceChips();
    runFind();
}
function clearFindSource() {
    sourceDefs.forEach(function(d) {
        if (d.kind === 'flag') findState[d.key] = false;
    });
    findState.devices = [];
    renderFindSourceChips();
    runFind();
}

// ----- 评分条件（单条实时生效，无需「添加」） -----
function setFindScoreEditorMetric(metric) {
    findState.scoreCond.metric = metric;
    document.querySelectorAll('#findScoreMetricChips .score-dimension-chip').forEach(function(b) {
        b.classList.toggle('active', b.dataset.editorMetric === metric);
    });
    updateFindScoreHint();
    runFind();
}
function setFindScoreEditorOp(op) {
    findState.scoreCond.op = op;
    document.querySelectorAll('.find-score-editor .score-op-chip').forEach(function(b) {
        b.classList.toggle('active', b.dataset.editorOp === op);
    });
    updateFindScoreSliderVisual();
    updateFindScoreHint();
    runFind();
}
function onFindScoreSliderInput() {
    var slider = document.getElementById('findScoreSlider');
    var input = document.getElementById('findScoreValue');
    if (!slider) return;
    findState.scoreCond.value = parseInt(slider.value, 10) || 0;
    if (input) input.value = findState.scoreCond.value;
    updateFindScoreSliderVisual();
    updateFindScoreHint();
    runFind();
}
function onFindScoreNumberInput() {
    var slider = document.getElementById('findScoreSlider');
    var input = document.getElementById('findScoreValue');
    if (!input) return;
    var val = Math.min(100, Math.max(0, parseInt(input.value, 10) || 0));
    findState.scoreCond.value = val;
    if (slider) slider.value = val;
    updateFindScoreSliderVisual();
    updateFindScoreHint();
    runFind();
}
function updateFindScoreSliderVisual() {
    var slider = document.getElementById('findScoreSlider');
    if (!slider) return;
    var min = Number(slider.min || 0);
    var max = Number(slider.max || 100);
    var val = findState.scoreCond.value;
    var percent = ((val - min) / (max - min)) * 100;
    var activeStart = 'var(--accent-gradient-1)';
    var activeEnd = 'var(--accent-gradient-2)';
    var inactive = 'var(--glass-bg)';
    if (findState.scoreCond.op === 'lt') {
        slider.style.background = 'linear-gradient(90deg, ' + activeStart + ' 0%, ' + activeEnd + ' ' + percent + '%, ' + inactive + ' ' + percent + '%, ' + inactive + ' 100%)';
    } else {
        slider.style.background = 'linear-gradient(90deg, ' + inactive + ' 0%, ' + inactive + ' ' + percent + '%, ' + activeStart + ' ' + percent + '%, ' + activeEnd + ' 100%)';
    }
}
function updateFindScoreHint() {
    var c = findState.scoreCond;
    var hint = document.getElementById('findScoreHint');
    if (!hint) return;
    if (!isScoreCondActive(c)) {
        hint.textContent = '未过滤评分（' + getMetricLabel(c.metric) + '大于 0 分）';
    } else {
        hint.textContent = '只显示 ' + getMetricLabel(c.metric) + (c.op === 'gt' ? ' 大于 ' : ' 小于 ') + c.value + ' 分的照片';
    }
    var clr = document.getElementById('findScoreClear');
    if (clr) clr.style.display = isScoreCondActive(c) ? '' : 'none';
}
function clearFindScore() {
    findState.scoreCond = { metric: 'aesthetics', op: 'gt', value: 0 };
    syncFindScoreEditor();
    var clr = document.getElementById('findScoreClear');
    if (clr) clr.style.display = 'none';
    runFind();
}
function syncFindScoreEditor() {
    var c = findState.scoreCond;
    document.querySelectorAll('#findScoreMetricChips .score-dimension-chip').forEach(function(b) {
        b.classList.toggle('active', b.dataset.editorMetric === c.metric);
    });
    document.querySelectorAll('.find-score-editor .score-op-chip').forEach(function(b) {
        b.classList.toggle('active', b.dataset.editorOp === c.op);
    });
    var slider = document.getElementById('findScoreSlider');
    if (slider) slider.value = c.value;
    var input = document.getElementById('findScoreValue');
    if (input) input.value = c.value;
    updateFindScoreSliderVisual();
    updateFindScoreHint();
}

// ----- 实时执行查找 -----
function findHasConditions() {
    var s = findState;
    return !!(s.query || s.mediaTypes.length || s.devices.length || isScoreCondActive(s.scoreCond) || s.dateRange ||
        s.locations.length || s.people.length || s.tags.length ||
        s.favorite || s.isProDevice || s.isProEdited || s.isDuplicate || s.isNewMonth || s.isICloud);
}

function buildFindSummary() {
    var s = findState;
    var parts = [];
    if (s.query) parts.push('“' + s.query + '”');
    if (s.mediaTypes.length) parts.push('媒体:' + s.mediaTypes.map(mediaLabel).join('/'));
    if (s.devices.length) parts.push('设备:' + s.devices.join('/'));
    if (isScoreCondActive(s.scoreCond)) parts.push(metricShort(s.scoreCond.metric) + (s.scoreCond.op === 'gt' ? '>' : '<') + s.scoreCond.value);
    if (s.dateRange) parts.push('时间:' + (s.dateLabel || '自定义'));
    if (s.locations.length) parts.push('地点:' + s.locations.join('/'));
    if (s.people.length) parts.push('人物:' + s.people.join('/'));
    if (s.tags.length) parts.push('标签:' + s.tags.join('/'));
    if (s.favorite) parts.push('收藏');
    if (s.isDuplicate) parts.push('重复/相似');
    if (s.isNewMonth) parts.push('近一月新增');
    if (s.isICloud) parts.push('已存iCloud');
    if (s.isProDevice) parts.push('专业设备');
    if (s.isProEdited) parts.push('专业软件调整');
    return parts.length ? parts.join(' · ') : '未设置任何条件 · 显示全部照片';
}

// 实时执行：照片墙(浮层之后)随条件刷新，浮层只展示结果数量
function runFind() {
    findAppliedToWall = true; // 浮层交互期间照片墙始终反映当前条件
    renderPhotos();
    var count = getVisiblePhotos().length;
    var hasCond = findHasConditions();
    var countEl = document.getElementById('findCount');
    if (countEl) countEl.textContent = (hasCond ? '匹配 ' : '全部 ') + count + ' 张';
    var sumEl = document.getElementById('findActiveSummary');
    if (sumEl) sumEl.textContent = buildFindSummary();
    var clearBtn = document.getElementById('findQueryClear');
    if (clearBtn) clearBtn.style.display = findState.query ? '' : 'none';
}

// ----- 重置 -----
function resetFind() {
    findState = createEmptyFindState();
    var input = document.getElementById('findInput');
    if (input) input.value = '';
    document.querySelectorAll('.date-chip').forEach(function(chip) { chip.classList.remove('active'); });
    var disp = document.getElementById('dateSelectedDisplay');
    if (disp) disp.style.display = 'none';
    renderFindFilters();
    syncFindScoreEditor();
    runFind();
    showToast('已重置所有查找条件');
}

function updateFindBanner() {
    var banner = document.getElementById('findAppliedBanner');
    if (!banner) return;
    if (findAppliedToWall && findHasConditions()) {
        banner.classList.add('show');
        var sum = document.getElementById('findAppliedSummary');
        if (sum) sum.textContent = '查找：' + buildFindSummary();
    } else {
        banner.classList.remove('show');
    }
}

function clearFindFromWall() {
    findAppliedToWall = false;
    updateFindBanner();
    renderPhotos();
    showToast('已清除照片墙的查找条件');
}

// ----- 自然语言解析（query 作为附加 AND 约束） -----
function matchesQuery(photo, query) {
    var lower = query.toLowerCase();
    var scoreRule = parseScoreRule(query);
    var yearRule = parseYearRule(query);
    var oneMonthRule = lower.indexOf('近一月') !== -1 || lower.indexOf('最近一个月') !== -1;
    var tagRule = parseTagRule(query);
    var locationRule = parseLocationRule(query);
    if (scoreRule) {
        var targetScore = scoreRule.metric === 'aesthetic' ? photo.aestheticScore : photo.score;
        if (scoreRule.op === 'gt' && !(targetScore > scoreRule.value)) return false;
        if (scoreRule.op === 'lt' && !(targetScore < scoreRule.value)) return false;
    }
    if (yearRule && photo.date.indexOf(String(yearRule)) !== 0) return false;
    if (oneMonthRule && !photo.isNewMonth) return false;
    if (tagRule.length > 0 && !tagRule.some(function(tag) { return photo.tags.indexOf(tag) !== -1; })) return false;
    if (locationRule && photo.location.indexOf(locationRule) === -1) return false;
    if (!scoreRule && !yearRule && !oneMonthRule && tagRule.length === 0 && !locationRule) {
        var textBlob = (photo.tags.join(' ') + ' ' + photo.location + ' ' + photo.date + ' ' + (photo.people || []).join(' ') + ' 综合评分' + photo.score + ' 美学评分' + photo.aestheticScore).toLowerCase();
        if (textBlob.indexOf(lower) === -1) return false;
    }
    return true;
}

function parseScoreRule(query) {
    var agt = query.match(/美学(?:评分)?\s*(?:大于|高于|>)\s*(\d{1,3})/);
    if (agt) return { metric: 'aesthetic', op: 'gt', value: Math.min(100, parseInt(agt[1], 10)) };
    var alt = query.match(/美学(?:评分)?\s*(?:小于|低于|<|以下)\s*(\d{1,3})/);
    if (alt) return { metric: 'aesthetic', op: 'lt', value: Math.max(0, parseInt(alt[1], 10)) };
    var gt = query.match(/(?:综合)?评分\s*(?:大于|高于|>)\s*(\d{1,3})/);
    if (gt) return { metric: 'composite', op: 'gt', value: Math.min(100, parseInt(gt[1], 10)) };
    var lt = query.match(/(?:综合)?评分\s*(?:小于|低于|<|以下)\s*(\d{1,3})/);
    if (lt) return { metric: 'composite', op: 'lt', value: Math.max(0, parseInt(lt[1], 10)) };
    return null;
}

function parseYearRule(query) {
    var nowYear = new Date().getFullYear();
    if (query.indexOf('今年') !== -1) return nowYear;
    if (query.indexOf('去年') !== -1) return nowYear - 1;
    var yearMatch = query.match(/(20\d{2})年?/);
    if (yearMatch) return parseInt(yearMatch[1], 10);
    return null;
}

function parseTagRule(query) {
    var rules = [];
    var ruleMap = {
        '旅行': '旅行',
        '海边': '风景',
        '风景': '风景',
        '人物': '人物',
        '人像': '人物',
        '建筑': '建筑',
        '美食': '美食',
        '宠物': '宠物',
        '狗': '宠物',
        '夜景': '夜景'
    };
    Object.keys(ruleMap).forEach(function(key) {
        if (query.indexOf(key) !== -1 && rules.indexOf(ruleMap[key]) === -1) {
            rules.push(ruleMap[key]);
        }
    });
    return rules;
}

function parseLocationRule(query) {
    var hit = locationPool.find(function(city) { return query.indexOf(city) !== -1; });
    return hit || '';
}

// ========== 设置页 ==========
function renderSettings() {
    updateModelButtons();
    updateBadgeScoreModeDisplay();
}

function setCurrentModel(modelName, evt) {
    if (evt) {
        evt.stopPropagation();
        evt.preventDefault();
    }
    currentModel = modelName;
    updateModelButtons();
    showToast('已切换模型：' + modelName);
}

function updateModelButtons() {
    document.querySelectorAll('.model-item').forEach(function(item) {
        var model = item.dataset.model;
        var btn = item.querySelector('.model-action');
        if (!btn) return;
        if (model === currentModel) {
            btn.className = 'model-action using';
            btn.innerHTML = '<i class="fas fa-check"></i> 使用中';
        } else {
            btn.className = 'model-action download';
            btn.textContent = '下载';
        }
    });
}

function cycleFirstAnalysisStrategy() {
    firstAnalysisStrategyIndex = (firstAnalysisStrategyIndex + 1) % firstAnalysisStrategies.length;
    var value = firstAnalysisStrategies[firstAnalysisStrategyIndex];
    var valueEl = document.getElementById('firstAnalysisStrategyValue');
    if (valueEl) valueEl.textContent = value;
    showToast('首次分析策略：' + value);
}

function updateBadgeScoreModeDisplay() {
    var aeBtn = document.getElementById('badgeSegAesthetic');
    var coBtn = document.getElementById('badgeSegComposite');
    if (aeBtn && coBtn) {
        aeBtn.classList.toggle('active', scoreBadgeVisible && scoreBadgeMode === 'aesthetic');
        coBtn.classList.toggle('active', scoreBadgeVisible && scoreBadgeMode === 'composite');
        // 隐藏态：当前模式按钮以暗色弱化高亮，另一按钮保持默认样式
        aeBtn.classList.toggle('current-dim', !scoreBadgeVisible && scoreBadgeMode === 'aesthetic');
        coBtn.classList.toggle('current-dim', !scoreBadgeVisible && scoreBadgeMode === 'composite');
    }
    syncSsfDimLabel();
    updateSortScoreLabels();
}

function updateSortScoreLabels() {
    var label = scoreBadgeMode === 'composite' ? '综合评分' : '美学评分';
    var descOpt = document.getElementById('sortOptScoreDesc');
    var ascOpt = document.getElementById('sortOptScoreAsc');
    if (descOpt) descOpt.textContent = '按' + label + '排序（高→低）';
    if (ascOpt) ascOpt.textContent = '按' + label + '排序（低→高）';
}

function setBadgeScoreMode(mode) {
    if (scoreBadgeVisible && scoreBadgeMode === mode) {
        // 再次点击当前激活的模式 → 隐藏分数标签
        scoreBadgeVisible = false;
    } else {
        scoreBadgeMode = mode;
        scoreBadgeVisible = true;
    }
    updateBadgeScoreModeDisplay();
    renderPhotos(); // 角标与排序（按分时）同步刷新
    if (!scoreBadgeVisible) {
        showToast('已隐藏分数标签');
    } else {
        var text = scoreBadgeMode === 'composite' ? '综合评分' : '美学评分';
        showToast('角标已切换为：' + text + '  ' + (currentSortMode.startsWith('score') ? '（排序已同步）' : ''));
    }
}

function cycleBadgeScoreMode() {
    if (!scoreBadgeVisible) { setBadgeScoreMode(scoreBadgeMode); return; }
    setBadgeScoreMode(scoreBadgeMode === 'aesthetic' ? 'composite' : 'aesthetic');
}

// ========== 分数标签配色区间配置 ==========
function renderScoreTierConfig() {
    var b = scoreTierBounds;
    var bar = document.getElementById('scoreTierBar');
    if (bar) {
        // 从低到高（左→右）：粉 0~t3 / 黄 t3~t2 / 绿 t2~t1 / 蓝 t1~100
        var segs = [
            { cls: 'tier-pink', from: 0, to: b.t3, name: '粉' },
            { cls: 'tier-yellow', from: b.t3, to: b.t2, name: '黄' },
            { cls: 'tier-green', from: b.t2, to: b.t1, name: '绿' },
            { cls: 'tier-blue', from: b.t1, to: 100, name: '蓝' }
        ];
        bar.innerHTML = segs.map(function(s) {
            var w = s.to - s.from;
            var label = w >= 12 ? (s.from + '–' + s.to) : '';
            return '<div class="score-tier-seg ' + s.cls + '" style="width:' + w + '%">' + label + '</div>';
        }).join('');
    }
    setTierHandlePos('tierHandle1', b.t1);
    setTierHandlePos('tierHandle2', b.t2);
    setTierHandlePos('tierHandle3', b.t3);
}

function setTierHandlePos(id, val) {
    var el = document.getElementById(id);
    if (el) el.style.left = val + '%';
}

// 应用分界值并维持 t3 <= t2 <= t1（互斥且覆盖 0-100）；无变化则跳过刷新
function applyTierBound(idx, v) {
    v = Math.max(0, Math.min(100, Math.round(v)));
    var b = scoreTierBounds, prev;
    if (idx === 1) { prev = b.t1; b.t1 = Math.max(v, b.t2); if (b.t1 === prev) return; }
    else if (idx === 2) { prev = b.t2; b.t2 = Math.min(Math.max(v, b.t3), b.t1); if (b.t2 === prev) return; }
    else if (idx === 3) { prev = b.t3; b.t3 = Math.min(v, b.t2); if (b.t3 === prev) return; }
    renderScoreTierConfig();
    renderPhotos();
}

function startTierDrag(e, idx) {
    e.preventDefault();
    var wrap = document.getElementById('scoreTierBarWrap');
    if (!wrap) return;
    var handle = document.getElementById('tierHandle' + idx);
    if (handle) handle.classList.add('dragging');
    function move(ev) {
        var rect = wrap.getBoundingClientRect();
        if (rect.width <= 0) return;
        var pct = ((ev.clientX - rect.left) / rect.width) * 100;
        applyTierBound(idx, pct);
    }
    function up() {
        document.removeEventListener('pointermove', move);
        document.removeEventListener('pointerup', up);
        if (handle) handle.classList.remove('dragging');
    }
    document.addEventListener('pointermove', move);
    document.addEventListener('pointerup', up);
}

function resetScoreTierBounds() {
    scoreTierBounds = { t1: 80, t2: 60, t3: 40 };
    renderScoreTierConfig();
    renderPhotos();
    showToast('已恢复默认分数区间');
}

// ========== 主题切换：跟随系统 / 浅色 / 深色（默认跟随系统） ==========
var themeMode = 'system'; // 'system' | 'light' | 'dark'
var _systemThemeMql = null;

function initTheme() {
    themeMode = 'system';
    if (window.matchMedia) {
        _systemThemeMql = window.matchMedia('(prefers-color-scheme: dark)');
        var onSystemChange = function() { if (themeMode === 'system') applyThemeMode('system'); };
        if (_systemThemeMql.addEventListener) _systemThemeMql.addEventListener('change', onSystemChange);
        else if (_systemThemeMql.addListener) _systemThemeMql.addListener(onSystemChange);
    }
    applyThemeMode('system');
}

function systemPrefersDark() {
    return !!(_systemThemeMql ? _systemThemeMql.matches : (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches));
}

function applyThemeMode(mode) {
    themeMode = mode;
    var html = document.documentElement;
    var effectiveDark = (mode === 'dark') || (mode === 'system' && systemPrefersDark());
    if (effectiveDark) html.setAttribute('data-theme', 'dark');
    else html.removeAttribute('data-theme');

    var btn = document.querySelector('.top-bar-right .icon-btn[title^="主题"]');
    var icon = btn ? btn.querySelector('i') : null;
    if (icon) {
        icon.className = 'fas ' + (mode === 'system' ? 'fa-circle-half-stroke' : (mode === 'dark' ? 'fa-moon' : 'fa-sun'));
    }
    if (btn) btn.title = '主题：' + (mode === 'system' ? '跟随系统' : (mode === 'dark' ? '深色' : '浅色'));
}

// 循环切换：跟随系统 → 浅色 → 深色 → 跟随系统
function toggleTheme() {
    var next = themeMode === 'system' ? 'light' : (themeMode === 'light' ? 'dark' : 'system');
    applyThemeMode(next);
    showToast('主题：' + (next === 'system' ? '跟随系统' : (next === 'dark' ? '深色' : '浅色')));
}

// ========== Toast ==========
function showToast(message, type) {
    type = type || '';
    var container = document.getElementById('toastContainer');
    var toast = document.createElement('div');
    toast.className = 'toast ' + type;
    toast.textContent = message;
    container.appendChild(toast);
    setTimeout(function() {
        toast.classList.add('toast-exit');
        setTimeout(function() { toast.remove(); }, 300);
    }, 3000);
}

// ========== 日期范围选择 ==========
var dateRangeMap = {
    'today': { label: '今天', days: 1 },
    'yesterday': { label: '昨天', days: 2 },
    'last3days': { label: '近3天', days: 3 },
    'near1Week': { label: '近一周', days: 7 },
    'thisWeek': { label: '本周', days: 7, mode: 'week' },
    'lastWeek': { label: '上周', days: 7, mode: 'lastWeek' },
    'last2Weeks': { label: '近两周', days: 14 },
    'near1Month': { label: '近一月', days: 31 },
    'thisMonth': { label: '本月', days: 30, mode: 'month' },
    'lastMonth': { label: '上月', days: 30, mode: 'lastMonth' },
    'last3Months': { label: '近3月', days: 90 },
    'last6Months': { label: '近6月', days: 180 },
    'thisYear': { label: '本年', days: 365, mode: 'year' },
    'lastYear': { label: '去年', days: 365, mode: 'lastYear' },
    'last2Years': { label: '近两年', days: 730 },
    'lastTrip': { label: '最近一次旅行', special: true },
    'holidays': { label: '法定节假日', special: true, holidays: true },
    'allTime': { label: '全部时间', special: true, all: true },
};

function selectDateRange(type, evt) {
    document.querySelectorAll('.date-chip').forEach(function(chip) {
        chip.classList.remove('active');
    });
    var disp = document.getElementById('dateSelectedDisplay');
    var textEl = document.getElementById('dateRangeText');
    if (dateRangeMap[type] && dateRangeMap[type].holidays) {
        if (textEl) textEl.textContent = '春节 · 国庆 · 劳动节';
        if (disp) disp.style.display = 'flex';
        findState.dateRange = { holidays: true };
        findState.dateLabel = '法定节假日';
    } else if (type === 'lastTrip') {
        var tripStart = '2025-08-01';
        var tripEnd = '2025-08-15';
        if (textEl) textEl.textContent = tripStart + ' 至 ' + tripEnd;
        if (disp) disp.style.display = 'flex';
        findState.dateRange = { start: tripStart, end: tripEnd };
        findState.dateLabel = '最近一次旅行';
    } else {
        var range = calculateDateRange(type);
        if (textEl) textEl.textContent = range.start + ' 至 ' + range.end;
        if (disp) disp.style.display = 'flex';
        findState.dateRange = { start: range.start, end: range.end };
        findState.dateLabel = range.label;
    }
    if (evt && evt.target) evt.target.closest('.date-chip').classList.add('active');
    var clr = document.getElementById('findDateClear');
    if (clr) clr.style.display = '';
    runFind();
}

function calculateDateRange(type) {
    var now = new Date();
    var today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    var todayStr = formatDate(today);
    switch(type) {
        case 'today': return { start: todayStr, end: todayStr, label: '今天' };
        case 'yesterday':
            var yesterday = new Date(today);
            yesterday.setDate(yesterday.getDate() - 1);
            return { start: formatDate(yesterday), end: formatDate(yesterday), label: '昨天' };
        case 'last3days':
            var d3 = new Date(today);
            d3.setDate(d3.getDate() - 2);
            return { start: formatDate(d3), end: todayStr, label: '近3天' };
        case 'near1Week':
            var d7 = new Date(today);
            d7.setDate(d7.getDate() - 6);
            return { start: formatDate(d7), end: todayStr, label: '近一周' };
        case 'thisWeek':
            var weekStart = new Date(today);
            weekStart.setDate(today.getDate() - today.getDay());
            return { start: formatDate(weekStart), end: todayStr, label: '本周' };
        case 'lastWeek':
            var lastWeekEnd = new Date(today);
            lastWeekEnd.setDate(today.getDate() - today.getDay() - 1);
            var lastWeekStart = new Date(lastWeekEnd);
            lastWeekStart.setDate(lastWeekEnd.getDate() - 6);
            return { start: formatDate(lastWeekStart), end: formatDate(lastWeekEnd), label: '上周' };
        case 'last2Weeks':
            var d14 = new Date(today);
            d14.setDate(d14.getDate() - 13);
            return { start: formatDate(d14), end: todayStr, label: '近两周' };
        case 'thisMonth':
            var monthStart = new Date(today.getFullYear(), today.getMonth(), 1);
            return { start: formatDate(monthStart), end: todayStr, label: '本月' };
        case 'near1Month':
            var d31 = new Date(today);
            d31.setDate(d31.getDate() - 30);
            return { start: formatDate(d31), end: todayStr, label: '近一月' };
        case 'lastMonth':
            var lastMonthEnd = new Date(today.getFullYear(), today.getMonth(), 0);
            var lastMonthStart = new Date(today.getFullYear(), today.getMonth() - 1, 1);
            return { start: formatDate(lastMonthStart), end: formatDate(lastMonthEnd), label: '上月' };
        case 'last3Months':
            var d90 = new Date(today);
            d90.setMonth(d90.getMonth() - 3);
            return { start: formatDate(d90), end: todayStr, label: '近3月' };
        case 'last6Months':
            var d180 = new Date(today);
            d180.setMonth(d180.getMonth() - 6);
            return { start: formatDate(d180), end: todayStr, label: '近6月' };
        case 'thisYear':
            var yearStart = new Date(today.getFullYear(), 0, 1);
            return { start: formatDate(yearStart), end: todayStr, label: '本年' };
        case 'lastYear':
            var lastYearStart = new Date(today.getFullYear() - 1, 0, 1);
            var lastYearEnd = new Date(today.getFullYear() - 1, 11, 31);
            return { start: formatDate(lastYearStart), end: formatDate(lastYearEnd), label: '去年' };
        case 'last2Years':
            var d730 = new Date(today);
            d730.setFullYear(d730.getFullYear() - 2);
            return { start: formatDate(d730), end: todayStr, label: '近两年' };
        default:
            return { start: formatDate(new Date(1970, 0, 1)), end: todayStr, label: '全部' };
    }
}

function formatDate(date) {
    var y = date.getFullYear();
    var m = String(date.getMonth() + 1).padStart(2, '0');
    var d = String(date.getDate()).padStart(2, '0');
    return y + '-' + m + '-' + d;
}

function clearDateRange() {
    document.querySelectorAll('.date-chip').forEach(function(chip) {
        chip.classList.remove('active');
    });
    var disp = document.getElementById('dateSelectedDisplay');
    if (disp) disp.style.display = 'none';
    var clr = document.getElementById('findDateClear');
    if (clr) clr.style.display = 'none';
    findState.dateRange = null;
    findState.dateLabel = '';
    runFind();
    showToast('已清除时间筛选');
}

// ========== 侧边栏标签云 ==========
function showMoreTags() {
    initSidebarExtraTags();
    areExtraTagsVisible = !areExtraTagsVisible;
    var input = document.getElementById('tagSearch');
    var keyword = input ? input.value.trim().toLowerCase() : '';
    var tagCloud = document.getElementById('tagCloud');
    var moreBtn = document.getElementById('sidebarMoreBtn');

    // 显示/隐藏扩展标签
    document.querySelectorAll('#tagCloud .sidebar-tag-item.extra-tag').forEach(function(item) {
        var tag = item.dataset.tag || '';
        var visible = areExtraTagsVisible;
        if (keyword) { visible = tag.toLowerCase().indexOf(keyword) !== -1; }
        item.style.display = visible ? '' : 'none';
    });

    // 更多：按钮移到最末尾（展开后收起在底部）；收起：按钮回到初始位
    if (moreBtn && tagCloud) {
        tagCloud.appendChild(moreBtn); // 始终追加到最末，展开前已在末尾，展开后新tag插入其前
    }

    var icon = document.getElementById('sidebarMoreIcon');
    var text = document.getElementById('sidebarMoreText');
    if (icon) icon.className = areExtraTagsVisible ? 'fas fa-chevron-up' : 'fas fa-chevron-down';
    if (text) text.textContent = areExtraTagsVisible ? '收起' : '更多';
}
// ========== 删除确认 ==========
function showDeleteModal(id) {
    if (typeof id === 'number') {
        pendingDeleteIds = [id];
    } else if (selectedPhotos.size > 0) {
        pendingDeleteIds = Array.from(selectedPhotos);
    } else {
        showToast('请先选择照片');
        return;
    }
    pendingDeleteMode = 'normal';
    var titleEl = document.getElementById('deleteModalTitle');
    if (titleEl) titleEl.innerHTML = '<i class="fas fa-exclamation-triangle" style="color:var(--warning)"></i> 确认删除';
    var bodyEl = document.getElementById('deleteModalBody');
    if (bodyEl) bodyEl.innerHTML = '确定要删除选中的 <strong id="deleteCount">' + pendingDeleteIds.length + '</strong> 张照片吗？此操作不可撤销。';
    document.getElementById('deleteModal').classList.add('show');
}

function closeDeleteModal() {
    document.getElementById('deleteModal').classList.remove('show');
    pendingDeleteIds = [];
    pendingDeleteMode = 'normal';
}

function confirmDelete() {
    if (pendingDeleteIds.length === 0) {
        closeDeleteModal();
        return;
    }
    var ids = pendingDeleteIds.slice();
    var inViewer = currentDetailPhotoId && ids.indexOf(currentDetailPhotoId) !== -1;
    var wasEmptyTrash = pendingDeleteMode === 'emptyTrash';
    var deletedCount = hardDeletePhotoIds(ids);
    if (inViewer) closePhotoViewer();
    // 清空废片篓后：自动退出废片篓筛选视图，回到全部照片
    if (wasEmptyTrash && activeQuickFilter === 'trash') {
        activeQuickFilter = 'none';
        document.querySelectorAll('.sidebar-item[data-quick]').forEach(function(item) {
            item.classList.remove('active');
        });
        var clearBtn = document.getElementById('sidebarStatusClear');
        if (clearBtn) clearBtn.style.display = 'none';
        renderPhotos();
    }
    var msg = wasEmptyTrash
        ? ('已清空废片篓，永久删除 ' + deletedCount + ' 项')
        : ('已删除 ' + deletedCount + ' 张照片');
    pendingDeleteIds = [];
    pendingDeleteMode = 'normal';
    showToast(msg);
    closeDeleteModal();
}

// ========== 权重配置 ==========
function openWeightConfig() {
    renderWeightConfig();
    document.getElementById('weightConfigModal').classList.add('show');
}

function closeWeightConfig() {
    document.getElementById('weightConfigModal').classList.remove('show');
}

function renderWeightConfig() {
    var html = '';
    for (var i = 0; i < weightConfig.length; i++) {
        var w = weightConfig[i];
        html += '<div class="weight-item"><div class="weight-item-info"><div class="weight-item-name"><i class="fas ' + w.icon + '"></i> ' + w.name + '</div><div class="weight-item-desc">' + w.desc + '</div></div><div class="weight-item-slider"><input type="range" min="0" max="100" value="' + w.weight + '" oninput="updateWeight(' + i + ', this.value)"><span class="weight-item-value">' + w.weight + '%</span></div></div>';
    }
    document.getElementById('weightConfigList').innerHTML = html;
    updateWeightTotal();
}

function updateWeight(idx, val) {
    weightConfig[idx].weight = parseInt(val, 10);
    document.querySelectorAll('.weight-item-value')[idx].textContent = val + '%';
    updateWeightTotal();
}

function updateWeightTotal() {
    var total = weightConfig.reduce(function(s, w) { return s + w.weight; }, 0);
    document.getElementById('weightTotalValue').textContent = total + '%';
    document.getElementById('weightTotal').classList.toggle('error', total !== 100);
    document.getElementById('weightWarning').style.display = total !== 100 ? 'block' : 'none';
}

function recomputePhotoScoresByWeights() {
    photos.forEach(function(photo) {
        photo.score = calculateCompositeScoreFromDimensions(photo.dimensions);
        photo.comprehensiveScore = photo.score;
        photo.retentionAdvice = buildRetentionAdvice(photo);
    });
    renderPhotos();
    updateFindBanner();
    if (isFindOpen()) runFind();
    if (currentDetailPhotoId && viewerInfoOpen) {
        var photo = photos.find(function(p) { return p.id === currentDetailPhotoId; });
        if (photo) renderViewerContent(photo);
    }
}

function resetWeights() {
    weightConfig.forEach(function(w) {
        if (w.id === 'aesthetics' || w.id === 'technical') w.weight = 30;
        else if (w.id === 'content') w.weight = 15;
        else if (w.id === 'emotion' || w.id === 'rarity') w.weight = 10;
        else w.weight = 5;
    });
    recomputePhotoScoresByWeights();
    renderWeightConfig();
    showToast('已恢复默认权重');
}

function saveWeights() {
    if (weightConfig.reduce(function(s, w) { return s + w.weight; }, 0) !== 100) {
        showToast('权重总和需等于 100%', 'warning');
        return;
    }
    recomputePhotoScoresByWeights();
    closeWeightConfig();
    showToast('权重配置已保存');
}

// ========== 提示词配置 ==========
function openPromptConfig() {
    renderPromptConfig();
    document.getElementById('promptConfigModal').classList.add('show');
}

function closePromptConfig() {
    document.getElementById('promptConfigModal').classList.remove('show');
}

function escapeHtml(text) {
    return String(text || '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
}

function renderPromptConfig() {
    var html = '';
    for (var i = 0; i < promptTasks.length; i++) {
        var t = promptTasks[i];
        var limitText = t.outputLimit ? '<div class="prompt-task-limit">输出上限：' + t.outputLimit + ' 字</div>' : '';
        if (t.locked) {
            html += '<div class="prompt-task-item prompt-task-expandable locked" data-task-id="' + t.id + '"><div class="prompt-task-header"><div class="prompt-task-name"><i class="fas fa-lock"></i> ' + t.name + '<span class="prompt-task-badge locked">' + t.badge + '</span></div><span class="prompt-task-lock-note">不可编辑 / 不可自定义</span></div><div class="prompt-task-content show"><textarea readonly>' + escapeHtml(t.prompt) + '</textarea>' + limitText + '</div></div>';
        } else {
            html += '<div class="prompt-task-item prompt-task-expandable" data-task-id="' + t.id + '"><div class="prompt-task-header"><div class="prompt-task-name"><i class="fas fa-robot"></i> ' + t.name + '<span class="prompt-task-badge">' + t.badge + '</span></div><button type="button" class="prompt-task-toggle" onclick="togglePrompt(this)"><i class="fas fa-chevron-down"></i> 编辑</button></div><div class="prompt-task-content"><textarea>' + escapeHtml(t.prompt) + '</textarea>' + limitText + '</div></div>';
        }
    }
    document.getElementById('promptTaskList').innerHTML = html;
}

function togglePrompt(btn) {
    var el = btn.closest('.prompt-task-item').querySelector('.prompt-task-content');
    el.classList.toggle('show');
    btn.innerHTML = el.classList.contains('show') ? '<i class="fas fa-chevron-up"></i> 收起' : '<i class="fas fa-chevron-down"></i> 编辑';
}

function savePrompts() {
    document.querySelectorAll('#promptTaskList .prompt-task-item').forEach(function(item) {
        var taskId = item.dataset.taskId;
        var task = promptTasks.find(function(t) { return t.id === taskId; });
        if (!task || task.locked) return;
        var textarea = item.querySelector('textarea');
        if (textarea) {
            task.prompt = textarea.value.trim();
        }
    });
    closePromptConfig();
    showToast('提示词配置已保存（锁定任务除外）');
}

document.addEventListener('keydown', function(e) {
    if ((e.metaKey || e.ctrlKey) && (e.key === 'k' || e.key === 'K')) {
        e.preventDefault();
        if (isFindOpen()) { closeFind(); } else { openFind(); }
        return;
    }
    // 照片查看器快捷键
    var viewer = document.getElementById('photoViewer');
    var viewerOpen = viewer && viewer.classList.contains('show');
    if (viewerOpen) {
        // ⌘D / Ctrl+D：直接删除（无二次确认）
        if ((e.metaKey || e.ctrlKey) && (e.key === 'd' || e.key === 'D')) {
            e.preventDefault();
            deleteCurrentPhoto();
            return;
        }
        if (e.metaKey || e.ctrlKey) return; // 其余组合键不处理
        if (e.key === 'Escape') { closePhotoViewer(); return; }
        if (e.key === 'i' || e.key === 'I') { e.preventDefault(); toggleViewerInfo(); return; }
        if (e.key === 'ArrowLeft')  { e.preventDefault(); navigateViewer(-1); return; }
        if (e.key === 'ArrowRight') { e.preventDefault(); navigateViewer(1);  return; }
        if (e.key === 't' || e.key === 'T') { e.preventDefault(); moveCurrentToTrash(); return; }
        if (e.key === 'f' || e.key === 'F') { e.preventDefault(); toggleFavoriteCurrent(); return; }
        if (e.key === ' ') { // 空格：视频 / Live 播放暂停
            var cur = photos.find(function(p) { return p.id === currentDetailPhotoId; });
            if (cur && (cur.mediaType === 'video' || cur.mediaType === 'live')) {
                e.preventDefault();
                toggleViewerPlayback();
            }
            return;
        }
        return;
    }
    if (e.key === 'Escape') {
        // 优先关闭层级更高的模态框（删除/权重/提示词）
        if (document.querySelector('.modal-overlay.show')) {
            closeDeleteModal();
            closeWeightConfig();
            closePromptConfig();
            return;
        }
        if (isFindOpen()) { closeFind(); return; }
        // 时间线搜索框：ESC 清除搜索词并失焦
        var tlInput = document.getElementById('tlSearchInput');
        if (tlInput && document.activeElement === tlInput && _tlSearchQuery) {
            clearTimelineSearch();
            tlInput.blur();
            return;
        }
    }
});

document.addEventListener('DOMContentLoaded', init);
