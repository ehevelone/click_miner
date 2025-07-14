// lib/fan_home_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundpool/soundpool.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'data/achievements_data.dart';
import 'data/achievement.dart';
import 'ad_helper.dart';

class FanHomePage extends StatefulWidget {
  final ValueChanged<ThemeMode> onThemeChanged;
  final ThemeMode currentTheme;

  const FanHomePage({
    Key? key,
    required this.onThemeChanged,
    required this.currentTheme,
  }) : super(key: key);

  @override
  _FanHomePageState createState() => _FanHomePageState();
}

class _FanHomePageState extends State<FanHomePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ─── Banner Ad fields ──────────────────────────────
  late final BannerAd _bannerAd;
  bool _bannerAdReady = false;

  // ─── Ads / countdowns ──────────────────────────────
  static const Duration _adInterval     = Duration(minutes: 5);
  static const int      _countdownStart = 15;
  Timer? _adIntervalTimer, _adCountdownTimer;
  int    _adCountdown     = 0;
  bool   _showAdCountdown = false;

  // ─── Ads watched counter ───────────────────────────
  int _adsPlayed = 0;

  // ─── Interstitial Ad ───────────────────────────────
  InterstitialAd? _interstitialAd;

  /// Called everywhere instead of the old placeholder
  Future<void> _showAd() async {
    if (_interstitialAd != null) {
      await _interstitialAd!.show();
      _interstitialAd!.dispose();
      _interstitialAd = null;
      // load next
      AdHelper.loadInterstitial().then((ad) => setState(() => _interstitialAd = ad));
    } else {
      await _showPlaceholderAd();
    }
  }

  /// Your old “fake ad” dialog
  Future<void> _showPlaceholderAd() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Advertisement', style: TextStyle(color: Colors.white)),
            SizedBox(height: 16),
            Container(
              width: 200, height: 100,
              color: Colors.grey[700],
              child: Center(child: Text('Your Ad Here', style: TextStyle(color: Colors.white70))),
            ),
          ],
        ),
      ),
    );
    await Future.delayed(Duration(seconds: 3));
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    setState(() => _adsPlayed++);
    await _saveState();
    _checkAchievements();
  }

  // ─── Earnings & bank ──────────────────────────────
  double _balance = 0;
  int    _dummyBankBalance = 0;

  // ─── Freeze / Auto Tap ─────────────────────────────
  bool _isFrozen = false, _isAuto = false;
  bool _isThermalCooling = false;
  Timer? _freezeTimer, _autoTimer, _autoStopTimer, _coolTimer;

  // ─── Double‐Earnings ────────────────────────────────
  bool   _isDouble = false;
  int    _doubleLeft = 0;
  Timer? _doubleTimer, _doubleCountdownTimer;

  // ─── Auto‐Tap countdown ─────────────────────────────
  int    _autoCountdown     = 0;
  bool   _showAutoCountdown = false;
  Timer? _autoCountdownTimer;

  // ─── Freeze‐GPU countdown ───────────────────────────
  int    _freezeCountdown      = 0;
  bool   _showFreezeCountdown  = false;
  Timer? _freezeCountdownTimer;

  // ─── Shop & Upgrades ───────────────────────────────
  final int    _maxGpus     = 35;
  final double _baseGpuCost = 5000, _maxGpuCost = 50000;
  late final double _gpuStep;
  double _priceMultiplier = 1.0;
  int _coolCost = 50, _systemCost = 10000;
  int _ownedGpus = 1, _ownedCooling = 0;

  // ─── Audio ──────────────────────────────────────────
  late final AudioPlayer _bgPlayer, _sfxPlayer;
  late final Soundpool   _pool;
  int _mineSoundId = 0, _bankSoundId = 0;
  bool _musicOn = true, _soundOn = true;

  // ─── Achievements ──────────────────────────────────
  late List<Achievement> _achievements;
  bool _achUpgradedGpu = false;

  // ─── Animation ─────────────────────────────────────
  static const int _frameCount = 24, _baseMs = 1000;
  late final AnimationController _fanController;
  late final List<Image> _frames;

  // ─── Temperature & BG ───────────────────────────────
  final double _minTemp = 30, _maxTemp = 90;
  late double  _temp;
  int _clickCount = 0, _steps = 30;
  double get _tNorm    => (_temp - _minTemp) / (_maxTemp - _minTemp);
  double get _speedMul => 0.5 + _tNorm * 2.5;
  Color  get _bgColor  => Color.lerp(Colors.blue, Colors.red, _tNorm)!;

  // ─── Earnings multiplier ────────────────────────────
  double _earnMultiplier = 1.0;

  // ─── Idle earnings ──────────────────────────────────
  final Duration _idleThreshold = Duration(minutes: 5);
  final String   _idleKey       = 'last_paused_timestamp';

  // ─── Layout constants ───────────────────────────────
  static const double actionRowHeight = 100.0;
  static const double iconHeight      = 64.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Create & load banner
    _bannerAd = AdHelper.createBannerAd(
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _bannerAdReady = true),
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
          debugPrint('Banner failed to load: $err');
        },
      ),
    )..load();

    // Load an interstitial now
    AdHelper.loadInterstitial().then((ad) => setState(() => _interstitialAd = ad));

    // Base setup
    _achievements = List.from(allAchievements);
    _gpuStep      = (_maxGpuCost - _baseGpuCost) / (_maxGpus - 1);
    _temp         = _minTemp;

    _loadState();
    _initAudio();
    _initAnimation();
    _startAdCycle();
  }

  // ─── Persisted state ────────────────────────────────
  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _balance         = prefs.getDouble('balance')         ?? _balance;
      _ownedGpus       = prefs.getInt('ownedGpus')         ?? _ownedGpus;
      _ownedCooling    = prefs.getInt('ownedCooling')      ?? _ownedCooling;
      _earnMultiplier  = prefs.getDouble('earnMultiplier') ?? _earnMultiplier;
      _priceMultiplier = prefs.getDouble('priceMultiplier')?? _priceMultiplier;
      _systemCost      = prefs.getInt('systemCost')        ?? _systemCost;
      _achUpgradedGpu  = prefs.getBool('achUpgradedGpu')   ?? _achUpgradedGpu;
      _adsPlayed       = prefs.getInt('adsPlayed')         ?? _adsPlayed;
    });
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs
      ..setDouble('balance',        _balance)
      ..setInt(   'ownedGpus',      _ownedGpus)
      ..setInt(   'ownedCooling',   _ownedCooling)
      ..setDouble('earnMultiplier', _earnMultiplier)
      ..setDouble('priceMultiplier',_priceMultiplier)
      ..setInt(   'systemCost',     _systemCost)
      ..setBool(  'achUpgradedGpu', _achUpgradedGpu)
      ..setInt(   'adsPlayed',      _adsPlayed);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      SharedPreferences.getInstance().then((p) =>
          p.setInt(_idleKey, DateTime.now().millisecondsSinceEpoch));
    } else if (state == AppLifecycleState.resumed) {
      _checkIdleEarnings();
    }
  }

  Future<void> _checkIdleEarnings() async {
    final prefs = await SharedPreferences.getInstance();
    final ms    = prefs.getInt(_idleKey);
    if (ms == null) return;
    final away = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (away > _idleThreshold) {
      final baseRate = _ownedGpus * _earnMultiplier;
      final rawEarn  = (away.inSeconds * baseRate).round();
      final earned   = (rawEarn * 0.25).round();
      if (earned > 0) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: Text('Welcome back!'),
            content: Text(
              'You earned $earned sats while idle.\n\n'
              'Watch a short ad now to double to ${earned * 2} sats?'
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() => _balance += earned);
                  _saveState();
                },
                child: Text('Keep $earned sats'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showAd().then((_) {
                    setState(() => _balance += earned * 2);
                    _saveState();
                    _checkAchievements();
                  });
                },
                child: Text('Watch Ad'),
              ),
            ],
          ),
        );
      }
    }
  }

  // ─── Audio setup ─────────────────────────────────────
  Future<void> _initAudio() async {
    _bgPlayer = AudioPlayer();
    await _bgPlayer.setSource(AssetSource('audio/my_background.mp3'));
    await _bgPlayer.setReleaseMode(ReleaseMode.loop);
    await _bgPlayer.resume();

    _sfxPlayer = AudioPlayer();
    _pool = Soundpool(streamType: StreamType.music);
    final mineData = await rootBundle.load('assets/audio/mine_coin.wav');
    _mineSoundId = await _pool.load(mineData);
    final bankData = await rootBundle.load('assets/audio/earn_coin_bank.wav');
    _bankSoundId = await _pool.load(bankData);
  }

  // ─── Fan animation ───────────────────────────────────
  void _initAnimation() {
    _frames = List.generate(
      _frameCount,
      (i) => Image.asset(
        'assets/images/frame_${i.toString().padLeft(3, '0')}.png',
        gaplessPlayback: true,
      ),
    );
    _fanController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _baseMs),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (var f in _frames) precacheImage(f.image, context);
    });
  }

  // ─── Ad cycle ────────────────────────────────────────
  void _startAdCycle() {
    _adIntervalTimer?.cancel();
    _adIntervalTimer = Timer(_adInterval, _beginAdCountdown);
  }

  void _beginAdCountdown() {
    setState(() {
      _adCountdown     = _countdownStart;
      _showAdCountdown = true;
    });
    _adCountdownTimer?.cancel();
    _adCountdownTimer = Timer.periodic(Duration(seconds: 1), (t) {
      if (_adCountdown <= 1) {
        t.cancel();
        setState(() => _showAdCountdown = false);
        SystemSound.play(SystemSoundType.click);
        _showAd().then((_) {
          SystemSound.play(SystemSoundType.click);
          _startAdCycle();
        });
      } else {
        setState(() => _adCountdown--);
      }
    });
  }

  // ─── UI countdown helpers ────────────────────────────
  void _beginFreezeCountdown(int secs) {
    _freezeCountdownTimer?.cancel();
    setState(() {
      _showFreezeCountdown = true;
      _freezeCountdown     = secs;
    });
    _freezeCountdownTimer = Timer.periodic(Duration(seconds: 1), (t) {
      if (_freezeCountdown <= 1) {
        t.cancel();
        setState(() => _showFreezeCountdown = false);
      } else {
        setState(() => _freezeCountdown--);
      }
    });
  }

  void _beginAutoCountdown(int secs) {
    _autoCountdownTimer?.cancel();
    setState(() {
      _showAutoCountdown = true;
      _autoCountdown     = secs;
    });
    _autoCountdownTimer = Timer.periodic(Duration(seconds: 1), (t) {
      if (_autoCountdown <= 1) {
        t.cancel();
        setState(() => _showAutoCountdown = false);
      } else {
        setState(() => _autoCountdown--);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bgPlayer.dispose();
    _sfxPlayer.dispose();
    _fanController.dispose();
    _adIntervalTimer?.cancel();
    _adCountdownTimer?.cancel();
    _freezeTimer?.cancel();
    _autoTimer?.cancel();
    _autoStopTimer?.cancel();
    _coolTimer?.cancel();
    _doubleTimer?.cancel();
    _doubleCountdownTimer?.cancel();
    _bannerAd.dispose();
    super.dispose();
  }

  // ─── Achievements logic ──────────────────────────────
  void _checkAchievements() {
    void unlock(String id) {
      final idx = _achievements.indexWhere((a) => a.id == id);
      if (idx != -1 && !_achievements[idx].unlocked) {
        setState(() => _achievements[idx].unlocked = true);
        _showAchievementDialog(_achievements[idx]);
      }
    }
    if (_balance.round() >= 10000) unlock('mine_10000');
    if (_ownedGpus >= 2)           unlock('first_gpu');
    if (_systemCost > _baseGpuCost) unlock('system_upgraded_1');
  }

  void _showAchievementDialog(Achievement a) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Achievement Unlocked!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(a.asset, height: 64),
            SizedBox(height: 12),
            Text(a.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            SizedBox(height: 8),
            Text(a.description),
          ],
        ),
        actions: [ TextButton(onPressed: () => Navigator.pop(context), child: Text('Nice!')) ],
      ),
    );
  }

  // ─── Core game actions: mine, freeze, auto, double ───
  void _updateFanSpeed() {
    final prog = _fanController.value;
    _fanController
      ..stop()
      ..duration = Duration(milliseconds: (_baseMs / _speedMul).round())
      ..forward(from: prog)
      ..repeat();
  }

  void _startCooldown() {
    _coolTimer?.cancel();
    if (_isFrozen || _isAuto) return;
    _coolTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
      if (_isFrozen || _isAuto) return;
      setState(() {
        final step = (_maxTemp - _minTemp) / _steps;
        final nextTemp = _temp - step;
        if (nextTemp <= _minTemp) {
          _temp = _minTemp;
          _isThermalCooling = false;
          _clickCount = 0;
          timer.cancel();
        } else {
          _temp = nextTemp;
        }
        _updateFanSpeed();
      });
    });
  }

  void _freezeGpu() {
    if (_isFrozen) return;
    HapticFeedback.mediumImpact();
    _showAd().then((_) {
      final secs = (10 * (1 + 0.05 * _ownedCooling)).round();
      setState(() {
        _isFrozen            = true;
        _freezeCountdown     = secs;
        _showFreezeCountdown = true;
      });
      _beginFreezeCountdown(secs);
      _coolTimer?.cancel();
      _freezeTimer?.cancel();
      _freezeTimer = Timer(Duration(seconds: secs), () {
        setState(() => _isFrozen = false);
        _startCooldown();
      });
    });
  }

  void _mine() {
    _clickCount = (((_temp - _minTemp) / (_maxTemp - _minTemp)) * _steps).round();
    HapticFeedback.lightImpact();
    if (_soundOn && _mineSoundId != 0) _pool.play(_mineSoundId);
    final earn = (_isDouble ? 2 : 1) * _ownedGpus * _earnMultiplier;
    _balance += earn;
    _saveState();
    _checkAchievements();
    setState(() {
        if (_isFrozen || _isAuto) return;    // ← add “|| _isAuto” here
        _coolTimer?.cancel();
        _clickCount++;
    _temp = (_minTemp + (_clickCount / _steps) * (_maxTemp - _minTemp))
       .clamp(_minTemp, _maxTemp);
     if (_temp >= _maxTemp) {
        _isThermalCooling = true;
        _temp             = _maxTemp;
  }
      _updateFanSpeed();
      _coolTimer = Timer(Duration(milliseconds: 500), _startCooldown);
    });
  }

  void _autoTap() {
    if (_isAuto) return;
    HapticFeedback.mediumImpact();
    _showAd().then((_) {
      setState(() {
        _isAuto = true;
        _autoCountdown = 30;
        _showAutoCountdown = true;
      });
      _beginAutoCountdown(_autoCountdown);
      _autoTimer?.cancel();
      _autoTimer = Timer.periodic(Duration(milliseconds: 200), (_) {
        final earn = (_isDouble ? 2 : 1) * _ownedGpus * _earnMultiplier;
        setState(() => _balance += earn);
        _saveState();
        _checkAchievements();
      });
      _autoStopTimer?.cancel();
      _autoStopTimer = Timer(Duration(seconds: _autoCountdown), () {
        _autoTimer?.cancel();
        setState(() => _isAuto = false);
        _startCooldown();
      });
    });
  }

  void _earnDouble() {
    if (_isDouble) return;
    HapticFeedback.mediumImpact();
    _showAd().then((_) {
      setState(() {
        _isDouble = true;
        _doubleLeft = 30;
      });
      _doubleTimer?.cancel();
      _doubleTimer = Timer(Duration(seconds: 30), () {
        setState(() => _isDouble = false);
      });
      _doubleCountdownTimer?.cancel();
      _doubleCountdownTimer = Timer.periodic(Duration(seconds: 1), (t) {
        if (_doubleLeft <= 1) t.cancel();
        else setState(() => _doubleLeft--);
      });
    });
  }

  void _buyGpu() {
    final cost = (_baseGpuCost + _gpuStep * (_ownedGpus - 1)) * _priceMultiplier;
    if (_balance >= cost && _ownedGpus < _maxGpus) {
      HapticFeedback.mediumImpact();
      setState(() {
        _balance -= cost;
        _ownedGpus++;
        _checkAchievements();
      });
      _saveState();
    }
  }

  void _buyCoolingGpu() {
    final cost = _coolCost * _priceMultiplier;
    if (_balance >= cost) {
      HapticFeedback.mediumImpact();
      setState(() {
        _balance -= cost;
        _ownedCooling++;
        _checkAchievements();
      });
      _saveState();
    }
  }

  void _upgradeSystem() {
    if (_balance >= _systemCost) {
      HapticFeedback.mediumImpact();
      setState(() {
        _balance -= _systemCost;
        _ownedGpus = 1;
        _earnMultiplier *= 1.1;
        _priceMultiplier*= 1.1;
        _systemCost = (_systemCost * 1.1).round();
        _achUpgradedGpu = true;
        _checkAchievements();
      });
      _saveState();
    }
  }

  void _showCashoutDialog() {
    String username = '';
    String password = '';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Cash Out to ZBD'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('You have $_dummyBankBalance sats in your bank.'),
            SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(labelText: 'ZBD Username'),
              onChanged: (v) => username = v,
            ),
            TextField(
              decoration: InputDecoration(labelText: 'Password'),
              obscureText: true,
              onChanged: (v) => password = v,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Cashing out $_dummyBankBalance sats…')),
              );
              setState(() => _dummyBankBalance = 0);
              _saveState();
            },
            child: Text('Cash Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mineButtonHeight = MediaQuery.of(context).size.height * 0.15;
    final sats            = _balance.round();
    final balanceText    = sats < 100000000
        ? '$sats sats'
        : '${(_balance / 100000000).toStringAsFixed(0)} BTC';

    // Banner height
    final adHeight = _bannerAd.size.height.toDouble();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      // AppBar
      appBar: AppBar(title: Text('GPU Duplicator Demo')),

      // Drawer
      drawer: _buildDrawer(),

      // Body
      body: Column(
        children: [
          // Banner at top
          if (_bannerAdReady)
            Container(
              width: _bannerAd.size.width.toDouble(),
              height: adHeight,
              color: Theme.of(context).scaffoldBackgroundColor,
              child: AdHelper.bannerAdWidget(_bannerAd),
            ),

          // 1) Balance & Bank Row
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    balanceText,
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                GestureDetector(
                  onTap: _showCashoutDialog,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset('assets/images/bank_button.png', height: 36),
                      Text(
                        '$_dummyBankBalance',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2) Timers & Temp Row
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            child: Wrap(
              spacing: 16, runSpacing: 4, alignment: WrapAlignment.center, children: [
                if (_showAdCountdown)
                  Text('Ad in $_adCountdown s', style: TextStyle(color: Colors.yellow, fontSize: 16)),
                if (_isDouble)
                  Text('2× Active: $_doubleLeft s', style: TextStyle(color: Colors.lightGreenAccent, fontSize: 16)),
                if (_showAutoCountdown)
                  Text('Auto-Tap: $_autoCountdown s', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 16)),
                if (_showFreezeCountdown)
                  Text('Frozen: $_freezeCountdown s', style: TextStyle(color: Colors.cyanAccent, fontSize: 16)),
                Text('Temp: ${_temp.toStringAsFixed(1)}°F', style: TextStyle(color: Colors.white70, fontSize: 16)),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 3) Fan Grid
          Expanded(child: _buildFanGrid()),
          const Spacer(),

          // 4) System Upgrade badge + price
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: Opacity(
                opacity: _balance < _systemCost ? 0.4 : 1.0,
                child: GestureDetector(
                  onTap: _upgradeSystem,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/images/upgrade_system.png', height: iconHeight),
                      const SizedBox(height: 4),
                      Text('${_systemCost} sats', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 5) Action Row
          SizedBox(
            height: actionRowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _actionBtn('freeze_gpu_art.png', _freezeGpu, 'Watch AD', iconHeight),
                  const SizedBox(width: 8),
                  _actionBtn('gpu_cooling_button_v2.png', _buyCoolingGpu, '$_coolCost sats', iconHeight),
                  const SizedBox(width: 8),
                  _actionBtn('upgrade_gpu_button.png', _buyGpu, '${(_baseGpuCost + _gpuStep * (_ownedGpus - 1) * _priceMultiplier).round()} sats', iconHeight),
                  const SizedBox(width: 8),
                  _actionBtn('auto_tap_button.png', _autoTap, 'Watch AD', iconHeight),
                  const SizedBox(width: 8),
                  _actionBtn('earn_2x.png', _earnDouble, 'Watch AD', iconHeight),
                ],
              ),
            ),
          ),
        ],
      ),

      // Bottom Nav: Mine button only
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: AbsorbPointer(
              absorbing: _isThermalCooling,
              child: Opacity(
                opacity: _isThermalCooling ? 0.4 : 1.0,
                child: GestureDetector(
                  onTap: _mine,
                  child: Image.asset('assets/images/mine_button.png', height: mineButtonHeight, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Drawer _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.blue),
            child: Text('Menu', style: TextStyle(color: Colors.white, fontSize: 24)),
          ),
          ExpansionTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            children: [
              SwitchListTile(
                title: const Text('Music'),
                value: _musicOn,
                onChanged: (v) {
                  setState(() => _musicOn = v);
                  if (v) _bgPlayer.resume(); else _bgPlayer.pause();
                  _saveState();
                },
              ),
              SwitchListTile(
                title: const Text('Sound Effects'),
                value: _soundOn,
                onChanged: (v) {
                  setState(() => _soundOn = v);
                  _saveState();
                },
              ),
            ],
          ),
          ListTile(
            leading: const Icon(Icons.emoji_events, color: Colors.amber),
            title: const Text('Achievements'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AchievementsPage(achievements: _achievements)),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Theme'),
            trailing: DropdownButton<ThemeMode>(
              value: widget.currentTheme,
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
              onChanged: (mode) {
                if (mode != null) widget.onThemeChanged(mode);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFanGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LayoutBuilder(builder: (_, c) {
        final cols = _ownedGpus < 7 ? _ownedGpus : 7;
        final tileW = c.maxWidth / cols;
        return Wrap(
          spacing: 0,
          runSpacing: 0,
          children: List.generate(_ownedGpus, (_) {
            return SizedBox(
              width: tileW, height: tileW,
              child: Container(
                color: _bgColor,
                child: AnimatedBuilder(
                  animation: _fanController,
                  builder: (_, __) {
                    final idx = (_fanController.value * _frames.length).floor() % _frames.length;
                    return _frames[idx];
                  },
                ),
              ),
            );
          }),
        );
      }),
    );
  }

  Widget _actionBtn(String asset, VoidCallback onTap, String label, double h) {
    return Expanded(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(onTap: onTap, child: Image.asset('assets/images/$asset', height: h, fit: BoxFit.contain)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.white, fontSize: 12)),
      ]),
    );
  }
}

/// Achievements page, unchanged
class AchievementsPage extends StatelessWidget {
  final List<Achievement> achievements;
  const AchievementsPage({Key? key, required this.achievements}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final unlocked = achievements.where((a) => a.unlocked).toList();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Achievements'), backgroundColor: Colors.black),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: unlocked.isEmpty
            ? Center(child: Text('No achievements yet!', style: TextStyle(color: Colors.white54, fontSize: 16)))
            : GridView.builder(
                itemCount: unlocked.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, childAspectRatio: 1, mainAxisSpacing: 16, crossAxisSpacing: 16,
                ),
                itemBuilder: (context, i) {
                  final a = unlocked[i];
                  return Column(
                    children: [
                      Image.asset(a.asset, height: 80),
                      const SizedBox(height: 8),
                      Text(a.title, textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(a.description, textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
