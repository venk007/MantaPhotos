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
var timelineData = [
    { date: '2025年8月', title: '三亚之旅', photos: ['https://picsum.photos/seed/t1/200/150', 'https://picsum.photos/seed/t2/200/150', 'https://picsum.photos/seed/t3/200/150', 'https://picsum.photos/seed/t4/200/150'], isTravel: true },
    { date: '2025年7月', title: '张家界登山', photos: ['https://picsum.photos/seed/t5/200/150', 'https://picsum.photos/seed/t6/200/150', 'https://picsum.photos/seed/t7/200/150'], isTravel: true },
    { date: '2025年6月', title: '北京美食周', photos: ['https://picsum.photos/seed/t8/200/150', 'https://picsum.photos/seed/t9/200/150'], isTravel: false },
    { date: '2025年5月', title: '宠物日常', photos: ['https://picsum.photos/seed/t10/200/150', 'https://picsum.photos/seed/t11/200/150', 'https://picsum.photos/seed/t12/200/150', 'https://picsum.photos/seed/t13/200/150'], isTravel: false },
    { date: '2024年12月', title: '圣诞聚会', photos: ['https://picsum.photos/seed/t14/200/150', 'https://picsum.photos/seed/t15/200/150', 'https://picsum.photos/seed/t16/200/150'], isTravel: false },
    { date: '2024年10月', title: '厦门秋游', photos: ['https://picsum.photos/seed/t17/200/150', 'https://picsum.photos/seed/t18/200/150'], isTravel: true },
];

// ========== 状态管理 ==========
var currentPage = 'photos';
var selectMode = false;
var selectedPhotos = new Set();
var activeSidebarTag = 'all';
var activeQuickFilter = 'none';
var currentModel = 'Qwen3-VL-4B';
var pendingDeleteIds = [];
var firstAnalysisStrategies = ['仅今年', '近三年', '全量'];
var firstAnalysisStrategyIndex = 0;
var currentSortMode = 'dateDesc';
var currentDetailPhotoId = null;
var scoreBadgeMode = 'aesthetic';

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
        favorite: false,
        isProDevice: false,
        isProEdited: false,
        isDuplicate: false,
        isNewMonth: false,
        isICloud: false
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
    { tag: '亲子', icon: 'fa-users', count: 3 },
    { tag: '运动', icon: 'fa-person-running', count: 5 },
    { tag: '花草', icon: 'fa-seedling', count: 4 },
    { tag: '海边', icon: 'fa-water', count: 2 }
];
var areExtraTagsVisible = false;
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
var tagPool = ['风景', '人物', '建筑', '美食', '旅行', '宠物', '夜景'];
var locationPool = ['北京', '上海', '厦门', '南京', '杭州', '三亚', '成都', '西安', '广州', '深圳'];
var friendPool = ['小林', '阿泽', 'Mia', '可可', '安妮', '家人'];
var peoplePool = ['小林', '阿泽', 'Mia', '可可', '安妮'];
var moodPool = ['轻松', '兴奋', '平静', '满足', '惊喜', '治愈'];
var beforeActivityPool = ['早起散步', '在咖啡店规划路线', '逛了当地早市', '从博物馆出来', '刚结束一段车程'];
var afterActivityPool = ['去附近餐馆补给', '继续下一段城市漫步', '回到酒店整理照片', '和朋友复盘当天行程', '赶去看夜景'];
var datePool = [
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
    if (photo.score < 60 || photo.isDuplicate) {
        return { level: 'clean', text: '分数偏低或存在重复，建议进入待清理列表。' };
    }
    return { level: 'review', text: '质量中等，建议人工复核后再决定是否保留。' };
}

for (var i = 1; i <= 48; i++) {
    var firstTag = tagPool[Math.floor(Math.random() * tagPool.length)];
    var secondTag = tagPool[Math.floor(Math.random() * tagPool.length)];
    var isProDevice = Math.random() < 0.35;
    var isICloud = Math.random() < 0.45;
    var isDuplicate = Math.random() < 0.2;
    var photoDate = datePool[Math.floor(Math.random() * datePool.length)];
    var photoLocation = locationPool[Math.floor(Math.random() * locationPool.length)];
    var isScreenshot = Math.random() < 0.12;
    var baseScore = Math.floor(Math.random() * 35) + 55;
    var aestheticsScore = isScreenshot ? 0 : clampScore(baseScore + (Math.random() * 24 - 12));
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
    var tags = isScreenshot ? ['截图', firstTag] : [firstTag, secondTag];
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
    var lastScrollTop = 0;

    mainContent.addEventListener('scroll', function() {
        var scrollTop = mainContent.scrollTop;
        var delta = scrollTop - lastScrollTop;
        lastScrollTop = scrollTop;

        // 任意方向滚动超过 10px 且侧边栏当前可见 → 隐藏
        if (Math.abs(delta) >= 10 && sidebarVisible) {
            _preScrollSidebarVisible = true;
            _scrollHiddenByScroll = true;
            setSidebarVisible(false);
        }

        // 滚动停止检测（200ms 防抖）
        clearTimeout(_scrollDebounceTimer);
        _scrollDebounceTimer = setTimeout(function() {
            // 停止后：若是被滚动隐藏的，延迟 500ms 恢复
            if (_scrollHiddenByScroll && _preScrollSidebarVisible && !sidebarVisible) {
                setTimeout(function() {
                    if (_scrollHiddenByScroll && !sidebarVisible) {
                        _scrollHiddenByScroll = false;
                        setSidebarVisible(true);
                    }
                }, 500);
            }
        }, 200);
    });
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
    var tag = el.dataset.tag || 'all';
    activeSidebarTag = tag;
    if (tag === 'all') {
        activeQuickFilter = 'none';
        document.querySelectorAll('.sidebar-item[data-quick]').forEach(function(item) {
            item.classList.remove('active');
        });
    }
    document.querySelectorAll('#tagCloud .sidebar-tag-item').forEach(function(item) {
        item.classList.toggle('active', item === el);
    });
    if (currentPage !== 'photos') navigateToPage('photos');
    findAppliedToWall = false;
    updateFindBanner();
    renderPhotos();
    updateMultiSelectToolbar();
    showToast(tag === 'all' ? '已切换：全部标签' : ('已切换标签：' + tag));
}

function applyQuickFilter(type) {
    activeQuickFilter = type;
    activeSidebarTag = 'all';
    document.querySelectorAll('#tagCloud .sidebar-tag-item').forEach(function(item) {
        item.classList.toggle('active', item.dataset.tag === 'all');
    });
    document.querySelectorAll('.sidebar-item[data-quick]').forEach(function(item) {
        item.classList.toggle('active', item.dataset.quick === type);
    });
    findAppliedToWall = false;
    if (currentPage !== 'photos') navigateToPage('photos');
    selectedPhotos.clear();
    updateFindBanner();
    renderPhotos();
    updateMultiSelectToolbar();
    var textMap = {
        favorite: '我的收藏',
        waste: '废片篓',
        highScore: '高分照片'
    };
    showToast('已应用快捷筛选：' + (textMap[type] || '全部'));
}

function updateAnalysisProgressUI() {
    var card = document.getElementById('aiProgressCard');
    var statusEl = document.getElementById('aiProgressStatus');
    var stateIcon = document.getElementById('aiProgressStateIcon');
    var pauseIcon = document.getElementById('aiPauseBtnIcon');
    var pauseText = document.getElementById('aiPauseBtnText');
    if (!card || !statusEl || !stateIcon || !pauseIcon || !pauseText) return;

    card.classList.remove('state-running', 'state-paused', 'state-stopped');
    if (analysisState === 'paused') {
        card.classList.add('state-paused');
        statusEl.textContent = '已暂停';
        stateIcon.className = 'fas fa-pause-circle';
        pauseIcon.className = 'fas fa-play';
        pauseText.textContent = '继续';
        return;
    }
    if (analysisState === 'stopped') {
        card.classList.add('state-stopped');
        statusEl.textContent = '已停止';
        stateIcon.className = 'fas fa-stop-circle';
        pauseIcon.className = 'fas fa-play';
        pauseText.textContent = '开始';
        return;
    }
    card.classList.add('state-running');
    statusEl.textContent = '分析中';
    stateIcon.className = 'fas fa-spinner fa-spin';
    pauseIcon.className = 'fas fa-pause';
    pauseText.textContent = '暂停';
}

function startAnalysis() {
    analysisState = 'running';
    updateAnalysisProgressUI();
    showToast('AI 分析已启动');
}

function togglePauseAnalysis() {
    if (analysisState === 'running') {
        analysisState = 'paused';
        updateAnalysisProgressUI();
        showToast('分析已暂停');
        return;
    }
    analysisState = 'running';
    updateAnalysisProgressUI();
    showToast('分析继续进行');
}

function stopAnalysis() {
    analysisState = 'stopped';
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
    if (activeSidebarTag !== 'all') {
        list = list.filter(function(photo) {
            return photo.tags.indexOf(activeSidebarTag) !== -1;
        });
    }
    if (activeQuickFilter === 'favorite') {
        list = list.filter(function(photo) { return photo.isFavorite; });
    } else if (activeQuickFilter === 'waste') {
        list = list.filter(function(photo) { return photo.score < 60 || photo.isDuplicate; });
    } else if (activeQuickFilter === 'highScore') {
        list = list.filter(function(photo) { return photo.score >= 85; });
    }
    return list;
}

// 统一查找过滤：自然语言 query 与所有属性芯片以 AND 叠加
function computeFindFilter(list) {
    var s = findState;
    return list.filter(function(photo) {
        if (s.mediaTypes.length && s.mediaTypes.indexOf(photo.mediaType) === -1) return false;
        if (s.devices.length && s.devices.indexOf(photo.deviceType) === -1) return false;
        if (s.favorite && !photo.isFavorite) return false;
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
var scoreTierBounds = { t1: 80, t2: 60, t3: 40 };

function getScoreClass(score) {
    if (score >= scoreTierBounds.t1) return 'tier-blue';
    if (score >= scoreTierBounds.t2) return 'tier-green';
    if (score >= scoreTierBounds.t3) return 'tier-yellow';
    return 'tier-pink';
}

function renderPhotos() {
    var grid = document.getElementById('photoGrid');
    if (!grid) return;
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
    // 渲染后重新应用尺寸（CSS var 在 grid 元素上，DOM 重建后无需重新设置，但 gap 需要）
    applyGridSize();
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
    if (!photoGrid) return;
    photoGrid.style.gap = gap + 'px';
    var colWidth = 'calc((100% - ' + ((cols - 1) * gap) + 'px) / ' + cols + ')';
    photoGrid.style.setProperty('--photo-col-width', colWidth);
    var radiusMap = { 2: '14px', 4: '12px', 6: '10px', 8: '8px', 12: '6px', 16: '4px', 32: '2px' };
    photoGrid.style.setProperty('--photo-card-radius', radiusMap[cols] || '8px');
    // 分数标签：用户关闭则始终隐藏；缩放到最后两级（缩略图过小）也隐藏
    var hideByZoom = gridSizeLevel >= gridColLevels.length - 2;
    photoGrid.classList.toggle('hide-score', !scoreBadgeVisible || hideByZoom);
    // scale pulse：0.995→1，0.1s，走 compositor 线程，不触发 layout
    photoGrid.style.transition = 'none';
    photoGrid.style.transform = 'scale(0.995)';
    requestAnimationFrame(function() {
        photoGrid.style.transition = 'transform 0.1s ease-out';
        photoGrid.style.transform = 'scale(1)';
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


function openPhotoDetail(id) {
    var photo = photos.find(function(item) { return item.id === id; });
    if (!photo) return;
    currentDetailPhotoId = id;
    var modal = document.getElementById('photoDetailModal');
    if (!modal) return;

    var image = document.getElementById('detailImage');
    if (image) image.src = photo.url;

    var title = document.getElementById('detailTitle');
    if (title) title.textContent = '照片 #' + photo.id + ' · 综合 ' + photo.score + ' · 美学 ' + photo.aestheticScore;

    var subtitle = document.getElementById('detailSubtitle');
    if (subtitle) subtitle.textContent = photo.date + ' · ' + photo.location + (photo.isScreenshot ? ' · 截图内容（美学 0 分）' : '');

    var dimensionList = document.getElementById('detailDimensionList');
    if (dimensionList) {
        var dimensions = [
            { name: '美学', value: photo.dimensions.aesthetics },
            { name: '技术', value: photo.dimensions.technical },
            { name: '内容', value: photo.dimensions.content },
            { name: '情感', value: photo.dimensions.emotion },
            { name: '稀有', value: photo.dimensions.rarity },
            { name: '独特', value: photo.dimensions.uniqueness }
        ];
        dimensionList.innerHTML = dimensions.map(function(d) {
            return '<div class="detail-dimension-item"><div class="detail-dimension-head"><span>' + d.name + '</span><strong>' + d.value + '</strong></div><div class="detail-dimension-track"><span class="detail-dimension-fill" style="width:' + d.value + '%"></span></div></div>';
        }).join('');
    }

    var tags = document.getElementById('detailTagList');
    if (tags) {
        tags.innerHTML = photo.tags.map(function(tag) {
            return '<span class="detail-tag">' + tag + '</span>';
        }).join('');
    }

    var duplicateInfo = document.getElementById('detailDuplicateInfo');
    if (duplicateInfo) {
        if (photo.isDuplicate && photo.duplicateGroup) {
            duplicateInfo.innerHTML = '相似组：<strong>' + photo.duplicateGroup + '</strong>（组内质量排名第 ' + photo.duplicateRank + '）';
        } else {
            duplicateInfo.innerHTML = '未命中相似组，当前照片具备独立保留价值。';
        }
    }

    var advice = document.getElementById('detailRetentionAdvice');
    if (advice) {
        advice.className = 'detail-advice ' + photo.retentionAdvice.level;
        advice.textContent = photo.retentionAdvice.text;
    }

    var description = document.getElementById('detailContentDescription');
    if (description) description.textContent = photo.contentDescription || '暂无内容描述。';

    var diary = document.getElementById('detailPhotoDiary');
    if (diary) diary.textContent = photo.photoDiary || '暂无照片回忆。';

    modal.classList.add('show');
}

function closePhotoDetail() {
    var modal = document.getElementById('photoDetailModal');
    if (modal) modal.classList.remove('show');
    currentDetailPhotoId = null;
}

function toggleFavoriteCurrent() {
    if (!currentDetailPhotoId) return;
    var photo = photos.find(function(item) { return item.id === currentDetailPhotoId; });
    if (!photo) return;
    photo.isFavorite = !photo.isFavorite;
    showToast(photo.isFavorite ? '已加入收藏' : '已取消收藏');
}

function deleteCurrentPhoto() {
    if (!currentDetailPhotoId) return;
    showDeleteModal(currentDetailPhotoId);
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
function collectTimelineYears() {
    var years = new Set();
    photos.forEach(function(photo) {
        if (photo.date && photo.date.length >= 4) {
            years.add(photo.date.slice(0, 4));
        }
    });
    timelineData.forEach(function(item) {
        var matched = String(item.date || '').match(/(\d{4})年/);
        if (matched) years.add(matched[1]);
    });
    return Array.from(years).sort(function(a, b) { return Number(a) - Number(b); });
}

function initTimelineYearOptions() {
    var yearSelect = document.getElementById('yearSelect');
    if (!yearSelect) return;
    var years = collectTimelineYears();
    if (years.length === 0) {
        years = [String(new Date().getFullYear())];
    }
    yearSelect.innerHTML = years.map(function(year) {
        return '<option value="' + year + '">' + year + '年</option>';
    }).join('');
    var currentYear = String(new Date().getFullYear());
    if (years.indexOf(currentYear) !== -1) {
        yearSelect.value = currentYear;
    } else {
        yearSelect.value = years[years.length - 1];
    }
}

function getTimelineEventsByYear(year) {
    var fromPreset = timelineData.filter(function(item) {
        return String(item.date).indexOf(year + '年') === 0;
    });
    if (fromPreset.length > 0) return fromPreset;

    var yearPhotos = photos.filter(function(photo) {
        return String(photo.date).indexOf(year + '-') === 0;
    });
    if (yearPhotos.length === 0) return [];

    var monthMap = {};
    yearPhotos.forEach(function(photo) {
        var month = photo.date.slice(5, 7);
        if (!monthMap[month]) {
            monthMap[month] = {
                date: year + '年' + Number(month) + '月',
                title: Number(month) + '月回忆',
                photos: [],
                isTravel: false
            };
        }
        if (monthMap[month].photos.length < 4) {
            monthMap[month].photos.push(photo.url);
        }
        if (photo.tags.indexOf('旅行') !== -1) {
            monthMap[month].isTravel = true;
        }
    });
    return Object.keys(monthMap)
        .sort(function(a, b) { return Number(b) - Number(a); })
        .map(function(monthKey) { return monthMap[monthKey]; });
}

function renderTimeline() {
    var container = document.getElementById('timelineContainer');
    if (!container) return;
    var yearSelect = document.getElementById('yearSelect');
    var year = yearSelect ? yearSelect.value : String(new Date().getFullYear());
    var filtered = getTimelineEventsByYear(year);
    if (filtered.length === 0) {
        container.innerHTML = '<div class="timeline-empty"><i class="fas fa-clock"></i><h3>' + year + ' 年暂无记录</h3><p>切换其他年份查看照片时间线</p></div>';
        return;
    }
    container.innerHTML = filtered.map(function(item) {
        var travelBadge = item.isTravel ? '<span class="travel-event-badge"><i class="fas fa-plane"></i> 旅行</span>' : '';
        return '<div class="timeline-item"><div class="timeline-date">' + item.date + travelBadge + '</div><div class="timeline-title">' + item.title + '</div><div class="timeline-photos">' + item.photos.map(function(url) { return '<img src="' + url + '" class="timeline-photo" alt="照片">'; }).join('') + '</div></div>';
    }).join('');
}

function navigateYear(dir) {
    var sel = document.getElementById('yearSelect');
    if (!sel) return;
    var currentYear = parseInt(sel.value, 10);
    var targetYear = String(currentYear + dir);
    var hasTarget = Array.from(sel.options).some(function(option) {
        return option.value === targetYear;
    });
    if (hasTarget) {
        selectYear(targetYear);
    }
}

function selectYear(y) {
    var sel = document.getElementById('yearSelect');
    if (sel && y) sel.value = String(y);
    renderTimeline();
    var current = sel ? sel.value : String(y || '');
    showToast('已切换到 ' + current + ' 年');
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
var statusDefs = [
    { key: 'favorite', label: '收藏', icon: 'fa-heart' },
    { key: 'isDuplicate', label: '重复/相似', icon: 'fa-copy' },
    { key: 'isNewMonth', label: '近一月新增', icon: 'fa-clock' },
    { key: 'isICloud', label: '已存 iCloud', icon: 'fa-cloud' },
    { key: 'isProDevice', label: '专业设备', icon: 'fa-camera-retro' },
    { key: 'isProEdited', label: '专业软件调整', icon: 'fa-magic' }
];
// 设备来源（多选，匹配 photo.deviceType）。icon 含完整样式前缀（fas/fab）
var deviceDefs = [
    { key: 'Pocket', label: 'Pocket', icon: 'fab fa-get-pocket' },
    { key: '运动相机', label: '运动相机', icon: 'fas fa-person-running' },
    { key: '无人机', label: '无人机', icon: 'fas fa-helicopter' },
    { key: '单反相机', label: '单反相机', icon: 'fas fa-camera' }
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
    document.querySelectorAll('#tagCloud .sidebar-tag-item').forEach(function(item) {
        item.classList.toggle('active', item.dataset.tag === 'all');
    });
    document.querySelectorAll('.sidebar-item[data-quick]').forEach(function(item) {
        item.classList.remove('active');
    });
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
}
function toggleFindMedia(key) {
    var i = findState.mediaTypes.indexOf(key);
    if (i === -1) findState.mediaTypes.push(key); else findState.mediaTypes.splice(i, 1);
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
}
function toggleFindLocation(loc) {
    var i = findState.locations.indexOf(loc);
    if (i === -1) findState.locations.push(loc); else findState.locations.splice(i, 1);
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
}
function toggleFindPerson(person) {
    var i = findState.people.indexOf(person);
    if (i === -1) findState.people.push(person); else findState.people.splice(i, 1);
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
}
function toggleFindTag(tag) {
    var i = findState.tags.indexOf(tag);
    if (i === -1) findState.tags.push(tag); else findState.tags.splice(i, 1);
    renderFindTagChips();
    runFind();
}

function renderFindStatusChips() {
    var c = document.getElementById('findStatusChips');
    if (!c) return;
    c.innerHTML = statusDefs.map(function(s) {
        var active = !!findState[s.key];
        return '<button class="find-chip' + (active ? ' active' : '') + '" onclick="toggleFindStatus(\'' + s.key + '\')"><i class="fas ' + s.icon + '"></i> ' + s.label + '</button>';
    }).join('');
    renderFindDeviceChips();
}
function toggleFindStatus(key) {
    findState[key] = !findState[key];
    renderFindStatusChips();
    runFind();
}
function renderFindDeviceChips() {
    var c = document.getElementById('findDeviceChips');
    if (!c) return;
    c.innerHTML = deviceDefs.map(function(d) {
        var n = countPhotos(function(p) { return p.deviceType === d.key; });
        var active = findState.devices.indexOf(d.key) !== -1;
        return '<button class="find-chip' + (active ? ' active' : '') + '" onclick="toggleFindDevice(\'' + d.key + '\')"><i class="' + d.icon + '"></i> ' + d.label + ' <span class="count">' + n + '</span></button>';
    }).join('');
}
function toggleFindDevice(key) {
    var i = findState.devices.indexOf(key);
    if (i === -1) findState.devices.push(key); else findState.devices.splice(i, 1);
    renderFindDeviceChips();
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
    var countEl = document.getElementById('deleteCount');
    if (countEl) countEl.textContent = pendingDeleteIds.length;
    document.getElementById('deleteModal').classList.add('show');
}

function closeDeleteModal() {
    document.getElementById('deleteModal').classList.remove('show');
    pendingDeleteIds = [];
}

function confirmDelete() {
    if (pendingDeleteIds.length === 0) {
        closeDeleteModal();
        return;
    }
    photos = photos.filter(function(photo) {
        return pendingDeleteIds.indexOf(photo.id) === -1;
    });
    pendingDeleteIds.forEach(function(id) { selectedPhotos.delete(id); });
    if (currentDetailPhotoId && pendingDeleteIds.indexOf(currentDetailPhotoId) !== -1) {
        closePhotoDetail();
    }
    var deletedCount = pendingDeleteIds.length;
    pendingDeleteIds = [];
    renderPhotos();
    updateFindBanner();
    if (isFindOpen()) runFind();
    updateMultiSelectToolbar();
    showToast('已删除 ' + deletedCount + ' 张照片');
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
    if (currentDetailPhotoId) {
        openPhotoDetail(currentDetailPhotoId);
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
    if (e.key === 'Escape') {
        // 优先关闭层级更高的模态框（详情/删除/权重/提示词，z-index 高于查找浮层）
        if (document.querySelector('.modal-overlay.show')) {
            closeDeleteModal();
            closeWeightConfig();
            closePromptConfig();
            closePhotoDetail();
            return;
        }
        if (isFindOpen()) { closeFind(); return; }
    }
});

document.addEventListener('DOMContentLoaded', init);
