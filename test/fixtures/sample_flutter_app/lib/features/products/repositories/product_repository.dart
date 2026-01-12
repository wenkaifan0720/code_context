import '../../../core/api_client.dart';
import '../models/product.dart';

/// Repository for product data access.
///
/// Fetches product data from the API and handles caching.
class ProductRepository {
  ProductRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Fetch all products from the catalog.
  Future<List<Product>> getProducts() async {
    final response = await _apiClient.get('/products');
    final products = response['items'] as List;
    return products.map((p) => Product.fromJson(p)).toList();
  }

  /// Fetch a single product by ID.
  Future<Product> getProduct(String id) async {
    final response = await _apiClient.get('/products/$id');
    return Product.fromJson(response);
  }

  /// Search products by query string.
  Future<List<Product>> searchProducts(String query) async {
    final response = await _apiClient.get('/products/search?q=$query');
    final products = response['items'] as List;
    return products.map((p) => Product.fromJson(p)).toList();
  }

  /// Get products by category.
  Future<List<Product>> getProductsByCategory(String category) async {
    final response = await _apiClient.get('/products?category=$category');
    final products = response['items'] as List;
    return products.map((p) => Product.fromJson(p)).toList();
  }
}
