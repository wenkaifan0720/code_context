import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../services/product_service.dart';
import '../widgets/product_card.dart';

/// Page displaying a list of products.
///
/// Shows a grid of products that can be tapped to view details.
class ProductListPage extends StatefulWidget {
  const ProductListPage({super.key});

  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductService>().loadProducts();
    });
  }

  void _onProductTap(Product product) {
    context.go('/products/${product.id}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: Consumer<ProductService>(
        builder: (context, productService, _) {
          if (productService.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (productService.error != null) {
            return Center(child: Text('Error: ${productService.error}'));
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.75,
            ),
            itemCount: productService.products.length,
            itemBuilder: (context, index) {
              final product = productService.products[index];
              return ProductCard(
                product: product,
                onTap: () => _onProductTap(product),
              );
            },
          );
        },
      ),
    );
  }
}
