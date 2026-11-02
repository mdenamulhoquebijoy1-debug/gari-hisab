import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'গাড়ির হিসাব',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: const Home(),
      );
}

typedef M = Map<String, dynamic>;
const outCats = ['তেল/গ্যাস', 'সার্ভিস', 'মেরামত', 'টায়ার', 'ড্রাইভার বেতন', 'ড্রাইভার অগ্রিম', 'পার্কিং/টোল', 'কাগজপত্র/ট্যাক্স', 'জরিমানা', 'অন্যান্য খরচ'];
const allCars = 'সব গাড়ি';
const noDrv = 'ড্রাইভার নেই';

String fm(num n) => n % 1 == 0 ? n.toInt().toString() : n.toStringAsFixed(2);
String fd(DateTime d) => '${d.day}/${d.month}/${d.year}';
String mk(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
double n0(dynamic v) => (v as num?)?.toDouble() ?? 0;
double inc(M e) => e['type'] == 'out' || e['type'] == 'self' ? 0 : n0(e['amt']);
double ex(M e) => e['type'] == 'out' ? n0(e['amt']) : (e['type'] == 'trip' ? (n0(e['cost']) + n0(e['commission'])) : 0);
double sIn(Iterable<M> l) => l.fold<double>(0, (s, e) => s + inc(e));
double sEx(Iterable<M> l) => l.fold<double>(0, (s, e) => s + ex(e));

class Home extends StatefulWidget {
  const Home({super.key});
  @override State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<M> items = [];
  List<M> rem = [];
  Map<String, double> drivers = {};
  Map<String, String> driverPhotos = {};
  String car = allCars;
  int tab = 0;
  DateTime month = DateTime.now();
  bool isBengali = true;
  SharedPreferences? p;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() { super.initState(); load(); checkUpdate(); }

  Future<void> checkUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final res = await http.get(Uri.parse('https://raw.githubusercontent.com/mdenamulhoquebijoy1-debug/gari-hisab/main/version.json'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (_isNewer(data['version'] as String, info.version)) {
          if (!mounted) return;
          showDialog(context: context, builder: (c) => AlertDialog(
            title: const Text('নতুন আপডেট'),
            content: Text(data['message'] ?? 'আপডেট আছে'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('পরে')),
              FilledButton(onPressed: () { Navigator.pop(c); _downloadAndInstall(data['apk_url']); }, child: const Text('ডাউনলোড')),
            ],
          ));
        }
      }
    } catch (_) {}
  }

  bool _isNewer(String latest, String current) {
    try {
      final l = latest.split('.').map(int.parse).toList();
      final c = current.split('.').map(int.parse).toList();
      for (var i = 0; i < 3; i++) {
        if ((l.length > i ? l[i] : 0) > (c.length > i ? c[i] : 0)) return true;
        if ((l.length > i ? l[i] : 0) < (c.length > i ? c[i] : 0)) return false;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _downloadAndInstall(String url) async {
    try {
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/update.apk');
      final res = await http.get(Uri.parse(url));
      await file.writeAsBytes(res.bodyBytes);
      await OpenFile.open(file.path);
    } catch (_) {}
  }

  List<M> _l(dynamic s) => s == null ? [] : (s as List).map((e) => Map<String, dynamic>.from(e)).toList();

  Future<void> load() async {
    p = await SharedPreferences.getInstance();
    try {
      final a = p!.getString('entries'), r = p!.getString('rem'), d = p!.getString('drivers'), ph = p!.getString('driverPhotos');
      items = _l(a == null ? null : jsonDecode(a));
      rem = _l(r == null ? null : jsonDecode(r));
      if (d != null) drivers = (jsonDecode(d) as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()));
      if (ph != null) driverPhotos = (jsonDecode(ph) as Map).map((k, v) => MapEntry(k as String, v as String));
    } catch (_) {}
    setState(() {});
  }

  void save() {
    p?.setString('entries', jsonEncode(items));
    p?.setString('rem', jsonEncode(rem));
    p?.setString('drivers', jsonEncode(drivers));
    p?.setString('driverPhotos', jsonEncode(driverPhotos));
    setState(() {});
  }

  void msg(String t) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t))); }

  Future<bool> ask(String t) async => (await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text(t), actions: [
    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('না')),
    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('হ্যাঁ')),
  ]))) == true;

  List<String> get cars => {for (final e in items) if (e['car'] != null) e['car'] as String}.toList();

  List<M> get shown {
    final l = items.where((e) => car == allCars || e['car'] == car).toList();
    l.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    return l;
  }

  Future<void> openAddPage(String type, [M? old]) async {
    final result = await Navigator.push<M>(context, MaterialPageRoute(builder: (_) => AddEditPage(initialType: type, old: old, cars: cars, currentCar: car, drivers: drivers.keys.toList())));
    if (result != null) {
      if (old != null) items.removeWhere((x) => x['id'] == old['id']);
      items.add(result);
      save();
    }
  }

  Future<void> editDriver([String? old]) async {
    final n = TextEditingController(text: old ?? '');
    final s = TextEditingController(text: old == null ? '' : fm(drivers[old] ?? 0));
    String? photo = old != null ? driverPhotos[old] : null;
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
      title: Text(old == null ? 'নতুন ড্রাইভার' : 'এডিট'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (photo != null) CircleAvatar(radius: 40, backgroundImage: MemoryImage(base64Decode(photo!))),
        TextButton.icon(icon: const Icon(Icons.photo), label: const Text('ছবি যোগ/পরিবর্তন'), onPressed: () async {
          final picker = ImagePicker();
          final x = await picker.pickImage(source: ImageSource.gallery, maxWidth: 300, maxHeight: 300);
          if (x != null) {
            final bytes = await x.readAsBytes();
            set(() => photo = base64Encode(bytes));
          }
        }),
        TextField(controller: n, decoration: const InputDecoration(labelText: 'নাম')),
        TextField(controller: s, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'মাসিক বেতন (৳)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
        TextButton(onPressed: () {
          final name = n.text.trim();
          if (name.isEmpty) return;
          if (old != null && old != name) {
            drivers.remove(old);
            driverPhotos.remove(old);
            for (final e in items) if (e['driver'] == old) e['driver'] = name;
          }
          drivers[name] = double.tryParse(s.text.trim()) ?? 0;
          if (photo != null) driverPhotos[name] = photo!;
          save();
          Navigator.pop(ctx);
        }, child: const Text('সংরক্ষণ')),
      ],
    )));
  }

  Future<void> backup() async {
    final data = jsonEncode({'entries': items, 'drivers': drivers, 'rem': rem, 'driverPhotos': driverPhotos});
    await Clipboard.setData(ClipboardData(text: data));
    msg('ব্যাকআপ কপি হয়েছে। Google Sheet-এ পেস্ট করতে পারেন।');
  }

  Future<void> restore() async {
    final t = (await Clipboard.getData('text/plain'))?.text;
    if (t == null || t.isEmpty) { msg('ক্লিপবোর্ডে কিছু নেই'); return; }
    try {
      final j = jsonDecode(t);
      if (j is Map) {
        items = _l(j['entries']);
        rem = _l(j['rem']);
        drivers = ((j['drivers'] ?? {}) as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()));
        if (j['driverPhotos'] != null) driverPhotos = (j['driverPhotos'] as Map).map((k, v) => MapEntry(k as String, v as String));
        save();
        msg('রিস্টোর সফল');
      }
    } catch (_) { msg('সঠিক ব্যাকআপ নয়'); }
  }

  String t(String bn, String en) => isBengali ? bn : en;

  Widget homeTab() {
    final yearList = shown.where((e) => DateTime.parse(e['date']).year == DateTime.now().year).toList();
    final i = sIn(yearList), o = sEx(yearList), pr = i - o;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        Expanded(child: FilledButton.icon(onPressed: () => openAddPage('trip'), icon: const Icon(Icons.route), label: Text(t('ট্রিপ', 'Trip')))),
        const SizedBox(width: 8),
        Expanded(child: FilledButton.icon(onPressed: () => openAddPage('self'), icon: const Icon(Icons.directions_car), label: Text(t('নিজে ব্যবহার', 'Self')))),
        const SizedBox(width: 8),
        Expanded(child: FilledButton.icon(onPressed: () => openAddPage('out'), icon: const Icon(Icons.money_off), label: Text(t('খরচ', 'Expense')))),
      ]),
      const SizedBox(height: 16),
      Text(t('স্বাগতম!', 'Welcome!'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      Text(t('আপনার গাড়ির আর্থিক হিসাব এখানে দেখুন।', 'View your car accounts here.')),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [const Icon(Icons.account_balance_wallet, color: Colors.green), Text('আয়'), Text('৳${fm(i)}', style: const TextStyle(fontWeight: FontWeight.bold))])))),
        const SizedBox(width: 8),
        Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [const Icon(Icons.receipt, color: Colors.red), Text('খরচ'), Text('৳${fm(o)}', style: const TextStyle(fontWeight: FontWeight.bold))])))),
        const SizedBox(width: 8),
        Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [const Icon(Icons.trending_up, color: Colors.blue), Text('লাভ'), Text('৳${fm(pr)}', style: const TextStyle(fontWeight: FontWeight.bold))])))),
      ]),
      const SizedBox(height: 16),
      Text(t('সাম্প্রতিক হিসাব', 'Recent'), style: const TextStyle(fontWeight: FontWeight.bold)),
      ...shown.take(5).map((e) => ListTile(
        title: Text(e['type'] == 'trip' ? '${e['from'] ?? ''} → ${e['to'] ?? ''}' : (e['cat'] ?? '')),
        subtitle: Text(fd(DateTime.parse(e['date']))),
        trailing: Text('৳${fm(n0(e['amt']))}'),
      )),
    ]);
  }

  Widget driverTab() {
    return ListView(children: [
      Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: () => editDriver(), icon: const Icon(Icons.person_add), label: Text(t('ড্রাইভার যোগ', 'Add Driver')))),
      if (drivers.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('ড্রাইভার যোগ করুন')),
      for (final n in drivers.keys)
        Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: ListTile(
          leading: driverPhotos[n] != null ? CircleAvatar(backgroundImage: MemoryImage(base64Decode(driverPhotos[n]!))) : const CircleAvatar(child: Icon(Icons.person)),
          title: Text(n),
          subtitle: Text('বেতন: ৳${fm(drivers[n] ?? 0)}'),
          trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => editDriver(n)),
        )),
    ]);
  }

  Widget reportTab() => const Center(child: Text('রিপোর্ট'));
  Widget documentTab() => const Center(child: Text('ডকুমেন্ট'));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(t('গাড়ির হিসাব', 'Car Account')),
        actions: [
          IconButton(icon: const Icon(Icons.backup), onPressed: backup, tooltip: 'ব্যাকআপ'),
          IconButton(icon: const Icon(Icons.restore), onPressed: restore, tooltip: 'রিস্টোর'),
        ],
      ),
      body: [homeTab(), driverTab(), reportTab(), documentTab()][tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'হোম'),
          NavigationDestination(icon: Icon(Icons.person), label: 'ড্রাইভার'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'রিপোর্ট'),
          NavigationDestination(icon: Icon(Icons.description), label: 'ডকুমেন্ট'),
        ],
      ),
    );
  }
}

class AddEditPage extends StatefulWidget {
  final String initialType;
  final M? old;
  final List<String> cars;
  final String currentCar;
  final List<String> drivers;
  const AddEditPage({super.key, required this.initialType, this.old, required this.cars, required this.currentCar, required this.drivers});
  @override State<AddEditPage> createState() => _AddEditPageState();
}

class _AddEditPageState extends State<AddEditPage> {
  late String t;
  late TextEditingController carC, amtC, costC, noteC, commissionC, driverPayC, fromC, toC;
  late String cat, drv;
  late DateTime d;
  bool paidNow = false;

  @override
  void initState() {
    super.initState();
    final old = widget.old;
    t = old?['type'] ?? widget.initialType;
    carC = TextEditingController(text: old?['car'] ?? (widget.currentCar != allCars ? widget.currentCar : 'আমার গাড়ি'));
    amtC = TextEditingController(text: old == null ? '' : fm(n0(old['amt'])));
    costC = TextEditingController(text: old == null ? '' : fm(n0(old['cost'])));
    noteC = TextEditingController(text: old?['note'] ?? '');
    commissionC = TextEditingController(text: old == null ? '' : fm(n0(old['commission'])));
    driverPayC = TextEditingController(text: old == null ? '' : fm(n0(old['driver_pay'])));
    fromC = TextEditingController(text: old?['from'] ?? '');
    toC = TextEditingController(text: old?['to'] ?? '');
    cat = old?['cat'] ?? outCats.first;
    drv = old?['driver'] ?? noDrv;
    d = old == null ? DateTime.now() : DateTime.parse(old['date']);
    paidNow = n0(old?['driver_pay']) > 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t == 'trip' ? 'ট্রিপ' : t == 'self' ? 'নিজে ব্যবহার' : 'খরচ')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: carC, decoration: const InputDecoration(labelText: 'গাড়ি', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        if (t == 'trip' || t == 'self') ...[
          TextField(controller: fromC, decoration: const InputDecoration(labelText: 'কোথা থেকে', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: toC, decoration: const InputDecoration(labelText: 'কোথায়', border: OutlineInputBorder())),
          const SizedBox(height: 12),
        ],
        TextField(controller: amtC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'টাকা', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        if (t == 'trip' || t == 'self') TextField(controller: costC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'খরচ', border: OutlineInputBorder())),
        if (t == 'out') DropdownButtonFormField<String>(value: cat, decoration: const InputDecoration(labelText: 'খরচের ধরন', border: OutlineInputBorder()), items: outCats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (v) => setState(() => cat = v!)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(value: drv, decoration: const InputDecoration(labelText: 'ড্রাইভার', border: OutlineInputBorder()), items: <String>{noDrv, ...widget.drivers, drv}.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (v) => setState(() => drv = v!)),
        const SizedBox(height: 12),
        TextField(controller: noteC, decoration: const InputDecoration(labelText: 'নোট', border: OutlineInputBorder())),
        ListTile(title: Text('তারিখ: ${fd(d)}'), trailing: const Icon(Icons.calendar_today), onTap: () async {
          final x = await showDatePicker(context: context, initialDate: d, firstDate: DateTime(2020), lastDate: DateTime(2100));
          if (x != null) setState(() => d = x);
        }),
        const SizedBox(height: 20),
        FilledButton(onPressed: () {
          final a = double.tryParse(amtC.text.trim());
          if (a == null || a <= 0) return;
          Navigator.pop(context, {
            'id': widget.old?['id'] ?? DateTime.now().millisecondsSinceEpoch,
            'car': carC.text.trim().isEmpty ? 'আমার গাড়ি' : carC.text.trim(),
            'type': t,
            'cat': t == 'out' ? cat : (t == 'trip' ? 'ট্রিপ' : 'নিজে ব্যবহার'),
            'amt': a,
            'cost': (t == 'trip' || t == 'self') ? (double.tryParse(costC.text.trim()) ?? 0) : 0,
            'commission': 0.0,
            'from': fromC.text.trim(),
            'to': toC.text.trim(),
            'driver': drv == noDrv ? null : drv,
            'driver_pay': 0.0,
            'note': noteC.text.trim(),
            'date': d.toIso8601String(),
          });
        }, child: const Text('সংরক্ষণ করুন')),
      ]),
    );
  }
}
