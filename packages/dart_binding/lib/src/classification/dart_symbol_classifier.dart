/// Dart/Flutter-specific symbol classification.
///
/// Classifies Dart symbols into architectural layers using
/// Flutter-specific patterns like widget inheritance.
library;

import 'package:scip_server/scip_server.dart';

/// Dart/Flutter-specific symbol classifier.
///
/// Implements [ClassificationBinding] for Dart codebases.
class DartSymbolClassifier implements ClassificationBinding {
  DartSymbolClassifier(ScipIndex index)
      : _layerClassifier = _DartLayerClassifier(index),
        _featureDetector = _DartFeatureDetector(index),
        _index = index;

  final _DartLayerClassifier _layerClassifier;
  final _DartFeatureDetector _featureDetector;
  final ScipIndex _index;

  @override
  List<SymbolClassification> classifyAll({String? pattern}) {
    Iterable<SymbolInfo> symbols;

    if (pattern != null && pattern != '*') {
      symbols = _index.findSymbols(pattern);
    } else {
      symbols = _index.allSymbols;
    }

    // Only classify classes, mixins, and top-level symbols
    // Filter out local/anonymous symbols (e.g., "local 82")
    final classifiableSymbols = symbols.where((s) {
      // Skip local/anonymous symbols
      if (s.name.startsWith('local ') || s.name.startsWith('anonymous')) {
        return false;
      }

      final kind = s.kindString.toLowerCase();
      return kind == 'class' ||
          kind == 'mixin' ||
          kind == 'enum' ||
          kind == 'extension';
    });

    return classifiableSymbols.map((symbol) {
      final layerResult = _layerClassifier.classify(symbol);
      final feature = _featureDetector.detectFeature(symbol);

      return SymbolClassification(
        symbol: symbol,
        layer: layerResult.layer,
        feature: feature,
        confidence: layerResult.confidence,
        signals: [
          ...layerResult.signals,
          if (feature != null) 'feature: $feature',
        ],
      );
    }).toList();
  }

  @override
  SymbolClassification classify(SymbolInfo symbol) {
    final layerResult = _layerClassifier.classify(symbol);
    final feature = _featureDetector.detectFeature(symbol);

    return SymbolClassification(
      symbol: symbol,
      layer: layerResult.layer,
      feature: feature,
      confidence: layerResult.confidence,
      signals: [
        ...layerResult.signals,
        if (feature != null) 'feature: $feature',
      ],
    );
  }

  @override
  Map<String, List<SymbolInfo>> detectFeatures() {
    return _featureDetector.clusterByCallGraph();
  }

  /// Get classifications grouped by layer.
  Map<SymbolLayer, List<SymbolClassification>> groupByLayer(
    List<SymbolClassification> classifications,
  ) {
    final grouped = <SymbolLayer, List<SymbolClassification>>{};
    for (final c in classifications) {
      grouped.putIfAbsent(c.layer, () => []).add(c);
    }
    return grouped;
  }

  /// Get classifications grouped by feature.
  Map<String, List<SymbolClassification>> groupByFeature(
    List<SymbolClassification> classifications,
  ) {
    final grouped = <String, List<SymbolClassification>>{};
    for (final c in classifications) {
      final feature = c.feature ?? 'uncategorized';
      grouped.putIfAbsent(feature, () => []).add(c);
    }
    return grouped;
  }
}

/// Dart/Flutter-specific layer classification logic.
class _DartLayerClassifier {
  _DartLayerClassifier(this.index) {
    _buildWidgetClassSet();
  }

  final ScipIndex index;

  /// Cached set of widget class names from SCIP hierarchy.
  late final Set<String> _widgetClasses;

  /// Cached set of service class names (called by UI, calls data).
  late final Set<String> _serviceClasses;

  /// Cached set of data layer class names (called by services).
  late final Set<String> _dataClasses;

  /// Build widget class set from SCIP type hierarchy.
  void _buildWidgetClassSet() {
    _widgetClasses = <String>{};
    _serviceClasses = <String>{};
    _dataClasses = <String>{};

    // First pass: identify widgets from type hierarchy
    // Check relationships - these point to external symbols too (like Flutter SDK)
    for (final symbol in index.allSymbols) {
      if (symbol.kindString != 'class') continue;
      // Skip local/anonymous symbols
      if (symbol.name.startsWith('local ') ||
          symbol.name.startsWith('anonymous')) {
        continue;
      }

      if (_isWidgetFromRelationships(symbol)) {
        _widgetClasses.add(symbol.name);
      }
    }

    // Second pass: also add classes whose supertypes are in _widgetClasses
    var changed = true;
    while (changed) {
      changed = false;
      for (final symbol in index.allSymbols) {
        if (symbol.kindString != 'class') continue;
        if (_widgetClasses.contains(symbol.name)) continue;

        for (final rel in symbol.relationships) {
          if (rel.isImplementation) {
            final supertypeName = _extractNameFromSymbolId(rel.symbol);
            if (_widgetClasses.contains(supertypeName)) {
              _widgetClasses.add(symbol.name);
              changed = true;
              break;
            }
          }
        }
      }
    }

    // Third pass: identify services (called by widgets, not widgets themselves)
    for (final symbol in index.allSymbols) {
      if (symbol.kindString != 'class') continue;
      if (_widgetClasses.contains(symbol.name)) continue;

      final callers = index.getCallers(symbol.symbol);
      final calledByWidget =
          callers.any((c) => _widgetClasses.contains(c.name));

      if (calledByWidget) {
        _serviceClasses.add(symbol.name);
      }
    }

    // Fourth pass: identify data layer (called by services)
    for (final symbol in index.allSymbols) {
      if (symbol.kindString != 'class') continue;
      if (_widgetClasses.contains(symbol.name)) continue;
      if (_serviceClasses.contains(symbol.name)) continue;

      final callers = index.getCallers(symbol.symbol);
      final calledByService =
          callers.any((c) => _serviceClasses.contains(c.name));

      if (calledByService) {
        _dataClasses.add(symbol.name);
      }
    }
  }

  /// Check if a symbol extends Widget from relationships.
  bool _isWidgetFromRelationships(SymbolInfo symbol) {
    for (final rel in symbol.relationships) {
      if (!rel.isImplementation) continue;

      final supertypeName = _extractNameFromSymbolId(rel.symbol);
      if (supertypeName == 'StatelessWidget' ||
          supertypeName == 'StatefulWidget' ||
          supertypeName == 'State' ||
          supertypeName == 'Widget' ||
          supertypeName == 'InheritedWidget' ||
          supertypeName == 'RenderObjectWidget' ||
          supertypeName == 'PreferredSizeWidget') {
        return true;
      }
    }
    return false;
  }

  /// Extract simple name from SCIP symbol ID.
  String _extractNameFromSymbolId(String symbolId) {
    // SCIP symbol format: scip-dart pub package version path/Class#method().
    // Extract the class/type name before # or . or (
    final match =
        RegExp(r'/([A-Za-z_][A-Za-z0-9_]*)[\#\.\(\[]').firstMatch(symbolId);
    if (match != null) return match.group(1)!;

    // Try simpler extraction
    final parts = symbolId.split('/');
    if (parts.isNotEmpty) {
      final last = parts.last.replaceAll(RegExp(r'[\#\.\(\)\[\]].*'), '');
      if (last.isNotEmpty) return last;
    }
    return symbolId;
  }

  /// Naming patterns for each layer (used as fallback/reinforcement).
  static const _namingPatterns = <SymbolLayer, List<String>>{
    SymbolLayer.ui: ['Page', 'Screen', 'View', 'Widget', 'Dialog', 'Sheet'],
    SymbolLayer.service: [
      'Service',
      'Bloc',
      'Cubit',
      'Controller',
      'Notifier',
      'Provider',
      'Manager',
      'UseCase',
    ],
    SymbolLayer.data: [
      'Repository',
      'Repo',
      'DataSource',
      'Dao',
      'Client',
      'Api',
      'Cache',
      'Store',
    ],
    SymbolLayer.model: [
      'Model',
      'Entity',
      'Dto',
      'Response',
      'Request',
      'Event',
      'State',
    ],
    SymbolLayer.util: ['Utils', 'Util', 'Helper', 'Extension', 'Constants'],
  };

  /// Classify a symbol using SCIP data and naming patterns.
  SymbolClassification classify(SymbolInfo symbol) {
    final signals = <String>[];
    var totalScore = 0.0;
    final layerScores = <SymbolLayer, double>{};

    // Signal 1: SCIP type hierarchy (highest confidence for UI)
    if (_widgetClasses.contains(symbol.name)) {
      layerScores[SymbolLayer.ui] = (layerScores[SymbolLayer.ui] ?? 0) + 4.0;
      signals.add('SCIP: extends Widget hierarchy');
      totalScore += 4.0;
    }

    // Signal 2: SCIP call graph analysis
    final callGraphLayer = _classifyByCallGraph(symbol);
    if (callGraphLayer != null) {
      layerScores[callGraphLayer] = (layerScores[callGraphLayer] ?? 0) + 3.0;
      signals.add('SCIP: call graph → $callGraphLayer');
      totalScore += 3.0;
    }

    // Signal 3: Naming conventions (reinforcement)
    final namingLayer = classifyByNaming(symbol.name);
    if (namingLayer != SymbolLayer.unknown) {
      layerScores[namingLayer] = (layerScores[namingLayer] ?? 0) + 1.5;
      signals.add('naming: ${symbol.name} → $namingLayer');
      totalScore += 1.5;
    }

    // Signal 4: File path patterns (lower weight)
    final pathLayer = _classifyByPath(symbol.file);
    if (pathLayer != SymbolLayer.unknown) {
      layerScores[pathLayer] = (layerScores[pathLayer] ?? 0) + 1.0;
      signals.add('path: ${symbol.file} → $pathLayer');
      totalScore += 1.0;
    }

    // Determine winning layer
    SymbolLayer bestLayer = SymbolLayer.unknown;
    double bestScore = 0;
    for (final entry in layerScores.entries) {
      if (entry.value > bestScore) {
        bestScore = entry.value;
        bestLayer = entry.key;
      }
    }

    // Calculate confidence
    final confidence =
        totalScore > 0 ? (bestScore / totalScore).clamp(0.0, 1.0) : 0.0;

    return SymbolClassification(
      symbol: symbol,
      layer: bestLayer,
      confidence: confidence,
      signals: signals,
    );
  }

  /// Classify by call graph relationships.
  SymbolLayer? _classifyByCallGraph(SymbolInfo symbol) {
    final name = symbol.name;

    // Already classified from SCIP hierarchy
    if (_widgetClasses.contains(name)) return SymbolLayer.ui;

    // Classified as service from call graph analysis
    if (_serviceClasses.contains(name)) return SymbolLayer.service;

    // Classified as data from call graph analysis
    if (_dataClasses.contains(name)) return SymbolLayer.data;

    // Check if it's a model (used by many, calls few)
    final callers = index.getCallers(symbol.symbol).length;
    final calls = index.getCalls(symbol.symbol).length;
    if (callers > 3 && calls < 2) {
      return SymbolLayer.model;
    }

    return null;
  }

  /// Classify by naming convention (used as reinforcement signal).
  SymbolLayer classifyByNaming(String name) {
    for (final entry in _namingPatterns.entries) {
      for (final suffix in entry.value) {
        if (name.endsWith(suffix) || name == suffix) {
          return entry.key;
        }
      }
    }
    return SymbolLayer.unknown;
  }

  /// Classify by file path patterns.
  SymbolLayer _classifyByPath(String? filePath) {
    if (filePath == null) return SymbolLayer.unknown;

    final path = filePath.toLowerCase();

    // Common directory patterns
    if (path.contains('/ui/') ||
        path.contains('/screens/') ||
        path.contains('/pages/') ||
        path.contains('/views/') ||
        path.contains('/widgets/')) {
      return SymbolLayer.ui;
    }

    if (path.contains('/services/') ||
        path.contains('/blocs/') ||
        path.contains('/controllers/') ||
        path.contains('/providers/')) {
      return SymbolLayer.service;
    }

    if (path.contains('/data/') ||
        path.contains('/repositories/') ||
        path.contains('/datasources/') ||
        path.contains('/api/')) {
      return SymbolLayer.data;
    }

    if (path.contains('/models/') ||
        path.contains('/entities/') ||
        path.contains('/domain/')) {
      return SymbolLayer.model;
    }

    if (path.contains('/utils/') ||
        path.contains('/helpers/') ||
        path.contains('/core/') ||
        path.contains('/common/')) {
      return SymbolLayer.util;
    }

    return SymbolLayer.unknown;
  }
}

/// Dart/Flutter-specific feature detection.
class _DartFeatureDetector {
  _DartFeatureDetector(this.index);

  final ScipIndex index;

  /// Common suffixes to strip when extracting feature names.
  static const _suffixesToStrip = [
    'Service',
    'Repository',
    'Repo',
    'Controller',
    'Bloc',
    'Cubit',
    'Notifier',
    'Provider',
    'Page',
    'Screen',
    'View',
    'Widget',
    'Model',
    'Entity',
    'Client',
    'Api',
    'Manager',
    'Handler',
    'DataSource',
  ];

  /// Detect feature for a symbol using multiple signals.
  String? detectFeature(SymbolInfo symbol) {
    // Signal 1: Extract from directory structure (highest confidence)
    final pathFeature = detectFromPath(symbol.file);
    if (pathFeature != null) return pathFeature;

    // Signal 2: Extract from naming prefix
    final nameFeature = detectFromNaming(symbol.name);
    if (nameFeature != null) return nameFeature;

    return null;
  }

  /// Extract feature from directory structure.
  String? detectFromPath(String? filePath) {
    if (filePath == null) return null;

    // Try features/<name>/ or modules/<name>/ pattern first (most specific)
    final featuresMatch =
        RegExp(r'(?:features|modules)/([a-z][a-z0-9_]*)/').firstMatch(filePath);
    if (featuresMatch != null) {
      final feature = featuresMatch.group(1)!;
      return _normalizeFeatureName(feature);
    }

    // Fall back to lib/<name>/ pattern, but skip common directories
    final libMatch = RegExp(r'lib/([a-z][a-z0-9_]*)/').firstMatch(filePath);
    if (libMatch != null) {
      final feature = libMatch.group(1)!;
      // Skip common non-feature directories
      if (!['src', 'core', 'common', 'shared', 'utils', 'features', 'modules']
          .contains(feature)) {
        return _normalizeFeatureName(feature);
      }
    }

    return null;
  }

  /// Extract feature from symbol naming prefix.
  String? detectFromNaming(String name) {
    // Strip known suffixes
    String baseName = name;
    for (final suffix in _suffixesToStrip) {
      if (name.endsWith(suffix) && name.length > suffix.length) {
        baseName = name.substring(0, name.length - suffix.length);
        break;
      }
    }

    if (baseName.isEmpty || baseName == name) return null;

    // Convert to lowercase feature name
    return _normalizeFeatureName(baseName);
  }

  /// Normalize feature name to lowercase with underscores.
  String _normalizeFeatureName(String name) {
    // Convert CamelCase to snake_case
    final snakeCase = name
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (m) => '${m.group(1)}_${m.group(2)}',
        )
        .toLowerCase();
    return snakeCase;
  }

  /// Cluster symbols by call graph relationships.
  Map<String, List<SymbolInfo>> clusterByCallGraph() {
    final clusters = <String, List<SymbolInfo>>{};
    final symbolToCluster = <String, String>{};

    // First pass: assign initial clusters based on detected features
    for (final symbol in index.allSymbols) {
      final feature = detectFeature(symbol);
      if (feature != null) {
        clusters.putIfAbsent(feature, () => []).add(symbol);
        symbolToCluster[symbol.symbol] = feature;
      }
    }

    // Second pass: assign unclustered symbols based on who calls them
    for (final symbol in index.allSymbols) {
      if (symbolToCluster.containsKey(symbol.symbol)) continue;

      final callers = index.getCallers(symbol.symbol);
      final callerClusters = <String, int>{};

      for (final caller in callers) {
        final cluster = symbolToCluster[caller.symbol];
        if (cluster != null) {
          callerClusters[cluster] = (callerClusters[cluster] ?? 0) + 1;
        }
      }

      // Assign to the cluster with most callers
      if (callerClusters.isNotEmpty) {
        final bestCluster = callerClusters.entries
            .reduce((a, b) => a.value > b.value ? a : b)
            .key;
        clusters.putIfAbsent(bestCluster, () => []).add(symbol);
        symbolToCluster[symbol.symbol] = bestCluster;
      }
    }

    return clusters;
  }
}
