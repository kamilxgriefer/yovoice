import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yovoice/core/localization/app_language.dart';

const _permissionUsageDescriptionKeys = <String>{
  'NSCameraUsageDescription',
  'NSMicrophoneUsageDescription',
  'NSPhotoLibraryUsageDescription',
};

void main() {
  final expectedAndroidLanguageTags = selectableAppLanguages
      .map((language) => language.androidLocaleTag)
      .toList(growable: false);
  final expectedIosLanguageTags = selectableAppLanguages
      .map((language) => language.iosLocalizationTag)
      .toList(growable: false);
  final nonEnglishIosLanguageTags = expectedIosLanguageTags
      .where((tag) => tag != 'en')
      .toList(growable: false);

  group('platform localization configuration', () {
    test('Android declares every selectable locale exactly once', () {
      final localesConfig = File(
        'android/app/src/main/res/xml/locales_config.xml',
      ).readAsStringSync();
      final configuredLanguageTags = RegExp(
        r'<locale\s+android:name="([^"]+)"\s*/>',
      ).allMatches(localesConfig).map((match) => match.group(1)!).toList();

      expect(
        configuredLanguageTags,
        orderedEquals(expectedAndroidLanguageTags),
        reason:
            'locales_config.xml must stay aligned with '
            'selectableAppLanguages.',
      );
      expect(
        configuredLanguageTags.toSet().length,
        configuredLanguageTags.length,
        reason: 'locales_config.xml must not contain duplicate locales.',
      );

      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('android:localeConfig="@xml/locales_config"'));
    });

    test('iOS declares and bundles every selectable locale', () {
      final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
      final localizationsArray = RegExp(
        r'<key>CFBundleLocalizations</key>\s*<array>([\s\S]*?)</array>',
      ).firstMatch(infoPlist);
      expect(
        localizationsArray,
        isNotNull,
        reason: 'Info.plist must declare CFBundleLocalizations.',
      );

      final configuredLanguageTags = RegExp(r'<string>([^<]+)</string>')
          .allMatches(localizationsArray!.group(1)!)
          .map((match) {
            return match.group(1)!;
          })
          .toList();
      expect(
        configuredLanguageTags,
        orderedEquals(expectedIosLanguageTags),
        reason:
            'CFBundleLocalizations must stay aligned with '
            'selectableAppLanguages.',
      );
      expect(
        configuredLanguageTags.toSet().length,
        configuredLanguageTags.length,
        reason: 'CFBundleLocalizations must not contain duplicate locales.',
      );

      for (final languageTag in nonEnglishIosLanguageTags) {
        final stringsFile = File(
          'ios/Runner/$languageTag.lproj/InfoPlist.strings',
        );
        expect(
          stringsFile.existsSync(),
          isTrue,
          reason: '${stringsFile.path} is missing.',
        );

        final assignments = RegExp(
          r'^\s*"([^"]+)"\s*=\s*"((?:\\.|[^"])*)"\s*;',
          multiLine: true,
        ).allMatches(stringsFile.readAsStringSync()).toList();
        final keys = assignments.map((match) => match.group(1)!).toList();

        expect(
          keys,
          unorderedEquals(_permissionUsageDescriptionKeys),
          reason:
              '${stringsFile.path} must contain exactly the three permission '
              'usage descriptions.',
        );
        expect(
          keys.length,
          _permissionUsageDescriptionKeys.length,
          reason: '${stringsFile.path} must not contain duplicate keys.',
        );
        for (final assignment in assignments) {
          expect(
            assignment.group(2)!.trim(),
            isNotEmpty,
            reason: '${assignment.group(1)} in ${stringsFile.path} is empty.',
          );
        }
      }

      final xcodeProject = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      final knownRegions = RegExp(
        r'knownRegions = \(([\s\S]*?)\);',
      ).firstMatch(xcodeProject);
      expect(
        knownRegions,
        isNotNull,
        reason: 'project.pbxproj must declare knownRegions.',
      );
      final configuredKnownRegions = knownRegions!
          .group(1)!
          .split(',')
          .map((region) => region.trim().replaceAll('"', ''))
          .where((region) => region.isNotEmpty)
          .toList(growable: false);
      expect(
        configuredKnownRegions,
        orderedEquals([...expectedIosLanguageTags, 'Base']),
        reason:
            'Xcode knownRegions must stay aligned with selectableAppLanguages.',
      );
      expect(
        configuredKnownRegions.toSet().length,
        configuredKnownRegions.length,
        reason: 'Xcode knownRegions must not contain duplicate locales.',
      );

      final infoPlistVariant = RegExp(
        r'([A-F0-9]{24}) /\* InfoPlist\.strings \*/ = \{\s*'
        r'isa = PBXVariantGroup;\s*children = \(([\s\S]*?)\);\s*'
        r'name = InfoPlist\.strings;',
      ).firstMatch(xcodeProject);
      expect(
        infoPlistVariant,
        isNotNull,
        reason: 'project.pbxproj must contain an InfoPlist.strings variant.',
      );

      final variantId = infoPlistVariant!.group(1)!;
      final variantChildren = RegExp(r'/\* ([^*]+) \*/')
          .allMatches(infoPlistVariant.group(2)!)
          .map((match) {
            return match.group(1)!.trim();
          })
          .toList();
      expect(
        variantChildren,
        orderedEquals(nonEnglishIosLanguageTags),
        reason:
            'The InfoPlist.strings variant group must contain every non-English '
            'selectable locale.',
      );

      final projectWithoutQuotes = xcodeProject.replaceAll('"', '');
      for (final languageTag in nonEnglishIosLanguageTags) {
        expect(
          projectWithoutQuotes,
          contains('path = $languageTag.lproj/InfoPlist.strings;'),
          reason: '$languageTag InfoPlist.strings is not referenced by Xcode.',
        );
      }
      expect(
        RegExp(
          '${RegExp.escape(variantId)} /\\* InfoPlist\\.strings \\*/',
        ).allMatches(xcodeProject).length,
        greaterThanOrEqualTo(2),
        reason:
            'The InfoPlist.strings variant group must be attached to the Runner '
            'project group.',
      );
      expect(
        RegExp(
          r'InfoPlist\.strings in Resources',
        ).allMatches(xcodeProject).length,
        greaterThanOrEqualTo(2),
        reason:
            'InfoPlist.strings must have a build-file entry and be included in '
            'the Resources build phase.',
      );
    });

    test('iOS compiles every permission strategy used by the app', () {
      final podfile = File('ios/Podfile').readAsStringSync();

      for (final definition in const <String>[
        'PERMISSION_CAMERA=1',
        'PERMISSION_MICROPHONE=1',
        'PERMISSION_NOTIFICATIONS=1',
      ]) {
        expect(
          podfile,
          contains(definition),
          reason:
              '$definition must be enabled or permission_handler compiles '
              'that iOS capability out.',
        );
      }
    });

    test('web starts in English and synchronizes the document language', () {
      final indexHtml = File('web/index.html').readAsStringSync();
      expect(
        indexHtml,
        contains('<html lang="en">'),
        reason: 'The static web document language must default to English.',
      );

      final conditionalExport = File(
        'lib/core/localization/document_language.dart',
      ).readAsStringSync();
      expect(conditionalExport, contains('dart.library.js_interop'));
      expect(conditionalExport, contains('document_language_web.dart'));

      final webImplementation = File(
        'lib/core/localization/document_language_web.dart',
      ).readAsStringSync();
      expect(
        webImplementation,
        contains("setAttribute('lang', locale.toLanguageTag())"),
        reason: 'The web implementation must apply the active locale tag.',
      );
      expect(
        webImplementation,
        contains("setAttribute(\n    'dir',"),
        reason:
            'The web implementation must synchronize document.dir with the '
            'active locale.',
      );
      for (final rtlLanguageCode in const ['ar', 'he', 'fa', 'ur']) {
        expect(
          webImplementation,
          contains("'$rtlLanguageCode'"),
          reason:
              '$rtlLanguageCode must render the web document right-to-left.',
        );
      }
      expect(webImplementation, contains("? 'rtl'"));
      expect(webImplementation, contains(": 'ltr'"));

      final appSource = File('lib/app/app.dart').readAsStringSync();
      expect(
        appSource,
        contains('localeListResolutionCallback: resolveAppLocale'),
        reason:
            'MaterialApp must use the region/script-aware device locale '
            'resolver.',
      );
      expect(
        appSource,
        contains('updateDocumentLanguage(locale);'),
        reason:
            'The app must synchronize document.lang and document.dir whenever '
            'its locale is resolved.',
      );
    });

    test('Polish is not labelled as beta anywhere in lib', () {
      final sourceFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final sourceFile in sourceFiles) {
        final source = sourceFile.readAsStringSync();
        expect(
          source,
          isNot(anyOf(contains('Polski · Beta'), contains('Polski - Beta'))),
          reason: '${sourceFile.path} still labels Polish as beta.',
        );
      }
    });
  });
}
