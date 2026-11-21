// Foot Zone — moteur de calcul : calendrier, classements, tableaux,
// aller-retour, forfaits, statistiques, suspensions, chronomètre.
// Fonctions pures sur le modèle ; aucune dépendance Flutter.
import 'dart:math';

import 'models.dart';

class Score {
  final int h;
  final int a;
  const Score(this.h, this.a);
}

class StandRow {
  final String team;
  int j = 0, g = 0, n = 0, p = 0, bp = 0, bc = 0, fp = 0, pts = 0;
  int rank = 0;
  bool live = false;
  bool lot = false;
  final List<String> form = [];
  StandRow(this.team);
  int get diff => bp - bc;
}

class RoundPairs {
  final List<List<String>> pairs;
  final List<String> rest;
  RoundPairs(this.pairs, this.rest);
}

class FzError implements Exception {
  final String key;
  final Map<String, String> args;
  FzError(this.key, [this.args = const {}]);
  @override
  String toString() => 'FzError($key, $args)';
}

class TournamentConfig {
  String name;
  String place;
  String format;
  List<String> teamNames;
  Settings settings;
  String drawMode; // auto | manual
  /// Tirage manuel des poules : pour chaque poule, les index des équipes.
  List<List<int>>? manualGroups;

  /// Tirage manuel du tableau : ordre des équipes. Les premières reçoivent
  /// les exemptions, puis les matchs se forment deux par deux.
  List<int>? manualOrder;

  TournamentConfig({
    this.name = '',
    this.place = '',
    this.format = Fmt.league,
    List<String>? teamNames,
    Settings? settings,
    this.drawMode = 'auto',
    this.manualGroups,
    this.manualOrder,
  })  : teamNames = teamNames ?? <String>[],
        settings = settings ?? Settings();
}

class PStat {
  final String id;
  final String name;
  final String num;
  final String teamId;
  int goals = 0, pens = 0, og = 0, assists = 0, yellow = 0, red = 0, motm = 0;
  final Set<String> games = {};
  PStat(this.id, this.name, this.num, this.teamId);
  int get played => games.length;
  int get rating => goals * 4 + assists * 3 + motm * 5 - yellow - red * 3;
}

class Suspensions {
  final Map<String, List<String>> byGame;
  final Map<String, int> remaining;
  final Map<String, int> yellows;
  Suspensions(this.byGame, this.remaining, this.yellows);
}

class ClockInfo {
  final String? label; // texte du chrono, ou null si `state` doit être traduit
  final String state; // pre, ht, pens, ft, running
  final int minute;
  final int extra;
  final bool running;
  final bool overtime; // le temps réglementaire de la période est dépassé
  const ClockInfo({this.label, required this.state, this.minute = 0, this.extra = 0, this.running = false, this.overtime = false});
}

const teamPalette = <int>[
  0xFF1D4ED8, 0xFFC2410C, 0xFF15803D, 0xFF7C3AED, 0xFFBE123C, 0xFF0E7490, 0xFFA16207, 0xFF334155,
  0xFFDB2777, 0xFF0F766E, 0xFF111827, 0xFFB91C1C, 0xFF4D7C0F, 0xFF0369A1, 0xFFC026D3, 0xFFEA580C,
];

const groupLetters = 'ABCDEFGHIJKLMNOP';

class FZ {
  // ------------------------------------------------------------ outils
  static List<T> shuffle<T>(List<T> list, [Random? r]) {
    final a = List<T>.of(list);
    a.shuffle(r ?? Random.secure());
    return a;
  }

  static int nextPow2(int n) {
    var p = 1;
    while (p < n) {
      p *= 2;
    }
    return p;
  }

  // ------------------------------------------------- calendrier (Berger)
  static List<RoundPairs> roundRobin(List<String> ids, int legs) {
    final list = <String?>[...ids];
    if (list.length < 2) return [];
    if (list.length.isOdd) list.add(null);
    final n = list.length;
    final fixed = list[0];
    var rot = list.sublist(1);
    final rounds = <RoundPairs>[];
    for (var r = 0; r < n - 1; r++) {
      final cur = <String?>[fixed, ...rot];
      final pairs = <List<String>>[];
      final rest = <String>[];
      for (var i = 0; i < n ~/ 2; i++) {
        var h = cur[i];
        var a = cur[n - 1 - i];
        if (i == 0 && r.isOdd) {
          final t = h;
          h = a;
          a = t;
        }
        if (h == null) {
          if (a != null) rest.add(a);
        } else if (a == null) {
          rest.add(h);
        } else {
          pairs.add([h, a]);
        }
      }
      rounds.add(RoundPairs(pairs, rest));
      rot = [rot.last, ...rot.sublist(0, rot.length - 1)];
    }
    if (legs == 2) {
      final back = rounds.map((rd) => RoundPairs(rd.pairs.map((p) => [p[1], p[0]]).toList(), List.of(rd.rest))).toList();
      return [...rounds, ...back];
    }
    return rounds;
  }

  // ------------------------------------------------------ score et vainqueur
  static Score score(Game m, Settings s) {
    final f = m.forfeit;
    if (f != null) {
      final g = s.forfeitGoals;
      return f == m.home ? Score(0, g) : Score(g, 0);
    }
    var h = 0, a = 0;
    for (final e in m.events) {
      if (e.cancelled || !e.isGoal) continue;
      if (e.teamId == m.home) {
        h++;
      } else if (e.teamId == m.away) {
        a++;
      }
    }
    return Score(h, a);
  }

  static String? _pensWinner(Game m) {
    final h = m.pensH, a = m.pensA;
    if (h == null || a == null || h == a) return null;
    return h > a ? m.home : m.away;
  }

  /// Vainqueur d'un match à élimination (ou de la double confrontation pour un match retour).
  static String? winner(Tournament t, Game m) {
    final s = t.settings;
    if (m.bye) return m.home ?? m.away;
    if (m.home == null || m.away == null) return null;
    if (m.leg == 1) return null;
    if (m.leg == 2) {
      final l1 = t.game(m.pairId);
      if (l1 == null) return null;
      if (l1.forfeit != null) return l1.forfeit == l1.home ? l1.away : l1.home;
      if (m.forfeit != null) return m.forfeit == m.home ? m.away : m.home;
      if (l1.status != Status.done || m.status != Status.done) return null;
      final s1 = score(l1, s), s2 = score(m, s);
      // L'équipe A reçoit à l'aller (l1.home) et joue à l'extérieur au retour (m.away).
      final aggA = s1.h + s2.a, aggB = s1.a + s2.h;
      if (aggA != aggB) return aggA > aggB ? m.away : m.home;
      if (s.awayGoals && s2.a != s1.a) return s2.a > s1.a ? m.away : m.home;
      return _pensWinner(m);
    }
    if (m.forfeit != null) return m.forfeit == m.home ? m.away : m.home;
    if (m.status != Status.done) return null;
    final sc = score(m, s);
    if (sc.h != sc.a) return sc.h > sc.a ? m.home : m.away;
    return _pensWinner(m);
  }

  static String? loser(Tournament t, Game m) {
    final w = winner(t, m);
    if (w == null || m.bye) return null;
    return w == m.home ? m.away : m.home;
  }

  /// Vrai si le match décisif est à égalité (score, ou cumul aller-retour et buts à l'extérieur).
  static bool koLevel(Tournament t, Game m) {
    if (m.stage != 'ko' || m.leg == 1 || m.bye || m.forfeit != null || !m.ready) return false;
    final s = t.settings;
    final s2 = score(m, s);
    if (m.leg == 2) {
      final l1 = t.game(m.pairId);
      if (l1 == null || l1.forfeit != null) return false;
      final s1 = score(l1, s);
      final aggA = s1.h + s2.a, aggB = s1.a + s2.h;
      if (aggA != aggB) return false;
      if (s.awayGoals && s2.a != s1.a) return false;
      return true;
    }
    return s2.h == s2.a;
  }

  /// Cumul aller-retour, vu depuis le match retour (domicile du retour d'abord).
  static Score? aggregate(Tournament t, Game m) {
    if (m.leg != 2) return null;
    final l1 = t.game(m.pairId);
    if (l1 == null) return null;
    final s1 = score(l1, t.settings), s2 = score(m, t.settings);
    return Score(s2.h + s1.a, s2.a + s1.h);
  }

  static bool _counts(Game m, bool live) {
    if (m.home == null || m.away == null || m.bye) return false;
    return m.status == Status.done || m.forfeit != null || (live && m.status == Status.live);
  }

  // ------------------------------------------------------------ classement
  static Map<String, StandRow> _rawTable(List<String> ids, List<Game> games, Settings s, bool live) {
    final set = ids.toSet();
    final rows = {for (final id in ids) id: StandRow(id)};
    for (final m in games) {
      if (!set.contains(m.home) || !set.contains(m.away) || !_counts(m, live)) continue;
      final sc = score(m, s);
      final h = rows[m.home]!, a = rows[m.away]!;
      h.j++;
      a.j++;
      h.bp += sc.h;
      h.bc += sc.a;
      a.bp += sc.a;
      a.bc += sc.h;
      if (sc.h > sc.a) {
        h.g++;
        a.p++;
        h.form.add('V');
        a.form.add('D');
      } else if (sc.h < sc.a) {
        a.g++;
        h.p++;
        a.form.add('V');
        h.form.add('D');
      } else {
        h.n++;
        a.n++;
        h.form.add('N');
        a.form.add('N');
      }
      if (m.status == Status.live) {
        h.live = true;
        a.live = true;
      }
      if (m.forfeit == null) {
        for (final e in m.events) {
          if (e.cancelled) continue;
          final r = rows[e.teamId];
          if (r == null) continue;
          if (e.type == 'yellow') r.fp += 1;
          if (e.type == 'red') r.fp += 3;
        }
      }
    }
    for (final r in rows.values) {
      r.pts = r.g * s.win + r.n * s.draw + r.p * s.loss;
      if (r.form.length > 5) r.form.removeRange(0, r.form.length - 5);
    }
    return rows;
  }

  static List<List<StandRow>> _partition(List<StandRow> group, List<int> Function(StandRow) key) {
    final keyed = group.map((r) => MapEntry(r, key(r))).toList();
    keyed.sort((x, y) {
      for (var i = 0; i < x.value.length; i++) {
        if (x.value[i] != y.value[i]) return y.value[i].compareTo(x.value[i]);
      }
      return 0;
    });
    final parts = <List<StandRow>>[];
    List<int>? lastKey;
    for (final it in keyed) {
      final same = lastKey != null && _eq(lastKey, it.value);
      if (same) {
        parts.last.add(it.key);
      } else {
        parts.add([it.key]);
        lastKey = it.value;
      }
    }
    return parts;
  }

  static bool _eq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static List<StandRow> _applySteps(List<StandRow> group, List<String> steps, List<Game> games, Settings s, Map<String, int> lots, bool live) {
    if (group.length <= 1 || steps.isEmpty) return group;
    final step = steps.first;
    final rest = steps.sublist(1);
    if (step == 'lot') {
      final sorted = List<StandRow>.of(group)..sort((a, b) => (lots[a.team] ?? 999).compareTo(lots[b.team] ?? 999));
      for (final r in sorted) {
        r.lot = true;
      }
      return sorted;
    }
    late List<int> Function(StandRow) key;
    if (step == 'h2h') {
      final mini = _rawTable(group.map((r) => r.team).toList(), games, s, live);
      key = (r) {
        final x = mini[r.team]!;
        return [x.pts, x.diff, x.bp];
      };
    } else if (step == 'gd') {
      key = (r) => [r.diff];
    } else if (step == 'gf') {
      key = (r) => [r.bp];
    } else if (step == 'wins') {
      key = (r) => [r.g];
    } else {
      key = (r) => [-r.fp];
    }
    final out = <StandRow>[];
    for (final part in _partition(group, key)) {
      if (part.length == 1) {
        out.add(part.first);
      } else if (step == 'h2h' && part.length < group.length) {
        // On réapplique la confrontation directe au sous-groupe encore à égalité.
        out.addAll(_applySteps(part, steps, games, s, lots, live));
      } else {
        out.addAll(_applySteps(part, rest, games, s, lots, live));
      }
    }
    return out;
  }

  static List<String> tiebreakSteps(Settings s) =>
      s.tiebreak == 'goals' ? ['gd', 'gf', 'h2h', 'wins', 'fp', 'lot'] : ['h2h', 'gd', 'gf', 'wins', 'fp', 'lot'];

  static List<StandRow> standings(List<String> ids, List<Game> games, Settings s, Map<String, int> lots, {bool live = false}) {
    final rows = _rawTable(ids, games, s, live).values.toList();
    final out = <StandRow>[];
    final steps = tiebreakSteps(s);
    for (final g in _partition(rows, (r) => [r.pts])) {
      out.addAll(_applySteps(g, steps, games, s, lots, live));
    }
    for (var i = 0; i < out.length; i++) {
      out[i].rank = i + 1;
    }
    return out;
  }

  // ---------------------------------------------------------------- poules
  static List<Group> drawGroups(List<String> ids, int groupCount, bool seeded, [Random? r]) {
    final buckets = List.generate(groupCount, (_) => <String>[]);
    if (seeded) {
      for (var p = 0; p * groupCount < ids.length; p++) {
        final end = min((p + 1) * groupCount, ids.length);
        final pot = shuffle(ids.sublist(p * groupCount, end), r);
        final order = shuffle(List.generate(groupCount, (i) => i), r)..sort((x, y) => buckets[x].length.compareTo(buckets[y].length));
        for (var i = 0; i < pot.length; i++) {
          buckets[order[i]].add(pot[i]);
        }
      }
    } else {
      final sh = shuffle(ids, r);
      for (var i = 0; i < sh.length; i++) {
        buckets[i % groupCount].add(sh[i]);
      }
    }
    return [for (var i = 0; i < groupCount; i++) Group(name: groupLetters[i], teamIds: buckets[i])];
  }

  // ----------------------------------------------- tableau éliminatoire
  static List<int> seedOrder(int size) {
    var o = <int>[1];
    while (o.length < size) {
      final n = o.length * 2;
      o = o.expand((x) => [x, n + 1 - x]).toList();
    }
    return o;
  }

  static List<String?> seededSlots(List<String> seeds) {
    final size = max(2, nextPow2(seeds.length));
    return seedOrder(size).map((k) => k <= seeds.length ? seeds[k - 1] : null).toList();
  }

  /// Tirage manuel : les premières équipes de la liste sont exemptées,
  /// les suivantes se rencontrent deux par deux, dans l'ordre.
  static List<String?> manualSlots(List<String> order) {
    final size = max(2, nextPow2(order.length));
    final byes = size - order.length;
    final slots = <String?>[];
    var i = 0;
    for (; i < byes; i++) {
      slots.addAll([order[i], null]);
    }
    for (; i < order.length; i++) {
      slots.add(order[i]);
    }
    return slots;
  }

  static List<Game> buildBracket(List<String?> slots, Settings s, {int legs = 1}) {
    final size = slots.length;
    var rounds = 0;
    while ((1 << rounds) < size) {
      rounds++;
    }
    final out = <Game>[];
    final deciders = <List<String>>[];
    for (var r = 1; r <= rounds; r++) {
      final count = size >> r;
      final roundSize = count * 2;
      final twoLegs = legs == 2 && count > 1; // la finale reste un match sec
      final cur = <String>[];
      for (var i = 0; i < count; i++) {
        Game mk(int leg) => Game(id: newId('m'), stage: 'ko', kround: r, pos: i, leg: leg, roundSize: roundSize);
        if (r == 1) {
          final h = slots[2 * i], a = slots[2 * i + 1];
          if (h == null || a == null) {
            final g = mk(0)
              ..home = h
              ..away = a
              ..bye = true
              ..status = Status.done
              ..phase = Phase.ft;
            out.add(g);
            cur.add(g.id);
            continue;
          }
          if (twoLegs) {
            final g1 = mk(1)
              ..home = h
              ..away = a;
            final g2 = mk(2)
              ..home = a
              ..away = h;
            g1.pairId = g2.id;
            g2.pairId = g1.id;
            out.addAll([g1, g2]);
            cur.add(g2.id);
          } else {
            final g = mk(0)
              ..home = h
              ..away = a;
            out.add(g);
            cur.add(g.id);
          }
        } else {
          final sa = deciders[r - 2][2 * i], sb = deciders[r - 2][2 * i + 1];
          if (twoLegs) {
            final g1 = mk(1)
              ..srcHome = Src(sa, true)
              ..srcAway = Src(sb, true);
            final g2 = mk(2)
              ..srcHome = Src(sb, true)
              ..srcAway = Src(sa, true);
            g1.pairId = g2.id;
            g2.pairId = g1.id;
            out.addAll([g1, g2]);
            cur.add(g2.id);
          } else {
            final g = mk(0)
              ..srcHome = Src(sa, true)
              ..srcAway = Src(sb, true);
            out.add(g);
            cur.add(g.id);
          }
        }
      }
      deciders.add(cur);
    }
    if (s.thirdPlace && rounds >= 2) {
      final semis = deciders[rounds - 2];
      final third = Game(id: newId('m'), stage: 'ko', kround: rounds, pos: -1, third: true, roundSize: 2)
        ..srcHome = Src(semis[0], false)
        ..srcAway = Src(semis[1], false);
      out.insert(out.length - 1, third);
    }
    return out;
  }

  static List<String?> avoidSameGroup(List<String?> slots, Map<String, String> groupOf) {
    final pairs = slots.length ~/ 2;
    bool clash(int i) {
      final a = slots[2 * i], b = slots[2 * i + 1];
      return a != null && b != null && groupOf[a] == groupOf[b];
    }

    for (var i = 0; i < pairs; i++) {
      if (!clash(i)) continue;
      for (var j = 0; j < pairs; j++) {
        if (j == i || slots[2 * j + 1] == null) continue;
        final ai = slots[2 * i]!, bi = slots[2 * i + 1]!, aj = slots[2 * j], bj = slots[2 * j + 1]!;
        if (groupOf[ai] != groupOf[bj] && (aj == null || groupOf[aj] != groupOf[bi])) {
          slots[2 * i + 1] = bj;
          slots[2 * j + 1] = bi;
          break;
        }
      }
    }
    return slots;
  }

  static void _resetGame(Game m) {
    m.status = Status.scheduled;
    m.phase = Phase.pre;
    m.phaseStart = null;
    m.added = 0;
    m.events = [];
    m.pensH = null;
    m.pensA = null;
    m.forfeit = null;
    m.motm = null;
  }

  static void _setForfeit(Game m, String teamId) {
    m.forfeit = teamId;
    m.status = Status.done;
    m.phase = Phase.ft;
  }

  /// Place les vainqueurs dans les tours suivants et applique les forfaits des équipes retirées.
  static void resolveBracket(Tournament t) {
    final withdrawn = t.teams.where((x) => x.withdrawn).map((x) => x.id).toSet();
    final ko = t.games.where((g) => g.stage == 'ko').toList()
      ..sort((a, b) {
        final c = a.kround.compareTo(b.kround);
        if (c != 0) return c;
        final d = (a.third ? 1 : 0) - (b.third ? 1 : 0);
        if (d != 0) return d;
        return a.leg.compareTo(b.leg);
      });
    for (final m in ko) {
      for (final home in [true, false]) {
        final src = home ? m.srcHome : m.srcAway;
        if (src == null) continue;
        final sm = t.game(src.id);
        final v = sm == null ? null : (src.winner ? winner(t, sm) : loser(t, sm));
        final cur = home ? m.home : m.away;
        if (cur != v) {
          if (home) {
            m.home = v;
          } else {
            m.away = v;
          }
          if (m.status != Status.scheduled || m.forfeit != null) _resetGame(m);
        }
      }
      if (m.ready && m.status != Status.done) {
        if (withdrawn.contains(m.home)) {
          _setForfeit(m, m.home!);
        } else if (withdrawn.contains(m.away)) {
          _setForfeit(m, m.away!);
        }
      }
    }
  }

  /// Un match à élimination ne peut plus être modifié si le tour suivant a commencé.
  static bool koLocked(Tournament t, Game m) {
    if (m.stage != 'ko') return false;
    final decider = m.leg == 1 ? m.pairId : m.id;
    if (decider == null) return false;
    return t.games.any((x) =>
        (x.srcHome?.id == decider || x.srcAway?.id == decider) && x.status != Status.scheduled && x.forfeit == null);
  }

  // ------------------------------------------------- création du tournoi
  static FzError? validate(TournamentConfig c) {
    final names = c.teamNames.map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    if (c.name.trim().isEmpty) return FzError('errName');
    final lower = names.map((x) => x.toLowerCase()).toList();
    for (var i = 0; i < lower.length; i++) {
      if (lower.indexOf(lower[i]) != i) return FzError('errDuplicate', {'name': names[i]});
    }
    if (c.format == Fmt.single) {
      if (names.length != 2) return FzError('errSingleTwo');
      return null;
    }
    if (names.length < 2) return FzError('errMinTeams');
    if (names.length > 64) return FzError('errMaxTeams');
    final s = c.settings;
    if (c.format == Fmt.cup && s.thirdPlace && names.length < 4) return FzError('errThirdPlace');
    if (c.format == Fmt.groups) {
      final g = s.groupCount, q = s.qualifiers;
      if (g < 2) return FzError('errGroupsMin');
      if (names.length < g * 2) return FzError('errGroupsTeams', {'groups': '$g', 'teams': '${g * 2}'});
      if (q < 1 || q >= names.length ~/ g) return FzError('errQualifiers');
      if (s.thirdPlace && g * q < 4) return FzError('errThirdPlace');
      if (c.drawMode == 'manual') {
        final mg = c.manualGroups;
        if (mg == null || mg.length != g) return FzError('errManualGroups');
        final used = <int>{};
        for (final grp in mg) {
          if (grp.length < 2) return FzError('errGroupSize');
          used.addAll(grp);
        }
        if (used.length != names.length) return FzError('errManualGroups');
      }
    }
    if (c.format == Fmt.cup && c.drawMode == 'manual') {
      final o = c.manualOrder;
      if (o == null || o.toSet().length != names.length) return FzError('errManualOrder');
    }
    return null;
  }

  static Tournament createTournament(TournamentConfig c, [Random? r]) {
    final err = validate(c);
    if (err != null) throw err;
    final s = c.settings.copy();
    final names = c.teamNames.map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    final teams = <Team>[
      for (var i = 0; i < names.length; i++)
        Team(id: newId('t'), name: names[i].length > 40 ? names[i].substring(0, 40) : names[i], color: teamPalette[i % teamPalette.length]),
    ];
    final ids = teams.map((x) => x.id).toList();
    final lots = <String, int>{};
    final lotOrder = shuffle(ids, r);
    for (var i = 0; i < lotOrder.length; i++) {
      lots[lotOrder[i]] = i + 1;
    }
    final t = Tournament(
      id: newId('T'),
      name: c.name.trim(),
      place: c.place.trim(),
      format: c.format,
      settings: s,
      teams: teams,
      lots: lots,
      drawMode: c.drawMode,
    );
    final manual = c.drawMode == 'manual';
    switch (c.format) {
      case Fmt.league:
        t.games = _leagueGames(manual ? ids : shuffle(ids, r), s.legs, 'league', null);
        break;
      case Fmt.groups:
        if (manual) {
          final mg = c.manualGroups!;
          t.groups = [for (var i = 0; i < mg.length; i++) Group(name: groupLetters[i], teamIds: mg[i].map((k) => ids[k]).toList())];
        } else {
          t.groups = drawGroups(ids, s.groupCount, s.seeded, r);
        }
        final all = t.groups.map((g) => _leagueGames(g.teamIds, s.legs, 'group', g.name)).toList();
        final maxRound = all.fold<int>(0, (m, l) => l.isEmpty ? m : max(m, l.last.round));
        for (var rd = 1; rd <= maxRound; rd++) {
          for (final list in all) {
            t.games.addAll(list.where((g) => g.round == rd));
          }
        }
        break;
      case Fmt.single:
        t.games = buildBracket([ids[0], ids[1]], s, legs: 1);
        break;
      default:
        final slots = manual
            ? manualSlots(c.manualOrder!.map((k) => ids[k]).toList())
            : seededSlots(s.seeded ? ids : shuffle(ids, r));
        t.games = buildBracket(slots, s, legs: s.koLegs);
        resolveBracket(t);
    }
    for (var i = 0; i < t.games.length; i++) {
      t.games[i].seq = i + 1;
    }
    return t;
  }

  static List<Game> _leagueGames(List<String> ids, int legs, String stage, String? group) {
    final out = <Game>[];
    final rounds = roundRobin(ids, legs);
    for (var r = 0; r < rounds.length; r++) {
      for (final p in rounds[r].pairs) {
        out.add(Game(id: newId('m'), stage: stage, group: group, round: r + 1, home: p[0], away: p[1]));
      }
    }
    return out;
  }

  /// Équipes au repos pendant une journée (championnat ou poule).
  static List<String> resting(Tournament t, String stage, int round) {
    final scopes = t.format == Fmt.league ? [t.teams.map((x) => x.id).toList()] : t.groups.map((g) => g.teamIds).toList();
    final playing = <String>{};
    for (final g in t.games) {
      if (g.stage == stage && g.round == round) {
        if (g.home != null) playing.add(g.home!);
        if (g.away != null) playing.add(g.away!);
      }
    }
    return scopes.expand((x) => x).where((id) => !playing.contains(id)).toList();
  }

  static bool groupStageDone(Tournament t) =>
      t.games.where((g) => g.stage == 'group').every((g) => g.status == Status.done || g.forfeit != null);

  /// Qualifiés de chaque poule (projection si la phase de poules n'est pas finie).
  /// Une équipe retirée ne se qualifie jamais : la suivante prend sa place.
  static List<({String group, List<StandRow> table, List<StandRow> qualified})> qualifiers(Tournament t, {bool live = false}) {
    final s = t.settings;
    final withdrawn = t.teams.where((x) => x.withdrawn).map((x) => x.id).toSet();
    return t.groups.map((g) {
      final table = standings(g.teamIds, t.games.where((m) => m.group == g.name).toList(), s, t.lots, live: live);
      final eligible = table.where((r) => !withdrawn.contains(r.team)).toList();
      return (group: g.name, table: table, qualified: eligible.take(s.qualifiers).toList());
    }).toList();
  }

  static void generateFinalPhase(Tournament t) {
    if (t.format != Fmt.groups) throw FzError('errNoGroups');
    if (t.hasKo) throw FzError('errFinalExists');
    if (!groupStageDone(t)) throw FzError('errGroupsNotDone');
    final s = t.settings;
    final qs = qualifiers(t);
    final g = qs.length, q = s.qualifiers;
    final groupOf = <String, String>{};
    for (final x in qs) {
      for (final r in x.table) {
        groupOf[r.team] = x.group;
      }
    }
    final complete = qs.every((x) => x.qualified.length == q);
    late List<String?> slots;
    if (complete && q == 2 && g >= 2 && (g & (g - 1)) == 0) {
      // 1er A – 2e B dans le haut du tableau, 1er B – 2e A dans le bas…
      final top = <String?>[], bottom = <String?>[];
      for (var k = 0; k < g; k += 2) {
        final a = qs[k].qualified, b = qs[k + 1].qualified;
        top.addAll([a[0].team, b[1].team]);
        bottom.addAll([b[0].team, a[1].team]);
      }
      slots = [...top, ...bottom];
    } else {
      final seeds = <String>[];
      for (var pos = 0; pos < q; pos++) {
        final tier = qs.where((x) => x.qualified.length > pos).map((x) => x.qualified[pos]).toList();
        tier.sort((a, b) {
          final pa = a.pts / max(1, a.j), pb = b.pts / max(1, b.j);
          if (pa != pb) return pb.compareTo(pa);
          final da = a.diff / max(1, a.j), db = b.diff / max(1, b.j);
          if (da != db) return db.compareTo(da);
          if (a.bp != b.bp) return b.bp.compareTo(a.bp);
          return (t.lots[a.team] ?? 0).compareTo(t.lots[b.team] ?? 0);
        });
        seeds.addAll(tier.map((r) => r.team));
      }
      if (seeds.length < 2) throw FzError('errNotEnoughQualified');
      slots = avoidSameGroup(seededSlots(seeds), groupOf);
    }
    final ko = buildBracket(slots, s, legs: s.koLegs);
    var seq = t.games.fold<int>(0, (m, x) => max(m, x.seq));
    for (final m in ko) {
      m.seq = ++seq;
    }
    t.games.addAll(ko);
    resolveBracket(t);
  }

  // ---------------------------------------------------------- forfaits
  static int withdrawTeam(Tournament t, String teamId) {
    final team = t.team(teamId);
    if (team == null) return 0;
    team.withdrawn = true;
    var n = 0;
    for (final m in t.games) {
      if ((m.home == teamId || m.away == teamId) && m.status != Status.done && m.ready) {
        _setForfeit(m, teamId);
        n++;
      }
    }
    resolveBracket(t);
    return n;
  }

  // ------------------------------------------------ statistiques joueurs
  static List<PStat> playerStats(Tournament t) {
    final st = <String, PStat>{};
    PStat? get(String? id) {
      if (id == null) return null;
      final x = t.player(id);
      if (x == null) return null;
      return st.putIfAbsent(id, () => PStat(id, x.player.name, x.player.num, x.team.id));
    }

    for (final m in t.games) {
      if (m.status == Status.scheduled || m.forfeit != null || m.bye) continue;
      for (final e in m.events) {
        if (e.cancelled) continue;
        final r = get(e.playerId);
        if (r != null) {
          r.games.add(m.id);
          switch (e.type) {
            case 'goal':
              r.goals++;
              break;
            case 'pen':
              r.goals++;
              r.pens++;
              break;
            case 'og':
              r.og++;
              break;
            case 'yellow':
              r.yellow++;
              break;
            case 'red':
              r.red++;
              break;
          }
        }
        if (e.type == 'goal' && e.assistId != null) {
          final a = get(e.assistId);
          if (a != null) {
            a.assists++;
            a.games.add(m.id);
          }
        }
        if (e.type == 'sub' && e.inId != null) get(e.inId)?.games.add(m.id);
      }
      final mm = get(m.motm);
      if (mm != null) {
        mm.motm++;
        mm.games.add(m.id);
      }
    }
    return st.values.toList();
  }

  /// Classement des buteurs : même nombre de buts = même place ; le plus de passes s'affiche en premier.
  static List<({int rank, PStat s})> scorers(List<PStat> stats) {
    final list = stats.where((x) => x.goals > 0).toList()
      ..sort((a, b) {
        if (a.goals != b.goals) return b.goals.compareTo(a.goals);
        if (a.assists != b.assists) return b.assists.compareTo(a.assists);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final out = <({int rank, PStat s})>[];
    for (var i = 0; i < list.length; i++) {
      final rank = (i > 0 && list[i].goals == list[i - 1].goals) ? out[i - 1].rank : i + 1;
      out.add((rank: rank, s: list[i]));
    }
    return out;
  }

  static List<({int rank, PStat s})> rankBy(List<PStat> stats, int Function(PStat) value) {
    final list = stats.where((x) => value(x) > 0).toList()
      ..sort((a, b) {
        final c = value(b).compareTo(value(a));
        if (c != 0) return c;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final out = <({int rank, PStat s})>[];
    for (var i = 0; i < list.length; i++) {
      final rank = (i > 0 && value(list[i]) == value(list[i - 1])) ? out[i - 1].rank : i + 1;
      out.add((rank: rank, s: list[i]));
    }
    return out;
  }

  // ------------------------------------------------------ suspensions
  static Suspensions suspensions(Tournament t) {
    final s = t.settings;
    final byGame = <String, List<String>>{};
    final remaining = <String, int>{};
    final yellows = <String, int>{};
    final ordered = t.games.where((g) => g.ready).toList()..sort((a, b) => a.seq.compareTo(b.seq));
    final teamPlayers = {for (final tm in t.teams) tm.id: tm.players.map((p) => p.id).toList()};
    for (final m in ordered) {
      final banned = <String>[];
      for (final side in [m.home!, m.away!]) {
        for (final pid in teamPlayers[side] ?? const <String>[]) {
          final r = remaining[pid] ?? 0;
          if (r > 0) {
            banned.add(pid);
            remaining[pid] = r - 1;
          }
        }
      }
      byGame[m.id] = banned;
      if (m.status != Status.done || m.forfeit != null) continue;
      final yIn = <String, int>{};
      final redIn = <String>{};
      for (final e in m.events) {
        if (e.cancelled || e.playerId == null) continue;
        if (e.type == 'yellow') yIn[e.playerId!] = (yIn[e.playerId!] ?? 0) + 1;
        if (e.type == 'red') redIn.add(e.playerId!);
      }
      yIn.forEach((pid, n) {
        if (n >= 2) {
          redIn.add(pid);
        } else if (!redIn.contains(pid)) {
          final y = (yellows[pid] ?? 0) + 1;
          yellows[pid] = y;
          if (s.yellowLimit > 0 && y % s.yellowLimit == 0) remaining[pid] = (remaining[pid] ?? 0) + 1;
        }
      });
      for (final pid in redIn) {
        remaining[pid] = (remaining[pid] ?? 0) + s.redBan;
      }
    }
    return Suspensions(byGame, remaining, yellows);
  }

  /// Joueurs sur le terrain exclus du match en cours (rouge ou deux jaunes).
  static Set<String> sentOff(Game m) {
    final y = <String, int>{};
    final out = <String>{};
    for (final e in m.events) {
      if (e.cancelled || e.playerId == null) continue;
      if (e.type == 'red') out.add(e.playerId!);
      if (e.type == 'yellow') {
        y[e.playerId!] = (y[e.playerId!] ?? 0) + 1;
        if (y[e.playerId!]! >= 2) out.add(e.playerId!);
      }
    }
    return out;
  }

  // ------------------------------------------------------ chronomètre
  static ClockInfo clock(Game m, Settings s, [int? now]) {
    final t = now ?? nowMs();
    final h = s.halfMinutes, e = s.etMinutes;
    int? base, len;
    switch (m.phase) {
      case Phase.h1:
        base = 0;
        len = h;
        break;
      case Phase.h2:
        base = h;
        len = h;
        break;
      case Phase.et1:
        base = 2 * h;
        len = e;
        break;
      case Phase.et2:
        base = 2 * h + e;
        len = e;
        break;
    }
    if (base == null || len == null) {
      final minute = m.phase == Phase.ht ? h : (m.phase == Phase.pre ? 0 : 2 * h);
      return ClockInfo(state: m.phase, minute: minute);
    }
    final elapsed = max(0, (t - (m.phaseStart ?? t)) ~/ 60000);
    final minute = elapsed + 1;
    if (minute > len) {
      var extra = minute - len;
      if (m.added > 0) extra = min(extra, m.added); // l'affichage ne dépasse jamais le temps annoncé
      return ClockInfo(label: "${base + len}+$extra'", state: 'running', minute: base + len, extra: extra, running: true, overtime: true);
    }
    return ClockInfo(label: "${base + minute}'", state: 'running', minute: base + minute, running: true);
  }

  // ------------------------------------------------------- état global
  static ({int done, int total, int live}) progress(Tournament t) {
    final real = t.games.where((g) => !g.bye).toList();
    return (
      done: real.where((g) => g.status == Status.done).length,
      total: real.length,
      live: real.where((g) => g.status == Status.live).length,
    );
  }

  static Game? finalGame(Tournament t) {
    for (final g in t.games) {
      if (g.stage == 'ko' && !g.third && g.roundSize == 2) return g;
    }
    return null;
  }

  static String? champion(Tournament t) {
    if (t.format == Fmt.league) {
      if (t.games.isEmpty || t.games.any((g) => g.status != Status.done)) return null;
      return standings(t.teams.map((x) => x.id).toList(), t.games, t.settings, t.lots).first.team;
    }
    final f = finalGame(t);
    return f == null ? null : winner(t, f);
  }

  static bool finished(Tournament t) => champion(t) != null;
}
