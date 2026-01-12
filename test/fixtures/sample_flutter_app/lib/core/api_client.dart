/// HTTP client wrapper for API requests.
///
/// Provides a simple interface for making authenticated HTTP requests
/// to the backend API.
class ApiClient {
  ApiClient({
    this.baseUrl = 'https://api.example.com',
    this.authToken,
  });

  /// Base URL for all API requests.
  final String baseUrl;

  /// Optional authentication token for requests.
  String? authToken;

  /// Make a GET request to the specified endpoint.
  Future<Map<String, dynamic>> get(String endpoint) async {
    // Simulate API call
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Return mock data for demonstration
    if (endpoint.startsWith('/products/') && !endpoint.contains('search')) {
      final id = endpoint.split('/').last;
      return {
        'id': id,
        'name': 'Product $id',
        'description': 'A great product description for product $id.',
        'price': 2999,
        'imageUrl': 'https://picsum.photos/400/300?random=$id',
      };
    }
    
    if (endpoint == '/products' || endpoint.contains('search') || endpoint.contains('category')) {
      return {
        'items': List.generate(
          10,
          (i) => {
            'id': 'prod_$i',
            'name': 'Product $i',
            'description': 'Description for product $i',
            'price': 1999 + (i * 500),
            'imageUrl': 'https://picsum.photos/400/300?random=$i',
          },
        ),
      };
    }
    
    if (endpoint == '/auth/me') {
      return {
        'id': 'user_1',
        'email': 'user@example.com',
        'name': 'Demo User',
      };
    }
    
    throw Exception('Unknown endpoint: $endpoint');
  }

  /// Make a POST request to the specified endpoint.
  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    // Simulate API call
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (endpoint == '/auth/login') {
      return {
        'id': 'user_1',
        'email': data['email'],
        'name': 'Demo User',
      };
    }
    
    if (endpoint == '/auth/signup') {
      return {
        'id': 'user_new',
        'email': data['email'],
        'name': data['name'],
      };
    }
    
    if (endpoint == '/auth/logout') {
      return {};
    }
    
    throw Exception('Unknown endpoint: $endpoint');
  }
}
