import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'barcode_scanner_screen.dart';
import 'database_helper.dart';
import 'notification_service.dart';

class AddProductScreen extends StatefulWidget {
  final Map<String, dynamic>? product; // للتعديل
  const AddProductScreen({super.key, this.product});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _sizeController = TextEditingController();
  final _weightController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _stockController = TextEditingController(text: '0');
  final _locationController = TextEditingController();
  final _memoController = TextEditingController();
  final _folderController = TextEditingController(text: 'المنتجات العامة');

  String? _barcode;
  DateTime? _expiryDate;
  DateTime? _productionDate;
  Uint8List? _imageBytes;
  int _notifyDaysBefore = 7;

  final ImagePicker _imagePicker = ImagePicker();
  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final p = widget.product!;
      _nameController.text = p['name'] ?? '';
      _sizeController.text = p['size'] ?? '';
      _weightController.text = p['weight'] ?? '';
      _qtyController.text = (p['quantity'] ?? 1).toString();
      _stockController.text = (p['stock'] ?? 0).toString();
      _locationController.text = p['location'] ?? '';
      _memoController.text = p['memo'] ?? '';
      _folderController.text = p['folder'] ?? 'المنتجات العامة';
      _barcode = p['barcode'];
      _notifyDaysBefore = p['notifyDaysBefore'] ?? 7;
      if (p['expiryDate'] != null) {
        _expiryDate = DateTime.parse(p['expiryDate']);
      }
      if (p['productionDate'] != null &&
          p['productionDate'].toString().isNotEmpty) {
        _productionDate = DateTime.parse(p['productionDate']);
      }
      final imgBase64 = p['imageBase64'];
      if (imgBase64 != null && imgBase64.toString().isNotEmpty) {
        try {
          _imageBytes = base64Decode(imgBase64.toString());
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sizeController.dispose();
    _weightController.dispose();
    _qtyController.dispose();
    _stockController.dispose();
    _locationController.dispose();
    _memoController.dispose();
    _folderController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 70,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        if (mounted) setState(() => _imageBytes = bytes);
      }
    } catch (e) {
      if (mounted) _showSnack('تعذّر التقاط الصورة');
    }
  }

  void _showSnack(String msg, {Color color = const Color(0xFFD32F2F)}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (result != null && mounted) {
      setState(() => _barcode = result);
    }
  }

  Future<void> _pickDate(bool isExpiry) async {
    final now = DateTime.now();
    final initial = isExpiry
        ? (widget.product != null && _expiryDate != null
            ? _expiryDate!
            : now.add(const Duration(days: 30)))
        : (_productionDate ?? now);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF2E7D32),
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        if (isExpiry) {
          _expiryDate = picked;
        } else {
          _productionDate = picked;
        }
      });
    }
  }

  int _daysUntilExpiry() {
    if (_expiryDate == null) return 0;
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    return _expiryDate!.difference(todayMidnight).inDays;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _expiryDate == null) {
      _showSnack('يرجى إكمال الحقول المطلوبة');
      return;
    }

    final id = _isEditing
        ? widget.product!['id']
        : DateTime.now().millisecondsSinceEpoch ~/ 1000;

    String? imageBase64Str;
    if (_imageBytes != null) {
      imageBase64Str = base64Encode(_imageBytes!);
    }

    final data = {
      'barcode': _barcode,
      'name': _nameController.text.trim(),
      'size': _sizeController.text.trim(),
      'weight': _weightController.text.trim(),
      'quantity': int.tryParse(_qtyController.text) ?? 1,
      'stock': int.tryParse(_stockController.text) ?? 0,
      'location': _locationController.text.trim(),
      'memo': _memoController.text.trim(),
      'folder': _folderController.text.trim(),
      'productionDate':
          _productionDate?.toIso8601String() ?? '',
      'expiryDate': _expiryDate!.toIso8601String(),
      'notifyDaysBefore': _notifyDaysBefore,
      'createdAt': DateTime.now().toIso8601String(),
      'imageBase64': imageBase64Str,
    };

    if (_isEditing) {
      await DatabaseHelper.instance.updateProduct(id, data);
      await NotificationService.cancelForProduct(id);
    } else {
      await DatabaseHelper.instance.addProduct(data);
    }

    await NotificationService.scheduleExpiryNotifications(
      id: id,
      productName: _nameController.text.trim(),
      expiryDate: _expiryDate!,
    );

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _isEditing ? 'تعديل المنتج' : 'منتج جديد',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
          IconButton(
            icon: const Icon(Icons.save_rounded),
            onPressed: _save,
            tooltip: 'حفظ',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // صورة + كاميرا باركود
            _buildTopImageSection(),
            const SizedBox(height: 12),

            // حقل الباركود
            _buildRow(
              icon: Icons.qr_code_2,
              child: InkWell(
                onTap: _scanBarcode,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _barcode ?? 'اضغط لمسح الباركود',
                          style: TextStyle(
                            fontSize: 15,
                            color: _barcode == null
                                ? Colors.grey.shade500
                                : const Color(0xFF212121),
                            fontWeight: _barcode != null
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.qr_code_scanner,
                        color: _barcode != null
                            ? const Color(0xFF2E7D32)
                            : Colors.grey,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // اسم المنتج
            _buildField(
              icon: Icons.edit_note,
              controller: _nameController,
              hint: 'اسم المنتج',
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'مطلوب' : null,
            ),

            // الحجم
            _buildField(
              icon: Icons.straighten,
              controller: _sizeController,
              hint: 'الحجم (مثال: 400ml)',
            ),

            // الوزن
            _buildField(
              icon: Icons.scale,
              controller: _weightController,
              hint: 'الوزن (مثال: 250 جرام)',
            ),

            // تاريخ الإنتاج
            _buildRow(
              icon: Icons.precision_manufacturing,
              child: InkWell(
                onTap: () => _pickDate(false),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _productionDate == null
                              ? 'تاريخ الإنتاج (اختياري)'
                              : DateFormat('yyyy-MM-dd')
                                  .format(_productionDate!),
                          style: TextStyle(
                            fontSize: 15,
                            color: _productionDate == null
                                ? Colors.grey.shade500
                                : const Color(0xFF212121),
                          ),
                        ),
                      ),
                      const Icon(Icons.calendar_today,
                          color: Color(0xFF2E7D32), size: 20),
                    ],
                  ),
                ),
              ),
            ),

            // تاريخ الانتهاء + D-Day
            _buildRow(
              icon: Icons.event_busy,
              child: InkWell(
                onTap: () => _pickDate(true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _expiryDate == null
                              ? 'تاريخ الانتهاء *'
                              : DateFormat('yyyy-MM-dd')
                                  .format(_expiryDate!),
                          style: TextStyle(
                            fontSize: 15,
                            color: _expiryDate == null
                                ? Colors.grey.shade500
                                : const Color(0xFF212121),
                            fontWeight: _expiryDate != null
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (_expiryDate != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getDayColor(_daysUntilExpiry()),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'D ${_daysUntilExpiry()}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      const Icon(Icons.calendar_today,
                          color: Color(0xFF2E7D32), size: 20),
                    ],
                  ),
                ),
              ),
            ),

            // الكمية + المخزون (صف واحد)
            Row(
              children: [
                Expanded(
                  child: _buildRow(
                    icon: Icons.numbers,
                    child: _buildQtyRow(
                      controller: _qtyController,
                      label: 'الكمية',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildRow(
                    icon: Icons.inventory_2,
                    child: _buildQtyRow(
                      controller: _stockController,
                      label: 'المخزون',
                    ),
                  ),
                ),
              ],
            ),

            // الموقع
            _buildField(
              icon: Icons.location_on,
              controller: _locationController,
              hint: 'الموقع (مثال: رف 3)',
            ),

            // الملاحظات
            _buildField(
              icon: Icons.note_alt,
              controller: _memoController,
              hint: 'ملاحظات',
              maxLines: 2,
            ),

            // المجلد
            _buildField(
              icon: Icons.folder,
              controller: _folderController,
              hint: 'المجلد',
            ),

            // إشعار مخصص
            const SizedBox(height: 12),
            _buildNotifySection(),

            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check_circle_rounded, size: 22),
          label: Text(
            _isEditing ? 'تحديث المنتج' : 'حفظ المنتج',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }

  // === مكونات مساعدة ===

  Widget _buildTopImageSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // الصورة
        Expanded(
          flex: 2,
          child: InkWell(
            onTap: _showImageOptions,
            child: Container(
              height: 130,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: _imageBytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.memory(
                        _imageBytes!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo,
                            size: 32, color: Colors.grey.shade500),
                        const SizedBox(height: 6),
                        Text(
                          'إضافة صورة',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // أزرار الكاميرا والمعرض
        Expanded(
          flex: 1,
          child: Column(
            children: [
              _smallBtn(
                'التقاط',
                Icons.camera_alt,
                const Color(0xFF2E7D32),
                () => _pickImage(ImageSource.camera),
              ),
              const SizedBox(height: 8),
              _smallBtn(
                'المعرض',
                Icons.photo_library,
                const Color(0xFF1976D2),
                () => _pickImage(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _smallBtn(String label, IconData icon, Color color, VoidCallback tap) {
    return InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow({required IconData icon, required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20, color: const Color(0xFF2E7D32)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildField({
    required IconData icon,
    required TextEditingController controller,
    required String hint,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return _buildRow(
      icon: icon,
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        validator: validator,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 0, vertical: 14),
        ),
        style: const TextStyle(fontSize: 15),
      ),
    );
  }

  Widget _buildQtyRow({
    required TextEditingController controller,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              final val = int.tryParse(controller.text) ?? 0;
              if (val > 0) {
                controller.text = (val - 1).toString();
                setState(() {});
              }
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.remove, size: 16),
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: controller,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: label,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          InkWell(
            onTap: () {
              final val = int.tryParse(controller.text) ?? 0;
              controller.text = (val + 1).toString();
              setState(() {});
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.add,
                  size: 16, color: Color(0xFF2E7D32)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotifySection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFB74D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active,
                  color: Color(0xFFF57C00), size: 20),
              const SizedBox(width: 6),
              const Text(
                'تنبيه قبل انتهاء الصلاحية',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFFE65100),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final d in [1, 3, 7, 14, 30])
                ChoiceChip(
                  label: Text('$d يوم'),
                  selected: _notifyDaysBefore == d,
                  onSelected: (_) =>
                      setState(() => _notifyDaysBefore = d),
                  selectedColor: const Color(0xFFF57C00),
                  labelStyle: TextStyle(
                    color: _notifyDaysBefore == d
                        ? Colors.white
                        : const Color(0xFFE65100),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getDayColor(int days) {
    if (days < 0) return const Color(0xFF424242);
    if (days == 0) return const Color(0xFFD32F2F);
    if (days <= 3) return const Color(0xFFF57C00);
    if (days <= 7) return const Color(0xFFFBC02D);
    return const Color(0xFF388E3C);
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.camera_alt,
                  color: Color(0xFF2E7D32)),
              title: const Text('التقاط صورة'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: Color(0xFF1976D2)),
              title: const Text('اختيار من المعرض'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_imageBytes != null)
              ListTile(
                leading:
                    const Icon(Icons.delete, color: Color(0xFFD32F2F)),
                title: const Text('حذف الصورة'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _imageBytes = null);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المنتج'),
        content: const Text('هل أنت متأكد؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final id = widget.product!['id'];
      await DatabaseHelper.instance.deleteProduct(id);
      await NotificationService.cancelForProduct(id);
      if (mounted) Navigator.pop(context, true);
    }
  }
}