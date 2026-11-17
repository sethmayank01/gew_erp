// Flutter: api_service.dart
// Updated for incoming approval workflow and frontend/backend sync

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

class OutgoingIssueRejected implements Exception {
  final String message;
  OutgoingIssueRejected(this.message);
  @override
  String toString() => message;
}

class ApiService {
  static final sessionExpired = ValueNotifier<bool>(false);
  //static const String lanUrl = 'http://192.168.2.205:5000';
  static const String lanUrl = 'http://192.168.2.205:5005';
  static const String versionUrl = 'http://192.168.2.205:8000/version.json';

  static Future<http.Response> _sendRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
  }) async {
    Uri uri = Uri.parse(
      '$lanUrl$endpoint',
    ).replace(queryParameters: queryParams);
    final response = await _send(
      method,
      uri,
      body,
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode >= 200 && response.statusCode < 300)
      return response;
    if (endpoint == '/users/login' && response.statusCode == 401)
      return response;
    if (response.statusCode == 401) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('accessToken');
      sessionExpired.value = true;
    }
    throw ApiException(response.statusCode, _extractError(response));
  }

  static Future<http.Response> _send(
    String method,
    Uri uri,
    Map<String, dynamic>? body,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('accessToken');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    switch (method) {
      case 'GET':
        return await http.get(uri, headers: headers);
      case 'POST':
        return await http.post(uri, headers: headers, body: jsonEncode(body));
      case 'PUT':
        return await http.put(uri, headers: headers, body: jsonEncode(body));
      case 'DELETE':
        return await http.delete(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
      default:
        throw Exception('Unsupported method');
    }
  }

  static Future<Map<String, dynamic>?> login(
    String username,
    String password,
  ) async {
    final res = await _sendRequest(
      'POST',
      '/users/login',
      body: {'username': username, 'password': password},
    );
    if (res.statusCode != 200) return null;
    final user = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    final prefs = await SharedPreferences.getInstance();
    if (user['token'] is String)
      await prefs.setString('accessToken', user['token']);
    sessionExpired.value = false;
    return user;
  }

  static Future<Map<String, dynamic>?> fetchVersionInfo() async {
    final client = http.Client();
    try {
      final res = await client
          .get(Uri.parse(versionUrl))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      }
      return null;
    } finally {
      client.close();
    }
  }

  static Future<String> getCurrentAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  static Future<void> addUser(
    String username,
    String password,
    String role,
  ) async {
    await _sendRequest(
      'POST',
      '/users',
      body: {'username': username, 'password': password, 'role': role},
    );
  }

  static Future<void> resetPassword(String username, String newPassword) async {
    await _sendRequest(
      'PUT',
      '/users/reset_password',
      body: {'username': username, 'newPassword': newPassword},
    );
  }

  static Future<void> deleteUser(String username) async {
    await _sendRequest('DELETE', '/users/$username');
  }

  static Future<List<Map<String, dynamic>>> getUsers() async {
    final res = await _sendRequest('GET', '/users');
    return List<Map<String, dynamic>>.from(jsonDecode(res.body));
  }

  static Future<void> saveReport(Map<String, dynamic> data) async {
    data['_requestId'] ??= const Uuid().v4();
    await _sendRequest('POST', '/reports', body: {'data': data});
  }

  static Future<bool> deleteReport(Map<String, dynamic> data) async {
    final res = await _sendRequest(
      'DELETE',
      '/reports',
      body: {
        'savedBy': data['savedBy'],
        'timestamp': data['timestamp'],
        if (data['_requestId'] != null) '_requestId': data['_requestId'],
      },
    );
    return res.statusCode == 200;
  }

  static Future<List<dynamic>> getReports() async {
    final res = await _sendRequest('GET', '/reports');
    return jsonDecode(res.body);
  }

  static Future<String> saveJob(Map<String, dynamic> job) async {
    job['_requestId'] ??= const Uuid().v4();
    final response = await _sendRequest(
      'POST',
      '/jobs',
      body: {
        ...job,
        '_autoNumber': job['jobType'] == 'New' || job['jobType'] == 'Repair',
      },
    );
    return (jsonDecode(response.body)['serialNo'] ?? job['serialNo'])
        .toString();
  }

  static Future<void> updateJob(Map<String, dynamic> job) async {
    await _sendRequest('PUT', '/jobs', body: job);
  }

  static Future<List<Map<String, dynamic>>> getJobs() async {
    final res = await _sendRequest('GET', '/jobs');
    return List<Map<String, dynamic>>.from(jsonDecode(res.body));
  }

  static Future<List<Map<String, dynamic>>> getOpenJobs() async {
    final res = await _sendRequest('GET', '/jobs/open');
    return List<Map<String, dynamic>>.from(jsonDecode(res.body));
  }

  static Future<void> addMaterial(Map<String, dynamic> data) async {
    data['id'] ??= const Uuid().v4();
    await _sendRequest('POST', '/materials', body: data);
  }

  static Future<void> deleteMaterial(String type, String subtype) async {
    await _sendRequest(
      'DELETE',
      '/materials',
      body: {'type': type, 'subtype': subtype},
    );
  }

  static Future<List<dynamic>> getMaterials() async {
    final res = await _sendRequest('GET', '/materials');
    return jsonDecode(res.body);
  }

  /// UPDATED: Set approval fields on creation. Don't add to stock here.
  static Future<void> submitMaterialIncoming(Map<String, dynamic> data) async {
    data['id'] ??= const Uuid().v4();
    data['approved'] = false;
    data['approved_by'] = null;
    data['approved_at'] = null;
    await _sendRequest('POST', '/incoming_materials', body: data);
  }

  static Future<bool> saveOutgoingMaterial(Map<String, dynamic> data) async {
    try {
      await _sendRequest('POST', '/outgoing_materials/issue', body: data);
    } on ApiException catch (error) {
      if (error.statusCode >= 400 && error.statusCode < 500) {
        throw OutgoingIssueRejected(error.message);
      }
      rethrow;
    }
    return true;
  }

  static Future<List<dynamic>> getOutgoingMaterials({
    String search = '',
  }) async {
    try {
      final encodedSearch = Uri.encodeQueryComponent(search.trim());

      final endpoint = search.trim().isEmpty
          ? '/outgoing_materials'
          : '/outgoing_materials?search=$encodedSearch';

      final res = await _sendRequest('GET', endpoint);

      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      } else {
        throw Exception(
          'Failed to load outgoing materials: ${_extractError(res)}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching outgoing materials: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getMaterialIncomingEntries() async {
    final res = await _sendRequest('GET', '/incoming_materials');
    return List<Map<String, dynamic>>.from(jsonDecode(res.body));
  }

  static Future<void> deleteMaterialEntry(String entryId) async {
    await _sendRequest('DELETE', '/incoming_materials/$entryId');
  }

  static Future<Map<String, dynamic>?> getMaterialEntryById(String id) async {
    final res = await _sendRequest('GET', '/incoming_materials/$id');
    return jsonDecode(res.body);
  }

  static Future<bool> removeStock({required Map<String, dynamic> data}) async {
    final res = await _sendRequest(
      'POST',
      '/stock/delete',
      body: {'data': data},
    );
    return res.statusCode == 200;
  }

  static Future<bool> addStock({required Map<String, dynamic> data}) async {
    final res = await _sendRequest('POST', '/stock/add', body: {'data': data});
    return res.statusCode == 200;
  }

  static Future<dynamic> updateStockQuantity({
    required Map<String, dynamic> data,
    required double quantity,
    required double price,
    required bool editFlag,
  }) async {
    try {
      final res = await _sendRequest(
        'POST',
        '/stock/update',
        body: {
          'data': data,
          'quantity': quantity,
          'editFlag': editFlag,
          'price': price,
          'expectedQuantity': data['quantity'],
          'expectedPrice': data['price'],
        },
      );
      if (res.statusCode == 200) {
        return true;
      } else {
        try {
          final responseBody = jsonDecode(res.body);
          final errorMessage =
              responseBody['error'] ??
              responseBody['message'] ??
              'Unknown error';
          return errorMessage;
        } catch (_) {
          return 'Error: ${res.statusCode}';
        }
      }
    } catch (error) {
      return error.toString();
    }
  }

  static Future<void> updateStock({
    required Map<String, dynamic> data,
    bool reduce = false,
    bool isDelete = false,
  }) async {
    await _sendRequest(
      'POST',
      '/stock',
      body: {
        'material': data['material'],
        'jobSpecific': data['jobSpecific'] ?? false,
        'serialNo': data['serialNo'],
        'price': data['price'],
        'quantity': data['quantity'],
        'issuedQty': data['issuedQty'],
        'reduce': reduce,
        'isDelete': isDelete,
      },
    );
  }

  static Future<List<dynamic>> getStock(bool isJobSpecific) async {
    final res = await _sendRequest(
      'GET',
      '/stock',
      queryParams: {'isJobSpecific': '$isJobSpecific'},
    );
    return jsonDecode(res.body);
  }

  static Future<void> saveStock(
    List<dynamic> stockData,
    bool isJobSpecific,
  ) async {
    await _sendRequest(
      'POST',
      '/stock/save',
      body: {'stockData': stockData, 'isJobSpecific': isJobSpecific},
    );
  }

  static Future<void> deleteStock(
    Map<String, dynamic> stockItem,
    bool isJobSpecific,
  ) async {
    String key = '${stockItem['type']} - ${stockItem['subtype']}';
    if (isJobSpecific && stockItem['serialNo'] != null) {
      key = '$key - ${stockItem['serialNo']}';
    }
    await _sendRequest('DELETE', '/stock/$key');
  }

  static Future<bool> submitJobIndent(List<Map<String, dynamic>> data) async {
    final res = await _sendRequest(
      'POST',
      '/job_indents',
      body: {'data': data},
    );
    return res.statusCode == 200;
  }

  static Future<List<dynamic>> getIndentsForJob(String jobId) async {
    try {
      final res = await _sendRequest('GET', '/job_indents/$jobId');
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      } else {
        throw Exception('Failed to load indents: ${_extractError(res)}');
      }
    } catch (e) {
      throw Exception('Error fetching job indents: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getOpenJobIndents() async {
    try {
      final res = await _sendRequest('GET', '/open_job_indents');

      if (res.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(res.body));
      } else {
        throw Exception(
          'Failed to load open job indents: ${_extractError(res)}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching open job indents: $e');
    }
  }

  static Future<List<dynamic>> getIndentStockList() async {
    try {
      final res = await _sendRequest('GET', '/indent_stock');
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      } else {
        throw Exception(
          'Failed to load indent stock list: ${_extractError(res)}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching indent stock list: $e');
    }
  }

  static Future<String> updateJobIndent({
    required Map<String, dynamic> data,
  }) async {
    try {
      final res = await _sendRequest('PUT', '/job_indents', body: data);
      if (res.statusCode == 200) {
        return "Success";
      } else {
        return 'Error: ${_extractError(res)}';
      }
    } catch (e) {
      return 'Error: $e';
    }
  }

  static Future<String> updateExistingJobIndent({
    required Map<String, dynamic> data,
  }) async {
    try {
      final res = await _sendRequest(
        'POST',
        '/job_indents/update_existing',
        body: data,
      );
      if (res.statusCode == 200) {
        return "Success";
      } else {
        return 'Error: ${_extractError(res)}';
      }
    } catch (e) {
      return 'Error: $e';
    }
  }

  static Future<String> issueMaterial(Map<String, dynamic> data) async {
    try {
      await saveOutgoingMaterial(data);
      return 'Success';
    } catch (e) {
      return 'Error issuing material: $e';
    }
  }

  /// Approve an incoming material entry (admin only).
  static Future<void> approveMaterialEntry({
    required String entryId,
    required String approver,
  }) async {
    final res = await _sendRequest(
      'POST',
      '/incoming_materials/$entryId/approve',
      body: {'approver': approver},
    );
    if (res.statusCode != 200) {
      throw Exception('Approval failed: ${_extractError(res)}');
    }
  }

  /// Edit an incoming entry before approval (admin or creator).
  static Future<void> updateMaterialIncomingEntry({
    required String entryId,
    required Map<String, dynamic> data,
  }) async {
    final res = await _sendRequest(
      'PUT',
      '/incoming_materials/$entryId',
      body: data,
    );
    if (res.statusCode != 200) {
      throw Exception('Update failed: ${_extractError(res)}');
    }
  }

  static String _extractError(http.Response res) {
    try {
      final body = json.decode(res.body);
      if (body is Map<String, dynamic>) {
        return body['error'] ??
            body['message'] ??
            res.reasonPhrase ??
            'Unknown error';
      }
      return res.reasonPhrase ?? 'Unknown error';
    } catch (_) {
      return res.reasonPhrase ?? 'Unknown error';
    }
  }
}
