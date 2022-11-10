import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl_standalone.dart'
    if (dart.library.html) 'package:intl/intl_browser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translations.dart';

class EasyLocalizationController extends ChangeNotifier {
  static Locale? _savedLocale;
  static late Locale _deviceLocale;

  late Locale _locale;
  Locale? _fallbackLocale;

  Locale? get fallbackLocale => _fallbackLocale;

  final Function(FlutterError e) onLoadError;

  // ignore: prefer_typing_uninitialized_variables
  final assetLoader;
  final String path;
  final bool useFallbackTranslations;
  final bool saveLocale;
  final bool useOnlyLangCode;
  Translations? _translations, _fallbackTranslations;

  Translations? get translations => _translations;

  Translations? get fallbackTranslations => _fallbackTranslations;

  Future<TranslationLoadResult?>? _waitTranslationLoad;
  Locale? _waitLocale;

  EasyLocalizationController({
    required List<Locale> supportedLocales,
    required this.useFallbackTranslations,
    required this.saveLocale,
    required this.assetLoader,
    required this.path,
    required this.useOnlyLangCode,
    required this.onLoadError,
    Locale? startLocale,
    Locale? fallbackLocale,
    Locale? forceLocale, // used for testing
  }) {
    _fallbackLocale = fallbackLocale;
    if (forceLocale != null) {
      _locale = forceLocale;
    } else if (_savedLocale == null && startLocale != null) {
      _locale = _getFallbackLocale(supportedLocales, startLocale);
      EasyLocalization.logger('Start locale loaded ${_locale.toString()}');
    }
    // If saved locale then get
    else if (saveLocale && _savedLocale != null) {
      EasyLocalization.logger('Saved locale loaded ${_savedLocale.toString()}');
      _locale = _savedLocale!;
    } else {
      // From Device Locale
      _locale = selectLocaleFrom(
        supportedLocales,
        _deviceLocale,
        fallbackLocale: fallbackLocale,
      );
    }
  }

  @visibleForTesting
  static Locale selectLocaleFrom(
    List<Locale> supportedLocales,
    Locale deviceLocale, {
    Locale? fallbackLocale,
  }) {
    final selectedLocale = supportedLocales.firstWhere(
      (locale) => locale.supports(deviceLocale),
      orElse: () => _getFallbackLocale(supportedLocales, fallbackLocale),
    );
    return selectedLocale;
  }

  //Get fallback Locale
  static Locale _getFallbackLocale(
      List<Locale> supportedLocales, Locale? fallbackLocale) {
    //If fallbackLocale not set then return first from supportedLocales
    if (fallbackLocale != null) {
      return fallbackLocale;
    } else {
      return supportedLocales.first;
    }
  }

  Future<TranslationLoadResult?> loadTranslations(
      Locale l, Locale? fallbackL) async {
    try {
      Translations translations;
      Translations? fallbackTranslations;
      final localData = await loadTranslationData(l);
      translations = Translations(localData);
      if (useFallbackTranslations && fallbackL != null) {
        Map<String, dynamic>? baseLangData;
        if (l.countryCode != null && l.countryCode!.isNotEmpty) {
          baseLangData =
              await loadBaseLangTranslationData(Locale(l.languageCode));
        }
        var fallbackData = await loadTranslationData(fallbackL);
        if (baseLangData != null) {
          try {
            fallbackData.addAll(baseLangData);
          } on UnsupportedError {
            fallbackData = Map.of(fallbackData)..addAll(baseLangData);
          }
        }
        fallbackTranslations = Translations(fallbackData);
      }
      return TranslationLoadResult(
        locale: l,
        translations: translations,
        fallbackTranslations: fallbackTranslations,
      );
    } on FlutterError catch (e) {
      onLoadError(e);
    } catch (e) {
      onLoadError(FlutterError(e.toString()));
    }
    return null;
  }

  Future<Map<String, dynamic>?> loadBaseLangTranslationData(
      Locale locale) async {
    try {
      return await loadTranslationData(Locale(locale.languageCode));
    } on FlutterError catch (e) {
      // Disregard asset not found FlutterError when attempting to load base language fallback
      EasyLocalization.logger.warning(e.message);
    }
    return null;
  }

  Future loadTranslationData(Locale locale) async {
    if (useOnlyLangCode) {
      return assetLoader.load(path, Locale(locale.languageCode));
    } else {
      return assetLoader.load(path, locale);
    }
  }

  Locale get locale => _locale;

  Future<void> setLocale(Locale l) async {
    if (_waitTranslationLoad != null) {
      _waitTranslationLoad = await _waitTranslationLoad!.then((value) {
        return loadTranslations(l, fallbackLocale);
      });
    } else {
      _waitTranslationLoad = loadTranslations(l, fallbackLocale);
    }

    await _waitTranslationLoad!.then((value) async {
      _waitTranslationLoad = null;
      if (value != null) {
        apply(value);
        notifyListeners();
        EasyLocalization.logger('Locale ${value.locale} changed');
        await _saveLocale(value.locale);
      }
    });
  }

  void apply(TranslationLoadResult translation) {
    _locale = translation.locale;
    _translations = translation.translations;
    if (translation.fallbackTranslations != null) {
      _fallbackTranslations = translation.fallbackTranslations;
    }
  }

  Future<void> _saveLocale(Locale? locale) async {
    if (!saveLocale) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('locale', locale.toString());
    EasyLocalization.logger('Locale $locale saved');
  }

  static Future<void> initEasyLocation() async {
    final preferences = await SharedPreferences.getInstance();
    final strLocale = preferences.getString('locale');
    _savedLocale = strLocale?.toLocale();
    final foundPlatformLocale = await findSystemLocale();
    _deviceLocale = foundPlatformLocale.toLocale();
    EasyLocalization.logger.debug('Localization initialized');
  }

  Future<void> deleteSaveLocale() async {
    _savedLocale = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('locale');
    EasyLocalization.logger('Saved locale deleted');
  }

  Locale get deviceLocale => _deviceLocale;

  Future<void> resetLocale() async {
    EasyLocalization.logger('Reset locale to platform locale $_deviceLocale');

    await setLocale(_deviceLocale);
  }
}

@visibleForTesting
extension LocaleExtension on Locale {
  bool supports(Locale locale) {
    if (this == locale) {
      return true;
    }
    if (languageCode != locale.languageCode) {
      return false;
    }
    if (countryCode != null &&
        countryCode!.isNotEmpty &&
        countryCode != locale.countryCode) {
      return false;
    }
    if (scriptCode != null && scriptCode != locale.scriptCode) {
      return false;
    }

    return true;
  }
}

class TranslationLoadResult {
  final Locale locale;
  final Translations translations;
  final Translations? fallbackTranslations;

  TranslationLoadResult({
    required this.locale,
    required this.translations,
    required this.fallbackTranslations,
  });
}
