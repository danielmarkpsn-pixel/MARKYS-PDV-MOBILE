import 'package:flutter/material.dart';
import 'data/local_database.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key, required this.userId});
  final String userId;
  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  late final local = LocalDatabase.forUser(widget.userId);
  final search = TextEditingController();
  List<Map<String,Object?>> rows = [];
  int? businessId;
  bool loading = true;
  String? error;
  String filter = 'Todos';

  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { search.dispose(); super.dispose(); }

  Future<void> load() async {
    try {
      final business = await local.firstBusiness();
      final id = business?['id'] as int?;
      if (id == null) throw StateError('Empresa não cadastrada');
      final data = await (await local.database).query('customers', where: 'business_id = ?', whereArgs: [id], orderBy: 'name COLLATE NOCASE');
      if (mounted) setState(() { rows = data; businessId = id; loading = false; error = null; });
    } catch (_) {
      if (mounted) setState(() { loading = false; error = 'Não foi possível carregar os clientes.'; });
    }
  }

  Future<void> edit([Map<String,Object?>? row]) async {
    final id = businessId;
    if (id == null) return;
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => CustomerForm(local: local, businessId: id, customer: row)));
    if (mounted && saved == true) await load();
  }

  @override
  Widget build(BuildContext context) {
    final q = search.text.trim().toLowerCase();
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    final filtered = rows.where((r) {
      final active = r['active'] == 1;
      if (filter == 'Ativos' && !active || filter == 'Inativos' && active) return false;
      return ['name','document','phone','whatsapp','email'].any((k) => (r[k]?.toString() ?? '').toLowerCase().contains(q)) ||
        (digits.isNotEmpty && RegExp(r'^[0-9(). /+-]+$').hasMatch(q) && ['document','phone','whatsapp'].any((k) => (r[k]?.toString() ?? '').replaceAll(RegExp(r'[^0-9]'), '').contains(digits)));
    }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      floatingActionButton: businessId == null ? null : FloatingActionButton.extended(onPressed: () => edit(), icon: const Icon(Icons.person_add), label: const Text('Novo cliente')),
      body: loading ? const Center(child: CircularProgressIndicator()) : error != null ? Center(child: TextButton(onPressed: load, child: Text(error!))) : Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(controller: search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Nome, CPF/CNPJ ou telefone'))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
          Expanded(child: Text('${rows.where((r) => r['active'] == 1).length} clientes ativos')),
          DropdownButton<String>(value: filter, items: ['Todos','Ativos','Inativos'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) { if (v != null) setState(() => filter = v); }),
        ])),
        Expanded(child: filtered.isEmpty ? const Center(child: Text('Nenhum cliente encontrado')) : ListView.builder(padding: const EdgeInsets.only(bottom: 88), itemCount: filtered.length, itemBuilder: (_, i) {
          final r = filtered[i];
          final details = [r['document'], r['phone'], r['whatsapp']].where((v) => v != null && v.toString().isNotEmpty).join(' • ');
          return Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.person_outline)), title: Text(r['name'].toString()), subtitle: Text(details.isEmpty ? (r['active'] == 1 ? 'Ativo' : 'Inativo') : '$details\n${r['active'] == 1 ? 'Ativo' : 'Inativo'}'), trailing: const Icon(Icons.edit_outlined), onTap: () => edit(r)));
        })),
      ]),
    );
  }
}

class CustomerForm extends StatefulWidget {
  const CustomerForm({super.key, required this.local, required this.businessId, this.customer});
  final LocalDatabase local;
  final int businessId;
  final Map<String,Object?>? customer;
  @override
  State<CustomerForm> createState() => _CustomerFormState();
}
class _CustomerFormState extends State<CustomerForm> {
  final form = GlobalKey<FormState>();
  late final Map<String,TextEditingController> fields;
  late bool active;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    fields = {for (final k in ['name','document','phone','whatsapp','email','address','notes']) k: TextEditingController(text: widget.customer?[k]?.toString() ?? '')};
    active = widget.customer?['active'] != 0;
  }
  @override
  void dispose() { for (final c in fields.values) { c.dispose(); } super.dispose(); }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final db = await widget.local.database;
      final data = <String,Object?>{'business_id':widget.businessId, for(final k in fields.keys) k: fields[k]!.text.trim(), 'active':active ? 1 : 0};
      await db.transaction((tx) async {
        final doc = fields['document']!.text.replaceAll(RegExp(r'[^0-9]'), '');
        if (doc.isNotEmpty) {
          final existing = await tx.query('customers', columns:['id','document'], where:'business_id = ?', whereArgs:[widget.businessId]);
          if (existing.any((r) => r['id'] != widget.customer?['id'] && (r['document']?.toString() ?? '').replaceAll(RegExp(r'[^0-9]'), '') == doc)) throw StateError('Documento já cadastrado');
        }
        if (widget.customer == null) {
          await tx.insert('customers',data);
        } else {
          final count = await tx.update('customers',data,where:'id = ? AND business_id = ?',whereArgs:[widget.customer!['id'],widget.businessId]);
          if (count != 1) throw StateError('Cliente não encontrado');
        }
      });
      if (mounted) Navigator.pop(context,true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e is StateError ? e.message.toString() : 'Não foi possível salvar o cliente.')));
    } finally { if (mounted) setState(() => saving = false); }
  }
  Widget field(String key,String label,{TextInputType? keyboard,String? Function(String?)? validator,int lines=1}) => Padding(padding:const EdgeInsets.only(bottom:12),child:TextFormField(controller:fields[key],enabled:!saving,keyboardType:keyboard,validator:validator,maxLines:lines,decoration:InputDecoration(labelText:label)));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:Text(widget.customer == null ? 'Cadastrar cliente' : 'Editar cliente')),
    body:Form(key:form,child:ListView(padding:const EdgeInsets.all(16),children:[
      field('name','Nome completo / razão social *',validator:(v)=>v==null||v.trim().isEmpty?'Informe o nome':null),
      field('document','CPF / CNPJ',keyboard:TextInputType.number,validator:(v){final s=v?.trim()??'';final n=s.replaceAll(RegExp(r'[^0-9]'),'');return s.isEmpty||n.length==11||n.length==14?null:'Informe 11 ou 14 dígitos';}),
      field('phone','Telefone',keyboard:TextInputType.phone),
      field('whatsapp','WhatsApp',keyboard:TextInputType.phone),
      field('email','E-mail',keyboard:TextInputType.emailAddress,validator:(v){final s=v?.trim()??'';return s.isEmpty||s.contains('@')?null:'E-mail inválido';}),
      field('address','Endereço',lines:2),
      field('notes','Observações',lines:3),
      SwitchListTile(title:const Text('Cliente ativo'),value:active,onChanged:saving?null:(v)=>setState(()=>active=v)),
      FilledButton(onPressed:saving?null:save,child:Text(saving?'Salvando...':'Salvar cliente')),
    ])),
  );
}
