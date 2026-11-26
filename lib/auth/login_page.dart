import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const authRedirect = 'com.markys.pdvmobile://login-callback/';
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.recovery = false, this.onRecovered});
  final bool recovery;
  final VoidCallback? onRecovered;
  @override
  State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final phone = TextEditingController();
  final document = TextEditingController();
  final confirmation = TextEditingController();
  bool signup = false;
  bool busy = false;
  bool hidden = true;
  @override
  void dispose() { email.dispose(); password.dispose(); name.dispose(); phone.dispose(); document.dispose(); confirmation.dispose(); super.dispose(); }
  void notify(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
  Future<void> act(String mode) async {
    final address = email.text.trim();
    if (mode != 'google' && mode != 'update' && !address.contains('@')) {
      notify('Informe um e-mail válido.'); return;
    }
    if (['login','signup','update'].contains(mode) && password.text.length < 6) {
      notify('Informe uma senha com pelo menos 6 caracteres.'); return;
    }
    final doc=document.text.replaceAll(RegExp(r'\D'),'');
    if(mode=='signup' && (name.text.trim().length<2 || phone.text.replaceAll(RegExp(r'\D'),'').length<10 || ![11,14].contains(doc.length) || confirmation.text!=password.text)){
      notify('Confira nome, telefone, CPF/CNPJ e confirmação da senha.'); return;
    }
    setState(() => busy = true);
    final auth = Supabase.instance.client.auth;
    try {
      switch (mode) {
        case 'login':
          await auth.signInWithPassword(email: address, password: password.text);
          break;
        case 'signup':
          final result = await auth.signUp(email: address, password: password.text, emailRedirectTo: authRedirect, data: {'name':name.text.trim(),'phone':phone.text.trim(),'document':doc});
          if (result.session == null) notify('Confira seu e-mail para confirmar a conta.');
          break;
        case 'reset':
          await auth.resetPasswordForEmail(address, redirectTo: authRedirect);
          notify('Se existir uma conta, confira seu e-mail.');
          break;
        case 'update':
          await auth.updateUser(UserAttributes(password: password.text));
          widget.onRecovered?.call();
          break;
        case 'google':
          final opened = await auth.signInWithOAuth(OAuthProvider.google, redirectTo: authRedirect, authScreenLaunchMode: LaunchMode.externalApplication);
          if (!opened) notify('Não foi possível abrir o Google.');
          break;
      }
    } on AuthException catch (_) {
      notify('Não foi possível autenticar. Confira os dados ou tente novamente.');
    } catch (_) {
      notify('Falha na conexão. Tente novamente.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.storefront, size: 64),
        const Text('MARKYS PDV MOBILE', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        Text(widget.recovery ? 'Defina sua nova senha' : signup ? 'Crie sua conta — 7 dias grátis' : 'Entre na sua conta', textAlign: TextAlign.center),
        if (!widget.recovery) TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail')),
        if(signup && !widget.recovery) ...[
          TextField(controller:name, decoration:const InputDecoration(labelText:'Nome completo ou razão social')),
          TextField(controller:phone, keyboardType:TextInputType.phone, decoration:const InputDecoration(labelText:'Telefone / WhatsApp')),
          TextField(controller:document, keyboardType:TextInputType.number, decoration:const InputDecoration(labelText:'CPF/CNPJ')),
        ],
        TextField(controller: password, obscureText: hidden, decoration: InputDecoration(labelText: 'Senha', suffixIcon: IconButton(onPressed: () => setState(() => hidden = !hidden), icon: Icon(hidden ? Icons.visibility : Icons.visibility_off)))),
        if(signup && !widget.recovery) TextField(controller:confirmation,obscureText:hidden,decoration:const InputDecoration(labelText:'Confirmar senha')),
        const SizedBox(height: 20),
        FilledButton(onPressed: busy ? null : () => act(widget.recovery ? 'update' : signup ? 'signup' : 'login'), child: Text(widget.recovery ? 'Salvar senha' : signup ? 'Criar conta e começar teste' : 'Entrar')),
        if (!widget.recovery) ...[
          OutlinedButton(onPressed: busy ? null : () => act('google'), child: const Text('Entrar com Google')),
          TextButton(onPressed: busy ? null : () => setState(()=>signup=!signup), child: Text(signup?'Já tenho conta':'Criar conta')),
          TextButton(onPressed: busy ? null : () => act('reset'), child: const Text('Esqueci minha senha')),
        ],
        if (busy) const LinearProgressIndicator(),
      ]),
    ))),
  );
}
