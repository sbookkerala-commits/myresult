import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// App launch screen — loads havells.com; 1s hold on header logo opens login.
class HavellsShellPage extends StatefulWidget {
  const HavellsShellPage({super.key, this.onSecretLogin});

  /// Called after holding the Havells header logo for 1 second.
  final void Function(BuildContext context)? onSecretLogin;

  static const String homeUrl = 'https://www.havells.com/';
  static const double headerHoldHeight = 88;
  static const double logoHoldWidth = 240;

  @override
  State<HavellsShellPage> createState() => _HavellsShellPageState();
}

class _HavellsShellPageState extends State<HavellsShellPage> {
  WebViewController? _controller;
  Timer? _holdTimer;
  bool _loading = true;

  bool get _supportsWebView {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return true;
      default:
        return false;
    }
  }

  @override
  void initState() {
    super.initState();
    if (_supportsWebView) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              if (mounted) setState(() => _loading = true);
            },
            onPageFinished: (_) {
              if (mounted) setState(() => _loading = false);
            },
          ),
        )
        ..loadRequest(Uri.parse(HavellsShellPage.homeUrl));
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _onHoldStart() {
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(seconds: 1), _openLogin);
  }

  void _onHoldEnd() {
    _holdTimer?.cancel();
  }

  void _openLogin() {
    _holdTimer?.cancel();
    if (!mounted) return;
    if (widget.onSecretLogin != null) {
      widget.onSecretLogin!(context);
      return;
    }
    Navigator.of(context).pushNamed('/login');
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(HavellsShellPage.homeUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_supportsWebView) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/icon/app_icon.png', height: 56),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _openInBrowser,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE31E24),
                ),
                child: const Text('Open Havells.com'),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _openLogin, child: const Text('Login')),
            ],
          ),
        ),
      );
    }

    final controller = _controller!;
    final topInset = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            SafeArea(
              top: true,
              bottom: false,
              child: WebViewWidget(controller: controller),
            ),
            if (_loading)
              const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFE31E24),
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              width: HavellsShellPage.logoHoldWidth,
              height: topInset + HavellsShellPage.headerHoldHeight,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _onHoldStart(),
                onPointerUp: (_) => _onHoldEnd(),
                onPointerCancel: (_) => _onHoldEnd(),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
