// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '生活助手';

  @override
  String get tabToday => '今天';

  @override
  String get tabSchedule => '课表';

  @override
  String get tabDiet => '饮食';

  @override
  String get tabWorkout => '训练';

  @override
  String get tabAi => 'AI 教练';

  @override
  String get commonSave => '保存';

  @override
  String get commonCancel => '取消';

  @override
  String get commonDelete => '删除';

  @override
  String get commonEdit => '编辑';

  @override
  String get commonAdd => '添加';

  @override
  String get commonConfirm => '确定';

  @override
  String get commonGotIt => '知道了';

  @override
  String get commonSkip => '跳过';

  @override
  String get commonRefresh => '刷新';

  @override
  String get commonToday => '今天';

  @override
  String get commonYesterday => '昨天';

  @override
  String get commonTomorrow => '明天';

  @override
  String get commonErrorTitle => '出错了';

  @override
  String get commonGoSettings => '去设置';

  @override
  String get commonSavedToast => '已保存';

  @override
  String get commonDeleteRecordConfirm => '删除这条记录？';

  @override
  String get commonAtLeastOneField => '请至少填写一项';

  @override
  String get commonInvalidNumber => '请输入数字';

  @override
  String commonRangeError(int min, int max) {
    return '范围 $min-$max';
  }

  @override
  String get weekdayMon => '周一';

  @override
  String get weekdayTue => '周二';

  @override
  String get weekdayWed => '周三';

  @override
  String get weekdayThu => '周四';

  @override
  String get weekdayFri => '周五';

  @override
  String get weekdaySat => '周六';

  @override
  String get weekdaySun => '周日';

  @override
  String get mealBreakfast => '早餐';

  @override
  String get mealLunch => '午餐';

  @override
  String get mealDinner => '晚餐';

  @override
  String get mealSnack => '加餐';

  @override
  String get homeQuickRecord => '快速记录';

  @override
  String get homeQuickDiet => '快速记饮食 / 拍照识热量';

  @override
  String get homeQuickWorkout => '快速开始训练 / 记有氧';

  @override
  String get homeQuickWeight => '快速记今日体重';

  @override
  String get homeQuickBus => '查看校车时刻表与换站';

  @override
  String get homeHeroSnapMeal => '拍美食算热量';

  @override
  String get homeHeroStartWorkout => '开始训练计时';

  @override
  String get homeHeroLogWeight => '记今日体重';

  @override
  String get homeHeroAiCoach => 'AI 定制计划';

  @override
  String get homeQuickLogHint => '一句话速记今天吃了什么（如：一碗牛肉面加个蛋）';

  @override
  String get homeAiQuickLog => 'AI速记';

  @override
  String homeStreakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '连续打卡 $count 天',
    );
    return '$_temp0';
  }

  @override
  String get homeStreakKeepGoing => '习惯正在养成，今天也继续保持！';

  @override
  String get homeStreakStartHint => '记录饮食或训练即可点亮今日打卡';

  @override
  String get homeProfilePromptTitle => '完善个人运动与身体问卷';

  @override
  String get homeProfilePromptSub => '30秒填好身高、目标与器械条件，自动计算动态 TDEE';

  @override
  String homeTodayClassesWeek(int week) {
    return '今日课程 · 第 $week 周';
  }

  @override
  String get homeTodayClasses => '今日课程';

  @override
  String get homeAllSchedule => '全部课表';

  @override
  String get homeNoClassesToday => '今天没有课，好好休息或去锻炼吧！';

  @override
  String get homeTodayWorkoutTitle => '今日训练与有氧汇总';

  @override
  String get homeGoWorkout => '去训练';

  @override
  String get homeNoWorkoutToday => '今天还没有训练或有氧记录';

  @override
  String get homeNoWorkoutSub => '训练消耗会自动叠加到今日可摄入热量额度';

  @override
  String get homeStartWorkoutBtn => '开练';

  @override
  String homeStrengthSummary(int count, int sets) {
    return '力量 $count 次（$sets 组）';
  }

  @override
  String homeCardioSummary(String mins) {
    return '有氧 $mins 分钟';
  }

  @override
  String homeWorkoutBurnSummary(String kcal) {
    return '今日活动与训练总消耗约 +$kcal kcal';
  }

  @override
  String get homeBodyStatus => '身体状态';

  @override
  String homeWeightLabel(String weight) {
    return '最近体重 $weight kg';
  }

  @override
  String get homeWeightNotLogged => '尚未记录体重';

  @override
  String homeBodyTargetSub(String goal, String kcal, String protein) {
    return '目标：$goal · 每日建议 $kcal kcal · 蛋白质 ${protein}g';
  }

  @override
  String get homeLogBodyBtn => '记录';

  @override
  String get homeAiCoachBannerTitle => '有问题？问问大肥鱼 AI 教练';

  @override
  String get homeAiCoachBannerSub => '结合你的课表、饮食与训练记录，一键生成今日点评与下餐推荐';

  @override
  String stepTitle(int steps, int goal) {
    return '今日自动步数：$steps / $goal 步';
  }

  @override
  String get stepUnsupported => '当前设备无硬件计步传感器（可在训练页手动记走路/跑步）';

  @override
  String get stepPermissionNeeded => '需要授予「身体活动」权限才能读取手机计步传感器';

  @override
  String stepBurnedSummary(String kcal) {
    return '步数折算消耗 +$kcal kcal（已自动计入今日饮食额度）';
  }

  @override
  String get stepAuthorize => '授权计步';

  @override
  String get weatherClear => '晴朗';

  @override
  String get weatherCloudy => '多云';

  @override
  String get weatherFoggy => '有雾';

  @override
  String get weatherRainy => '有雨';

  @override
  String get weatherSnowy => '降雪';

  @override
  String get weatherShowers => '阵雨';

  @override
  String get weatherThunderstorm => '雷阵雨';

  @override
  String get weatherTipRain => '记得带伞';

  @override
  String get weatherTipHot => '注意防晒补水';

  @override
  String get weatherTipGreat => '适宜出行与运动';

  @override
  String weatherCompactSub(String min, String max, String precip, String tip) {
    return '$min~$max°C · 降水 $precip% · $tip';
  }

  @override
  String get weatherSheetTitle => '天气定位与城市切换（防代理/VPN 跑偏）';

  @override
  String get weatherAutoLocate => '自动 GPS 定位 (6h缓存)';

  @override
  String get weatherSearchCity => '去设置页搜索更多城市';

  @override
  String get dietRemaining => '剩余额度';

  @override
  String get dietExceeded => '超出 kcal';

  @override
  String dietConsumedTarget(String consumed, String target) {
    return '摄入 $consumed / 目标 $target kcal';
  }

  @override
  String get dietEstimatedHint => '（默认估算，点右上角填体重）';

  @override
  String get dietProtein => '蛋白质';

  @override
  String get dietCarbs => '碳水';

  @override
  String get dietFat => '脂肪';

  @override
  String get dietBmr => '基础代谢';

  @override
  String get dietTrainingBurn => '训练消耗';

  @override
  String get dietTodayIntake => '今日摄入';

  @override
  String get dietSurplus => '剩余额度';

  @override
  String get dietScanFood => '拍照识热量';

  @override
  String get dietPickGallery => '相册选图';

  @override
  String get dietAiTextEstimate => '文字估算';

  @override
  String get dietManualAdd => '手动记';

  @override
  String dietEmptyMealHint(String meal) {
    return '还没有$meal记录，点击添加或上方拍美食';
  }

  @override
  String dietDeleteMealConfirm(String name) {
    return '删除「$name」？';
  }

  @override
  String get dietAiAnalyzing => 'AI 正在分析食物与热量…';

  @override
  String dietCameraError(String error) {
    return '无法打开相机/相册：$error';
  }

  @override
  String get dietPhotoHintTitle => '发送照片给 AI 分析';

  @override
  String get dietPhotoHintLabel => '补充说明（可选）';

  @override
  String get dietPhotoHintPlaceholder => '如：半碗米饭、去皮鸡腿、少油';

  @override
  String get dietStartAnalyze => '开始识别';

  @override
  String get dietTextEstimateTitle => 'AI 文字估算热量';

  @override
  String get dietTextEstimateHint => '描述你吃了什么，例如：\n一碗兰州牛肉面加一个卤蛋、半瓶无糖可乐';

  @override
  String get dietEstimateBtn => '估算';

  @override
  String get foodConfirmTitle => 'AI 估算结果（可修改）';

  @override
  String get foodConfirmName => '食物';

  @override
  String get foodConfirmAmount => '份量';

  @override
  String get foodConfirmKcal => '热量 kcal';

  @override
  String get foodConfirmProtein => '蛋白 g';

  @override
  String get foodConfirmCarbs => '碳水 g';

  @override
  String get foodConfirmFat => '脂肪 g';

  @override
  String get foodConfirmSaveBtn => '添加到今日饮食';

  @override
  String get mealEditAddTitle => '记录饮食';

  @override
  String get mealEditUpdateTitle => '编辑饮食';

  @override
  String get mealEditTypeLabel => '餐次';

  @override
  String get mealEditNameLabel => '食物名称 *';

  @override
  String get mealEditNameRequired => '请输入食物名称';

  @override
  String get mealEditAmountLabel => '份量（如 1碗 / 200g）';

  @override
  String get mealEditKcalLabel => '热量';

  @override
  String busHomeTitle(String stop) {
    return '校车 · $stop';
  }

  @override
  String busHomeNextCountdown(String dir, String time, int mins) {
    return '$dir · 下一班 $time（还有 $mins 分钟）';
  }

  @override
  String busHomeEndedToday(String time) {
    return '今日班次已结束（明日首班 $time）';
  }

  @override
  String get busHomeWeekend => '周末停运（仅周一至周五运行）';

  @override
  String get busBoardTitle => '校车实时看板';

  @override
  String get busStopReminderSettings => '站点与提醒设置';

  @override
  String get busRouteActions => '路线管理与模板';

  @override
  String get busMenuSwitchImport => '切换 / 导入路线';

  @override
  String get busMenuShareJson => '分享当前路线 JSON';

  @override
  String get busMenuDownloadTemplate => '下载空 JSON 模板';

  @override
  String get busSwitchImportBtn => '切换/导入';

  @override
  String get busMyFavStopLabel => '我的常用站：';

  @override
  String busReminderBadgeOn(int mins) {
    return '提前$mins分提醒';
  }

  @override
  String get busReminderBadgeOff => '提醒已关';

  @override
  String get busVibrationSwitchTitle => '到站前手机震动提醒（仅周一至周五）';

  @override
  String get busRemindBeforeLabel => '提前提醒时间';

  @override
  String busRemindMinsOption(int mins) {
    return '提前 $mins 分钟';
  }

  @override
  String get busOutboundSegment => '去程 → BUV';

  @override
  String get busInboundSegment => '回程 ← 家';

  @override
  String get busWeekendBanner => '今天是周末（本路线仅周一至周五运行），以下为工作日班次预演';

  @override
  String busEndedTodayBanner(String time, String stop) {
    return '今日该方向班次已全部结束 · 明日首班 $time（$stop）';
  }

  @override
  String get busStatusImminent => '即将到站 ≤5m';

  @override
  String get busStatusSoon => '快到了';

  @override
  String get busStatusUpcoming => '待发车';

  @override
  String get busStatusDeparted => '已发车';

  @override
  String get busStatusEnded => '今日已结束';

  @override
  String get busNextBadge => '下一班 NEXT';

  @override
  String busDepartedAtStop(String stop, String time) {
    return '已于 $time 经过 $stop';
  }

  @override
  String busCountdownHoursMinsSecs(int hours, String mins, String secs) {
    return '还有 $hours 小时 $mins 分 $secs 秒';
  }

  @override
  String busCountdownMinsSecs(String mins, String secs) {
    return '还有 $mins 分 $secs 秒';
  }

  @override
  String get busEnRoute => '行驶中';

  @override
  String get busWaitingDepart => '待发车';

  @override
  String get busArrivingSoon => '即将进站';

  @override
  String busProgressStart(String time) {
    return '候车起点 $time';
  }

  @override
  String busProgressPrev(String time) {
    return '上一班 $time';
  }

  @override
  String busProgressNow(String time) {
    return '现在 $time';
  }

  @override
  String busProgressTarget(String time) {
    return '本站 $time';
  }

  @override
  String get busYourFavStopTag => '← 你的常用站';

  @override
  String get busFooterTipTitle => '小贴士：点击卡片内任意站点即可设为常用站';

  @override
  String get busFooterTipSub =>
      '看板按距离当前时刻最近自动排序，≤5 分钟红橙呼吸提醒，已发车班次自动沉底置灰。右上角支持导入/分享自定义路线 JSON。';

  @override
  String busFavStopToast(String stop) {
    return '已更新常用站为 $stop';
  }

  @override
  String busSwitchedRouteToast(String name) {
    return '已切换路线为：$name';
  }

  @override
  String busImportedRouteToast(String name) {
    return '成功导入并启用路线：$name';
  }

  @override
  String get busValidationFailedTitle => '路线格式校验未通过';

  @override
  String get busSheetTitle => '切换或管理校车路线';

  @override
  String get busDownloadTemplateBtn => '下载模板';

  @override
  String get busBadgeBuiltin => '内置';

  @override
  String get busBadgeImported => '已导入';

  @override
  String get busBadgeCustom => '自定义';

  @override
  String busStopsCountSub(int outCount, int inCount) {
    return '去程 $outCount 站 · 回程 $inCount 站';
  }

  @override
  String busDeleteRouteConfirm(String name) {
    return '确定删除路线「$name」吗？';
  }

  @override
  String get busManualCreateBtn => '手动创建路线';

  @override
  String get busImportJsonBtn => '导入 JSON 文件';

  @override
  String get busCustomDialogCreateTitle => '手动创建校车路线';

  @override
  String get busCustomDialogEditTitle => '编辑校车路线';

  @override
  String get busCustomRouteNameLabel => '路线名称 *';

  @override
  String get busCustomSchoolLabel => '学校名称（可选）';

  @override
  String get busCustomOutboundHint => '去程站点与时刻（每行一站，格式：站点名: 07:30, 09:30）';

  @override
  String get busCustomInboundHint => '回程站点与时刻（每行一站，格式：站点名: 12:00, 17:30）';

  @override
  String get busCustomValidateSaveBtn => '校验并保存';

  @override
  String scheduleWeekTitle(int week) {
    return '第 $week 周';
  }

  @override
  String get scheduleCurrentWeek => '本周';

  @override
  String get scheduleBackToCurrent => '点击回到本周';

  @override
  String get scheduleImportTitle => '导入课表';

  @override
  String get scheduleImportSub => '支持教务系统截图、课程表小程序截图或直接粘贴选课文字';

  @override
  String get scheduleImportPresetTitle => '一键载入我的默认课表';

  @override
  String get scheduleImportPresetSub =>
      'Database Principles / Machine Learning / UX Design（周一至周五）';

  @override
  String get scheduleImportGalleryTitle => '从相册选课表截图（AI 识别）';

  @override
  String get scheduleImportGallerySub => '拍下或截屏教务课表，自动提取所有课程';

  @override
  String get scheduleImportCameraTitle => '拍照识别课表';

  @override
  String get scheduleImportCameraSub => '直接对着电脑屏幕或纸质课表拍照';

  @override
  String get scheduleImportTextTitle => '粘贴教务文字 / JSON 导入';

  @override
  String get scheduleImportTextSub => '复制教务网页上的选课列表文字，由 DeepSeek 解析';

  @override
  String get schedulePasteDialogTitle => '粘贴课表文字导入';

  @override
  String get schedulePasteDialogHint =>
      '直接粘贴教务系统里的课程文字，例如：\n高等数学 周一1-2节 1-16周 A203 王老师\n大学英语 周二5-6节 单周 C302';

  @override
  String get scheduleAiParseBtn => 'AI 解析';

  @override
  String get scheduleAiParsing => 'AI 正在识别并提取全部课程…';

  @override
  String scheduleConfirmImportTitle(int count) {
    return '识别到 $count 门课（勾选要导入的课程）';
  }

  @override
  String get scheduleReplaceAllSwitch => '清空原有课表后导入';

  @override
  String get scheduleWeekEvery => '每周';

  @override
  String get scheduleWeekOdd => '单周';

  @override
  String get scheduleWeekEven => '双周';

  @override
  String scheduleCourseImportSub(
    String weekday,
    int start,
    int end,
    int startWeek,
    int endWeek,
    String weekType,
  ) {
    return '$weekday 第$start-$end节 · $startWeek-$endWeek周($weekType)';
  }

  @override
  String get scheduleConfirmImportBtn => '确认导入课表';

  @override
  String scheduleImportedToast(int count) {
    return '成功导入 $count 门课程';
  }

  @override
  String get scheduleSettingsTitle => '课表与上课提醒设置';

  @override
  String get scheduleColorOsWarnTitle => 'OPPO/ColorOS 通知权限可能被降级';

  @override
  String get scheduleColorOsWarnSub =>
      '请点击下方按钮进入系统通知设置，将「上课与休息强提醒」设为【重要通知】并开启【震动】与【横幅】。';

  @override
  String get scheduleOpenChannelSettingsBtn => '去系统设置开启「重要通知+震动」';

  @override
  String get scheduleEnableReminderSwitch => '开启课前手机通知强提醒';

  @override
  String get scheduleEnableReminderSub => '快上课时调用硬件闹钟震动+横幅弹窗';

  @override
  String get scheduleDiagnoseBtn => '通知与震动诊断页';

  @override
  String get scheduleSysNotifBtn => '系统通知设置';

  @override
  String get scheduleTestVibBtn => '立即测试震动通知';

  @override
  String get scheduleTestVibToast => '已触发强震动测试通知！';

  @override
  String get scheduleUseSysClockSwitch => '用系统时钟 App 闹钟提醒（可选）';

  @override
  String get scheduleUseSysClockSub => '调起手机自带「时钟」新建闹钟，100%必响，但会在闹钟列表留记录';

  @override
  String get scheduleWriteNextAlarmBtn => '一键把下一节课写入系统闹钟';

  @override
  String scheduleWriteNextAlarmToast(String info) {
    return '已为您调起系统时钟设置下一节课闹钟：$info';
  }

  @override
  String get scheduleNoUpcomingClassToast => '未来 7 天内暂无待上课程';

  @override
  String get scheduleFirstWeekMonLabel => '第一周的周一';

  @override
  String get schedulePickSemesterStartHelp => '选择开学第一周的任意一天';

  @override
  String get scheduleSectionsPerDayLabel => '每天节数';

  @override
  String scheduleSectionsCount(int count) {
    return '$count 节';
  }

  @override
  String get scheduleAddCourseTooltip => '添加课程';

  @override
  String scheduleRainBanner(String precip) {
    return '今日有雨（降水概率 $precip%），去教室或坐校车记得带伞！';
  }

  @override
  String get scheduleEmptyTapHint => '点格子添加，或 ';

  @override
  String get scheduleEmptyImportBtn => '截图 / 文本一键导入课表';

  @override
  String get scheduleClearAllTitle => '清空所有课程';

  @override
  String get scheduleClearAllSub => '删除课表中所有课程并取消对应上课提醒';

  @override
  String get scheduleClearConfirmTitle => '确定清空所有课程？';

  @override
  String scheduleClearConfirmDesc(int count) {
    return '这会删除 $count 节课程和相关的上课提醒。\n这个操作不能撤销。';
  }

  @override
  String get scheduleClearConfirmBtn => '清空';

  @override
  String scheduleClearedToast(int count) {
    return '已清空 $count 节课程并取消相关提醒';
  }

  @override
  String get scheduleAlreadyEmptyToast => '当前课表已经是空的';

  @override
  String get scheduleSeedPromptTitle => '要不要导入 BUV 示例课表？';

  @override
  String get scheduleSeedPromptDesc => '如果你不是 BUV 的学生，可以跳过，之后随时手动添加或导入自己的课程。';

  @override
  String get scheduleSeedImportBtn => '导入示例';

  @override
  String get scheduleSeedSkipBtn => '跳过，自己添加';

  @override
  String get scheduleManualAddBtn => '手动添加';

  @override
  String get courseEditMultiWeekdayHint => '支持多选，例如周一、三、五一次添加';

  @override
  String courseEditAddedMultiToast(int count) {
    return '已添加 $count 节课程';
  }

  @override
  String holidayTodayNoClass(String name) {
    return '今天是假期（$name），没有课程';
  }

  @override
  String get holidayShortBadge => '假';

  @override
  String holidayWeekBanner(String items) {
    return '本周假期：$items（假期当天不上课、不提醒）';
  }

  @override
  String get holidayColumnLabel => '假期无课';

  @override
  String scheduleMonthHeader(int month) {
    return '$month\n月';
  }

  @override
  String scheduleCourseDetailSection(
    String weekday,
    String timeRange,
    int start,
    int end,
  ) {
    return '$weekday $timeRange（第 $start-$end 节）';
  }

  @override
  String scheduleCourseDetailWeeks(
    int startWeek,
    int endWeek,
    String weekType,
  ) {
    return '第 $startWeek-$endWeek 周 · $weekType';
  }

  @override
  String scheduleDeleteCourseConfirm(String name) {
    return '删除课程「$name」？';
  }

  @override
  String get courseEditAddTitle => '添加课程';

  @override
  String get courseEditUpdateTitle => '编辑课程';

  @override
  String get courseEditNameLabel => '课程名称 *';

  @override
  String get courseEditNameRequired => '请输入课程名称';

  @override
  String get courseEditLocationLabel => '教室';

  @override
  String get courseEditTeacherLabel => '老师';

  @override
  String get courseEditWeekdayTitle => '上课星期';

  @override
  String get courseEditSectionTitle => '上课节次与时间';

  @override
  String get courseEditStartSection => '开始节次';

  @override
  String get courseEditEndSection => '结束节次';

  @override
  String courseEditSectionItem(int num, String time) {
    return '第 $num 节 ($time)';
  }

  @override
  String get courseEditSectionOrderError => '结束节次不能早于开始节次';

  @override
  String get courseEditWeeksTitle => '周数范围与单双周';

  @override
  String courseEditWeeksSummary(int start, int end, String timeRange) {
    return '第 $start - $end 周 · $timeRange';
  }

  @override
  String get courseEditColorTitle => '课程专属颜色';

  @override
  String get courseEditSaveBtn => '保存课程';

  @override
  String get workoutTitle => '训练与有氧';

  @override
  String get workoutExerciseLibBtn => '动作库';

  @override
  String get workoutStartStrengthBtn => '开始力量训练';

  @override
  String get workoutLogCardioBtn => '记录有氧运动';

  @override
  String get workoutTabStrength => '力量训练 (按组/计时)';

  @override
  String get workoutTabCardio => '有氧运动 (MET消耗)';

  @override
  String workoutActivePlanTitle(String name) {
    return '当前计划：$name';
  }

  @override
  String get workoutTapSplitHint => '点分化直接开练';

  @override
  String workoutPlanSplitChip(String day, String focus, int count) {
    return '$day · $focus ($count动作)';
  }

  @override
  String get workoutVolumeChartTitle => '近期力量训练总容量 (kg)';

  @override
  String get workoutHistoryTitle => '力量训练会话记录';

  @override
  String get workoutEmptyStrengthHint =>
      '还没有力量训练记录\n点下方按钮开始计时训练，或去 AI 页生成专属训练计划';

  @override
  String get workoutEmptyStrengthBtn => '开始第一次训练';

  @override
  String get workoutEmptySessionTitle => '空训练';

  @override
  String workoutSessionDuration(int mins) {
    return '时长 $mins 分钟';
  }

  @override
  String workoutSessionSets(int sets) {
    return '正式组 $sets 组';
  }

  @override
  String workoutSessionVolume(String volume) {
    return '总容量 $volume kg';
  }

  @override
  String workoutSessionBurn(String kcal) {
    return '消耗 ~$kcal kcal';
  }

  @override
  String get workoutDeleteSessionConfirm => '删除这次训练记录？';

  @override
  String get workoutEmptyCardioHint =>
      '还没有独立有氧记录\n支持走路、跑步、骑行、游泳、跳绳等，按 MET 公式自动算千卡消耗';

  @override
  String get workoutEmptyCardioBtn => '添加有氧运动';

  @override
  String workoutCardioItemTitle(String type, String mins) {
    return '$type · $mins 分钟';
  }

  @override
  String get workoutDeleteCardioConfirm => '删除这条有氧记录？';

  @override
  String workoutCardioSavedToast(String kcal) {
    return '已记录有氧：消耗约 $kcal kcal（已自动计入今日饮食额度）';
  }

  @override
  String get workoutAdjustedBadge => '已修正';

  @override
  String get workoutAdjustTooltip => '修正时长与消耗';

  @override
  String get workoutAdjustTitle => '修正训练记录';

  @override
  String get workoutAdjustDurationLabel => '实际训练时长';

  @override
  String get workoutAdjustDurationUnit => '分钟';

  @override
  String get workoutAdjustBurnLabel => '消耗热量';

  @override
  String workoutAdjustHint(String kcal) {
    return '估算值 $kcal kcal，可手动改';
  }

  @override
  String get workoutAdjustResetBtn => '恢复自动估算';

  @override
  String workoutAdjustSavedToast(String kcal) {
    return '已保存修正（$kcal kcal）';
  }

  @override
  String get workoutQuickLogBtn => '快速补录';

  @override
  String get workoutQuickLogTitle => '快速补录训练';

  @override
  String get workoutQuickLogNoteLabel => '训练内容（可选，如壶铃/胸背）';

  @override
  String get workoutQuickLogNoteDefault => '快速补录训练';

  @override
  String get workoutQuickLogExerciseLabel => '关联动作（可选）';

  @override
  String get workoutQuickLogNone => '不关联具体动作';

  @override
  String get workoutQuickLogSetsLabel => '组数（可选）';

  @override
  String get workoutQuickLogDurationRequired => '请填写大于 0 的训练时长';

  @override
  String workoutQuickLogSavedToast(int mins, String kcal) {
    return '已补录训练（$mins 分钟 · $kcal kcal）';
  }

  @override
  String workoutCompactSets(int count) {
    return '$count 组';
  }

  @override
  String workoutCompactDuration(int mins) {
    return '$mins 分钟';
  }

  @override
  String workoutCompactBurnEst(String kcal) {
    return '约 $kcal kcal';
  }

  @override
  String workoutCompactBurnExact(String kcal) {
    return '$kcal kcal';
  }

  @override
  String workoutSingleDayVolumeSub(String date) {
    return '$date · 最近 1 次力量训练';
  }

  @override
  String get workoutInProgressBadge => '训练进行中';

  @override
  String workoutInProgressElapsed(String clock) {
    return '已进行 $clock';
  }

  @override
  String get workoutResumeBtn => '继续训练';

  @override
  String get workoutFinishSaveBtn => '结束并保存';

  @override
  String get workoutStaleTitle => '这次训练还要继续吗？';

  @override
  String workoutStaleDesc(int hours, int sets) {
    return '检测到你在 $hours 小时前开始了一次未结束的训练（已记录 $sets 组），是否继续？';
  }

  @override
  String get workoutDiscardBtn => '放弃本次';

  @override
  String get workoutExitDialogTitle => '训练仍在进行中';

  @override
  String get workoutExitDialogDesc => '你可以暂离页面（计时器将在后台继续），或直接结束并保存本次训练。';

  @override
  String get workoutExitKeepRunningBtn => '暂离（保持计时）';

  @override
  String get workoutExitContinueBtn => '继续训练';

  @override
  String get workoutPlanMenuRename => '重命名计划';

  @override
  String get workoutPlanMenuReplace => '替换计划（去 AI 生成）';

  @override
  String get workoutPlanMenuDelete => '删除计划';

  @override
  String get workoutPlanRenameTitle => '重命名训练计划';

  @override
  String get workoutPlanRenameLabel => '计划名称';

  @override
  String workoutPlanDeleteTitle(String name) {
    return '确认删除「$name」？';
  }

  @override
  String get workoutPlanDeleteDesc => '这个计划会被移除，但已经完成的训练记录不受影响。';

  @override
  String get workoutPlanDeletedToast => '已删除当前训练计划';

  @override
  String get workoutFreeTrainingBtn => '不按计划，自由训练';

  @override
  String get mealQuickRecentTitle => '最近常吃（点一下秒填）';

  @override
  String get mealExpandMacrosBtn => '展开份量与三大营养素（可选）';

  @override
  String get mealCollapseMacrosBtn => '收起营养素明细';

  @override
  String get cardioDialogAddTitle => '记录有氧运动';

  @override
  String get cardioDialogEditTitle => '编辑有氧运动';

  @override
  String get cardioTypeLabel => '有氧类型';

  @override
  String get cardioDurationLabel => '时长 *';

  @override
  String get cardioMinutesSuffix => '分钟';

  @override
  String get cardioDistanceLabel => '距离(可选)';

  @override
  String cardioEstBurnLabel(String weight, String met) {
    return '估算消耗 (按体重 ${weight}kg × MET $met)';
  }

  @override
  String get cardioDurationRequired => '请输入大于 0 的有氧时长';

  @override
  String get cardioTypeWalk => '走路';

  @override
  String get cardioTypeBriskWalk => '快走';

  @override
  String get cardioTypeJog => '慢跑';

  @override
  String get cardioTypeRun => '中速跑';

  @override
  String get cardioTypeCycle => '骑行';

  @override
  String get cardioTypeSwim => '游泳';

  @override
  String get cardioTypeJumpRope => '跳绳';

  @override
  String get cardioTypeOther => '其他';

  @override
  String sessionHeaderStats(int sets, String volume) {
    return '$sets 组 · $volume kg';
  }

  @override
  String get sessionFinishBtn => '结束训练';

  @override
  String get sessionAddExerciseBtn => '添加动作';

  @override
  String get sessionEmptyHint => '训练计时已开始！\n点击下方按钮选择动作，每完成一组点右侧 ✓ 自动开启组间休息倒计时';

  @override
  String get sessionSelectExerciseBtn => '选择训练动作';

  @override
  String sessionRestActive(String clock, String paused) {
    return '组间休息倒计时：$clock$paused';
  }

  @override
  String get sessionRestPausedTag => ' (已暂停)';

  @override
  String get sessionRestResume => '继续';

  @override
  String get sessionRestPause => '暂停';

  @override
  String get sessionRestSkip => '跳过';

  @override
  String get sessionRestDurationLabel => '组间休息时长：';

  @override
  String get sessionRestStartNow => '立即开始休息计时';

  @override
  String get sessionRestFinishedToast => '组间休息结束！开始下一组吧';

  @override
  String sessionPlanTargetHint(int sets, String reps, String weightHint) {
    return '计划目标：$sets组 × $reps$weightHint';
  }

  @override
  String sessionLastCardioHint(String records) {
    return '上次：$records';
  }

  @override
  String sessionLastStrengthHint(String records) {
    return '上次：$records';
  }

  @override
  String get sessionWarmupTag => '热';

  @override
  String get sessionCardioDuration => '时长';

  @override
  String get sessionCardioMins => '分';

  @override
  String get sessionStrengthWeight => '重量';

  @override
  String get sessionCardioSteps => '步数';

  @override
  String get sessionCardioStepsUnit => '步';

  @override
  String get sessionStrengthReps => '次数';

  @override
  String get sessionStrengthRepsUnit => '次';

  @override
  String get sessionCompleteSetTooltip => '完成本组并开始休息倒计时';

  @override
  String get sessionAddCardioRow => '再加一段有氧记录';

  @override
  String get sessionAddStrengthRow => '加一组（点 ✓ 完成本组并自动倒计时休息）';

  @override
  String sessionFinishedToast(int mins, int sets, String volume, String kcal) {
    return '训练完成！耗时 $mins 分钟 · $sets 组 · 容量 $volume kg · 消耗约 $kcal kcal';
  }

  @override
  String get exerciseSelectTitle => '选择训练动作';

  @override
  String get exerciseLibTitle => '动作库';

  @override
  String get exerciseAddCustomBtn => '自定义动作';

  @override
  String get exerciseCustomDialogTitle => '添加自定义动作';

  @override
  String get exerciseCategoryLabel => '部位分类';

  @override
  String get exerciseNameLabel => '动作名称';

  @override
  String exerciseCustomSubtitle(String category) {
    return '$category · 自定义动作';
  }

  @override
  String exercisePresetSubtitle(String category) {
    return '$category肌群训练';
  }

  @override
  String exerciseDeleteConfirm(String name) {
    return '删除自定义动作「$name」？';
  }

  @override
  String get catChest => '胸';

  @override
  String get catBack => '背';

  @override
  String get catLegs => '腿';

  @override
  String get catShoulders => '肩';

  @override
  String get catArms => '手臂';

  @override
  String get catCore => '核心';

  @override
  String get catCardio => '有氧';

  @override
  String get catOther => '其他';

  @override
  String get bodyTitle => '身体数据';

  @override
  String get bodyProfileBtn => '资料';

  @override
  String get bodyLogWeightBtn => '记体重';

  @override
  String get bodyNoProfileTitle => '还没有填写身体资料';

  @override
  String get bodyNoProfileSub => '点击右上角「资料」填写，代谢与热量计算才准确';

  @override
  String get bodyWeightTrendTitle => '体重趋势曲线';

  @override
  String get bodyEmptyChartHint => '记录第一笔体重后即可查看变化趋势图';

  @override
  String get bodyEmptyChartBtn => '立即记录体重';

  @override
  String get bodyHistoryTitle => '历史记录';

  @override
  String get bodyEmptyHistoryHint => '还没有身体记录\n每天早上空腹称重最准确哦';

  @override
  String get bodyEmptyHistoryBtn => '记录今日体重';

  @override
  String bodyFatTag(String fat) {
    return '体脂 $fat%';
  }

  @override
  String bodyWaistTag(String waist) {
    return '腰围 $waist cm';
  }

  @override
  String get bodyStatWeight => '体重 kg';

  @override
  String get bodyStatBmr => '基础代谢';

  @override
  String get bodyStatTdee => '总消耗 TDEE';

  @override
  String get bodyStatTargetKcal => '目标 kcal';

  @override
  String get bodyStatGoal => '当前目标';

  @override
  String bodyChartTargetLine(String weight) {
    return '目标 ${weight}kg';
  }

  @override
  String get bodyDialogTitle => '记录身体数据';

  @override
  String get bodyWeightLabel => '体重';

  @override
  String get bodyFatLabel => '体脂率（可选）';

  @override
  String get bodyWaistLabel => '腰围（可选）';

  @override
  String get bmiUnderweight => '偏瘦';

  @override
  String get bmiNormal => '正常';

  @override
  String get bmiOverweight => '超重';

  @override
  String get bmiObese => '肥胖';

  @override
  String get profileTitle => '身体资料与训练档案';

  @override
  String get profileGenderSection => '性别';

  @override
  String get profileMale => '男生';

  @override
  String get profileFemale => '女生';

  @override
  String get profileAgeHeightSection => '年龄与身高';

  @override
  String get profileAgeLabel => '年龄';

  @override
  String get profileAgeUnit => '岁';

  @override
  String get profileHeightLabel => '身高';

  @override
  String get profileActivityGoalSection => '活动水平与目标';

  @override
  String get profileActivityLabel => '日常静息/工作活动水平';

  @override
  String get profileTargetWeightLabel => '目标体重（可选，将在体重趋势图画出目标线）';

  @override
  String get profileTrainingConditionSection => '运动条件（供 AI 定制计划）';

  @override
  String get profileExperienceLabel => '运动经验';

  @override
  String get profileWeeklyDaysLabel => '每周可练';

  @override
  String profileWeeklyDaysItem(int days) {
    return '$days 天/周';
  }

  @override
  String get profileSessionMinsLabel => '单次时长';

  @override
  String profileSessionMinsItem(int mins) {
    return '$mins 分钟';
  }

  @override
  String get profileEquipmentLabel => '可用器械';

  @override
  String get profileInjuriesLabel => '伤病或动作限制（可选）';

  @override
  String get profileInjuriesHint => '如：膝盖不适、腰突、无';

  @override
  String get profileSaveBtn => '保存资料';

  @override
  String get onboardingTitle => '定制你的健康与训练档案';

  @override
  String get onboardingIntro =>
      '花 30 秒填好基本情况，系统将自动计算你的动态热量目标，并在每次与 DeepSeek AI 对话时自动带上这些条件。';

  @override
  String get onboardingStep1 => '1. 基本身体数据';

  @override
  String get onboardingCurrentWeight => '当前体重';

  @override
  String get onboardingTargetWeight => '目标体重(可选)';

  @override
  String get onboardingStep2 => '2. 目标与日常活动量';

  @override
  String get onboardingStep3 => '3. 运动经验与训练条件';

  @override
  String get onboardingFinishBtn => '完成并初始化我的计划';

  @override
  String get onboardingSavedToast => '个人档案已保存，TDEE 与 AI 上下文已初始化！';

  @override
  String get goalLose => '减脂';

  @override
  String get goalMaintain => '维持';

  @override
  String get goalGain => '增肌';

  @override
  String get goalFitness => '提升体能';

  @override
  String get actSedentary => '久坐（几乎不运动）';

  @override
  String get actLight => '轻度（每周运动 1-3 天）';

  @override
  String get actModerate => '中度（每周运动 3-5 天）';

  @override
  String get actHigh => '高强度（每周运动 6-7 天）';

  @override
  String get actExtreme => '极高（体力劳动 / 一天两练）';

  @override
  String get expNone => '零基础';

  @override
  String get expBeginner => '半年以内';

  @override
  String get expIntermediate => '1-3 年';

  @override
  String get expAdvanced => '3 年以上';

  @override
  String get equipBodyweight => '徒手';

  @override
  String get equipDumbbell => '哑铃';

  @override
  String get equipBarbell => '杠铃';

  @override
  String get equipGym => '健身房全套';

  @override
  String get aiTitle => 'AI 健康助手';

  @override
  String get aiClearChatTooltip => '清空对话';

  @override
  String get aiClearChatConfirm => '清空全部聊天记录？';

  @override
  String get aiSettingsTooltip => 'AI 设置';

  @override
  String get aiQuickGeneratePlan => '生成训练计划(可导入)';

  @override
  String get aiQuickTodaySummary => '今日总结';

  @override
  String get aiQuickWeekSummary => '本周总结';

  @override
  String get aiQuickNextMeal => '下一餐吃什么';

  @override
  String get aiPromptGeneratePlan =>
      '请根据我的个人档案（目标、运动经验、每周可训练天数、单次时长、可用器械、伤病限制）以及本周课表空闲时间，为我定制一份周训练计划，并在末尾附上可一键导入的 JSON 训练计划代码块。';

  @override
  String get aiPromptTodaySummary => '请结合我今天的饮食和训练记录做个简短点评，并告诉我接下来一餐怎么吃最合适。';

  @override
  String get aiPromptWeekSummary => '请总结我近7天的热量摄入、营养素比例和训练情况，指出做得好的地方和需要改进的地方。';

  @override
  String get aiPromptNextMeal => '根据我今天剩余的热量和三大营养素缺口，给我推荐2-3个常见、容易买到的餐食方案。';

  @override
  String get aiEmptyHint =>
      'AI 会自动读取你的身体档案、饮食、训练和课表\n点上方「生成训练计划(可导入)」即可定制专属计划并一键放入训练页';

  @override
  String get aiEmptyActionBtn => '生成我的专属训练计划';

  @override
  String aiImportPlanBtn(String name) {
    return '导入到训练计划（$name）';
  }

  @override
  String aiPlanImportedToast(String name) {
    return '已导入「$name」！去「训练」页点击对应分化即可直接按计划开练';
  }

  @override
  String get aiInputHint => '问问饮食、训练，或说“帮我生成训练计划”…';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsAppearanceSection => '外观、字号与语言';

  @override
  String get settingsThemeMode => '深色模式';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsFontSize => '字体大小（户外阅读建议选大）';

  @override
  String get settingsFontSmall => '小';

  @override
  String get settingsFontMedium => '标准';

  @override
  String get settingsFontLarge => '大';

  @override
  String get settingsLanguage => '界面语言 / Language';

  @override
  String get settingsLangSystem => '跟随系统';

  @override
  String get settingsLangZh => '简体中文';

  @override
  String get settingsLangEn => 'English';

  @override
  String get settingsWeatherSection => '天气城市与定位方式';

  @override
  String get settingsWeatherModeAuto => '当前模式：自动 GPS 定位（6小时缓存，失败兜底 IP）';

  @override
  String settingsWeatherModeManual(String city) {
    return '当前模式：手动固定城市 · $city';
  }

  @override
  String get settingsWeatherProxyHint =>
      '开启代理/VPN 时若未开 GPS 可能误判到代理所在地（如香港），可直接点选下方常用城市锁定天气：';

  @override
  String get settingsWeatherAutoChip => '自动 GPS 定位';

  @override
  String get settingsWeatherAutoToast => '已切换为自动 GPS 定位并刷新天气';

  @override
  String settingsWeatherLockedToast(String city) {
    return '已锁定天气城市为：$city';
  }

  @override
  String get settingsWeatherCustomLabel => '自定义搜索城市（支持中英文）';

  @override
  String get settingsWeatherCustomHint => '如 Ho Chi Minh City / Hanoi / 成都';

  @override
  String get settingsWeatherSetBtn => '设为该城';

  @override
  String get settingsChatAiSection => '对话与建议模型（支持一键预设）';

  @override
  String get settingsChatAiHint =>
      '支持点选下方服务商预设，或直接输入 deepseek / 域名（系统会自动补全 /chat/completions）。API Key 加密保存在本机。';

  @override
  String get settingsPresetDeepseek => 'DeepSeek (默认)';

  @override
  String get settingsPresetOpenai => 'OpenAI';

  @override
  String get settingsPresetQwen => '通义千问 (阿里云)';

  @override
  String get settingsBaseUrlLabel => 'Base URL（可直接填 deepseek 或完整地址）';

  @override
  String get settingsApiKeyLabel => 'API Key';

  @override
  String get settingsModelNameLabel => '模型名称（可点上方预设或手填）';

  @override
  String get settingsTestingBtn => '测试中…';

  @override
  String get settingsTestConnectionBtn => '测试连接';

  @override
  String settingsTestSuccessToast(String reply) {
    return '连接成功：$reply';
  }

  @override
  String get settingsVisionSection => '拍照识图模型（方案 A）';

  @override
  String get settingsVisionSameSwitch => '与对话模型共用同一套配置';

  @override
  String get settingsVisionSameSub => '若当前对话模型不支持图片输入，请关闭此开关并点选下方视觉模型';

  @override
  String get settingsVisionBaseUrlLabel => '识图 Base URL';

  @override
  String get settingsVisionApiKeyLabel => '识图 API Key';

  @override
  String get settingsVisionModelLabel => '识图模型名称';

  @override
  String get settingsTestVisionBtn => '测试识图接口';

  @override
  String get settingsSaveAiBtn => '保存 AI 配置';

  @override
  String get settingsSystemDataSection => '系统通知与数据备份';

  @override
  String get settingsDiagTileTitle => '通知与震动诊断页（ColorOS 必看）';

  @override
  String get settingsDiagTileSub => '排查为什么没响、一键开启重要通知与全屏横幅';

  @override
  String get settingsExportJsonTitle => '导出完整备份 (JSON)';

  @override
  String get settingsExportJsonSub => '包含课表、饮食、力量训练、有氧、身体记录';

  @override
  String get settingsExportCsvTitle => '导出 Excel 表格 (CSV)';

  @override
  String get settingsExportCsvSub => '方便在电脑或手机表格中查看饮食、体重与有氧明细';

  @override
  String get settingsAboutTileTitle => '关于生活助手';

  @override
  String get settingsAboutTileSub => '版本 v2.1.9 · 由大肥鱼协助开发';

  @override
  String get usageSectionTitle => '使用数据与性能分析';

  @override
  String get usageSwitchTitle => '记录使用情况与性能探针';

  @override
  String usageCountSub(int count) {
    return '已记录 $count 条（保留 30 天，仅存本机绝不联网上报）';
  }

  @override
  String get usageExportBtn => '导出数据';

  @override
  String get usageClearBtn => '清空';

  @override
  String get usageClearConfirm => '确定清空全部已记录的使用数据吗？';

  @override
  String get usageClearedToast => '使用数据已清空';

  @override
  String get usageExportDialogTitle => '导出使用数据到电脑分析';

  @override
  String get usageExportRangeLabel => '选择导出时间范围：';

  @override
  String get usageRange1d => '最近 1 天';

  @override
  String get usageRange7d => '最近 7 天';

  @override
  String get usageRange30d => '最近 30 天';

  @override
  String get usageRangeAll => '全部数据';

  @override
  String get usageExportJsonBtn => '导出 JSON（含 Summary 汇总 + 明细）';

  @override
  String get usageExportCsvBtn => '导出 CSV（方便 Excel 打开）';

  @override
  String get diagTitle => '通知与震动诊断';

  @override
  String get diagRefreshTooltip => '重新检测';

  @override
  String get diagStatusGood => '当前通知与强震动状态正常';

  @override
  String get diagStatusWarn => '检测到通知或震动可能被系统限制';

  @override
  String diagDeviceChannelSub(
    String device,
    String channelName,
    String channelId,
  ) {
    return '设备：$device\n渠道：$channelName ($channelId)';
  }

  @override
  String get diagSectionPermissions => '各项权限与系统分级状态';

  @override
  String get diagAppNotifTitle => '应用通知总开关 (areNotificationsEnabled)';

  @override
  String get diagAppNotifOn => '已开启';

  @override
  String get diagAppNotifOff => '被关闭！将无法收到任何上课或校车提醒';

  @override
  String get diagImportanceTitle => '通知渠道重要性 (Channel Importance)';

  @override
  String get diagImp0 => '0 - 已关闭 (NONE)';

  @override
  String get diagImp1 => '1 - 极低 (MIN，无声无横幅)';

  @override
  String get diagImp2 => '2 - 低 (LOW，被降级为静默/其他通知)';

  @override
  String get diagImp3 => '3 - 默认 (DEFAULT，可能无横幅弹窗)';

  @override
  String diagImpHigh(int imp) {
    return '$imp - 高/最高 (HIGH/MAX，正常弹出横幅+震动)';
  }

  @override
  String get diagVibrateTitle => '渠道震动许可 (shouldVibrate)';

  @override
  String get diagVibrateOn => '已允许震动（+ 硬件闹钟震动双保险）';

  @override
  String get diagVibrateOff => '渠道震动被系统关闭，请点下方按钮开启';

  @override
  String get diagSoundTitle => '通知提示音 (Sound URI)';

  @override
  String get diagSoundOn => '已配置提示音';

  @override
  String get diagSoundOff => '静音状态';

  @override
  String get diagExactAlarmTitle => '精确闹钟权限 (canScheduleExactAlarms)';

  @override
  String get diagExactAlarmOn => '已授权准时触发';

  @override
  String get diagExactAlarmOff => '未授权精确闹钟，提醒可能延迟';

  @override
  String get diagSectionColorOs => 'OPPO / ColorOS 专属修复操作';

  @override
  String get diagColorOsGuide =>
      '如果在 OPPO / Find X8 等机型上通知不弹横幅或不震动，请点击下面两个按钮，把「生活助手」设为允许通知，并将「生活助手·强提醒通知」设为【重要通知】且打开【横幅】与【震动】：';

  @override
  String get diagBtn1AppNotif => '1. 一键打开「生活助手」应用通知设置';

  @override
  String get diagBtn2Channel => '2. 一键打开「强提醒通知渠道」详细设置';

  @override
  String get diagBtn3Test => '3. 立即发送一条全屏横幅+强震动测试通知';

  @override
  String get diagTestSentToast => '已发送测试强提醒（含闹钟级震动 + 声音 + 横幅）';

  @override
  String get aboutTitle => '关于 · 生活助手';

  @override
  String get aboutVersion => '版本 v2.1.9 (Build 15)';

  @override
  String get aboutBadge => '由大肥鱼协助开发与监工 · 陪伴你的每一天';

  @override
  String get aboutDesc =>
      '集课程表、多路线校车起终点实时时间轴（内置 BUV 路线 + 自定义/JSON 导入）、GPS 实时天气、拍照热量识别、力量训练计时、MET 有氧与自动计步、DeepSeek AI 私人教练于一体的全能个人生活助手。';

  @override
  String get aboutCreditsTitle => '协作开发';

  @override
  String get aboutCreditsBody => '本应用由以下三方协作完成：';

  @override
  String get aboutCreditOwner => '产品设计与需求';

  @override
  String get aboutCreditGemini => '代码开发（Antigravity）';

  @override
  String get aboutCreditDeepSeek => '监工与验证（大肥鱼）';

  @override
  String get aboutCreditsNote => '所有功能均经过真实设备测试验证。';

  @override
  String get batteryDiagTitle => '耗电与性能诊断';

  @override
  String get batteryDiagTileSub => '查看近 7 天前后台时长、计时器活跃度、GPS、写库与小组件刷新次数';

  @override
  String get batteryDiagResetBtn => '重置统计';

  @override
  String get batteryDiagResetConfirm => '确定清空最近 7 天的耗电诊断计数吗？';

  @override
  String get batteryDiagResetToast => '耗电诊断统计已重置';

  @override
  String get batteryDiagSummaryTitle => '最近 24 小时与当前活跃资源监控';

  @override
  String batteryDiagActiveTimers(int count) {
    return '当前运行中的周期计时器：$count 个';
  }

  @override
  String get batteryDiagFgTime => '前台时长';

  @override
  String get batteryDiagBgTime => '后台时长';

  @override
  String get batteryDiagTimerTime => '计时器活跃';

  @override
  String get batteryDiagGpsCalls => 'GPS 调用';

  @override
  String get batteryDiagDbWrites => '数据库写入';

  @override
  String get batteryDiagWidgetSyncs => '小组件刷新';

  @override
  String get batteryDiagHistoryTitle => '近 7 天滚动统计明细（存于 kv 表）';

  @override
  String batteryDiagDaySub(
    String fg,
    String bg,
    String timer,
    int gps,
    int db,
    int widget,
  ) {
    return '前台 $fg · 后台 $bg · 计时器 $timer\nGPS $gps 次 · 写库 $db 次 · 小组件 $widget 次';
  }

  @override
  String get batteryDiagTipTitle => '已生效的省电优化策略';

  @override
  String get batteryDiagTipSub =>
      '• 桌面小组件 updatePeriodMillis=0（仅事件驱动推送，零后台定时唤醒）\n• 计步传感器在退后台时自动注销监听，前台写库节流至 ≥30 秒\n• 校车与训练计时器在页面不可见或按 Home 键退后台时立即暂停\n• GPS 权限全局仅询问一次，定位坐标本地缓存 6 小时';

  @override
  String get widgetGuideTitle => '把小组件添加到桌面';

  @override
  String get widgetGuideTileSub => '在手机桌面直接看今日课程、剩余热量与实时步数';

  @override
  String get widgetGuideHeader => '一键添加「生活助手」桌面小组件';

  @override
  String get widgetGuideDesc => '无需打开 App，在手机主屏幕即可一眼看到今日课程安排、剩余可吃热量和实时步数。';

  @override
  String get widgetGuideStep1 => '1. 点击下方「一键添加到桌面」（支持 Android 8.0+ 主流桌面）。';

  @override
  String get widgetGuideStep2 => '2. 或回到手机桌面，长按空白处 → 点击底部「小组件 / 插件」。';

  @override
  String get widgetGuideStep3 => '3. 找到「生活助手 · 今日概览」（4×2 卡片），拖到桌面即可。';

  @override
  String get widgetGuidePinBtn => '一键添加到桌面';

  @override
  String get widgetGuidePinSuccess => '已调起系统桌面添加弹窗，请在弹窗中确认！';

  @override
  String get widgetGuidePinFallback =>
      '当前桌面不支持自动弹窗，请长按手机桌面空白处 → 小组件 → 选择「生活助手」添加。';

  @override
  String get busOriginLabel => '起点';

  @override
  String get busDestinationLabel => '终点';

  @override
  String get busSwapStopsTooltip => '一键交换起点与终点';

  @override
  String get busSameStopError => '起点和终点不能相同，请选择不同的站点';

  @override
  String busAutoSwitchedDirToast(String origin, String dest) {
    return '已根据所选起终点自动切换至对应方向：$origin → $dest';
  }

  @override
  String get busNoMoreTripsToday => '今日已无班次';

  @override
  String busNoMoreTripsSub(String time) {
    return '该区间今日所有班次均已发车 · 明日首班 $time';
  }

  @override
  String busTimelineTitle(String slot) {
    return '实时站点时间轴（$slot）';
  }

  @override
  String get busStopPassedTag => '✓ 已过';

  @override
  String get busStopCurrentTag => '← 当前站';

  @override
  String busStopInMinutesTag(int mins) {
    return '还有 $mins 分';
  }

  @override
  String get busStopArrivingNowTag => '即将到站';

  @override
  String get busStopOriginTag => '起点';

  @override
  String get busStopDestTag => '终点';

  @override
  String busBusHereLabel(int pct) {
    return '车在这里 · 行驶中 ($pct%)';
  }

  @override
  String get busSelectSlotLabel => '班次切换：';

  @override
  String get busRefreshSpinToast => '校车时刻与车辆位置已刷新';

  @override
  String get aiPlanCardHeader => '已生成训练计划';

  @override
  String aiPlanDayExerciseCount(int count) {
    return '$count 个动作';
  }

  @override
  String get aiPlanViewDetailsBtn => '查看详情';

  @override
  String get aiPlanImportBtn => '导入到训练';

  @override
  String get aiPlanImportedDoneBtn => '已导入 ✓';

  @override
  String get aiPlanGeneratingPlaceholder => '正在生成计划…';

  @override
  String get aiPlanParseFailedHint => '结构化计划数据解析失败，可点击下方查看原始回复。';

  @override
  String get aiPlanShowRawReplyBtn => '显示原始回复';

  @override
  String get aiPlanHideRawReplyBtn => '收起原始回复';

  @override
  String get weatherForecast15Title => '未来 15 天天气预报';

  @override
  String get weatherForecast15Badge => '15天';

  @override
  String get weatherOpenSystemBtn => '手机天气';

  @override
  String get weatherSwitchCityBtn => '切换城市';

  @override
  String get weatherSystemNotFound => '未检测到手机内置天气应用';

  @override
  String get weatherForecastEmpty => '暂未获取到未来 15 天预报，请点击刷新重试';

  @override
  String get weatherTodayTag => '今天';

  @override
  String get weatherTomorrowTag => '明天';

  @override
  String busHomeNextAbsolute(String dir, String time) {
    return '$dir · 下一班 $time';
  }

  @override
  String busNextTripWaiting(String time, int mins) {
    return '下一班 $time · 还有 $mins 分钟';
  }

  @override
  String busNextTripAbsolute(String time) {
    return '下一班 $time';
  }

  @override
  String busTomorrowTimeTag(String time) {
    return '明日 $time';
  }

  @override
  String get busWeekendShortTag => '周末停运';

  @override
  String busReverseOrderError(String origin, String dest) {
    return '当前方向行车顺序为「$dest → $origin」，不包含「$origin → $dest」。';
  }

  @override
  String get busSwapBtnShort => '对调起终点';
}
