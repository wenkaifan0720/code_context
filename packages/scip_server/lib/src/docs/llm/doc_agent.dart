import 'dart:async';

import '../context_builder.dart';
import '../llm_interface.dart';
import 'doc_tools.dart';
import 'llm_service.dart';

/// Agentic documentation generator.
///
/// This agent generates documentation for folders by:
/// 1. Receiving initial context about the folder
/// 2. Using tools to explore and understand the code
/// 3. Generating comprehensive documentation with smart symbols
class DocGenerationAgent implements DocGenerator {
  DocGenerationAgent({
    required LlmService llmService,
    required DocToolRegistry toolRegistry,
    this.maxIterations = 10,
    this.verbose = false,
    this.onLog,
  })  : _llmService = llmService,
        _toolRegistry = toolRegistry;

  final LlmService _llmService;
  final DocToolRegistry _toolRegistry;
  final int maxIterations;
  final bool verbose;
  final void Function(String)? onLog;

  // Track token usage
  int _inputTokens = 0;
  int _outputTokens = 0;

  /// Get total token usage.
  (int input, int output) get tokenUsage => (_inputTokens, _outputTokens);

  @override
  Future<GeneratedDoc> generateFolderDoc(DocContext context) async {
    final config = _getConfigForFolder(context);
    final systemPrompt = _buildFolderSystemPrompt();
    final userPrompt = _buildFolderUserPrompt(context);

    final messages = <LlmMessage>[
      SystemMessage(systemPrompt),
      UserMessage(userPrompt),
    ];

    return _runAgentLoop(
      messages: messages,
      config: config,
      extractDoc: (content) => _extractFolderDoc(content, context),
      folderPath: context.current.path,
    );
  }

  /// Generate a root-level synthesis document.
  ///
  /// This creates a high-level overview by reading ONLY from existing docs,
  /// not from source code. It synthesizes architecture, user flows, and
  /// cross-cutting patterns.
  Future<GeneratedDoc> generateRootDoc({
    required String projectName,
    required List<String> folderDocPaths,
  }) async {
    final systemPrompt = _buildRootSystemPrompt();
    final userPrompt = _buildRootUserPrompt(projectName, folderDocPaths);

    final messages = <LlmMessage>[
      SystemMessage(systemPrompt),
      UserMessage(userPrompt),
    ];

    return _runAgentLoop(
      messages: messages,
      config: LlmConfig.moduleLevel, // Root doc needs more tokens
      extractDoc: _extractRootDoc,
      folderPath: 'root',
    );
  }

  String _buildRootSystemPrompt() => '''
You are writing the ROOT documentation for a codebase. Your job is to SYNTHESIZE 
from existing folder documentation, NOT to read source code.

## Your Task

Create a high-level overview that helps developers understand:
- What this project DOES and WHY it exists
- The overall ARCHITECTURE and how components connect
- Key USER FLOWS (how data/requests move through the system)
- Cross-cutting PATTERNS used throughout the codebase

## Tools Available

- `ls(path)` - list directories to find documentation
- `read_file(path)` - read existing folder documentation
- `grep(pattern, path)` - search across documentation for patterns

## Rules

1. **DO NOT read source code** - only read from `.dart_context/docs/`
2. **Synthesize, don't repeat** - create a unified narrative, not a list of folder summaries
3. **Link to subfolder docs** - use `doc://` links so readers can dive deeper
4. **Identify cross-cutting concerns** - error handling, logging, state management patterns

## Output

Write markdown documentation that includes:
- Project overview (what it does, who it's for)
- Architecture diagram (mermaid) showing major components
- Key user flows with links to relevant folders
- Cross-cutting patterns and conventions
- Links to all major subfolder documentation
''';

  String _buildRootUserPrompt(String projectName, List<String> folderDocPaths) {
    final buffer = StringBuffer();
    buffer.writeln('Create root documentation for: **$projectName**');
    buffer.writeln();
    buffer.writeln('The following folder documentation has been generated:');
    for (final path in folderDocPaths) {
      buffer.writeln('- $path');
    }
    buffer.writeln();
    buffer.writeln(
        'Read these docs using `read_file` and synthesize a high-level overview.');
    buffer.writeln();
    buffer.writeln(
        'Focus on ARCHITECTURE, USER FLOWS, and CROSS-CUTTING PATTERNS.');
    buffer.writeln('Link to subfolder docs using `doc://` protocol.');

    return buffer.toString();
  }

  GeneratedDoc _extractRootDoc(String content) {
    final cleaned = _stripThinking(content);
    final smartSymbols = _extractSmartSymbols(cleaned);
    final title = _extractTitle(cleaned);
    final summary = _extractSummary(cleaned);

    return GeneratedDoc(
      content: cleaned,
      smartSymbols: smartSymbols,
      title: title,
      summary: summary,
    );
  }

  /// Run the agent loop with tool calling.
  Future<GeneratedDoc> _runAgentLoop({
    required List<LlmMessage> messages,
    required LlmConfig config,
    required GeneratedDoc Function(String content) extractDoc,
    String? folderPath, // For logging
  }) async {
    final startTime = DateTime.now();
    final toolCounts = <String, int>{};
    var iterations = 0;
    var iterationInputTokens = 0;
    var iterationOutputTokens = 0;

    while (iterations < maxIterations) {
      iterations++;

      final response = await _llmService.chat(
        messages: messages,
        config: config,
        tools: _toolRegistry.tools,
      );

      _inputTokens += response.inputTokens;
      _outputTokens += response.outputTokens;
      iterationInputTokens += response.inputTokens;
      iterationOutputTokens += response.outputTokens;

      // If no tool calls, we have the final response
      if (!response.hasToolCalls) {
        final content = response.content ?? '';
        _logSummary(
          folderPath: folderPath,
          toolCounts: toolCounts,
          startTime: startTime,
          inputTokens: iterationInputTokens,
          outputTokens: iterationOutputTokens,
        );
        return extractDoc(content);
      }

      // Handle tool calls
      messages.add(AssistantMessage(
        content: response.content,
        toolCalls: response.toolCalls,
      ));

      final toolResults = <LlmToolResult>[];
      for (final call in response.toolCalls) {
        // Track tool usage
        toolCounts[call.name] = (toolCounts[call.name] ?? 0) + 1;
        _log('[Tool Call] ${call.name}(${call.arguments})');
        final result =
            await _toolRegistry.executeTool(call.name, call.arguments);
        _log('[Tool Result] ${result.length} chars');
        toolResults.add(LlmToolResult(
          toolCallId: call.id,
          content: result,
        ));
      }

      messages.add(ToolResultsMessage(toolResults));
    }

    // Max iterations reached - generate with current context
    final response = await _llmService.chat(
      messages: [
        ...messages,
        const UserMessage(
          'Please generate the documentation now with the information you have gathered.',
        ),
      ],
      config: config,
      tools: [], // No tools - force text response
    );

    _inputTokens += response.inputTokens;
    _outputTokens += response.outputTokens;
    iterationInputTokens += response.inputTokens;
    iterationOutputTokens += response.outputTokens;

    _logSummary(
      folderPath: folderPath,
      toolCounts: toolCounts,
      startTime: startTime,
      inputTokens: iterationInputTokens,
      outputTokens: iterationOutputTokens,
    );

    return extractDoc(response.content ?? '');
  }

  /// Log a summary of the generation run.
  void _logSummary({
    String? folderPath,
    required Map<String, int> toolCounts,
    required DateTime startTime,
    required int inputTokens,
    required int outputTokens,
  }) {
    if (!verbose) return;

    final duration = DateTime.now().difference(startTime);
    final durationStr =
        '${duration.inSeconds}.${(duration.inMilliseconds % 1000) ~/ 100}s';

    // Format tool counts
    final toolStr = toolCounts.isEmpty
        ? 'no tools'
        : toolCounts.entries.map((e) => '${e.key}(${e.value})').join(', ');

    // Format tokens (k for thousands)
    final totalTokens = inputTokens + outputTokens;
    final tokenStr = totalTokens >= 1000
        ? '${(totalTokens / 1000).toStringAsFixed(1)}k'
        : '$totalTokens';

    final label = folderPath ?? 'doc';
    _log('[$label] Tools: $toolStr | $durationStr | $tokenStr tokens');
  }

  // ===== Config Selection =====

  LlmConfig _getConfigForFolder(DocContext context) {
    // Count total complexity metrics
    final fileCount = context.current.files.length;
    final symbolCount = context.current.files
        .fold<int>(0, (sum, f) => sum + f.publicApi.length);

    // Model selection heuristic:
    // - Haiku for simple folders (cheap, fast)
    // - Sonnet for moderate folders
    // - Sonnet with higher tokens for complex folders
    if (fileCount < 5 && symbolCount < 20) {
      return LlmConfig.leafLevel; // Haiku - cheap
    } else if (fileCount >= 10 || symbolCount >= 50) {
      return LlmConfig.moduleLevel; // Sonnet with more tokens
    }
    return LlmConfig.folderLevel; // Sonnet - balanced
  }

  // ===== System Prompts =====

  String _buildFolderSystemPrompt() => '''
You are writing documentation for a code folder. Your goal is to help developers 
(and AI agents) understand what this code DOES and WHY it exists, not just what 
files are present.

## Your Task

Write documentation that answers:
- What is the PURPOSE of this folder?
- What PROBLEM does it solve?
- How does the code FLOW through this folder?
- How does it CONNECT to other parts of the codebase?

## Tools Available

- `ls(path)` - list directory contents (subfolders marked [documented] have existing docs)
- `read_file(path, start?, end?)` - read a file or specific line range
- `grep(pattern, path?)` - search for text across files
- `glob(pattern)` - find files matching a pattern
- `query(q)` - run semantic code queries (e.g., "symbols get lib/auth/", "call-graph callers MyClass.method")

## Approach

1. **Start with `ls`** - see what files and subfolders exist. Subfolders marked [documented] 
   have existing docs you can read with `read_file`

2. **Read subfolder docs first** - if subfolders have documentation, read them at 
   `.dart_context/docs/rendered/folders/<path>/README.md` to understand the big picture

3. **Use `query` for code understanding** - get symbol info, call graphs, imports without 
   reading entire files. Example: `query("symbols get lib/auth/")` or `query("call-graph callers AuthService.login")`

4. **Sample strategically** - for large folders, use `grep` to find patterns and 
   `read_file` with line ranges for specific sections

5. **Link precisely** - use `scip://` for code, `doc://` for other docs

## What Good Documentation Looks Like

BAD (enumeration):
> "This folder contains UserService, UserRepository, and UserController."

GOOD (conceptual):
> "This folder implements user management. Requests flow from UserController 
> through UserService (which handles business logic like password hashing) 
> to UserRepository (which persists to the database)."

## Linking

- Link to CODE: `[UserService](scip://lib/src/auth/user_service.dart/UserService#)`
- Link to DOCS: `[Authentication](doc://lib/src/auth)`

Do NOT mix these - doc:// is for linking to other docs, scip:// is for linking to source code.

## Output

Write markdown documentation. Include:
- A clear overview (2-3 sentences explaining purpose)
- Key concepts/components and how they relate
- Data flow or architecture diagram (mermaid) if helpful
- Links to important symbols and subfolder docs
''';

  // ===== User Prompts =====

  String _buildFolderUserPrompt(DocContext context) {
    // Minimal prompt - let the agent explore using tools
    // Don't pass the full context upfront (can exceed token limits for large folders)
    final folderPath = context.current.path;
    final fileCount = context.current.files.length;
    final internalDeps = context.current.internalDeps.take(5).toList();

    final buffer = StringBuffer();
    buffer.writeln('Document this folder: **$folderPath**');
    buffer.writeln();
    buffer.writeln('Context:');
    buffer.writeln('- $fileCount files in this folder');
    if (internalDeps.isNotEmpty) {
      buffer.writeln('- Depends on: ${internalDeps.join(", ")}');
    }
    buffer.writeln();
    buffer.writeln(
        'Start by using `ls` to see what\'s here. If subfolders are marked [documented], read their docs at `.dart_context/docs/rendered/folders/<path>/README.md`.');
    buffer.writeln();
    buffer.writeln(
        'Use `query` for semantic code understanding (symbols, call graphs, imports). Focus on explaining PURPOSE and DATA FLOW.');

    return buffer.toString();
  }

  // ===== Helpers =====

  void _log(String message) {
    if (verbose) {
      onLog?.call(message);
      print(message);
    }
  }

  /// Strip LLM thinking/meta-commentary from generated content.
  ///
  /// Removes lines that look like:
  /// - "Now I have enough information..."
  /// - "Let me generate..."
  /// - Other conversational filler
  String _stripThinking(String content) {
    final lines = content.split('\n');
    final filtered = <String>[];

    for (final line in lines) {
      final trimmed = line.trim().toLowerCase();

      // Skip thinking lines
      if (trimmed.startsWith('now i ') ||
          trimmed.startsWith('let me ') ||
          trimmed.startsWith('i will ') ||
          trimmed.startsWith('i can ') ||
          trimmed.startsWith('i have ') ||
          trimmed.startsWith('i need ') ||
          trimmed.contains('enough information') ||
          trimmed.contains('generate comprehensive')) {
        continue;
      }

      filtered.add(line);
    }

    // Remove leading empty lines
    while (filtered.isNotEmpty && filtered.first.trim().isEmpty) {
      filtered.removeAt(0);
    }

    return filtered.join('\n');
  }

  // ===== Doc Extraction =====

  GeneratedDoc _extractFolderDoc(String content, DocContext context) {
    final cleaned = _stripThinking(content);
    final smartSymbols = _extractSmartSymbols(cleaned);
    final title = _extractTitle(cleaned);
    final summary = _extractSummary(cleaned);

    return GeneratedDoc(
      content: cleaned,
      smartSymbols: smartSymbols,
      title: title,
      summary: summary,
    );
  }

  /// Extract scip:// URIs from content.
  List<String> _extractSmartSymbols(String content) {
    final regex = RegExp(r'scip://[^\s\)>\]]+');
    return regex.allMatches(content).map((m) => m.group(0)!).toList();
  }

  /// Extract title from markdown content.
  String? _extractTitle(String content) {
    final match = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(content);
    return match?.group(1);
  }

  /// Extract first paragraph as summary.
  String? _extractSummary(String content) {
    final lines = content.split('\n');
    final buffer = StringBuffer();

    var inParagraph = false;
    for (final line in lines) {
      // Skip title
      if (line.startsWith('#')) continue;

      // Skip empty lines before paragraph
      if (!inParagraph && line.trim().isEmpty) continue;

      // End paragraph on empty line
      if (inParagraph && line.trim().isEmpty) break;

      inParagraph = true;
      buffer.write(line);
      buffer.write(' ');
    }

    final summary = buffer.toString().trim();
    if (summary.isEmpty) return null;

    // Truncate if too long
    if (summary.length > 200) {
      return '${summary.substring(0, 197)}...';
    }
    return summary;
  }
}
