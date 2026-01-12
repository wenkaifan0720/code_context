import 'package:flutter/foundation.dart';

import '../models/product.dart';
import '../repositories/product_repository.dart';

/// Service layer for product business logic.
///
/// Manages product state and provides product data to the UI.
class ProductService extends ChangeNotifier {
  ProductService(this._productRepository);

  final ProductRepository _productRepository;

  List<Product> _products = [];
  Product? _selectedProduct;
  bool _isLoading = false;
  String? _error;

  /// List of all products.
  List<Product> get products => _products;

  /// Currently selected product for detail view.
  Product? get selectedProduct => _selectedProduct;

  /// Whether products are being loaded.
  bool get isLoading => _isLoading;

  /// Error message from the last failed operation.
  String? get error => _error;

  /// Load all products from the repository.
  Future<void> loadProducts() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _products = await _productRepository.getProducts();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load a specific product by ID.
  Future<void> loadProduct(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _selectedProduct = await _productRepository.getProduct(id);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Search products by query.
  Future<void> searchProducts(String query) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _products = await _productRepository.searchProducts(query);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
