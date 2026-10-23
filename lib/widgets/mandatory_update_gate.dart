import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_update.dart';
import '../services/api_service.dart';

class MandatoryUpdateGate extends StatefulWidget {
  final Widget child;
  final Future<String> Function()? installedVersion;
  final Future<Map<String, dynamic>?> Function()? fetchManifest;
  final Future<bool> Function(Uri)? openDownload;

  const MandatoryUpdateGate({
    super.key,
    required this.child,
    this.installedVersion,
    this.fetchManifest,
    this.openDownload,
  });

  @override
  State<MandatoryUpdateGate> createState() => _MandatoryUpdateGateState();
}

class _MandatoryUpdateGateState extends State<MandatoryUpdateGate>
    with WidgetsBindingObserver {
  static const _retryInterval = Duration(minutes: 5);
  Timer? _timer;
  bool _checking = false;
  bool _launching = false;
  AppUpdate? _requiredUpdate;
  String? _downloadError;

  String get _platform =>
      defaultTargetPlatform == TargetPlatform.android ? 'android' : 'windows';
  String get _cacheKey => 'mandatory_update_$_platform';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_checking) return;
    _timer?.cancel();
    setState(() => _checking = true);
    try {
      final installed =
          await (widget.installedVersion ?? ApiService.getCurrentAppVersion)();
      final prefs = await SharedPreferences.getInstance();
      if (_requiredUpdate == null) {
        final cached = prefs.getString(_cacheKey);
        if (cached != null) {
          try {
            final update = AppUpdate.fromManifest(
              Map<String, dynamic>.from(jsonDecode(cached) as Map),
              _platform,
            );
            if (update.isNewerThan(installed)) {
              if (!mounted) return;
              setState(() => _requiredUpdate = update);
            } else {
              await prefs.remove(_cacheKey);
            }
          } catch (_) {
            await prefs.remove(_cacheKey);
          }
        }
      } else if (!_requiredUpdate!.isNewerThan(installed)) {
        _requiredUpdate = null;
        await prefs.remove(_cacheKey);
      }
      final manifest =
          await (widget.fetchManifest ?? ApiService.fetchVersionInfo)().timeout(
            const Duration(seconds: 10),
          );
      if (manifest != null) {
        final update = AppUpdate.fromManifest(manifest, _platform);
        if (update.isNewerThan(installed)) {
          if (!mounted) return;
          // A failed download or later server failure must not unlock this client.
          setState(() => _requiredUpdate = update);
          await prefs.setString(
            _cacheKey,
            jsonEncode(update.toJson(_platform)),
          );
        }
      }
    } catch (_) {
      // An unavailable update server does not prevent normal app use.
    } finally {
      if (mounted) {
        setState(() => _checking = false);
        _timer = Timer(_retryInterval, _check);
      }
    }
  }

  Future<void> _download() async {
    final uri = _requiredUpdate?.downloadUri;
    if (uri == null) {
      setState(
        () => _downloadError =
            'Update download link is unavailable. Contact the administrator.',
      );
      return;
    }
    setState(() {
      _launching = true;
      _downloadError = null;
    });
    try {
      final launched =
          await (widget.openDownload ??
              (Uri uri) =>
                  launchUrl(uri, mode: LaunchMode.externalApplication))(uri);
      if (!launched && mounted)
        setState(
          () => _downloadError =
              'Could not open the update download. Please retry.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => _downloadError =
              'Could not open the update download. Please retry.',
        );
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _requiredUpdate != null;
    return Stack(
      children: [
        Offstage(
          offstage: blocked,
          child: TickerMode(enabled: !blocked, child: widget.child),
        ),
        if (blocked)
          PopScope(
            canPop: false,
            child: Scaffold(
              body: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.system_update, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            'Update Required',
                            style: Theme.of(context).textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          if (_requiredUpdate != null) ...[
                            Text(
                              'Install GEW ERP ${_requiredUpdate!.version} to continue.',
                              textAlign: TextAlign.center,
                            ),
                            if (_requiredUpdate!.changelog.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(_requiredUpdate!.changelog),
                            ],
                            if (_downloadError != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _downloadError!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _launching ? null : _download,
                              icon: const Icon(Icons.download),
                              label: Text(
                                _launching ? 'Opening Update...' : 'Update Now',
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _checking ? null : _check,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Check Again'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
