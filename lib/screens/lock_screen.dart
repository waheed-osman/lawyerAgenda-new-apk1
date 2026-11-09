import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/security.dart';

/// Wraps the whole app. Shows a lock overlay above everything (including
/// pushed routes) when a password is set and the app is opened/resumed.
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});
  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _ready = false;
  bool _locked = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Security.lockSignal.addListener(_lockNow);
    _init();
  }

  Future<void> _init() async {
    final has = await Security.hasPassword();
    if (!mounted) return;
    setState(() {
      _locked = has;
      _ready = true;
    });
  }

  Future<void> _lockNow() async {
    if (await Security.hasPassword() && mounted) setState(() => _locked = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _pausedAt != null) {
      final away = DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      final suspended = Security.suspend; // تُقرأ قبل أي await (منتقي الملفات/الكاميرا/المشاركة)
      final grace = await Security.graceSeconds();
      if (!suspended && away.inSeconds >= grace && await Security.hasPassword() && mounted) {
        setState(() => _locked = true);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Security.lockSignal.removeListener(_lockNow);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      if (!_ready)
        Positioned.fill(child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor))
      else if (_locked)
        Positioned.fill(
          child: Overlay(initialEntries: [
            OverlayEntry(builder: (_) => LockScreen(onUnlocked: () => setState(() => _locked = false))),
          ]),
        ),
    ]);
  }
}

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pw = TextEditingController();
  bool _bio = false;
  bool _numeric = false;
  bool _busy = false;
  int _pinLen = 0;
  int _wait = 0; // ثواني الإيقاف المؤقت بعد محاولات خاطئة
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    final enabled = await Security.biometricEnabled();
    final avail = enabled && await Security.biometricAvailable();
    final numeric = await Security.isNumeric();
    final len = await Security.pinLength();
    final wait = await Security.lockoutSeconds();
    if (!mounted) return;
    setState(() {
      _bio = avail;
      _numeric = numeric;
      _pinLen = len;
      _wait = wait;
    });
    if (wait > 0) _startTimer();
    if (avail && wait == 0) _tryBio();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final w = await Security.lockoutSeconds();
      if (!mounted) return;
      setState(() {
        _wait = w;
        if (w == 0) _error = null;
      });
      if (w == 0) _timer?.cancel();
    });
  }

  Future<void> _tryBio() async {
    if (await Security.authenticate()) {
      widget.onUnlocked();
    } else if (Security.lastBioError != null && mounted) {
      setState(() => _error = Security.lastBioError);
    }
  }

  Future<void> _submit() async {
    if (_busy || _wait > 0 || _pw.text.isEmpty) return;
    _busy = true;
    final r = await Security.tryUnlock(_pw.text);
    _pw.clear();
    if (r == UnlockResult.ok) {
      widget.onUnlocked();
    } else {
      final w = await Security.lockoutSeconds();
      final left = await Security.attemptsLeft();
      if (mounted) {
        setState(() {
          _wait = w;
          _error = w > 0 ? null : '${_numeric ? 'الرمز' : 'كلمة المرور'} غير صحيح — المتبقي $left محاولات';
        });
        if (w > 0) _startTimer();
      }
    }
    _busy = false;
  }

  String _waitText() {
    final m = (_wait ~/ 60).toString().padLeft(2, '0');
    final s = (_wait % 60).toString().padLeft(2, '0');
    return 'محاولات خاطئة كثيرة. حاول بعد $m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locked = _wait > 0;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.balance, size: 72, color: cs.primary),
                const SizedBox(height: 12),
                Text('أجندة المحامي القانونية',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 28),
                TextField(
                  controller: _pw,
                  enabled: !locked,
                  obscureText: true,
                  autofocus: !_bio,
                  textAlign: TextAlign.center,
                  keyboardType: _numeric ? TextInputType.number : TextInputType.visiblePassword,
                  inputFormatters: _numeric
                      ? [
                          FilteringTextInputFormatter.digitsOnly,
                          if (_pinLen > 0) LengthLimitingTextInputFormatter(_pinLen),
                        ]
                      : null,
                  style: _numeric ? const TextStyle(fontSize: 24, letterSpacing: 10) : null,
                  decoration: InputDecoration(
                    labelText: _numeric ? 'رمز PIN' : 'كلمة المرور',
                    errorText: locked ? _waitText() : _error,
                    errorMaxLines: 2,
                  ),
                  onChanged: (v) {
                    if (_numeric && _pinLen > 0 && v.length == _pinLen) _submit();
                  },
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: locked ? null : _submit, child: const Text('فتح'))),
                if (_bio) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: locked ? null : _tryBio,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('استخدام بصمة الإصبع'),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
