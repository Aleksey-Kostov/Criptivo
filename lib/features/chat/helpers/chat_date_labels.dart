import 'package:intl/intl.dart';

/// Разделители в чата в стил Viber/Signal:
/// Днес · Вчера · Миналата седмица · d MMMM / d MMMM y
class ChatDateLabels {
  ChatDateLabels._();

  /// Етикет за календарния ден на [utcOrLocal].
  static String labelFor(DateTime date, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final local = date.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final today = DateTime(n.year, n.month, n.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (day == today) return 'Днес';
    if (day == yesterday) return 'Вчера';

    // Миналата седмица = преди yesterday, но в рамките на 6 дни назад от today
    final weekStart = today.subtract(const Duration(days: 6));
    if (day.isAfter(weekStart.subtract(const Duration(days: 1))) &&
        day.isBefore(yesterday)) {
      // Пон–Нед на български чрез DateFormat (locale може да липсва)
      return _weekdayBg(day.weekday);
    }

    if (local.year == n.year) {
      return DateFormat('d MMMM', 'en').format(local); // fallback без bg locale
    }
    return DateFormat('d MMMM y', 'en').format(local);
  }

  /// Български етикети без зависимост от intl locale data.
  static String labelForBg(DateTime date, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final local = date.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final today = DateTime(n.year, n.month, n.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (day == today) return 'Днес';
    if (day == yesterday) return 'Вчера';

    final daysAgo = today.difference(day).inDays;
    if (daysAgo > 1 && daysAgo < 7) {
      return _weekdayBg(day.weekday);
    }

    final months = _monthsBg;
    final m = months[local.month - 1];
    if (local.year == n.year) {
      return '${local.day} $m';
    }
    return '${local.day} $m ${local.year}';
  }

  static String _weekdayBg(int weekday) {
    const names = [
      'Понеделник',
      'Вторник',
      'Сряда',
      'Четвъртък',
      'Петък',
      'Събота',
      'Неделя',
    ];
    return names[(weekday - 1).clamp(0, 6)];
  }

  static const _monthsBg = [
    'януари',
    'февруари',
    'март',
    'април',
    'май',
    'юни',
    'юли',
    'август',
    'септември',
    'октомври',
    'ноември',
    'декември',
  ];

  /// Ключ за групиране: yyyy-MM-dd (локален ден).
  static String dayKey(DateTime date) {
    final l = date.toLocal();
    final y = l.year.toString().padLeft(4, '0');
    final m = l.month.toString().padLeft(2, '0');
    final d = l.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateTime? parseCreatedAt(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toUtc();
    try {
      return DateTime.parse(raw.toString()).toUtc();
    } catch (_) {
      return null;
    }
  }
}

/// Елемент в плосък списък: или разделител, или съобщение.
sealed class ChatListEntry {
  const ChatListEntry();
}

class ChatDateSeparatorEntry extends ChatListEntry {
  final String label;
  final String dayKey;
  const ChatDateSeparatorEntry({required this.label, required this.dayKey});
}

class ChatMessageEntry extends ChatListEntry {
  final Map<String, dynamic> message;
  final int originalIndex;
  const ChatMessageEntry({required this.message, required this.originalIndex});
}

/// Плосък списък с разделители преди първото съобщение на всеки ден.
List<ChatListEntry> buildChatListWithDates(
  List<Map<String, dynamic>> messages, {
  DateTime? now,
}) {
  final out = <ChatListEntry>[];
  String? lastKey;

  for (var i = 0; i < messages.length; i++) {
    final msg = messages[i];
    final dt = ChatDateLabels.parseCreatedAt(msg['created_at']);
    final key = dt != null ? ChatDateLabels.dayKey(dt) : 'unknown';

    if (key != lastKey) {
      lastKey = key;
      final label = dt != null
          ? ChatDateLabels.labelForBg(dt, now: now)
          : '—';
      out.add(ChatDateSeparatorEntry(label: label, dayKey: key));
    }
    out.add(ChatMessageEntry(message: msg, originalIndex: i));
  }

  return out;
}
