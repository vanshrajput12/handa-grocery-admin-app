import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../models/product_model.dart';
import '../../../services/product_service.dart';
import 'products_state.dart';

class ProductsCubit extends Cubit<ProductsState> {
  ProductsCubit(this._service) : super(const ProductsState()) {
    start();
  }

  final ProductService _service;
  final Map<String, List<ProductModel>> _byCategory = {};
  final Map<String, StreamSubscription<List<ProductModel>>> _productSubs = {};
  StreamSubscription<List<String>>? _categorySub;
  List<String> _categories = [];

  static const _reserved = {'users', 'categories'};

  /// Starts (or restarts) the live streams. Also used by the Retry button.
  void start() {
    _cancelAll();
    emit(const ProductsState());

    _categorySub = _service.watchCategories().listen(
          (categories) {
        _categories = categories;

        // Stop listening to deleted categories
        for (final c in _productSubs.keys
            .where((c) => !categories.contains(c))
            .toList()) {
          _productSubs.remove(c)?.cancel();
          _byCategory.remove(c);
        }

        // Start listening to new categories
        for (final c in categories) {
          if (_productSubs.containsKey(c)) continue;
          _productSubs[c] = _service.watchCategory(c).listen(
                (list) {
              _byCategory[c] = list;
              _publish();
            },
            onError: _onLoadError,
          );
        }

        _publish();
      },
      onError: _onLoadError,
    );
  }

  void _publish() {
    // Wait until every category has delivered its first result
    if (!_categories.every(_byCategory.containsKey)) return;

    final merged = <ProductModel>[
      for (final c in _categories) ...?_byCategory[c],
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final filterGone =
        state.category != null && !_categories.contains(state.category);

    emit(state.copyWith(
      loadStatus: ProductsLoadStatus.loaded,
      categories: _categories,
      products: merged,
      clearCategory: filterGone,
      clearError: true,
    ));
  }

  void _onLoadError(Object e) => emit(state.copyWith(
    loadStatus: ProductsLoadStatus.error,
    errorMessage: _loadMessage(e),
  ));

  void setQuery(String query) => emit(state.copyWith(query: query));

  void setCategory(String? category) {
    emit(category == null
        ? state.copyWith(clearCategory: true)
        : state.copyWith(category: category));
  }

  /// Returns the category name to use: an existing one (any capitalisation)
  /// or the cleaned new name. Throws FormatException for invalid names.
  String _resolveCategory(String input) {
    final name = input.trim();
    if (name.isEmpty) throw const FormatException('Please enter a category.');
    if (name.contains('/')) {
      throw const FormatException('Category name cannot contain "/".');
    }
    if (_reserved.contains(name.toLowerCase())) {
      throw const FormatException('That category name is reserved.');
    }
    for (final c in state.categories) {
      if (c.toLowerCase() == name.toLowerCase()) return c;
    }
    return name;
  }

  /// Adds a product, or updates [existing] with the fields in [data].
  /// A brand-new category is created automatically.
  Future<bool> save({
    ProductModel? existing,
    required String category,
    required Map<String, dynamic> data,
  }) async {
    try {
      if (existing == null) {
        final name = _resolveCategory(category);
        final isNew = !state.categories.contains(name);
        if (isNew) await _service.addCategory(name);
        await _service.addProduct(category: name, data: data);
        _notice(isNew
            ? 'Product added in new category "$name". It is live in the app.'
            : 'Product added. It is now live in the customer app.');
      } else {
        await _service.updateProduct(product: existing, changes: data);
        _notice('Product updated.');
      }
      return true;
    } on FormatException catch (e) {
      _notice(e.message, isError: true);
      return false;
    } catch (e) {
      _notice(_actionMessage(e), isError: true);
      return false;
    }
  }

  Future<void> delete(ProductModel product) async {
    try {
      await _service.deleteProduct(product);
      _notice('"${product.name}" was deleted.');
    } catch (e) {
      _notice(_actionMessage(e), isError: true);
    }
  }

  void _notice(String message, {bool isError = false}) {
    emit(state.copyWith(
      notice: message,
      noticeIsError: isError,
      noticeSeq: state.noticeSeq + 1,
    ));
  }

  String _loadMessage(Object e) {
    if (e is FirebaseException) {
      if (e.code == 'permission-denied') {
        return 'Permission denied. Sign out and sign in again, then check '
            'the Firestore rules for categories and product collections.';
      }
      if (e.code == 'unavailable') {
        return 'Cannot reach Firestore. Check your internet connection.';
      }
    }
    return 'Could not load products. Please try again.';
  }

  String _actionMessage(Object e) {
    if (e is FirebaseException && e.code == 'permission-denied') {
      return 'You are not allowed to change products. Sign out and sign in '
          'again, then retry.';
    }
    return 'Could not save the change. Please try again.';
  }

  void _cancelAll() {
    _categorySub?.cancel();
    _categorySub = null;
    for (final s in _productSubs.values) {
      s.cancel();
    }
    _productSubs.clear();
    _byCategory.clear();
    _categories = [];
  }

  @override
  Future<void> close() {
    _cancelAll();
    return super.close();
  }
}