import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';

/// Categories that always show as chips (your existing collections).
/// Any category saved from the form is also written to `categories/{name}`
/// and appears automatically.
const _defaultCategories = ['Rice', 'Snacks'];

typedef _Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

String _nameOf(Map<String, dynamic> d) =>
    (d['name'] ?? d['text'] ?? '').toString();

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _db = FirebaseFirestore.instance;

  late final Stream<List<String>> _categoriesStream;
  String? _selected;
  String? _streamCategory;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _productsStream;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _categoriesStream = _db.collection('categories').snapshots().map((snap) {
      final names = <String>{..._defaultCategories};
      for (final d in snap.docs) {
        final n = (d.data()['name'] ?? d.id).toString().trim();
        if (n.isNotEmpty) names.add(n);
      }
      return names.toList()..sort();
    });
  }

  void _useCategory(String category) {
    if (_streamCategory != category) {
      _streamCategory = category;
      _productsStream = _db.collection(category).snapshots();
    }
  }

  Future<void> _openForm(List<String> categories, {_Doc? doc}) async {
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 580),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _ProductForm(
        categories: categories,
        initialCategory: _selected ?? categories.first,
        doc: doc,
      ),
    );
    if (saved != null && mounted) {
      setState(() {
        _selected = saved;
        _useCategory(saved);
      });
    }
  }

  Future<void> _delete(_Doc doc) async {
    final name = _nameOf(doc.data());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text(
          '"$name" will be removed from the store and the customer app.',
          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.mutedText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(100, 42),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await doc.reference.delete();
      if (mounted) _toast('Product deleted');
    } catch (e) {
      if (mounted) _toast('Could not delete: $e', error: true);
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: error ? AppColors.error : AppColors.deepGreen,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: _categoriesStream,
      builder: (context, catSnap) {
        final categories = catSnap.data ?? _defaultCategories;
        if (_selected == null || !categories.contains(_selected)) {
          _selected = categories.first;
        }
        _useCategory(_selected!);

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(onAdd: () => _openForm(categories)),
              const SizedBox(height: 18),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final name = categories[i];
                    final selected = name == _selected;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _selected = name;
                        _useCategory(name);
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? AppColors.green : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                            selected ? AppColors.green : AppColors.border,
                          ),
                        ),
                        child: Text(
                          name,
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color:
                            selected ? Colors.white : AppColors.darkText,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                onChanged: (v) => setState(() => _query = v.trim()),
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search in $_selected',
                  prefixIcon: const Icon(Icons.search_rounded),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(child: _buildProducts(categories)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProducts(List<String> categories) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _productsStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return _Message(
            icon: Icons.error_outline_rounded,
            title: 'Unable to load products',
            subtitle: '${snap.error}',
            color: AppColors.error,
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final all = snap.data!.docs.toList()
          ..sort((a, b) => _nameOf(a.data())
              .toLowerCase()
              .compareTo(_nameOf(b.data()).toLowerCase()));
        final q = _query.toLowerCase();
        final docs = q.isEmpty
            ? all
            : all
            .where((d) => _nameOf(d.data()).toLowerCase().contains(q))
            .toList();

        if (docs.isEmpty) {
          return _Message(
            icon: Icons.inventory_2_outlined,
            title: all.isEmpty
                ? 'No products in $_selected yet'
                : 'No matching products',
            subtitle: all.isEmpty
                ? 'Tap "Add product" to create the first one.'
                : 'Try a different search.',
            color: AppColors.green,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${docs.length} item${docs.length == 1 ? '' : 's'} in $_selected',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.mutedText,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.only(bottom: 28),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 560,
                  mainAxisExtent: 132,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                ),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final d = doc.data();
                  return _ProductCard(
                    name: _nameOf(d),
                    price: (d['price'] ?? '').toString(),
                    description: (d['description'] ?? '').toString(),
                    image: (d['image'] ?? '').toString(),
                    onEdit: () => _openForm(categories, doc: doc),
                    onDelete: () => _delete(doc),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ───────────────────────── Header ─────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 16, 20),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepGreen.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Products',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Add, edit and remove store items',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Add product'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Product card ─────────────────────────

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.name,
    required this.price,
    required this.description,
    required this.image,
    required this.onEdit,
    required this.onDelete,
  });

  final String name;
  final String price;
  final String description;
  final String image;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final shownPrice = price.isEmpty
        ? ''
        : (price.startsWith('₹') ? price : '₹$price');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepGreen.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          _Thumb(url: image, size: 100),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Untitled product' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description.isEmpty ? 'No description' : description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    height: 1.4,
                    color: AppColors.mutedText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  shownPrice,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.green,
                  ),
                ),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RoundIcon(
                icon: Icons.edit_outlined,
                color: AppColors.green,
                bg: AppColors.softGreen,
                tooltip: 'Edit',
                onTap: onEdit,
              ),
              const SizedBox(height: 10),
              _RoundIcon(
                icon: Icons.delete_outline_rounded,
                color: AppColors.mutedText,
                bg: AppColors.background,
                tooltip: 'Delete',
                onTap: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.color,
    required this.bg,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color bg;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 38,
            width: 38,
            child: Icon(icon, size: 19, color: color),
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.size});
  final String url;
  final double size;

  Widget _placeholder() => Container(
    color: AppColors.softGreen,
    child: const Center(
      child: Icon(Icons.image_outlined, color: AppColors.green, size: 30),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: size,
        width: size,
        child: url.startsWith('http')
            ? Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        )
            : _placeholder(),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 76,
              width: 76,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.darkText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: AppColors.mutedText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Add / Edit form ─────────────────────────

class _ProductForm extends StatefulWidget {
  const _ProductForm({
    required this.categories,
    required this.initialCategory,
    this.doc,
  });

  final List<String> categories;
  final String initialCategory;
  final _Doc? doc;

  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  static const _newKey = '__new__';

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _image;
  late final TextEditingController _desc;
  final _newCategory = TextEditingController();

  late String _category;
  bool _saving = false;

  bool get _isEdit => widget.doc != null;

  @override
  void initState() {
    super.initState();
    final d = widget.doc?.data() ?? <String, dynamic>{};
    _name = TextEditingController(text: _nameOf(d));
    _price = TextEditingController(text: (d['price'] ?? '').toString());
    _image = TextEditingController(text: (d['image'] ?? '').toString());
    _desc = TextEditingController(text: (d['description'] ?? '').toString());
    _category = widget.initialCategory;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _image.dispose();
    _desc.dispose();
    _newCategory.dispose();
    super.dispose();
  }

  Future<void> _pasteImageUrl() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is empty')),
      );
      return;
    }
    setState(() {
      _image.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
  }

  InputDecoration _dec(String label,
      {IconData? icon, String? hint, Widget? suffix}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
        labelStyle: GoogleFonts.poppins(fontSize: 13),
        filled: true,
        fillColor: AppColors.background,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final db = FirebaseFirestore.instance;
    final category =
    _category == _newKey ? _newCategory.text.trim() : _category;
    final name = _name.text.trim();

    final data = <String, dynamic>{
      // Written under both keys so the customer app works whichever it reads.
      'name': name,
      'text': name,
      'price': _price.text.trim(), // kept as String (customer app strips non-digits)
      'image': _image.text.trim(),
      'description': _desc.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (_isEdit) {
        await widget.doc!.reference.update(data);
      } else {
        await db
            .collection(category)
            .add({...data, 'createdAt': FieldValue.serverTimestamp()});
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Makes the category appear as a chip (admin + customer app).
    try {
      await db
          .collection('categories')
          .doc(category)
          .set({'name': category}, SetOptions(merge: true));
    } catch (_) {}

    if (!mounted) return;
    Navigator.pop(context, category);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isEdit ? 'Product updated' : 'Product added'),
        backgroundColor: AppColors.deepGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = {...widget.categories, if (_isEdit) _category}.toList();

    return Padding(
      padding:
      EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  height: 4,
                  width: 44,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _isEdit ? 'Edit product' : 'Add product',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkText,
                ),
              ),
              const SizedBox(height: 18),

              DropdownButtonFormField<String>(
                value: _category, // ignore: deprecated_member_use
                decoration: _dec('Category', icon: Icons.category_outlined),
                borderRadius: BorderRadius.circular(14),
                items: [
                  ...items.map(
                        (c) => DropdownMenuItem(value: c, child: Text(c)),
                  ),
                  if (!_isEdit)
                    const DropdownMenuItem(
                      value: _newKey,
                      child: Text('+ New category'),
                    ),
                ],
                onChanged: _isEdit
                    ? null
                    : (v) => setState(() => _category = v ?? _category),
              ),
              if (_category == _newKey) ...[
                const SizedBox(height: 14),
                TextFormField(
                  controller: _newCategory,
                  decoration: _dec('New category name',
                      icon: Icons.add_circle_outline_rounded,
                      hint: 'e.g. Dairy'),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'Enter a category name';
                    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9 _-]*$').hasMatch(t)) {
                      return 'Use letters, numbers, spaces, - or _';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 14),

              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration:
                _dec('Product name', icon: Icons.shopping_basket_outlined),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? 'Enter the product name'
                    : null,
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _price,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec('Price (₹)',
                    icon: Icons.currency_rupee_rounded, hint: 'e.g. 150'),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Enter the price';
                  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(t)) {
                    return 'Numbers only';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _image,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                enableInteractiveSelection: true,
                onChanged: (_) => setState(() {}),
                decoration: _dec(
                  'Image URL',
                  icon: Icons.image_outlined,
                  hint: 'https://...',
                  suffix: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_image.text.isNotEmpty)
                        IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => setState(_image.clear),
                        ),
                      IconButton(
                        tooltip: 'Paste',
                        icon: const Icon(Icons.content_paste_rounded,
                            size: 20, color: AppColors.green),
                        onPressed: _pasteImageUrl,
                      ),
                    ],
                  ),
                ),
              ),
              if (_image.text.trim().startsWith('http')) ...[
                const SizedBox(height: 12),
                Center(child: _Thumb(url: _image.text.trim(), size: 120)),
              ],
              const SizedBox(height: 14),

              TextFormField(
                controller: _desc,
                maxLines: 4,
                minLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: _dec('Description',
                    hint: 'Short description shown in the customer app'),
              ),
              const SizedBox(height: 22),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                      _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                          : Text(_isEdit ? 'Save changes' : 'Add product'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}