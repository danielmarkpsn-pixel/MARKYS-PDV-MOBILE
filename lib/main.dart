import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/login_page.dart';
import 'data/local_database.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: 'https://zdltbzwowkjevhigcgvr.supabase.co', anonKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'));
  runApp(const MarkysApp());
}

class MarkysApp extends StatelessWidget {
  const MarkysApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MARKYS PDV MOBILE',
    theme: MarkysTheme.light,
    debugShowCheckedModeBanner: false,
    home: const AuthGate(),
  );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}
class _AuthGateState extends State<AuthGate> {
  final auth = Supabase.instance.client.auth;
  late final StreamSubscription<AuthState> subscription;
  bool recovery = false;
  @override
  void initState() {
    super.initState();
    subscription = auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      setState(() {
        if (state.event == AuthChangeEvent.passwordRecovery) recovery = true;
        if (state.event == AuthChangeEvent.signedOut) recovery = false;
      });
    }, onError: (Object error) {});
  }
  @override
  void dispose() { subscription.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final session = auth.currentSession;
    if (recovery) return LoginPage(recovery: true, onRecovered: () => setState(() => recovery = false));
    if (session == null) return const LoginPage();
    return WelcomeGate(key: ValueKey(session.user.id), userId: session.user.id);
  }
}

class WelcomeGate extends StatefulWidget {
  const WelcomeGate({super.key, required this.userId});
  final String userId;
  @override
  State<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends State<WelcomeGate> {
  late final Future<Map<String, Object?>?> _business = LocalDatabase.forUser(widget.userId).firstBusiness();
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, Object?>?>(
    future: _business,
    builder: (context, snapshot) {
      if (snapshot.hasError) return Scaffold(body: Center(child: Text('Falha ao abrir dados locais: ${snapshot.error}')));
      if (!snapshot.hasData && snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final business = snapshot.data;
      return business == null ? BusinessRegisterPage(userId: widget.userId) : HomePage(businessName: business['name'] as String);
    },
  );
}

class BusinessRegisterPage extends StatefulWidget {
  const BusinessRegisterPage({super.key, required this.userId});
  final String userId;
  @override
  State<BusinessRegisterPage> createState() => _BusinessRegisterPageState();
}

class _BusinessRegisterPageState extends State<BusinessRegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _document = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _segment = TextEditingController();
  bool _saving = false;
  String? _registeredName;

  @override
  void dispose() {
    for (final c in [_name, _document, _phone, _email, _address, _segment]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await LocalDatabase.forUser(widget.userId).registerBusiness(
        name: _name.text,
        document: _document.text,
        phone: _phone.text,
        email: _email.text,
        address: _address.text,
        segment: _segment.text,
      );
      if (!mounted) return;
      setState(() => _registeredName = _name.text.trim());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar empresa: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _registeredName != null ? HomePage(businessName: _registeredName!) : Scaffold(
    appBar: AppBar(title: const Text('Cadastrar minha empresa'), actions: [IconButton(onPressed: () => Supabase.instance.client.auth.signOut(), icon: const Icon(Icons.logout))]),
    body: SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const Icon(Icons.storefront, color: MarkysTheme.blue, size: 64),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nome da empresa *'),
            validator: (v) => v == null || v.trim().isEmpty ? 'Informe o nome' : null,
          ),
          TextFormField(controller: _document, decoration: const InputDecoration(labelText: 'CPF ou CNPJ')),
          TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefone / WhatsApp')),
          TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail comercial')),
          TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Endereço')),
          TextFormField(controller: _segment, decoration: const InputDecoration(labelText: 'Segmento comercial')),
          const SizedBox(height: 24),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Salvando...' : 'Cadastrar empresa')),
        ]),
      ),
    ),
  );
}

class HomePage extends StatelessWidget {
  final String businessName;
  const HomePage({super.key, required this.businessName});

  static const sections = <(IconData, String)>[
    (Icons.home_outlined, 'Início'),
    (Icons.shopping_cart_outlined, 'Vender'),
    (Icons.receipt_long_outlined, 'Pedidos'),
    (Icons.inventory_2_outlined, 'Produtos'),
    (Icons.store_outlined, 'Catálogo Online'),
    (Icons.account_balance_wallet_outlined, 'Finanças'),
    (Icons.local_offer_outlined, 'Cupons'),
    (Icons.people_outline, 'Clientes'),
    (Icons.history, 'Histórico'),
    (Icons.bar_chart_outlined, 'Estatísticas'),
    (Icons.manage_accounts_outlined, 'Usuários'),
    (Icons.settings_outlined, 'Configurações'),
    (Icons.help_outline, 'Ajuda'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    drawer: Drawer(
      backgroundColor: MarkysTheme.dark,
      child: SafeArea(child: Column(children: [
        ListTile(title: const Text('MARKYS PDV', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: Text(businessName, style: const TextStyle(color: Colors.white70))),
        const Divider(color: Colors.white24),
        Expanded(child: ListView(children: sections.map((section) =>
          ListTile(
            leading: Icon(section.$1, color: Colors.white70),
            title: Text(section.$2, style: const TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              if (section.$2 != 'Início') {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Módulo ${section.$2}: em desenvolvimento')),
                );
              }
            },
          )).toList())),
      ])),
    ),
    appBar: AppBar(title: const Text('Início'), actions: [IconButton(onPressed: () => Supabase.instance.client.auth.signOut(), icon: const Icon(Icons.logout), tooltip: 'Sair')]),
    body: ListView(children: [
      Container(
        color: MarkysTheme.dark,
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Text(businessName.toUpperCase(), style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 15),
          const Text('Hoje', style: TextStyle(color: Colors.white70)),
          const Text('R$ 0,00', style: TextStyle(color: Colors.white, fontSize: 32)),
          const Text('0 vendas realizadas', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          const Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _Metric(label: 'Ontem', value: 'R$ 0,00'),
            _Metric(label: 'Este mês', value: 'R$ 0,00'),
          ]),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Tela de venda: próxima etapa')),
            ),
            child: const Text('Registrar venda'),
          )),
        ]),
      ),
      const Padding(padding: EdgeInsets.all(12), child: _HomeCard(
        icon: Icons.inventory_2_outlined, title: 'Estoque',
        content: 'Valor em estoque: R$ 0,00\nNenhum produto cadastrado',
        button: '+ Cadastrar produto',
      )),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: _HomeCard(
        icon: Icons.receipt_long_outlined, title: 'Pedidos em aberto',
        content: 'Nenhum pedido em aberto', button: '+ Criar pedido',
      )),
      const Padding(padding: EdgeInsets.all(12), child: _HomeCard(
        icon: Icons.storefront_outlined, title: 'Catálogo Online',
        content: 'Vamos começar a expor seus produtos?', button: 'Ver catálogo',
      )),
    ]),
  );
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
    Text(value, style: const TextStyle(color: Colors.white)),
  ]);
}

class _HomeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;
  final String button;
  const _HomeCard({required this.icon, required this.title, required this.content, required this.button});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(14), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [Icon(icon, color: MarkysTheme.blue), const SizedBox(width: 8), Text(title,
          style: const TextStyle(fontWeight: FontWeight.bold))]),
        const SizedBox(height: 12),
        Text(content),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$button: em desenvolvimento')),
        ), child: Text(button)),
      ],
    )),
  );
}
