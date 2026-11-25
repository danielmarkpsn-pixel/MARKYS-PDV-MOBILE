import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'data/local_database.dart';
import 'sales_page.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key,required this.userId});
  final String userId;
  @override
  State<ReportsPage> createState()=>_ReportsPageState();
}
class _ReportsPageState extends State<ReportsPage>{
  late final local=LocalDatabase.forUser(widget.userId);
  DateTimeRange range=DateTimeRange(start:DateTime(DateTime.now().year,DateTime.now().month),end:DateTime.now());
  List<Map<String,Object?>> sales=[],items=[],payments=[];
  bool busy=true;
  String? error;
  @override
  void initState(){super.initState();load();}
  Future<void> load() async{
    setState(()=>busy=true);
    try{
      final id=(await local.firstBusiness())?['id'];
      final db=await local.database;
      final start=DateTime(range.start.year,range.start.month,range.start.day).toIso8601String();
      final end=DateTime(range.end.year,range.end.month,range.end.day+1).toIso8601String();
      const condition="s.business_id=? AND s.status='Concluída' AND s.created_at>=? AND s.created_at<?";
      final args=[id,start,end];
      final s=await db.rawQuery('SELECT s.* FROM sales s WHERE $condition ORDER BY s.created_at DESC',args);
      final i=await db.rawQuery('SELECT p.name,SUM(i.quantity) AS quantity,SUM(i.quantity*i.price_cents) AS gross FROM sale_items i JOIN sales s ON s.id=i.sale_id JOIN products p ON p.id=i.product_id WHERE $condition GROUP BY p.id ORDER BY quantity DESC',args);
      final p=await db.rawQuery('SELECT p.method,SUM(p.amount) AS amount FROM sale_payments p JOIN sales s ON s.id=p.sale_id WHERE $condition GROUP BY p.method ORDER BY amount DESC',args);
      if(mounted)setState((){sales=s;items=i;payments=p;error=null;});
    }catch(_){if(mounted)setState(()=>error='Não foi possível gerar o relatório');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  String date(DateTime d)=>'${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
  Future<void> export() async{
    try{
      final dir=await getTemporaryDirectory();
      final file=File('${dir.path}/vendas_markys.csv');
      final lines=['Venda;Data;Total (R\$);Desconto (R\$)',...sales.map((s)=>"${s['id']};${s['created_at']};${((s['total_cents'] as int)/100).toStringAsFixed(2).replaceAll('.',',')};${((s['discount_cents'] as int)/100).toStringAsFixed(2).replaceAll('.',',')}")];
      await file.writeAsString('\uFEFF${lines.join('\r\n')}');
      await Share.shareXFiles([XFile(file.path)],text:'Relatório de vendas MARKYS');
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Falha ao compartilhar relatório')));}
  }
  @override
  Widget build(BuildContext context){
    final total=sales.fold<int>(0,(a,s)=>a+(s['total_cents'] as int));
    final discount=sales.fold<int>(0,(a,s)=>a+(s['discount_cents'] as int));
    return Scaffold(appBar:AppBar(title:const Text('Estatísticas'),actions:[IconButton(onPressed:busy||error!=null?null:export,icon:const Icon(Icons.share),tooltip:'Exportar CSV')]),body:ListView(padding:const EdgeInsets.all(12),children:[
      OutlinedButton.icon(onPressed:busy?null:()async{final r=await showDateRangePicker(context:context,firstDate:DateTime(2000),lastDate:DateTime.now(),initialDateRange:range);if(r!=null&&mounted){setState(()=>range=r);await load();}},icon:const Icon(Icons.date_range),label:Text('${date(range.start)} a ${date(range.end)}')),
      if(busy)const LinearProgressIndicator() else if(error!=null)TextButton(onPressed:load,child:Text(error!)) else ...[
        Card(child:Column(children:[ListTile(title:const Text('Vendas líquidas de descontos'),trailing:Text(saleMoney(total))),ListTile(title:const Text('Vendas concluídas'),trailing:Text('${sales.length}')),ListTile(title:const Text('Ticket médio'),trailing:Text(saleMoney(sales.isEmpty?0:(total/sales.length).round()))),ListTile(title:const Text('Descontos'),trailing:Text(saleMoney(discount)))])),
        const Text('Produtos mais vendidos (unidades)'),
        ...items.map((i)=>ListTile(title:Text(i['name'].toString()),subtitle:LinearProgressIndicator(value:(i['quantity'] as num)/(items.first['quantity'] as num)),trailing:Text('${i['quantity']}'))),
        const Divider(),const Text('Formas de pagamento na venda'),
        ...payments.map((p)=>ListTile(title:Text(p['method'].toString()),trailing:Text(saleMoney(p['amount'] as int)))),
      ],
    ]));
  }
}
