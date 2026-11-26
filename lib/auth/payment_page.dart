import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentPage extends StatefulWidget {
 const PaymentPage({super.key});
 @override
 State<PaymentPage> createState()=>_PaymentPageState();
}
class _PaymentPageState extends State<PaymentPage>{
 List<dynamic> plans=[], charges=[];
 Map<String,dynamic>? pix;
 String? plan;
 String message='';
 bool busy=false;
 Timer? timer;
 Future<Map<String,dynamic>> request(String endpoint,Map<String,dynamic> body) async {
  final session=Supabase.instance.client.auth.currentSession;
  if(session==null)throw StateError('Sessão encerrada');
  final client=HttpClient()..connectionTimeout=const Duration(seconds:10);
  try{
   final req=await client.postUrl(Uri.parse('https://xwzxgazwqehcpyhrbord.supabase.co/functions/v1/$endpoint')).timeout(const Duration(seconds:20));
   req.headers.set('Authorization','Bearer ${session.accessToken}');
   req.headers.contentType=ContentType.json;
   req.write(jsonEncode(body));
   final res=await req.close().timeout(const Duration(seconds:45));
   final data=jsonDecode(await res.transform(utf8.decoder).join().timeout(const Duration(seconds:20))) as Map<String,dynamic>;
   if(res.statusCode!=200)throw StateError(data['error']=='charge_unavailable'?'Já existe uma cobrança em aberto ou plano indisponível.':'Não foi possível concluir. Consulte as cobranças antes de tentar novamente.');
   if(data['environment']!='sandbox')throw StateError('Ambiente de teste obrigatório');
   return data;
  }finally{client.close(force:true);}
 }
 @override
 void initState(){super.initState();load();timer=Timer.periodic(const Duration(seconds:15),(_)=>load());}
 @override
 void dispose(){timer?.cancel();super.dispose();}
 Future<void> load() async{
  if(busy||!mounted)return;
  setState(()=>busy=true);
  try{
   final d=await request('asaas-catalog',{});
   if(!mounted)return;
   setState((){plans=d['plans'] as List? ?? [];charges=d['charges'] as List? ?? [];});
  }catch(e){if(mounted)setState(()=>message='Falha ao consultar cobranças. Tente atualizar.');}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Future<void> generate() async{
  if(busy||plan==null)return;
  setState(()=>busy=true);
  try{
   final d=await request('asaas-create-payment',{'plan_id':plan});
   if(mounted)setState(()=>pix=d);
  }catch(e){if(mounted)setState(()=>message=e.toString());}
  finally{if(mounted){setState(()=>busy=false);final previous=message;await load();if(mounted&&previous.isNotEmpty)setState(()=>message=previous);}}
 }
 String money(dynamic cents)=>'R\$ ${((num.tryParse('$cents')??0)/100).toStringAsFixed(2).replaceAll('.',',')}';
 bool get open=>charges.any((q)=>['creating','pending','received'].contains(q['status']));
 @override
 Widget build(BuildContext context){
  final received=charges.any((q)=>q['status']=='received'&&q['id']==pix?['charge_id']);
  return Scaffold(appBar:AppBar(title:const Text('Planos e pagamentos'),actions:[IconButton(onPressed:busy?null:load,icon:const Icon(Icons.refresh))]),body:ListView(padding:const EdgeInsets.all(16),children:[
   const Text('SANDBOX — somente testes. Não efetue pagamentos reais.',style:TextStyle(fontWeight:FontWeight.bold)),
   if(busy)const LinearProgressIndicator(),
   if(message.isNotEmpty)Text(message),
   for(final p in plans) RadioListTile<String>(value:p['id'].toString(),groupValue:plan,onChanged:busy?null:(v)=>setState(()=>plan=v),title:Text(p['name'].toString()),subtitle:Text(money(p['price_cents']))),
   FilledButton(onPressed:busy||plan==null||pix!=null?null:generate,child:Text(open?'Recuperar PIX existente':'Gerar PIX de teste')),
   if(pix!=null)...[
    if(pix!['encoded_image'] is String)Image.memory(base64Decode(pix!['encoded_image'] as String),height:220,errorBuilder:(_,__,___)=>const Text('QR Code indisponível')),
    SelectableText(pix!['payload']?.toString()??''),
    OutlinedButton(onPressed:()=>Clipboard.setData(ClipboardData(text:pix!['payload']?.toString()??'')),child:const Text('Copiar código PIX')),
    Text(received?'Pagamento simulado confirmado. Licença real inalterada.':'Aguardando confirmação no Sandbox.'),
   ],
   const Divider(),
   const Text('Cobranças de teste'),
   for(final q in charges)ListTile(title:Text(money(q['amount_cents'])),subtitle:Text(q['id'].toString()),trailing:Text({'creating':'Em criação','pending':'Pendente','received':'Recebido (teste)','applied':'Aplicado','review':'Em revisão','cancelled':'Cancelado'}[q['status']]??'Indefinido')),
  ]));
 }
}
