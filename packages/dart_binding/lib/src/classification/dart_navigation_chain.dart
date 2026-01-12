/// Dart/Flutter-specific AST-based navigation chain extraction.
///
/// Uses the Dart analyzer to build detailed containment chains
/// from page → method → widget → callback → navigation.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// A node in the navigation containment chain.
sealed class ChainNode {
  String get displayName;
}

/// A method or function in the chain.
class MethodNode extends ChainNode {
  MethodNode(this.name, {this.isPrivate = false});
  final String name;
  final bool isPrivate;

  @override
  String get displayName => name;
}

/// A class in the chain (usually a widget).
class ClassNode extends ChainNode {
  ClassNode(this.name, {this.isWidget = false});
  final String name;
  final bool isWidget;

  @override
  String get displayName => name;
}

/// A callback parameter in the chain.
class CallbackNode extends ChainNode {
  CallbackNode(this.name);
  final String name;

  @override
  String get displayName => name;
}

/// A control flow boundary (if/for/while/switch).
class ControlFlowNode extends ChainNode {
  ControlFlowNode(this.type, {this.condition});
  final String type; // 'if', 'for', 'while', 'switch'
  final String? condition;

  @override
  String get displayName => condition != null ? '$type($condition)' : type;
}

/// Widget instantiation in the chain.
class WidgetNode extends ChainNode {
  WidgetNode(this.name);
  final String name;

  @override
  String get displayName => name;
}

/// Extracts navigation chains using the Dart analyzer.
///
/// This is Dart/Flutter-specific and understands widget patterns.
class DartNavigationChainExtractor {
  /// Create an extractor with type information from SCIP index.
  ///
  /// [widgetClasses] - Set of class names that are widgets (extend Widget)
  DartNavigationChainExtractor({
    Set<String>? widgetClasses,
  }) : _widgetClasses = widgetClasses ?? const {};

  /// Widget class names from SCIP type hierarchy.
  final Set<String> _widgetClasses;

  /// Cache of parsed files to avoid re-parsing.
  final _parseCache = <String, _ParsedFile>{};

  /// Extract the containment chain for a navigation call at the given line.
  Future<List<ChainNode>> extractChain({
    required String filePath,
    required int line,
    required int column,
  }) async {
    // Parse the file (or use cached version)
    final parsed = await _parseFile(filePath);
    if (parsed == null) return [];

    // Convert line/column to byte offset
    // Note: line is 0-indexed (from _offsetToLine)
    int offset;
    try {
      offset = parsed.lineInfo.getOffsetOfLine(line) + column;
    } catch (e) {
      return [];
    }

    // Find the navigation node at this location
    final navNode = _findNodeAtOffset(parsed.unit, offset);
    if (navNode == null) return [];

    // Walk up the AST, collecting chain nodes
    return _buildChainFromNode(navNode);
  }

  /// Parse a file and cache the result.
  Future<_ParsedFile?> _parseFile(String filePath) async {
    if (_parseCache.containsKey(filePath)) {
      return _parseCache[filePath];
    }

    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      // Allow parsing even with syntax errors - we just need the AST structure
      final result = parseString(
        content: content,
        path: filePath,
        throwIfDiagnostics: false,
      );
      final parsed = _ParsedFile(result.unit, result.lineInfo);
      _parseCache[filePath] = parsed;
      return parsed;
    } catch (e) {
      return null;
    }
  }

  /// Find the innermost AST node containing the given offset.
  AstNode? _findNodeAtOffset(CompilationUnit unit, int offset) {
    final visitor = _NodeAtOffsetVisitor(offset);
    unit.accept(visitor);
    return visitor.foundNode;
  }

  /// Build the chain by walking up from a node.
  List<ChainNode> _buildChainFromNode(AstNode node) {
    final chain = <ChainNode>[];
    AstNode? current = node;

    while (current != null) {
      final chainNode = _nodeToChainNode(current);
      if (chainNode != null) {
        chain.add(chainNode);
      }
      current = current.parent;
    }

    // Reverse to get top-down order (Page → Method → Widget → Callback)
    return chain.reversed.toList();
  }

  /// Convert an AST node to a chain node (if relevant).
  ChainNode? _nodeToChainNode(AstNode node) {
    switch (node) {
      case ClassDeclaration():
        return ClassNode(
          node.name.lexeme,
          isWidget: _isWidgetClass(node),
        );

      case MethodDeclaration():
        final name = node.name.lexeme;
        if (_isGenericMethod(name)) return null;
        return MethodNode(name, isPrivate: name.startsWith('_'));

      case FunctionDeclaration():
        final name = node.name.lexeme;
        if (_isGenericMethod(name)) return null;
        return MethodNode(name, isPrivate: name.startsWith('_'));

      case FunctionExpression():
        // Detect callbacks by usage: if a FunctionExpression is passed
        // as a named argument, it IS a callback by definition
        final parent = node.parent;
        if (parent is NamedExpression) {
          // Named argument with function value = callback
          return CallbackNode(parent.name.label.name);
        }
        // Also handle positional callbacks (e.g., .then(() => ...))
        if (parent is ArgumentList) {
          // Check if this is a method like .then(), .catchError(), etc.
          final grandparent = parent.parent;
          if (grandparent is MethodInvocation) {
            final methodName = grandparent.methodName.name;
            // Common async callback methods
            if (const {'then', 'catchError', 'whenComplete', 'map', 'forEach'}
                .contains(methodName)) {
              return CallbackNode(methodName);
            }
          }
        }
        return null;

      case InstanceCreationExpression():
        final typeName = node.constructorName.type.name2.lexeme;
        // Only include widget instantiations
        if (_isWidgetType(typeName)) {
          return WidgetNode(typeName);
        }
        return null;

      case IfStatement():
        final condition = _extractConditionSummary(node.expression);
        return ControlFlowNode('if', condition: condition);

      case ForStatement():
        return ControlFlowNode('for');

      case ForElement():
        return ControlFlowNode('for');

      case WhileStatement():
        final condition = _extractConditionSummary(node.condition);
        return ControlFlowNode('while', condition: condition);

      case SwitchStatement():
        final expr = node.expression;
        final exprStr = expr is SimpleIdentifier ? expr.name : 'switch';
        return ControlFlowNode('switch', condition: exprStr);

      case SwitchExpression():
        return ControlFlowNode('switch');

      case ConditionalExpression():
        // Ternary operator - only include if it's significant
        return null;

      default:
        return null;
    }
  }

  /// Check if a class is a widget (from SCIP type hierarchy).
  bool _isWidgetClass(ClassDeclaration node) {
    final className = node.name.lexeme;
    return _widgetClasses.contains(className);
  }

  /// Check if a type name is a widget (from SCIP type hierarchy).
  bool _isWidgetType(String name) {
    return _widgetClasses.contains(name);
  }

  /// Check if a method name is generic (build, initState, etc.).
  bool _isGenericMethod(String name) {
    const generic = {
      'build',
      'initState',
      'dispose',
      'didChangeDependencies',
      'didUpdateWidget',
      'createState',
    };
    return generic.contains(name);
  }

  /// Extract the full condition expression as source code.
  String? _extractConditionSummary(Expression expr) {
    // Get the full source of the condition
    final source = expr.toSource();

    // If it's too long, we could truncate, but user wants full condition
    // Just clean up any newlines/extra spaces
    return source.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Clear the parse cache.
  void clearCache() {
    _parseCache.clear();
  }
}

/// Cached parse result with line info.
class _ParsedFile {
  _ParsedFile(this.unit, this.lineInfo);
  final CompilationUnit unit;
  final LineInfo lineInfo;
}

/// Visitor to find the innermost node at a specific byte offset.
class _NodeAtOffsetVisitor extends GeneralizingAstVisitor<void> {
  _NodeAtOffsetVisitor(this.targetOffset);

  final int targetOffset;
  AstNode? foundNode;

  @override
  void visitNode(AstNode node) {
    // Check if this node contains the target offset
    if (node.offset <= targetOffset && node.end >= targetOffset) {
      // This node contains the target offset
      // Keep drilling down to find the most specific node
      foundNode = node;
      super.visitNode(node);
    }
  }
}

/// Format a chain of nodes into a readable string.
String formatChain(List<ChainNode> chain, {String separator = ' → '}) {
  if (chain.isEmpty) return 'navigate';

  // Filter out redundant nodes and format
  final filtered = <String>[];

  for (final node in chain) {
    final name = node.displayName;

    // Skip duplicates
    if (filtered.isNotEmpty && filtered.last == name) continue;

    // Skip certain generic nodes
    if (node is ControlFlowNode && node.condition == null) continue;

    filtered.add(name);
  }

  if (filtered.isEmpty) return 'navigate';

  // Truncate very long chains
  if (filtered.length > 5) {
    return '${filtered.take(2).join(separator)} → ... → ${filtered.skip(filtered.length - 2).join(separator)}';
  }

  return filtered.join(separator);
}
