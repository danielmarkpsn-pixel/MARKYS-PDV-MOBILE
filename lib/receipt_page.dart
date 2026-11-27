import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'data/local_database.dart';
import 'sales_page.dart';
import 'printer_page.dart';

Future<void> openReceipt(BuildContext context,LocalDatabase local,int businessId,int saleId) async {
  try {
    final db=await local.database;
    final b=(await db.query('businesses',where:'id = ?',whereArgs:[businessId])).single;
    final s=(await db.rawQuery('SELECT s.*,c.name AS customer FROM sales s LEFT JOIN customers c ON c.id=s.customer_id WHERE s.id=? AND s.business_id=?',[saleId,businessId])).single;
    final items=await db.rawQuery('SELECT i.*,p.name FROM sale_items i JOIN products p ON p.id=i.product_id WHERE i.sale_id=?',[saleId]);
    final payments=await db.query('sale_payments',where:'sale_id = ?',whereArgs:[saleId]);
    final receipt=[
      b['name'].toString(),
      if((b['document']?.toString()??'').isNotEmpty)b['document'].toString(),
      if((b['address']?.toString()??'').isNotEmpty)b['address'].toString(),
      'COMPROVANTE NÃO FISCAL',
      'Venda #$saleId • ${s['status']}',
      s['created_at'].toString().replaceFirst('T',' ').split('.').first,
      'Cliente: ${s['customer']??'Consumidor final'}',
      '--------------------------------',
      ...items.map((i)=>"${i['quantity']} x ${i['name']}\n${saleMoney((i['quantity'] as int)*(i['price_cents'] as int))}"),
      '--------------------------------',
      'Desconto: ${saleMoney(s['discount_cents'] as int)}',
      'TOTAL: ${saleMoney(s['total_cents'] as int)}',
      ...payments.where((p)=>(p['amount'] as int)>0).map((p)=>"${p['method']}: ${saleMoney(p['amount'] as int)}"),
      'Obrigado pela preferência!',
    ].join('\n');
    if(context.mounted)await Navigator.push(context,MaterialPageRoute(builder:(_)=>ReceiptPage(receipt:receipt,userId:local.userId)));
  }catch(_){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Não foi possível gerar comprovante')));}
}
class ReceiptPage extends StatelessWidget {
  const ReceiptPage({super.key,required this.receipt,required this.userId});
  final String userId;
  final String receipt;
  Future<void> printReceipt(BuildContext context,double width) async {
    try{
      await Printing.layoutPdf(name:'Comprovante MARKYS',onLayout:(_)async{
        final doc=pw.Document();
        doc.addPage(pw.MultiPage(pageFormat:PdfPageFormat(width*PdfPageFormat.mm,200*PdfPageFormat.mm,marginAll:4*PdfPageFormat.mm),build:(_)=>receipt.split('\n').map((line)=>pw.Text(line,style:const pw.TextStyle(fontSize:9))).toList()));
        return doc.save();
      });
    }catch(_){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Falha ao abrir impressão')));}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Comprovante')),body:ListView(padding:const EdgeInsets.all(16),children:[
    Card(child:Padding(padding:const EdgeInsets.all(16),child:SelectableText(receipt))),
    FilledButton.icon(onPressed:()async{try{await Share.share(receipt);}catch(_){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Falha ao compartilhar')));}},icon:const Icon(Icons.share),label:const Text('Compartilhar / WhatsApp')),
    FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>PrinterPage(userId:userId,receipt:receipt))),icon:const Icon(Icons.bluetooth),label:const Text('Imprimir via Bluetooth')),
    OutlinedButton.icon(onPressed:()=>printReceipt(context,58),icon:const Icon(Icons.print),label:const Text('Imprimir 58 mm')),
    OutlinedButton.icon(onPressed:()=>printReceipt(context,80),icon:const Icon(Icons.print),label:const Text('Imprimir 80 mm')),
  ]));
}
