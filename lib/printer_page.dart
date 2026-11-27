import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrinterPage extends StatefulWidget {
  const PrinterPage({super.key,required this.userId,this.receipt});
  final String userId;
  final String? receipt;
  @override
  State<PrinterPage> createState()=>_PrinterPageState();
}
class _PrinterPageState extends State<PrinterPage>{
  static const channel=MethodChannel('markys/printer');
  List<Map<String,String>> devices=[];
  String? address;
  int width=58;
  bool busy=false;
  String get key=>'printer_${widget.userId}';
  @override
  void initState(){super.initState();load();}
  Future<void> run(Future<void> Function() fn) async{
    if(busy)return;
    setState(()=>busy=true);
    try{await fn();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e is PlatformException?e.message??'Falha Bluetooth':e.toString())));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> load()=>run(()async{
    final prefs=await SharedPreferences.getInstance();
    if(await channel.invokeMethod<bool>('permission')!=true)throw StateError('Autorize dispositivos próximos');
    final list=await channel.invokeListMethod<dynamic>('devices')??[];
    final found=list.map((d)=>Map<String,String>.from(d as Map)).toList();
    final saved=prefs.getString(key);
    if(mounted)setState((){devices=found;address=found.any((d)=>d['address']==saved)?saved:null;width=prefs.getInt('${key}_width')==80?80:58;});
  });
  Future<void> printText(String text)=>run(()async{
    if(address==null)throw StateError('Selecione uma impressora');
    final prefs=await SharedPreferences.getInstance();
    await prefs.setString(key,address!);
    await prefs.setInt('${key}_width',width);
    final columns=width==58?32:48;
    const accented='áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const plain='aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
    final buffer=StringBuffer();
    for(final line in text.split('\n')){
      final clean=line.runes.map((r){final c=String.fromCharCode(r);final i=accented.indexOf(c);return i>=0?plain[i]:r>=32&&r<=126?c:' ';}).join();
      for(int i=0;i<clean.length;i+=columns){buffer.writeln(clean.substring(i,(i+columns).clamp(0,clean.length).toInt()));}
      if(clean.isEmpty)buffer.writeln();
    }
    final bytes=Uint8List.fromList([27,64,...buffer.toString().codeUnits,10,10,10]);
    await channel.invokeMethod<bool>('print',{'address':address,'bytes':bytes});
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Dados enviados à impressora')));
  });
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Impressora Bluetooth'),actions:[IconButton(onPressed:busy?null:load,icon:const Icon(Icons.refresh))]),body:ListView(padding:const EdgeInsets.all(16),children:[
    const Text('Pareie a impressora nas configurações Bluetooth do Android e atualize a lista.'),
    if(busy)const LinearProgressIndicator(),
    DropdownButtonFormField<String>(value:address,isExpanded:true,decoration:const InputDecoration(labelText:'Impressora pareada'),items:devices.map((d)=>DropdownMenuItem(value:d['address'],child:Text(d['name']??'',overflow:TextOverflow.ellipsis))).toList(),onChanged:busy?null:(v)=>setState(()=>address=v)),
    DropdownButtonFormField<int>(value:width,decoration:const InputDecoration(labelText:'Largura do papel'),items:[58,80].map((v)=>DropdownMenuItem(value:v,child:Text('$v mm'))).toList(),onChanged:busy?null:(v)=>setState(()=>width=v!)),
    OutlinedButton(onPressed:busy||address==null?null:()=>printText('MARKYS PDV MOBILE\nTESTE DE IMPRESSAO\nPapel: $width mm'),child:const Text('Teste de impressão')),
    if(widget.receipt!=null)FilledButton(onPressed:busy||address==null?null:()=>printText(widget.receipt!),child:const Text('Imprimir comprovante')),
  ]));
}
