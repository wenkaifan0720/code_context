import 'package:scip_server/scip_server.dart';

import 'package_registry.dart';

/// Adapter that wraps [PackageRegistry] to implement [IndexProvider].
///
/// This allows the query executor to use PackageRegistry for cross-package
/// queries without PackageRegistry needing to know about the scip_server
/// abstractions.
///
/// ## Usage
///
/// ```dart
/// final registry = PackageRegistry(rootPath: '/path/to/project');
/// final provider = PackageRegistryProvider(registry);
/// final executor = QueryExecutor(registry.projectIndex, provider: provider);
/// ```
class PackageRegistryProvider implements IndexProvider {
  PackageRegistryProvider(this._registry);

  final PackageRegistry _registry;

  /// Access to the underlying registry.
  PackageRegistry get registry => _registry;

  @override
  ScipIndex get projectIndex => _registry.projectIndex;

  @override
  Map<String, ScipIndex> get localIndexes {
    final result = <String, ScipIndex>{};
    for (final pkg in _registry.localPackages.values) {
      result[pkg.name] = pkg.index;
    }
    return result;
  }

  @override
  Iterable<ScipIndex> get allExternalIndexes => _registry.allExternalIndexes;

  @override
  Iterable<ScipIndex> get allIndexes => _registry.allIndexes;

  @override
  SymbolInfo? getSymbol(String symbolId) => _registry.getSymbol(symbolId);

  @override
  OccurrenceInfo? findDefinition(String symbolId) =>
      _registry.findDefinition(symbolId);

  @override
  List<OccurrenceInfo> findAllReferences(String symbolId) =>
      _registry.findAllReferences(symbolId);

  @override
  List<SymbolInfo> findSymbols(String pattern) =>
      _registry.findSymbols(pattern).toList();

  @override
  List<SymbolInfo> findQualified(String container, String member) =>
      _registry.findQualified(container, member).toList();

  @override
  List<SymbolInfo> membersOf(String symbolId) =>
      _registry.membersOf(symbolId);

  @override
  List<SymbolInfo> supertypesOf(String symbolId) =>
      _registry.supertypesOf(symbolId);

  @override
  List<SymbolInfo> subtypesOf(String symbolId) =>
      _registry.subtypesOf(symbolId);

  @override
  List<SymbolInfo> getCalls(String symbolId) =>
      _registry.getCalls(symbolId);

  @override
  List<SymbolInfo> getCallers(String symbolId) =>
      _registry.getCallers(symbolId);

  @override
  List<SymbolInfo> findAllCallersByName(String symbolName) =>
      _registry.findAllCallersByName(symbolName);

  @override
  List<ReferenceWithSource> findAllReferencesByName(
    String symbolName, {
    String? symbolKind,
  }) {
    final results = _registry.findAllReferencesByName(
      symbolName,
      symbolKind: symbolKind,
    );
    return results.map((r) {
      return ReferenceWithSource(
        ref: r.ref,
        sourceRoot: r.sourceRoot,
      );
    }).toList();
  }

  @override
  Future<String?> getSource(String symbolId) =>
      _registry.getSource(symbolId);

  @override
  Future<List<GrepMatchInfo>> grep(
    RegExp pattern, {
    String? pathFilter,
    String? includeGlob,
    String? excludeGlob,
    int linesBefore = 2,
    int linesAfter = 2,
    bool invertMatch = false,
    int? maxPerFile,
    bool multiline = false,
    bool onlyMatching = false,
    bool includeExternal = false,
  }) async {
    final matches = await _registry.grep(
      pattern,
      pathFilter: pathFilter,
      includeGlob: includeGlob,
      excludeGlob: excludeGlob,
      linesBefore: linesBefore,
      linesAfter: linesAfter,
      invertMatch: invertMatch,
      maxPerFile: maxPerFile,
      multiline: multiline,
      onlyMatching: onlyMatching,
      includeExternal: includeExternal,
    );
    return matches.map((m) {
      return GrepMatchInfo(
        file: m.file,
        line: m.line,
        column: m.column,
        matchText: m.matchText,
        contextLines: m.contextLines,
        contextBefore: m.contextBefore,
        symbolContext: m.symbolContext,
        matchLineCount: m.matchLineCount,
      );
    }).toList();
  }
}

/// Extension to easily create an IndexProvider from a PackageRegistry.
extension PackageRegistryProviderExtension on PackageRegistry {
  /// Create an [IndexProvider] adapter for this registry.
  IndexProvider toProvider() => PackageRegistryProvider(this);
}

