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
var currentDateRange = null;
var currentFilter = 'all';
var scoreFilterOperator = 'gt';
var scoreThreshold = 60;
var activeSidebarTag = 'all';
var activeQuickFilter = 'none';
var activeFilterOptions = {
    isProDevice: false,
    isProEdited: false,
    isDuplicate: false,
    isNewMonth: false,
    isICloud: false
};
var isAdvancedFilterApplied = false;
var currentModel = 'Qwen3-VL-4B';
var pendingDeleteIds = [];
var firstAnalysisStrategies = ['仅今年', '近三年', '全量'];
var firstAnalysisStrategyIndex = 0;
var currentSortMode = 'dateDesc';
var currentSearchQuery = '';
var currentSearchResults = [];
var currentDetailPhotoId = null;
var scoreBadgeMode = 'aesthetic';
var scoreFilterMetric = 'aesthetics';

var scoreMetricLabels = {
    aesthetics: '美学评分',
    composite: '综合评分',
    technical: '技术质量',
    content: '内容价值',
    emotion: '情感价值',
    rarity: '稀有性',
    uniqueness: '独特性'
};
var hiddenSidebarTags = [
    { tag: '宠物', icon: 'fa-paw', count: 7 },
    { tag: '夜景', icon: 'fa-moon', count: 6 },
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
        isProEdited: Math.random() < 0.25,
        isDuplicate: isDuplicate,
        duplicateGroup: duplicateGroup,
        duplicateRank: isDuplicate ? (Math.floor(Math.random() * 3) + 1) : null,
        isNewMonth: Math.random() < 0.2,
        isICloud: isICloud,
        isFavorite: Math.random() < 0.3,
        dimensions: dimensions,
        contentDescription: contentDescription,
        photoDiary: photoDiary
    });
    photos[i - 1].retentionAdvice = buildRetentionAdvice(photos[i - 1]);
}

// ========== 初始化 ==========
function init() {
    initNavigation();
    initSidebarExtraTags();
    initSidebarTagSearch();
    initTimelineYearOptions();
    renderPhotos();
    renderReports();
    renderSearchPage();
    initSidebarCollapse();
    updateAnalysisProgressUI();
    updateBadgeScoreModeDisplay();
    updateScoreFilterHint();
    updateFilterPreviewCount();
    updateModelButtons();
}

// ========== 侧边栏折叠 ==========
var sidebarVisible = true;
function initSidebarCollapse() {
    var toggleBtn = document.getElementById('sidebarToggle');
    if (toggleBtn) {
        toggleBtn.addEventListener('click', function() {
            sidebarVisible = !sidebarVisible;
            var sidebar = document.getElementById('sidebar');
            if (sidebar) {
                sidebar.classList.toggle('collapsed', !sidebarVisible);
            }
            toggleBtn.classList.toggle('rotated', !sidebarVisible);
        });
    }
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
    var moreBtn = tagCloud.querySelector('.sidebar-tag-more');
    hiddenSidebarTags.forEach(function(item) {
        var el = document.createElement('span');
        el.className = 'sidebar-tag-item extra-tag';
        el.dataset.tag = item.tag;
        el.style.display = 'none';
        el.innerHTML = '<i class="fas ' + item.icon + '"></i> ' + item.tag + ' <span class="count">' + item.count + '</span>';
        el.onclick = function() { toggleSidebarTag(el); };
        tagCloud.insertBefore(el, moreBtn);
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
    isAdvancedFilterApplied = false;
    updateFilterPreviewCount();
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
    isAdvancedFilterApplied = false;
    if (currentPage !== 'photos') navigateToPage('photos');
    selectedPhotos.clear();
    updateFilterPreviewCount();
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
    if (page === 'search') renderSearchPage();
    if (page === 'reports') renderReports();
    if (page === 'filter') renderFilterPage();
    if (page === 'settings') renderSettings();
    if (page === 'search') {
        window.setTimeout(function() {
            var input = document.getElementById('searchInput');
            if (input) input.focus();
        }, 0);
    }

    // 侧边栏
    var sidebar = document.getElementById('sidebar');
    var sidebarToggle = document.getElementById('sidebarToggle');
    if (page === 'photos') {
        sidebar.style.display = '';
        sidebarToggle.style.display = '';
    } else {
        sidebar.style.display = 'none';
        sidebarToggle.style.display = 'none';
    }
}

function getVisiblePhotos() {
    var list = getBasePhotosForFilter();
    if (isAdvancedFilterApplied) {
        list = applyAdvancedFilters(list);
    }
    if (currentSortMode === 'scoreDesc') {
        list.sort(function(a, b) { return b.score - a.score; });
    } else if (currentSortMode === 'scoreAsc') {
        list.sort(function(a, b) { return a.score - b.score; });
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

function applyAdvancedFilters(list) {
    return list.filter(function(photo) {
        if (!matchesScoreFilter(photo)) return false;

        if (currentDateRange) {
            if (currentDateRange.holidays) {
                var month = new Date(photo.date).getMonth() + 1;
                if ([1, 5, 10].indexOf(month) === -1) return false;
            } else if (currentDateRange.start && currentDateRange.end) {
                if (photo.date < currentDateRange.start || photo.date > currentDateRange.end) return false;
            }
        }

        if (activeFilterOptions.isProDevice && !photo.isProDevice) return false;
        if (activeFilterOptions.isProEdited && !photo.isProEdited) return false;
        if (activeFilterOptions.isDuplicate && !photo.isDuplicate) return false;
        if (activeFilterOptions.isNewMonth && !photo.isNewMonth) return false;
        if (activeFilterOptions.isICloud && !photo.isICloud) return false;
        return true;
    });
}

// ========== 照片网格 ==========
function getScoreClass(score) {
    return score >= 80 ? 'high' : score >= 60 ? 'medium' : 'low';
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

// ========== 搜索 ==========
function renderSearchPage() {
    renderHotSearchSuggestions();
    renderSearchResults(currentSearchResults, currentSearchQuery);
}

function pickRandomHotSearches(limit) {
    var shuffled = hotSearchPool.slice().sort(function() { return Math.random() - 0.5; });
    return shuffled.slice(0, limit);
}

function renderHotSearchSuggestions() {
    var container = document.getElementById('hotSearchList');
    if (!container) return;
    var items = pickRandomHotSearches(3);
    container.innerHTML = items.map(function(item) {
        return '<div class="suggestion-item" onclick="applySearchSuggestion(\'' + item.text.replace(/'/g, '\\\'') + '\')"><i class="fas ' + item.icon + '"></i><span>' + item.text + '</span></div>';
    }).join('');
}

function showSearchSuggestions() {
    renderHotSearchSuggestions();
    var panel = document.getElementById('searchSuggestions');
    if (panel) panel.classList.add('show');
}

function hideSearchSuggestions() {
    window.setTimeout(function() {
        var panel = document.getElementById('searchSuggestions');
        if (panel) panel.classList.remove('show');
    }, 120);
}

function applySearchSuggestion(text) {
    var input = document.getElementById('searchInput');
    if (!input) return;
    input.value = text;
    handleSearchInput();
}

function clearSearch() {
    currentSearchQuery = '';
    currentSearchResults = [];
    var input = document.getElementById('searchInput');
    if (input) input.value = '';
    var clearBtn = document.getElementById('searchClear');
    if (clearBtn) clearBtn.style.display = 'none';
    renderSearchResults([], '');
    showToast('已清空搜索条件');
}

function handleSearchInput() {
    var input = document.getElementById('searchInput');
    if (!input) return;
    var query = input.value.trim();
    currentSearchQuery = query;
    var clearBtn = document.getElementById('searchClear');
    if (clearBtn) clearBtn.style.display = query ? '' : 'none';
    if (!query) {
        currentSearchResults = [];
        renderSearchResults([], '');
        return;
    }
    currentSearchResults = searchPhotos(query);
    renderSearchResults(currentSearchResults, query);
}

function searchPhotos(query) {
    var lower = query.toLowerCase();
    var scoreRule = parseScoreRule(query);
    var yearRule = parseYearRule(query);
    var oneMonthRule = lower.indexOf('近一月') !== -1 || lower.indexOf('最近一个月') !== -1;
    var tagRule = parseTagRule(query);
    var locationRule = parseLocationRule(query);
    return photos.filter(function(photo) {
        if (scoreRule) {
            var targetScore = scoreRule.metric === 'aesthetic' ? photo.aestheticScore : photo.score;
            if (scoreRule.op === 'gt' && !(targetScore > scoreRule.value)) return false;
            if (scoreRule.op === 'lt' && !(targetScore < scoreRule.value)) return false;
        }
        if (yearRule && photo.date.indexOf(String(yearRule)) !== 0) return false;
        if (oneMonthRule && !photo.isNewMonth) return false;
        if (tagRule.length > 0) {
            var hitTag = tagRule.some(function(tag) { return photo.tags.indexOf(tag) !== -1; });
            if (!hitTag) return false;
        }
        if (locationRule && photo.location.indexOf(locationRule) === -1) return false;
        if (!scoreRule && !yearRule && !oneMonthRule && tagRule.length === 0 && !locationRule) {
            var textBlob = (photo.tags.join(' ') + ' ' + photo.location + ' ' + photo.date + ' 综合评分' + photo.score + ' 美学评分' + photo.aestheticScore).toLowerCase();
            if (textBlob.indexOf(lower) === -1) return false;
        }
        return true;
    }).sort(function(a, b) { return b.date.localeCompare(a.date); });
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

function renderSearchResults(results, query) {
    var summary = document.getElementById('searchSummary');
    var container = document.getElementById('searchResults');
    if (!summary || !container) return;
    if (!query) {
        summary.textContent = '输入关键词开始搜索';
        container.innerHTML = '';
        return;
    }
    summary.textContent = '“' + query + '” 共匹配到 ' + results.length + ' 张照片';
    if (results.length === 0) {
        container.innerHTML = '<div class="timeline-empty"><i class="fas fa-search"></i><h3>暂无匹配结果</h3><p>试试地点、时间或分数关键词</p></div>';
        return;
    }
    container.innerHTML = results.map(function(photo) {
        return '<div class="search-result-card"><img src="' + photo.url + '" alt="搜索结果"><div class="search-result-info"><div class="search-result-title">综合 ' + photo.score + ' · 美学 ' + photo.aestheticScore + ' · ' + photo.location + '</div><div class="search-result-meta">' + photo.date + ' · ' + photo.tags.join(' / ') + '</div></div><button class="btn btn-secondary search-open-btn" onclick="openPhotoFromSearch(' + photo.id + ')"><i class="fas fa-location-crosshairs"></i> 定位</button></div>';
    }).join('');
}

function openPhotoFromSearch(id) {
    activeSidebarTag = 'all';
    activeQuickFilter = 'none';
    isAdvancedFilterApplied = false;
    document.querySelectorAll('#tagCloud .sidebar-tag-item').forEach(function(item) {
        item.classList.toggle('active', item.dataset.tag === 'all');
    });
    document.querySelectorAll('.sidebar-item[data-quick]').forEach(function(item) {
        item.classList.remove('active');
    });
    selectedPhotos.clear();
    navigateToPage('photos');
    renderPhotos();
    updateMultiSelectToolbar();
    openPhotoDetail(id);
    showToast('已定位到照片 #' + id + '，并打开详情');
}

// ========== 筛选页 ==========
function renderFilterPage() {
    document.querySelectorAll('.score-dimension-chip').forEach(function(chip) {
        chip.classList.toggle('active', chip.dataset.metric === scoreFilterMetric);
    });
    updateScoreFilterHint();
    updateFilterPreviewCount();
}

function setScoreFilterMetric(metric, evt) {
    scoreFilterMetric = metric;
    document.querySelectorAll('.score-dimension-chip').forEach(function(chip) {
        chip.classList.toggle('active', chip.dataset.metric === metric);
    });
    isAdvancedFilterApplied = false;
    updateScoreFilterHint();
    updateFilterPreviewCount();
}

function setScoreOperator(op, evt) {
    scoreFilterOperator = op;
    document.querySelectorAll('.score-op-chip').forEach(function(chip) {
        chip.classList.toggle('active', chip.dataset.op === op);
    });
    isAdvancedFilterApplied = false;
    updateScoreFilterHint();
    updateFilterPreviewCount();
}

function updateSliderValue() {
    var slider = document.getElementById('scoreSlider');
    var input = document.getElementById('scoreInput');
    if (!slider || !input) return;
    var val = parseInt(slider.value, 10);
    scoreThreshold = val;
    input.value = val;
    var display = document.getElementById('scoreDisplay');
    if (display) display.textContent = val;
    isAdvancedFilterApplied = false;
    updateScoreFilterHint();
    updateFilterPreviewCount();
}

function updateSlider() {
    var slider = document.getElementById('scoreSlider');
    var input = document.getElementById('scoreInput');
    if (!slider || !input) return;
    var val = Math.min(100, Math.max(0, parseInt(input.value, 10) || 0));
    scoreThreshold = val;
    slider.value = val;
    input.value = val;
    var display = document.getElementById('scoreDisplay');
    if (display) display.textContent = val;
    isAdvancedFilterApplied = false;
    updateScoreFilterHint();
    updateFilterPreviewCount();
}

function updateScoreSliderVisual() {
    var slider = document.getElementById('scoreSlider');
    if (!slider) return;
    var min = Number(slider.min || 0);
    var max = Number(slider.max || 100);
    var percent = ((scoreThreshold - min) / (max - min)) * 100;
    var activeStart = 'var(--accent-gradient-1)';
    var activeEnd = 'var(--accent-gradient-2)';
    var inactive = 'var(--glass-bg)';
    if (scoreFilterOperator === 'lt') {
        slider.style.background = 'linear-gradient(90deg, ' + activeStart + ' 0%, ' + activeEnd + ' ' + percent + '%, ' + inactive + ' ' + percent + '%, ' + inactive + ' 100%)';
    } else {
        slider.style.background = 'linear-gradient(90deg, ' + inactive + ' 0%, ' + inactive + ' ' + percent + '%, ' + activeStart + ' ' + percent + '%, ' + activeEnd + ' 100%)';
    }
}

function updateScoreFilterHint() {
    var opText = document.getElementById('scoreOpText');
    if (opText) opText.textContent = scoreFilterOperator === 'gt' ? '大于' : '小于';
    var display = document.getElementById('scoreDisplay');
    if (display) display.textContent = scoreThreshold;
    var metricText = document.getElementById('scoreMetricText');
    if (metricText) metricText.textContent = getMetricLabel(scoreFilterMetric);
    updateScoreSliderVisual();
}

function matchesScoreFilter(photo) {
    var metricScore = getMetricScore(photo, scoreFilterMetric);
    if (scoreFilterOperator === 'gt') return metricScore > scoreThreshold;
    return metricScore < scoreThreshold;
}

function updateFilterPreviewCount() {
    var preview = applyAdvancedFilters(getBasePhotosForFilter());
    var countEl = document.getElementById('filterPreviewCount');
    if (countEl) countEl.textContent = preview.length;
    return preview;
}

function previewFilteredPhotos() {
    isAdvancedFilterApplied = true;
    selectedPhotos.clear();
    navigateToPage('photos');
    renderPhotos();
    updateMultiSelectToolbar();
    var count = getVisiblePhotos().length;
    showToast('预览完成：共 ' + count + ' 张照片');
}

function openDeleteModalForFiltered() {
    var preview = updateFilterPreviewCount();
    if (preview.length === 0) {
        showToast('当前筛选无可删除照片', 'warning');
        return;
    }
    pendingDeleteIds = preview.map(function(photo) { return photo.id; });
    var countEl = document.getElementById('deleteCount');
    if (countEl) countEl.textContent = pendingDeleteIds.length;
    document.getElementById('deleteModal').classList.add('show');
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
    var valueEl = document.getElementById('badgeScoreModeValue');
    if (valueEl) {
        valueEl.textContent = scoreBadgeMode === 'composite' ? '综合评分' : '美学评分';
    }
}

function cycleBadgeScoreMode() {
    scoreBadgeMode = scoreBadgeMode === 'aesthetic' ? 'composite' : 'aesthetic';
    updateBadgeScoreModeDisplay();
    renderPhotos();
    var text = scoreBadgeMode === 'composite' ? '综合评分' : '美学评分';
    showToast('角标已切换为：' + text);
}

// ========== 主题切换 ==========
function toggleTheme() {
    var html = document.documentElement;
    var currentTheme = html.getAttribute('data-theme');
    var themeBtn = document.querySelector('.top-bar-right .icon-btn[title="主题切换"] i')
        || document.querySelector('.top-bar-right .icon-btn i.fa-moon, .top-bar-right .icon-btn i.fa-sun');
    if (currentTheme === 'dark') {
        html.removeAttribute('data-theme');
        if (themeBtn) themeBtn.className = 'fas fa-moon';
    } else {
        html.setAttribute('data-theme', 'dark');
        if (themeBtn) themeBtn.className = 'fas fa-sun';
    }
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
    if (dateRangeMap[type].all) {
        document.getElementById('dateSelectedDisplay').style.display = 'none';
        currentDateRange = null;
        if (evt && evt.target) evt.target.closest('.date-chip').classList.add('active');
        isAdvancedFilterApplied = false;
        updateFilterPreviewCount();
        showToast('已选择全部时间');
        return;
    }
    if (dateRangeMap[type].holidays) {
        document.getElementById('dateRangeText').textContent = '春节 · 国庆 · 劳动节';
        document.getElementById('dateSelectedDisplay').style.display = 'flex';
        currentDateRange = { holidays: true };
        if (evt && evt.target) evt.target.closest('.date-chip').classList.add('active');
        isAdvancedFilterApplied = false;
        updateFilterPreviewCount();
        showToast('已选择：法定节假日');
        return;
    }
    if (dateRangeMap[type].special && type === 'lastTrip') {
        var tripStart = '2025-08-01';
        var tripEnd = '2025-08-15';
        document.getElementById('dateRangeText').textContent = tripStart + ' 至 ' + tripEnd;
        document.getElementById('dateSelectedDisplay').style.display = 'flex';
        currentDateRange = { start: tripStart, end: tripEnd };
        if (evt && evt.target) evt.target.closest('.date-chip').classList.add('active');
        isAdvancedFilterApplied = false;
        updateFilterPreviewCount();
        showToast('已选择：最近一次旅行 (' + tripStart + ' 至 ' + tripEnd + ')');
        return;
    }
    var range = calculateDateRange(type);
    document.getElementById('dateRangeText').textContent = range.start + ' 至 ' + range.end;
    currentDateRange = range;
    document.getElementById('dateSelectedDisplay').style.display = 'flex';
    if (evt && evt.target) evt.target.closest('.date-chip').classList.add('active');
    isAdvancedFilterApplied = false;
    updateFilterPreviewCount();
    showToast('已选择：' + range.label);
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
    document.getElementById('dateSelectedDisplay').style.display = 'none';
    currentDateRange = null;
    isAdvancedFilterApplied = false;
    updateFilterPreviewCount();
    showToast('已清除日期筛选');
}

// ========== 筛选标签云 ==========
function toggleTag(el) {
    el.classList.toggle('active');
    showToast('已筛选: ' + el.textContent.trim());
}

function toggleTagSort() { showToast('切换排序方式'); }
function showMoreTags() {
    initSidebarExtraTags();
    areExtraTagsVisible = !areExtraTagsVisible;
    var input = document.getElementById('tagSearch');
    var keyword = input ? input.value.trim().toLowerCase() : '';
    document.querySelectorAll('#tagCloud .sidebar-tag-item.extra-tag').forEach(function(item) {
        var tag = item.dataset.tag || '';
        var visible = areExtraTagsVisible;
        if (keyword) {
            visible = tag.toLowerCase().indexOf(keyword) !== -1;
        }
        item.style.display = visible ? '' : 'none';
    });
    var moreBtn = document.querySelector('#tagCloud .sidebar-tag-more');
    if (moreBtn) {
        moreBtn.textContent = areExtraTagsVisible ? '收起' : '更多...';
    }
    showToast(areExtraTagsVisible ? '已展示更多标签' : '已收起扩展标签');
}
function toggleFilterChip(el) {
    el.classList.toggle('active');
    var key = el.dataset.filterKey;
    if (key && Object.prototype.hasOwnProperty.call(activeFilterOptions, key)) {
        activeFilterOptions[key] = el.classList.contains('active');
    }
    isAdvancedFilterApplied = false;
    updateFilterPreviewCount();
    showToast('已切换筛选: ' + el.textContent.trim());
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
    updateFilterPreviewCount();
    renderPhotos();
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
    if (currentSearchQuery) {
        currentSearchResults = searchPhotos(currentSearchQuery);
    }
    renderPhotos();
    renderSearchPage();
    updateFilterPreviewCount();
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
        navigateToPage('search');
        var input = document.getElementById('searchInput');
        if (input) {
            input.focus();
            input.select();
        }
        showSearchSuggestions();
        return;
    }
    if (e.key === 'Escape') {
        closeDeleteModal();
        closeWeightConfig();
        closePromptConfig();
        closePhotoDetail();
    }
});

document.addEventListener('DOMContentLoaded', init);
