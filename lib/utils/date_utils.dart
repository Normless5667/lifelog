import 'package:intl/intl.dart';

final _dateFmt = DateFormat('yyyy-MM-dd');

String fmtDate(DateTime d) => _dateFmt.format(d);

DateTime parseDate(String s) => _dateFmt.parse(s);

String today() => fmtDate(DateTime.now());

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

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

/// 学期第几周（从 1 开始）
int weekOfSemester(DateTime semesterStart, DateTime day) {
  final diff = dateOnly(day).difference(mondayOf(semesterStart)).inDays;
  return diff < 0 ? 0 : diff ~/ 7 + 1;
}
