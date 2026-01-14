import 'package:scip_server/src/query/query_result.dart';
import 'package:test/test.dart';

void main() {
  group('StoryboardResult', () {
    group('toText', () {
      test('generates mermaid diagram by default', () {
        const result = StoryboardResult(
          screens: [
            ScreenInfo(name: 'LoginPage', feature: 'auth'),
            ScreenInfo(name: 'HomePage', feature: 'main'),
            ScreenInfo(name: 'SettingsPage', feature: 'settings'),
          ],
          edges: [
            NavigationEdgeInfo(
              fromScreen: 'LoginPage',
              toScreen: 'HomePage',
              trigger: 'push',
            ),
            NavigationEdgeInfo(
              fromScreen: 'HomePage',
              toScreen: 'SettingsPage',
              trigger: 'push',
            ),
          ],
          routerType: 'navigator',
          entryScreen: 'LoginPage',
        );

        final text = result.toText();

        expect(text, contains('## Navigation Storyboard'));
        expect(text, contains('3 screens'));
        expect(text, contains('2 navigation edges'));
        expect(text, contains('Router: navigator'));
        expect(text, contains('Entry: LoginPage'));
        expect(text, contains('### Graph'));
        expect(text, contains('LoginPage'));
        expect(text, contains('HomePage'));
        expect(text, contains('SettingsPage'));
      });

      test('generates text diagram when format is ascii', () {
        const result = StoryboardResult(
          screens: [
            ScreenInfo(name: 'LoginPage'),
            ScreenInfo(name: 'HomePage'),
          ],
          edges: [
            NavigationEdgeInfo(
              fromScreen: 'LoginPage',
              toScreen: 'HomePage',
            ),
          ],
          routerType: 'navigator',
          format: 'ascii',
        );

        final text = result.toText();

        // toText now always generates the same format
        expect(text, contains('## Navigation Storyboard'));
        expect(text, contains('LoginPage'));
        expect(text, contains('HomePage'));
        expect(text, isNot(contains('```mermaid')));
      });

      test('handles empty screens', () {
        const result = StoryboardResult(
          screens: [],
          edges: [],
          routerType: 'unknown',
        );

        expect(result.isEmpty, isTrue);
        expect(result.toText(), contains('No screens found'));
      });
    });

    group('toJson', () {
      test('includes all fields', () {
        const result = StoryboardResult(
          screens: [
            ScreenInfo(name: 'LoginPage', feature: 'auth', file: 'lib/login.dart'),
          ],
          edges: [
            NavigationEdgeInfo(
              fromScreen: 'LoginPage',
              toScreen: 'HomePage',
              trigger: 'push',
              routePath: '/home',
            ),
          ],
          routerType: 'goRouter',
          entryScreen: 'LoginPage',
        );

        final json = result.toJson();

        // toJson now returns a DirectedGraph-compatible structure
        expect(json['nodes'], isA<List>());
        expect(json['edges'], isA<List>());
        expect(json['metadata'], isA<Map>());
        expect((json['nodes'] as List).length, 2); // LoginPage and HomePage
        expect((json['edges'] as List).length, 1);
      });
    });

    group('DirectedGraph-compatible JSON', () {
      test('includes nodes and edges when multiple features exist', () {
        const result = StoryboardResult(
          screens: [
            ScreenInfo(name: 'LoginPage', feature: 'auth'),
            ScreenInfo(name: 'SignupPage', feature: 'auth'),
            ScreenInfo(name: 'HomePage', feature: 'main'),
          ],
          edges: [
            NavigationEdgeInfo(fromScreen: 'LoginPage', toScreen: 'SignupPage'),
            NavigationEdgeInfo(fromScreen: 'LoginPage', toScreen: 'HomePage'),
          ],
          routerType: 'navigator',
        );

        final json = result.toJson();

        expect(json['nodes'], isA<List>());
        expect((json['nodes'] as List).length, 3);
        expect(json['edges'], isA<List>());
        expect((json['edges'] as List).length, 2);
      });

      test('includes edge metadata when present', () {
        const result = StoryboardResult(
          screens: [
            ScreenInfo(name: 'LoginPage'),
            ScreenInfo(name: 'HomePage'),
          ],
          edges: [
            NavigationEdgeInfo(
              fromScreen: 'LoginPage',
              toScreen: 'HomePage',
              label: 'on success',
            ),
          ],
          routerType: 'navigator',
        );

        final json = result.toJson();
        final edges = json['edges'] as List;
        expect(edges.length, 1);
        final edge = edges.first as Map<String, dynamic>;
        expect(edge['label'], 'on success');
      });

      test('handles special characters in node names', () {
        const result = StoryboardResult(
          screens: [
            ScreenInfo(name: 'Login-Page'),
            ScreenInfo(name: 'Home Page'),
          ],
          edges: [
            NavigationEdgeInfo(
              fromScreen: 'Login-Page',
              toScreen: 'Home Page',
            ),
          ],
          routerType: 'navigator',
        );

        final json = result.toJson();
        final nodes = json['nodes'] as List;

        // Node names are preserved as-is in the DirectedGraph format
        expect(nodes, contains('Home Page'));
        expect(nodes, contains('Login-Page'));
      });
    });
  });

  group('ClassifyResult', () {
    group('toText', () {
      test('groups symbols by layer', () {
        const result = ClassifyResult(
          classifications: [
            SymbolClassificationInfo(
              symbolId: 'test#LoginPage',
              name: 'LoginPage',
              layer: 'ui',
              feature: 'auth',
              confidence: 0.9,
              file: 'lib/login.dart',
            ),
            SymbolClassificationInfo(
              symbolId: 'test#AuthService',
              name: 'AuthService',
              layer: 'service',
              feature: 'auth',
              confidence: 0.85,
              file: 'lib/auth.dart',
            ),
            SymbolClassificationInfo(
              symbolId: 'test#UserRepository',
              name: 'UserRepository',
              layer: 'data',
              feature: 'user',
              confidence: 0.95,
              file: 'lib/user_repo.dart',
            ),
          ],
        );

        final text = result.toText();

        expect(text, contains('## Symbol Classification (3 symbols)'));
        expect(text, contains('### UI Layer'));
        expect(text, contains('### Service Layer'));
        expect(text, contains('### Data Layer'));
        expect(text, contains('LoginPage'));
        expect(text, contains('AuthService'));
        expect(text, contains('UserRepository'));
      });

      test('handles empty classifications', () {
        const result = ClassifyResult(classifications: []);

        expect(result.isEmpty, isTrue);
        expect(result.toText(), contains('No symbols found'));
      });

      test('shows symbols grouped by layer', () {
        const result = ClassifyResult(
          classifications: [
            SymbolClassificationInfo(
              symbolId: 'test#MyService',
              name: 'MyService',
              layer: 'service',
              feature: 'core',
              confidence: 0.8,
              file: 'lib/service.dart',
            ),
          ],
        );

        final text = result.toText();

        expect(text, contains('## Symbol Classification'));
        expect(text, contains('Service Layer'));
        expect(text, contains('- MyService [core]'));
        expect(text, contains('lib/service.dart'));
      });
    });

    group('toJson', () {
      test('includes all fields', () {
        const result = ClassifyResult(
          classifications: [
            SymbolClassificationInfo(
              symbolId: 'test#AuthService',
              name: 'AuthService',
              layer: 'service',
              feature: 'auth',
              confidence: 0.9,
              file: 'lib/auth.dart',
              signals: ['name pattern → service'],
            ),
          ],
          pattern: '*Service',
        );

        final json = result.toJson();

        expect(json['type'], 'classify');
        expect(json['count'], 1);
        expect(json['pattern'], '*Service');
        expect(json['classifications'], hasLength(1));
        
        final c = json['classifications'][0] as Map<String, dynamic>;
        expect(c['symbol'], 'test#AuthService');
        expect(c['name'], 'AuthService');
        expect(c['layer'], 'service');
        expect(c['feature'], 'auth');
        expect(c['confidence'], 0.9);
        expect(c['file'], 'lib/auth.dart');
        expect(c['signals'], contains('name pattern → service'));
      });
    });
  });
}
