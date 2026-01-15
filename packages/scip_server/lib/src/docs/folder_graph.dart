import 'dart:io';

import 'package:path/path.dart' as p;

import '../index/scip_index.dart';

/// Configuration for folder collapse behavior.
class CollapseConfig {
  const CollapseConfig({
    this.lineThreshold = 500,
    this.hysteresisLow = 450,
    this.hysteresisHigh = 550,
    this.maxDepth = 3,
    this.enabled = true,
  });

  /// Default configuration (no collapsing).
  static const disabled = CollapseConfig(enabled: false);

  /// Line count threshold for collapsing.
  final int lineThreshold;

  /// Lower hysteresis bound (collapse when below this).
  final int hysteresisLow;

  /// Upper hysteresis bound (expand when above this).
  final int hysteresisHigh;

  /// Maximum depth under lib/ before forcing collapse.
  final int maxDepth;

  /// Whether collapse is enabled.
  final bool enabled;
}

/// Decision about which folders should be collapsed.
class CollapseDecision {
  const CollapseDecision({
    required this.collapsedRoots,
    required this.childToRoot,
    required this.expandedFolders,
    required this.folderLineCounts,
  });

  /// Create an empty decision (no collapsing).
  const CollapseDecision.none()
      : collapsedRoots = const {},
        childToRoot = const {},
        expandedFolders = const {},
        folderLineCounts = const {};

  /// Folders that are collapse roots (generate a single doc for subtree).
  final Set<String> collapsedRoots;

  /// Maps collapsed children to their root folder.
  /// Children should NOT have their own docs generated.
  final Map<String, String> childToRoot;

  /// Folders that get individual docs (not collapsed).
  final Set<String> expandedFolders;

  /// Line counts for each folder subtree.
  final Map<String, int> folderLineCounts;

  /// Check if a folder is a collapsed root.
  bool isCollapsedRoot(String folder) => collapsedRoots.contains(folder);

  /// Check if a folder is a collapsed child (should not get its own doc).
  bool isCollapsedChild(String folder) => childToRoot.containsKey(folder);

  /// Get the collapse root for a folder, or null if not collapsed.
  String? getCollapseRoot(String folder) {
    if (collapsedRoots.contains(folder)) return folder;
    return childToRoot[folder];
  }

  /// Get all folders that should have docs generated.
  Set<String> get foldersToGenerate => {...collapsedRoots, ...expandedFolders};

  /// Get all subfolders included in a collapsed root.
  List<String> getCollapsedSubfolders(String root) {
    if (!collapsedRoots.contains(root)) return [];
    return childToRoot.entries
        .where((e) => e.value == root)
        .map((e) => e.key)
        .toList()
      ..sort();
  }

  @override
  String toString() {
    return 'CollapseDecision('
        'roots: ${collapsedRoots.length}, '
        'children: ${childToRoot.length}, '
        'expanded: ${expandedFolders.length})';
  }
}

/// A folder-level dependency graph built from SCIP index.
///
/// Aggregates file-level imports to folder level, providing:
/// - Internal dependencies (folders this folder imports from)
/// - External dependencies (packages this folder imports)
/// - Dependents (folders that import from this folder)
///
/// This is used to determine the order of documentation generation
/// and to track which folders need regeneration when dependencies change.
class FolderDependencyGraph {
  FolderDependencyGraph._({
    required this.folders,
    required Map<String, Set<String>> internalDeps,
    required Map<String, Set<String>> externalDeps,
    required Map<String, Set<String>> dependents,
    Set<String>? files,
  })  : _internalDeps = internalDeps,
        _externalDeps = externalDeps,
        _dependents = dependents,
        _filesInFolders = files ?? {};

  /// Create a graph for testing purposes.
  ///
  /// This allows testing graph query methods without needing a full ScipIndex.
  factory FolderDependencyGraph.forTesting({
    required Set<String> folders,
    required Map<String, Set<String>> internalDeps,
    Map<String, Set<String>>? externalDeps,
    Map<String, Set<String>>? dependents,
    Set<String>? files,
  }) {
    // Auto-compute dependents if not provided
    final computedDependents = dependents ?? <String, Set<String>>{};
    if (dependents == null) {
      for (final folder in folders) {
        computedDependents[folder] = {};
      }
      for (final entry in internalDeps.entries) {
        for (final dep in entry.value) {
          computedDependents.putIfAbsent(dep, () => {}).add(entry.key);
        }
      }
    }

    return FolderDependencyGraph._(
      folders: folders,
      internalDeps: internalDeps,
      externalDeps: externalDeps ?? {},
      dependents: computedDependents,
      files: files,
    );
  }

  /// All folders in the graph.
  final Set<String> folders;

  /// folder -> folders it imports from (internal project folders)
  final Map<String, Set<String>> _internalDeps;

  /// folder -> packages it imports (external dependencies)
  final Map<String, Set<String>> _externalDeps;

  /// folder -> folders that import from it
  final Map<String, Set<String>> _dependents;

  /// All files indexed (used for line counting).
  final Set<String> _filesInFolders;

  /// Build a folder dependency graph from a SCIP index.
  ///
  /// Analyzes all files in the index, extracts their imports,
  /// and aggregates to folder level.
  static FolderDependencyGraph build(ScipIndex index) {
    final folders = <String>{};
    final internalDeps = <String, Set<String>>{};
    final externalDeps = <String, Set<String>>{};
    final dependents = <String, Set<String>>{};

    // First pass: collect all folders AND their ancestors
    // This ensures intermediate directories (like lib/features/auth/)
    // are included even if they don't contain files directly.
    for (final file in index.files) {
      var folder = p.dirname(file);
      
      // Add this folder and all ancestors up to (but not including) root
      while (folder.isNotEmpty && folder != '.' && folder != '/') {
        if (folders.add(folder)) {
          // Only initialize if newly added
          internalDeps.putIfAbsent(folder, () => {});
          externalDeps.putIfAbsent(folder, () => {});
          dependents.putIfAbsent(folder, () => {});
        }
        final parent = p.dirname(folder);
        if (parent == folder) break; // Reached root
        folder = parent;
      }
    }

    // Second pass: analyze imports via SCIP relationships
    for (final file in index.files) {
      final sourceFolder = p.dirname(file);
      final symbols = index.symbolsInFile(file);

      for (final symbol in symbols) {
        // Look at what this symbol calls/references
        final calls = index.getCalls(symbol.symbol);
        for (final calledSymbol in calls) {
          _addDependency(
            sourceFolder: sourceFolder,
            calledSymbol: calledSymbol,
            folders: folders,
            internalDeps: internalDeps,
            externalDeps: externalDeps,
            dependents: dependents,
          );
        }

        // Also look at relationships (implements, etc.)
        for (final rel in symbol.relationships) {
          final relSymbol = index.getSymbol(rel.symbol);
          if (relSymbol != null) {
            _addDependency(
              sourceFolder: sourceFolder,
              calledSymbol: relSymbol,
              folders: folders,
              internalDeps: internalDeps,
              externalDeps: externalDeps,
              dependents: dependents,
            );
          }
        }
      }
    }

    return FolderDependencyGraph._(
      folders: folders,
      internalDeps: internalDeps,
      externalDeps: externalDeps,
      dependents: dependents,
      files: index.files.toSet(),
    );
  }

  static void _addDependency({
    required String sourceFolder,
    required SymbolInfo calledSymbol,
    required Set<String> folders,
    required Map<String, Set<String>> internalDeps,
    required Map<String, Set<String>> externalDeps,
    required Map<String, Set<String>> dependents,
  }) {
    if (calledSymbol.isExternal) {
      // External package dependency
      final packageName = _extractPackageName(calledSymbol.symbol);
      if (packageName != null) {
        externalDeps[sourceFolder]?.add(packageName);
      }
    } else if (calledSymbol.file != null) {
      // Internal dependency
      final targetFolder = p.dirname(calledSymbol.file!);
      if (targetFolder != sourceFolder && folders.contains(targetFolder)) {
        internalDeps[sourceFolder]?.add(targetFolder);
        dependents[targetFolder]?.add(sourceFolder);
      }
    }
  }

  /// Extract package name from a SCIP symbol ID.
  ///
  /// SCIP symbols look like:
  /// `scip-dart pub firebase_auth 4.6.0 lib/src/firebase_auth.dart/FirebaseAuth#`
  static String? _extractPackageName(String symbol) {
    // Pattern: scip-dart <manager> <package> <version> <path>
    final parts = symbol.split(' ');
    if (parts.length >= 3) {
      // parts[0] = "scip-dart", parts[1] = "pub", parts[2] = package name
      return parts[2];
    }
    return null;
  }

  /// Get internal folders that this folder depends on.
  Set<String> getInternalDependencies(String folder) {
    return _internalDeps[folder] ?? {};
  }

  /// Get external packages that this folder depends on.
  Set<String> getExternalDependencies(String folder) {
    return _externalDeps[folder] ?? {};
  }

  /// Get folders that depend on this folder.
  Set<String> getDependents(String folder) {
    return _dependents[folder] ?? {};
  }

  /// Get the internal dependency graph as a map.
  ///
  /// Returns folder -> set of folders it depends on.
  Map<String, Set<String>> get internalDependencyGraph => _internalDeps;

  /// Check if folder A depends on folder B (directly).
  bool dependsOn(String folderA, String folderB) {
    return _internalDeps[folderA]?.contains(folderB) ?? false;
  }

  /// Check if folder A transitively depends on folder B.
  bool transitivelyDependsOn(String folderA, String folderB) {
    final visited = <String>{};
    final queue = <String>[folderA];

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (current == folderB) return true;
      if (visited.contains(current)) continue;
      visited.add(current);

      final deps = _internalDeps[current];
      if (deps != null) {
        queue.addAll(deps);
      }
    }

    return false;
  }

  /// Get summary statistics.
  Map<String, int> get stats => {
        'folders': folders.length,
        'internalEdges':
            _internalDeps.values.fold(0, (sum, deps) => sum + deps.length),
        'externalPackages': _externalDeps.values
            .expand((deps) => deps)
            .toSet()
            .length,
      };

  /// Compute which folders should be collapsed based on criteria.
  ///
  /// Collapse criteria:
  /// 1. Line count: Folders with subtree < lineThreshold are collapsed
  /// 2. Depth: Folders more than maxDepth levels under lib/ are collapsed
  ///
  /// Uses hysteresis to prevent oscillation at boundaries.
  /// 
  /// **Key: Top-down evaluation** - We check parent folders first.
  /// If a parent qualifies for collapse, ALL its descendants become
  /// collapsed children, and we generate only one doc for the parent.
  Future<CollapseDecision> computeCollapseDecision({
    required CollapseConfig config,
    required String projectRoot,
    Map<String, bool>? previousCollapseState,
  }) async {
    if (!config.enabled) {
      return CollapseDecision(
        collapsedRoots: {},
        childToRoot: {},
        expandedFolders: folders,
        folderLineCounts: {},
      );
    }

    // Step 1: Compute line counts for each folder subtree
    final folderLineCounts = await _computeFolderLineCounts(projectRoot);

    // Step 2: Determine collapse state for each folder (top-down)
    final collapsedRoots = <String>{};
    final childToRoot = <String, String>{};
    final expandedFolders = <String>{};

    // Process folders from SHALLOWEST to DEEPEST (top-down)
    // This ensures parent folders are evaluated first - if a parent
    // qualifies for collapse, all descendants become collapsed children.
    final sortedFolders = folders.toList()
      ..sort((a, b) => a.split('/').length.compareTo(b.split('/').length));

    for (final folder in sortedFolders) {
      // Skip if already marked as a child of a collapsed root
      if (childToRoot.containsKey(folder)) continue;

      final shouldCollapse = _shouldCollapse(
        folder: folder,
        config: config,
        folderLineCounts: folderLineCounts,
        previousCollapseState: previousCollapseState,
      );

      if (shouldCollapse) {
        // This folder becomes a collapsed root
        collapsedRoots.add(folder);

        // Mark ALL descendants as children of this root
        // This handles "virtual" folders (folders without files)
        for (final otherFolder in folders) {
          if (otherFolder != folder &&
              otherFolder.startsWith('$folder/')) {
            childToRoot[otherFolder] = folder;
          }
        }
      } else {
        expandedFolders.add(folder);
      }
    }

    return CollapseDecision(
      collapsedRoots: collapsedRoots,
      childToRoot: childToRoot,
      expandedFolders: expandedFolders,
      folderLineCounts: folderLineCounts,
    );
  }

  /// Compute line counts for each folder and its subtree.
  Future<Map<String, int>> _computeFolderLineCounts(String projectRoot) async {
    final lineCounts = <String, int>{};

    for (final folder in folders) {
      var totalLines = 0;

      // Count lines in files directly in this folder
      for (final file in _getFilesInFolder(folder)) {
        final filePath = p.join(projectRoot, file);
        try {
          final content = await File(filePath).readAsString();
          totalLines += content.split('\n').length;
        } catch (_) {
          // File might not exist or be unreadable
        }
      }

      lineCounts[folder] = totalLines;
    }

    // Add subtree line counts
    final subtreeCounts = <String, int>{};
    for (final folder in folders) {
      subtreeCounts[folder] = _computeSubtreeLineCount(folder, lineCounts);
    }

    return subtreeCounts;
  }

  /// Get files directly in a folder (not subfolders).
  List<String> _getFilesInFolder(String folder) {
    final result = <String>[];
    for (final file in _allFiles) {
      if (_isFileInFolder(file, folder)) {
        result.add(file);
      }
    }
    return result;
  }

  /// Helper to get all indexed files.
  Set<String> get _allFiles => _filesInFolders;

  static bool _isFileInFolder(String filePath, String folderPath) {
    if (!filePath.startsWith(folderPath)) return false;

    final remainder = filePath.substring(folderPath.length);
    if (!remainder.startsWith('/')) return false;

    final afterSlash = remainder.substring(1);
    return !afterSlash.contains('/');
  }

  /// Compute subtree line count (folder + all descendants).
  int _computeSubtreeLineCount(String folder, Map<String, int> lineCounts) {
    var total = lineCounts[folder] ?? 0;

    for (final otherFolder in folders) {
      if (otherFolder != folder && otherFolder.startsWith('$folder/')) {
        total += lineCounts[otherFolder] ?? 0;
      }
    }

    return total;
  }


  /// Determine if a folder should be collapsed.
  bool _shouldCollapse({
    required String folder,
    required CollapseConfig config,
    required Map<String, int> folderLineCounts,
    Map<String, bool>? previousCollapseState,
  }) {
    // Check depth limit (folders under lib/)
    if (_exceedsDepthLimit(folder, config.maxDepth)) {
      return true;
    }

    // Check line count with hysteresis
    final lineCount = folderLineCounts[folder] ?? 0;
    final wasCollapsed = previousCollapseState?[folder] ?? false;

    if (wasCollapsed) {
      // Currently collapsed - only expand if above high threshold
      return lineCount < config.hysteresisHigh;
    } else {
      // Currently expanded - only collapse if below low threshold
      return lineCount < config.hysteresisLow;
    }
  }

  /// Check if folder exceeds the depth limit under lib/.
  bool _exceedsDepthLimit(String folder, int maxDepth) {
    // Find lib/ in the path
    final parts = folder.split('/');
    final libIndex = parts.indexOf('lib');

    if (libIndex < 0) return false;

    // Count depth after lib/
    final depthAfterLib = parts.length - libIndex - 1;
    return depthAfterLib > maxDepth;
  }

  @override
  String toString() {
    final buffer = StringBuffer('FolderDependencyGraph(\n');
    for (final folder in folders.toList()..sort()) {
      final internal = _internalDeps[folder] ?? {};
      final external = _externalDeps[folder] ?? {};
      buffer.writeln('  $folder:');
      if (internal.isNotEmpty) {
        buffer.writeln('    internal: ${internal.join(", ")}');
      }
      if (external.isNotEmpty) {
        buffer.writeln('    external: ${external.join(", ")}');
      }
    }
    buffer.write(')');
    return buffer.toString();
  }
}
