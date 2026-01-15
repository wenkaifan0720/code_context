import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scip_server/src/docs/llm/doc_tools.dart';
import 'package:scip_server/src/index/scip_index.dart';
import 'package:test/test.dart';

void main() {
  group('DocToolRegistry', () {
    late Directory tempDir;
    late ScipIndex emptyIndex;
    late DocToolRegistry registry;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('doc_tools_test_');
      emptyIndex = ScipIndex.empty(projectRoot: tempDir.path);
      registry = DocToolRegistry(
        projectRoot: tempDir.path,
        scipIndex: emptyIndex,
        docsPath: '${tempDir.path}/.dart_context/docs',
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('tools list contains all expected tools', () {
      final tools = registry.tools;

      expect(tools.length, equals(5));
      expect(
          tools.map((t) => t.name).toSet(),
          equals({
            'ls',
            'read_file',
            'grep',
            'glob',
            'query',
          }));
    });

    test('ls returns folder contents', () async {
      // Create test structure
      final libDir = Directory(p.join(tempDir.path, 'lib'));
      await libDir.create();
      await File(p.join(libDir.path, 'main.dart')).writeAsString('// Main');
      await Directory(p.join(libDir.path, 'src')).create();

      final result = await registry.executeTool('ls', {
        'path': 'lib',
      });

      expect(result, contains('lib'));
      expect(result, contains('main.dart'));
      expect(result, contains('src'));
    });

    test('ls handles non-existent folder', () async {
      final result = await registry.executeTool('ls', {
        'path': 'nonexistent',
      });

      expect(result, contains('Error'));
      expect(result, contains('does not exist'));
    });

    test('ls marks documented subfolders', () async {
      // Create test structure with docs
      final libDir = Directory(p.join(tempDir.path, 'lib'));
      await libDir.create();
      await Directory(p.join(libDir.path, 'auth')).create();

      // Create doc for auth subfolder
      final docDir = Directory(
          p.join(tempDir.path, '.dart_context/docs/folders/lib/auth'));
      await docDir.create(recursive: true);
      await File(p.join(docDir.path, 'README.md')).writeAsString('# Auth');

      final result = await registry.executeTool('ls', {
        'path': 'lib',
      });

      expect(result, contains('auth/'));
      expect(result, contains('[documented]'));
    });

    test('read_file returns file content with line numbers', () async {
      final file = File(p.join(tempDir.path, 'test.dart'));
      await file.writeAsString('line 1\nline 2\nline 3');

      final result = await registry.executeTool('read_file', {
        'path': 'test.dart',
      });

      expect(result, contains('test.dart'));
      expect(result, contains('line 1'));
      expect(result, contains('line 2'));
      expect(result, contains('line 3'));
    });

    test('read_file with range', () async {
      final file = File(p.join(tempDir.path, 'test.dart'));
      await file.writeAsString('line 1\nline 2\nline 3\nline 4\nline 5');

      final result = await registry.executeTool('read_file', {
        'path': 'test.dart',
        'start_line': 2,
        'end_line': 4,
      });

      expect(result, contains('Lines: 2-4'));
      expect(result, contains('line 2'));
      expect(result, contains('line 3'));
      expect(result, contains('line 4'));
    });

    test('read_file handles non-existent file', () async {
      final result = await registry.executeTool('read_file', {
        'path': 'nonexistent.dart',
      });

      expect(result, contains('Error'));
      expect(result, contains('does not exist'));
    });

    test('grep finds pattern in files', () async {
      // Create test files
      final libDir = Directory(p.join(tempDir.path, 'lib'));
      await libDir.create();
      await File(p.join(libDir.path, 'main.dart'))
          .writeAsString('void main() {}\nclass MyApp {}');
      await File(p.join(libDir.path, 'utils.dart'))
          .writeAsString('class Helper {}\nvoid helper() {}');

      final result = await registry.executeTool('grep', {
        'pattern': 'class',
      });

      expect(result, contains('Searching for: "class"'));
      expect(result, contains('main.dart'));
      expect(result, contains('MyApp'));
      expect(result, contains('utils.dart'));
      expect(result, contains('Helper'));
    });

    test('grep with path scope', () async {
      // Create test files
      final libDir = Directory(p.join(tempDir.path, 'lib'));
      await libDir.create();
      await File(p.join(libDir.path, 'main.dart')).writeAsString('class A {}');

      final testDir = Directory(p.join(tempDir.path, 'test'));
      await testDir.create();
      await File(p.join(testDir.path, 'test.dart')).writeAsString('class B {}');

      final result = await registry.executeTool('grep', {
        'pattern': 'class',
        'path': 'lib',
      });

      expect(result, contains('class A'));
      expect(result, isNot(contains('class B')));
    });

    test('grep handles no matches', () async {
      final result = await registry.executeTool('grep', {
        'pattern': 'nonexistent_pattern_xyz',
      });

      expect(result, contains('No matches found'));
    });

    test('glob finds matching files', () async {
      // Create test files
      final libDir = Directory(p.join(tempDir.path, 'lib'));
      await libDir.create();
      await File(p.join(libDir.path, 'main.dart')).writeAsString('');
      await File(p.join(libDir.path, 'utils.dart')).writeAsString('');

      final srcDir = Directory(p.join(libDir.path, 'src'));
      await srcDir.create();
      await File(p.join(srcDir.path, 'widget.dart')).writeAsString('');

      final result = await registry.executeTool('glob', {
        'pattern': '**/*.dart',
      });

      expect(result, contains('main.dart'));
      expect(result, contains('utils.dart'));
      expect(result, contains('widget.dart'));
    });

    test('glob handles no matches', () async {
      final result = await registry.executeTool('glob', {
        'pattern': '**/*.xyz',
      });

      expect(result, contains('No files found'));
    });

    test('query without executor returns error', () async {
      final result = await registry.executeTool('query', {
        'q': 'symbols get lib/',
      });

      expect(result, contains('Error'));
      expect(result, contains('Query executor not available'));
    });

    test('unknown tool returns error', () async {
      final result = await registry.executeTool('unknown_tool', {});

      expect(result, contains('Error'));
      expect(result, contains('Unknown tool'));
      expect(result, contains('Available tools'));
    });
  });
}
