import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LicenseGate extends StatefulWidget {
  const LicenseGate({super.key, required this.userId, required this.child});
  final String userId;
  final Widget child;
  @override
  State<LicenseGate> createState() => _LicenseGateState();
}
class _LicenseGateState extends State<LicenseGate> with WidgetsBindingObserver {
  bool allowed=false, busy=false;
  String reason='Verificando licença...';
  Timer? timer;
  @override
  void initState(){
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    check();
    timer=Timer.periodic(const Duration(minutes:5), (_) => check());
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.resumed) check();
  }
  @override
  void dispose(){timer?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
  Future<String> deviceId() async {
    final prefs=await SharedPreferences.getInstance();
    final old=prefs.getString('markys_license_device');
    if(old!=null)return old;
    final random=Random.secure();
    final bytes=List.generate(16, (_) => random.nextInt(256));
    bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128;
    final h=bytes.map((b)=>b.toRadixString(16).padLeft(2,'0')).join();
    final id='${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
    if(!await prefs.setString('markys_license_device',id))throw StateError('Falha ao salvar dispositivo');
    return id;
  }
  Future<void> check() async {
    if(busy||!mounted)return;
    setState(()=>busy=true);
    final client=HttpClient()..connectionTimeout=const Duration(seconds:10);
    bool ok=false;
    String message='Não foi possível validar a licença. Conecte-se à internet e tente novamente.';
    try {
      final session=Supabase.instance.client.auth.currentSession;
      if(session==null||session.user.id!=widget.userId)throw StateError('Sessão inválida');
      final request=await client.postUrl(Uri.parse('https://xwzxgazwqehcpyhrbord.supabase.co/functions/v1/validate-license')).timeout(const Duration(seconds:15));
      request.headers.set('Authorization','Bearer ${session.accessToken}');
      request.headers.contentType=ContentType.json;
      request.write(jsonEncode({'device_id':await deviceId()}));
      final response=await request.close().timeout(const Duration(seconds:15));
      final data=jsonDecode(await response.transform(utf8.decoder).join().timeout(const Duration(seconds:15)));
      if(response.statusCode==200 && data is Map){
        ok=data['allowed']==true;
        message=const {'not_registered':'Licença ainda não cadastrada.','pending':'Licença aguardando ativação.','blocked':'Licença bloqueada.','expired':'Licença vencida.','device_limit':'Limite de dispositivos atingido.','not_started':'Licença ainda não iniciada.','missing_expiration':'Validade da licença não configurada.'}[data['reason']]??'Licença não autorizada.';
      }
    }catch(_){}finally{client.close(force:true);}
    if(!mounted)return;
    if(!ok && allowed) Navigator.of(context).popUntil((route)=>route.isFirst);
    setState((){allowed=ok;reason=message;busy=false;});
  }
  @override
  Widget build(BuildContext context){
    if(allowed)return widget.child;
    return Scaffold(body:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Icon(Icons.verified_user_outlined,size:64),
      const SizedBox(height:16),
      Text('MARKYS PDV MOBILE',style:Theme.of(context).textTheme.titleLarge),
      const SizedBox(height:12),
      if(busy)const CircularProgressIndicator() else Text(reason,textAlign:TextAlign.center),
      const SizedBox(height:16),
      const Text('Código do cliente'),
      SelectableText(widget.userId),
      TextButton(onPressed:()=>Clipboard.setData(ClipboardData(text:widget.userId)),child:const Text('Copiar código')),
      FilledButton(onPressed:busy?null:check,child:const Text('Verificar licença')),
      TextButton(onPressed:()=>Supabase.instance.client.auth.signOut(),child:const Text('Sair')),
    ])))));
  }
}
