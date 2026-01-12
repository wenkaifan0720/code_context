/// Product model representing an item in the catalog.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    this.imageUrl,
    this.category,
  });

  /// Unique product identifier.
  final String id;

  /// Product display name.
  final String name;

  /// Detailed product description.
  final String description;

  /// Price in cents.
  final int price;

  /// Optional product image URL.
  final String? imageUrl;

  /// Product category for filtering.
  final String? category;

  /// Format price as currency string.
  String get formattedPrice => '\$${(price / 100).toStringAsFixed(2)}';

  /// Create a Product from JSON data.
  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      price: json['price'] as int,
      imageUrl: json['imageUrl'] as String?,
      category: json['category'] as String?,
    );
  }
}
