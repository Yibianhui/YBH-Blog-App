import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import '../data/blog_api.dart';

/// 全局单例引用，方便外壳与页面共享登录态。
final WpAuth wpAuth = WpAuth.instance;

/// 登录后的 WordPress 用户（来自 /wp-json/wp/v2/users/me）。
class WpUser {
  const WpUser({
    required this.id,
    required this.login,
    this.displayName,
    this.nickname,
    this.email,
    this.avatarUrl,
  });

  final int id;
  final String login;
  final String? displayName;
  final String? nickname;
  final String? email;
  final String? avatarUrl;

  String get name => (displayName ?? nickname ?? login).trim().isEmpty
      ? login
      : (displayName ?? nickname ?? login);

  factory WpUser.fromJson(Map<String, dynamic> json) {
    final avatars = json['avatar_urls'];
    final String? avatar = avatars is Map ? (avatars['96'] as String?) : null;
    return WpUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      login: (json['slug'] as String?) ?? (json['username'] as String?) ?? '',
      displayName: _clean(json['name']),
      nickname: _clean(json['nickname']),
      email: _clean(json['email']),
      avatarUrl: avatar,
    );
  }

  /// 仅从 JWT 令牌响应（无 id / 头像）构造的最小用户，用于兜底展示。
  factory WpUser.fromJwt({
    required String displayName,
    String? email,
    String? nicename,
  }) {
    return WpUser(
      id: 0,
      login: (nicename ?? displayName).trim(),
      displayName: displayName.trim().isEmpty ? nicename : displayName,
      email: email,
    );
  }

  static String? _clean(Object? v) =>
      v is String ? v.trim() : null;
}

/// 鉴权方式。
enum WpAuthMethod {
  /// JWT 插件令牌（Bearer），本站已安装并配置。
  jwt,

  /// WordPress 核心「应用密码」（Basic Auth），无需插件。
  basic,
}

/// WordPress 账号鉴权。
///
/// 登录优先级：
/// 1. **JWT**（默认，最友好）：用「用户名 + 账号密码」向 jwt-auth 令牌接口换取
///    Bearer 令牌，再用该令牌请求 /users/me 拿到用户资料。
/// 2. **应用密码（Basic Auth）兜底**：若 JWT 接口不可用（插件未装 / 未配置），
///    退回到 WordPress 核心自带的应用密码方式（用户名 + 应用密码）。
///
/// 【整站登录态同步】实测发现本站服务端只信任「真实浏览器指纹」的
/// wp-login PHP 会话：应用内 dart HttpClient 提交的登录虽然会收到
/// 302 + Set-Cookie，但服务端不会落库会话，拿到的是无效凭据。
/// 因此 App 登录成功后，由「整站」WebView 用 [webLoginCredentials]
/// （仅内存暂存、绝不持久化的最近一次登录凭据）在 WebView 内完成
/// 真实表单登录；退出登录时清除凭据并清空 WebView Cookie。
class WpAuth {
  WpAuth._();

  /// 全局单例，供外壳与各个页面共享登录态。
  static final WpAuth instance = WpAuth._();

  static const String _tokenKey = 'ybh_wp_token';
  static const String _userKey = 'ybh_wp_user';
  static const String _methodKey = 'ybh_wp_method';
  static const Duration _timeout = Duration(seconds: 25);

  String? _token;
  WpUser? _user;
  WpAuthMethod _method = WpAuthMethod.basic;

  /// 最近一次成功登录的凭据（仅内存，供「整站」WebView 自动登录）。
  (String, String)? _webLoginCredentials;

  /// App 内登录/退出事件通知（「整站」WebView 监听后执行
  /// 自动登录 / 清理会话）。
  final ValueNotifier<int> webLoginRequested = ValueNotifier<int>(0);

  /// 供「整站」WebView 自动登录使用的凭据；退出登录后为 null。
  (String, String)? get webLoginCredentials => _webLoginCredentials;

  /// 原始凭据（JWT 时为 Bearer 令牌，Basic 时为 base64 凭据）。
  String? get token => _token;

  /// 当前鉴权方式。
  WpAuthMethod get method => _method;

  /// 当前登录用户；未登录为 null。
  WpUser? get user => _user;

  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  /// 写操作所需的请求头；未登录返回空，调用方应先判断 [isLoggedIn]。
  Map<String, String> get authHeaders {
    if (_token == null) return const {};
    return switch (_method) {
      WpAuthMethod.jwt => {'Authorization': 'Bearer $_token'},
      WpAuthMethod.basic => {'Authorization': 'Basic $_token'},
    };
  }

  /// 从本地存储恢复登录态（应用启动时调用一次）。
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_tokenKey);
      final rawMethod = prefs.getString(_methodKey);
      _method = rawMethod == 'jwt' ? WpAuthMethod.jwt : WpAuthMethod.basic;
      final raw = prefs.getString(_userKey);
      if (raw != null) {
        _user = WpUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // 忽略：当作未登录。
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token == null) {
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
      await prefs.remove(_methodKey);
      await prefs.remove('ybh_wp_cookies');
    } else {
      await prefs.setString(_tokenKey, _token!);
      await prefs.setString(_userKey, jsonEncode(_user!.toJson()));
      await prefs.setString(
        _methodKey,
        _method == WpAuthMethod.jwt ? 'jwt' : 'basic',
      );
    }
  }

  /// 用「用户名 + 密码」登录。
  ///
  /// 优先尝试 JWT（账号密码），失败则回退到应用密码（Basic Auth）。
  /// 登录成功后凭据暂存于内存（[webLoginCredentials]），供「整站」
  /// WebView 自动登录；同时通知 [webLoginRequested]。返回 true 表示成功。
  Future<bool> login(String username, String password) async {
    final user = username.trim();
    final pass = password.replaceAll(' ', '');
    if (user.isEmpty || pass.isEmpty) return false;

    WpUser? loggedInUser;
    WpAuthMethod method;
    String? tok;

    // 1) JWT 优先。
    final jwtUser = await _loginJwt(user, pass);
    if (jwtUser != null) {
      method = WpAuthMethod.jwt;
      tok = jwtUser.$1;
      loggedInUser = jwtUser.$2;
    } else {
      // 2) 应用密码兜底。
      final basic = await _loginBasic(user, pass);
      if (basic == null) return false;
      method = WpAuthMethod.basic;
      tok = basic.$1;
      loggedInUser = basic.$2;
    }

    _method = method;
    _token = tok;
    _user = loggedInUser;
    _webLoginCredentials = (user, pass);
    webLoginRequested.value++;

    await _persist();
    return true;
  }

  /// JWT 登录：换取令牌并拉取用户资料。任一步非 200 均返回 null。
  Future<(String, WpUser)?> _loginJwt(String user, String pass) async {
    final http.Response tokenResp;
    try {
      tokenResp = await http
          .post(
            Uri.parse(AppConfig.jwtTokenUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': user, 'password': pass}),
          )
          .timeout(_timeout);
    } catch (e) {
      if (kDebugMode) debugPrint('[wp_auth] JWT 请求异常: $e');
      return null;
    }
    if (kDebugMode) {
      debugPrint('[wp_auth] JWT 状态码: ${tokenResp.statusCode}');
    }
    if (tokenResp.statusCode != 200) return null;
    final tokenJson = jsonDecode(utf8.decode(tokenResp.bodyBytes));
    final jwt = tokenJson is Map ? (tokenJson['token'] as String?) : null;
    if (jwt == null || jwt.isEmpty) return null;

    // 用令牌请求 /users/me 拿完整资料（含 id / 头像）。
    try {
      final meResp = await http
          .get(
            Uri.parse('${AppConfig.apiBase}/users/me'),
            headers: {'Authorization': 'Bearer $jwt'},
          )
          .timeout(_timeout);
      if (kDebugMode) debugPrint('[wp_auth] users/me 状态码: ${meResp.statusCode}');
      if (meResp.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(meResp.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          return (jwt, WpUser.fromJson(decoded));
        }
      }
    } catch (_) {
      // 令牌有效但拉资料失败：用 JWT 响应里的资料兜底。
    }
    final display = _asString(tokenJson['user_display_name']) ??
        _asString(tokenJson['user_nicename']) ??
        user;
    final email = _asString(tokenJson['user_email']);
    final nicename = _asString(tokenJson['user_nicename']);
    return (jwt, WpUser.fromJwt(displayName: display, email: email, nicename: nicename));
  }

  /// 应用密码（Basic Auth）登录：用「用户名 + 应用密码」请求 /users/me。
  Future<(String, WpUser)?> _loginBasic(String user, String appPassword) async {
    final basic = base64Encode(utf8.encode('$user:$appPassword'));
    final http.Response response;
    try {
      response = await http
          .get(
            Uri.parse('${AppConfig.apiBase}/users/me'),
            headers: {'Authorization': 'Basic $basic'},
          )
          .timeout(_timeout);
    } catch (_) {
      return null;
    }
    if (response.statusCode != 200) return null;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      return (basic, WpUser.fromJson(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    _method = WpAuthMethod.basic;
    _webLoginCredentials = null;
    webLoginRequested.value++;
    await _persist();
  }

  /// 拉取「我的文章」列表（当前登录用户）。
  Future<List<PostSummary>> fetchMyPosts({int page = 1, int perPage = 20}) async {
    if (!isLoggedIn) return const [];
    // JWT 但未能拿到用户 id（极少见的兜底情况）：不按作者过滤会拉全站，
    // 这里直接返回空，避免误展示他人文章。
    if (_user == null || _user!.id == 0) return const [];
    final uri = Uri.parse('${AppConfig.apiBase}/posts').replace(
      queryParameters: {
        'per_page': '$perPage',
        'page': '$page',
        'author': '${_user!.id}',
        '_embed': '1',
        'orderby': 'date',
        'order': 'desc',
      },
    );
    final response = await http
        .get(uri, headers: authHeaders)
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(PostSummary.fromJson)
        .toList();
  }

  /// 发布/草稿文章。
  ///
  /// [content] 为纯文本（按空行分段，自动包 `<p>`）；
  /// [status] 取 'publish' 或 'draft'。
  /// 返回新建文章的可访问链接，失败返回 null。
  Future<String?> publishPost({
    required String title,
    required String content,
    String status = 'publish',
    List<int>? categories,
  }) async {
    if (!isLoggedIn) return null;
    final body = {
      'title': title,
      'content': _wrapParagraphs(content),
      'status': status,
      if (categories != null && categories.isNotEmpty) 'categories': categories,
    };
    final response = await http
        .post(
          Uri.parse('${AppConfig.apiBase}/posts'),
          headers: {
            ...authHeaders,
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    if (response.statusCode == 201 || response.statusCode == 200) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          return decoded['link'] as String?;
        }
      } catch (_) {
        // 发布成功但解析失败，仍视为成功。
        return AppConfig.blogUrl;
      }
    }
    return null;
  }

  /// 纯文本按空行分段包成 HTML 段落，并转义特殊字符避免破坏排版。
  static String _wrapParagraphs(String text) {
    final blocks = text
        .split(RegExp(r'\n\s*\n'))
        .map((b) => b.replaceAll('\r', '').trim())
        .where((b) => b.isNotEmpty)
        .map((b) {
          final escaped = b
              .replaceAll('&', '&amp;')
              .replaceAll('<', '&lt;')
              .replaceAll('>', '&gt;');
          final withBreaks = escaped.replaceAll('\n', '<br>');
          return '<p>$withBreaks</p>';
        })
        .join('\n');
    return blocks;
  }

  static String? _asString(Object? v) => v is String ? v.trim() : null;
}

/// 调试/扩展用：WpUser 序列化。
extension WpUserX on WpUser {
  Map<String, dynamic> toJson() => {
        'id': id,
        'slug': login,
        'name': displayName,
        'nickname': nickname,
        'email': email,
        'avatar_urls': {'96': avatarUrl},
      };
}