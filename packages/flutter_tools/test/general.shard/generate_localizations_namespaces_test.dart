// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/localizations/gen_l10n.dart';
import 'package:flutter_tools/src/localizations/gen_l10n_types.dart';
import 'package:flutter_tools/src/localizations/localizations_utils.dart';

import '../src/common.dart';

const _templateArbFileName = 'app_en.arb';
const _esArbFileName = 'app_es.arb';
const _titleMessageArbFileString = '''
{
  "title": "Title",
  "@title": {
    "description": "Title for the application."
  }
}''';
const _titleEsMessageArbFileString = '''
{
  "title": "Título"
}''';

// A small helper for creating ARB files in the (virtual) arb directory.
class _NamespacedSetup {
  _NamespacedSetup(this.fs, this.l10nPath) {
    l10nDirectory.createSync(recursive: true);
  }

  final MemoryFileSystem fs;
  final String l10nPath;

  Directory get l10nDirectory => fs.directory(l10nPath);

  _NamespacedSetup withRootArbFiles() {
    l10nDirectory.childFile(_templateArbFileName).writeAsStringSync(_titleMessageArbFileString);
    l10nDirectory.childFile(_esArbFileName).writeAsStringSync(_titleEsMessageArbFileString);
    return this;
  }

  /// Creates `namespace/<namespace>_en.arb` and `namespace/<namespace>_es.arb`
  /// containing the `title` message.
  _NamespacedSetup withNamespaceArbFiles(String namespace) {
    final Directory namespaceDirectory = l10nDirectory.childDirectory(namespace)
      ..createSync(recursive: true);
    namespaceDirectory
        .childFile('${namespace}_en.arb')
        .writeAsStringSync(_titleMessageArbFileString);
    namespaceDirectory
        .childFile('${namespace}_es.arb')
        .writeAsStringSync(_titleEsMessageArbFileString);
    return this;
  }
}

void main() {
  late MemoryFileSystem fs;
  late BufferLogger logger;
  late String l10nPath;

  setUp(() {
    fs = MemoryFileSystem.test();
    logger = BufferLogger.test();
    l10nPath = fs.path.join('lib', 'l10n');
    precacheLanguageAndRegionTags();
  });

  LocalizationsGenerator setupLocalizations(_NamespacedSetup setup, {bool useNamespaces = false}) {
    setup.l10nDirectory.createSync(recursive: true);
    return LocalizationsGenerator(
      fileSystem: fs,
      inputPathString: l10nPath,
      outputPathString: l10nPath,
      templateArbFileName: _templateArbFileName,
      outputFileString: 'output-localization-file.dart',
      classNameString: 'AppLocalizations',
      logger: logger,
      useNamespaces: useNamespaces,
      projectPathString: fs.currentDirectory.path,
    );
  }

  String generatedFileContent({String? locale}) {
    final fileName = 'output-localization-file${locale == null ? '' : '_$locale'}.dart';
    return fs.file(fs.path.join(l10nPath, fileName)).readAsStringSync();
  }

  testWithoutContext('useNamespaces=false does not use subdirectories', () {
    final setup = _NamespacedSetup(fs, l10nPath)
      ..withRootArbFiles()
      ..withNamespaceArbFiles('home');

    final LocalizationsGenerator generator = setupLocalizations(setup);
    generator.loadResources();
    generator.writeOutputFiles();

    final String englishFile = generatedFileContent(locale: 'en');
    expect(englishFile, contains('String get title'));
    // The subdirectory is treated as a namespace only when useNamespaces is true.
    expect(englishFile, isNot(contains('String get home_title')));
  });

  testWithoutContext('useNamespaces=true prefixes messages from each namespace', () {
    final setup = _NamespacedSetup(fs, l10nPath)
      ..withRootArbFiles()
      ..withNamespaceArbFiles('home');

    final LocalizationsGenerator generator = setupLocalizations(setup, useNamespaces: true);
    generator.loadResources();
    generator.writeOutputFiles();

    final String englishFile = generatedFileContent(locale: 'en');
    final String spanishFile = generatedFileContent(locale: 'es');

    // Root messages keep their plain identifier.
    expect(englishFile, contains('String get title'));
    // Namespaced messages are prefixed with the namespace.
    expect(englishFile, contains('String get home_title'));

    // Both locales in the namespace are generated.
    expect(spanishFile, contains('String get home_title'));
  });

  testWithoutContext('root and namespaced messages coexist for the same locale', () {
    final setup = _NamespacedSetup(fs, l10nPath)
      ..withRootArbFiles()
      ..withNamespaceArbFiles('checkout');

    final LocalizationsGenerator generator = setupLocalizations(setup, useNamespaces: true);
    generator.loadResources();
    generator.writeOutputFiles();

    final String englishFile = generatedFileContent(locale: 'en');
    expect(englishFile, contains('String get title'));
    expect(englishFile, contains('String get checkout_title'));
  });

  testWithoutContext('throws a scoped duplicate-locale error for files within a namespace', () {
    final setup = _NamespacedSetup(fs, l10nPath)..withRootArbFiles();
    final Directory namespace = setup.l10nDirectory.childDirectory('shop')
      ..createSync(recursive: true);
    // Both files declare the same en locale within the 'shop' namespace.
    namespace.childFile('shop_en.arb').writeAsStringSync(_titleMessageArbFileString);
    namespace.childFile('another_en.arb').writeAsStringSync(_titleMessageArbFileString);

    final LocalizationsGenerator generator = setupLocalizations(setup, useNamespaces: true);

    expect(
      () => generator.loadResources(),
      throwsA(
        isA<L10nException>().having(
          (L10nException e) => e.message,
          'message',
          contains("in the namespace 'shop'"),
        ),
      ),
    );
  });

  testWithoutContext('colliding prefixed names throw a descriptive error', () {
    final setup = _NamespacedSetup(fs, l10nPath)
      ..withRootArbFiles()
      ..withNamespaceArbFiles('home');
    // Give the root ARB file a message named exactly like the prefixed one
    // generated by the namespace, e.g. `home_title`.
    setup.l10nDirectory.childFile(_templateArbFileName).writeAsStringSync('''
{
  "title": "Title",
  "home_title": "Root home title"
}''');

    final LocalizationsGenerator generator = setupLocalizations(setup, useNamespaces: true);

    expect(
      () => generator.loadResources(),
      throwsA(
        isA<L10nException>().having(
          (L10nException e) => e.message,
          'message',
          contains('The formatted resource id "home_title" is used by both'),
        ),
      ),
    );
  });

  testWithoutContext('skips a namespace when the template locale is missing', () {
    final setup = _NamespacedSetup(fs, l10nPath)..withRootArbFiles();
    // The 'billing' namespace only has Spanish files, so it has no template
    // file for the 'en' template locale and must be skipped.
    final Directory billing = setup.l10nDirectory.childDirectory('billing')
      ..createSync(recursive: true);
    billing.childFile('billing_es.arb').writeAsStringSync(_titleEsMessageArbFileString);

    final LocalizationsGenerator generator = setupLocalizations(setup, useNamespaces: true);
    generator.loadResources();
    generator.writeOutputFiles();

    expect(logger.warningText, contains('no template ARB file'));
    expect(logger.warningText, contains('billing'));

    final String englishFile = generatedFileContent(locale: 'en');
    expect(englishFile, isNot(contains('billing_title')));
  });

  testWithoutContext('throws when a namespace is not a valid Dart identifier', () {
    final setup = _NamespacedSetup(fs, l10nPath);
    // A namespace containing a hyphen is not a valid Dart identifier.
    final Directory invalidNamespace = setup.l10nDirectory.childDirectory('user-profile')
      ..createSync(recursive: true);
    invalidNamespace.childFile('user_profile.arb').writeAsStringSync(_titleMessageArbFileString);

    expect(
      () => setupLocalizations(setup, useNamespaces: true).loadResources(),
      throwsA(isA<L10nException>()),
    );
  });
}
