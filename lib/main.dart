import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// ───────────────────────── Model ─────────────────────────

class Word {
  final String en;
  final String tk;
  bool learned;
  Word(this.en, this.tk, {this.learned = false});
  Map<String, dynamic> toJson() => {'en': en, 'tk': tk, 'l': learned};
  factory Word.fromJson(Map<String, dynamic> j) =>
      Word(j['en'] as String, j['tk'] as String, learned: j['l'] == true);
}

const seedWords = <List<String>>[
  ['Hello', 'Salam'],
  ['Good morning', 'Ertiriň haýyrly bolsun'],
  ['Good night', 'Gijäň rahat bolsun'],
  ['Welcome', 'Hoş geldiň'],
  ['Goodbye', 'Hoş galyň'],
  ['Thank you', 'Sag bol'],
  ['Please', 'Haýyş'],
  ['Yes', 'Hawa'],
  ['No', 'Ýok'],
  ['How are you?', 'Işleriň nähili?'],
  ['What is your name?', 'Adyň näme?'],
  ['My name is ...', 'Meniň adym ...'],
  ['Where are you from?', 'Sen nireden?'],
  ['I love you', 'Men seni söýýärin'],
  ['I am learning English', 'Men iňlis dilini öwrenýärin'],
  ["I don't understand", 'Men düşünemok'],
  ['Can you help me?', 'Maňa kömek edip bilersiňmi?'],
  ['How much is it?', 'Bu näçeden?'],
  ['I am hungry', 'Men aç'],
  ['See you tomorrow', 'Ertir görüşeris'],
  ['Water', 'Suw'],
  ['Bread', 'Çörek'],
  ['Tea', 'Çaý'],
  ['Apple', 'Alma'],
  ['Book', 'Kitap'],
  ['Friend', 'Dost'],
  ['Family', 'Maşgala'],
  ['School', 'Mekdep'],
  ['Teacher', 'Mugallym'],
  ['House', 'Öý'],
  ['Mother', 'Ene'],
  ['Father', 'Kaka'],
  ['Sun', 'Gün'],
  ['Moon', 'Aý'],
  ['Night', 'Gije'],
  ['Time', 'Wagt'],
  ['Work', 'Iş'],
  ['Money', 'Pul'],
  ['City', 'Şäher'],
  ['Car', 'Awtoulag'],
  ['Eat', 'Iýmek'],
  ['Drink', 'Içmek'],
  ['Read', 'Okamak'],
  ['Write', 'Ýazmak'],
  ['Big', 'Uly'],
  ['Small', 'Kiçi'],
  ['Beautiful', 'Owadan'],
  ['Fast', 'Çalt'],
  ['Happy', 'Bagtly'],
  ['Today', 'Şu gün'],
];

// ───────────────────────── State ─────────────────────────

class AppState extends ChangeNotifier {
  List<Word> words = [];
  List<String> times = ['09:00', '13:00', '19:00'];
  bool enabled = true;
  bool randomMode = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final raw = p.getString('words');
    if (raw == null) {
      words = seedWords.map((e) => Word(e[0], e[1])).toList();
    } else {
      words = (jsonDecode(raw) as List)
          .map((e) => Word.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    times = p.getStringList('times') ?? times;
    enabled = p.getBool('enabled') ?? true;
    randomMode = p.getBool('random') ?? false;
  }

  Future<void> reload() async {
    await load();
    notifyListeners();
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('words', jsonEncode(words.map((w) => w.toJson()).toList()));
    await p.setStringList('times', times);
    await p.setBool('enabled', enabled);
    await p.setBool('random', randomMode);
    notifyListeners();
    await Notifier.reschedule();
  }

  List<Word> get pool => words.where((w) => !w.learned).toList();
  int get learnedCount => words.where((w) => w.learned).length;

  Word? wordOfDay() {
    final words = pool;
    if (words.isEmpty) return null;
    final day = DateTime.utc(DateTime.now().year, DateTime.now().month,
            DateTime.now().day)
        .difference(DateTime.utc(1970))
        .inDays;
    return words[day % words.length];
  }

  String? nextTime() {
    if (!enabled || times.isEmpty || pool.isEmpty) return null;
    final now = DateTime.now();
    final sorted = [...times]..sort();
    for (final t in sorted) {
      final p = t.split(':');
      final dt = DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
      if (dt.isAfter(now)) return t;
    }
    return sorted.first;
  }
}

final appState = AppState();

Future<void> markKnown(String? en) async {
  if (en == null) return;
  for (final w in appState.words) {
    if (w.en == en) w.learned = true;
  }
  await appState.save();
}

@pragma('vm:entry-point')
Future<void> notificationBackground(NotificationResponse r) async {
  if (r.actionId != 'known') return;
  DartPluginRegistrant.ensureInitialized();
  await Notifier.init();
  await appState.load();
  await markKnown(r.payload);
}

Future<void> openAndroid(String action, {String? data}) async {
  try {
    await AndroidIntent(action: action, data: data).launch();
  } catch (_) {}
}

final FlutterTts tts = FlutterTts();
Future<void> speakEn(String text) async {
  try {
    await tts.setLanguage('en-US');
    await tts.setSpeechRate(0.45);
    await tts.stop();
    await tts.speak(text);
  } catch (_) {}
}

// ───────────────────────── Notifications ─────────────────────────

class Notifier {
  static final plugin = FlutterLocalNotificationsPlugin();

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await plugin.initialize(
      init,
      onDidReceiveNotificationResponse: (r) {
        if (r.actionId == 'known') markKnown(r.payload);
      },
      onDidReceiveBackgroundNotificationResponse: notificationBackground,
    );
  }

  static Future<void> requestNotifPermission() async {
    await _android?.requestNotificationsPermission();
  }

  static Future<void> requestExactPermission() async {
    await _android?.requestExactAlarmsPermission();
  }

  static NotificationDetails _details(String body) => NotificationDetails(
        android: AndroidNotificationDetails(
          'soz_channel_v1',
          'Söz ýatlatmalary',
          channelDescription: 'Iňlis-Türkmen söz ýatlatmalary',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          category: AndroidNotificationCategory.reminder,
          styleInformation: BigTextStyleInformation(body),
          actions: const [
            AndroidNotificationAction('known', 'Bilýärin ✅',
                cancelNotification: true),
          ],
        ),
      );

  static Word _pick(List<Word> words, DateTime dt, int slot, int n) {
    if (appState.randomMode) {
      return words[Random(dt.millisecondsSinceEpoch).nextInt(words.length)];
    }
    final day = DateTime.utc(dt.year, dt.month, dt.day)
        .difference(DateTime.utc(1970))
        .inDays;
    return words[(day * n + slot) % words.length];
  }

  static Future<void> reschedule() async {
    await plugin.cancelAll();
    final pool = appState.pool;
    if (!appState.enabled || pool.isEmpty || appState.times.isEmpty) {
      return;
    }
    final times = [...appState.times]..sort();
    final now = DateTime.now();
    final days = min(30, 300 ~/ times.length);
    final canExact = await _android?.canScheduleExactNotifications() ?? false;
    final mode = canExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    var id = 1;
    for (var d = 0; d <= days; d++) {
      for (var s = 0; s < times.length; s++) {
        final p = times[s].split(':');
        final dt = DateTime(now.year, now.month, now.day + d,
            int.parse(p[0]), int.parse(p[1]));
        if (!dt.isAfter(now.add(const Duration(seconds: 3)))) continue;
        final w = _pick(pool, dt, s, times.length);
        try {
          await plugin.zonedSchedule(
            id++,
            w.en,
            w.tk,
            tz.TZDateTime.from(dt, tz.UTC),
            _details(w.tk),
            androidScheduleMode: mode,
            payload: w.en,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
        } catch (_) {}
      }
    }
  }

  static Future<void> showTest() async {
    final w = appState.wordOfDay() ?? Word('Hello', 'Salam');
    await plugin.show(0, w.en, w.tk, _details(w.tk), payload: w.en);
  }
}

// ───────────────────────── App ─────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appState.load();
  await Notifier.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Söz Ýatlatma',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B3FD9)),
      ),
      home: const HomePage(),
    );
  }
}

// ───────────────────────── Home ─────────────────────────

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Word? _shown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _shown = null;
      appState.reload();
    }
  }

  Future<void> _init() async {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool('asked') ?? false)) {
      await Notifier.requestNotifPermission();
      await Notifier.requestExactPermission();
      await p.setBool('asked', true);
    }
    await Notifier.reschedule();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      drawer: const AppDrawer(),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final w = _shown ?? appState.wordOfDay();
          final next = appState.nextTime();
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              const _Header(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Transform.translate(
                  offset: const Offset(0, -40),
                  child: Column(
                    children: [
                      Card(
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            children: [
                              Text('Şu günüň sözi',
                                  style: TextStyle(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 14),
                              Text(w?.en ?? 'Hemme sözi öwrendiňiz! 🎉',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 28, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text(w?.tk ?? '',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 20, color: cs.secondary)),
                              const SizedBox(height: 10),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 4,
                                children: [
                                  TextButton.icon(
                                    onPressed: w == null
                                        ? null
                                        : () => speakEn(w.en),
                                    icon: const Icon(Icons.volume_up),
                                    label: const Text('Diňle'),
                                  ),
                                  TextButton.icon(
                                    onPressed: appState.pool.isEmpty
                                        ? null
                                        : () => setState(() => _shown =
                                            appState.pool[Random().nextInt(
                                                appState.pool.length)]),
                                    icon: const Icon(Icons.shuffle),
                                    label: const Text('Başga'),
                                  ),
                                  TextButton.icon(
                                    onPressed: w == null
                                        ? null
                                        : () {
                                            w.learned = true;
                                            _shown = null;
                                            appState.save();
                                          },
                                    icon: const Icon(Icons.check_circle_outline),
                                    label: const Text('Öwrendim'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: _Stat(
                                icon: Icons.menu_book,
                                title:
                                    '${appState.learnedCount}/${appState.words.length}',
                                sub: 'öwrenilen')),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _Stat(
                                icon: Icons.alarm,
                                title: '${appState.times.length}',
                                sub: 'gündeki wagt')),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _Stat(
                                icon: Icons.notifications_active,
                                title: next ?? 'Öçük',
                                sub: 'indiki')),
                      ]),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  const _Stat({required this.icon, required this.title, required this.sub});
  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 6),
          Text(title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(sub, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 320,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A1C9E), Color(0xFF7B4DFF), Color(0xFF00B8D4)],
        ),
        borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
      ),
      child: Stack(
        children: [
          Positioned(top: -40, right: -30, child: _circle(160, 0.10)),
          Positioned(top: 90, left: -50, child: _circle(130, 0.08)),
          Positioned(bottom: -20, right: 60, child: _circle(90, 0.12)),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _bubble('Hello', Colors.white, const Color(0xFF3A1C9E)),
                        const SizedBox(width: 10),
                        const Icon(Icons.swap_horiz, color: Colors.white, size: 34),
                        const SizedBox(width: 10),
                        _bubble('Salam', const Color(0xFFFFD54F),
                            const Color(0xFF3A1C9E)),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const Icon(Icons.translate, color: Colors.white, size: 54),
                    const SizedBox(height: 10),
                    const Text('Söz Ýatlatma',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text('Her gün täze söz — ýatda galsyn!',
                        style: TextStyle(color: Colors.white70, fontSize: 15)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _circle(double s, double o) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
            shape: BoxShape.circle, color: Colors.white.withOpacity(o)),
      );

  static Widget _bubble(String t, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(t,
            style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 18)),
      );
}

// ───────────────────────── Drawer ─────────────────────────

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            height: 170,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF3A1C9E), Color(0xFF00B8D4)]),
            ),
            alignment: Alignment.bottomLeft,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.translate, color: Colors.white, size: 40),
                SizedBox(height: 8),
                Text('Söz Ýatlatma',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home_rounded),
            title: const Text('Baş sahypa'),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.settings_rounded),
            title: const Text('Sazlamalar'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()));
            },
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Settings ─────────────────────────

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sazlamalar'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.alarm), text: 'Wagtlar'),
            Tab(icon: Icon(Icons.menu_book), text: 'Sözler'),
          ]),
        ),
        body: const TabBarView(children: [TimesTab(), WordsTab()]),
      ),
    );
  }
}

class TimesTab extends StatelessWidget {
  const TimesTab({super.key});

  Future<void> _addTime(BuildContext context) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t == null) return;
    final s =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (!appState.times.contains(s)) {
      appState.times.add(s);
      await appState.save();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final times = [...appState.times]..sort();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: SwitchListTile(
                title: const Text('Ýatlatmalar'),
                subtitle: const Text('Sesli bildirişi açyp/ýapmak'),
                value: appState.enabled,
                onChanged: (v) {
                  appState.enabled = v;
                  appState.save();
                },
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sözleriň tertibi',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Yzygiderli')),
                          ButtonSegment(value: true, label: Text('Tötänleýin')),
                        ],
                        selected: {appState.randomMode},
                        onSelectionChanged: (s) {
                          appState.randomMode = s.first;
                          appState.save();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Her günki wagtlar',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            for (final t in times)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.alarm),
                  title: Text(t,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      appState.times.remove(t);
                      appState.save();
                    },
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _addTime(context),
              icon: const Icon(Icons.add_alarm),
              label: const Text('Wagt goş'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await Notifier.requestNotifPermission();
                await Notifier.showTest();
              },
              icon: const Icon(Icons.volume_up),
              label: const Text('Sesli synag'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await Notifier.requestExactPermission();
                await Notifier.reschedule();
              },
              icon: const Icon(Icons.verified_user),
              label: const Text('Dogry minutda işlemäge rugsat'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => openAndroid(
                  'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS'),
              icon: const Icon(Icons.battery_saver),
              label: const Text('Batareýa sazlamalaryny aç'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => openAndroid(
                  'android.settings.APPLICATION_DETAILS_SETTINGS',
                  data: 'package:com.oraz.soz_yatlatma'),
              icon: const Icon(Icons.settings_applications),
              label: const Text('Programma sazlamalary (rugsatlar)'),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 12, 4, 24),
              child: Text(
                'Maslahat: Batareýa sazlamalarynda "Söz Ýatlatma" programmasyny '
                '"Çäksiz" (Unrestricted) edip goýuň we mümkin bolsa "Autostart" '
                'açyň. Şonda ýatlatmalar telefon ýapyk ýa-da programma ýapyk '
                'wagty hem dogry gelýär.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
          ],
        );
      },
    );
  }
}

class WordsTab extends StatefulWidget {
  const WordsTab({super.key});
  @override
  State<WordsTab> createState() => _WordsTabState();
}

class _WordsTabState extends State<WordsTab> {
  final _en = TextEditingController();
  final _tk = TextEditingController();

  @override
  void dispose() {
    _en.dispose();
    _tk.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final en = _en.text.trim();
    final tk = _tk.text.trim();
    if (en.isEmpty || tk.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Iki meýdany hem dolduryň')));
      return;
    }
    appState.words.add(Word(en, tk));
    _en.clear();
    _tk.clear();
    FocusScope.of(context).unfocus();
    await appState.save();
  }

  Future<void> _import() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Köp söz goş'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Her setire bir söz: iňlisçe = türkmençe'),
            const SizedBox(height: 8),
            TextField(
              controller: c,
              maxLines: 8,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Apple = Alma\nBook = Kitap'),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ýatyr')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Goş')),
        ],
      ),
    );
    final text = c.text;
    c.dispose();
    if (ok != true) return;
    final existing = appState.words.map((w) => w.en.toLowerCase()).toSet();
    var added = 0;
    for (final line in text.split('\n')) {
      final l = line.trim();
      if (l.isEmpty) continue;
      String? en, tk;
      for (final sep in ['=', '|', ';', '\t', ' - ', ' – ']) {
        final i = l.indexOf(sep);
        if (i > 0) {
          en = l.substring(0, i).trim();
          tk = l.substring(i + sep.length).trim();
          break;
        }
      }
      if (en == null || tk == null || en.isEmpty || tk.isEmpty) continue;
      if (existing.contains(en.toLowerCase())) continue;
      existing.add(en.toLowerCase());
      appState.words.add(Word(en, tk));
      added++;
    }
    if (added > 0) await appState.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$added söz goşuldy')));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final words = appState.words;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                TextField(
                  controller: _en,
                  decoration: const InputDecoration(
                      labelText: 'Iňlisçe söz / sözlem',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _tk,
                  decoration: const InputDecoration(
                      labelText: 'Türkmençesi', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: const Text('Goş'),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                        'Jemi: ${words.length} · Öwrenilen: ${appState.learnedCount}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  TextButton.icon(
                    onPressed: _import,
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Köp goş'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: words.length,
                itemBuilder: (context, i) {
                  final idx = words.length - 1 - i; // iň täzesi ýokarda
                  final w = words[idx];
                  return Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      title: Text(w.en,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: w.learned ? Colors.grey : null,
                              decoration: w.learned
                                  ? TextDecoration.lineThrough
                                  : null)),
                      subtitle: Text(w.tk),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.volume_up),
                            onPressed: () => speakEn(w.en),
                          ),
                          IconButton(
                            tooltip: 'Öwrendim',
                            icon: Icon(
                                w.learned
                                    ? Icons.check_circle
                                    : Icons.check_circle_outline,
                                color: w.learned ? Colors.green : null),
                            onPressed: () {
                              w.learned = !w.learned;
                              appState.save();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () {
                              appState.words.removeAt(idx);
                              appState.save();
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
