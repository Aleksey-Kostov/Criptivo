import 'package:http/http.dart' as http;

class LinkPreviewData {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;

  const LinkPreviewData({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
  });
}

class LinkPreviewService {
  static final _cache = <String, LinkPreviewData>{};
  static final _urlRegex = RegExp(
    r'https?:\/\/[^\s<>"{}|\\^`\[\]]+',
    caseSensitive: false,
  );

  static String? firstUrl(String text) {
    final m = _urlRegex.firstMatch(text);
    return m?.group(0);
  }

  static bool isYoutube(String url) {
    final u = url.toLowerCase();
    return u.contains('youtube.com') || u.contains('youtu.be');
  }

  static Future<LinkPreviewData?> fetch(String url) async {
    if (_cache.containsKey(url)) return _cache[url];

    try {
      // Лек open-graph fetch — за production по-добре edge function
      final uri = Uri.parse(url);
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode < 200 || res.statusCode >= 400) return null;

      final body = res.body;
      String? og(String prop) {
        final re = RegExp(
          r"""property=["']og:$prop["'][^>]*content=["']([^"']+)["']""",
          caseSensitive: false,
        );
        final re2 = RegExp(
          r"""content=["']([^"']+)["'][^>]*property=["']og:$prop["']""",
          caseSensitive: false,
        );
        return re.firstMatch(body)?.group(1) ?? re2.firstMatch(body)?.group(1);
      }

      final title =
          og('title') ??
          RegExp(
            r'<title[^>]*>([^<]+)</title>',
            caseSensitive: false,
          ).firstMatch(body)?.group(1)?.trim();

      final data = LinkPreviewData(
        url: url,
        title: _decode(title),
        description: _decode(og('description')),
        imageUrl: og('image'),
        siteName: _decode(og('site_name')) ?? uri.host,
      );
      _cache[url] = data;
      return data;
    } catch (_) {
      return LinkPreviewData(url: url, siteName: Uri.tryParse(url)?.host);
    }
  }

  static String? _decode(String? s) {
    if (s == null) return null;
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }
}
