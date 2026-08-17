
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

String hashPassword(String value) => sha256.convert(utf8.encode(value)).toString();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await openDatabase(
    join(await getDatabasesPath(), 'sme_saman.db'),
    version: 1,
    onCreate: (database, version) async {
      await database.execute('CREATE TABLE agents (code TEXT PRIMARY KEY, password_hash TEXT NOT NULL, name TEXT NOT NULL, role TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1)');
      await database.execute('CREATE TABLE cases (id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT NOT NULL, agent_code TEXT NOT NULL, company_name TEXT NOT NULL, social_count INTEGER NOT NULL DEFAULT 0, principal_count INTEGER NOT NULL DEFAULT 0, total_count INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL)');
      await database.execute('CREATE TABLE members (id INTEGER PRIMARY KEY AUTOINCREMENT, case_id INTEGER NOT NULL, relation TEXT NOT NULL, national_id TEXT NOT NULL, first_name TEXT NOT NULL, last_name TEXT NOT NULL, iban TEXT)');
    },
  );
  runApp(SmeApp(db: db));
}

class SmeApp extends StatelessWidget {
  const SmeApp({super.key, required this.db});
  final Database db;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'پنل صدور SME',
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b87))),
    home: AuthPage(db: db),
  );
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.db});
  final Database db;
  @override State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final user = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  bool firstRun = false;
  String? message;

  @override
  void initState() { super.initState(); checkFirstRun(); }

  Future<void> checkFirstRun() async {
    final count = Sqflite.firstIntValue(await widget.db.rawQuery('SELECT COUNT(*) FROM agents')) ?? 0;
    if (mounted) setState(() => firstRun = count == 0);
  }

  Future<void> submit() async {
    if (firstRun) {
      if (user.text.trim().isEmpty || name.text.trim().isEmpty || password.text.length < 8) {
        setState(() => message = 'نام مدیر، نام کاربری و رمز حداقل ۸ کاراکتری را وارد کنید.');
        return;
      }
      await widget.db.insert('agents', {
        'code': user.text.trim().toUpperCase(),
        'password_hash': hashPassword(password.text),
        'name': name.text.trim(),
        'role': 'admin',
        'active': 1,
      });
      if (mounted) setState(() { firstRun = false; message = 'مدیر ساخته شد؛ اکنون وارد شوید.'; password.clear(); });
      return;
    }
    final rows = await widget.db.query('agents', where: 'code = ? AND password_hash = ? AND active = 1', whereArgs: [user.text.trim().toUpperCase(), hashPassword(password.text)]);
    if (rows.isEmpty) { setState(() => message = 'نام کاربری یا رمز عبور صحیح نیست.'); return; }
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DashboardPage(db: widget.db, agent: rows.first)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Card(child: Padding(padding: const EdgeInsets.all(26), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('انجمن صنفی بیمه سامان', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xff176b87))),
        const SizedBox(height: 8), Text(firstRun ? 'ساخت مدیر اصلی' : 'ورود به پنل صدور SME', textAlign: TextAlign.center),
        const SizedBox(height: 20), if (firstRun) TextField(controller: name, decoration: const InputDecoration(labelText: 'نام مدیر')),
        TextField(controller: user, decoration: const InputDecoration(labelText: 'نام کاربری')),
        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'رمز عبور حداقل ۸ کاراکتر')),
        if (message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(message!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 18), FilledButton(onPressed: submit, child: Text(firstRun ? 'ساخت مدیر' : 'ورود')),
        const SizedBox(height: 20), const Text('نسخه 26-1405 — طراحی و توسعه و اهدا شده توسط وحید ارفعی — سال 1405', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey)),
      ]))),
    )),
  );
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.db, required this.agent});
  final Database db; final Map<String, Object?> agent;
  @override State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<Map<String, Object?>> cases = [];
  @override void initState() { super.initState(); load(); }
  Future<void> load() async { cases = await widget.db.query('cases', orderBy: 'id DESC'); if (mounted) setState(() {}); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('کارتابل پرونده‌ها')),
    floatingActionButton: FloatingActionButton.extended(onPressed: () {}, icon: const Icon(Icons.add), label: const Text('پرونده جدید')),
    body: RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(16), children: [
      ...cases.map((item) {
        final social = item['social_count'] as int? ?? 0;
        final principal = item['principal_count'] as int? ?? 0;
        final rate = social == 0 ? 0.0 : principal / social;
        final threshold = social <= 100 ? .7 : .6;
        return Card(child: ListTile(title: Text('${item['company_name']}'), subtitle: Text('لیست تأمین: $social | اصلی متقاضی: $principal | مشارکت: ${(rate * 100).toStringAsFixed(1)}٪'), trailing: Chip(label: Text(rate >= threshold && rate <= 1 ? 'مجاز' : 'نیازمند بررسی'))));
      }),
    ])),
  );
}
