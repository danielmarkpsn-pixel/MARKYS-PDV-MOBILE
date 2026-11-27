import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  LocalDatabase._(this.userId);
  final String userId;
  static final Map<String, LocalDatabase> _accounts = {};
  static LocalDatabase forUser(String userId) {
    if (userId.length != 36 || RegExp(r'[^a-fA-F0-9-]').hasMatch(userId)) {
      throw ArgumentError('Conta inválida');
    }
    return _accounts.putIfAbsent(userId, () => LocalDatabase._(userId));
  }
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      join(await getDatabasesPath(), 'markys_pdv_$userId.db'),
      version: 5,
      onUpgrade: (db, old, version) async { if (old < 2) await upgradeStock(db); if (old < 3) await upgradeCustomers(db); if (old < 4) await upgradeSales(db); if (old < 5) await upgradeFinance(db); },
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
        await upgradeStock(db);
        await upgradeCustomers(db);
        await upgradeSales(db);
        await upgradeFinance(db);
        await db.execute('CREATE INDEX idx_products_business ON products(business_id)');
        await db.execute('CREATE INDEX idx_sales_business_date ON sales(business_id, created_at)');
      },
    );
    await _db!.execute('PRAGMA foreign_keys = ON');
    return _db!;
  }

  Future<void> upgradeFinance(Database db) async {
    await db.execute("ALTER TABLE sales ADD COLUMN status TEXT NOT NULL DEFAULT 'Concluída'");
    await db.execute('ALTER TABLE sales ADD COLUMN cancelled_at TEXT');
    await db.execute('CREATE TABLE sale_payments (id INTEGER PRIMARY KEY, sale_id INTEGER NOT NULL REFERENCES sales(id), method TEXT NOT NULL, amount INTEGER NOT NULL)');
    await db.execute('INSERT INTO sale_payments(sale_id,method,amount) SELECT id,payment_method,total_cents FROM sales');
    await db.execute('CREATE TABLE debt_receipts (id INTEGER PRIMARY KEY, sale_id INTEGER NOT NULL REFERENCES sales(id), amount INTEGER NOT NULL, method TEXT NOT NULL, created_at TEXT NOT NULL)');
    await db.execute('CREATE TABLE open_orders (id INTEGER PRIMARY KEY, business_id INTEGER NOT NULL REFERENCES businesses(id), cart_json TEXT NOT NULL, created_at TEXT NOT NULL)');
  }
  Future<void> cancelSale(int businessId,int id) async {
    await (await database).transaction((tx) async {
      final rows=await tx.query('sales',where:"id = ? AND business_id = ? AND status = 'Concluída'",whereArgs:[id,businessId]);
      if(rows.isEmpty)throw StateError('Venda indisponível');
      if((await tx.query('debt_receipts',where:'sale_id = ?',whereArgs:[id])).isNotEmpty)throw StateError('Venda com recebimento de fiado: regularize antes de cancelar');
      final now=DateTime.now().toIso8601String();
      for(final item in await tx.query('sale_items',where:'sale_id = ?',whereArgs:[id])){
        await tx.rawUpdate('UPDATE products SET stock = stock + ? WHERE id = ? AND business_id = ?',[item['quantity'],item['product_id'],businessId]);
        await tx.insert('stock_movements',{'product_id':item['product_id'],'business_id':businessId,'delta':item['quantity'],'reason':'Cancelamento #$id','created_at':now});
      }
      await tx.update('sales',{'status':'Cancelada','cancelled_at':now},where:'id = ? AND business_id = ?',whereArgs:[id,businessId]);
    });
  }
  Future<void> receiveDebt(int businessId,int id,int amount,String method) async {
    await (await database).transaction((tx) async {
      final rows=await tx.rawQuery("SELECT COALESCE((SELECT SUM(amount) FROM sale_payments WHERE sale_id=s.id AND method='Fiado'),0)-COALESCE((SELECT SUM(amount) FROM debt_receipts WHERE sale_id=s.id),0) AS balance FROM sales s WHERE s.id=? AND s.business_id=? AND s.status='Concluída'",[id,businessId]);
      if(rows.isEmpty||amount<=0||amount>(rows.first['balance'] as int)||!['Pix','Dinheiro','Débito','Crédito'].contains(method))throw StateError('Recebimento inválido');
      await tx.insert('debt_receipts',{'sale_id':id,'amount':amount,'method':method,'created_at':DateTime.now().toIso8601String()});
    });
  }

  Future<void> upgradeSales(Database db) async {
    await db.execute('ALTER TABLE sales ADD COLUMN discount_cents INTEGER NOT NULL DEFAULT 0');
  }

  Future<int> finishSale(int businessId, int? customerId, Map<int,int> cart, int discount, String payment, {Map<String,int>? split, int? orderId}) async {
    if (cart.isEmpty || discount < 0 || !['Dinheiro','Pix','Débito','Crédito','Fiado','Combinado'].contains(payment)) throw StateError('Venda inválida');
    return (await database).transaction((tx) async {
      if (customerId != null && (await tx.query('customers',where:'id = ? AND business_id = ? AND active = 1',whereArgs:[customerId,businessId])).isEmpty) throw StateError('Cliente indisponível');
      int subtotal = 0;
      final items = <Map<String,Object?>>[];
      for (final e in cart.entries) {
        final rows = await tx.query('products',where:'id = ? AND business_id = ? AND active = 1',whereArgs:[e.key,businessId]);
        if (rows.isEmpty || e.value <= 0) throw StateError('Produto indisponível');
        final p = rows.first;
        if ((p['stock'] as int) < e.value) throw StateError('Estoque insuficiente: ${p['name']}');
        final price = p['sale_cents'] as int;
        subtotal += price * e.value;
        items.add({'product_id':e.key,'quantity':e.value,'price_cents':price});
      }
      if (discount > subtotal) throw StateError('Desconto superior ao subtotal');
      final total = subtotal-discount;
      final parts = split ?? {payment:total};
      if (parts.isEmpty || parts.entries.any((e)=>!['Dinheiro','Pix','Débito','Crédito','Fiado'].contains(e.key)||e.value<0) || parts.values.fold<int>(0,(a,b)=>a+b)!=total || (parts['Fiado']??0)>0 && customerId==null) throw StateError('Confira os pagamentos e o cliente');
      if(orderId!=null && (await tx.delete('open_orders',where:'id = ? AND business_id = ?',whereArgs:[orderId,businessId]))!=1) throw StateError('Pedido indisponível');
      final now = DateTime.now().toIso8601String();
      final id = await tx.insert('sales',{'business_id':businessId,'customer_id':customerId,'total_cents':subtotal-discount,'discount_cents':discount,'payment_method':payment,'created_at':now});
      for(final e in parts.entries){await tx.insert('sale_payments',{'sale_id':id,'method':e.key,'amount':e.value});}
      for (final item in items) {
        await tx.insert('sale_items',{'sale_id':id,...item});
        await tx.rawUpdate('UPDATE products SET stock = stock - ? WHERE id = ? AND business_id = ?',[item['quantity'],item['product_id'],businessId]);
        await tx.insert('stock_movements',{'product_id':item['product_id'],'business_id':businessId,'delta':-(item['quantity'] as int),'reason':'Venda #$id','created_at':now});
      }
      return id;
    });
  }

  Future<void> upgradeCustomers(Database db) async {
    await db.execute('ALTER TABLE customers ADD COLUMN address TEXT');
    await db.execute('ALTER TABLE customers ADD COLUMN notes TEXT');
    await db.execute('ALTER TABLE customers ADD COLUMN whatsapp TEXT');
    await db.execute('ALTER TABLE customers ADD COLUMN active INTEGER NOT NULL DEFAULT 1');
    await db.execute('CREATE INDEX idx_customers_business ON customers(business_id)');
  }

  Future<void> upgradeStock(Database db) async {
    await db.execute('ALTER TABLE products ADD COLUMN min_stock INTEGER NOT NULL DEFAULT 0');
    await db.execute('CREATE TABLE categories (id INTEGER PRIMARY KEY, business_id INTEGER NOT NULL REFERENCES businesses(id), name TEXT NOT NULL COLLATE NOCASE, UNIQUE(business_id,name))');
    await db.execute("INSERT OR IGNORE INTO categories(business_id,name) SELECT business_id,trim(category) FROM products WHERE trim(category) <> ''");
    await db.execute('CREATE TABLE stock_movements (id INTEGER PRIMARY KEY, product_id INTEGER NOT NULL REFERENCES products(id), business_id INTEGER NOT NULL REFERENCES businesses(id), delta INTEGER NOT NULL, reason TEXT NOT NULL, created_at TEXT NOT NULL)');
  }

  Future<void> moveStock(int businessId, int productId, int delta, String reason) async {
    if (delta == 0) return;
    await (await database).transaction((tx) async {
      final rows = await tx.query('products', where: 'id = ? AND business_id = ?', whereArgs: [productId,businessId]);
      if (rows.isEmpty) throw StateError('Produto não encontrado');
      final next = (rows.first['stock'] as int) + delta;
      if (next < 0 || next > 2147483647) throw StateError('Quantidade inválida ou estoque insuficiente');
      await tx.update('products', {'stock':next}, where: 'id = ? AND business_id = ?', whereArgs: [productId,businessId]);
      await tx.insert('stock_movements', {'product_id':productId,'business_id':businessId,'delta':delta,'reason':reason,'created_at':DateTime.now().toIso8601String()});
    });
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
