import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:gew_erp/main.dart';
import 'package:gew_erp/models/app_update.dart';
import 'package:gew_erp/widgets/mandatory_update_gate.dart';

Map<String, dynamic> manifest(String version) => {
  'windows': {'version': version, 'installer_url': 'http://server/erp.exe'},
  'android': {'version': version, 'apk_url': 'http://server/erp.apk'},
};

Future<void> pumpGate(
  WidgetTester tester,
  Future<Map<String, dynamic>?> Function() fetch, {
  Future<bool> Function(Uri)? launch,
  String installed = '1.2.9',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MandatoryUpdateGate(
        installedVersion: () async => installed,
        fetchManifest: fetch,
        openDownload: launch,
        child: const Scaffold(body: Text('ERP access')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
}

void updateTest(String name, Future<void> Function(WidgetTester) callback) {
  testWidgets(
    name,
    callback,
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  updateTest('real app blocks login when an update is required', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'GEW ERP',
      packageName: 'gew_erp',
      version: '1.2.9',
      buildNumber: '1',
      buildSignature: '',
    );
    await http.runWithClient(
      () async {
        await tester.pumpWidget(const MyApp());
        await tester.pumpAndSettle();
        expect(find.text('Update Required'), findsOneWidget);
        expect(find.text('Login'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      () => MockClient(
        (request) async => http.Response(jsonEncode(manifest('1.2.10')), 200),
      ),
    );
  });

  test('versions compare numerically and never force a downgrade', () {
    expect(
      AppUpdate.fromManifest(
        manifest('1.2.10'),
        'windows',
      ).isNewerThan('1.2.9'),
      isTrue,
    );
    expect(
      AppUpdate.fromManifest(
        manifest('1.2.9'),
        'windows',
      ).isNewerThan('1.2.10'),
      isFalse,
    );
    expect(
      AppUpdate.fromManifest(
        manifest('1.2.9'),
        'windows',
      ).isNewerThan('1.2.9+1'),
      isFalse,
    );
    expect(
      AppUpdate.fromManifest(
        manifest('2.0.0'),
        'android',
      ).downloadUri.toString(),
      'http://server/erp.apk',
    );
    expect(
      () => AppUpdate.fromManifest(manifest('bad'), 'windows'),
      throwsFormatException,
    );
  });

  updateTest('current and newer installations can access the application', (
    tester,
  ) async {
    await pumpGate(tester, () async => manifest('1.2.8'));
    expect(find.text('ERP access'), findsOneWidget);
    expect(find.text('Update Required'), findsNothing);
  });

  updateTest('server failure permits access and retries after five minutes', (
    tester,
  ) async {
    var checks = 0;
    await pumpGate(tester, () async {
      checks++;
      throw Exception('offline');
    });
    expect(find.text('ERP access'), findsOneWidget);
    expect(checks, 1);
    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(checks, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(checks, 2);
    expect(find.text('ERP access'), findsOneWidget);
  });

  updateTest('new release blocks access and downloading does not unlock it', (
    tester,
  ) async {
    Uri? opened;
    await pumpGate(
      tester,
      () async => manifest('1.2.10'),
      launch: (uri) async {
        opened = uri;
        return true;
      },
    );
    expect(find.text('ERP access'), findsNothing);
    expect(find.text('Update Required'), findsOneWidget);
    await tester.tap(find.text('Update Now'));
    await tester.pumpAndSettle();
    expect(opened.toString(), 'http://server/erp.exe');
    expect(find.text('Update Required'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('ERP access'), findsNothing);
  });

  updateTest('required update stays blocked when subsequent check fails', (
    tester,
  ) async {
    var checks = 0;
    await pumpGate(tester, () async {
      if (checks++ == 0) return manifest('1.2.10');
      throw Exception('offline');
    });
    await tester.tap(find.text('Check Again'));
    await tester.pumpAndSettle();
    expect(find.text('ERP access'), findsNothing);
    expect(find.text('Update Required'), findsOneWidget);
  });

  updateTest('cached requirement cannot be bypassed by restarting offline', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'mandatory_update_windows': jsonEncode(manifest('1.2.10')),
    });
    await pumpGate(tester, () async => null);
    expect(find.text('Update Required'), findsOneWidget);
    expect(find.text('ERP access'), findsNothing);
  });

  updateTest('installing the required release clears the cached block', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'mandatory_update_windows': jsonEncode(manifest('1.2.10')),
    });
    await pumpGate(tester, () async => null, installed: '1.2.10');
    expect(find.text('ERP access'), findsOneWidget);
  });

  updateTest('a release found on resume blocks an already open screen', (
    tester,
  ) async {
    var checks = 0;
    await pumpGate(
      tester,
      () async => manifest(checks++ == 0 ? '1.2.9' : '1.2.10'),
    );
    expect(find.text('ERP access'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('ERP access'), findsNothing);
    expect(find.text('Update Required'), findsOneWidget);
  });

  updateTest('slow update server times out without locking users out', (
    tester,
  ) async {
    final request = Completer<Map<String, dynamic>?>();
    await tester.pumpWidget(
      MaterialApp(
        home: MandatoryUpdateGate(
          installedVersion: () async => '1.2.9',
          fetchManifest: () => request.future,
          child: const Scaffold(body: Text('ERP access')),
        ),
      ),
    );
    expect(find.text('ERP access'), findsOneWidget);
    expect(find.text('Checking for Updates'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('ERP access'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  updateTest('startup stays visible while background lookup is pending', (
    tester,
  ) async {
    final installed = Completer<String>();
    final release = Completer<Map<String, dynamic>?>();
    await tester.pumpWidget(
      MaterialApp(
        home: MandatoryUpdateGate(
          installedVersion: () => installed.future,
          fetchManifest: () => release.future,
          child: const Scaffold(body: Text('ERP access')),
        ),
      ),
    );
    expect(find.text('ERP access'), findsOneWidget);
    expect(find.text('Checking for Updates'), findsNothing);
    installed.complete('1.2.9');
    await tester.pumpAndSettle();
    expect(find.text('ERP access'), findsOneWidget);
    release.complete(manifest('1.2.10'));
    await tester.pumpAndSettle();
    expect(find.text('ERP access'), findsNothing);
    expect(find.text('Update Required'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
