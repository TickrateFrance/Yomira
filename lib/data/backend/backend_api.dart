import 'package:dio/dio.dart';

import '../../core/app_update.dart';
import 'models/auth_models.dart';
import 'models/sync_models.dart';
import 'token_store.dart';

/// Wrapper over our sync backend. Injects the JWT from [TokenStore] on
/// protected calls and surfaces friendly errors.
class BackendApi {
  BackendApi(this._dio, this._tokens);

  final Dio _dio;
  final TokenStore _tokens;

  Future<Options> _authOptions() async {
    final token = await _tokens.read();
    return Options(headers: {
      if (token != null) 'Authorization': 'Bearer $token',
    });
  }

  // ---- App version ----

  Future<AppUpdate> appStatus() async {
    final res = await _dio.get('/api/v1/app-status');
    final m = (res.data as Map).cast<String, dynamic>();
    final status = switch (m['status'] as String? ?? 'none') {
      'force' => UpdateStatus.force,
      'soft' => UpdateStatus.soft,
      _ => UpdateStatus.none,
    };
    return AppUpdate(status, m['url'] as String? ?? '');
  }

  // ---- Auth ----

  Future<AuthResult> register(String username, String password) async {
    final res = await _dio.post('/auth/register',
        data: {'username': username, 'password': password});
    return AuthResult.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<AuthResult> login(String username, String password) async {
    final res = await _dio.post('/auth/login',
        data: {'username': username, 'password': password});
    return AuthResult.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<AuthUser> me() async {
    final res = await _dio.get('/auth/me', options: await _authOptions());
    return AuthUser.fromJson(
        ((res.data as Map)['user'] as Map).cast<String, dynamic>());
  }

  // ---- Progress ----

  Future<List<ProgressEntry>> getProgress() async {
    final res = await _dio.get('/progress', options: await _authOptions());
    final list = ((res.data as Map)['progress'] as List? ?? const []);
    return list
        .map((e) => ProgressEntry.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<ProgressEntry> putProgress(ProgressEntry entry) async {
    final res = await _dio.put('/progress',
        data: entry.toPutBody(), options: await _authOptions());
    return ProgressEntry.fromJson(
        ((res.data as Map)['progress'] as Map).cast<String, dynamic>());
  }

  // ---- Library ----

  Future<List<LibraryEntry>> getLibrary() async {
    final res = await _dio.get('/library', options: await _authOptions());
    final list = ((res.data as Map)['library'] as List? ?? const []);
    return list
        .map((e) => LibraryEntry.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> addLibrary(String mangaId) async {
    await _dio.post('/library', data: {'mangaId': mangaId}, options: await _authOptions());
  }

  Future<void> removeLibrary(String mangaId) async {
    await _dio.delete('/library/$mangaId', options: await _authOptions());
  }

  // ---- History ----

  Future<List<HistoryEntry>> getHistory({int limit = 50}) async {
    final res = await _dio.get('/history',
        queryParameters: {'limit': limit}, options: await _authOptions());
    final list = ((res.data as Map)['history'] as List? ?? const []);
    return list
        .map((e) => HistoryEntry.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> deleteHistory(String mangaId) async {
    await _dio.delete('/history/$mangaId', options: await _authOptions());
  }
}
