// Foot Zone — création d'un tournoi en 4 étapes : format, équipes, règles, tirage.
import 'package:flutter/material.dart';

import '../data/store.dart';
import '../engine/engine.dart';
import '../engine/models.dart';
import '../l10n/strings.dart';
import 'home_page.dart' show formatIcon;
import 'theme.dart';
import 'tournament_page.dart';
import 'widgets.dart';

class CreatePage extends StatefulWidget {
  const CreatePage({super.key});
  @override
  State<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends State<CreatePage> {
  int step = 1;
  final name = TextEditingController();
  final place = TextEditingController();
  final teams = TextEditingController();
  String format = Fmt.league;
  final Settings s = Settings();
  String drawMode = 'auto';
  List<int> groupOf = [];
  List<int> order = [];
  String? error;

  List<String> get teamNames => teams.text.split('\n').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

  @override
  void initState() {
    super.initState();
    teams.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    name.dispose();
    place.dispose();
    teams.dispose();
    super.dispose();
  }

  TournamentConfig get config => TournamentConfig(
        name: name.text,
        place: place.text,
        format: format,
        teamNames: drawMode == 'manual' && format == Fmt.league && order.length == teamNames.length
            ? order.map((i) => teamNames[i]).toList()
            : teamNames,
        settings: s,
        drawMode: drawMode,
        manualGroups: drawMode == 'manual' && format == Fmt.groups
            ? List.generate(s.groupCount, (g) => [for (var i = 0; i < groupOf.length; i++) if (groupOf[i] == g) i])
            : null,
        manualOrder: drawMode == 'manual' && format == Fmt.cup ? order : null,
      );

  void _prepareDraw() {
    final n = teamNames.length;
    if (groupOf.length != n || groupOf.any((g) => g >= s.groupCount)) groupOf = List.generate(n, (i) => i % s.groupCount);
    if (order.length != n) order = List.generate(n, (i) => i);
  }

  void next() {
    setState(() => error = null);
    if (step == 1) {
      if (name.text.trim().isEmpty) return setState(() => error = tr('errName'));
    } else if (step == 2) {
      final n = teamNames.length;
      if (format == Fmt.single && n != 2) return setState(() => error = tr('errSingleTwo'));
      if (n < 2) return setState(() => error = tr('errMinTeams'));
      if (format == Fmt.groups) {
        if (n < 4) return setState(() => error = tr('errGroupsTeams', {'groups': '2', 'teams': '4'}));
        if (s.groupCount * 2 > n) s.groupCount = n ~/ 2;
        if (n >= 16 && s.groupCount == 2) s.groupCount = (n / 4).round();
        if (s.qualifiers >= n ~/ s.groupCount) s.qualifiers = 1;
      }
      if (format == Fmt.cup && n < 4) s.thirdPlace = false;
      final e = FZ.validate(TournamentConfig(name: name.text, format: format == Fmt.groups ? Fmt.league : format, teamNames: teamNames, settings: Settings()));
      if (e != null) return setState(() => error = tr(e.key, e.args));
    } else if (step == 3) {
      final e = FZ.validate(TournamentConfig(name: name.text, format: format, teamNames: teamNames, settings: s));
      if (e != null) return setState(() => error = tr(e.key, e.args));
      if (format == Fmt.single) return create();
      _prepareDraw();
    }
    setState(() => step++);
  }

  void create() {
    try {
      final t = FZ.createTournament(config);
      StoreScope.read(context).add(t);
      final nav = Navigator.of(context);
      nav.pushReplacement(MaterialPageRoute(builder: (_) => TournamentPage(id: t.id, justCreated: true)));
    } on FzError catch (e) {
      setState(() => error = tr(e.key, e.args));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final total = format == Fmt.single ? 3 : 4;
    Widget body;
    switch (step) {
      case 1:
        body = _step1();
        break;
      case 2:
        body = _step2();
        break;
      case 3:
        body = _step3();
        break;
      default:
        body = _step4();
    }
    return Scaffold(
      appBar: FzAppBar(title: Text(tr('newTournament'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Row(children: [
            for (var i = 1; i <= total; i++)
              Expanded(
                child: Container(
                  height: 5,
                  margin: EdgeInsets.only(right: i < total ? 6 : 0),
                  decoration: BoxDecoration(color: i <= step ? p.cone : p.line, borderRadius: BorderRadius.circular(3)),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Hint(tr('stepOf', {'n': '$step', 'total': '$total'})),
          const SizedBox(height: 14),
          body,
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: TextStyle(color: p.red, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 18),
          Row(children: [
            if (step > 1) ...[
              Expanded(child: OutlinedButton(onPressed: () => setState(() {
                    step--;
                    error = null;
                  }), child: Text(tr('back')))),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: (step == 4 || (step == 3 && format == Fmt.single)) ? create : next,
                icon: Icon((step == 4 || (step == 3 && format == Fmt.single)) ? Icons.sports : Icons.arrow_forward),
                label: Text((step == 4 || (step == 3 && format == Fmt.single)) ? tr('createIt') : tr('continue')),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _step1() {
    final p = Pal.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(children: [
        TextField(controller: name, maxLength: 60, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: tr('tournamentName'), hintText: tr('tournamentNameHint'))),
        TextField(controller: place, maxLength: 60, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: tr('placeOptional'), hintText: tr('placeHint'))),
      ]),
      const SizedBox(height: 16),
      SectionTitle(tr('formatTitle')),
      const SizedBox(height: 8),
      for (final f in Fmt.all) ...[
        Material(
          color: p.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => format = f),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: format == f ? p.cone : p.line, width: format == f ? 3 : 2),
              ),
              child: Row(children: [
                Icon(formatIcon(f), size: 40, color: p.board2),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(formatLabel(f), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Hint(tr('fmtDesc_$f')),
                  ]),
                ),
                if (format == f) Icon(Icons.check_circle, color: p.cone),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    ]);
  }

  Widget _step2() {
    final n = teamNames.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(title: tr('teams'), children: [
        Hint(format == Fmt.single ? tr('teamsHintSingle') : tr('teamsHint')),
        TextField(
          controller: teams,
          minLines: 7,
          maxLines: 14,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: tr('teamsPlaceholder')),
        ),
        Text(tr('nTeams', {'n': '$n'}), style: const TextStyle(fontWeight: FontWeight.w700)),
        if (format == Fmt.cup || format == Fmt.groups)
          SwitchRow(label: tr('seededLabel'), hint: tr('seededHint'), value: s.seeded, onChanged: (v) => setState(() => s.seeded = v)),
      ]),
    ]);
  }

  void _gameType(int g) {
    setState(() {
      s.gameType = g;
      s.halfMinutes = Settings.halfFor(g);
      s.etMinutes = Settings.etFor(g);
    });
  }

  Widget _step3() {
    final n = teamNames.length;
    final hasTable = format == Fmt.league || format == Fmt.groups;
    final hasKo = format == Fmt.cup || format == Fmt.groups;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Banner2(tr('rulesIntro'), icon: Icons.rule),
      const SizedBox(height: 12),
      if (hasTable) ...[
        Panel(title: tr('points'), children: [
          Row(children: [
            Expanded(child: NumStepper(label: tr('win'), value: s.win, min: 1, max: 5, onChanged: (v) => setState(() => s.win = v))),
            const SizedBox(width: 12),
            Expanded(child: NumStepper(label: tr('draw'), value: s.draw, min: 0, max: 3, onChanged: (v) => setState(() => s.draw = v))),
          ]),
          Hint(tr('pointsHint')),
        ]),
        const SizedBox(height: 12),
        Panel(title: tr('tiebreakTitle'), children: [
          Choice<String>(options: [('h2h', tr('tbH2h')), ('goals', tr('tbGoals'))], value: s.tiebreak, onChanged: (v) => setState(() => s.tiebreak = v)),
          Hint(s.tiebreak == 'h2h' ? tr('tbH2hHint') : tr('tbGoalsHint')),
        ]),
        const SizedBox(height: 12),
      ],
      if (format == Fmt.groups) ...[
        Panel(title: tr('groupsTitle'), children: [
          Row(children: [
            Expanded(
                child: NumStepper(
                    label: tr('groupCount'),
                    value: s.groupCount,
                    min: 2,
                    max: (n ~/ 2).clamp(2, 16),
                    onChanged: (v) => setState(() {
                          s.groupCount = v;
                          if (s.qualifiers >= n ~/ v) s.qualifiers = (n ~/ v - 1).clamp(1, 8);
                        }))),
            const SizedBox(width: 12),
            Expanded(child: NumStepper(label: tr('qualifiersPerGroup'), value: s.qualifiers, min: 1, max: (n ~/ s.groupCount - 1).clamp(1, 8), onChanged: (v) => setState(() => s.qualifiers = v))),
          ]),
          Hint(tr('groupsHint', {'min': '${n ~/ s.groupCount}', 'max': '${(n / s.groupCount).ceil()}'})),
        ]),
        const SizedBox(height: 12),
      ],
      Panel(title: tr('legsTitle'), children: [
        if (hasTable) SwitchRow(label: tr('legsTable'), hint: tr('legsTableHint'), value: s.legs == 2, onChanged: (v) => setState(() => s.legs = v ? 2 : 1)),
        if (hasKo) SwitchRow(label: tr('legsKo'), hint: tr('legsKoHint'), value: s.koLegs == 2, onChanged: (v) => setState(() => s.koLegs = v ? 2 : 1)),
        if (hasKo && s.koLegs == 2) SwitchRow(label: tr('awayGoals'), hint: tr('awayGoalsHint'), value: s.awayGoals, onChanged: (v) => setState(() => s.awayGoals = v)),
        if (format != Fmt.league) SwitchRow(label: tr('extraTime'), hint: tr('extraTimeHint'), value: s.extraTime, onChanged: (v) => setState(() => s.extraTime = v)),
        if (hasKo && (format == Fmt.groups || n >= 4))
          SwitchRow(label: tr('thirdPlaceToggle'), hint: tr('thirdPlaceHint'), value: s.thirdPlace, onChanged: (v) => setState(() => s.thirdPlace = v)),
      ]),
      const SizedBox(height: 12),
      Panel(title: tr('durationTitle'), children: [
        Choice<int>(options: [for (final g in [11, 9, 8, 7, 5]) (g, tr('gameTypeN', {'n': '$g'}))], value: s.gameType, onChanged: _gameType),
        Row(children: [
          Expanded(child: NumStepper(label: tr('halfMinutes'), value: s.halfMinutes, min: 5, max: 60, onChanged: (v) => setState(() => s.halfMinutes = v))),
          if (format != Fmt.league) ...[
            const SizedBox(width: 12),
            Expanded(child: NumStepper(label: tr('etMinutes'), value: s.etMinutes, min: 3, max: 20, onChanged: (v) => setState(() => s.etMinutes = v))),
          ],
        ]),
        Hint(tr('durationHint')),
      ]),
      const SizedBox(height: 12),
      Panel(title: tr('disciplineTitle'), children: [
        Row(children: [
          Expanded(child: NumStepper(label: tr('yellowLimit'), hint: tr('zeroNever'), value: s.yellowLimit, min: 0, max: 10, onChanged: (v) => setState(() => s.yellowLimit = v))),
          const SizedBox(width: 12),
          Expanded(child: NumStepper(label: tr('redBan'), hint: tr('matches'), value: s.redBan, min: 1, max: 5, onChanged: (v) => setState(() => s.redBan = v))),
        ]),
        SwitchRow(label: tr('showNames'), hint: tr('showNamesHint'), value: s.showNames, onChanged: (v) => setState(() => s.showNames = v)),
      ]),
    ]);
  }

  Widget _step4() {
    final p = Pal.of(context);
    final names = teamNames;
    final n = names.length;
    final canManual = format != Fmt.single;
    String summary;
    try {
      final t = FZ.createTournament(TournamentConfig(name: 'x', format: format, teamNames: names, settings: s));
      final real = t.games.where((g) => !g.bye).length;
      summary = format == Fmt.groups
          ? tr('summaryGroups', {'n': '$real', 'ko': '${s.groupCount * s.qualifiers - 1 + (s.thirdPlace ? 1 : 0)}'})
          : tr('summaryN', {'n': '$real'});
    } catch (_) {
      summary = '';
    }
    final children = <Widget>[
      Panel(title: tr('drawTitle'), children: [
        Choice<String>(options: [('auto', tr('drawAuto')), ('manual', tr('drawManual'))], value: drawMode, onChanged: canManual ? (v) => setState(() => drawMode = v) : (_) {}),
        Hint(drawMode == 'auto' ? tr('drawAutoHint') : tr('drawManualHint_$format')),
      ]),
    ];
    if (drawMode == 'manual' && format == Fmt.groups) {
      final counts = List.generate(s.groupCount, (g) => groupOf.where((x) => x == g).length);
      children.addAll([
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var g = 0; g < s.groupCount; g++)
            Chip2(tr('groupCountLabel', {'g': groupLetters[g], 'n': '${counts[g]}'}), bg: counts[g] < 2 ? Color.alphaBlend(p.red.withValues(alpha: .18), p.surface) : null),
        ]),
        const SizedBox(height: 8),
        Boxed(children: [
          for (var i = 0; i < n; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(names[i], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (var g = 0; g < s.groupCount; g++)
                    ChoiceChip(
                      label: Text(groupLetters[g]),
                      selected: groupOf[i] == g,
                      onSelected: (_) => setState(() => groupOf[i] = g),
                    ),
                ]),
              ]),
            ),
        ]),
      ]);
    }
    if (drawMode == 'manual' && (format == Fmt.cup || format == Fmt.league)) {
      final byes = format == Fmt.cup ? FZ.nextPow2(n) - n : 0;
      children.addAll([
        const SizedBox(height: 12),
        Boxed(children: [
          for (var k = 0; k < order.length; k++)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    format == Fmt.league ? '${k + 1}' : (k < byes ? tr('exempt') : tr('matchN', {'n': '${(k - byes) ~/ 2 + 1}'})),
                    style: TextStyle(color: k < byes ? p.cone : p.muted, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
                Expanded(child: Text(names[order[k]], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                IconButton(
                  tooltip: tr('moveUp'),
                  onPressed: k == 0 ? null : () => setState(() {
                        final x = order[k];
                        order[k] = order[k - 1];
                        order[k - 1] = x;
                      }),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: tr('moveDown'),
                  onPressed: k == order.length - 1 ? null : () => setState(() {
                        final x = order[k];
                        order[k] = order[k + 1];
                        order[k + 1] = x;
                      }),
                  icon: const Icon(Icons.arrow_downward),
                ),
              ]),
            ),
        ]),
      ]);
    }
    if (summary.isNotEmpty) children.addAll([const SizedBox(height: 12), Banner2(summary, icon: Icons.event_note)]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}
