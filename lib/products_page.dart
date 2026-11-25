import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'data/local_database.dart';
import 'stock_tools.dart';

Widget productPhoto(String? photo, double size) {
  if (photo == null || photo.isEmpty) return Icon(Icons.inventory_2_outlined, size: size / 2);
  return ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(photo), width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, error, stack) => Icon(Icons.broken_image_outlined, size: size / 2)));
}


class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key, required this.userId});
  final String userId;
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  late final local = LocalDatabase.forUser(widget.userId);
  final search = TextEditingController();
  List<Map<String, Object?>> rows = [];
  int? businessId;
  String filter = 'Todos';
  String? categoryFilter;
  List<String> categories = [];
  bool loading = true;
  String? error;
  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { search.dispose(); super.dispose(); }

  Future<void> load() async {
    try {
      final business = await local.firstBusiness();
      final id = business?['id'] as int?;
      if (id == null) throw StateError('Cadastre uma empresa primeiro.');
      final db = await local.database;
      final result = await db.query('products', where: 'business_id = ?', whereArgs: [id], orderBy: 'name COLLATE NOCASE');
      final cats = await db.query('categories', where: 'business_id = ?', whereArgs: [id], orderBy: 'name');
      if (!mounted) return;
      setState(() { categories = cats.map((r) => r['name'] as String).toList(); if (!categories.contains(categoryFilter)) categoryFilter = null; businessId = id; rows = result; loading = false; error = null; });
    } catch (_) {
      if (mounted) setState(() { loading = false; error = 'Não foi possível carregar os produtos.'; });
    }
  }

  String money(Object? cents) => ((cents as int? ?? 0) / 100).toStringAsFixed(2).replaceAll('.', ',');
  Future<void> edit([Map<String, Object?>? product]) async {
    final id = businessId;
    if (id == null) return;
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ProductForm(local: local, businessId: id, product: product, categories: categories)));
    if (saved == true && mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final filtered = rows.where((r) => (categoryFilter == null || r['category'] == categoryFilter) && (filter == 'Todos' || filter == 'Ativos' && r['active'] == 1 || filter == 'Inativos' && r['active'] == 0 || filter == 'Sem estoque' && r['stock'] == 0 || filter == 'Estoque baixo' && (r['stock'] as int) <= (r['min_stock'] as int)) && ['name','barcode','sku','category'].any((k) => (r[k]?.toString() ?? '').toLowerCase().contains(query))).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Produtos e estoque'), actions: [IconButton(tooltip: 'Categorias', icon: const Icon(Icons.category), onPressed: businessId == null ? null : () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => CategoriesPage(local: local, businessId: businessId!))); if (mounted) await load(); })]),
      floatingActionButton: businessId == null ? null : FloatingActionButton(onPressed: () => edit(), child: const Icon(Icons.add)),
      body: loading ? const Center(child: CircularProgressIndicator()) : error != null ? Center(child: TextButton(onPressed: load, child: Text(error!))) : Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(controller: search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Pesquisar produto, categoria ou código'))),
        Row(children: [Expanded(child: DropdownButton<String>(isExpanded: true, value: filter, items: ['Todos','Ativos','Inativos','Sem estoque','Estoque baixo'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>filter=v!))), Expanded(child: DropdownButton<String>(isExpanded:true,value:categoryFilter,hint:const Text('Todas categorias'),items:[const DropdownMenuItem<String>(value:null,child:Text('Todas categorias')),...categories.map((v)=>DropdownMenuItem(value:v,child:Text(v)))],onChanged:(v)=>setState(()=>categoryFilter=v))), IconButton(icon:const Icon(Icons.qr_code_scanner),onPressed:() async {final code=await scanBarcode(context);if(mounted && code!=null)setState(()=>search.text=code);})]),
        Padding(padding: const EdgeInsets.all(8), child: Text('${rows.where((r) => r['active'] == 1).length} produtos ativos')),
        Expanded(child: filtered.isEmpty ? const Center(child: Text('Nenhum produto encontrado')) : ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) {
          final r = filtered[i];
          return Card(child: ListTile(
            leading: productPhoto(r['photo_path'] as String?, 48),
            title: Text(r['name'].toString()),
            subtitle: Text('${r['category'] ?? 'Sem categoria'} • Estoque: ${r['stock']} • ${r['active'] == 1 ? 'Ativo' : 'Inativo'}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text('R\$ ${money(r['sale_cents'])}'), IconButton(tooltip:'Movimentar estoque',icon:Icon(Icons.swap_vert,color:(r['stock'] as int)<=(r['min_stock'] as int)?Colors.red:null),onPressed:() async {await Navigator.push(context,MaterialPageRoute(builder:(_)=>StockPage(local:local,businessId:businessId!,product:r)));if(mounted)await load();})]),
            onTap: () => edit(r),
          ));
        })),
      ]),
    );
  }
}

class ProductForm extends StatefulWidget {
  const ProductForm({super.key, required this.local, required this.businessId, this.product, required this.categories});
  final List<String> categories;
  final LocalDatabase local;
  final int businessId;
  final Map<String, Object?>? product;
  @override
  State<ProductForm> createState() => _ProductFormState();
}
class _ProductFormState extends State<ProductForm> {
  final form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> fields;
  late bool active;
  bool saving = false;
  bool picking = false;
  String? photo;
  String? selectedPhoto;
  @override
  void initState() {
    super.initState();
    final p = widget.product;
    fields = {for (final k in ['name','sku','barcode','category','sale_cents','cost_cents','stock','min_stock']) k: TextEditingController(text: k.endsWith('_cents') ? ((p?[k] as int? ?? 0)/100).toStringAsFixed(2).replaceAll('.', ',') : (p?[k]?.toString() ?? ((k == 'stock' || k == 'min_stock') ? '0' : '')))};
    active = p?['active'] != 0;
    photo = p?['photo_path'] as String?;
  }
  @override
  void dispose() { for (final c in fields.values) { c.dispose(); } super.dispose(); }
  int? cents(String? s) {
    final value = s?.trim().replaceAll(',', '.') ?? '';
    if (!RegExp(r'^[0-9]+([.][0-9]{1,2})?$').hasMatch(value)) return null;
    final n = double.tryParse(value);
    return n == null || !n.isFinite || n > 999999999 ? null : (n*100).round();
  }
  Future<void> pickPhoto() async {
    setState(() => picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['jpg','jpeg','png','webp'], allowMultiple: false);
      if (!mounted || result == null) return;
      final file = result.files.single;
      if (file.path == null || file.size > 10 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione uma imagem de até 10 MB.')));
        return;
      }
      setState(() { selectedPhoto = file.path; photo = file.path; });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível abrir a imagem.')));
    } finally { if (mounted) setState(() => picking = false); }
  }
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    File? copied;
    bool committed = false;
    try {
      String? savedPhoto = photo;
      if (selectedPhoto != null) {
        final root = await getApplicationDocumentsDirectory();
        final folder = Directory(path.join(root.path, 'product_photos', widget.local.userId));
        await folder.create(recursive: true);
        final target = path.join(folder.path, '${DateTime.now().microsecondsSinceEpoch}${path.extension(selectedPhoto!)}');
        copied = await File(selectedPhoto!).copy(target);
        savedPhoto = copied.path;
      }
      final db = await widget.local.database;
      final data = <String, Object?>{
        'business_id': widget.businessId,
        for (final k in ['name','sku','barcode','category']) k: fields[k]!.text.trim(),
        'sale_cents': cents(fields['sale_cents']!.text),
        'cost_cents': cents(fields['cost_cents']!.text),
        'stock': int.parse(fields['stock']!.text.trim()),
        'min_stock': int.parse(fields['min_stock']!.text.trim()),
        'active': active ? 1 : 0,
        'photo_path': savedPhoto,
      };
      await db.transaction((tx) async {
        final category = data['category'] as String;
        if (category.isNotEmpty) await tx.rawInsert('INSERT OR IGNORE INTO categories(business_id,name) VALUES (?,?)',[widget.businessId,category]);
        if (widget.product == null) {
          final id = await tx.insert('products',data);
          final initial = data['stock'] as int;
          if(initial>0) await tx.insert('stock_movements',{'product_id':id,'business_id':widget.businessId,'delta':initial,'reason':'Estoque inicial','created_at':DateTime.now().toIso8601String()});
        } else {
          data.remove('stock');
          await tx.update('products',data,where:'id = ? AND business_id = ?',whereArgs:[widget.product!['id'],widget.businessId]);
        }
      });
      committed = true;
      final old = widget.product?['photo_path'] as String?;
      if (old != null && old != savedPhoto) {
        try {
          final root = await getApplicationDocumentsDirectory();
          final folder = path.join(root.path, 'product_photos', widget.local.userId);
          if (path.isWithin(folder, old)) await File(old).delete();
        } catch (_) {}
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!committed && copied != null) { try { await copied.delete(); } catch (_) {} }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível salvar o produto.')));
    } finally { if (mounted) setState(() => saving = false); }
  }
  Widget field(String key, String label, {String? Function(String?)? validator, TextInputType? keyboard}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(controller: fields[key], decoration: InputDecoration(labelText: label), validator: validator, keyboardType: keyboard),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.product == null ? 'Cadastrar produto' : 'Editar produto')),
    body: Form(key: form, child: ListView(padding: const EdgeInsets.all(16), children: [
      Center(child: productPhoto(photo, 140)),
      OutlinedButton.icon(onPressed: saving || picking ? null : pickPhoto, icon: const Icon(Icons.add_photo_alternate_outlined), label: Text(photo == null ? 'Carregar foto do celular' : 'Trocar foto')),
      if (photo != null) TextButton(onPressed: saving || picking ? null : () => setState(() { photo = null; selectedPhoto = null; }), child: const Text('Remover foto')),
      const SizedBox(height: 12),
      field('name','Nome do produto *', validator: (v) => v == null || v.trim().isEmpty ? 'Informe o nome' : null),
      field('category','Categoria'),
      if(widget.categories.isNotEmpty) Wrap(spacing:6,children:widget.categories.map((v)=>ActionChip(label:Text(v),onPressed:()=>setState(()=>fields['category']!.text=v))).toList()),
      field('sku','Código interno'),
      field('barcode','Código de barras'),
      OutlinedButton.icon(onPressed: saving ? null : () async {final code=await scanBarcode(context);if(mounted && code!=null)setState(()=>fields['barcode']!.text=code);},icon:const Icon(Icons.qr_code_scanner),label:const Text('Ler pela câmera')),
      field('cost_cents','Preço de custo (R\$)', keyboard: const TextInputType.numberWithOptions(decimal: true), validator: (v) => cents(v) == null ? 'Valor inválido' : null),
      field('sale_cents','Preço de venda (R\$)', keyboard: const TextInputType.numberWithOptions(decimal: true), validator: (v) => cents(v) == null ? 'Valor inválido' : null),
      if(widget.product == null) field('stock','Quantidade em estoque', keyboard: TextInputType.number, validator: (v) { final n = int.tryParse(v?.trim() ?? ''); return n == null || n < 0 || n > 2147483647 ? 'Quantidade inválida' : null; }),
      field('min_stock','Estoque mínimo',keyboard:TextInputType.number,validator:(v){final n=int.tryParse(v?.trim()??'');return n==null||n<0||n>2147483647?'Quantidade inválida':null;}),
      SwitchListTile(title: const Text('Produto ativo'), value: active, onChanged: saving ? null : (v) => setState(() => active = v)),
      FilledButton(onPressed: saving || picking ? null : save, child: Text(saving ? 'Salvando...' : 'Salvar produto')),
    ])),
  );
}
