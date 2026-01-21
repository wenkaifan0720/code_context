import 'dart:io';

import 'package:code_context/code_context.dart';
import 'package:scip_server/scip_server.dart';
import 'package:test/test.dart';

void main() {
  group('ScipServer', () {
    late ScipServer server;
    late Directory tempDir;

    setUp(() async {
      server = ScipServer();
      server.registerBinding(DartBinding());

      tempDir = await Directory.systemTemp.createTemp('scip_server_test_');

      // Create a minimal Dart project
      final libDir = Directory('${tempDir.path}/lib');
      await libDir.create();

      final dartToolDir = Directory('${tempDir.path}/.dart_tool');
      await dartToolDir.create();

      await File('${tempDir.path}/pubspec.yaml').writeAsString('''
name: test_project
environment:
  sdk: ^3.0.0
''');

      // Create minimal package_config.json
      await File('${dartToolDir.path}/package_config.json').writeAsString('''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "test_project",
      "rootUri": "../",
      "packageUri": "lib/"
    }
  ]
}
''');

      await File('${libDir.path}/example.dart').writeAsString('''
class ExampleService {
  void doSomething() {
    print('doing something');
  }
  
  String getValue() => 'value';
}

void main() {
  final service = ExampleService();
  service.doSomething();
}
''');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('registerBinding adds language', () {
      expect(server.availableLanguages, contains('dart'));
    });

    test('handleRequest returns error for uninitialized sql query', () async {
      final request = JsonRpcRequest(
        id: 1,
        method: ScipMethod.sql,
        params: {'query': 'SELECT COUNT(*) FROM symbols'},
      );

      final response = await server.handleRequest(request);

      expect(response, isNotNull);
      expect(response!.result['success'], isFalse);
      expect(response.result['error'], contains('not initialized'));
    });

    test('initialize creates index', () async {
      final request = JsonRpcRequest(
        id: 1,
        method: ScipMethod.initialize,
        params: {
          'rootPath': tempDir.path,
          'languageId': 'dart',
        },
      );

      final response = await server.handleRequest(request);

      expect(response, isNotNull);
      // Debug output
      if (response!.result['success'] != true) {
        print('Initialize failed: ${response.result['message']}');
      }
      expect(response.result['success'], isTrue,
          reason: response.result['message'] ?? 'no message');
      expect(response.result['projectName'], isNotEmpty);
      expect(response.result['fileCount'], greaterThanOrEqualTo(0));
      expect(response.result['symbolCount'], greaterThanOrEqualTo(0));
    });

    test('status returns index info after initialize', () async {
      // Initialize first
      await server.handleRequest(JsonRpcRequest(
        id: 1,
        method: ScipMethod.initialize,
        params: {
          'rootPath': tempDir.path,
          'languageId': 'dart',
        },
      ));

      // Now check status
      final response = await server.handleRequest(JsonRpcRequest(
        id: 2,
        method: ScipMethod.status,
      ));

      expect(response, isNotNull);
      expect(response!.result['initialized'], isTrue);
      expect(response.result['languageId'], 'dart');
      expect(response.result['fileCount'], greaterThan(0));
    });

    test('sql query executes after initialize', () async {
      // Initialize
      await server.handleRequest(JsonRpcRequest(
        id: 1,
        method: ScipMethod.initialize,
        params: {
          'rootPath': tempDir.path,
          'languageId': 'dart',
        },
      ));

      // SQL query for symbols
      final response = await server.handleRequest(JsonRpcRequest(
        id: 2,
        method: ScipMethod.sql,
        params: {'sql': "SELECT name FROM symbols WHERE name = 'ExampleService'"},
      ));

      expect(response, isNotNull);
      expect(response!.result['success'], isTrue);
      expect(response.result['result'], contains('ExampleService'));
    });

    test('sql query with json format returns structured data', () async {
      // Initialize
      await server.handleRequest(JsonRpcRequest(
        id: 1,
        method: ScipMethod.initialize,
        params: {
          'rootPath': tempDir.path,
          'languageId': 'dart',
        },
      ));

      // SQL query with JSON format
      final response = await server.handleRequest(JsonRpcRequest(
        id: 2,
        method: ScipMethod.sql,
        params: {
          'sql': 'SELECT name, kind FROM symbols LIMIT 5',
          'format': 'json',
        },
      ));

      expect(response, isNotNull);
      expect(response!.result['success'], isTrue);
      expect(response.result['result'], isA<Map>());
    });

    test('shutdown cleans up', () async {
      // Initialize
      await server.handleRequest(JsonRpcRequest(
        id: 1,
        method: ScipMethod.initialize,
        params: {
          'rootPath': tempDir.path,
          'languageId': 'dart',
        },
      ));

      expect(server.isInitialized, isTrue);

      // Shutdown
      final response = await server.handleRequest(JsonRpcRequest(
        id: 2,
        method: ScipMethod.shutdown,
      ));

      expect(response, isNotNull);
      expect(response!.result['success'], isTrue);
      expect(server.isInitialized, isFalse);
    });

    test('sql query returns empty when symbol not found', () async {
      // Initialize
      await server.handleRequest(JsonRpcRequest(
        id: 1,
        method: ScipMethod.initialize,
        params: {
          'rootPath': tempDir.path,
          'languageId': 'dart',
        },
      ));

      // Search for non-existent symbol
      final response = await server.handleRequest(JsonRpcRequest(
        id: 2,
        method: ScipMethod.sql,
        params: {'sql': "SELECT name FROM symbols WHERE name = 'NonExistentClass'"},
      ));

      expect(response, isNotNull);
      expect(response!.result['success'], isTrue);
      // Result should be empty (0 rows)
      expect(response.result['result'], contains('(0 rows)'));
    });

    test('initialize with unknown language returns error', () async {
      final response = await server.handleRequest(JsonRpcRequest(
        id: 1,
        method: ScipMethod.initialize,
        params: {
          'rootPath': tempDir.path,
          'languageId': 'python',
        },
      ));

      expect(response, isNotNull);
      expect(response!.result['success'], isFalse);
      expect(response.result['message'], contains('Unknown language'));
    });

    test('unknown method returns error', () async {
      final request = JsonRpcRequest(
        id: 1,
        method: 'unknown/method',
        params: {},
      );

      final response = await server.handleRequest(request);

      expect(response, isNotNull);
      expect(response!.error, isNotNull);
      expect(response.error!.code, JsonRpcError.methodNotFound);
    });

    test('notification does not return response', () async {
      // Initialize first
      await server.handleRequest(JsonRpcRequest(
        id: 1,
        method: ScipMethod.initialize,
        params: {
          'rootPath': tempDir.path,
          'languageId': 'dart',
        },
      ));

      // Notification (no id)
      final response = await server.handleRequest(JsonRpcRequest(
        method: ScipMethod.didChangeFile,
        params: {'path': '${tempDir.path}/lib/example.dart'},
      ));

      expect(response, isNull); // Notifications don't get responses
    });
  });

  group('JsonRpcRequest', () {
    test('fromJson parses request', () {
      final json = {
        'jsonrpc': '2.0',
        'method': 'query',
        'params': {'query': 'def Foo'},
        'id': 1,
      };

      final request = JsonRpcRequest.fromJson(json);

      expect(request.method, 'query');
      expect(request.params['query'], 'def Foo');
      expect(request.id, 1);
      expect(request.isNotification, isFalse);
    });

    test('fromJson parses notification', () {
      final json = {
        'jsonrpc': '2.0',
        'method': 'file/didChange',
        'params': {'path': 'lib/foo.dart'},
      };

      final request = JsonRpcRequest.fromJson(json);

      expect(request.method, 'file/didChange');
      expect(request.id, isNull);
      expect(request.isNotification, isTrue);
    });

    test('toJson serializes correctly', () {
      final request = JsonRpcRequest(
        id: 42,
        method: 'query',
        params: {'query': 'stats'},
      );

      final json = request.toJson();

      expect(json['jsonrpc'], '2.0');
      expect(json['method'], 'query');
      expect(json['id'], 42);
      expect(json['params'], {'query': 'stats'});
    });
  });

  group('JsonRpcResponse', () {
    test('toJson with result', () {
      final response = JsonRpcResponse(
        id: 1,
        result: {'success': true},
      );

      final json = response.toJson();

      expect(json['jsonrpc'], '2.0');
      expect(json['id'], 1);
      expect(json['result'], {'success': true});
      expect(json.containsKey('error'), isFalse);
    });

    test('toJson with error', () {
      final response = JsonRpcResponse(
        id: 1,
        error: JsonRpcError(
          code: JsonRpcError.internalError,
          message: 'Something went wrong',
        ),
      );

      final json = response.toJson();

      expect(json['jsonrpc'], '2.0');
      expect(json['id'], 1);
      expect(json['error']['code'], JsonRpcError.internalError);
      expect(json['error']['message'], 'Something went wrong');
      expect(json.containsKey('result'), isFalse);
    });
  });
}

