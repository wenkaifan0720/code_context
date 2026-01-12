/// Base interfaces for language-specific classification.
///
/// Each language binding (Dart, TypeScript, etc.) implements these
/// interfaces to provide symbol classification and navigation detection.
library;

import '../index/scip_index.dart';
import 'types.dart';

/// Interface for language-specific navigation detection.
///
/// Implementations detect navigation patterns specific to their language
/// and framework (e.g., Flutter's go_router, React Router, etc.).
abstract class NavigationBinding {
  /// Build navigation graph for the codebase.
  ///
  /// Detects screens/pages and navigation edges between them.
  Future<NavigationGraph> buildNavigationGraph({String? entryPoint});

  /// Find all page/screen widgets in the index.
  ///
  /// Returns symbols that represent navigable screens.
  Future<List<SymbolInfo>> findPages();
}

/// Interface for language-specific symbol classification.
///
/// Implementations classify symbols into architectural layers
/// based on language-specific patterns (e.g., Flutter widgets → UI layer).
abstract class ClassificationBinding {
  /// Classify all symbols in the index.
  List<SymbolClassification> classifyAll();

  /// Classify a single symbol.
  SymbolClassification classify(SymbolInfo symbol);

  /// Detect features/modules in the codebase.
  Map<String, List<SymbolInfo>> detectFeatures();
}
