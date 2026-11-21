// Foot Zone — modèle de données (aucune dépendance Flutter).
import 'dart:math';

final Random _rng = Random.secure();

String newId([String prefix = 'x']) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final b = StringBuffer(prefix);
  for (var i = 0; i < 12; i++) {
    b.write(chars[_rng.nextInt(chars.length)]);
  }
  return b.toString();
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;

int _i(dynamic v, int d) => v is int ? v : (v is num ? v.toInt() : d);
int? _in(dynamic v) => v is int ? v : (v is num ? v.toInt() : null);
bool _b(dynamic v, bool d) => v is bool ? v : d;
String _s(dynamic v, String d) => v is String ? v : d;
String? _sn(dynamic v) => v is String ? v : null;
List<dynamic> _l(dynamic v) => v is List ? v : const [];
Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Formats de tournoi.
class Fmt {
  static const league = 'league';
  static const cup = 'cup';
  static const groups = 'groups';
  static const single = 'single';
  static const all = [league, cup, groups, single];
}

class Settings {
  int win;
  int draw;
  int loss;
  int legs; // championnat / poules : 1 = aller, 2 = aller-retour
  int koLegs; // élimination : 1 = match sec, 2 = aller-retour (la finale reste un match sec)
  bool awayGoals; // buts à l'extérieur en aller-retour
  bool extraTime; // prolongations avant les tirs au but
  String tiebreak; // 'h2h' ou 'goals'
  int groupCount;
  int qualifiers;
  bool thirdPlace;
  int gameType; // 11, 9, 8, 7, 5 joueurs
  int halfMinutes;
  int etMinutes;
  int forfeitGoals;
  int yellowLimit;
  int redBan;
  bool showNames;
  bool seeded;

  Settings({
    this.win = 3,
    this.draw = 1,
    this.loss = 0,
    this.legs = 1,
    this.koLegs = 1,
    this.awayGoals = true,
    this.extraTime = true,
    this.tiebreak = 'h2h',
    this.groupCount = 2,
    this.qualifiers = 2,
    this.thirdPlace = false,
    this.gameType = 11,
    this.halfMinutes = 45,
    this.etMinutes = 15,
    this.forfeitGoals = 3,
    this.yellowLimit = 3,
    this.redBan = 1,
    this.showNames = true,
    this.seeded = false,
  });

  Map<String, dynamic> toJson() => {
        'win': win,
        'draw': draw,
        'loss': loss,
        'legs': legs,
        'koLegs': koLegs,
        'awayGoals': awayGoals,
        'extraTime': extraTime,
        'tiebreak': tiebreak,
        'groupCount': groupCount,
        'qualifiers': qualifiers,
        'thirdPlace': thirdPlace,
        'gameType': gameType,
        'halfMinutes': halfMinutes,
        'etMinutes': etMinutes,
        'forfeitGoals': forfeitGoals,
        'yellowLimit': yellowLimit,
        'redBan': redBan,
        'showNames': showNames,
        'seeded': seeded,
      };

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        win: _i(j['win'], 3),
        draw: _i(j['draw'], 1),
        loss: _i(j['loss'], 0),
        legs: _i(j['legs'], 1) == 2 ? 2 : 1,
        koLegs: _i(j['koLegs'], 1) == 2 ? 2 : 1,
        awayGoals: _b(j['awayGoals'], true),
        extraTime: _b(j['extraTime'], true),
        tiebreak: _s(j['tiebreak'], 'h2h') == 'goals' ? 'goals' : 'h2h',
        groupCount: _i(j['groupCount'], 2),
        qualifiers: _i(j['qualifiers'], 2),
        thirdPlace: _b(j['thirdPlace'], false),
        gameType: _i(j['gameType'], 11),
        halfMinutes: _i(j['halfMinutes'], 45),
        etMinutes: _i(j['etMinutes'], 15),
        forfeitGoals: _i(j['forfeitGoals'], 3),
        yellowLimit: _i(j['yellowLimit'], 3),
        redBan: _i(j['redBan'], 1),
        showNames: _b(j['showNames'], true),
        seeded: _b(j['seeded'], false),
      );

  Settings copy() => Settings.fromJson(toJson());

  /// Durées officielles proposées selon le type de jeu.
  static int halfFor(int gameType) {
    switch (gameType) {
      case 9:
        return 35;
      case 8:
        return 30;
      case 7:
        return 25;
      case 5:
        return 20;
      default:
        return 45;
    }
  }

  static int etFor(int gameType) {
    switch (gameType) {
      case 9:
      case 8:
        return 10;
      case 7:
      case 5:
        return 5;
      default:
        return 15;
    }
  }
}

class Player {
  String id;
  String num;
  String name;
  Player({required this.id, this.num = '', required this.name});
  Map<String, dynamic> toJson() => {'id': id, 'num': num, 'name': name};
  factory Player.fromJson(Map<String, dynamic> j) =>
      Player(id: _s(j['id'], newId('p')), num: _s(j['num'], ''), name: _s(j['name'], '?'));
}

class Team {
  String id;
  String name;
  int color;
  String? logo; // image encodée en base64 (JPEG/PNG), déjà réduite
  List<Player> players;
  bool withdrawn;
  Team({required this.id, required this.name, required this.color, this.logo, List<Player>? players, this.withdrawn = false})
      : players = players ?? <Player>[];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        if (logo != null) 'logo': logo,
        'players': players.map((p) => p.toJson()).toList(),
        'withdrawn': withdrawn,
      };

  factory Team.fromJson(Map<String, dynamic> j) => Team(
        id: _s(j['id'], newId('t')),
        name: _s(j['name'], '?'),
        color: _i(j['color'], 0xFF1D4ED8),
        logo: _sn(j['logo']),
        players: _l(j['players']).map((p) => Player.fromJson(_m(p))).toList(),
        withdrawn: _b(j['withdrawn'], false),
      );
}

class Group {
  String name;
  List<String> teamIds;
  Group({required this.name, required this.teamIds});
  Map<String, dynamic> toJson() => {'name': name, 'teamIds': teamIds};
  factory Group.fromJson(Map<String, dynamic> j) =>
      Group(name: _s(j['name'], 'A'), teamIds: _l(j['teamIds']).whereType<String>().toList());
}

/// Types d'événements : goal, pen, og, yellow, red, sub.
/// Pour un but contre son camp (og), teamId = équipe qui profite du but,
/// playerId = joueur adverse qui a marqué contre son camp.
/// Pour un remplacement (sub), playerId = joueur sortant, inId = joueur entrant.
class MatchEvent {
  String id;
  String type;
  String teamId;
  String? playerId;
  String? assistId;
  String? inId;
  int? minute;
  int? extra;
  bool cancelled;
  int at;
  MatchEvent({
    required this.id,
    required this.type,
    required this.teamId,
    this.playerId,
    this.assistId,
    this.inId,
    this.minute,
    this.extra,
    this.cancelled = false,
    int? at,
  }) : at = at ?? nowMs();

  bool get isGoal => type == 'goal' || type == 'pen' || type == 'og';

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'teamId': teamId,
        if (playerId != null) 'playerId': playerId,
        if (assistId != null) 'assistId': assistId,
        if (inId != null) 'inId': inId,
        if (minute != null) 'minute': minute,
        if (extra != null) 'extra': extra,
        'cancelled': cancelled,
        'at': at,
      };

  factory MatchEvent.fromJson(Map<String, dynamic> j) => MatchEvent(
        id: _s(j['id'], newId('e')),
        type: _s(j['type'], 'goal'),
        teamId: _s(j['teamId'], ''),
        playerId: _sn(j['playerId']),
        assistId: _sn(j['assistId']),
        inId: _sn(j['inId']),
        minute: _in(j['minute']),
        extra: _in(j['extra']),
        cancelled: _b(j['cancelled'], false),
        at: _in(j['at']),
      );
}

/// Origine d'une place dans le tableau : vainqueur (w) ou perdant (l) d'un match.
class Src {
  final String id;
  final bool winner;
  const Src(this.id, this.winner);
  Map<String, dynamic> toJson() => winner ? {'w': id} : {'l': id};
  static Src? fromJson(dynamic v) {
    final j = _m(v);
    if (j['w'] is String) return Src(j['w'] as String, true);
    if (j['l'] is String) return Src(j['l'] as String, false);
    return null;
  }
}

class Phase {
  static const pre = 'pre';
  static const h1 = 'h1';
  static const ht = 'ht';
  static const h2 = 'h2';
  static const et1 = 'et1';
  static const et2 = 'et2';
  static const pens = 'pens';
  static const ft = 'ft';
}

class Status {
  static const scheduled = 'scheduled';
  static const live = 'live';
  static const done = 'done';
}

class Game {
  String id;
  String stage; // league, group, ko
  String? group;
  int round; // journée (championnat, poules)
  int kround; // tour (élimination)
  int pos;
  int leg; // 0 = match sec, 1 = aller, 2 = retour
  String? pairId;
  bool third;
  int roundSize; // équipes dans ce tour : 2 = finale, 4 = demi-finales…
  String? home;
  String? away;
  String status;
  String phase;
  int? phaseStart;
  int added; // temps additionnel annoncé pour la période en cours
  List<MatchEvent> events;
  int? pensH;
  int? pensA;
  String? forfeit; // équipe qui déclare forfait
  String? motm;
  String when;
  String venue;
  String referee;
  bool bye;
  Src? srcHome;
  Src? srcAway;
  int seq;

  Game({
    required this.id,
    required this.stage,
    this.group,
    this.round = 0,
    this.kround = 0,
    this.pos = 0,
    this.leg = 0,
    this.pairId,
    this.third = false,
    this.roundSize = 0,
    this.home,
    this.away,
    this.status = Status.scheduled,
    this.phase = Phase.pre,
    this.phaseStart,
    this.added = 0,
    List<MatchEvent>? events,
    this.pensH,
    this.pensA,
    this.forfeit,
    this.motm,
    this.when = '',
    this.venue = '',
    this.referee = '',
    this.bye = false,
    this.srcHome,
    this.srcAway,
    this.seq = 0,
  }) : events = events ?? <MatchEvent>[];

  bool get hasPens => pensH != null && pensA != null;
  bool get ready => home != null && away != null && !bye;
  List<MatchEvent> get activeEvents => events.where((e) => !e.cancelled).toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'stage': stage,
        if (group != null) 'group': group,
        'round': round,
        'kround': kround,
        'pos': pos,
        'leg': leg,
        if (pairId != null) 'pairId': pairId,
        'third': third,
        'roundSize': roundSize,
        if (home != null) 'home': home,
        if (away != null) 'away': away,
        'status': status,
        'phase': phase,
        if (phaseStart != null) 'phaseStart': phaseStart,
        'added': added,
        'events': events.map((e) => e.toJson()).toList(),
        if (pensH != null) 'pensH': pensH,
        if (pensA != null) 'pensA': pensA,
        if (forfeit != null) 'forfeit': forfeit,
        if (motm != null) 'motm': motm,
        'when': when,
        'venue': venue,
        'referee': referee,
        'bye': bye,
        if (srcHome != null) 'srcHome': srcHome!.toJson(),
        if (srcAway != null) 'srcAway': srcAway!.toJson(),
        'seq': seq,
      };

  factory Game.fromJson(Map<String, dynamic> j) => Game(
        id: _s(j['id'], newId('m')),
        stage: _s(j['stage'], 'league'),
        group: _sn(j['group']),
        round: _i(j['round'], 0),
        kround: _i(j['kround'], 0),
        pos: _i(j['pos'], 0),
        leg: _i(j['leg'], 0),
        pairId: _sn(j['pairId']),
        third: _b(j['third'], false),
        roundSize: _i(j['roundSize'], 0),
        home: _sn(j['home']),
        away: _sn(j['away']),
        status: _s(j['status'], Status.scheduled),
        phase: _s(j['phase'], Phase.pre),
        phaseStart: _in(j['phaseStart']),
        added: _i(j['added'], 0),
        events: _l(j['events']).map((e) => MatchEvent.fromJson(_m(e))).toList(),
        pensH: _in(j['pensH']),
        pensA: _in(j['pensA']),
        forfeit: _sn(j['forfeit']),
        motm: _sn(j['motm']),
        when: _s(j['when'], ''),
        venue: _s(j['venue'], ''),
        referee: _s(j['referee'], ''),
        bye: _b(j['bye'], false),
        srcHome: Src.fromJson(j['srcHome']),
        srcAway: Src.fromJson(j['srcAway']),
        seq: _i(j['seq'], 0),
      );
}

class Tournament {
  String id;
  String name;
  String place;
  String format;
  Settings settings;
  List<Team> teams;
  List<Group> groups;
  List<Game> games;
  Map<String, int> lots; // tirage au sort enregistré (dernier critère de départage)
  int createdAt;
  int updatedAt;
  bool example;
  String? bestPlayer;
  String drawMode; // auto ou manual

  Tournament({
    required this.id,
    required this.name,
    this.place = '',
    required this.format,
    required this.settings,
    List<Team>? teams,
    List<Group>? groups,
    List<Game>? games,
    Map<String, int>? lots,
    int? createdAt,
    int? updatedAt,
    this.example = false,
    this.bestPlayer,
    this.drawMode = 'auto',
  })  : teams = teams ?? <Team>[],
        groups = groups ?? <Group>[],
        games = games ?? <Game>[],
        lots = lots ?? <String, int>{},
        createdAt = createdAt ?? nowMs(),
        updatedAt = updatedAt ?? nowMs();

  Team? team(String? id) {
    if (id == null) return null;
    for (final t in teams) {
      if (t.id == id) return t;
    }
    return null;
  }

  Game? game(String? id) {
    if (id == null) return null;
    for (final g in games) {
      if (g.id == id) return g;
    }
    return null;
  }

  ({Player player, Team team})? player(String? id) {
    if (id == null) return null;
    for (final t in teams) {
      for (final p in t.players) {
        if (p.id == id) return (player: p, team: t);
      }
    }
    return null;
  }

  bool get hasKo => games.any((g) => g.stage == 'ko');

  Map<String, dynamic> toJson() => {
        'app': 'Foot Zone',
        'v': 1,
        'id': id,
        'name': name,
        'place': place,
        'format': format,
        'settings': settings.toJson(),
        'teams': teams.map((t) => t.toJson()).toList(),
        'groups': groups.map((g) => g.toJson()).toList(),
        'games': games.map((g) => g.toJson()).toList(),
        'lots': lots,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'example': example,
        if (bestPlayer != null) 'bestPlayer': bestPlayer,
        'drawMode': drawMode,
      };

  /// Lit un tournoi sauvegardé. Renvoie null si le contenu n'est pas un tournoi Foot Zone valide.
  static Tournament? tryFromJson(dynamic raw) {
    try {
      final j = _m(raw);
      final format = _s(j['format'], '');
      if (!Fmt.all.contains(format) || j['id'] is! String || j['teams'] is! List || j['games'] is! List) return null;
      final lots = <String, int>{};
      _m(j['lots']).forEach((k, v) {
        final n = _in(v);
        if (n != null) lots[k] = n;
      });
      return Tournament(
        id: j['id'] as String,
        name: _s(j['name'], 'Tournoi'),
        place: _s(j['place'], ''),
        format: format,
        settings: Settings.fromJson(_m(j['settings'])),
        teams: _l(j['teams']).map((t) => Team.fromJson(_m(t))).toList(),
        groups: _l(j['groups']).map((g) => Group.fromJson(_m(g))).toList(),
        games: _l(j['games']).map((g) => Game.fromJson(_m(g))).toList(),
        lots: lots,
        createdAt: _in(j['createdAt']),
        updatedAt: _in(j['updatedAt']),
        example: _b(j['example'], false),
        bestPlayer: _sn(j['bestPlayer']),
        drawMode: _s(j['drawMode'], 'auto'),
      );
    } catch (_) {
      return null;
    }
  }
}
