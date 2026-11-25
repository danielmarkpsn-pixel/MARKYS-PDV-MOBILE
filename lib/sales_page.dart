import 'package:flutter/material.dart';
import 'data/local_database.dart';
import 'products_page.dart';
import 'stock_tools.dart';

String saleMoney(int cents) => 'R\$ ${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')}';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key, required this.userId});
  final String userId;
  @override
  State<SalesPage> createState() => _SalesPageState();
}
class _SalesPageState extends State<SalesPage> {
  late final local = LocalDatabase.forUser(widget.userId);
  final search = TextEditingController();
  final cart = <int,int>{};
  List<Map<String,Object?>> products = [], customers = [];
  int? businessId;
  bool loading = true;
  String? error;
  @override
  void initState(){super.initState();load();}
  @override
  void dispose(){search.dispose();super.dispose();}
  Future<void> load() async {
    try {
      final b = await local.firstBusiness();
      final id = b?['id'] as int?;
      if(id==null) throw StateError('Empresa não cadastrada');
      final db=await local.database;
      final p=await db.query('products',where:'business_id = ? AND active = 1',whereArgs:[id],orderBy:'name COLLATE NOCASE');
      final c=await db.query('customers',where:'business_id = ? AND active = 1',whereArgs:[id],orderBy:'name COLLATE NOCASE');
      if(mounted)setState((){businessId=id;products=p;customers=c;loading=false;error=null;});
    }catch(_){if(mounted)setState((){loading=false;error='Não foi possível abrir o PDV';});}
  }
  int get subtotal => products.fold<int>(0,(sum,p)=>sum+(cart[p['id']]??0)*(p['sale_cents'] as int));
  void add(Map<String,Object?> p){
    final id=p['id'] as int;
    if((cart[id]??0)>=(p['stock'] as int)){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Estoque insuficiente')));return;}
    setState(()=>cart[id]=(cart[id]??0)+1);
  }
  Future<void> scan() async {
    final code=await scanBarcode(context);
    if(!mounted||code==null)return;
    final matches=products.where((p)=>p['barcode']==code).toList();
    setState(()=>search.text=code);
    if(matches.length==1)add(matches.first);
  }
  Future<void> checkout() async {
    if(cart.isEmpty||businessId==null)return;
    final result=await Navigator.push<int>(context,MaterialPageRoute(builder:(_)=>CheckoutPage(local:local,businessId:businessId!,products:products,customers:customers,cart:Map.of(cart))));
    if(!mounted)return;
    if(result!=null){setState(()=>cart.clear());await load();if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Venda #$result registrada com sucesso')));}
  }
  @override
  Widget build(BuildContext context){
    final q=search.text.trim().toLowerCase();
    final filtered=products.where((p)=>['name','barcode','sku','category'].any((k)=>(p[k]?.toString()??'').toLowerCase().contains(q))).toList();
    return Scaffold(appBar:AppBar(title:const Text('Frente de caixa')),body:loading?const Center(child:CircularProgressIndicator()):error!=null?Center(child:TextButton(onPressed:load,child:Text(error!))):Column(children:[
      Padding(padding:const EdgeInsets.all(8),child:Row(children:[Expanded(child:TextField(controller:search,onChanged:(_)=>setState((){}),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Pesquisar produtos'))),IconButton(onPressed:scan,icon:const Icon(Icons.qr_code_scanner))])),
      Expanded(child:filtered.isEmpty?const Center(child:Text('Nenhum produto encontrado')):GridView.builder(padding:const EdgeInsets.all(8),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:3,mainAxisExtent:170,crossAxisSpacing:6,mainAxisSpacing:6),itemCount:filtered.length,itemBuilder:(_,i){
        final p=filtered[i];final qty=cart[p['id']]??0;
        return Card(child:InkWell(onTap:()=>add(p),child:Padding(padding:const EdgeInsets.all(5),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
          productPhoto(p['photo_path'] as String?,56),
          Text(p['name'].toString(),maxLines:2,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center),
          Text(saleMoney(p['sale_cents'] as int),style:const TextStyle(fontWeight:FontWeight.bold)),
          Text('Estoque: ${p['stock']}',style:const TextStyle(fontSize:11)),
          if(qty>0)Text('No carrinho: $qty',style:const TextStyle(fontSize:11)),
        ]))));
      })),
      SafeArea(top:false,child:Padding(padding:const EdgeInsets.all(12),child:FilledButton.icon(onPressed:cart.isEmpty?null:checkout,icon:const Icon(Icons.shopping_cart),label:Text('${cart.values.fold<int>(0,(a,b)=>a+b)} itens • ${saleMoney(subtotal)} • Carrinho')))),
    ]));
  }
}

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key,required this.local,required this.businessId,required this.products,required this.customers,required this.cart});
  final LocalDatabase local;
  final int businessId;
  final List<Map<String,Object?>> products,customers;
  final Map<int,int> cart;
  @override
  State<CheckoutPage> createState()=>_CheckoutPageState();
}
class _CheckoutPageState extends State<CheckoutPage>{
  final discount=TextEditingController(text:'0');
  final received=TextEditingController();
  int? customer;
  String payment='Pix';
  bool busy=false;
  int get subtotal=>widget.products.fold<int>(0,(s,p)=>s+(widget.cart[p['id']]??0)*(p['sale_cents'] as int));
  int? parse(String s){final n=double.tryParse(s.trim().replaceAll(',','.'));return n==null||!n.isFinite||n<0||n>999999999?null:(n*100).round();}
  int get total=>subtotal-(parse(discount.text)??0);
  @override
  void dispose(){discount.dispose();received.dispose();super.dispose();}
  Future<void> finish() async {
    final d=parse(discount.text);
    if(busy||widget.cart.isEmpty||d==null||d>subtotal||payment=='Dinheiro'&&(parse(received.text)??-1)<total){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Confira o carrinho, desconto e pagamento')));return;}
    setState(()=>busy=true);
    try{
      final id=await widget.local.finishSale(widget.businessId,customer,widget.cart,d,payment);
      if(mounted)Navigator.pop(context,id);
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e is StateError?e.message.toString():'Não foi possível finalizar a venda')));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context)=>PopScope(canPop:!busy,child:Scaffold(appBar:AppBar(title:const Text('Carrinho e pagamento')),body:ListView(padding:const EdgeInsets.all(12),children:[
    ...widget.products.where((p)=>widget.cart.containsKey(p['id'])).map((p){
      final id=p['id'] as int;final n=widget.cart[id]!;
      return ListTile(title:Text(p['name'].toString()),subtitle:Text(saleMoney(n*(p['sale_cents'] as int))),trailing:Row(mainAxisSize:MainAxisSize.min,children:[
        IconButton(onPressed:busy?null:()=>setState((){if(n==1){widget.cart.remove(id);}else{widget.cart[id]=n-1;}}),icon:const Icon(Icons.remove)),
        Text('$n'),IconButton(onPressed:busy||n>=(p['stock'] as int)?null:()=>setState(()=>widget.cart[id]=n+1),icon:const Icon(Icons.add)),
      ]));
    }),
    const Divider(),
    DropdownButtonFormField<int>(value:customer,isExpanded:true,decoration:const InputDecoration(labelText:'Cliente'),items:[const DropdownMenuItem<int>(value:null,child:Text('Consumidor final')),...widget.customers.map((c)=>DropdownMenuItem<int>(value:c['id'] as int,child:Text(c['name'].toString(),overflow:TextOverflow.ellipsis)))],onChanged:busy?null:(v)=>setState(()=>customer=v)),
    Text('Subtotal: ${saleMoney(subtotal)}'),
    TextField(controller:discount,enabled:!busy,keyboardType:const TextInputType.numberWithOptions(decimal:true),onChanged:(_)=>setState((){}),decoration:const InputDecoration(labelText:'Desconto em reais')),
    DropdownButtonFormField<String>(value:payment,decoration:const InputDecoration(labelText:'Pagamento'),items:['Pix','Dinheiro','Débito','Crédito'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:busy?null:(v)=>setState(()=>payment=v!)),
    if(payment=='Dinheiro')...[
      TextField(controller:received,enabled:!busy,keyboardType:const TextInputType.numberWithOptions(decimal:true),onChanged:(_)=>setState((){}),decoration:const InputDecoration(labelText:'Valor recebido')),
      Text('Troco: ${saleMoney(((parse(received.text)??0)-total).clamp(0,999999999).toInt())}'),
    ],
    const SizedBox(height:12),
    Text('Total: ${saleMoney(total)}',style:Theme.of(context).textTheme.headlineSmall),
    FilledButton(onPressed:busy||widget.cart.isEmpty?null:finish,child:Text(busy?'Finalizando...':'Finalizar venda')),
  ])));
}
