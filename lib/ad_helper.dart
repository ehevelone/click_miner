// lib/ad_helper.dart

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdHelper {
  // ─── Test Ad Unit IDs (replace with your real ones) ────
  static String get bannerAdUnitId =>
      'ca-app-pub-3940256099942544/6300978111';
  static String get interstitialAdUnitId =>
      'ca-app-pub-3940256099942544/1033173712';

  /// 1) Initialize the Mobile Ads SDK. Call once in main().
  static Future<InitializationStatus> initializeAds() {
    return MobileAds.instance.initialize();
  }

  /// 2) Create & load a BannerAd.
  static BannerAd createBannerAd({required BannerAdListener listener}) {
    return BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: AdRequest(),
      listener: listener,
    )..load();
  }

  /// 3) Wrap a BannerAd in a widget.
  static Widget bannerAdWidget(BannerAd ad) {
    return Container(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }

  /// 4) Load an InterstitialAd for later showing.
  static Future<InterstitialAd?> loadInterstitial() async {
    InterstitialAd? loadedAd;
    await InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          loadedAd = ad;
        },
        onAdFailedToLoad: (err) {
          debugPrint('Failed to load interstitial: $err');
        },
      ),
    );
    return loadedAd;
  }

  /// 5) Show a preloaded InterstitialAd and dispose it when done.
  /// 
  /// Caller should immediately call `loadInterstitial()` again
  /// and store the result in your `_interstitialAd` field.
  static void showInterstitial(InterstitialAd? ad) {
    if (ad == null) return;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        debugPrint('Interstitial displayed');
      },
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('Interstitial dismissed');
        ad.dispose();
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        debugPrint('Failed to show interstitial: $err');
        ad.dispose();
      },
    );
    ad.show();
  }
}
