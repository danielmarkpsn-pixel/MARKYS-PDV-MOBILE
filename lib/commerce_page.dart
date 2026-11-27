import 'dart:convert';
import 'package:flutter/material.dart';
import 'data/local_database.dart';
import 'sales_page.dart';
import 'receipt_page.dart';

class CommercePage extends StatefulWidget {
  const CommercePage({super.key,required this.userId,required this.mode});
  final String userId,mode;
  @override
  State<CommercePage> createState()=>_CommercePageState();
}
class _CommercePageState extends State<CommercePage>{
  late final local=LocalDatabase.forUser(widget.userId);
  int? businessId;
  List<Map<String,Object?>> rows=[];
  bool loading=true,busy=false;
  String? error;
  bool get orders=>widget.mode=='Pedidos';
  bool get finance=>widget.mode=='Finanças';
  @override
  void initState(){super.initState();load();}
  Future<void> load() async{
    try{
      final id=(await local.firstBusiness())?['id'] as int?;
      final db=await local.database;
      final data=orders?await db.query('open_orders',where:'business_id = ?',whereArgs:[id],orderBy:'id DESC'):await db.rawQuery("SELECT s.*,c.name AS customer,COALESCE((SELECT SUM(amount) FROM sale_payments WHERE sale_id=s.id AND method='Fiado'),0)-COALESCE((SELECT SUM(amount) FROM debt_receipts WHERE sale_id=s.id),0) AS balance FROM sales s LEFT JOIN customers c ON c.id=s.customer_id WHERE s.business_id=? ORDER BY s.id DESC",[id]);
      if(mounted)setState((){businessId=id;rows=data;loading=false;error=null;});
    }catch(_){if(mounted)setState((){loading=false;error='Não foi possível carregar os registros';});}
  }
  Future<void> action(Future<void> Function() fn) async{
    if(busy)return;
    setState(()=>busy=true);
    try{await fn();await load();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e is StateError?e.message.toString():'Não foi possível concluir')));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<bool> confirm(String message) async=>await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(content:Text(message),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Voltar')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirmar'))]))??false;
  Future<void> openOrder(Map<String,Object?> r) async{
    final raw=jsonDecode(r['cart_json'] as String) as Map<String,dynamic>;
    final cart=raw.map((k,v)=>MapEntry(int.parse(k),v as int));
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>SalesPage(userId:widget.userId,orderId:r['id'] as int,initialCart:cart)));
    if(mounted)await load();
  }
  Future<void> details(Map<String,Object?> r) async{
    final db=await local.database;
    final items=await db.rawQuery('SELECT i.*,p.name FROM sale_items i JOIN products p ON p.id=i.product_id WHERE i.sale_id=?',[r['id']]);
    final payments=await db.query('sale_payments',where:'sale_id = ?',whereArgs:[r['id']]);
    if(!mounted)return;
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:Text('Venda #${r['id']}'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      ...items.map((i)=>Text('${i['quantity']} × ${i['name']} — ${saleMoney((i['quantity'] as int)*(i['price_cents'] as int))}')),
      const Divider(),Text('Desconto: ${saleMoney(r['discount_cents'] as int)}'),
      ...payments.where((p)=>(p['amount'] as int)>0).map((p)=>Text('${p['method']}: ${saleMoney(p['amount'] as int)}')),
      Text('Total: ${saleMoney(r['total_cents'] as int)}'),
    ])),actions:[TextButton(onPressed:(){Navigator.pop(ctx);openReceipt(context,local,businessId!,r['id'] as int);},child:const Text('Comprovante')),TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Fechar'))]));
  }
  Future<void> receive(Map<String,Object?> r) async{
    String value='',method='Pix';
    final amount=await showDialog<int>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,set)=>AlertDialog(title:const Text('Receber fiado'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      Text('Saldo: ${saleMoney(r['balance'] as int)}'),
      TextField(keyboardType:const TextInputType.numberWithOptions(decimal:true),onChanged:(v)=>value=v,decoration:const InputDecoration(labelText:'Valor recebido')),
      DropdownButton<String>(value:method,items:['Pix','Dinheiro','Débito','Crédito'].map((m)=>DropdownMenuItem(value:m,child:Text(m))).toList(),onChanged:(v)=>set(()=>method=v!)),
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),FilledButton(onPressed:(){final n=double.tryParse(value.replaceAll(',','.'));if(n!=null&&n.isFinite&&n>0&&n<=999999999)Navigator.pop(ctx,(n*100).round());},child:const Text('Receber'))])));
    if(amount!=null&&mounted)await action(()=>local.receiveDebt(businessId!,r['id'] as int,amount,method));
  }
  @override
  Widget build(BuildContext context){
    final active=rows.where((r)=>r['status']=='Concluída');
    final debts=active.where((r)=>(r['balance'] as int)>0).toList();
    final gross=active.fold<int>(0,(s,r)=>s+(r['total_cents'] as int));
    final due=debts.fold<int>(0,(s,r)=>s+(r['balance'] as int));
    return Scaffold(appBar:AppBar(title:Text(widget.mode)),floatingActionButton:orders?FloatingActionButton(onPressed:busy?null:()async{await Navigator.push(context,MaterialPageRoute(builder:(_)=>SalesPage(userId:widget.userId)));if(mounted)await load();},child:const Icon(Icons.add)):null,body:loading?const Center(child:CircularProgressIndicator()):error!=null?Center(child:TextButton(onPressed:load,child:Text(error!))):ListView(padding:const EdgeInsets.all(12),children:[
      if(finance)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[Text('Vendas concluídas: ${saleMoney(gross)}'),Text('A receber: ${saleMoney(due)}'),Text('Recebido: ${saleMoney(gross-due)}')]))),
      if((finance?debts:rows).isEmpty)const Center(child:Text('Nenhum registro')),
      ...(finance?debts:rows).map((r)=>Card(child:ListTile(
        title:Text(orders?'Pedido #${r['id']}':'Venda #${r['id']} • ${r['customer']??'Consumidor final'}'),
        subtitle:Text(orders?r['created_at'].toString():'${saleMoney(r['total_cents'] as int)} • ${r['status']}\n${r['created_at']}${finance?'\nSaldo: ${saleMoney(r['balance'] as int)}':''}'),
        onTap:busy?null:()=>orders?openOrder(r):details(r),
        trailing:finance?TextButton(onPressed:busy?null:()=>receive(r),child:const Text('Receber')):IconButton(icon:Icon(orders?Icons.delete_outline:Icons.cancel_outlined),onPressed:busy||!orders&&r['status']!='Concluída'?null:()async{
          if(!await confirm(orders?'Excluir pedido?':'Cancelar venda e devolver itens ao estoque?')||!mounted)return;
          await action(()async{if(orders){await (await local.database).delete('open_orders',where:'id = ? AND business_id = ?',whereArgs:[r['id'],businessId]);}else{await local.cancelSale(businessId!,r['id'] as int);}});
        }),
      ))),
    ]));
  }
}
