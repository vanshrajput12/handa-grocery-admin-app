import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/product_model.dart';

class ProductService {
  ProductService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Category names. The document ID is the collection name.
  Stream<List<String>> watchCategories() {
    return _db.collection('categories').snapshots().map((snap) {
      final docs = snap.docs.toList()
        ..sort((a, b) {
          final aT = a.data()['createdAt'] as Timestamp?;
          final bT = b.data()['createdAt'] as Timestamp?;
          return (aT?.millisecondsSinceEpoch ?? 0)
              .compareTo(bT?.millisecondsSinceEpoch ?? 0);
        });
      return docs.map((d) => d.id).toList();
    });
  }

  /// Registers a category so the customer app shows it automatically.
  Future<void> addCategory(String name) {
    return _db.collection('categories').doc(name).set({
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Live stream of one category (one Firestore collection).
  Stream<List<ProductModel>> watchCategory(String category) {
    return _db.collection(category).snapshots().map(
          (snap) =>
          snap.docs.map((d) => ProductModel.fromDoc(category, d)).toList(),
    );
  }

  Future<void> addProduct({
    required String category,
    required Map<String, dynamic> data,
  }) {
    return _db.collection(category).add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateProduct({
    required ProductModel product,
    required Map<String, dynamic> changes,
  }) {
    return _db.collection(product.category).doc(product.id).update({
      ...changes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteProduct(ProductModel product) {
    return _db.collection(product.category).doc(product.id).delete();
  }
}