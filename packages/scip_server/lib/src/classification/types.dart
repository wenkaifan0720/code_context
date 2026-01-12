/// Language-agnostic classification types.
///
/// These data structures are used across all language bindings
/// for symbol classification and navigation detection.
library;

import '../index/scip_index.dart';

// ============================================================================
// Symbol Classification Types
// ============================================================================

/// Architectural layer for a symbol.
enum SymbolLayer {
  /// UI layer - widgets, pages, screens, views, components
  ui,

  /// Service layer - business logic, blocs, controllers, use cases
  service,

  /// Data layer - repositories, data sources, API clients
  data,

  /// Model layer - entities, DTOs, value objects
  model,

  /// Utility layer - helpers, extensions, constants
  util,

  /// Unknown/unclassified
  unknown,
}

/// Classification result for a single symbol.
class SymbolClassification {
  const SymbolClassification({
    required this.symbol,
    required this.layer,
    this.feature,
    required this.confidence,
    this.signals = const [],
  });

  /// The classified symbol.
  final SymbolInfo symbol;

  /// Detected architectural layer.
  final SymbolLayer layer;

  /// Detected feature/module name (e.g., "auth", "products").
  final String? feature;

  /// Confidence score (0.0 - 1.0).
  final double confidence;

  /// Signals that contributed to the classification.
  final List<String> signals;

  @override
  String toString() =>
      'Classification(${symbol.name}: $layer, feature: $feature, confidence: $confidence)';

  /// Convert to JSON for serialization.
  Map<String, dynamic> toJson() => {
        'symbol': symbol.symbol,
        'name': symbol.name,
        'layer': layer.name,
        'feature': feature,
        'confidence': confidence,
        'signals': signals,
      };
}

// ============================================================================
// Navigation Types
// ============================================================================

/// A navigation edge between two screens/pages.
class NavigationEdge {
  const NavigationEdge({
    required this.fromScreen,
    required this.toScreen,
    this.trigger,
    this.label,
    this.routePath,
  });

  /// Source screen name.
  final String fromScreen;

  /// Target screen name.
  final String toScreen;

  /// What triggers the navigation (e.g., "button tap", "onSuccess").
  final String? trigger;

  /// Human-readable label for the edge.
  final String? label;

  /// Route path if using named routes (e.g., "/home", "/products/:id").
  final String? routePath;

  @override
  String toString() =>
      '$fromScreen → $toScreen${trigger != null ? ' ($trigger)' : ''}';

  @override
  bool operator ==(Object other) =>
      other is NavigationEdge &&
      fromScreen == other.fromScreen &&
      toScreen == other.toScreen &&
      trigger == other.trigger;

  @override
  int get hashCode => Object.hash(fromScreen, toScreen, trigger);

  /// Convert to JSON for serialization.
  Map<String, dynamic> toJson() => {
        'from': fromScreen,
        'to': toScreen,
        'trigger': trigger,
        'label': label,
        'routePath': routePath,
      };
}

/// Detected router/navigation framework type.
enum RouterType {
  /// Flutter Navigator
  navigator,

  /// go_router package
  goRouter,

  /// auto_route package
  autoRoute,

  /// GetX navigation
  getX,

  /// React Router (for future TypeScript support)
  reactRouter,

  /// Next.js routing (for future TypeScript support)
  nextJs,

  /// Unknown/undetected
  unknown,
}

/// Result of navigation detection.
class NavigationGraph {
  const NavigationGraph({
    required this.screens,
    required this.edges,
    required this.routerType,
    this.entryScreen,
  });

  /// All detected screens/pages.
  final List<SymbolInfo> screens;

  /// Navigation edges between screens.
  final List<NavigationEdge> edges;

  /// Detected router/navigation framework type.
  final RouterType routerType;

  /// Entry point screen (if detected).
  final String? entryScreen;

  /// Convert to JSON for serialization.
  Map<String, dynamic> toJson() => {
        'nodes': screens.map((s) => s.name).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
        'routerType': routerType.name,
        'entryScreen': entryScreen,
      };
}

// ============================================================================
// Feature Detection Types
// ============================================================================

/// A detected feature/module in the codebase.
class DetectedFeature {
  const DetectedFeature({
    required this.name,
    required this.symbols,
    this.path,
  });

  /// Feature name (e.g., "auth", "products").
  final String name;

  /// Symbols belonging to this feature.
  final List<SymbolInfo> symbols;

  /// Common path prefix for this feature's files.
  final String? path;
}
