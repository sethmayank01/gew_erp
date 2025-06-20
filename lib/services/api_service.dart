// Flutter: api_service.dart
// Updated to use correct HTTP methods to match Flask backend

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class ApiService {
  static const String lanUrl = 'http://192.168.2.160:5000';
  //static const String cloudUrl = 'https://your-cloud-backend.com';
  static const String cloudUrl = 'http://192.168.2.160:5000';

  static Future<http.Response> _sendRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
  }) async {
    Uri uri = Uri.parse(
      '$lanUrl$endpoint',
    ).replace(queryParameters: queryParams);
    try {
      return await _send(method, uri, body);
    } catch (_) {
      uri = Uri.parse(
        '$cloudUrl$endpoint',
      ).replace(queryParameters: queryParams);
      return await _send(method, uri, body);
    }
  }

  static Future<http.Response> _send(
    String method,
    Uri uri,
    Map<String, dynamic>? body,
  ) async {
    switch (method) {
      case 'GET':
        return await http.get(uri);
      case 'POST':
        return await http.post(
          uri,
          headers: _headers(),
          body: jsonEncode(body),
        );
      case 'PUT':
        return await http.put(uri, headers: _headers(), body: jsonEncode(body));
      case 'DELETE':
        return await http.delete(uri);
      default:
        throw Exception('Unsupported method');
    }
  }

  static Map<String, String> _headers() => {'Content-Type': 'application/json'};

  static Future<Map<String, dynamic>?> login(
    String username,
    String password,
  ) async {
    final res = await _sendRequest(
      'POST',
      '/users/login',
      body: {'username': username, 'password': password},
    );
    return res.statusCode == 200 ? jsonDecode(res.body) : null;
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
    await _sendRequest('POST', '/reports', body: {'data': data});
  }

  static Future<List<dynamic>> getReports() async {
    final res = await _sendRequest('GET', '/reports');
    return jsonDecode(res.body);
  }

  static Future<void> saveJob(Map<String, dynamic> job) async {
    await _sendRequest('POST', '/jobs', body: job);
  }

  static Future<void> updateJob(Map<String, dynamic> job) async =>
      await saveJob(job);

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

  static Future<void> submitMaterialIncoming(Map<String, dynamic> data) async {
    data['id'] ??= const Uuid().v4();
    await _sendRequest('POST', '/incoming_materials', body: data);
  }

  static Future<bool> saveOutgoingMaterial(Map<String, dynamic> data) async {
    final res = await _sendRequest('POST', '/outgoing_materials', body: data);

    return res.statusCode == 200;
  }

  static Future<List<Map<String, dynamic>>> getOutgoingMaterials() async {
    final res = await _sendRequest('GET', '/outgoing_materials');
    return List<Map<String, dynamic>>.from(jsonDecode(res.body));
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
    //Delete the stock entry for which material is deleted
    //Add the stock entry per invoice/lot
    final res = await _sendRequest(
      'POST',
      '/stock/delete',
      body: {'data': data},
    );
    return res.statusCode == 200;
  }

  static Future<bool> addStock({required Map<String, dynamic> data}) async {
    //Add the stock entry per invoice/lot
    final res = await _sendRequest(
      'POST',
      '/stock/add',
      body: {'data': data},
    );
    return res.statusCode == 200;
  }

  static Future<bool> updateStockQuantity(
      {required Map<String, dynamic> data, required double quantity}) async {
    //Add the stock entry per invoice/lot
    final res = await _sendRequest(
      'POST',
      '/stock/update',
      body: {
        'data': data,
        'quantity': quantity,
      },
    );
    return res.statusCode == 200;
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
    return res.statusCode == 201;
  }

  static Future<List<dynamic>> getIndentsForJob(String jobId) async {
    final res = await _sendRequest('GET', '/job_indents/$jobId');
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> getIndentStockList() async {
    final res = await _sendRequest('GET', '/indent_stock');
    return jsonDecode(res.body);
  }

  static Future<String> updateJobIndent({
    required Map<String, dynamic> data,
  }) async {
    final res = await _sendRequest('PUT', '/job_indents', body: data);
    if (res.statusCode == 200)
      return "Success";
    else {
      final responseBody = json.decode(res.body);
      final errorMessage =
          responseBody['error'] ?? responseBody['message'] ?? 'Unknown error';
      return 'Error: $errorMessage';
    }
  }

  static Future<String> issueMaterial(Map<String, dynamic> data) async {
    final jobIndentResult = await updateJobIndent(data: data);

    if (jobIndentResult != 'Success') {
      // Skip updating stock and return the error message
      return 'Job Indent Failed: $jobIndentResult';
    }
    await updateStock(data: data, reduce: true);
    return 'Success';
  }
}
