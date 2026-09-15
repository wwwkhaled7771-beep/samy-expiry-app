import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'add_product_screen.dart';
import 'database_helper.dart';
import 'notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _allProducts = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filterStatus = 'all';
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    final products = await DatabaseHelper.instance.getProducts();
    if (mounted) {
      setState(() {
        _allProducts = products;
        _isLoading = false;
        _applyFilters();
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
      _filteredProducts = _allProducts.where((p) {
        final matchesSearch = _searchQuery.isEmpty ||
            (p['name'] ?? '').toString().toLowerCase().contains(_searchQuery) ||
            (p['barcode'] ?? '')
                .toString()
                .toLowerCase()
                .contains(_searchQuery) ||
            (p['location'] ?? '')
                .toString()
                .toLowerCase()
                .contains(_searchQuery);
        final days = _daysLeft(DateTime.parse(p['expiryDate']));
        bool matchesStatus = true;
        if (_filterStatus == 'urgent') {
          matchesStatus = days >= 0 && days <= 3;
        } else if (_filterStatus == 'warning') {
          matchesStatus = days >= 4 && days <= 7;
        } else if (_filterStatus == 'expired') {
          matchesStatus = days < 0;
        }
        return matchesSearch && matchesStatus;
      }).toList();
    });
  }

  Future<void> _deleteProduct(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('حذف المنتج'),
          ],
        ),
        content: Text('هل أنت متأكد من حذف "$name"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deleteProduct(id);
      await NotificationService.cancelForProduct(id);
      _loadProducts();
    }
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف $count منتج'),
        content: const Text('هل أنت متأكد من حذف المنتجات المحددة؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      for (final id in _selectedIds) {
        await DatabaseHelper.instance.deleteProduct(id);
        await NotificationService.cancelForProduct(id);
      }
      setState(() => _selectedIds.clear());
      _loadProducts();
    }
  }

  int _daysLeft(DateTime expiry) {
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    return expiry.difference(todayMidnight).inDays;
  }

  Color _getStatusColor(int days) {
    if (days < 0) return const Color(0xFF424242);
    if (days == 0) return const Color(0xFFD32F2F);
    if (days <= 3) return const Color(0xFFF57C00);
    if (days <= 7) return const Color(0xFFFBC02D);
    return const Color(0xFF388E3C);
  }

  @override
  Widget build(BuildContext context) {
    int expired = 0;
    int urgent = 0;
    int warning = 0;
    for (final p in _allProducts) {
      final expiry = DateTime.parse(p['expiryDate']);
      final days = _daysLeft(expiry);
      if (days < 0) {
        expired++;
      } else if (days <= 3) {
        urgent++;
      } else if (days <= 7) {
        warning++;
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _selectedIds.isEmpty ? _buildAppBar() : _buildSelectionAppBar(),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : Column(
              children: [
                _buildSearchBar(),
                _buildStatsRow(expired, urgent, warning),
                const Divider(height: 1),
                if (_filteredProducts.isEmpty)
                  Expanded(child: _buildEmptyState())
                else
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadProducts,
                      color: const Color(0xFF2E7D32),
                      child: ListView.separated(
                        itemCount: _filteredProducts.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, thickness: 0.5),
                        itemBuilder: (ctx, i) =>
                            _buildProductRow(_filteredProducts[i]),
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: _selectedIds.isEmpty
          ? FloatingActionButton.extended(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddProductScreen()),
                );
                if (result == true) _loadProducts();
              },
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text(
                'مسح الباركود',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            )
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF2E7D32),
      foregroundColor: Colors.white,
      elevation: 0,
      title: const Text(
        'إدارة الصلاحية',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loadProducts,
          tooltip: 'تحديث',
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1B5E20),
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => setState(() => _selectedIds.clear()),
      ),
      title: Text('${_selectedIds.length} محدد'),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: _deleteSelected,
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'بحث...',
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            prefixIcon: const Icon(Icons.search_rounded,
                color: Color(0xFF2E7D32), size: 22),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () => _searchController.clear(),
                  )
                : null,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow(int expired, int urgent, int warning) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          _statChip(
              'الكل', _allProducts.length, const Color(0xFF546E7A), 'all'),
          _statChip('حرج', urgent, const Color(0xFFF57C00), 'urgent'),
          _statChip('تحذير', warning, const Color(0xFFFBC02D), 'warning'),
          _statChip('منتهي', expired, const Color(0xFFD32F2F), 'expired'),
        ],
      ),
    );
  }

  Widget _statChip(String label, int count, Color color, String status) {
    final isSelected = _filterStatus == status;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _filterStatus = status);
          _applyFilters();
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? color : color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? Colors.white : color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'لا توجد منتجات',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF212121),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isEmpty
                ? 'اضغط على "مسح الباركود" للبدء'
                : 'لا توجد نتائج مطابقة',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildProductRow(Map<String, dynamic> product) {
    final expiry = DateTime.parse(product['expiryDate']);
    final days = _daysLeft(expiry);
    final color = _getStatusColor(days);
    final id = product['id'] as int;
    final isSelected = _selectedIds.contains(id);

    // الصورة
    Uint8List? imageBytes;
    final imageBase64 = product['imageBase64'];
    if (imageBase64 != null && imageBase64.toString().isNotEmpty) {
      try {
        imageBytes = base64Decode(imageBase64.toString());
      } catch (_) {}
    }

    return InkWell(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddProductScreen(product: product),
          ),
        );
        if (result == true) _loadProducts();
      },
      onLongPress: () {
        setState(() {
          if (isSelected) {
            _selectedIds.remove(id);
          } else {
            _selectedIds.add(id);
          }
        });
      },
      child: Container(
        color: isSelected
            ? const Color(0xFF2E7D32).withValues(alpha: 0.1)
            : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Checkbox
            SizedBox(
              width: 32,
              child: Center(
                child: Checkbox(
                  value: isSelected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedIds.add(id);
                      } else {
                        _selectedIds.remove(id);
                      }
                    });
                  },
                  activeColor: const Color(0xFF2E7D32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            // صورة المنتج
            Container(
              width: 55,
              height: 55,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: imageBytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.memory(imageBytes,
                          fit: BoxFit.cover, width: 55, height: 55),
                    )
                  : Icon(Icons.inventory_2, color: color, size: 26),
            ),
            const SizedBox(width: 10),
            // التفاصيل
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // السطر الأول: التاريخ + D-day + الكمية
                  Row(
                    children: [
                      Text(
                        DateFormat('yyyy-MM-dd').format(expiry),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'D $days',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if ((product['location'] ?? '')
                          .toString()
                          .isNotEmpty) ...[
                        Icon(Icons.location_on,
                            size: 12, color: Colors.grey.shade600),
                        const SizedBox(width: 2),
                        Text(
                          product['location'].toString(),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        '${product['quantity']}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // اسم المنتج
                  Text(
                    product['name'] ?? '',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF212121),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // الباركود + الحجم
                  Row(
                    children: [
                      if ((product['barcode'] ?? '').toString().isNotEmpty) ...[
                        Icon(Icons.qr_code_2,
                            size: 11, color: Colors.grey.shade500),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            product['barcode'].toString(),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ] else
                        const Spacer(),
                      if ((product['size'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          product['size'].toString(),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // زر الحذف
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Color(0xFFD32F2F), size: 20),
              onPressed: () => _deleteProduct(id, product['name'] ?? ''),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
          ],
        ),
      ),
    );
  }
}
