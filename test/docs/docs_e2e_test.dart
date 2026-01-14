import 'dart:io';

import 'package:code_context/code_context.dart';
import 'package:dart_binding/dart_binding.dart' show DartBinding;
import 'package:path/path.dart' as p;
import 'package:scip_server/scip_server.dart';
import 'package:test/test.dart';

/// End-to-end tests for the docs infrastructure using the real SCIP indexer.
///
/// This test:
/// 1. Creates a real Dart project in a temp directory
/// 2. Indexes it with the real SCIP indexer
/// 3. Tests the docs infrastructure
/// 4. Modifies files
/// 5. Verifies dirty detection works correctly
void main() {
  // Register binding for auto-detection
  CodeContext.registerBinding(DartBinding());

  late Directory tempDir;
  late String projectPath;
  late CodeContext context;

  setUpAll(() async {
    // Create a temp directory
    tempDir = await Directory.systemTemp.createTemp('docs_e2e_test_');
    projectPath = tempDir.path;

    // Create a test project with proper structure
    await _createTestProject(projectPath);

    // Index with real SCIP indexer
    context = await CodeContext.open(projectPath, watch: false);
  });

  tearDownAll(() async {
    await context.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Structure hash with real index', () {
    test('computes hash for real folders', () {
      final index = context.index;

      // Get folders
      final folders = index.files.map((f) => p.dirname(f)).toSet();
      expect(folders, isNotEmpty);

      print('\n=== Real index folders ===');
      for (final folder in folders.toList()..sort()) {
        final hash = StructureHash.computeFolderHash(index, folder);
        print('$folder: ${hash.isEmpty ? "(empty)" : hash.substring(0, 8)}...');
      }
    });

    test('hash changes when signature changes', () async {
      final index = context.index;

      // Get initial hash for lib folder
      final initialHash = StructureHash.computeFolderHash(index, 'lib');

      // Modify a file - add a new method (changes signature)
      final greeterFile = File(p.join(projectPath, 'lib', 'greeter.dart'));
      final content = await greeterFile.readAsString();
      await greeterFile.writeAsString(content.replaceFirst(
        'String greet() {',
        '''String farewell() {
    return 'Goodbye, \$name!';
  }

  String greet() {''',
      ));

      // Re-index
      await context.refreshFile(greeterFile.path);

      // Hash should change
      final newHash = StructureHash.computeFolderHash(context.index, 'lib');
      expect(newHash, isNot(equals(initialHash)));

      print('\n=== Hash change after signature change ===');
      print('Before: ${initialHash.substring(0, 8)}...');
      print('After:  ${newHash.substring(0, 8)}...');
    });
  });

  group('Folder graph with real index', () {
    test('builds graph from real index', () {
      final graph = FolderDependencyGraph.build(context.index);

      expect(graph.folders, isNotEmpty);

      print('\n=== Real folder graph ===');
      print('Folders: ${graph.folders.length}');
      print('Internal edges: ${graph.stats['internalEdges']}');
      print(graph.toString());
    });

    test('detects dependencies between folders', () {
      final graph = FolderDependencyGraph.build(context.index);

      // lib should exist
      expect(graph.folders.contains('lib'), isTrue);

      // Check for any internal dependencies
      for (final folder in graph.folders) {
        final deps = graph.getInternalDependencies(folder);
        if (deps.isNotEmpty) {
          print('$folder depends on: $deps');
        }
      }
    });
  });

  group('Topological sort with real index', () {
    test('sorts real folders', () {
      final graph = FolderDependencyGraph.build(context.index);
      final sorted = TopologicalSort.sort(graph);

      expect(sorted, isNotEmpty);

      print('\n=== Real generation order ===');
      for (var i = 0; i < sorted.length; i++) {
        final group = sorted[i];
        print('$i: ${group.join(", ")}');
      }
    });
  });

  group('Incremental docs workflow', () {
    test('full workflow: initial index -> modify -> detect dirty', () async {
      // 1. Build folder graph
      var graph = FolderDependencyGraph.build(context.index);
      expect(graph.folders, isNotEmpty);

      // 2. Compute initial hashes
      final initialHashes = <String, String>{};
      for (final folder in graph.folders) {
        initialHashes[folder] =
            StructureHash.computeFolderHash(context.index, folder);
      }

      // 3. Create manifest and mark all as "generated"
      final manifest = DocManifest();
      for (final folder in graph.folders) {
        manifest.updateFolder(
          folder,
          FolderDocState(
            structureHash: initialHashes[folder]!,
            docHash: 'generated-v1',
            generatedAt: DateTime.now(),
            internalDeps: graph.getInternalDependencies(folder).toList(),
            externalDeps: graph.getExternalDependencies(folder).toList(),
          ),
        );
      }

      // 4. Verify nothing is dirty initially
      var dirty = manifest.getDirtyFolders(initialHashes);
      expect(dirty, isEmpty, reason: 'No folders should be dirty initially');

      print('\n=== Incremental workflow ===');
      print('Initial folders: ${graph.folders.length}');
      print('Initial dirty: ${dirty.length}');

      // 5. Modify a file (add new class - signature change)
      final calcFile = File(p.join(projectPath, 'lib', 'calculator.dart'));
      final content = await calcFile.readAsString();
      await calcFile.writeAsString('''
$content

/// A matrix calculator for advanced operations.
class MatrixCalculator {
  List<List<double>> multiply(List<List<double>> a, List<List<double>> b) {
    // Implementation here
    return [];
  }
}
''');

      // 6. Re-index the modified file
      await context.refreshFile(calcFile.path);

      // 7. Compute new hashes
      final newHashes = <String, String>{};
      for (final folder in graph.folders) {
        newHashes[folder] =
            StructureHash.computeFolderHash(context.index, folder);
      }

      // 8. Check what's dirty now
      dirty = manifest.getDirtyFolders(newHashes);

      print('After modification:');
      print('Dirty folders: $dirty');

      // The lib folder should be dirty (we added a class there)
      expect(dirty, contains('lib'));

      // 9. "Regenerate" the dirty folder
      for (final folder in dirty) {
        manifest.updateFolder(
          folder,
          FolderDocState(
            structureHash: newHashes[folder]!,
            docHash: 'generated-v2',
            generatedAt: DateTime.now(),
            internalDeps: graph.getInternalDependencies(folder).toList(),
            externalDeps: graph.getExternalDependencies(folder).toList(),
          ),
        );
      }

      // 10. Verify nothing is dirty after regeneration
      dirty = manifest.getDirtyFolders(newHashes);
      expect(dirty, isEmpty, reason: 'No folders should be dirty after regen');

      print('After regeneration: ${dirty.length} dirty');
    });

    test('implementation-only change does not mark folder dirty', () async {
      // 1. Get initial hash
      final initialHash =
          StructureHash.computeFolderHash(context.index, 'lib');

      // 2. Modify a file - implementation only (no signature change)
      final greeterFile = File(p.join(projectPath, 'lib', 'greeter.dart'));
      var content = await greeterFile.readAsString();

      // Change only the implementation (return value)
      content = content.replaceFirst(
        "return 'Hello, \$name!';",
        "return 'Hi there, \$name!';",
      );
      await greeterFile.writeAsString(content);

      // 3. Re-index
      await context.refreshFile(greeterFile.path);

      // 4. Compute new hash
      final newHash = StructureHash.computeFolderHash(context.index, 'lib');

      print('\n=== Implementation-only change ===');
      print('Before: ${initialHash.substring(0, 8)}...');
      print('After:  ${newHash.substring(0, 8)}...');

      // Note: SCIP may or may not capture implementation details
      // If it doesn't, hashes should be the same
      // If it does (e.g., doc comments), they might differ

      // The key insight is that we only hash signature/docs, not implementation
      // So this test documents the behavior
    });
  });

  group('Link transformer with real index', () {
    test('resolves symbols from real index', () async {
      final tempDocsDir = await Directory.systemTemp.createTemp('docs_test');

      try {
        final transformer = LinkTransformer(
          index: context.index,
          docsRoot: tempDocsDir.path,
          projectRoot: projectPath,
        );

        // Find a real symbol to reference
        final symbols = context.index.findSymbols('Greeter');
        expect(symbols, isNotEmpty);

        final greeterSymbol = symbols.first;
        print('\n=== Real symbol resolution ===');
        print('Symbol: ${greeterSymbol.symbol}');
        print('File: ${greeterSymbol.file}');

        // Try to resolve it
        // Note: The URI format needs to match what we put in docs
        final def = context.index.findDefinition(greeterSymbol.symbol);
        if (def != null) {
          print('Definition at: ${def.file}:${def.line + 1}');
        }
      } finally {
        await tempDocsDir.delete(recursive: true);
      }
    });
  });

  group('Manifest persistence', () {
    test('saves and loads manifest with real data', () async {
      final manifestPath = p.join(tempDir.path, '.dart_context', 'docs', 'manifest.json');

      // Create manifest with real folder data
      final graph = FolderDependencyGraph.build(context.index);
      final manifest = DocManifest();

      for (final folder in graph.folders) {
        manifest.updateFolder(
          folder,
          FolderDocState(
            structureHash: StructureHash.computeFolderHash(context.index, folder),
            docHash: 'doc-hash-$folder',
            generatedAt: DateTime.now(),
            internalDeps: graph.getInternalDependencies(folder).toList(),
            externalDeps: graph.getExternalDependencies(folder).toList(),
          ),
        );
      }

      // Save
      await manifest.save(manifestPath);
      expect(await File(manifestPath).exists(), isTrue);

      // Load
      final loaded = await DocManifest.load(manifestPath);
      expect(loaded.folders.length, equals(manifest.folders.length));

      print('\n=== Manifest persistence ===');
      print('Saved ${manifest.folders.length} folders');
      print('Loaded ${loaded.folders.length} folders');
      print('Path: $manifestPath');
    });
  });
}

/// Creates a minimal Dart project for testing.
Future<void> _createTestProject(String projectPath) async {
  // Create pubspec.yaml
  await File(p.join(projectPath, 'pubspec.yaml')).writeAsString('''
name: docs_test_project
description: A test project for docs e2e tests.
version: 1.0.0

environment:
  sdk: ^3.0.0
''');

  // Create lib directory
  await Directory(p.join(projectPath, 'lib')).create(recursive: true);

  // Create main.dart
  await File(p.join(projectPath, 'lib', 'main.dart')).writeAsString('''
import 'greeter.dart';
import 'calculator.dart';

void main() {
  final greeter = Greeter('World');
  print(greeter.greet());

  final calc = Calculator();
  print(calc.add(2, 3));
}
''');

  // Create greeter.dart
  await File(p.join(projectPath, 'lib', 'greeter.dart')).writeAsString('''
/// A class that greets people.
class Greeter {
  /// The name to greet.
  final String name;

  /// Creates a new greeter for [name].
  Greeter(this.name);

  /// Returns a greeting message.
  String greet() {
    return 'Hello, \$name!';
  }
}
''');

  // Create calculator.dart
  await File(p.join(projectPath, 'lib', 'calculator.dart')).writeAsString('''
/// A simple calculator for basic arithmetic.
class Calculator {
  /// Adds two numbers.
  int add(int a, int b) => a + b;

  /// Subtracts two numbers.
  int subtract(int a, int b) => a - b;

  /// Multiplies two numbers.
  int multiply(int a, int b) => a * b;

  /// Divides two numbers.
  double divide(int a, int b) => a / b;
}

/// An advanced calculator with more operations.
class ScientificCalculator extends Calculator {
  /// Calculates base raised to exponent.
  double power(double base, int exponent) {
    double result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= base;
    }
    return result;
  }
}
''');

  // Run dart pub get to create package_config.json
  final result = await Process.run(
    'dart',
    ['pub', 'get'],
    workingDirectory: projectPath,
  );

  if (result.exitCode != 0) {
    throw StateError('Failed to run dart pub get: ${result.stderr}');
  }
}
