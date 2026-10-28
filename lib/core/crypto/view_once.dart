import 'dart:convert';

/// Маркер за „покажи веднъж“ в media/text envelope (след decrypt).
class ViewOnce {
  static const metaKey = 'view_once';
  static const secondsKey = 'view_once_seconds';

  static bool isViewOnce(Map<String, dynamic>? media) {
    if (media == null) return false;
    return media[metaKey] == true;
  }

  static int seconds(Map<String, dynamic>? media, {int fallback = 5}) {
    final s = media?[secondsKey];
    if (s is int && s > 0) return s;
    return fallback;
  }

  /// Добавя view-once към вече парснат media map / envelope map.
  static Map<String, dynamic> mark(
    Map<String, dynamic> envelope, {
    int seconds = 5,
  }) {
    return {...envelope, metaKey: true, secondsKey: seconds};
  }

  static String markEnvelopeJson(String envelopeJson, {int seconds = 5}) {
    final map = jsonDecode(envelopeJson) as Map<String, dynamic>;
    return jsonEncode(mark(map, seconds: seconds));
  }
}
