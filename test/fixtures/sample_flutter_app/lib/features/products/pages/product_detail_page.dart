import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/product_service.dart';

/// Page displaying detailed product information.
///
/// Shows product image, description, price, and add to cart button.
class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({
    super.key,
    required this.productId,
  });

  final String productId;

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductService>().loadProduct(widget.productId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/products'),
        ),
      ),
      body: Consumer<ProductService>(
        builder: (context, productService, _) {
          if (productService.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final product = productService.selectedProduct;
          if (product == null) {
            return const Center(child: Text('Product not found'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (product.imageUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      product.imageUrl!,
                      height: 300,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  product.name,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  product.formattedPrice,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                Text(
                  product.description,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      // TODO: Add to cart functionality
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Added to cart!')),
                      );
                    },
                    child: const Text('Add to Cart'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
