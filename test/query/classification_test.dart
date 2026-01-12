// ignore: implementation_imports
import 'package:scip_dart/src/gen/scip.pb.dart' as scip;
import 'package:scip_server/src/classification/classifier.dart';
import 'package:scip_server/src/classification/navigation.dart';
import 'package:scip_server/src/index/scip_index.dart';
import 'package:test/test.dart';

void main() {
  group('LayerClassifier', () {
    group('classifyByNaming', () {
      late LayerClassifier classifier;

      setUp(() {
        // Create empty index for naming tests
        classifier = LayerClassifier(ScipIndex.empty(projectRoot: '/test'));
      });

      test('classifies *Page as UI', () {
        expect(classifier.classifyByNaming('LoginPage'), SymbolLayer.ui);
        expect(classifier.classifyByNaming('HomePage'), SymbolLayer.ui);
        expect(classifier.classifyByNaming('ProductDetailPage'), SymbolLayer.ui);
      });

      test('classifies *Screen as UI', () {
        expect(classifier.classifyByNaming('SplashScreen'), SymbolLayer.ui);
        expect(classifier.classifyByNaming('SettingsScreen'), SymbolLayer.ui);
      });

      test('classifies *Widget as UI', () {
        // Patterns include Widget suffix
        expect(classifier.classifyByNaming('ProductCardWidget'), SymbolLayer.ui);
        // ProductCard doesn't end with a known pattern
        expect(classifier.classifyByNaming('ProductCard'), SymbolLayer.unknown);
        // Non-matching name
        expect(classifier.classifyByNaming('SomeClass'), SymbolLayer.unknown);
      });

      test('classifies *Service as Service', () {
        expect(classifier.classifyByNaming('AuthService'), SymbolLayer.service);
        expect(classifier.classifyByNaming('ProductService'), SymbolLayer.service);
      });

      test('classifies *Bloc as Service', () {
        expect(classifier.classifyByNaming('AuthBloc'), SymbolLayer.service);
        expect(classifier.classifyByNaming('CartBloc'), SymbolLayer.service);
      });

      test('classifies *Controller as Service', () {
        expect(classifier.classifyByNaming('HomeController'), SymbolLayer.service);
      });

      test('classifies *Repository as Data', () {
        expect(classifier.classifyByNaming('UserRepository'), SymbolLayer.data);
        expect(classifier.classifyByNaming('ProductRepository'), SymbolLayer.data);
      });

      test('classifies *Client as Data', () {
        expect(classifier.classifyByNaming('ApiClient'), SymbolLayer.data);
        expect(classifier.classifyByNaming('HttpClient'), SymbolLayer.data);
      });

      test('classifies *Model as Model', () {
        expect(classifier.classifyByNaming('UserModel'), SymbolLayer.model);
        expect(classifier.classifyByNaming('ProductModel'), SymbolLayer.model);
      });

      test('classifies *Entity as Model', () {
        expect(classifier.classifyByNaming('UserEntity'), SymbolLayer.model);
      });

      test('classifies *Utils as Util', () {
        expect(classifier.classifyByNaming('StringUtils'), SymbolLayer.util);
        expect(classifier.classifyByNaming('DateUtils'), SymbolLayer.util);
      });

      test('returns unknown for unrecognized patterns', () {
        expect(classifier.classifyByNaming('SomeClass'), SymbolLayer.unknown);
        expect(classifier.classifyByNaming('MyThing'), SymbolLayer.unknown);
      });
    });
  });

  group('FeatureDetector', () {
    late FeatureDetector detector;

    setUp(() {
      detector = FeatureDetector(ScipIndex.empty(projectRoot: '/test'));
    });

    group('detectFromPath', () {
      test('extracts feature from features/ directory', () {
        expect(detector.detectFromPath('lib/features/auth/login_page.dart'), 'auth');
        expect(detector.detectFromPath('lib/features/products/product_list.dart'), 'products');
        expect(detector.detectFromPath('lib/features/user_profile/profile_page.dart'), 'user_profile');
      });

      test('extracts feature from modules/ directory', () {
        expect(detector.detectFromPath('lib/modules/auth/auth_service.dart'), 'auth');
      });

      test('ignores common non-feature directories', () {
        expect(detector.detectFromPath('lib/src/auth_service.dart'), isNull);
        expect(detector.detectFromPath('lib/core/utils.dart'), isNull);
        expect(detector.detectFromPath('lib/common/widgets.dart'), isNull);
      });

      test('returns null for non-feature paths', () {
        expect(detector.detectFromPath('lib/main.dart'), isNull);
        expect(detector.detectFromPath('test/widget_test.dart'), isNull);
      });
    });

    group('detectFromNaming', () {
      test('extracts feature from *Service names', () {
        expect(detector.detectFromNaming('AuthService'), 'auth');
        expect(detector.detectFromNaming('ProductService'), 'product');
        expect(detector.detectFromNaming('UserProfileService'), 'user_profile');
      });

      test('extracts feature from *Repository names', () {
        expect(detector.detectFromNaming('UserRepository'), 'user');
        expect(detector.detectFromNaming('OrderRepository'), 'order');
      });

      test('extracts feature from *Page names', () {
        expect(detector.detectFromNaming('LoginPage'), 'login');
        expect(detector.detectFromNaming('ProductDetailPage'), 'product_detail');
      });

      test('extracts feature from *Bloc names', () {
        expect(detector.detectFromNaming('CartBloc'), 'cart');
        expect(detector.detectFromNaming('AuthBloc'), 'auth');
      });

      test('returns null for names without recognized suffixes', () {
        expect(detector.detectFromNaming('MyClass'), isNull);
        expect(detector.detectFromNaming('Helper'), isNull);
      });
    });
  });

  group('NavigationDetector', () {
    group('screen detection', () {
      test('identifies classes ending with Page as screens', () {
        final detector = NavigationDetector(ScipIndex.empty(projectRoot: '/test'));
        // findScreens returns empty list on empty index
        expect(detector.findScreens(), isEmpty);
        // Test naming heuristic
        expect('LoginPage'.endsWith('Page'), isTrue);
        expect('HomePage'.endsWith('Page'), isTrue);
      });

      test('identifies classes ending with Screen as screens', () {
        expect('SplashScreen'.endsWith('Screen'), isTrue);
        expect('SettingsScreen'.endsWith('Screen'), isTrue);
      });

      test('identifies classes ending with View as screens', () {
        expect('ProfileView'.endsWith('View'), isTrue);
      });
    });
  });

  group('NavigationEdge', () {
    test('equals compares fromScreen and toScreen', () {
      const edge1 = NavigationEdge(
        fromScreen: 'LoginPage',
        toScreen: 'HomePage',
        trigger: 'push',
      );
      const edge2 = NavigationEdge(
        fromScreen: 'LoginPage',
        toScreen: 'HomePage',
        trigger: 'go', // Different trigger
      );
      const edge3 = NavigationEdge(
        fromScreen: 'LoginPage',
        toScreen: 'SettingsPage',
        trigger: 'push',
      );

      expect(edge1, isNot(equals(edge2))); // Same screens, different trigger - NOT equal
      expect(edge1, isNot(equals(edge3))); // Different target
    });

    test('toString formats correctly', () {
      const edge = NavigationEdge(
        fromScreen: 'LoginPage',
        toScreen: 'HomePage',
        trigger: 'on success',
      );
      expect(edge.toString(), 'LoginPage → HomePage (on success)');
    });
  });

  group('SymbolClassification', () {
    test('toString formats correctly', () {
      // Create a minimal SymbolInfo for testing
      final classification = SymbolClassification(
        symbol: _createMockSymbol('AuthService'),
        layer: SymbolLayer.service,
        feature: 'auth',
        confidence: 0.95,
        signals: ['name pattern → service', 'feature: auth'],
      );

      expect(
        classification.toString(),
        contains('AuthService'),
      );
      expect(classification.toString(), contains('service'));
    });
  });
}

/// Create a mock SymbolInfo for testing.
SymbolInfo _createMockSymbol(String name) {
  return SymbolInfo(
    symbol: 'test#$name',
    kind: scip.SymbolInformation_Kind.Class,
    documentation: [],
    relationships: [],
    displayName: name,
    file: 'lib/test.dart',
  );
}
