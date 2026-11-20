import 'package:intl/intl.dart';

final _dateFmt = DateFormat('yyyy-MM-dd');

String fmtDate(DateTime d) => _dateFmt.format(d);

DateTime parseDate(String s) => _dateFmt.parse(s);

String today() => fmtDate(DateTime.now());

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 将任意日期字符串归一化为 yyyy-MM-dd（兼容 ISO 时间戳如 2026-11-19T00:00:00）
String dateOnlyStr(String raw) {
  final t = raw.trim();
  if (t.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(t)) {
    return t.substring(0, 10);
  }
  final parsed = DateTime.tryParse(t);
  return parsed != null ? fmtDate(parsed) : t;
}

DateTime mondayOf(DateTime d) {
  final day = dateOnly(d);
  return day.subtract(Duration(days: day.weekday - 1));
}

const weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// 友好的日期显示：今天 / 昨天 / 11月17日 周一
String friendlyDate(String date) {
  final d = parseDate(date);
  final now = dateOnly(DateTime.now());
  final diff = now.difference(d).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  if (diff == -1) return '明天';
  final y = d.year == now.year ? '' : '${d.year}年';
  return '$y${d.month}月${d.day}日 ${weekdayNames[d.weekday - 1]}';
}

String fmtNum(double v, {int digits = 0}) {
  if (digits == 0) return v.round().toString();
  final s = v.toStringAsFixed(digits);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// 学期第几周（week1Start 所在周为第 1 周，公式：floor((date - week1Start) / 7) + 1；第 1 周之前返回 <= 0）
int weekOfSemester(DateTime semesterStart, DateTime day) {
  final diff = dateOnly(day).difference(mondayOf(semesterStart)).inDays;
  return (diff / 7).floor() + 1;
}
