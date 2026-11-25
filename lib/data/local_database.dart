import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  LocalDatabase._(this.userId);
  final String userId;
  static final Map<String, LocalDatabase> _accounts = {};
  static LocalDatabase forUser(String userId) {
    if (!RegExp(r'^[a-fA-F0-9-]{36}
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      join(await getDatabasesPath(), 'markys_pdv_$userId.db'),
      version: 1,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE businesses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            document TEXT,
            phone TEXT,
            email TEXT,
            address TEXT,
            segment TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            business_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            sku TEXT,
            barcode TEXT,
            category TEXT,
            sale_cents INTEGER NOT NULL DEFAULT 0,
            cost_cents INTEGER NOT NULL DEFAULT 0,
            stock INTEGER NOT NULL DEFAULT 0,
            photo_path TEXT,
            active INTEGER NOT NULL DEFAULT 1,
            FOREIGN KEY (business_id) REFERENCES businesses(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            business_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            phone TEXT,
            email TEXT,
            document TEXT,
            FOREIGN KEY (business_id) REFERENCES businesses(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE sales (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            business_id INTEGER NOT NULL,
            customer_id INTEGER,
            total_cents INTEGER NOT NULL,
            payment_method TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY (business_id) REFERENCES businesses(id),
            FOREIGN KEY (customer_id) REFERENCES customers(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE sale_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sale_id INTEGER NOT NULL,
            product_id INTEGER NOT NULL,
            quantity INTEGER NOT NULL,
            price_cents INTEGER NOT NULL,
            FOREIGN KEY (sale_id) REFERENCES sales(id),
            FOREIGN KEY (product_id) REFERENCES products(id)
          )
        ''');
        await db.execute('CREATE INDEX idx_products_business ON products(business_id)');
        await db.execute('CREATE INDEX idx_sales_business_date ON sales(business_id, created_at)');
      },
    );
    await _db!.execute('PRAGMA foreign_keys = ON');
    return _db!;
  }

  Future<Map<String, Object?>?> firstBusiness() async {
    final rows = await (await database).query('businesses', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> registerBusiness({
    required String name,
    String? document,
    String? phone,
    String? email,
    String? address,
    String? segment,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Informe o nome da empresa');
    return (await database).insert('businesses', {
      'name': trimmed,
      'document': document?.trim(),
      'phone': phone?.trim(),
      'email': email?.trim(),
      'address': address?.trim(),
      'segment': segment?.trim(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
).hasMatch(userId)) throw ArgumentError('Conta inválida');
    return _accounts.putIfAbsent(userId, () => LocalDatabase._(userId));
  }
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      join(await getDatabasesPath(), 'markys_pdv_mobile.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE businesses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            document TEXT,
            phone TEXT,
            email TEXT,
            address TEXT,
            segment TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            business_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            sku TEXT,
            barcode TEXT,
            category TEXT,
            sale_cents INTEGER NOT NULL DEFAULT 0,
            cost_cents INTEGER NOT NULL DEFAULT 0,
            stock INTEGER NOT NULL DEFAULT 0,
            photo_path TEXT,
            active INTEGER NOT NULL DEFAULT 1,
            FOREIGN KEY (business_id) REFERENCES businesses(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            business_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            phone TEXT,
            email TEXT,
            document TEXT,
            FOREIGN KEY (business_id) REFERENCES businesses(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE sales (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            business_id INTEGER NOT NULL,
            customer_id INTEGER,
            total_cents INTEGER NOT NULL,
            payment_method TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY (business_id) REFERENCES businesses(id),
            FOREIGN KEY (customer_id) REFERENCES customers(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE sale_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sale_id INTEGER NOT NULL,
            product_id INTEGER NOT NULL,
            quantity INTEGER NOT NULL,
            price_cents INTEGER NOT NULL,
            FOREIGN KEY (sale_id) REFERENCES sales(id),
            FOREIGN KEY (product_id) REFERENCES products(id)
          )
        ''');
        await db.execute('CREATE INDEX idx_products_business ON products(business_id)');
        await db.execute('CREATE INDEX idx_sales_business_date ON sales(business_id, created_at)');
      },
    );
    await _db!.execute('PRAGMA foreign_keys = ON');
    return _db!;
  }

  Future<Map<String, Object?>?> firstBusiness() async {
    final rows = await (await database).query('businesses', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> registerBusiness({
    required String name,
    String? document,
    String? phone,
    String? email,
    String? address,
    String? segment,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Informe o nome da empresa');
    return (await database).insert('businesses', {
      'name': trimmed,
      'document': document?.trim(),
      'phone': phone?.trim(),
      'email': email?.trim(),
      'address': address?.trim(),
      'segment': segment?.trim(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
