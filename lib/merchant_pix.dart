import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';

class MerchantPix {
  final String key, name, city;
  const MerchantPix(this.key,this.name,this.city);
  static String clean(String s)=>s.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9 ]'),'');
  static bool validKey(String s)=>s.length<=77 && (RegExp(r'^\d{11}$|^\d{14}$|^\+[1-9]\d{7,14}$|^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(s)||RegExp(r'^[!-~]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$').hasMatch(s));
  static Future<MerchantPix?> load(String user) async {
    final p=await SharedPreferences.getInstance();
    final k=p.getString('pix_key_$user'), n=p.getString('pix_name_$user'), c=p.getString('pix_city_$user');
    if(k==null||n==null||c==null||!validKey(k)||n.isEmpty||n.length>25||c.isEmpty||c.length>15)return null;
    return MerchantPix(k,n,c);
  }
  static String tlv(String id,String value)=>id+value.length.toString().padLeft(2,'0')+value;
  String payload(int cents){
    if(cents<=0||cents>99999999999)throw ArgumentError('Valor PIX inválido');
    final value='${cents~/100}.${(cents%100).toString().padLeft(2,'0')}';
    final data=tlv('00','01')+tlv('26',tlv('00','br.gov.bcb.pix')+tlv('01',key))+tlv('52','0000')+tlv('53','986')+tlv('54',value)+tlv('58','BR')+tlv('59',name)+tlv('60',city)+tlv('62',tlv('05','***'))+'6304';
    int crc=0xffff;
    for(final b in data.codeUnits){crc^=b<<8;for(int i=0;i<8;i++){crc=((crc&0x8000)!=0?(crc<<1)^0x1021:crc<<1)&0xffff;}}
    return data+crc.toRadixString(16).padLeft(4,'0').toUpperCase();
  }
  static Future<bool> confirm(BuildContext context,String user,int cents) async {
    final pix=await load(user);
    if(!context.mounted)return false;
    if(pix==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Cadastre sua chave PIX em Configurações.')));return false;}
    final code=pix.payload(cents);
    return await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Receber PIX'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text('R\$ ${(cents/100).toStringAsFixed(2).replaceAll('.',',')}'),
      Text(pix.name),Container(color:Colors.white,padding:const EdgeInsets.all(8),child:QrImageView(data:code,size:220)),
      TextButton(onPressed:()=>Clipboard.setData(ClipboardData(text:code)),child:const Text('Copiar código PIX')),
      const Text('Confira o crédito na sua conta bancária. O QR Code não confirma o pagamento.'),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirmei o recebimento'))]))??false;
  }
}
class MerchantPixPage extends StatefulWidget {
  final String userId;
  const MerchantPixPage({super.key,required this.userId});
  @override State<MerchantPixPage> createState()=>_MerchantPixPageState();
}
class _MerchantPixPageState extends State<MerchantPixPage>{
  final keyField=TextEditingController(),name=TextEditingController(),city=TextEditingController();
  bool busy=true;
  @override void initState(){super.initState();load();}
  Future<void> load()async{try{final p=await MerchantPix.load(widget.userId);if(mounted&&p!=null){keyField.text=p.key;name.text=p.name;city.text=p.city;}}finally{if(mounted)setState(()=>busy=false);}}
  @override void dispose(){keyField.dispose();name.dispose();city.dispose();super.dispose();}
  Future<void> save()async{
    final k=keyField.text.trim(),n=MerchantPix.clean(name.text),c=MerchantPix.clean(city.text);
    if(!MerchantPix.validKey(k)||n.isEmpty||n.length>25||c.isEmpty||c.length>15){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Confira a chave, nome (25 caracteres) e cidade (15 caracteres), sem acentos.')));return;}
    setState(()=>busy=true);
    try{final p=await SharedPreferences.getInstance();final u=widget.userId;
    if(!await p.setString('pix_key_$u',k)||!await p.setString('pix_name_$u',n)||!await p.setString('pix_city_$u',c))throw StateError('Falha ao salvar');
    if(mounted)Navigator.pop(context);
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Falha ao salvar PIX')));}finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('PIX do comerciante')),body:ListView(padding:const EdgeInsets.all(16),children:[
    const Text('Informe uma chave registrada na sua conta. CPF/CNPJ sem pontuação, telefone com +55, e-mail ou chave aleatória.'),
    TextField(controller:keyField,enabled:!busy,decoration:const InputDecoration(labelText:'Chave PIX')),
    TextField(controller:name,enabled:!busy,maxLength:25,decoration:const InputDecoration(labelText:'Nome do beneficiário sem acentos')),
    TextField(controller:city,enabled:!busy,maxLength:15,decoration:const InputDecoration(labelText:'Cidade sem acentos')),
    FilledButton(onPressed:busy?null:save,child:const Text('Salvar PIX')),
  ]));
}
