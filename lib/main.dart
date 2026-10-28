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
import 'package:file_picker/file_picker.dart';

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
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
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
  bool isBengali = true;
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

  Future<void> openAddPage(String type, [M? old]) async {
    final result = await Navigator.push<M>(
      context,
      MaterialPageRoute(builder: (_) => AddEditPage(initialType: type, old: old, cars: cars, currentCar: car, drivers: drivers.keys.toList())),
    );
    if (result != null) {
      if (old != null) items.removeWhere((x) => x['id'] == old['id']);
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
    final tCtrl = TextEditingController();
    DateTime d = DateTime.now().add(const Duration(days: 30));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
            title: const Text('রিমাইন্ডার যোগ'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: tCtrl, decoration: const InputDecoration(labelText: 'কীসের রিমাইন্ডার?')),
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
    if (ok == true && tCtrl.text.trim().isNotEmpty) {
      rem.add({'id': DateTime.now().millisecondsSinceEpoch, 'title': tCtrl.text.trim(), 'date': d.toIso8601String()});
      save();
    }
  }

  Future<void> backup() async {
    try {
      final data = jsonEncode({'entries': items, 'drivers': drivers, 'rem': rem});
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/gari_hisab_backup_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(data);
      msg('ব্যাকআপ সেভ হয়েছে');
    } catch (_) {
      msg('ব্যাকআপ ব্যর্থ');
    }
  }

  Future<void> restore() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (result == null || result.files.single.path == null) return;
    try {
      final content = await File(result.files.single.path!).readAsString();
      final j = jsonDecode(content);
      if (j is Map) {
        items = _l(j['entries']);
        rem = _l(j['rem']);
        drivers = ((j['drivers'] ?? {}) as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()));
        save();
        msg('রিস্টোর সফল');
      }
    } catch (_) {
      msg('রিস্টোর ব্যর্থ');
    }
  }

  String t(String bn, String en) => isBengali ? bn : en;

  Widget langToggle() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(onTap: () => setState(() => isBengali = false), child: Text('EN', style: TextStyle(fontWeight: isBengali ? FontWeight.normal : FontWeight.bold, color: isBengali ? Colors.grey : Colors.blue))),
          const Text(' | '),
          GestureDetector(onTap: () => setState(() => isBengali = true), child: Text('বাংলা', style: TextStyle(fontWeight: isBengali ? FontWeight.bold : FontWeight.normal, color: isBengali ? Colors.blue : Colors.grey))),
        ]),
      );

  List<double> yearlyProfits() {
    final year = DateTime.now().year;
    return List.generate(12, (m) {
      final list = shown.where((e) {
        final d = DateTime.parse(e['date']);
        return d.year == year && d.month == m + 1;
      }).toList();
      return sIn(list) - sEx(list);
    });
  }

  Widget profitChart() {
    final data = yearlyProfits();
    final maxY = data.map((e) => e.abs()).fold(0.0, (a, b) => a > b ? a : b) * 1.2 + 1000;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('চলতি অর্থবছরের লাভ', 'Current Financial Year Profit'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) => Text(['জান', 'ফেব', 'মার্চ', 'এপ্রি', 'মে', 'জুন', 'জুল', 'আগ', 'সেপ', 'অক্টো', 'নভে', 'ডিসে'][v.toInt()], style: const TextStyle(fontSize: 10)))),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(12, (i) => FlSpot(i.toDouble(), data[i])),
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(show: true, color: Colors.blue.withOpacity(0.1)),
                  ),
                ],
                maxY: maxY,
                minY: 0,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget summaryCard(String title, double value, Color iconBg, IconData icon, String percent) => Expanded(
        child: Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(backgroundColor: iconBg, child: Icon(icon, color: Colors.white, size: 20)),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontSize: 13, color: Colors.grey)),
              Text('৳${fm(value)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(percent, style: const TextStyle(color: Colors.green, fontSize: 12)),
            ]),
          ),
        ),
      );

  Widget homeTab() {
    final yearList = shown.where((e) => DateTime.parse(e['date']).year == DateTime.now().year).toList();
    final i = sIn(yearList), o = sEx(yearList), pr = i - o;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(t('স্বাগতম!', 'Welcome!'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      Text(t('আপনার গাড়ির আর্থিক হিসাব এখানে দেখুন।', 'View your car financial accounts here.'), style: const TextStyle(color: Colors.grey)),
      const SizedBox(height: 16),
      Row(children: [
        summaryCard(t('মোট আয়', 'Total Income'), i, Colors.green, Icons.account_balance_wallet, '↑ 12.6%'),
        const SizedBox(width: 8),
        summaryCard(t('মোট খরচ', 'Total Expense'), o, Colors.red, Icons.receipt, '↑ 8.2%'),
        const SizedBox(width: 8),
        summaryCard(t('নেট লাভ', 'Net Profit'), pr, Colors.blue, Icons.trending_up, '↑ 15.3%'),
      ]),
      const SizedBox(height: 16),
      profitChart(),
      const SizedBox(height: 16),
      Text(t('সাম্প্রতিক হিসাব', 'Recent Accounts'), style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      ...shown.take(5).map((e) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(e['type'] == 'trip' ? Icons.route : Icons.arrow_upward),
            title: Text(e['type'] == 'trip' ? t('ট্রিপ', 'Trip') : e['cat']),
            subtitle: Text(fd(DateTime.parse(e['date']))),
            trailing: Text('৳${fm(n0(e['amt']))}'),
          )),
      const SizedBox(height: 80),
    ]);
  }

  Widget driverTab() => ListView(children: [
        Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: () => editDriver(), icon: const Icon(Icons.person_add), label: Text(t('ড্রাইভার যোগ', 'Add Driver')))),
        if (drivers.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(t('ড্রাইভার যোগ করুন', 'Add a driver'))),
        for (final n in drivers.keys)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              title: Text(n, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(t('মাসিক বেতন: ৳${fm(drivers[n] ?? 0)}', 'Monthly Salary: ৳${fm(drivers[n] ?? 0)}')),
              onTap: () => showDriverDetails(n),
              trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => editDriver(n)),
            ),
          ),
      ]);

  Widget reportTab() => Center(child: Text(t('রিপোর্ট', 'Report')));

  Widget documentTab() {
    final rs = [...rem]..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    return ListView(children: [
      Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: addRem, icon: const Icon(Icons.add), label: Text(t('রিমাইন্ডার যোগ করুন', 'Add Reminder')))),
      if (rs.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(t('কোনো রিমাইন্ডার নেই', 'No reminders'))),
      for (final r in rs)
        ListTile(
          title: Text(r['title']),
          subtitle: Text(fd(DateTime.parse(r['date']))),
          trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async {
            if (await ask(t('মুছবেন?', 'Delete?'))) {
              rem.removeWhere((x) => x['id'] == r['id']);
              save();
            }
          }),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final opts = [allCars, ...cars];
    if (!opts.contains(car)) car = allCars;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(t('গাড়ির হিসাব', 'Car Account')),
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
        actions: [
          IconButton(icon: const Icon(Icons.backup), onPressed: backup, tooltip: 'ব্যাকআপ'),
          IconButton(icon: const Icon(Icons.restore), onPressed: restore, tooltip: 'রিস্টোর'),
          Padding(padding: const EdgeInsets.only(right: 8), child: langToggle()),
        ],
      ),
      drawer: Drawer(
        child: ListView(padding: EdgeInsets.zero, children: [
          const DrawerHeader(decoration: BoxDecoration(color: Color(0xFF00695C)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
            Icon(Icons.directions_car, color: Colors.white, size: 40),
            SizedBox(height: 8),
            Text('গাড়ির হিসাব', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          ])),
          ListTile(leading: const Icon(Icons.route), title: Text(t('ট্রিপ', 'Trip')), onTap: () { Navigator.pop(context); openAddPage('trip'); }),
          ListTile(leading: const Icon(Icons.directions_car), title: Text(t('নিজে ব্যবহার', 'Personal Use')), onTap: () { Navigator.pop(context); openAddPage('self'); }),
          ListTile(leading: const Icon(Icons.arrow_upward), title: Text(t('খরচ', 'Expense')), onTap: () { Navigator.pop(context); openAddPage('out'); }),
        ]),
      ),
      body: [homeTab(), driverTab(), reportTab(), documentTab()][tab],
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() => tab = i),
            indicatorColor: Colors.blue.shade100,
            backgroundColor: Colors.white,
            destinations: [
              NavigationDestination(icon: const Icon(Icons.home), label: t('হোম', 'Home')),
              NavigationDestination(icon: const Icon(Icons.person), label: t('ড্রাইভার', 'Driver')),
              NavigationDestination(icon: const Icon(Icons.bar_chart), label: t('রিপোর্ট', 'Report')),
              NavigationDestination(icon: const Icon(Icons.description), label: t('ডকুমেন্ট', 'Document')),
            ],
          ),
        ),
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
    final old = widget.old;
    t = old?['type'] ?? widget.initialType;
    carC = TextEditingController(text: old?['car'] ?? (widget.currentCar != allCars ? widget.currentCar : (widget.cars.isNotEmpty ? widget.cars.first : 'আমার গাড়ি')));
    amtC = TextEditingController(text: old == null ? '' : fm(n0(old['amt'])));
    costC = TextEditingController(text: old == null ? '' : fm(n0(old['cost'])));
    noteC = TextEditingController(text: old?['note'] ?? '');
    commissionC = TextEditingController(text: old == null ? '' : fm(n0(old['commission'])));
    driverPayC = TextEditingController(text: old == null ? '' : fm(n0(old['driver_pay'])));
    cat = old?['cat'] ?? outCats.first;
    drv = old?['driver'] ?? noDrv;
    d = old == null ? DateTime.now() : DateTime.parse(old['date']);
    paidNow = old != null && n0(old['driver_pay']) > 0;
  }

  @override
  void dispose() {
    carC.dispose(); amtC.dispose(); costC.dispose(); noteC.dispose(); commissionC.dispose(); driverPayC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.old == null ? (t == 'trip' ? 'নতুন ট্রিপ' : t == 'self' ? 'নিজে ব্যবহার' : 'নতুন খরচ') : 'এডিট')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: carC, decoration: const InputDecoration(labelText: 'গাড়ির নাম/নম্বর', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: amtC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: t == 'trip' ? 'ট্রিপের ভাড়া (৳)' : 'পরিমাণ (৳)', border: const OutlineInputBorder())),
          if (t == 'trip' || t == 'self') ...[
            const SizedBox(height: 12),
            TextField(controller: costC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'খরচ (৳)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: commissionC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'ড্রাইভারের কমিশন (৳)', border: OutlineInputBorder())),
            CheckboxListTile(value: paidNow, onChanged: (v) => setState(() => paidNow = v ?? false), title: const Text('এখনই দিয়ে দিয়েছি'), controlAffinity: ListTileControlAffinity.leading),
            if (paidNow) TextField(controller: driverPayC, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'কত দিয়েছি (৳)', border: OutlineInputBorder())),
          ],
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
          FilledButton(
            onPressed: () {
              final a = double.tryParse(amtC.text.trim());
              if (a == null || a <= 0) return;
              final commission = double.tryParse(commissionC.text.trim()) ?? 0;
              double paid = paidNow ? (double.tryParse(driverPayC.text.trim()) ?? commission) : 0;
              Navigator.pop(context, {
                'id': widget.old?['id'] ?? DateTime.now().millisecondsSinceEpoch,
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
            child: const Text('সংরক্ষণ করুন'),
          ),
        ]),
      ),
    );
  }
}
