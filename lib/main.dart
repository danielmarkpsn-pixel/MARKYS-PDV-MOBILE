import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/login_page.dart';
import 'data/local_database.dart';
import 'theme.dart';
import 'products_page.dart';
import 'customers_page.dart';
import 'sales_page.dart';
import 'commerce_page.dart';
import 'reports_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: 'https://zdltbzwowkjevhigcgvr.supabase.co', publishableKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'));
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
      return business == null ? BusinessRegisterPage(userId: widget.userId) : HomePage(businessName: business['name'] as String, userId: widget.userId);
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
  Widget build(BuildContext context) => _registeredName != null ? HomePage(businessName: _registeredName!, userId: widget.userId) : Scaffold(
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

class HomePage extends StatefulWidget {
  final String businessName;
  final String userId;
  const HomePage({super.key, required this.businessName, required this.userId});

  @override
  State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  String get userId => widget.userId;
  String get businessName => widget.businessName;
  int today=0,yesterday=0,month=0,count=0,orders=0;
  String stockSummary = 'Carregando estoque...';
  @override
  void initState(){super.initState();refreshStock();}
  Future<void> refreshStock() async {
    try {
      final local=LocalDatabase.forUser(userId);
      final business=await local.firstBusiness();
      final rows=await (await local.database).rawQuery('SELECT COUNT(*) AS total, COALESCE(SUM(stock * cost_cents),0) AS value, COALESCE(SUM(CASE WHEN stock <= min_stock THEN 1 ELSE 0 END),0) AS low FROM products WHERE business_id = ? AND active = 1',[business?['id']]);
      final r=rows.first;
      final value=((r['value'] as num)/100).toStringAsFixed(2).replaceAll('.',',');
      final db=await local.database;
      final now=DateTime.now();
      final day=DateTime(now.year,now.month,now.day);
      final prev=day.subtract(const Duration(days:1));
      final start=DateTime(now.year,now.month);
      final sales=await db.query('sales',where:"business_id = ? AND status = 'Concluída'",whereArgs:[business?['id']]);
      final pending=await db.query('open_orders',where:'business_id = ?',whereArgs:[business?['id']]);
      int t=0,y=0,m=0,n=0;
      for(final s in sales){final date=DateTime.tryParse(s['created_at'].toString());if(date==null)continue;final amount=s['total_cents'] as int;if(!date.isBefore(day)){t+=amount;n++;}else if(!date.isBefore(prev)){y+=amount;}if(!date.isBefore(start))m+=amount;}
      if(mounted)setState((){today=t;yesterday=y;month=m;count=n;orders=pending.length;});
      if(mounted)setState(()=>stockSummary='Valor de custo em estoque: R\$ $value\n${r['total']} produtos ativos • ${r['low']} com estoque baixo');
    }catch(_){if(mounted)setState(()=>stockSummary='Não foi possível carregar estoque');}
  }
  Future<void> openProducts() async {await Navigator.of(context).push(MaterialPageRoute(builder:(_)=>ProductsPage(userId:userId)));if(mounted)await refreshStock();}
  Future<void> openSales() async { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SalesPage(userId: userId))); if (mounted) await refreshStock(); }
  Future<void> openCommerce(String mode) async {await Navigator.push(context,MaterialPageRoute(builder:(_)=>CommercePage(userId:userId,mode:mode)));if(mounted)await refreshStock();}
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
              if (section.$2 == 'Produtos') {
                openProducts();
              } else if (section.$2 == 'Vender') {
                openSales();
              } else if (['Pedidos','Finanças','Histórico'].contains(section.$2)) {
                openCommerce(section.$2);
              } else if (section.$2 == 'Estatísticas') {
                Navigator.push(context,MaterialPageRoute(builder:(_)=>ReportsPage(userId:userId)));
              } else if (section.$2 == 'Clientes') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => CustomersPage(userId: userId)));
              } else if (section.$2 != 'Início') {
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
          Text(saleMoney(today), style: const TextStyle(color: Colors.white, fontSize: 32)),
          Text('$count vendas realizadas', style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _Metric(label: 'Ontem', value: saleMoney(yesterday)),
            _Metric(label: 'Este mês', value: saleMoney(month)),
          ]),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: openSales,
            child: const Text('Registrar venda'),
          )),
        ]),
      ),
      Padding(padding: const EdgeInsets.all(12), child: _HomeCard(
        onPressed: openProducts,
        icon: Icons.inventory_2_outlined, title: 'Estoque',
        content: stockSummary,
        button: '+ Cadastrar produto',
      )),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _HomeCard(
        icon: Icons.receipt_long_outlined, title: 'Pedidos em aberto',
        content: '$orders pedidos em aberto', button: 'Ver pedidos', onPressed: () => openCommerce('Pedidos'),
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
  final VoidCallback? onPressed;
  const _HomeCard({required this.icon, required this.title, required this.content, required this.button, this.onPressed});
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
        FilledButton(onPressed: onPressed ?? () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$button: em desenvolvimento')),
        ), child: Text(button)),
      ],
    )),
  );
}
