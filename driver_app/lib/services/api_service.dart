// lib/services/api_service.dart
// Handles all REST API communication with the Flask backend.

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // ── Change this to your server IP/hostname ─────────────────────────────────
  static const String baseUrl = 'https://driver-monitoring-system-nkw7.onrender.com/api';
  // Use 10.0.2.2 for Android emulator → localhost
  // Use your machine's IP for physical devices (e.g. http://192.168.1.100:5000/api)

  static const Duration _timeout = Duration(seconds: 60);

  // ── Stored session ─────────────────────────────────────────────────────────

  static Future<void> saveSession(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(user));
  }

  static Future<Map<String, dynamic>?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('user');
    if (data == null) return null;
    return jsonDecode(data);
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user');
  }

  // ── Helper ─────────────────────────────────────────────────────────────────

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  static Map<String, dynamic> _parse(http.Response res) {
    try {
      return jsonDecode(res.body);
    } catch (_) {
      return {'success': false, 'message': 'Invalid server response'};
    }
  }

  // ── Authentication ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String role,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/register'),
            headers: _headers,
            body: jsonEncode({
              'username': username,
              'email': email,
              'password': password,
              'role': role,
            }),
          )
          .timeout(_timeout);
      return _parse(res);
    } on SocketException {
      return {'success': false, 'message': 'Cannot connect to server'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/login'),
            headers: _headers,
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(_timeout);
      return _parse(res);
    } on SocketException {
      return {'success': false, 'message': 'Cannot connect to server'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ── Alert Logging ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> logAlert({
    required String username,
    required String alertType,
    required String timestamp,
    String? screenshotBase64,
  }) async {
    try {
      final body = {
        'username': username,
        'alert_type': alertType,
        'timestamp': timestamp,
        if (screenshotBase64 != null) 'screenshot': screenshotBase64,
      };
      final res = await http
          .post(
            Uri.parse('$baseUrl/log-alert'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      return _parse(res);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ── Admin ──────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getLogs({String? username}) async {
    try {
      final uri = Uri.parse('$baseUrl/logs')
          .replace(queryParameters: username != null ? {'username': username} : null);
      final res = await http.get(uri, headers: _headers).timeout(_timeout);
      return _parse(res);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getStats() async {
    try {
      final res =
          await http.get(Uri.parse('$baseUrl/stats'), headers: _headers).timeout(_timeout);
      return _parse(res);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static String getCsvUrl({String? username}) {
    final base = '$baseUrl/reports/csv';
    if (username != null) return '$base?username=$username';
    return base;
  }

  static String getPdfUrl({String? username}) {
    final base = '$baseUrl/reports/pdf';
    if (username != null) return '$base?username=$username';
    return base;
  }

  // ── Super Admin ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getPendingAdmins() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/superadmin/pending-admins'), headers: _headers)
          .timeout(_timeout);
      return _parse(res);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> approveAdmin(int userId) async {
    try {
      final res = await http
          .post(Uri.parse('$baseUrl/superadmin/approve/$userId'), headers: _headers)
          .timeout(_timeout);
      return _parse(res);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> rejectAdmin(int userId) async {
    try {
      final res = await http
          .delete(Uri.parse('$baseUrl/superadmin/reject/$userId'), headers: _headers)
          .timeout(_timeout);
      return _parse(res);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getAllUsers() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/superadmin/users'), headers: _headers)
          .timeout(_timeout);
      return _parse(res);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> deleteUser(int userId) async {
    try {
      final res = await http
          .delete(Uri.parse('$baseUrl/superadmin/delete/$userId'), headers: _headers)
          .timeout(_timeout);
      return _parse(res);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
