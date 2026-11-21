import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:foot_zone/engine/engine.dart';
import 'package:foot_zone/engine/models.dart';

void play(Game m, int h, int a, {int? pensH, int? pensA}) {
  m.events = [
    for (var i = 0; i < h; i++) MatchEvent(id: newId('e'), type: 'goal', teamId: m.home!),
    for (var i = 0; i < a; i++) MatchEvent(id: newId('e'), type: 'goal', teamId: m.away!),
  ];
  m.status = Status.done;
  m.phase = Phase.ft;
  m.pensH = pensH;
  m.pensA = pensA;
}

Game mk(String h, String a, int gh, int ga) {
  final m = Game(id: newId('m'), stage: 'league', home: h, away: a);
  play(m, gh, ga);
  return m;
}

String nameOf(Tournament t, String? id) => t.team(id)?.name ?? '-';

Tournament create(String format, List<String> teams, {Settings? s, String draw = 'auto', List<List<int>>? groups, List<int>? order}) =>
    FZ.createTournament(TournamentConfig(
      name: 'Test',
      format: format,
      teamNames: teams,
      settings: s ?? Settings(),
      drawMode: draw,
      manualGroups: groups,
      manualOrder: order,
    ));

void main() {
  group('Calendrier (méthode de Berger)', () {
    test('chaque équipe joue chaque autre une fois, domicile/extérieur équilibrés, de 2 à 20 équipes', () {
      for (var k = 2; k <= 20; k++) {
        final ids = List.generate(k, (i) => 'T$i');
        final rounds = FZ.roundRobin(ids, 1);
        final seen = <String>{};
        final home = <String, int>{};
        for (final rd in rounds) {
          final inRound = <String>{};
          for (final p in rd.pairs) {
            final key = ([...p]..sort()).join('-');
            expect(seen.contains(key), isFalse, reason: 'doublon $key');
            seen.add(key);
            expect(inRound.contains(p[0]) || inRound.contains(p[1]), isFalse);
            inRound.addAll(p);
            home[p[0]] = (home[p[0]] ?? 0) + 1;
          }
          expect(inRound.length + rd.rest.length, k);
        }
        expect(seen.length, k * (k - 1) ~/ 2);
        for (final id in ids) {
          final hm = home[id] ?? 0, aw = (k - 1) - hm;
          expect((hm - aw).abs() <= 1, isTrue, reason: '$k équipes : $id $hm/$aw');
        }
        expect(FZ.roundRobin(ids, 2).fold<int>(0, (s, r) => s + r.pairs.length), k * (k - 1));
      }
    });

    test('5 équipes : 5 journées avec un repos chacune', () {
      final rounds = FZ.roundRobin(['A', 'B', 'C', 'D', 'E'], 1);
      expect(rounds.length, 5);
      final rests = rounds.map((r) => r.rest.single).toSet();
      expect(rests.length, 5);
    });
  });

  group('Classement et départage', () {
    test('points et ordre de base', () {
      final ms = [mk('A', 'B', 2, 0), mk('B', 'C', 1, 1), mk('A', 'C', 0, 3)];
      final tb = FZ.standings(['A', 'B', 'C'], ms, Settings(), {});
      expect(tb.map((r) => r.team).toList(), ['C', 'A', 'B']);
      expect(tb.map((r) => r.pts).toList(), [4, 3, 1]);
    });

    test('confrontation directe avant la différence de buts (et inversement)', () {
      final ms = [mk('A', 'B', 0, 1), mk('A', 'C', 5, 0), mk('A', 'D', 5, 0), mk('B', 'C', 0, 1), mk('B', 'D', 1, 0), mk('C', 'D', 0, 2)];
      expect(FZ.standings(['A', 'B', 'C', 'D'], ms, Settings(tiebreak: 'h2h'), {}).first.team, 'B');
      expect(FZ.standings(['A', 'B', 'C', 'D'], ms, Settings(tiebreak: 'goals'), {}).first.team, 'A');
    });

    test('égalité à trois : mini-classement puis réapplication au sous-groupe', () {
      final ms = [mk('A', 'B', 3, 0), mk('B', 'C', 1, 0), mk('C', 'A', 1, 0), mk('A', 'D', 1, 0), mk('B', 'D', 1, 0), mk('C', 'D', 4, 0)];
      final tb = FZ.standings(['A', 'B', 'C', 'D'], ms, Settings(), {});
      expect(tb.map((r) => r.team).toList(), ['A', 'C', 'B', 'D']);
    });

    test('égalité parfaite : tirage au sort enregistré', () {
      final m = Game(id: 'x', stage: 'league', home: 'A', away: 'B', status: Status.done);
      final tb = FZ.standings(['A', 'B'], [m], Settings(), {'A': 2, 'B': 1});
      expect(tb.first.team, 'B');
      expect(tb.first.lot, isTrue);
    });

    test('points réglables', () {
      final ms = [mk('A', 'B', 1, 1)];
      final tb = FZ.standings(['A', 'B'], ms, Settings(draw: 2), {});
      expect(tb.first.pts, 2);
    });

    test('un événement annulé ne compte plus', () {
      final m = mk('A', 'B', 1, 0);
      m.events.first.cancelled = true;
      expect(FZ.score(m, Settings()).h, 0);
    });
  });

  group('Tableau à élimination', () {
    test('ordre des têtes de série', () {
      expect(FZ.seedOrder(8), [1, 8, 4, 5, 2, 7, 3, 6]);
    });

    test('de 2 à 40 équipes : exemptés, et la meilleure tête de série gagne', () {
      for (var k = 2; k <= 40; k++) {
        final ids = List.generate(k, (i) => 'S${i + 1}');
        final t = Tournament(id: 'T', name: 'x', format: Fmt.cup, settings: Settings(), teams: ids.map((id) => Team(id: id, name: id, color: 0)).toList());
        t.games = FZ.buildBracket(FZ.seededSlots(ids), t.settings);
        final r1 = t.games.where((g) => g.kround == 1).toList();
        expect(r1.where((g) => g.bye).length, FZ.nextPow2(k) - k);
        for (final g in r1) {
          expect(g.home != null || g.away != null, isTrue);
        }
        for (var guard = 0; guard < 10; guard++) {
          FZ.resolveBracket(t);
          for (final m in t.games.where((g) => g.ready && g.status != Status.done)) {
            final hs = int.parse(m.home!.substring(1)), aws = int.parse(m.away!.substring(1));
            hs < aws ? play(m, 1, 0) : play(m, 0, 1);
          }
        }
        final f = FZ.finalGame(t)!;
        expect(FZ.winner(t, f), 'S1', reason: '$k équipes');
        if (k >= 2) expect(FZ.loser(t, f), 'S2');
      }
    });

    test('tirs au but, petite finale et verrouillage', () {
      final t = create(Fmt.cup, ['A', 'B', 'C', 'D'], s: Settings(thirdPlace: true, seeded: true));
      final r1 = t.games.where((g) => g.kround == 1).toList();
      play(r1[0], 1, 1, pensH: 4, pensA: 5);
      play(r1[1], 2, 0);
      FZ.resolveBracket(t);
      final third = t.games.firstWhere((g) => g.third), fin = FZ.finalGame(t)!;
      expect(fin.home, r1[0].away);
      expect(third.home, r1[0].home);
      expect(third.away, r1[1].away);
      expect(FZ.koLocked(t, r1[0]), isFalse);
      fin.status = Status.live;
      expect(FZ.koLocked(t, r1[0]), isTrue);
    });

    test('petite finale refusée à 3 équipes', () {
      expect(() => create(Fmt.cup, ['A', 'B', 'C'], s: Settings(thirdPlace: true)), throwsA(isA<FzError>()));
    });

    test('correction d\'un résultat : le tour suivant est remis à zéro', () {
      final t = create(Fmt.cup, ['A', 'B', 'C', 'D'], s: Settings(seeded: true));
      final r1 = t.games.where((g) => g.kround == 1).toList();
      play(r1[0], 1, 0);
      play(r1[1], 1, 0);
      FZ.resolveBracket(t);
      final fin = FZ.finalGame(t)!;
      expect(fin.home, r1[0].home);
      play(r1[0], 0, 1);
      FZ.resolveBracket(t);
      expect(fin.home, r1[0].away);
    });

    test('tirage manuel : les premières équipes sont exemptées, puis deux par deux', () {
      final t = create(Fmt.cup, ['A', 'B', 'C', 'D', 'E', 'F'], draw: 'manual', order: [5, 4, 3, 2, 1, 0]);
      final r1 = t.games.where((g) => g.kround == 1).toList()..sort((a, b) => a.pos.compareTo(b.pos));
      expect(r1.where((g) => g.bye).map((g) => nameOf(t, g.home)).toList(), ['F', 'E']);
      final real = r1.where((g) => !g.bye).toList();
      expect([nameOf(t, real[0].home), nameOf(t, real[0].away)], ['D', 'C']);
      expect([nameOf(t, real[1].home), nameOf(t, real[1].away)], ['B', 'A']);
    });
  });

  group('Aller-retour en élimination', () {
    test('cumul des buts, puis buts à l\'extérieur, puis tirs au but', () {
      final t = create(Fmt.cup, ['A', 'B', 'C', 'D'], s: Settings(koLegs: 2, seeded: true));
      final semis = t.games.where((g) => g.kround == 1).toList();
      expect(semis.length, 4);
      expect(FZ.finalGame(t)!.leg, 0, reason: 'la finale reste un match sec');
      final aller = semis.firstWhere((g) => g.leg == 1);
      final retour = t.game(aller.pairId)!;
      expect(retour.home, aller.away);
      // Aller 2-1, retour 1-0 : cumul 2-2, buts à l'extérieur : l'équipe B (visiteuse à l'aller) en a 1, A en a 0.
      play(aller, 2, 1);
      play(retour, 1, 0);
      expect(FZ.winner(t, retour), retour.home);
      expect(FZ.koLevel(t, retour), isFalse);
      // Sans la règle des buts à l'extérieur : tirs au but.
      t.settings.awayGoals = false;
      expect(FZ.koLevel(t, retour), isTrue);
      expect(FZ.winner(t, retour), isNull);
      retour.pensH = 3;
      retour.pensA = 4;
      expect(FZ.winner(t, retour), retour.away);
      expect(FZ.aggregate(t, retour)!.h, 2);
      expect(FZ.aggregate(t, retour)!.a, 2);
      // Le match aller ne désigne jamais de vainqueur.
      expect(FZ.winner(t, aller), isNull);
    });

    test('le vainqueur de la double confrontation va en finale', () {
      final t = create(Fmt.cup, ['A', 'B', 'C', 'D'], s: Settings(koLegs: 2, seeded: true));
      for (final g in t.games.where((g) => g.kround == 1)) {
        play(g, g.leg == 1 ? 3 : 0, 0);
      }
      FZ.resolveBracket(t);
      final fin = FZ.finalGame(t)!;
      expect(fin.ready, isTrue);
      final allers = t.games.where((g) => g.kround == 1 && g.leg == 1).toList()..sort((a, b) => a.pos.compareTo(b.pos));
      expect(fin.home, allers[0].home);
      expect(fin.away, allers[1].home);
    });
  });

  group('Poules et phase finale', () {
    test('création, croisement 1er A – 2e B', () {
      final names = List.generate(16, (i) => 'Eq$i');
      final t = create(Fmt.groups, names, s: Settings(groupCount: 4, qualifiers: 2));
      expect(t.groups.length, 4);
      for (final g in t.groups) {
        expect(g.teamIds.length, 4);
      }
      expect(t.games.length, 24);
      expect(() => FZ.generateFinalPhase(t), throwsA(isA<FzError>()));
      for (final m in t.games) {
        play(m, m.seq % 3, m.seq % 2);
      }
      FZ.generateFinalPhase(t);
      final qs = FZ.qualifiers(t);
      final r1 = t.games.where((g) => g.stage == 'ko' && g.kround == 1).toList();
      expect(r1.length, 4);
      expect(r1[0].home, qs[0].qualified[0].team);
      expect(r1[0].away, qs[1].qualified[1].team);
      expect(r1[2].home, qs[1].qualified[0].team);
      expect(r1[2].away, qs[0].qualified[1].team);
    });

    test('poules inégales : exempts et jamais deux équipes d\'une même poule au 1er tour', () {
      final rnd = Random(7);
      for (var rep = 0; rep < 30; rep++) {
        final t = create(Fmt.groups, List.generate(11, (i) => 'E$i'), s: Settings(groupCount: 3, qualifiers: 2));
        for (final m in t.games) {
          play(m, rnd.nextInt(4), rnd.nextInt(4));
        }
        FZ.generateFinalPhase(t);
        final groupOf = <String, String>{};
        for (final g in t.groups) {
          for (final id in g.teamIds) {
            groupOf[id] = g.name;
          }
        }
        final r1 = t.games.where((g) => g.stage == 'ko' && g.kround == 1).toList();
        expect(r1.length, 4);
        expect(r1.where((g) => g.bye).length, 2);
        for (final g in r1.where((g) => !g.bye)) {
          expect(groupOf[g.home], isNot(groupOf[g.away]));
        }
      }
    });

    test('une équipe retirée ne se qualifie jamais : la suivante prend sa place', () {
      final t = create(Fmt.groups, ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'], s: Settings(groupCount: 2, qualifiers: 2));
      for (final m in t.games) {
        play(m, 1, 0);
      }
      final first = FZ.qualifiers(t).first.table.first.team;
      FZ.withdrawTeam(t, first);
      final q = FZ.qualifiers(t).first.qualified.map((r) => r.team).toList();
      expect(q.contains(first), isFalse);
      expect(q.length, 2);
    });

    test('tirage manuel des poules', () {
      final t = create(Fmt.groups, ['A', 'B', 'C', 'D'], s: Settings(groupCount: 2, qualifiers: 1), draw: 'manual', groups: [
        [0, 3],
        [1, 2]
      ]);
      expect(t.groups[0].teamIds.map((id) => nameOf(t, id)).toList(), ['A', 'D']);
      expect(t.groups[1].teamIds.map((id) => nameOf(t, id)).toList(), ['B', 'C']);
    });

    test('poule d\'une seule équipe refusée', () {
      expect(
          () => create(Fmt.groups, ['A', 'B', 'C', 'D'], s: Settings(groupCount: 2, qualifiers: 1), draw: 'manual', groups: [
                [0],
                [1, 2, 3]
              ]),
          throwsA(isA<FzError>()));
    });
  });

  group('Forfaits', () {
    test('championnat : matchs restants perdus 3-0, matchs joués conservés', () {
      final t = create(Fmt.league, ['A', 'B', 'C', 'D']);
      final a = t.teams.first.id;
      final first = t.games.firstWhere((g) => g.home == a || g.away == a);
      play(first, 2, 2);
      expect(FZ.withdrawTeam(t, a), 2);
      final row = FZ.standings(t.teams.map((x) => x.id).toList(), t.games, t.settings, t.lots).firstWhere((r) => r.team == a);
      expect(row.pts, 1);
      expect(row.bc, 2 + 6);
    });

    test('élimination : l\'adversaire est qualifié d\'office', () {
      final t = create(Fmt.cup, ['A', 'B', 'C', 'D'], s: Settings(seeded: true));
      final r1 = t.games.where((g) => g.kround == 1).toList();
      play(r1[1], 1, 0);
      FZ.withdrawTeam(t, r1[0].home!);
      final f = FZ.finalGame(t)!;
      expect(f.home, r1[0].away);
      expect(f.away, r1[1].home);
    });
  });

  group('Match unique', () {
    test('deux équipes exactement, un vainqueur', () {
      expect(() => create(Fmt.single, ['A', 'B', 'C']), throwsA(isA<FzError>()));
      final t = create(Fmt.single, ['A', 'B']);
      expect(t.games.length, 1);
      play(t.games.first, 2, 1);
      expect(FZ.champion(t), t.games.first.home);
    });
  });

  group('Statistiques et suspensions', () {
    test('buteurs, passes, homme du match, cartons et suspensions', () {
      final t = create(Fmt.league, ['A', 'B', 'C', 'D', 'E'], s: Settings(yellowLimit: 2));
      final a = t.teams.first;
      a.players = [Player(id: 'p1', num: '9', name: 'Diallo'), Player(id: 'p2', num: '10', name: 'Bah'), Player(id: 'p3', num: '4', name: 'Sow')];
      final mA = t.games.where((g) => g.home == a.id || g.away == a.id).toList()..sort((x, y) => x.seq.compareTo(y.seq));
      expect(mA.length, 4);
      final m1 = mA[0];
      m1.events = [
        MatchEvent(id: '1', type: 'goal', teamId: a.id, playerId: 'p1', assistId: 'p2'),
        MatchEvent(id: '2', type: 'pen', teamId: a.id, playerId: 'p1'),
        MatchEvent(id: '3', type: 'red', teamId: a.id, playerId: 'p3'),
        MatchEvent(id: '4', type: 'yellow', teamId: a.id, playerId: 'p2'),
        MatchEvent(id: '5', type: 'yellow', teamId: a.id, playerId: 'p2'),
        MatchEvent(id: '6', type: 'goal', teamId: a.id, playerId: 'p2', cancelled: true),
      ];
      m1.status = Status.done;
      m1.motm = 'p1';
      final st = FZ.playerStats(t);
      final p1 = st.firstWhere((x) => x.id == 'p1'), p2 = st.firstWhere((x) => x.id == 'p2');
      expect(p1.goals, 2);
      expect(p1.pens, 1);
      expect(p1.motm, 1);
      expect(p2.goals, 0, reason: 'but annulé');
      expect(p2.assists, 1);
      final sus = FZ.suspensions(t);
      expect((sus.byGame[mA[1].id]!..sort()), ['p2', 'p3']);
      expect(sus.byGame[mA[2].id], isEmpty);
      mA[1].events = [MatchEvent(id: '7', type: 'yellow', teamId: a.id, playerId: 'p1')];
      mA[1].status = Status.done;
      mA[2].events = [MatchEvent(id: '8', type: 'yellow', teamId: a.id, playerId: 'p1')];
      mA[2].status = Status.done;
      expect(FZ.suspensions(t).byGame[mA[3].id], ['p1']);
    });

    test('même nombre de buts = même place, le plus de passes d\'abord', () {
      final a = PStat('a', 'Alpha', '1', 't')..goals = 3;
      final b = PStat('b', 'Bravo', '2', 't')
        ..goals = 3
        ..assists = 2;
      final c = PStat('c', 'Charlie', '3', 't')..goals = 1;
      final r = FZ.scorers([a, b, c]);
      expect(r.map((x) => x.s.id).toList(), ['b', 'a', 'c']);
      expect(r.map((x) => x.rank).toList(), [1, 1, 3]);
    });
  });

  group('Chronomètre', () {
    test('minutes, temps additionnel et plafond du temps annoncé', () {
      const t0 = 1000000000000;
      final s = Settings(halfMinutes: 45, etMinutes: 15);
      expect(FZ.clock(Game(id: 'a', stage: 'x', phase: Phase.h1, phaseStart: t0), s, t0 + 10 * 60000).label, "11'");
      expect(FZ.clock(Game(id: 'a', stage: 'x', phase: Phase.h1, phaseStart: t0), s, t0 + 47 * 60000).label, "45+3'");
      expect(FZ.clock(Game(id: 'a', stage: 'x', phase: Phase.h1, phaseStart: t0, added: 2), s, t0 + 52 * 60000).label, "45+2'");
      expect(FZ.clock(Game(id: 'a', stage: 'x', phase: Phase.h2, phaseStart: t0), Settings(halfMinutes: 30), t0).label, "31'");
      expect(FZ.clock(Game(id: 'a', stage: 'x', phase: Phase.ht), s).state, Phase.ht);
    });
  });

  group('Validation', () {
    test('saisies refusées', () {
      expect(FZ.validate(TournamentConfig(name: 'X', format: Fmt.league, teamNames: ['A', 'a'])), isA<FzError>());
      expect(FZ.validate(TournamentConfig(name: '', format: Fmt.league, teamNames: ['A', 'B'])), isA<FzError>());
      expect(FZ.validate(TournamentConfig(name: 'X', format: Fmt.groups, teamNames: ['A', 'B', 'C'], settings: Settings(groupCount: 2, qualifiers: 1))), isA<FzError>());
      expect(FZ.validate(TournamentConfig(name: 'X', format: Fmt.groups, teamNames: ['A', 'B', 'C', 'D'], settings: Settings(groupCount: 2, qualifiers: 2))), isA<FzError>());
      expect(FZ.validate(TournamentConfig(name: 'X', format: Fmt.league, teamNames: ['A', 'B'])), isNull);
    });

    test('sauvegarde : lecture et écriture identiques', () {
      final t = create(Fmt.groups, List.generate(8, (i) => 'Équipe $i'), s: Settings(groupCount: 2, qualifiers: 2, koLegs: 2));
      final back = Tournament.tryFromJson(t.toJson())!;
      expect(back.toJson().toString(), t.toJson().toString());
      expect(Tournament.tryFromJson({'format': 'x'}), isNull);
    });
  });
}
