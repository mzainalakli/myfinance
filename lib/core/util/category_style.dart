import 'package:flutter/material.dart';

/// Ikon kategori disimpan sebagai kunci teks agar skema DB stabil.
const Map<String, IconData> categoryIcons = {
  'restaurant': Icons.restaurant,
  'coffee': Icons.local_cafe,
  'bus': Icons.directions_bus,
  'car': Icons.directions_car,
  'bag': Icons.shopping_bag,
  'cart': Icons.shopping_cart,
  'bill': Icons.receipt_long,
  'home': Icons.home,
  'health': Icons.medical_services,
  'movie': Icons.movie,
  'game': Icons.sports_esports,
  'school': Icons.school,
  'more': Icons.more_horiz,
  'salary': Icons.payments,
  'bonus': Icons.emoji_events,
  'gift': Icons.card_giftcard,
  'shop': Icons.storefront,
  'pets': Icons.pets,
  'flight': Icons.flight,
  'phone': Icons.smartphone,
  'fitness': Icons.fitness_center,
  'savings': Icons.savings,
  'work': Icons.work,
  'child': Icons.child_care,
};

IconData iconFor(String key) => categoryIcons[key] ?? Icons.category;

const List<int> categoryColors = [
  0xFFEF6C00, 0xFF1E88E5, 0xFF8E24AA, 0xFFD81B60, 0xFF43A047, 0xFF00897B,
  0xFF6D4C41, 0xFF546E7A, 0xFFFBC02D, 0xFF3949AB, 0xFFE53935, 0xFF7CB342,
];
