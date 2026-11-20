import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../services/reminder_service.dart';

/// 当日单节课程的实时状态
enum CourseStatus {
  /// 已上完（当前时间 >= 下课时间）
  completed,

  /// 进行中（上课时间 <= 当前时间 < 下课时间）
  inProgress,

  /// 未开始（当前时间 < 上课时间）
  upcoming,
}

/// 单节课程状态及倒计时明细
class CourseStatusInfo {
  final Course course;
  final CourseStatus status;
  final DateTime startTime;
  final DateTime endTime;

  /// 距离上课的分钟数（未开始时 >= 1，其余为 0）
  final int minutesUntilStart;

  /// 距离下课的分钟数（进行中时 >= 1，其余为 0）
  final int minutesUntilEnd;

  const CourseStatusInfo({
    required this.course,
    required this.status,
    required this.startTime,
    required this.endTime,
    required this.minutesUntilStart,
    required this.minutesUntilEnd,
  });
}

/// 今日全部课程的实时状态汇总（供首页顶部倒计时条与卡片列表共用）
class TodayCourseSummary {
  final List<CourseStatusInfo> items;
  final CourseStatusInfo? current;
  final CourseStatusInfo? next;
  final int completedCount;

  const TodayCourseSummary({
    required this.items,
    required this.current,
    required this.next,
    required this.completedCount,
  });

  bool get allDone => items.isNotEmpty && current == null && next == null;
}

/// 计算单门课程在 [now] 时刻的状态与精确倒计时
CourseStatusInfo evaluateCourseStatus(Course course, DateTime now) {
  final st = ReminderService.sectionStartTime(course.startSection);
  final et = ReminderService.sectionEndTime(course.endSection);
  final start = DateTime(now.year, now.month, now.day, st.hour, st.minute);
  final end = DateTime(now.year, now.month, now.day, et.hour, et.minute);

  if (now.isBefore(start)) {
    final diffSec = start.difference(now).inSeconds;
    final mins = ((diffSec + 59) ~/ 60).clamp(1, 24 * 60);
    return CourseStatusInfo(
      course: course,
      status: CourseStatus.upcoming,
      startTime: start,
      endTime: end,
      minutesUntilStart: mins,
      minutesUntilEnd: 0,
    );
  }

  if (now.isBefore(end)) {
    final diffSec = end.difference(now).inSeconds;
    final mins = ((diffSec + 59) ~/ 60).clamp(1, 24 * 60);
    return CourseStatusInfo(
      course: course,
      status: CourseStatus.inProgress,
      startTime: start,
      endTime: end,
      minutesUntilStart: 0,
      minutesUntilEnd: mins,
    );
  }

  return CourseStatusInfo(
    course: course,
    status: CourseStatus.completed,
    startTime: start,
    endTime: end,
    minutesUntilStart: 0,
    minutesUntilEnd: 0,
  );
}

/// 汇总当日课程状态（按节次升序排列）
TodayCourseSummary summarizeTodayCourses(List<Course> courses, DateTime now) {
  final sorted = List<Course>.from(courses)
    ..sort((a, b) => a.startSection.compareTo(b.startSection));
  final items = sorted.map((c) => evaluateCourseStatus(c, now)).toList();

  CourseStatusInfo? current;
  CourseStatusInfo? next;
  var completedCount = 0;

  for (final info in items) {
    switch (info.status) {
      case CourseStatus.inProgress:
        current ??= info;
        break;
      case CourseStatus.upcoming:
        next ??= info;
        break;
      case CourseStatus.completed:
        completedCount++;
        break;
    }
  }

  return TodayCourseSummary(
    items: items,
    current: current,
    next: next,
    completedCount: completedCount,
  );
}

/// 将单节课程的倒计时格式化为本地化文案（进行中 / 未开始 / 已上完）
String formatCourseStatusLabel(AppLocalizations l, CourseStatusInfo info) {
  switch (info.status) {
    case CourseStatus.completed:
      return l.courseStatusDone;
    case CourseStatus.inProgress:
      return formatRemainingMinutes(l, info.minutesUntilEnd, isEnding: true);
    case CourseStatus.upcoming:
      return formatRemainingMinutes(l, info.minutesUntilStart, isEnding: false);
  }
}

/// 将分钟数格式化为「还有 N 分钟下课 / N 分钟后开始」或小时+分钟格式
String formatRemainingMinutes(
  AppLocalizations l,
  int totalMinutes, {
  required bool isEnding,
}) {
  final mins = totalMinutes < 1 ? 1 : totalMinutes;
  if (mins >= 60) {
    final h = mins ~/ 60;
    final m = mins % 60;
    return isEnding
        ? l.courseEndsInHoursMins(h, m)
        : l.courseStartsInHoursMins(h, m);
  }
  return isEnding ? l.courseEndsInMins(mins) : l.courseStartsInMins(mins);
}
