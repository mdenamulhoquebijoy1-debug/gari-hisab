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

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'গাড়ির হিসাব',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.teal,
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF00695C),
            foregroundColor: Colors.white,
          ),
        ),
        home: const Home(),
      );
}

typedef M = Map<String, dynamic>;

const outCats = [
  'তেল/গ্যাস', 'সার্ভিস', 'মেরামত', 'টায়ার', 'ড্রাইভার বেতন', 'ড্রাইভার অগ্রিম',
  'পার্কিং/টোল', 'কাগজপত্র/ট্যাক্স', 'জরিমানা', 'অন্যান্য খরচ'
];
const allCars = 'সব গাড়ি';
const noDrv = 'ড্রাইভার নেই';

String fm(num n) => n % 1 == 0 ? n.toInt().toString() : n.toStringAsFixed(2);
String fd(DateTime d) => '${d.day}/${d.month}/${d.year}';
String mk(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
double n0(dynamic v) => (v as num?)?.toDouble() ?? 0;

// লাভ = ভাড়া - খরচ - কমিশন (ট্রিপের ক্ষেত্রে)
double tripProfit(M e) => e['type'] == 'trip' ? (n0(e['amt']) - n0(e['cost']) - n0(e['commission'])) : 0;
double inc(M e) => e['type'] == 'out' || e['type'] == 'self' ? 0 : n0(e['amt']);
double ex(M e) => e['type'] == 'out' ? n0(e['amt']) : (e['type'] == 'trip' ? (n0(e['cost']) + n0(e['commission'])) : 0);
double sIn(Iterable<M> l) => l.fold<double>(0, (s, e) => s + inc(e));
double sEx(Iterable<M> l) => l.fold<double>(0, (s, e) => s + ex(e));

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<M> items = [];
  List<M> rem = [];
  Map<String, double> drivers = {};
  String car = allCars;
  int tab = 0;
  DateTime month = DateTime.now();
  SharedPreferences? p;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    load();
    checkUpdate();
  }

  Future<void> checkUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final res = await http.get(Uri.parse(
          'https://raw.githubusercontent.com/mdenamulhoquebijoy1-debug/gari-hisab/main/version.json'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (_isNewer(data['version'] as String, info.version)) {
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('নতুন আপডেট'),
              content: Text(data['message'] ?? 'আপডেট আছে'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c), child: const Text('পরে')),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(c);
                    _downloadAndInstall(data['apk_url']);
                  },
                  child: const Text('ডাউনলোড'),
                ),
              ],
            ),
          );
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
      final a = p!.getString('entries'), r = p!.getString('rem'), d = p!.getString('drivers');
      items = _l(a == null ? null : jsonDecode(a));
      rem = _l(r == null ? null : jsonDecode(r));
      if (d != null) drivers = (jsonDecode(d) as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()));
    } catch (_) {}
    setState(() {});
  }

  void save() {
    p?.setString('entries', jsonEncode(items));
    p?.setString('rem', jsonEncode(rem));
    p?.setString('drivers', jsonEncode(drivers));
    setState(() {});
  }

  void msg(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<bool> ask(String t) async =>
      (await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(title: Text(t), actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('না')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('হ্যাঁ')),
        ]),
      )) == true;

  List<String> get cars => {for (final e in items) if (e['car'] != null) e['car'] as String}.toList();

  List<M> get shown {
    final l = items.where((e) => car == allCars || e['car'] == car).toList();
    l.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    return l;
  }

  Future<void> openAddPage(String type) async {
    final result = await Navigator.push<M>(
      context,
      MaterialPageRoute(builder: (_) => AddEditPage(initialType: type, cars: cars, currentCar: car, drivers: drivers.keys.toList())),
    );
    if (result != null) {
      items.add(result);
      save();
    }
  }

  Future<void> editDriver([String? old]) async {
    final n = TextEditingController(text: old ?? '');
    final s = TextEditingController(text: old == null ? '' : fm(drivers[old] ?? 0));
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(old == null ? 'নতুন ড্রাইভার' : 'এডিট'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
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
              for (final e in items) if (e['driver'] == old) e['driver'] = name;
            }
            drivers[name] = double.tryParse(s.text.trim()) ?? 0;
            save();
            Navigator.pop(ctx);
          }, child: const Text('সংরক্ষণ')),
        ],
      ),
    );
  }

  void showDriverDetails(String name) {
    final trips = items.where((e) => e['driver'] == name && (e['type'] == 'trip' || e['type'] == 'self')).toList();
    final totalTrips = trips.length;
    final totalCommission = trips.fold<double>(0, (s, e) => s + n0(e['commission']));
    final totalPaid = trips.fold<double>(0, (s, e) => s + n0(e['driver_pay']));
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          color: Colors.teal.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Text('মোট ট্রিপ: $totalTrips', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('মোট কমিশন আয়: ৳${fm(totalCommission)}', style: const TextStyle(fontSize: 16)),
              Text('মোট প্রাপ্ত: ৳${fm(totalPaid)}', style: const TextStyle(fontSize: 16)),
              Text('বকেয়া: ৳${fm(totalCommission - totalPaid)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        const Text('ট্রিপসমূহ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ...trips.map((e) => ListTile(
              leading: Icon(e['type'] == 'trip' ? Icons.route : Icons.directions_car),
              title: Text('${e['car']} • ${fd(DateTime.parse(e['date']))}'),
              subtitle: Text('কমিশন ৳${fm(n0(e['commission']))}'),
              trailing: Text(n0(e['driver_pay']) > 0 ? 'দেওয়া হয়েছে' : 'বকেয়া', style: TextStyle(color: n0(e['driver_pay']) > 0 ? Colors.green : Colors.orange)),
            )),
      ]),
    )));
  }

  Future<void> addRem() async {
    final t = TextEditingController();
    DateTime d = DateTime.now().add(const Duration(days: 30));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
            title: const Text('রিমাইন্ডার যোগ'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: t, decoration: const InputDecoration(labelText: 'কীসের রিমাইন্ডার?')),
              ListTile(
                title: Text('তারিখ: ${fd(d)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final x = await showDatePicker(context: ctx, initialDate: d, firstDate: DateTime.now(), lastDate: DateTime(2100));
                  if (x != null) set(() => d = x);
                },
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('যোগ')),
            ],
          )),
    );
    if (ok == true && t.text.trim().isNotEmpty) {
      rem.add({'id': DateTime.now().millisecondsSinceEpoch, 'title': t.text.trim(), 'date': d.toIso8601String()});
      save();
    }
  }

  String _monthName(int m) => ['', 'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', 'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'][m];

  Widget monthNav() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)), icon: const Icon(Icons.chevron_left)),
          Text('${_monthName(month.month)} ${month.year}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)), icon: const Icon(Icons.chevron_right)),
        ]),
      );

  Widget sumCard(String title, double value, Color color, IconData icon) => Expanded(
        child: Card(
          elevation: 2,
          color: color.withOpacity(0.15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 6),
              Text(title, style: const TextStyle(fontSize: 13)),
              Text('৳${fm(value)}', style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 18)),
            ]),
          ),
        ),
      );

  Widget homeTab() {
    final m = shown.where((e) => mk(DateTime.parse(e['date'])) == mk(month)).toList();
    final i = sIn(m), o = sEx(m), pr = i - o;
    return ListView(padding: const EdgeInsets.all(12), children: [
      monthNav(),
      Row(children: [
        sumCard('আয়', i, Colors.green, Icons.account_balance_wallet),
        const SizedBox(width: 8),
        sumCard('খরচ', o, Colors.redAccent, Icons.receipt_long),
        const SizedBox(width: 8),
        sumCard(pr >= 0 ? 'লাভ' : 'লোকসান', pr.abs(), pr >= 0 ? Colors.teal : Colors.deepOrange, Icons.trending_up),
      ]),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(12)),
        child: const Text('সাম্প্রতিক হিসাব', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      const SizedBox(height: 8),
      ...shown.take(8).map((e) => Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: e['type'] == 'trip' ? Colors.indigo.shade100 : e['type'] == 'self' ? Colors.orange.shade100 : Colors.red.shade100,
                child: Icon(e['type'] == 'trip' ? Icons.route : e['type'] == 'self' ? Icons.directions_car : Icons.arrow_upward,
                    color: e['type'] == 'trip' ? Colors.indigo : e['type'] == 'self' ? Colors.orange : Colors.red),
              ),
              title: Text(e['type'] == 'trip' ? 'ট্রিপ • লাভ ৳${fm(tripProfit(e))}' : e['type'] == 'self' ? 'নিজে ব্যবহার' : e['cat']),
              subtitle: Text('${e['car']} • ${fd(DateTime.parse(e['date']))}'),
              trailing: Text('৳${fm(n0(e['amt']))}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          )),
      const SizedBox(height: 80),
    ]);
  }

  Widget driverTab() {
    final m = shown.where((e) => mk(DateTime.parse(e['date'])) == mk(month)).toList();
    return ListView(children: [
      monthNav(),
      Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(onPressed: () => editDriver(), icon: const Icon(Icons.person_add), label: const Text('ড্রাইভার যোগ')),
      ),
      if (drivers.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('ড্রাইভার যোগ করুন')),
      for (final n in drivers.keys)
        Builder(builder: (c) {
          final mine = m.where((e) => e['driver'] == n).toList();
          final sal = drivers[n] ?? 0;
          final paidSalary = sEx(mine.where((e) => e['cat'] == 'ড্রাইভার বেতন'));
          final adv = sEx(mine.where((e) => e['cat'] == 'ড্রাইভার অগ্রিম'));
          final paidNow = mine.fold<double>(0, (s, e) => s + n0(e['driver_pay']));
          final commission = mine.fold<double>(0, (s, e) => s + n0(e['commission']));
          final unpaid = commission - paidNow;
          final bal = sal - paidSalary - adv + unpaid;
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: InkWell(
              onTap: () => showDriverDetails(n),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(n, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                    IconButton(icon: const Icon(Icons.edit), onPressed: () => editDriver(n)),
                  ]),
                  Text('মাসিক বেতন: ৳${fm(sal)}'),
                  Text('কমিশন (এই মাস): ৳${fm(commission)}'),
                  Text('এখনই দিয়েছি: ৳${fm(paidNow)}'),
                  Text('কমিশন বকেয়া: ৳${fm(unpaid)}'),
                  const SizedBox(height: 4),
                  Text(bal >= 0 ? 'মোট বকেয়া: ৳${fm(bal)}' : 'বেশি দেওয়া হয়েছে: ৳${fm(-bal)}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: bal > 0 ? Colors.orange : Colors.teal)),
                  const Align(alignment: Alignment.centerRight, child: Text('বিস্তারিত দেখতে ট্যাপ করুন →', style: TextStyle(fontSize: 12, color: Colors.grey))),
                ]),
              ),
            ),
          );
        }),
      const SizedBox(height: 80),
    ]);
  }

  Widget reportTab() {
    final m = shown.where((e) => mk(DateTime.parse(e['date'])) == mk(month)).toList();
    final i = sIn(m), o = sEx(m), pr = i - o;
    final selfUses = m.where((e) => e['type'] == 'self').toList();
    final selfCost = selfUses.fold<double>(0, (s, e) => s + n0(e['cost']));
    return ListView(padding: const EdgeInsets.all(12), children: [
      monthNav(),
      Card(
        color: Colors.teal.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Text('এই মাসের হিসাব', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              Text('আয়\n৳${fm(i)}', textAlign: TextAlign.center),
              Text('খরচ\n৳${fm(o)}', textAlign: TextAlign.center),
              Text('${pr >= 0 ? "লাভ" : "লোকসান"}\n৳${fm(pr.abs())}', textAlign: TextAlign.center),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      const Text('নিজে ব্যবহার', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      if (selfUses.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('এই মাসে কোনো নিজে ব্যবহার নেই')),
      for (final e in selfUses)
        ListTile(
          leading: const Icon(Icons.directions_car, color: Colors.orange),
          title: Text(e['car'] ?? ''),
          subtitle: Text(fd(DateTime.parse(e['date']))),
          trailing: Text('খরচ ৳${fm(n0(e['cost']))}'),
        ),
      if (selfUses.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('মোট নিজে ব্যবহার খরচ: ৳${fm(selfCost)}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      const SizedBox(height: 80),
    ]);
  }

  Widget documentTab() {
    final today = DateTime.now();
    final rs = [...rem]..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(onPressed: addRem, icon: const Icon(Icons.add), label: const Text('রিমাইন্ডার যোগ করুন')),
      ),
      if (rs.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('কোনো ডকুমেন্ট রিমাইন্ডার নেই')),
      for (final r in rs)
        Builder(builder: (c) {
          final days = DateTime.parse(r['date']).difference(today).inDays;
          return ListTile(
            leading: Icon(Icons.notifications, color: days < 0 ? Colors.red : Colors.teal),
            title: Text(r['title']),
            subtitle: Text(days < 0 ? 'মেয়াদ শেষ ${-days} দিন আগে' : '$days দিন বাকি'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await ask('মুছবেন?')) {
                  rem.removeWhere((x) => x['id'] == r['id']);
                  save();
                }
              },
            ),
          );
        }),
      const SizedBox(height: 80),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final opts = [allCars, ...cars];
    if (!opts.contains(car)) car = allCars;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('গাড়ির হিসাব'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          DropdownButton<String>(
            value: car,
            underline: const SizedBox(),
            items: opts.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(color: Colors.white)))).toList(),
            onChanged: (v) => setState(() => car = v!),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF00695C)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.directions_car, color: Colors.white, size: 40),
                  SizedBox(height: 8),
                  Text('গাড়ির হিসাব', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  Text('নতুন হিসাব যোগ করুন', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            ListTile(leading: const Icon(Icons.route), title: const Text('ট্রিপ'), onTap: () { Navigator.pop(context); openAddPage('trip'); }),
            ListTile(leading: const Icon(Icons.directions_car), title: const Text('নিজে ব্যবহার'), onTap: () { Navigator.pop(context); openAddPage('self'); }),
            ListTile(leading: const Icon(Icons.arrow_upward), title: const Text('খরচ'), onTap: () { Navigator.pop(context); openAddPage('out'); }),
          ],
        ),
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
  final List<String> cars;
  final String currentCar;
  final List<String> drivers;
  const AddEditPage({super.key, required this.initialType, required this.cars, required this.currentCar, required this.drivers});
  @override
  State<AddEditPage> createState() => _AddEditPageState();
}

class _AddEditPageState extends State<AddEditPage> {
  late String t;
  late TextEditingController carC, amtC, costC, noteC, commissionC, driverPayC;
  late String cat, drv;
  late DateTime d;
  bool paidNow = false;

  @override
  void initState() {
    super.initState();
    t = widget.initialType;
    carC = TextEditingController(text: widget.currentCar != allCars ? widget.currentCar : (widget.cars.isNotEmpty ? widget.cars.first : 'আমার গাড়ি'));
    amtC = TextEditingController();
    costC = TextEditingController();
    noteC = TextEditingController();
    commissionC = TextEditingController();
    driverPayC = TextEditingController();
    cat = outCats.first;
    drv = noDrv;
    d = DateTime.now();
  }

  @override
  void dispose() {
    carC.dispose(); amtC.dispose(); costC.dispose(); noteC.dispose(); commissionC.dispose(); driverPayC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t == 'trip' ? 'নতুন ট্রিপ' : t == 'self' ? 'নিজে ব্যবহার' : 'নতুন খরচ')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: carC, decoration: const InputDecoration(labelText: 'গাড়ির নাম/নম্বর', border: OutlineInputBorder(), prefixIcon: Icon(Icons.directions_car))),
          const SizedBox(height: 12),
          TextField(controller: amtC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: t == 'trip' ? 'ট্রিপের ভাড়া (৳)' : 'পরিমাণ (৳)', border: const OutlineInputBorder())),
          if (t == 'trip' || t == 'self') ...[
            const SizedBox(height: 12),
            TextField(controller: costC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'খরচ (তেল/টোল) (৳)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: commissionC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'ড্রাইভারের কমিশন (৳)', border: OutlineInputBorder(), helperText: 'লাভ থেকে বাদ যাবে')),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: paidNow,
              onChanged: (v) => setState(() => paidNow = v ?? false),
              title: const Text('এখনই দিয়ে দিয়েছি'),
              subtitle: const Text('টিক দিলে বকেয়ায় যোগ হবে না'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (paidNow) ...[
              const SizedBox(height: 8),
              TextField(controller: driverPayC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'কত দিয়েছি (৳)', border: OutlineInputBorder(), helperText: 'খালি রাখলে পুরো কমিশন দেওয়া ধরা হবে')),
            ],
          ],
          if (t == 'out') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(value: cat, decoration: const InputDecoration(labelText: 'খরচের ধরন', border: OutlineInputBorder()), items: outCats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (v) => setState(() => cat = v!)),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: drv, decoration: const InputDecoration(labelText: 'ড্রাইভার', border: OutlineInputBorder()), items: <String>{noDrv, ...widget.drivers, drv}.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (v) => setState(() => drv = v!)),
          const SizedBox(height: 12),
          TextField(controller: noteC, decoration: const InputDecoration(labelText: 'নোট (ঐচ্ছিক)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          ListTile(title: Text('তারিখ: ${fd(d)}'), trailing: const Icon(Icons.calendar_today), onTap: () async {
            final x = await showDatePicker(context: context, initialDate: d, firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (x != null) setState(() => d = x);
          }),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: () {
                final a = double.tryParse(amtC.text.trim());
                if (a == null || a <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('সঠিক পরিমাণ দিন')));
                  return;
                }
                final commission = double.tryParse(commissionC.text.trim()) ?? 0;
                double paid = 0;
                if (paidNow) {
                  paid = double.tryParse(driverPayC.text.trim()) ?? commission;
                }
                Navigator.pop(context, {
                  'id': DateTime.now().millisecondsSinceEpoch,
                  'car': carC.text.trim().isEmpty ? 'আমার গাড়ি' : carC.text.trim(),
                  'type': t,
                  'cat': t == 'out' ? cat : (t == 'trip' ? 'ট্রিপ' : 'নিজে ব্যবহার'),
                  'amt': a,
                  'cost': (t == 'trip' || t == 'self') ? (double.tryParse(costC.text.trim()) ?? 0) : 0,
                  'commission': (t == 'trip' || t == 'self') ? commission : 0,
                  'driver': drv == noDrv ? null : drv,
                  'driver_pay': paid,
                  'note': noteC.text.trim(),
                  'date': d.toIso8601String(),
                });
              },
              icon: const Icon(Icons.save),
              label: const Text('সংরক্ষণ করুন'),
            ),
          ),
        ]),
      ),
    );
  }
}
