import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../index/scip_index.dart' show ScipIndex;
import '../../query/query_executor.dart';
import 'llm_service.dart';

/// Handler function for a doc generation tool.
typedef DocToolHandler = FutureOr<String> Function(Map<String, dynamic> args);

/// Registry of tools available to the doc generation agent.
///
/// Provides general-purpose FS tools (ls, grep, glob, read_file) plus
/// a powerful `query` tool that exposes the full code_context query DSL.
class DocToolRegistry {
  DocToolRegistry({
    required this.projectRoot,
    required this.scipIndex,
    required this.docsPath,
    this.queryExecutor,
  });

  final String projectRoot;
  final ScipIndex scipIndex;
  final String docsPath;
  final QueryExecutor? queryExecutor;

  /// Get all tool definitions for the LLM.
  List<LlmTool> get tools => [
        _lsTool,
        _readFileTool,
        _grepTool,
        _globTool,
        _queryTool,
      ];

  /// Execute a tool by name.
  Future<String> executeTool(String name, Map<String, dynamic> args) async {
    final handler = _handlers[name];
    if (handler == null) {
      return 'Error: Unknown tool "$name". Available tools: ${_handlers.keys.join(', ')}';
    }
    try {
      return await handler(args);
    } catch (e) {
      return 'Error executing $name: $e';
    }
  }

  Map<String, DocToolHandler> get _handlers => {
        'ls': _handleLs,
        'read_file': _handleReadFile,
        'grep': _handleGrep,
        'glob': _handleGlob,
        'query': _handleQuery,
      };

  // ===== Tool Definitions =====

  LlmTool get _lsTool => const LlmTool(
        name: 'ls',
        description: '''
List files and directories in a given path.
Subfolders with existing documentation are marked [documented].
Use this to explore the project structure.
''',
        parameters: {
          'path': LlmToolParameter(
            type: 'string',
            description:
                'Relative path from project root (e.g., "lib/features/auth")',
          ),
        },
        required: ['path'],
      );

  LlmTool get _readFileTool => const LlmTool(
        name: 'read_file',
        description: '''
Read the contents of a file, optionally specifying a line range.
Returns the file content with line numbers for reference.
For large files, use start_line/end_line to read specific sections.
''',
        parameters: {
          'path': LlmToolParameter(
            type: 'string',
            description: 'Relative path to the file from project root',
          ),
          'start_line': LlmToolParameter(
            type: 'integer',
            description:
                'Optional: Start line number (1-indexed). Omit to read from beginning.',
          ),
          'end_line': LlmToolParameter(
            type: 'integer',
            description:
                'Optional: End line number (inclusive). Omit to read to end.',
          ),
        },
        required: ['path'],
      );

  LlmTool get _grepTool => const LlmTool(
        name: 'grep',
        description: '''
Search for a text pattern in files.
Returns matching lines with file paths and line numbers.
Useful for finding usages, patterns, or specific code across the project.
''',
        parameters: {
          'pattern': LlmToolParameter(
            type: 'string',
            description: 'The text pattern to search for',
          ),
          'path': LlmToolParameter(
            type: 'string',
            description:
                'Optional: Directory to search in (defaults to project root)',
          ),
        },
        required: ['pattern'],
      );

  LlmTool get _globTool => const LlmTool(
        name: 'glob',
        description: '''
Find files matching a glob pattern.
Returns a list of file paths that match the pattern.
Examples: "**/*.dart", "lib/features/**/*_page.dart"
''',
        parameters: {
          'pattern': LlmToolParameter(
            type: 'string',
            description: 'Glob pattern to match files (e.g., "**/*.dart")',
          ),
        },
        required: ['pattern'],
      );

  LlmTool get _queryTool => const LlmTool(
        name: 'query',
        description: '''
Execute a code_context query for semantic code analysis.
This is a powerful tool that understands code structure, not just text.

Example queries:
- "symbols get lib/features/auth/" - list all symbols in a folder
- "symbols refs AuthService.login" - find all references to a method
- "symbols def UserRepository" - find definition of a symbol
- "call-graph callers AuthService.login" - who calls this method?
- "call-graph callees HomePage.build" - what does this method call?
- "imports lib/features/auth/services/auth_service.dart" - what does this file import?
- "exports lib/features/auth/" - what does this folder export?
- "hierarchy User" - get type hierarchy for a class
- "members AuthService" - get all members of a class

Queries can be piped: "symbols get lib/auth/ | refs" (find refs for all symbols in folder)
''',
        parameters: {
          'q': LlmToolParameter(
            type: 'string',
            description: 'The query string to execute',
          ),
        },
        required: ['q'],
      );

  // ===== Tool Handlers =====

  Future<String> _handleLs(Map<String, dynamic> args) async {
    final relativePath = args['path'] as String;
    final absolutePath = p.join(projectRoot, relativePath);
    final dir = Directory(absolutePath);

    if (!dir.existsSync()) {
      return 'Error: Directory "$relativePath" does not exist.';
    }

    final buffer = StringBuffer();
    buffer.writeln('Contents of $relativePath:');
    buffer.writeln();

    final entries = dir.listSync();
    final files = <FileSystemEntity>[];
    final folders = <FileSystemEntity>[];

    for (final entry in entries) {
      if (entry is File) {
        files.add(entry);
      } else if (entry is Directory) {
        folders.add(entry);
      }
    }

    // List folders first
    if (folders.isNotEmpty) {
      buffer.writeln('Folders:');
      for (final folder in folders) {
        final name = p.basename(folder.path);
        if (name.startsWith('.')) continue; // Skip hidden

        // Check if this subfolder has docs
        final subfolderRelPath = p.join(relativePath, name);
        final hasDoc = _hasDocumentation(subfolderRelPath);
        buffer.writeln('  $name/${hasDoc ? ' [documented]' : ''}');
      }
      buffer.writeln();
    }

    // List files
    if (files.isNotEmpty) {
      buffer.writeln('Files:');
      for (final file in files) {
        final name = p.basename(file.path);
        if (name.startsWith('.')) continue; // Skip hidden

        final size = file.statSync().size;
        final sizeStr = _formatSize(size);
        buffer.writeln('  $name ($sizeStr)');
      }
    }

    return buffer.toString();
  }

  Future<String> _handleReadFile(Map<String, dynamic> args) async {
    final relativePath = args['path'] as String;
    final startLine = args['start_line'] as int?;
    final endLine = args['end_line'] as int?;

    final absolutePath = p.join(projectRoot, relativePath);
    final file = File(absolutePath);

    if (!file.existsSync()) {
      return 'Error: File "$relativePath" does not exist.';
    }

    final lines = file.readAsLinesSync();
    final start = (startLine ?? 1) - 1; // Convert to 0-indexed
    final end = endLine ?? lines.length;

    if (start < 0 || start >= lines.length) {
      return 'Error: Start line $startLine is out of range (file has ${lines.length} lines).';
    }

    final buffer = StringBuffer();
    buffer.writeln('File: $relativePath');
    if (startLine != null || endLine != null) {
      buffer.writeln('Lines: ${start + 1}-$end of ${lines.length}');
    }
    buffer.writeln('---');

    for (var i = start; i < end && i < lines.length; i++) {
      final lineNum = (i + 1).toString().padLeft(4);
      buffer.writeln('$lineNum| ${lines[i]}');
    }

    return buffer.toString();
  }

  Future<String> _handleGrep(Map<String, dynamic> args) async {
    final pattern = args['pattern'] as String;
    final searchPath = args['path'] as String? ?? '';

    final absolutePath = p.join(projectRoot, searchPath);
    final dir = Directory(absolutePath);

    if (!dir.existsSync()) {
      return 'Error: Directory "$searchPath" does not exist.';
    }

    final buffer = StringBuffer();
    buffer.writeln('Searching for: "$pattern"');
    if (searchPath.isNotEmpty) {
      buffer.writeln('In: $searchPath');
    }
    buffer.writeln('---');

    var matchCount = 0;
    const maxMatches = 100;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;

      final relativePath = p.relative(entity.path, from: projectRoot);

      // Skip hidden files/folders and non-text files
      if (relativePath.contains('/.') || relativePath.startsWith('.')) continue;
      if (!_isTextFile(relativePath)) continue;

      try {
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains(pattern)) {
            buffer.writeln('$relativePath:${i + 1}: ${lines[i].trim()}');
            matchCount++;
            if (matchCount >= maxMatches) {
              buffer.writeln('... (truncated at $maxMatches matches)');
              return buffer.toString();
            }
          }
        }
      } catch (_) {
        // Skip files that can't be read
      }
    }

    if (matchCount == 0) {
      buffer.writeln('No matches found.');
    } else {
      buffer.writeln();
      buffer.writeln('Found $matchCount matches.');
    }

    return buffer.toString();
  }

  Future<String> _handleGlob(Map<String, dynamic> args) async {
    final pattern = args['pattern'] as String;

    final buffer = StringBuffer();
    buffer.writeln('Files matching: $pattern');
    buffer.writeln('---');

    final matches = <String>[];
    final dir = Directory(projectRoot);

    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;

      final relativePath = p.relative(entity.path, from: projectRoot);

      // Skip hidden files/folders
      if (relativePath.contains('/.') || relativePath.startsWith('.')) continue;

      if (_matchesGlob(relativePath, pattern)) {
        matches.add(relativePath);
      }
    }

    if (matches.isEmpty) {
      buffer.writeln('No files found.');
    } else {
      matches.sort();
      for (final match in matches) {
        buffer.writeln(match);
      }
      buffer.writeln();
      buffer.writeln('Found ${matches.length} files.');
    }

    return buffer.toString();
  }

  Future<String> _handleQuery(Map<String, dynamic> args) async {
    final queryString = args['q'] as String;

    if (queryExecutor == null) {
      return 'Error: Query executor not available. '
          'Use other tools (ls, grep, read_file) instead.';
    }

    try {
      final result = await queryExecutor!.execute(queryString);
      return result.toText();
    } catch (e) {
      return 'Error executing query: $e';
    }
  }

  // ===== Helpers =====

  bool _hasDocumentation(String relativePath) {
    final docPath = p.join(docsPath, 'folders', relativePath, 'README.md');
    return File(docPath).existsSync();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  bool _isTextFile(String path) {
    final ext = p.extension(path).toLowerCase();
    const textExtensions = {
      '.dart',
      '.md',
      '.txt',
      '.json',
      '.yaml',
      '.yml',
      '.xml',
      '.html',
      '.css',
      '.js',
      '.ts',
      '.py',
      '.sh',
      '.gradle',
      '.properties',
    };
    return textExtensions.contains(ext);
  }

  bool _matchesGlob(String path, String pattern) {
    // Simple glob matching - supports * and **
    var regexPattern = pattern
        .replaceAll('.', r'\.')
        .replaceAll('**/', '.*')
        .replaceAll('**', '.*')
        .replaceAll('*', r'[^/]*');

    if (!pattern.startsWith('*')) {
      regexPattern = '^$regexPattern';
    }
    if (!pattern.endsWith('*')) {
      regexPattern = '$regexPattern\$';
    }

    try {
      return RegExp(regexPattern).hasMatch(path);
    } catch (_) {
      return false;
    }
  }
}
