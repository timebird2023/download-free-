import 'dart:async';
import 'package:flutter/widgets.dart';

/// خدمة الإعلانات المحايدة (Ad-Free Service)
/// تم إزالة جميع شبكات الإعلانات البرمجية (Unity Ads / AdMob) نهائياً لتوفير تجربة مستخدم سريعة،
/// نظيفة، خفيفة على الذاكرة والبطارية وبدون أي مقاطعة أثناء التحميل أو المشاهدة.
class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  bool get isInitialized => false;
  final ValueNotifier<bool> isInitializedNotifier = ValueNotifier<bool>(false);
  bool get isInterstitialLoaded => false;

  /// تهيئة محايدة بدون أي مكتبات إعلانات
  static Future<void> init({bool testMode = false}) async {
    // التطبيق خالٍ تماماً من الإعلانات
  }

  Future<void> setTestMode(bool enabled) async {}

  void loadInterstitialAd() {}

  /// إغلاق الإعلان تلقائياً وتنفيذ الإجراء مباشرة دون أي تعطيل أو انتظار
  void showInterstitialAd({VoidCallback? onAdClosed}) {
    if (onAdClosed != null) {
      onAdClosed();
    }
  }

  /// إرجاع ويدجت فارغ تماماً بدون استهلاك أي مساحة على الشاشة
  Widget buildBannerWidget({
    VoidCallback? onLoaded,
    Function(String, dynamic, String)? onFailed,
  }) {
    return const SizedBox.shrink();
  }
}
