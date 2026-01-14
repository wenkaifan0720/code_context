import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
// ignore: implementation_imports
import 'package:scip_dart/src/gen/scip.pb.dart' as scip;
import 'package:scip_server/scip_server.dart';
import 'package:test/test.dart';

/// Integration tests that run classification and storyboard commands
/// on the sample Flutter app fixture.
void main() {
  late ScipIndex index;
  late QueryExecutor executor;
  late String fixturePath;

  setUpAll(() async {
    // Get the fixture path
    fixturePath = p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'sample_flutter_app',
    );

    // Build a mock index from the fixture files
    // Since we don't have scip-dart indexing the fixture,
    // we'll create a simulated index based on the file structure
    index = await _buildMockIndex(fixturePath);
    executor = QueryExecutor(index);
  });

  group('classify command on fixture', () {
    test('classifies pages as UI layer', () async {
      final result = await executor.execute('classify *Page');

      expect(result, isA<ClassifyResult>());
      final classifyResult = result as ClassifyResult;

      // Should find all pages
      expect(classifyResult.classifications, isNotEmpty);

      // All should be classified as UI
      for (final c in classifyResult.classifications) {
        expect(c.layer, equals('ui'),
            reason: '${c.name} should be UI layer');
      }

      // Print output for manual inspection
      print('\n=== classify *Page ===');
      print(result.toText());
    });

    test('classifies services as service layer', () async {
      final result = await executor.execute('classify *Service');

      expect(result, isA<ClassifyResult>());
      final classifyResult = result as ClassifyResult;

      expect(classifyResult.classifications, isNotEmpty);

      for (final c in classifyResult.classifications) {
        expect(c.layer, equals('service'),
            reason: '${c.name} should be service layer');
      }

      print('\n=== classify *Service ===');
      print(result.toText());
    });

    test('classifies repositories as data layer', () async {
      final result = await executor.execute('classify *Repository');

      expect(result, isA<ClassifyResult>());
      final classifyResult = result as ClassifyResult;

      expect(classifyResult.classifications, isNotEmpty);

      for (final c in classifyResult.classifications) {
        expect(c.layer, equals('data'),
            reason: '${c.name} should be data layer');
      }

      print('\n=== classify *Repository ===');
      print(result.toText());
    });

    test('classifies all symbols', () async {
      final result = await executor.execute('classify');

      expect(result, isA<ClassifyResult>());
      final classifyResult = result as ClassifyResult;

      expect(classifyResult.classifications.length, greaterThan(5));

      print('\n=== classify (all) ===');
      print(result.toText());
    });

    test('detects features from paths', () async {
      final result = await executor.execute('classify');

      expect(result, isA<ClassifyResult>());
      final classifyResult = result as ClassifyResult;

      // Get unique features
      final features = classifyResult.classifications
          .map((c) => c.feature)
          .whereType<String>()
          .toSet();

      print('\n=== Detected features ===');
      print(features.join(', '));

      // Should detect auth, products, settings, home
      expect(features, containsAll(['auth', 'products', 'settings', 'home']));
    });
  });

  group('storyboard command on fixture', () {
    test('finds all screen pages', () async {
      final result = await executor.execute('storyboard');

      expect(result, isA<StoryboardResult>());
      final storyboardResult = result as StoryboardResult;

      expect(storyboardResult.screens, isNotEmpty);

      final screenNames = storyboardResult.screens.map((s) => s.name).toList();
      print('\n=== Screens found ===');
      print(screenNames.join(', '));

      // Should find key pages
      expect(screenNames, contains('LoginPage'));
      expect(screenNames, contains('SignupPage'));
      expect(screenNames, contains('HomePage'));
      expect(screenNames, contains('ProductListPage'));
      expect(screenNames, contains('ProductDetailPage'));
      expect(screenNames, contains('SettingsPage'));
      expect(screenNames, contains('ProfilePage'));
    });

    test('generates storyboard with nodes and edges', () async {
      final result = await executor.execute('storyboard');

      expect(result, isA<StoryboardResult>());
      final storyboardResult = result as StoryboardResult;

      final json = storyboardResult.toJson();
      final nodes = json['nodes'] as List;
      expect(nodes, isNotEmpty);

      print('\n=== Storyboard ===');
      print(result.toText());
    });

    test('generates ascii diagram', () async {
      final result = await executor.execute('storyboard --format:ascii');

      expect(result, isA<StoryboardResult>());
      final storyboardResult = result as StoryboardResult;

      expect(storyboardResult.format, equals('ascii'));

      print('\n=== Storyboard ASCII ===');
      print(result.toText());
    });

    test('detects navigation edges', () async {
      final result = await executor.execute('storyboard');

      expect(result, isA<StoryboardResult>());
      final storyboardResult = result as StoryboardResult;

      print('\n=== Navigation edges ===');
      for (final edge in storyboardResult.edges) {
        print('${edge.fromScreen} → ${edge.toScreen}');
      }

      // Should detect navigation from login to home and signup
      // Note: Route paths like '/home' are converted to 'Home' screen names
      expect(
        storyboardResult.edges.any(
          (e) => e.fromScreen == 'LoginPage' && 
                 (e.toScreen.toLowerCase().contains('home')),
        ),
        isTrue,
        reason: 'Should detect LoginPage → Home navigation',
      );
    });
  });

  group('JSON output', () {
    test('classify produces valid JSON', () async {
      final result = await executor.execute('classify');
      final json = result.toJson();

      expect(json['type'], equals('classify'));
      expect(json['classifications'], isA<List>());

      print('\n=== Classify JSON structure ===');
      print('type: ${json['type']}');
      print('count: ${json['count']}');
      print('classifications sample: ${(json['classifications'] as List).take(2)}');
    });

    test('storyboard produces valid JSON', () async {
      final result = await executor.execute('storyboard');
      final json = result.toJson();

      // toJson returns DirectedGraph-compatible format
      expect(json['nodes'], isA<List>());
      expect(json['edges'], isA<List>());
      expect(json['metadata'], isA<Map>());

      print('\n=== Storyboard JSON structure ===');
      print('nodes: ${json['nodes']}');
      print('edges count: ${(json['edges'] as List).length}');
      print('metadata: ${json['metadata']}');
    });
  });

  group('output file generation', () {
    test('--output flag writes query result to file', () async {
      // Test the _outputResult-like functionality
      final result = await executor.execute('classify');

      // Simulate what the CLI does
      final tempDir = await Directory.systemTemp.createTemp('code_context_test');
      final outputFile = File(p.join(tempDir.path, 'test_output.md'));

      try {
        await outputFile.writeAsString(result.toText());

        expect(await outputFile.exists(), isTrue);
        final content = await outputFile.readAsString();
        expect(content, contains('## Symbol Classification'));

        print('\n=== Output file test ===');
        print('File created: ${outputFile.path}');
        print('Content length: ${content.length} bytes');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('JSON output can be written and parsed', () async {
      final result = await executor.execute('storyboard');

      final tempDir = await Directory.systemTemp.createTemp('code_context_test');
      final outputFile = File(p.join(tempDir.path, 'storyboard.json'));

      try {
        final jsonContent = const JsonEncoder.withIndent('  ').convert(result.toJson());
        await outputFile.writeAsString(jsonContent);

        // Re-parse to verify it's valid JSON
        final parsed = json.decode(await outputFile.readAsString()) as Map<String, dynamic>;
        // toJson now returns DirectedGraph-compatible format
        expect(parsed['nodes'], isA<List>());
        expect(parsed['edges'], isA<List>());

        print('\n=== JSON output test ===');
        print('Valid JSON written and parsed successfully');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('generates docs folder structure', () async {
      // Simulate generate-docs behavior
      final tempDir = await Directory.systemTemp.createTemp('code_context_docs');
      final docsDir = Directory(p.join(tempDir.path, 'docs'));

      try {
        await docsDir.create(recursive: true);

        // Generate all docs
        final classifyResult = await executor.execute('classify');
        final storyboardResult = await executor.execute('storyboard');

        // Write architecture.md
        final archFile = File(p.join(docsDir.path, 'architecture.md'));
        await archFile.writeAsString('''# Architecture

> Auto-generated by code_context

${classifyResult.toText()}
''');

        // Write navigation.md
        final navFile = File(p.join(docsDir.path, 'navigation.md'));
        await navFile.writeAsString('''# Navigation Flow

> Auto-generated by code_context

${storyboardResult.toText()}
''');

        // Write index.md
        final indexFile = File(p.join(docsDir.path, 'index.md'));
        await indexFile.writeAsString('''# Project Documentation

> Auto-generated by code_context

## Documentation

- [Architecture](./architecture.md)
- [Navigation](./navigation.md)
''');

        // Verify all files exist
        expect(await archFile.exists(), isTrue);
        expect(await navFile.exists(), isTrue);
        expect(await indexFile.exists(), isTrue);

        // Verify content
        expect(await archFile.readAsString(), contains('Symbol Classification'));
        expect(await navFile.readAsString(), contains('Storyboard'));
        expect(await indexFile.readAsString(), contains('Architecture'));

        print('\n=== Docs generation test ===');
        print('Created files:');
        await for (final f in docsDir.list()) {
          print('  ${p.basename(f.path)}');
        }
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}

/// Build a mock index from fixture files.
///
/// Since we don't have the full scip-dart indexer running on the fixture,
/// this creates a simulated index based on file names and contents.
Future<ScipIndex> _buildMockIndex(String fixturePath) async {
  final documents = <scip.Document>[];
  final libDir = Directory(p.join(fixturePath, 'lib'));

  if (!await libDir.exists()) {
    throw Exception('Fixture lib directory not found: ${libDir.path}');
  }

  await for (final entity in libDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final relativePath = p.relative(entity.path, from: fixturePath);
      final content = await entity.readAsString();

      // Parse class declarations
      final classMatches = RegExp(r'class\s+(\w+)(?:\s+extends\s+(\w+))?')
          .allMatches(content);

      final symbols = <scip.SymbolInformation>[];
      final occurrences = <scip.Occurrence>[];

      for (final match in classMatches) {
        final className = match.group(1)!;
        final parentClass = match.group(2);
        final symbolId = 'scip-dart fixture 1.0.0 $relativePath/$className#';

        // Extract doc comments before the class
        final beforeClass = content.substring(0, match.start);
        final docMatch = RegExp(r'((?:///[^\n]*\n)+)\s*$').firstMatch(beforeClass);
        final docs = docMatch != null
            ? docMatch.group(1)!.split('\n').map((l) => l.replaceFirst('/// ', '')).toList()
            : <String>[];

        final relationships = <scip.Relationship>[];
        if (parentClass != null) {
          relationships.add(scip.Relationship(
            symbol: 'scip-dart flutter 3.0.0 $parentClass#',
            isImplementation: true,
          ));
        }

        symbols.add(scip.SymbolInformation(
          symbol: symbolId,
          documentation: docs,
          kind: scip.SymbolInformation_Kind.Class,
          displayName: className,
          relationships: relationships,
        ));

        // Find the line number for the class definition
        final lineNumber = '\n'.allMatches(content.substring(0, match.start)).length;

        occurrences.add(scip.Occurrence(
          symbol: symbolId,
          range: [lineNumber, match.start - content.lastIndexOf('\n', match.start) - 1],
          symbolRoles: scip.SymbolRole.Definition.value,
        ));
      }

      documents.add(scip.Document(
        language: 'Dart',
        relativePath: relativePath,
        symbols: symbols,
        occurrences: occurrences,
      ));
    }
  }

  final rawIndex = scip.Index(
    metadata: scip.Metadata(
      projectRoot: Uri.file(fixturePath).toString(),
    ),
    documents: documents,
  );

  return ScipIndex.fromScipIndex(rawIndex, projectRoot: fixturePath);
}
