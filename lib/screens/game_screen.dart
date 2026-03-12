import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import '../core/feature_registry.dart';
import '../features/zoom/zoom_feature.dart';
import '../features/afk_timer/afk_timer_feature.dart';
import '../widgets/side_panel_drawer.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  InAppWebViewController? _webViewController;

  final String _currentUrl        = 'https://play.rn04.rs/rs2.cgi';
  final String _currentWorldLabel = 'RN04';
  bool   _pageLoading = true;
  int    _loadGen     = 0;

  // ── Per-tab zoom ──────────────────────────────────────────────────────────
  final List<double> _tabZoom = [0.90, 1.00, 1.00];
  static const List<String> _tabZoomKeys = [
    'zoom_game', 'zoom_hiscores', 'zoom_market'
  ];

  double get _currentZoom => _tabZoom[_activeTab];

  // ── Tabs ──────────────────────────────────────────────────────────────────
  int _activeTab = 0;
  InAppWebViewController? _hiscoresController;
  bool _hiscoresLoading = false;
  InAppWebViewController? _marketController;
  bool _marketLoading = false;

  // ── Ping ──────────────────────────────────────────────────────────────────
  int?   _pingMs;
  Timer? _pingTimer;
  static const String _pingHost = 'https://play.rn04.rs/';

  // ── AFK Timer ─────────────────────────────────────────────────────────────
  AfkTimerSettings _afkSettings = const AfkTimerSettings();
  int    _afkRemaining = 90;
  bool   _afkAlerted   = false;
  Timer? _afkTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // ── JS ────────────────────────────────────────────────────────────────────
  static const String _fullscreenJS = r'''
    (function makeFullscreen() {
      var iframe = document.querySelector('iframe.gameframe');
      if (!iframe) { setTimeout(makeFullscreen, 300); return; }

      iframe.style.cssText =
        'position:fixed!important;top:0!important;left:0!important;' +
        'width:100%!important;height:100%!important;' +
        'border:none!important;margin:0!important;padding:0!important;' +
        'z-index:1!important;display:block!important;';

      var header = document.querySelector('.gameframe-top');
      if (header) header.style.setProperty('display', 'none', 'important');

      document.body.style.cssText =
        'margin:0!important;padding:0!important;' +
        'overflow:hidden!important;background:#000!important;' +
        'touch-action:none!important;';
      document.documentElement.style.cssText =
        'margin:0!important;padding:0!important;' +
        'overflow:hidden!important;touch-action:none!important;';

      if (!window._lkScrollLocked) {
        window._lkScrollLocked = true;
        document.addEventListener('touchmove', function(e) {
          var node = e.target;
          while (node) {
            if (node.tagName === 'IFRAME') return;
            node = node.parentElement;
          }
          e.preventDefault();
        }, { passive: false });
      }

      window._lkReady = true;
    })();
  ''';

  static String _zoomJS(double zoom) =>
      "document.documentElement.style.setProperty('zoom', '$zoom', 'important');";

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _registerFeatures();
    _startPing();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.setSource(AssetSource('sounds/afk_alert.mp3'));
      debugPrint('AFK audio pre-loaded OK');
    } catch (e) {
      debugPrint('AFK audio init skipped: $e');
    }
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _afkTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ── Prefs ─────────────────────────────────────────────────────────────────

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final zoomGame      = prefs.getDouble('zoom_game')      ?? 0.90;
    final zoomHiscores  = prefs.getDouble('zoom_hiscores')  ?? 1.00;
    final zoomMarket    = prefs.getDouble('zoom_market')    ?? 1.00;

    final afkThreshold  = prefs.getInt('afk_threshold')  ?? 10;
    final afkSound      = prefs.getBool('afk_sound')      ?? true;
    final afkVibration  = prefs.getBool('afk_vibration')  ?? true;

    if (mounted) {
      setState(() {
        _tabZoom[0] = zoomGame;
        _tabZoom[1] = zoomHiscores;
        _tabZoom[2] = zoomMarket;
        _afkSettings = AfkTimerSettings(
          enabled          : false,
          soundEnabled     : afkSound,
          vibrationEnabled : afkVibration,
          thresholdSeconds : afkThreshold,
          durationSeconds  : 90,
        );
        _afkRemaining = _afkSettings.durationSeconds;
      });
      _registerFeatures();
    }
  }

  Future<void> _saveAfkSettings(AfkTimerSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt ('afk_threshold',  s.thresholdSeconds);
    await prefs.setBool('afk_sound',      s.soundEnabled);
    await prefs.setBool('afk_vibration',  s.vibrationEnabled);
  }

  // ── Features ──────────────────────────────────────────────────────────────

  void _registerFeatures() {
    FeatureRegistry.features.clear();
    FeatureRegistry.registerAll([
      ZoomFeature(
        currentZoom   : _currentZoom,
        onZoomChanged : _onZoomChanged,
      ),
      AfkTimerFeature(
        settings         : _afkSettings,
        onSettingsChanged: _onAfkSettingsChanged,
      ),
    ]);
  }

  void _onZoomChanged(double zoom) async {
    setState(() => _tabZoom[_activeTab] = zoom);
    final ctrl = _controllerForTab(_activeTab);
    ctrl?.evaluateJavascript(source: _zoomJS(zoom));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_tabZoomKeys[_activeTab], zoom);
    _registerFeatures();
  }

  InAppWebViewController? _controllerForTab(int tab) {
    switch (tab) {
      case 0: return _webViewController;
      case 1: return _hiscoresController;
      case 2: return _marketController;
      default: return null;
    }
  }

  void _onAfkSettingsChanged(AfkTimerSettings next) {
    setState(() => _afkSettings = next);
    _saveAfkSettings(next);
    if (next.enabled) {
      _resetAfkTimer();
    } else {
      _afkTimer?.cancel();
      setState(() {
        _afkRemaining = next.durationSeconds;
        _afkAlerted   = false;
      });
    }
    _registerFeatures();
  }

  void _openPanel() {
    _registerFeatures();
    _scaffoldKey.currentState?.openDrawer();
  }

  void _switchTab(int index) {
    setState(() => _activeTab = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controllerForTab(index)
          ?.evaluateJavascript(source: _zoomJS(_tabZoom[index]));
    });
    _registerFeatures();
  }

  // ── AFK Timer ─────────────────────────────────────────────────────────────

  void _onGameTouch() {
    if (!_afkSettings.enabled) return;
    _resetAfkTimer();
  }

  void _resetAfkTimer() {
    _afkTimer?.cancel();
    _afkAlerted = false;
    if (mounted) setState(() => _afkRemaining = _afkSettings.durationSeconds);
    debugPrint('AFK timer reset → ${_afkSettings.durationSeconds}s  threshold=${_afkSettings.thresholdSeconds}s');

    _afkTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }

      setState(() => _afkRemaining--);

      debugPrint('AFK tick: $_afkRemaining  alerted=$_afkAlerted');

      if (!_afkAlerted && _afkRemaining <= _afkSettings.thresholdSeconds) {
        _afkAlerted = true;
        debugPrint('AFK ALERT FIRING — sound=${_afkSettings.soundEnabled}  vib=${_afkSettings.vibrationEnabled}');
        _triggerAfkAlert();
      }
    });
  }

  Future<void> _triggerAfkAlert() async {
    debugPrint('_triggerAfkAlert() entered');

    if (_afkSettings.soundEnabled) {
      try {
        await _audioPlayer.resume();
        debugPrint('AFK sound resume() OK');
      } catch (e) {
        debugPrint('AFK sound error: $e');
        try {
          await _audioPlayer.play(AssetSource('sounds/afk_alert.mp3'));
          debugPrint('AFK sound fallback play() OK');
        } catch (e2) {
          debugPrint('AFK sound fallback error: $e2');
        }
      }
    }

    if (_afkSettings.vibrationEnabled) {
      try {
        final hasVibrator = await Vibration.hasVibrator() ?? false;
        if (hasVibrator) {
          await Vibration.vibrate(
            pattern    : [0, 400, 150, 400, 150, 400],
            intensities: [0, 255, 0,   255, 0,   255],
          );
          debugPrint('AFK vibration fired');
        } else {
          debugPrint('AFK vibration: no vibrator found on device');
        }
      } catch (e) {
        debugPrint('AFK vibration error: $e');
      }
    }

    debugPrint('_triggerAfkAlert() complete');
  }

  // ── Ping ──────────────────────────────────────────────────────────────────

  void _startPing() {
    _measurePing();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _measurePing());
  }

  Future<void> _measurePing() async {
    try {
      final sw     = Stopwatch()..start();
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);
      final req = await client.headUrl(Uri.parse(_pingHost));
      final res = await req.close();
      await res.drain<void>();
      sw.stop();
      client.close(force: false);
      if (mounted) setState(() => _pingMs = sw.elapsedMilliseconds);
    } catch (_) {
      if (mounted) setState(() => _pingMs = null);
    }
  }

  Color _pingColor(int ms) {
    if (ms <= 80)  return const Color(0xFF44CC44);
    if (ms <= 150) return const Color(0xFFCCAA00);
    return const Color(0xFFCC0000);
  }

  // ── WebView helpers ───────────────────────────────────────────────────────

  Future<void> _applyFullscreen(InAppWebViewController ctrl, int gen) async {
    const pollInterval = Duration(milliseconds: 400);
    const maxAttempts  = 30;

    for (int i = 0; i < maxAttempts; i++) {
      if (!mounted || _loadGen != gen) return;
      await ctrl.evaluateJavascript(source: _fullscreenJS);
      await Future.delayed(pollInterval);
      if (!mounted || _loadGen != gen) return;

      final ready = await ctrl.evaluateJavascript(source: 'window._lkReady === true;');
      if (ready == true || ready == 'true') {
        await ctrl.evaluateJavascript(source: _zoomJS(_tabZoom[0]));
        if (mounted && _loadGen == gen) setState(() => _pageLoading = false);
        return;
      }
    }
    await ctrl.evaluateJavascript(source: _zoomJS(_tabZoom[0]));
    if (mounted && _loadGen == gen) setState(() => _pageLoading = false);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: true,
      drawerScrimColor: Colors.transparent,
      drawer: const SidePanelDrawer(),
      body: Stack(
        children: [

          // ── Both tabs always mounted, game runs in background ──────
          IndexedStack(
            index: _activeTab,
            children: [

              // ── Tab 0: Game ────────────────────────────────────────
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _onGameTouch(),
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled               : true,
                    mediaPlaybackRequiresUserGesture: false,
                    allowsInlineMediaPlayback       : true,
                    useHybridComposition            : true,
                    supportZoom                     : false,
                    builtInZoomControls             : false,
                    displayZoomControls             : false,
                    horizontalScrollBarEnabled      : false,
                    verticalScrollBarEnabled        : false,
                    userAgent: 'Mozilla/5.0 (Linux; Android 11; Mobile) RN04Launcher/1.0',
                  ),
                  onWebViewCreated: (controller) {
                    _webViewController = controller;
                  },
                  onLoadStart: (controller, url) {
                    _loadGen++;
                    controller.evaluateJavascript(source: 'window._lkReady = false;');
                    if (mounted) setState(() => _pageLoading = true);
                  },
                  onLoadStop: (controller, url) async {
                    final gen = _loadGen;
                    await _applyFullscreen(controller, gen);
                  },
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final url = navigationAction.request.url?.toString() ?? '';
                    if (url.startsWith('https://play.rn04.rs/') || url.isEmpty) {
                      return NavigationActionPolicy.ALLOW;
                    }
                    return NavigationActionPolicy.CANCEL;
                  },
                  onReceivedError: (controller, request, error) {
                    debugPrint('WebView error: ${error.description}');
                    if (mounted) setState(() => _pageLoading = false);
                  },
                ),
              ),

              // ── Tab 1: Hiscores ────────────────────────────────────
              InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri('https://highscores.rn04.rs'),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled         : true,
                  useHybridComposition      : true,
                  supportZoom               : true,
                  horizontalScrollBarEnabled: false,
                  verticalScrollBarEnabled  : false,
                ),
                onWebViewCreated: (controller) {
                  _hiscoresController = controller;
                },
                onLoadStart: (controller, url) {
                  if (mounted) setState(() => _hiscoresLoading = true);
                },
                onLoadStop: (controller, url) {
                  if (mounted) setState(() => _hiscoresLoading = false);
                },
                onReceivedError: (controller, request, error) {
                  if (mounted) setState(() => _hiscoresLoading = false);
                },
              ),

              // ── Tab 2: Market ──────────────────────────────────────
              InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri('https://markets.rn04.rs'),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled         : true,
                  useHybridComposition      : true,
                  supportZoom               : true,
                  horizontalScrollBarEnabled: false,
                  verticalScrollBarEnabled  : false,
                ),
                onWebViewCreated: (controller) {
                  _marketController = controller;
                },
                onLoadStart: (controller, url) {
                  if (mounted) setState(() => _marketLoading = true);
                },
                onLoadStop: (controller, url) {
                  if (mounted) setState(() => _marketLoading = false);
                },
                onReceivedError: (controller, request, error) {
                  if (mounted) setState(() => _marketLoading = false);
                },
              ),
            ],
          ),

          // ── Game loading overlay ───────────────────────────────────
          if (_pageLoading && _activeTab == 0)
            Container(
              color: const Color(0xFF000000),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFFCC0000)),
                    const SizedBox(height: 16),
                    const Text('Loading game...',
                        style: TextStyle(fontFamily: 'RuneScape',
                            color: Color(0xFFC8A450), fontSize: 14, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Text(_currentWorldLabel,
                        style: const TextStyle(fontFamily: 'RuneScape',
                            color: Color(0xFF666666), fontSize: 11)),
                  ],
                ),
              ),
            ),

          // ── Top bar ────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Menu button
                  GestureDetector(
                    onTap: _openPanel,
                    child: _FloatButton(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (_) => Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          width: 16, height: 2,
                          color: const Color(0xFFC8A450),
                        )),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),

                  // ── Left column: ping → tabs ───────────────────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Ping row
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        color: const Color(0xAA000000),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5, height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _pingMs != null
                                    ? _pingColor(_pingMs!)
                                    : const Color(0xFF444444),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _pingMs != null ? '${_pingMs}ms' : '---',
                              style: TextStyle(
                                fontFamily: 'RuneScape',
                                fontSize  : 9,
                                color     : _pingMs != null
                                    ? _pingColor(_pingMs!)
                                    : const Color(0xFF555555),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),

                      // RN04 tab chip
                      _TabChip(
                        label: _currentWorldLabel,
                        icon: Icons.sports_esports,
                        active: _activeTab == 0,
                        onTap: () => _switchTab(0),
                      ),
                      const SizedBox(height: 2),

                      // Hiscores tab chip
                      _TabChip(
                        label: 'Hiscores',
                        icon: Icons.leaderboard,
                        active: _activeTab == 1,
                        loading: _hiscoresLoading && _activeTab == 1,
                        onTap: () => _switchTab(1),
                      ),
                      const SizedBox(height: 2),

                      // Market tab chip
                      _TabChip(
                        label: 'Market',
                        icon: Icons.storefront,
                        active: _activeTab == 2,
                        loading: _marketLoading && _activeTab == 2,
                        onTap: () => _switchTab(2),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── AFK badge (game tab only) ──────────────────────────────
          if (_afkSettings.enabled && _activeTab == 0)
            Positioned(
              top: 44, right: 6,
              child: _AfkBadge(
                remaining       : _afkRemaining,
                thresholdSeconds: _afkSettings.thresholdSeconds,
              ),
            ),
        ],
      ),
    );
  }
}

// ── AFK countdown badge ───────────────────────────────────────────────────────

class _AfkBadge extends StatelessWidget {
  final int remaining;
  final int thresholdSeconds;

  const _AfkBadge({
    required this.remaining,
    required this.thresholdSeconds,
  });

  Color get _color {
    if (remaining < 0)                       return const Color(0xFF4499FF);
    if (remaining <= thresholdSeconds)       return const Color(0xFFCC0000);
    if (remaining <= thresholdSeconds + 10)  return const Color(0xFFCCAA00);
    return const Color(0xFF44CC44);
  }

  String get _label {
    if (remaining >= 0) {
      final m = remaining ~/ 60;
      final s = remaining % 60;
      return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    } else {
      final abs = remaining.abs();
      final m   = abs ~/ 60;
      final s   = abs % 60;
      return '-${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color : const Color(0xCC000000),
        border: Border.all(color: _color.withOpacity(0.6), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'AFK',
            style: TextStyle(
              fontFamily   : 'RuneScape',
              fontSize     : 9,
              color        : _color.withOpacity(0.8),
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _label,
            style: TextStyle(
              fontFamily : 'RuneScape',
              fontSize   : 18,
              fontWeight : FontWeight.bold,
              color      : _color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab chip widget ───────────────────────────────────────────────────────────

class _TabChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final bool loading;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xCC000000) : const Color(0x88000000),
          border: Border.all(
            color: active ? const Color(0xFFCC0000) : const Color(0x44888888),
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            loading
                ? const SizedBox(
                    width: 10, height: 10,
                    child: CircularProgressIndicator(
                      color: Color(0xFFC8A450), strokeWidth: 1.5),
                  )
                : Icon(icon,
                    size: 11,
                    color: active
                        ? const Color(0xFFC8A450)
                        : const Color(0xFF666666)),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 80),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'RuneScape',
                  fontSize: 10,
                  color: active
                      ? const Color(0xFFC8A450)
                      : const Color(0xFF666666),
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloatButton extends StatelessWidget {
  final Widget child;
  const _FloatButton({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34, height: 34,
      decoration: BoxDecoration(
        color : const Color(0xBB000000),
        border: Border.all(color: const Color(0x558B6914)),
      ),
      child: Center(child: child),
    );
  }
}
