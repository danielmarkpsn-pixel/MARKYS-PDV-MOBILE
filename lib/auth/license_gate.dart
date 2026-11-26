import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'lease_verifier.dart';
import 'payment_page.dart';
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
  Timer? timer, deadline;
  final storage=const FlutterSecureStorage();
  String get cacheKey=>'markys_lease_${widget.userId}';
  Future<Map<dynamic,dynamic>> clock() async =>
    (await const MethodChannel('markys/license_clock').invokeMapMethod<dynamic,dynamic>('snapshot'))!;
  Future<int> remaining(String device) async {
    try {
      final raw=await storage.read(key:cacheKey);
      if(raw==null)return 0;
      final record=jsonDecode(raw);
      final lifetime=LeaseVerifier.verify(record['token'] as String,widget.userId,device);
      final now=await clock();
      final start=record['elapsed'] as int;
      final elapsed=now['elapsed'] as int;
      if(lifetime==null||now['boot']!=record['boot']||elapsed<start)return 0;
      return max(0,lifetime*1000-(elapsed-start)-1000);
    }catch(_){return 0;}
  }
  void expire(){
    if(!mounted)return;
    if(allowed)Navigator.of(context).popUntil((route)=>route.isFirst);
    setState((){allowed=false;reason='Validação online necessária.';});
  }
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
  void dispose(){timer?.cancel();deadline?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
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
    bool ok=false, transient=false;
    int offlineRemaining=0;
    String? device;
    Map<dynamic,dynamic>? started;
    String message='Não foi possível validar a licença. Conecte-se à internet e tente novamente.';
    try {
      final session=Supabase.instance.client.auth.currentSession;
      if(session==null||session.user.id!=widget.userId)throw StateError('Sessão inválida');
      device=await deviceId();
      try{started=await clock();}catch(_){}
      final request=await client.postUrl(Uri.parse('https://xwzxgazwqehcpyhrbord.supabase.co/functions/v1/validate-license')).timeout(const Duration(seconds:15));
      request.headers.set('Authorization','Bearer ${session.accessToken}');
      request.headers.contentType=ContentType.json;
      request.write(jsonEncode({'device_id':device}));
      final response=await request.close().timeout(const Duration(seconds:15));
      transient=response.statusCode>=500;
      final data=jsonDecode(await response.transform(utf8.decoder).join().timeout(const Duration(seconds:15)));
      if(response.statusCode==200 && data is Map){
        ok=data['allowed']==true;
        try {await storage.delete(key:cacheKey);}catch(_){}
        final token=data['offline_lease'];
        if(ok&&token is String&&started!=null&&LeaseVerifier.verify(token,widget.userId,device)!=null){
          try {await storage.write(key:cacheKey,value:jsonEncode({'token':token,'boot':started['boot'],'elapsed':started['elapsed']}));}catch(_){}
          offlineRemaining=await remaining(device);
        }
        message=const {'profile_required':'Cadastro incompleto: nome, telefone e CPF/CNPJ necessários.','email_unconfirmed':'Confirme seu e-mail.','trial_registration_failed':'Não foi possível cadastrar o período de teste. Contate o suporte.','not_registered':'Licença ainda não cadastrada.','pending':'Licença aguardando ativação.','blocked':'Licença bloqueada.','expired':'Licença vencida.','device_limit':'Limite de dispositivos atingido.','not_started':'Licença ainda não iniciada.','missing_expiration':'Validade da licença não configurada.'}[data['reason']]??'Licença não autorizada.';
      }
      else if(!transient){await storage.delete(key:cacheKey);message='Falha na validação (HTTP ${response.statusCode}). Entre novamente ou contate o suporte.';}
    }on SocketException{transient=true;}on TimeoutException{transient=true;}catch(_){ok=false;}finally{client.close(force:true);}
    if(transient&&device!=null){
      offlineRemaining=await remaining(device);
      ok=offlineRemaining>0;
    }
    deadline?.cancel();
    if(ok)deadline=Timer(Duration(milliseconds:offlineRemaining>0?offlineRemaining:300000),expire);
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
      OutlinedButton(onPressed:busy?null:() async {await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const PaymentPage()));if(mounted)await check();},child:const Text('Planos e pagamentos')),
      TextButton(onPressed:()=>Supabase.instance.client.auth.signOut(),child:const Text('Sair')),
    ])))));
  }
}
