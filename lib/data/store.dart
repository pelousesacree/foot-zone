// Foot Zone — enregistrement des tournois sur le téléphone (un fichier JSON par tournoi).
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../engine/engine.dart';
import '../engine/models.dart';
import '../l10n/strings.dart';

class AppStore extends ChangeNotifier {
  final Map<String, Tournament> _all = {};
  String lang = 'fr';
  bool loaded = false;
  String? loadError;
  Directory? _dir;
  final Map<String, Future<void>> _writing = {};

  List<Tournament> get tournaments => _all.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  Tournament? byId(String id) => _all[id];

  Future<void> load() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/footzone');
      if (!await dir.exists()) await dir.create(recursive: true);
      _dir = dir;
      final prefs = File('${dir.path}/settings.json');
      var seeded = false;
      if (await prefs.exists()) {
        final j = jsonDecode(await prefs.readAsString());
        if (j is Map) {
          if (j['lang'] == 'fr' || j['lang'] == 'en') lang = j['lang'] as String;
          seeded = j['seeded'] == true;
        }
      } else {
        lang = ui.PlatformDispatcher.instance.locale.languageCode == 'fr' ? 'fr' : 'en';
      }
      L.lang = lang;
      await for (final f in dir.list()) {
        if (f is File && f.path.endsWith('.json') && !f.path.endsWith('settings.json')) {
          try {
            final t = Tournament.tryFromJson(jsonDecode(await f.readAsString()));
            if (t != null) _all[t.id] = t;
          } catch (_) {
            // Fichier abîmé : on l'ignore sans bloquer l'app.
          }
        }
      }
      if (_all.isEmpty && !seeded) {
        final t = ExampleTournament.build();
        _all[t.id] = t;
        await _writeNow(t);
      }
      await _savePrefs(seeded: true);
    } catch (e) {
      loadError = '$e';
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _savePrefs({bool seeded = true}) async {
    final dir = _dir;
    if (dir == null) return;
    final f = File('${dir.path}/settings.json');
    await f.writeAsString(jsonEncode({'lang': lang, 'seeded': seeded}));
  }

  void setLang(String l) {
    lang = l;
    L.lang = l;
    notifyListeners();
    _savePrefs();
  }

  /// Enregistre le tournoi : recalcule le tableau puis écrit le fichier.
  void save(Tournament t) {
    if (t.hasKo) FZ.resolveBracket(t);
    t.updatedAt = nowMs();
    _all[t.id] = t;
    notifyListeners();
    _queueWrite(t);
  }

  void add(Tournament t) => save(t);

  void remove(String id) {
    _all.remove(id);
    notifyListeners();
    final dir = _dir;
    if (dir == null) return;
    final prev = _writing[id] ?? Future.value();
    _writing[id] = prev.then((_) async {
      final f = File('${dir.path}/$id.json');
      if (await f.exists()) await f.delete();
    }).catchError((_) {});
  }

  void _queueWrite(Tournament t) {
    final prev = _writing[t.id] ?? Future.value();
    _writing[t.id] = prev.then((_) => _writeNow(t)).catchError((_) {});
  }

  Future<void> _writeNow(Tournament t) async {
    final dir = _dir;
    if (dir == null) return;
    final data = jsonEncode(t.toJson());
    final tmp = File('${dir.path}/${t.id}.json.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename('${dir.path}/${t.id}.json');
  }

  /// Fichier de sauvegarde à partager.
  Future<File> exportFile(Tournament t) async {
    final dir = await getTemporaryDirectory();
    final safe = t.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    final f = File('${dir.path}/footzone-${safe.isEmpty ? 'tournoi' : safe}.json');
    await f.writeAsString(const JsonEncoder.withIndent(' ').convert(t.toJson()));
    return f;
  }

  /// Ouvre une sauvegarde. Renvoie le tournoi importé, ou null si le fichier n'est pas valide.
  Tournament? importJson(String text) {
    try {
      final t = Tournament.tryFromJson(jsonDecode(text));
      if (t == null) return null;
      if (_all.containsKey(t.id)) t.id = newId('T');
      t.example = false;
      save(t);
      return t;
    } catch (_) {
      return null;
    }
  }
}

class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child}) : super(notifier: store);

  static AppStore of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;
  static AppStore read(BuildContext context) => context.getInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}

/// Tournoi d'exemple ouvert au premier lancement.
class ExampleTournament {
  static Tournament build() {
    final r = Random();
    final names = ['Étoile FC', 'Lions du Port', 'Racing Club', 'Union Sportive', 'Olympique Est', 'Atlético Centre', 'Jeunesse FC', 'Dynamo Nord'];
    final first = ['Moussa', 'Ibrahima', 'Alpha', 'Mamadou', 'Sékou', 'Ousmane', 'Lamine', 'Karim', 'Yacouba', 'Boubacar', 'Abdoulaye', 'Thomas', 'Kevin', 'Idrissa', 'Souleymane', 'Amadou'];
    final last = ['Diallo', 'Bah', 'Camara', 'Sow', 'Barry', 'Traoré', 'Koné', 'Sylla', 'Keita', 'Touré', 'Fofana', 'Condé', 'Kouyaté', 'Cissé', 'Doumbouya', 'Soumah'];
    final t = FZ.createTournament(
      TournamentConfig(
        name: L.lang == 'fr' ? 'Coupe du quartier' : 'Neighbourhood Cup',
        place: L.lang == 'fr' ? 'Terrain municipal' : 'Town pitch',
        format: Fmt.groups,
        teamNames: names,
        settings: Settings(groupCount: 2, qualifiers: 2, gameType: 7, halfMinutes: 25, etMinutes: 5, thirdPlace: true),
      ),
      r,
    );
    t.example = true;
    T pick<T>(List<T> a) => a[r.nextInt(a.length)];
    for (final tm in t.teams) {
      final nums = FZ.shuffle([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 14, 17, 21], r).take(9).toList();
      tm.players = nums.map((n) => Player(id: newId('p'), num: '$n', name: '${pick(first)} ${pick(last)}')).toList();
    }
    final group = t.games.where((g) => g.stage == 'group').toList();
    void sim(Game m, int until) {
      final ev = <MatchEvent>[];
      for (final side in [m.home!, m.away!]) {
        final tm = t.team(side)!;
        final goals = r.nextInt(4);
        for (var i = 0; i < goals; i++) {
          final p = pick(tm.players);
          final e = MatchEvent(id: newId('e'), type: r.nextDouble() < 0.12 ? 'pen' : 'goal', teamId: side, playerId: p.id, minute: 1 + r.nextInt(until));
          if (e.type == 'goal' && r.nextDouble() < 0.55) e.assistId = pick(tm.players.where((q) => q.id != p.id).toList()).id;
          ev.add(e);
        }
        if (r.nextDouble() < 0.45) ev.add(MatchEvent(id: newId('e'), type: 'yellow', teamId: side, playerId: pick(tm.players).id, minute: 1 + r.nextInt(until)));
      }
      ev.sort((a, b) => (a.minute ?? 0).compareTo(b.minute ?? 0));
      m.events = ev;
    }

    for (var i = 0; i < group.length - 2; i++) {
      final m = group[i];
      sim(m, 50);
      m.status = Status.done;
      m.phase = Phase.ft;
      final sc = m.events.where((e) => e.isGoal).toList();
      if (sc.isNotEmpty) m.motm = pick(sc).playerId;
    }
    final live = group[group.length - 2];
    sim(live, 33);
    live.status = Status.live;
    live.phase = Phase.h2;
    live.phaseStart = nowMs() - 8 * 60000;
    return t;
  }
}
