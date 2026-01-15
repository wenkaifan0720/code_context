import 'package:scip_server/src/docs/link_transformer.dart';
import 'package:scip_server/src/index/scip_index.dart';
import 'package:test/test.dart';

void main() {
  group('ScipUri', () {
    group('parse', () {
      test('parses simple URI', () {
        final uri = ScipUri.parse('lib/auth/service.dart/AuthService#');

        expect(uri, isNotNull);
        expect(uri!.package, isNull);
        expect(uri.version, isNull);
        expect(uri.path, equals('lib/auth/service.dart'));
        expect(uri.symbolName, equals('AuthService'));
        expect(uri.member, isNull);
      });

      test('parses URI with member', () {
        final uri = ScipUri.parse('lib/auth/service.dart/AuthService#login().');

        expect(uri, isNotNull);
        expect(uri!.path, equals('lib/auth/service.dart'));
        expect(uri.symbolName, equals('AuthService'));
        expect(uri.member, equals('login().'));
      });

      test('parses URI with package and version', () {
        final uri = ScipUri.parse(
          'firebase_auth@4.6.0/lib/src/firebase_auth.dart/FirebaseAuth#',
        );

        expect(uri, isNotNull);
        expect(uri!.package, equals('firebase_auth'));
        expect(uri.version, equals('4.6.0'));
        expect(uri.path, equals('lib/src/firebase_auth.dart'));
        expect(uri.symbolName, equals('FirebaseAuth'));
      });

      test('parses URI with scip:// prefix', () {
        final uri = ScipUri.parse('scip://lib/auth/service.dart/AuthService#');

        expect(uri, isNotNull);
        expect(uri!.path, equals('lib/auth/service.dart'));
        expect(uri.symbolName, equals('AuthService'));
      });

      test('handles getter/setter members', () {
        final uri = ScipUri.parse('lib/auth/service.dart/AuthService#authState.');

        expect(uri, isNotNull);
        expect(uri!.member, equals('authState.'));
      });
    });

    group('toString', () {
      test('formats simple URI', () {
        final uri = ScipUri(
          path: 'lib/auth/service.dart',
          symbolName: 'AuthService',
        );

        expect(uri.toString(), equals('scip://lib/auth/service.dart/AuthService#'));
      });

      test('formats URI with member', () {
        final uri = ScipUri(
          path: 'lib/auth/service.dart',
          symbolName: 'AuthService',
          member: 'login().',
        );

        expect(
          uri.toString(),
          equals('scip://lib/auth/service.dart/AuthService#login().'),
        );
      });

      test('formats URI with package', () {
        final uri = ScipUri(
          package: 'firebase_auth',
          version: '4.6.0',
          path: 'lib/src/firebase_auth.dart',
          symbolName: 'FirebaseAuth',
        );

        expect(
          uri.toString(),
          equals('scip://firebase_auth@4.6.0/lib/src/firebase_auth.dart/FirebaseAuth#'),
        );
      });
    });

    group('toSymbolId', () {
      test('creates symbol ID for internal symbol', () {
        final uri = ScipUri(
          path: 'lib/auth/service.dart',
          symbolName: 'AuthService',
        );

        expect(uri.toSymbolId(), equals('lib/auth/service.dart/AuthService#'));
      });

      test('creates symbol ID for external symbol', () {
        final uri = ScipUri(
          package: 'firebase_auth',
          version: '4.6.0',
          path: 'lib/src/firebase_auth.dart',
          symbolName: 'FirebaseAuth',
        );

        expect(
          uri.toSymbolId(),
          contains('scip-dart pub firebase_auth 4.6.0'),
        );
      });
    });
  });

  group('LinkTransformer', () {
    late ScipIndex emptyIndex;
    late LinkTransformer transformer;

    setUp(() {
      emptyIndex = ScipIndex.empty(projectRoot: '/project');
      transformer = LinkTransformer(
        index: emptyIndex,
        docsRoot: '/project/.dart_context/docs',
        projectRoot: '/project',
      );
    });

    group('transform', () {
      test('transforms scip:// links to relative paths', () {
        // With empty index, links become #symbol-not-found
        final source = '''
# Auth Feature

See [`AuthService`][auth-service].

[auth-service]: scip://lib/auth/service.dart/AuthService#
''';

        final result = transformer.transform(source);

        expect(result, contains('[auth-service]: #symbol-not-found'));
      });

      test('preserves non-scip links', () {
        final source = '''
# Auth Feature

See [Google](https://google.com).
''';

        final result = transformer.transform(source);

        expect(result, equals(source));
      });
    });

    group('extractScipUris', () {
      test('extracts all scip:// URIs', () {
        final doc = '''
[auth]: scip://lib/auth/service.dart/AuthService#
[login]: scip://lib/auth/service.dart/AuthService#login().
[firebase]: scip://firebase_auth@4.6.0/lib/firebase_auth.dart/FirebaseAuth#
''';

        final uris = transformer.extractScipUris(doc);

        expect(uris.length, equals(3));
        expect(uris, contains('lib/auth/service.dart/AuthService#'));
        expect(uris, contains('lib/auth/service.dart/AuthService#login().'));
      });

      test('returns empty list for doc without scip links', () {
        final doc = '''
# Simple Doc

No scip links here.
''';

        final uris = transformer.extractScipUris(doc);

        expect(uris, isEmpty);
      });
    });

    group('validateUris', () {
      test('returns false for unresolvable URIs', () {
        final doc = '[auth]: scip://lib/auth/service.dart/AuthService#';

        final results = transformer.validateUris(doc);

        expect(results.length, equals(1));
        expect(results['lib/auth/service.dart/AuthService#'], isFalse);
      });
    });

    group('resolveUri', () {
      test('returns null for symbol not in index', () {
        final result = transformer.resolveUri('lib/auth/service.dart/AuthService#');
        expect(result, isNull);
      });
    });

    group('file-level links', () {
      test('transforms scip:// file link to relative path', () {
        final source = '''
# Overview

See [main.dart](scip://lib/main.dart) for entry point.
''';

        final result = transformer.transform(
          source,
          docPath: '.dart_context/docs/rendered/folders/lib/README.md',
        );

        // File link should be resolved to relative path (no #symbol-not-found)
        expect(result, contains('[main.dart]('));
        expect(result, isNot(contains('#symbol-not-found')));
        expect(result, isNot(contains('scip://')));
      });

      test('transforms scip:// folder link', () {
        final source = '''
See [auth](scip://lib/auth/) folder.
''';

        final result = transformer.transform(
          source,
          docPath: '.dart_context/docs/rendered/folders/lib/README.md',
        );

        expect(result, contains('[auth]('));
        expect(result, isNot(contains('scip://')));
      });
    });

    group('external symbol fallback', () {
      test('converts external inline link to plain text', () {
        final source = '''
Uses [FirebaseAuth](scip://firebase_auth@4.6.0/lib/firebase_auth.dart/FirebaseAuth#) for auth.
''';

        final result = transformer.transform(source);

        // External symbol should become plain text (label only)
        expect(result, contains('FirebaseAuth'));
        expect(result, isNot(contains('#symbol-not-found')));
      });

      test('converts external reference link to HTML comment', () {
        final source = '''
Uses [FirebaseAuth][firebase].

[firebase]: scip://firebase_auth@4.6.0/lib/firebase_auth.dart/FirebaseAuth#
''';

        final result = transformer.transform(source);

        // Reference definition should become HTML comment
        expect(result, contains('<!-- external:'));
        expect(result, isNot(contains('#symbol-not-found')));
      });

      test('keeps internal unresolved as #symbol-not-found', () {
        final source = '''
Uses [UnknownClass](scip://lib/unknown.dart/UnknownClass#).
''';

        final result = transformer.transform(source);

        // Internal unresolved symbol should still be #symbol-not-found
        expect(result, contains('#symbol-not-found'));
      });
    });
  });

  group('LinkStyle', () {
    test('has all expected values', () {
      expect(LinkStyle.values, contains(LinkStyle.relative));
      expect(LinkStyle.values, contains(LinkStyle.github));
      expect(LinkStyle.values, contains(LinkStyle.absolute));
    });
  });
}
