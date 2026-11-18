import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';

/// Same defaults as the Products page (your existing collections).
const _defaultCategories = ['Rice', 'Snacks'];

// ───────────────────────── Data ─────────────────────────

enum _Status { inStock, low, out, notSet }

extension on _Status {
  String get label => switch (this) {
    _Status.inStock => 'In stock',
    _Status.low => 'Low stock',
    _Status.out => 'Out of stock',
    _Status.notSet => 'Not set',
  };

  Color get color => switch (this) {
    _Status.inStock => AppColors.green,
    _Status.low => AppColors.orange,
    _Status.out => AppColors.error,
    _Status.notSet => AppColors.mutedText,
  };

  /// Sort order: problems first.
  int get rank => switch (this) {
    _Status.out => 0,
    _Status.low => 1,
    _Status.notSet => 2,
    _Status.inStock => 3,
  };
}

class _Item {
  _Item({
    required this.ref,
    required this.category,
    required this.name,
    required this.image,
    required this.stock,
  });

  final DocumentReference<Map<String, dynamic>> ref;
  final String category;
  final String name;
  final String image;
  final int? stock; // null = stock was never set for this product

  factory _Item.from(
      String category,
      QueryDocumentSnapshot<Map<String, dynamic>> d,
      ) {
    final m = d.data();
    final raw = m['stock'];
    final stock = raw == null ? null : num.tryParse(raw.toString())?.toInt();
    return _Item(
      ref: d.reference,
      category: category,
      name: (m['name'] ?? m['text'] ?? '').toString(),
      image: (m['image'] ?? '').toString(),
      stock: stock,
    );
  }
}

// ───────────────────────── Page ─────────────────────────

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _db = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _catSub;
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _prodSubs = {};
  final Map<String, List<_Item>> _byCategory = {};
  final Map<String, String> _errors = {};
  final Set<String> _loaded = {};

  List<String> _categories = [..._defaultCategories];
  bool _catsReady = false;

  String _query = '';
  _Status? _statusFilter;
  String? _categoryFilter;
  int _threshold = 10;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Rules only allow reading a product collection if categories/{name}
    // exists, so make sure the default ones are there first.
    for (final c in _defaultCategories) {
      try {
        await _db
            .collection('categories')
            .doc(c)
            .set({'name': c}, SetOptions(merge: true));
      } catch (_) {}
    }
    if (!mounted) return;
    _catSub = _db.collection('categories').snapshots().listen(
      _onCategories,
      onError: (_) => _onCategories(null),
    );
  }

  void _onCategories(QuerySnapshot<Map<String, dynamic>>? snap) {
    final names = <String>{..._defaultCategories};
    if (snap != null) {
      for (final d in snap.docs) {
        final n = (d.data()['name'] ?? d.id).toString().trim();
        if (n.isNotEmpty && !n.contains('/')) names.add(n);
      }
    }
    final list = names.toList()..sort();

    for (final c in list) {
      if (_prodSubs.containsKey(c)) continue;
      _prodSubs[c] = _db.collection(c).snapshots().listen(
            (s) {
          if (!mounted) return;
          setState(() {
            _byCategory[c] = s.docs.map((d) => _Item.from(c, d)).toList();
            _errors.remove(c);
            _loaded.add(c);
          });
        },
        onError: (Object e) {
          if (!mounted) return;
          setState(() {
            _byCategory.remove(c);
            _errors[c] = '$e';
            _loaded.add(c);
          });
        },
      );
    }
    for (final c in _prodSubs.keys.toList()) {
      if (!list.contains(c)) {
        _prodSubs.remove(c)?.cancel();
        _byCategory.remove(c);
        _errors.remove(c);
        _loaded.remove(c);
      }
    }

    if (!mounted) return;
    setState(() {
      _categories = list;
      _catsReady = true;
      if (_categoryFilter != null && !list.contains(_categoryFilter)) {
        _categoryFilter = null;
      }
    });
  }

  @override
  void dispose() {
    _catSub?.cancel();
    for (final s in _prodSubs.values) {
      s.cancel();
    }
    super.dispose();
  }

  // ── helpers ──

  _Status _statusOf(_Item i) {
    final s = i.stock;
    if (s == null) return _Status.notSet;
    if (s <= 0) return _Status.out;
    if (s <= _threshold) return _Status.low;
    return _Status.inStock;
  }

  bool get _loading =>
      !_catsReady || _categories.any((c) => !_loaded.contains(c));

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

  Future<void> _write(_Item item, Map<String, dynamic> data) async {
    try {
      await item.ref
          .update({...data, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      if (mounted) _toast('Could not update stock: $e', error: true);
    }
  }

  Future<void> _adjust(_Item item, int delta) async {
    final cur = item.stock;
    if (cur == null) {
      if (delta > 0) await _write(item, {'stock': delta});
      return;
    }
    if (cur + delta < 0) return;
    await _write(item, {'stock': FieldValue.increment(delta)});
  }

  Future<void> _editStock(_Item item) async {
    final qty = await showDialog<int>(
      context: context,
      builder: (_) => _StockDialog(item: item),
    );
    if (qty != null) {
      await _write(item, {'stock': qty});
      if (mounted) _toast('${item.name}: stock set to $qty');
    }
  }

  Future<void> _editThreshold() async {
    final c = TextEditingController(text: '$_threshold');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Low-stock alert'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Items with this many units or fewer are marked "Low stock".',
              style: GoogleFonts.poppins(
                  fontSize: 12.5, color: AppColors.mutedText),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Alert at (units)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.green,
              minimumSize: const Size(90, 42),
            ),
            onPressed: () => Navigator.pop(ctx, int.tryParse(c.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    c.dispose();
    if (v != null && mounted) setState(() => _threshold = v);
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final all = _byCategory.values.expand((e) => e).toList();

    final counts = <_Status, int>{for (final s in _Status.values) s: 0};
    for (final i in all) {
      counts[_statusOf(i)] = counts[_statusOf(i)]! + 1;
    }

    final q = _query.toLowerCase();
    final shown = all.where((i) {
      if (_categoryFilter != null && i.category != _categoryFilter) {
        return false;
      }
      if (_statusFilter != null && _statusOf(i) != _statusFilter) return false;
      if (q.isNotEmpty && !i.name.toLowerCase().contains(q)) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        final r = _statusOf(a).rank.compareTo(_statusOf(b).rank);
        return r != 0
            ? r
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(threshold: _threshold, onThreshold: _editThreshold),
                const SizedBox(height: 18),
                _StatsRow(
                  total: all.length,
                  counts: counts,
                  active: _statusFilter,
                  onTap: (s) => setState(
                        () => _statusFilter = _statusFilter == s ? null : s,
                  ),
                ),
                const SizedBox(height: 18),
                _SearchField(onChanged: (v) => setState(() => _query = v)),
                const SizedBox(height: 12),
                _FilterChips(
                  active: _statusFilter,
                  total: all.length,
                  counts: counts,
                  onSelect: (s) => setState(() => _statusFilter = s),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _loading
                            ? 'Loading…'
                            : '${shown.length} product${shown.length == 1 ? '' : 's'}',
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.mutedText,
                        ),
                      ),
                    ),
                    _CategoryPicker(
                      value: _categoryFilter,
                      categories: _categories,
                      onChanged: (v) => setState(() => _categoryFilter = v),
                    ),
                  ],
                ),
                if (_errors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ErrorBanner(errors: _errors),
                ],
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        if (_loading && all.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (shown.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _Message(
              icon: Icons.inventory_2_outlined,
              title: all.isEmpty ? 'No products yet' : 'No matching products',
              subtitle: all.isEmpty
                  ? 'Add products from the Products section, then track their stock here.'
                  : 'Try a different search or filter.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 560,
                mainAxisExtent: 132,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              delegate: SliverChildBuilderDelegate(
                    (context, i) {
                  final item = shown[i];
                  return _StockCard(
                    key: ValueKey(item.ref.path),
                    item: item,
                    status: _statusOf(item),
                    onMinus: () => _adjust(item, -1),
                    onPlus: () => _adjust(item, 1),
                    onEdit: () => _editStock(item),
                  );
                },
                childCount: shown.length,
              ),
            ),
          ),
      ],
    );
  }
}

// ───────────────────────── Header & filters ─────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.threshold, required this.onThreshold});
  final int threshold;
  final VoidCallback onThreshold;

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
                  'Inventory',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Track stock levels and low-stock items',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: AppColors.orange,
            borderRadius: BorderRadius.circular(30),
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: onThreshold,
              child: Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.notifications_active_outlined,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      '≤ $threshold',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.total,
    required this.counts,
    required this.active,
    required this.onTap,
  });

  final int total;
  final Map<_Status, int> counts;
  final _Status? active;
  final ValueChanged<_Status> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 700 ? 4 : 2;
        final w = (c.maxWidth - (cols - 1) * 12) / cols;

        Widget stat(String label, int value, IconData icon, Color color,
            {_Status? status}) {
          final selected = status != null && status == active;
          return SizedBox(
            width: w,
            child: Material(
              color: selected ? color.withValues(alpha: 0.10) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: status == null ? null : () => onTap(status),
                child: Ink(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: selected ? color : AppColors.border,
                      width: selected ? 1.4 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        height: 40,
                        width: 40,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: color, size: 21),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$value',
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: AppColors.darkText,
                              ),
                            ),
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                color: AppColors.mutedText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            stat('Total products', total, Icons.inventory_2_outlined,
                AppColors.deepGreen),
            stat('In stock', counts[_Status.inStock]!,
                Icons.check_circle_outline_rounded, AppColors.green,
                status: _Status.inStock),
            stat('Low stock', counts[_Status.low]!,
                Icons.warning_amber_rounded, AppColors.orange,
                status: _Status.low),
            stat('Out of stock', counts[_Status.out]!,
                Icons.remove_shopping_cart_outlined, AppColors.error,
                status: _Status.out),
          ],
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search products',
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
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.active,
    required this.total,
    required this.counts,
    required this.onSelect,
  });

  final _Status? active;
  final int total;
  final Map<_Status, int> counts;
  final ValueChanged<_Status?> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool selected, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.green : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.green : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.darkText,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip('All ($total)', active == null, () => onSelect(null)),
          for (final s in _Status.values) ...[
            const SizedBox(width: 10),
            chip('${s.label} (${counts[s]})', active == s, () => onSelect(s)),
          ],
        ],
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({
    required this.value,
    required this.categories,
    required this.onChanged,
  });

  final String? value;
  final List<String> categories;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(14),
          dropdownColor: Colors.white,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.deepGreen),
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.deepGreen,
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All categories'),
            ),
            ...categories.map(
                  (c) => DropdownMenuItem<String?>(value: c, child: Text(c)),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.errors});
  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.softOrange,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppColors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Could not load: ${errors.keys.join(', ')}. '
                  'Check that each has a document in "categories" and that your '
                  'account has the admin claim.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                height: 1.5,
                color: AppColors.darkText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Stock card ─────────────────────────

class _StockCard extends StatelessWidget {
  const _StockCard({
    super.key,
    required this.item,
    required this.status,
    required this.onMinus,
    required this.onPlus,
    required this.onEdit,
  });

  final _Item item;
  final _Status status;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final stock = item.stock;

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
          _Thumb(url: item.image, size: 80),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name.isEmpty ? 'Untitled product' : item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkText,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          color: AppColors.mutedText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusPill(status),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _StepButton(
                      icon: Icons.remove_rounded,
                      onTap: (stock == null || stock <= 0) ? null : onMinus,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Material(
                        color: status.color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: onEdit,
                          child: Container(
                            height: 38,
                            alignment: Alignment.center,
                            child: Text(
                              stock?.toString() ?? 'Set',
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: status.color,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StepButton(
                      icon: Icons.add_rounded,
                      filled: true,
                      onTap: onPlus,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: filled
          ? (enabled ? AppColors.green : AppColors.border)
          : AppColors.softGreen,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          height: 38,
          width: 38,
          child: Icon(
            icon,
            size: 20,
            color: filled
                ? Colors.white
                : (enabled ? AppColors.deepGreen : AppColors.mutedText),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);
  final _Status status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: GoogleFonts.poppins(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: status.color,
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
      child: Icon(Icons.image_outlined, color: AppColors.green, size: 28),
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
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 76,
              width: 76,
              decoration: const BoxDecoration(
                color: AppColors.softGreen,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: AppColors.green),
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

// ───────────────────────── Update-stock dialog ─────────────────────────

class _StockDialog extends StatefulWidget {
  const _StockDialog({required this.item});
  final _Item item;

  @override
  State<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<_StockDialog> {
  late final TextEditingController _c;
  String? _error;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.item.stock?.toString() ?? '');
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _add(int n) {
    final cur = int.tryParse(_c.text) ?? 0;
    final next = '${cur + n}';
    setState(() {
      _error = null;
      _c.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    });
  }

  void _save() {
    final n = int.tryParse(_c.text.trim());
    if (n == null) {
      setState(() => _error = 'Enter a whole number');
      return;
    }
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return AlertDialog(
      title: const Text('Update stock'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.name,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.darkText,
            ),
          ),
          Text(
            item.stock == null
                ? 'Stock not set yet'
                : 'Current stock: ${item.stock}',
            style:
            GoogleFonts.poppins(fontSize: 12, color: AppColors.mutedText),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _c,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              labelText: 'Quantity in stock',
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final n in const [5, 10, 25, 50])
                ActionChip(
                  label: Text('+$n'),
                  onPressed: () => _add(n),
                  backgroundColor: AppColors.softGreen,
                  side: BorderSide.none,
                  labelStyle: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.deepGreen,
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.green,
            minimumSize: const Size(100, 42),
          ),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}