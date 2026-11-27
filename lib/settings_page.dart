import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'data/local_database.dart';
import 'printer_page.dart';
import 'merchant_pix.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key,required this.userId});
  final String userId;
  @override
  State<SettingsPage> createState()=>_SettingsPageState();
}
class _SettingsPageState extends State<SettingsPage>{
  late final local=LocalDatabase.forUser(widget.userId);
  static const tables=['businesses','categories','products','customers','sales','sale_items','sale_payments','debt_receipts','stock_movements','open_orders'];
  bool busy=false;
  void notify(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  Future<void> run(Future<void> Function() task) async{
    if(busy)return;
    setState(()=>busy=true);
    try{await task();}catch(e){notify('Operação não concluída: ${e is FormatException ? e.message : 'verifique o arquivo e o espaço disponível'}');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> backup() async{
    final db=await local.database;
    final data=await db.transaction((tx)async{
      final result=<String,List<Map<String,Object?>>>{};
      for(final t in tables){result[t]=(await tx.query(t)).map((r)=>Map<String,Object?>.of(r)).toList();}
      return result;
    });
    final root=p.join((await getApplicationDocumentsDirectory()).path,'product_photos',widget.userId);
    final photos=<String,String>{};
    for(final row in data['products']!){
      final path=row['photo_path'] as String?;
      if(path==null||path.isEmpty){row['photo_path']=null;continue;}
      if(!p.isWithin(root,p.normalize(path))||!await File(path).exists())throw const FormatException('Foto de produto indisponível; confira o cadastro.');
      final key=row['id'].toString();
      photos[key]=base64Encode(await File(path).readAsBytes());
      row['photo_path']=key;
    }
    final file=File(p.join((await getTemporaryDirectory()).path,'markys_${DateTime.now().millisecondsSinceEpoch}.markys'));
    await file.writeAsString(jsonEncode({'format':1,'schema':5,'owner':widget.userId,'tables':data,'photos':photos}),flush:true);
    await Share.shareXFiles([XFile(file.path)],text:'Backup MARKYS — contém dados privados');
  }
  Future<void> restore() async{
    final picked=await FilePicker.platform.pickFiles(type:FileType.any,allowMultiple:false);
    if(picked==null)return;
    final path=picked.files.single.path;
    if(path==null)throw const FormatException('Arquivo indisponível');
    final file=File(path);
    if(await file.length()>150*1024*1024)throw const FormatException('Arquivo superior a 150 MB');
    final doc=jsonDecode(await file.readAsString()) as Map<String,dynamic>;
    if(doc['format']!=1||doc['schema']!=5||doc['owner']!=widget.userId)throw const FormatException('Backup incompatível ou de outra conta');
    final data=doc['tables'] as Map<String,dynamic>;
    final photos=doc['photos'] as Map<String,dynamic>;
    if(data.length!=tables.length||!tables.every(data.containsKey)||(data['businesses'] as List).length!=1)throw const FormatException('Estrutura inválida');
    if(!mounted)return;
    final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Substituir dados locais?'),content:const Text('A restauração substitui todos os registros desta conta. Guarde uma cópia atual antes de continuar.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Restaurar'))]));
    if(yes!=true)return;
    final db=await local.database;
    final root=await Directory(p.join((await getApplicationDocumentsDirectory()).path,'product_photos',widget.userId)).create(recursive:true);
    final staged=<File>[];
    try{
      final rows=<String,List<Map<String,Object?>>>{};
      for(final t in tables){
        final cols=(await db.rawQuery('PRAGMA table_info($t)')).map((r)=>r['name']).toSet();
        rows[t]=(data[t] as List).map((r){
          final row=Map<String,Object?>.from(r as Map);
          if(row.keys.toSet().length!=cols.length||!row.keys.every(cols.contains))throw const FormatException('Colunas incompatíveis');
          return row;
        }).toList();
      }
      for(final row in rows['products']!){
        final key=row['photo_path'];
        if(key==null)continue;
        if(key!=row['id'].toString()||photos[key] is! String)throw const FormatException('Foto inválida');
        final bytes=base64Decode(photos[key] as String);
        if(bytes.length>10*1024*1024)throw const FormatException('Foto superior a 10 MB');
        final f=File(p.join(root.path,'restore_${DateTime.now().microsecondsSinceEpoch}_${staged.length}.img'));
        staged.add(f);await f.writeAsBytes(bytes,flush:true);row['photo_path']=f.path;
      }
      await db.transaction((tx)async{
        for(final t in tables.reversed){await tx.delete(t);}
        for(final t in tables){for(final row in rows[t]!){await tx.insert(t,row);}}
        if((await tx.rawQuery('PRAGMA foreign_key_check')).isNotEmpty)throw const FormatException('Vínculos inválidos');
      });
    }catch(_){for(final f in staged){try{await f.delete();}catch(_){}}rethrow;}
    notify('Backup restaurado');
    if(mounted)Navigator.pop(context,true);
  }
  Future<void> editBusiness() async{
    final b=await local.firstBusiness();
    if(b==null||!mounted)return;
    final fields={for(final k in ['name','document','phone','email','address','segment'])k:TextEditingController(text:b[k]?.toString()??'')};
    final labels=['Nome da empresa','CPF/CNPJ','Telefone','E-mail','Endereço','Segmento'];
    try{
      final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Dados da empresa'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[for(final e in fields.entries.toList().asMap().entries)TextField(controller:e.value.value,decoration:InputDecoration(labelText:labels[e.key]))])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),FilledButton(onPressed:(){if(fields['name']!.text.trim().isNotEmpty)Navigator.pop(ctx,true);},child:const Text('Salvar'))]));
      if(ok==true){await (await local.database).update('businesses',{for(final e in fields.entries)e.key:e.value.text.trim()},where:'id = ?',whereArgs:[b['id']]);if(mounted)Navigator.pop(context,true);}
    }finally{for(final c in fields.values){c.dispose();}}
  }
  @override
  Widget build(BuildContext context)=>PopScope(canPop:!busy,child:Scaffold(appBar:AppBar(title:const Text('Configurações')),body:ListView(padding:const EdgeInsets.all(16),children:[
    if(busy)const LinearProgressIndicator(),
    ListTile(leading:const Icon(Icons.qr_code),title:const Text('PIX do comerciante'),onTap:busy?null:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>MerchantPixPage(userId:widget.userId)))),
    ListTile(leading:const Icon(Icons.print),title:const Text('Impressora Bluetooth'),onTap:busy?null:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>PrinterPage(userId:widget.userId)))),
    ListTile(leading:const Icon(Icons.store),title:const Text('Dados da empresa'),onTap:busy?null:()=>run(editBusiness)),
    ListTile(leading:const Icon(Icons.backup),title:const Text('Criar backup'),subtitle:const Text('Exportar dados e fotos para um arquivo'),onTap:busy?null:()=>run(backup)),
    ListTile(leading:const Icon(Icons.restore),title:const Text('Restaurar backup'),subtitle:const Text('Substituir os dados desta conta'),onTap:busy?null:()=>run(restore)),
    const Text('O arquivo contém informações privadas e não é criptografado. Guarde-o em local seguro.'),
  ])));
}
