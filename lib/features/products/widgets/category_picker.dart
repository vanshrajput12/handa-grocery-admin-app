import 'package:flutter/material.dart';

class CategoryPicker extends StatelessWidget {
  const CategoryPicker({
    super.key,
    required this.controller,
    required this.categories,
    this.enabled = true,
  });

  final TextEditingController controller;
  final List<String> categories;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          enabled: enabled,
          decoration: const InputDecoration(
            labelText: 'Category',
            hintText: 'Pick one below or type a new category',
          ),
          validator: (v) =>
          (v ?? '').trim().isEmpty ? 'Please enter a category' : null,
        ),
        if (enabled && categories.isNotEmpty) ...[
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in categories)
                  ChoiceChip(
                    label: Text(c),
                    selected: value.text.trim().toLowerCase() == c.toLowerCase(),
                    onSelected: (_) => controller.text = c,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}