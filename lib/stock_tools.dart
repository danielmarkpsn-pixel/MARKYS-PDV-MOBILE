import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'data/local_database.dart';

Future<String?> scanBarcode(BuildContext context) => Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const BarcodePage()));
class BarcodePage extends StatefulWidget {
  const BarcodePage({super.key});
  @override
  State<BarcodePage> createState() => _BarcodePageState();
}
class _BarcodePageState extends State<BarcodePage> {
  bool found = false;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Ler código de barras')), body: MobileScanner(onDetect: (capture) {
    if (found) return;
    for (final code in capture.barcodes) {
      final value = code.rawValue;
      if (value != null && value.isNotEmpty) { found = true; Navigator.pop(context, value); break; }
    }
  }));
}

Future<String?> askText(BuildContext context, String title, {String initial = ''}) async {
  String value = initial;
  return showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: TextFormField(initialValue: initial, autofocus: true, onChanged: (v) => value = v), actions: [
    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
    FilledButton(onPressed: () { if (value.trim().isNotEmpty) Navigator.pop(ctx,value.trim()); }, child: const Text('Salvar')),
  ]));
}

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key, required this.local, required this.businessId});
  final LocalDatabase local;
  final int businessId;
  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}
class _CategoriesPageState extends State<CategoriesPage> {
  List<Map<String,Object?>> rows = [];
  bool loading = true;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final data = await (await widget.local.database).query('categories', where:'business_id = ?',whereArgs:[widget.businessId],orderBy:'name');
      if (mounted) setState(() { rows = data; loading = false; });
    } catch (_) { if (mounted) { setState(() => loading = false); message(); } }
  }
  void message() => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível concluir. Verifique se o nome já existe.')));
  Future<void> edit([Map<String,Object?>? row]) async {
    final name = await askText(context, row == null ? 'Nova categoria' : 'Editar categoria', initial: row?['name'] as String? ?? '');
    if (name == null || !mounted) return;
    try {
      await (await widget.local.database).transaction((tx) async {
        if (row == null) {
          await tx.insert('categories',{'business_id':widget.businessId,'name':name});
        } else {
          await tx.update('categories',{'name':name},where:'id = ? AND business_id = ?',whereArgs:[row['id'],widget.businessId]);
          await tx.update('products',{'category':name},where:'business_id = ? AND trim(category) = ? COLLATE NOCASE',whereArgs:[widget.businessId,row['name']]);
        }
      });
      await load();
    } catch (_) { if (mounted) message(); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Categorias')),floatingActionButton: FloatingActionButton(onPressed: () => edit(),child: const Icon(Icons.add)),body: loading ? const Center(child:CircularProgressIndicator()) : ListView(children: rows.map((r) => ListTile(title:Text(r['name'].toString()),trailing:const Icon(Icons.edit),onTap:()=>edit(r))).toList()));
}

class StockPage extends StatefulWidget {
  const StockPage({super.key,required this.local,required this.businessId,required this.product});
  final LocalDatabase local;
  final int businessId;
  final Map<String,Object?> product;
  @override
  State<StockPage> createState()=>_StockPageState();
}
class _StockPageState extends State<StockPage> {
  final quantity = TextEditingController();
  final reason = TextEditingController();
  bool entry = true, busy = false;
  List<Map<String,Object?>> rows = [];
  int stock = 0;
  @override
  void initState(){super.initState();stock=widget.product['stock'] as int;load();}
  @override
  void dispose(){quantity.dispose();reason.dispose();super.dispose();}
  Future<void> load() async {
    final db=await widget.local.database;
    final p=await db.query('products',where:'id = ? AND business_id = ?',whereArgs:[widget.product['id'],widget.businessId]);
    final history=await db.query('stock_movements',where:'product_id = ? AND business_id = ?',whereArgs:[widget.product['id'],widget.businessId],orderBy:'id DESC');
    if(mounted && p.isNotEmpty) setState((){stock=p.first['stock'] as int;rows=history;});
  }
  Future<void> save() async {
    final n=int.tryParse(quantity.text.trim());
    if(n==null || n<=0 || n>2147483647 || reason.text.trim().isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Informe quantidade positiva e motivo.')));return;}
    setState(()=>busy=true);
    try{
      await widget.local.moveStock(widget.businessId,widget.product['id'] as int,entry?n:-n,reason.text.trim());
      if(mounted){quantity.clear();reason.clear();await load();}
    }catch(_){if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Não foi possível movimentar. Confira o saldo.')));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.product['name'].toString())),body:ListView(padding:const EdgeInsets.all(16),children:[
    Text('Estoque atual: $stock',style:Theme.of(context).textTheme.headlineSmall),
    SwitchListTile(title:Text(entry?'Entrada':'Saída'),value:entry,onChanged:busy?null:(v)=>setState(()=>entry=v)),
    TextField(controller:quantity,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Quantidade')),
    TextField(controller:reason,decoration:const InputDecoration(labelText:'Motivo')),
    FilledButton(onPressed:busy?null:save,child:const Text('Registrar movimentação')),
    const Divider(),const Text('Histórico'),
    ...rows.map((r)=>ListTile(title:Text('${r['delta']} unidades • ${r['reason']}'),subtitle:Text(r['created_at'].toString().replaceFirst('T',' ').split('.').first))),
  ]));
}
