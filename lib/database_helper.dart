import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('samy.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT,
        name TEXT NOT NULL,
        size TEXT,
        weight TEXT,
        quantity INTEGER NOT NULL DEFAULT 1,
        stock INTEGER DEFAULT 0,
        location TEXT,
        memo TEXT,
        folder TEXT DEFAULT 'المنتجات العامة',
        productionDate TEXT,
        expiryDate TEXT NOT NULL,
        notifyDaysBefore INTEGER DEFAULT 7,
        createdAt TEXT NOT NULL,
        imageBase64 TEXT
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE products ADD COLUMN imageBase64 TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE products ADD COLUMN stock INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE products ADD COLUMN location TEXT');
      await db.execute('ALTER TABLE products ADD COLUMN memo TEXT');
      await db.execute(
          "ALTER TABLE products ADD COLUMN folder TEXT DEFAULT 'المنتجات العامة'");
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE products ADD COLUMN weight TEXT');
      await db.execute('ALTER TABLE products ADD COLUMN productionDate TEXT');
      await db.execute(
          'ALTER TABLE products ADD COLUMN notifyDaysBefore INTEGER DEFAULT 7');
    }
  }

  Future<int> addProduct(Map<String, dynamic> product) async {
    final db = await instance.database;
    return await db.insert('products', product);
  }

  Future<List<Map<String, dynamic>>> getProducts() async {
    final db = await instance.database;
    return await db.query('products', orderBy: 'expiryDate ASC');
  }

  Future<int> deleteProduct(int id) async {
    final db = await instance.database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateProduct(int id, Map<String, dynamic> data) async {
    final db = await instance.database;
    return await db.update('products', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateQuantity(int id, int newQuantity) async {
    final db = await instance.database;
    return await db.update(
      'products',
      {'quantity': newQuantity},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>?> getProductByBarcode(String barcode) async {
    final db = await instance.database;
    final results = await db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    if (results.isNotEmpty) return results.first;
    return null;
  }

  Future<List<String>> getFolders() async {
    final db = await instance.database;
    final result = await db.rawQuery(
        'SELECT DISTINCT folder FROM products WHERE folder IS NOT NULL');
    return result
        .map((row) => row['folder']?.toString() ?? '')
        .where((f) => f.isNotEmpty)
        .toList();
  }
}