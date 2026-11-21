// Foot Zone — page d'un tournoi : matchs, classement/tableau, statistiques, équipes, réglages.

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/store.dart';
import '../engine/engine.dart';
import '../engine/models.dart';
import '../l10n/strings.dart';
import 'match_page.dart';
import 'share_images.dart';
import 'team_page.dart';
import 'theme.dart';
import 'widgets.dart';

class TournamentPage extends StatefulWidget {
  final String id;
  final bool justCreated;
  const TournamentPage({super.key, required this.id, this.justCreated = false});
  @override
  State<TournamentPage> createState() => _TournamentPageState();
}

class _TournamentPageState extends State<TournamentPage> {
  int tab = 0;
  String filter = 'all';
  String statTab = 'goals';

  @override
  void initState() {
    super.initState();
    if (widget.justCreated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final t = StoreScope.read(context).byId(widget.id);
        if (t == null || !mounted) return;
        final n = t.games.where((g) => !g.bye).length;
        snack(context, tr('createdToast', {'n': '$n'}), seconds: 4);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = store.byId(widget.id);
    if (t == null) {
      return Scaffold(appBar: FzAppBar(), body: EmptyState(icon: Icons.delete_outline, text: tr('tournamentGone')));
    }
    final tabs = [
      (Icons.list_alt, tr('tabMatches')),
      (t.format == Fmt.cup || t.format == Fmt.single ? Icons.account_tree_outlined : Icons.table_chart_outlined,
          t.format == Fmt.cup || t.format == Fmt.single ? tr('tabBracket') : tr('tabStandings')),
      (Icons.bar_chart, tr('tabStats')),
      (Icons.groups_outlined, tr('tabTeams')),
      (Icons.tune, tr('tabSettings')),
    ];
    Widget body;
    switch (tab) {
      case 0:
        body = _matches(t);
        break;
      case 1:
        body = _standings(t);
        break;
      case 2:
        body = _stats(t);
        break;
      case 3:
        body = _teams(t);
        break;
      default:
        body = _settings(t);
    }
    return Scaffold(
      appBar: FzAppBar(title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          if (t.example) ...[Banner2(tr('exampleBanner'), icon: Icons.info_outline), const SizedBox(height: 12)],
          body,
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [for (final x in tabs) NavigationDestination(icon: Icon(x.$1), label: x.$2)],
      ),
    );
  }

  void _openGame(Tournament t, Game g) {
    if (g.bye) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MatchPage(tid: t.id, gid: g.id)));
  }

  // ----------------------------------------------------------- matchs
  Widget _matches(Tournament t) {
    final p = Pal.of(context);
    bool keep(Game g) =>
        !g.bye &&
        (filter == 'all' ||
            (filter == 'todo' && g.status == Status.scheduled) ||
            (filter == 'live' && g.status == Status.live) ||
            (filter == 'done' && g.status == Status.done));
    final ordered = List<Game>.of(t.games)..sort((a, b) => a.seq.compareTo(b.seq));
    final sections = <String, List<Game>>{};
    for (final g in ordered) {
      final key = g.stage == 'ko' ? 'k${g.kround}${g.third ? 't' : ''}' : 'r${g.round}';
      sections.putIfAbsent(key, () => []).add(g);
    }
    final out = <Widget>[
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final f in [('all', tr('fAll')), ('todo', tr('fTodo')), ('live', tr('fLive')), ('done', tr('fDone'))]) ...[
            ChoiceChip(label: Text(f.$2), selected: filter == f.$1, onSelected: (_) => setState(() => filter = f.$1)),
            const SizedBox(width: 8),
          ],
        ]),
      ),
    ];
    String? lastStage;
    var any = false;
    for (final entry in sections.entries) {
      final list = entry.value;
      final vis = list.where(keep).toList();
      if (vis.isEmpty) continue;
      any = true;
      final first = list.first;
      if (t.format == Fmt.groups && first.stage != lastStage) {
        out.add(const SizedBox(height: 14));
        out.add(SectionTitle(first.stage == 'ko' ? tr('finalPhase') : tr('groupPhase')));
      }
      lastStage = first.stage;
      final real = list.where((g) => !g.bye).toList();
      final done = real.where((g) => g.status == Status.done).length;
      final title = first.stage == 'ko' ? roundName(t, first.roundSize) : roundTitle(t, first);
      out.add(const SizedBox(height: 14));
      out.add(Row(children: [
        Expanded(child: Text(first.third ? tr('thirdPlace') : (t.format == Fmt.single ? tr('theMatch') : title), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.muted))),
        Text('$done/${real.length}', style: TextStyle(color: p.muted, fontWeight: FontWeight.w700)),
        IconButton(
          tooltip: tr('shareSchedule'),
          icon: Icon(Icons.ios_share, color: p.muted, size: 20),
          onPressed: () => shareImage(context, (v) => ShareImages.round(t, real, title, v), 'programme'),
        ),
      ]));
      final rows = <Widget>[for (final g in vis) GameRow(t: t, g: g, showGroup: t.format == Fmt.groups, onTap: () => _openGame(t, g))];
      if (filter == 'all' && first.stage != 'ko') {
        final rest = FZ.resting(t, first.stage, first.round);
        if (rest.isNotEmpty) {
          rows.add(Container(
            color: p.bg,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(tr('resting', {'teams': rest.map((id) => teamName(t, id)).join(', ')}), style: TextStyle(color: p.muted, fontSize: 13)),
          ));
        }
      }
      out.add(Boxed(children: rows));
    }
    if (t.format == Fmt.groups && !t.hasKo && filter == 'all') {
      out.add(const SizedBox(height: 16));
      out.add(_finalPhaseCard(t));
    }
    if (!any) out.add(EmptyState(icon: Icons.sports_soccer, text: tr('noMatchHere')));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }

  Widget _finalPhaseCard(Tournament t) {
    if (FZ.groupStageDone(t)) {
      return Panel(title: tr('finalPhase'), children: [
        Hint(tr('groupsDone')),
        FilledButton.icon(
          onPressed: () {
            try {
              FZ.generateFinalPhase(t);
              StoreScope.read(context).save(t);
              setState(() => tab = 1);
              snack(context, tr('finalCreated'));
            } on FzError catch (e) {
              snack(context, tr(e.key, e.args));
            }
          },
          icon: const Icon(Icons.account_tree_outlined),
          label: Text(tr('createFinal')),
        ),
      ]);
    }
    return Hint(tr('finalLater'));
  }

  // ------------------------------------------------- classement / tableau
  Widget _standings(Tournament t) {
    final s = t.settings;
    final out = <Widget>[];
    final ch = FZ.champion(t);
    if (ch != null) {
      out.add(ChampionCard(t: t, teamId: ch));
      out.add(const SizedBox(height: 14));
    }
    if (t.format == Fmt.league) {
      out.add(StandingsTable(t: t, ids: t.teams.map((x) => x.id).toList(), games: t.games, qualified: 0));
    } else if (t.format == Fmt.groups) {
      for (final g in t.groups) {
        out.add(SectionTitle(tr('groupN', {'g': g.name})));
        out.add(const SizedBox(height: 8));
        out.add(StandingsTable(t: t, ids: g.teamIds, games: t.games.where((m) => m.group == g.name).toList(), qualified: s.qualifiers));
        out.add(const SizedBox(height: 14));
      }
      out.add(SectionTitle(tr('finalPhase')));
      out.add(const SizedBox(height: 8));
      out.add(t.hasKo ? Bracket(t: t, onOpen: (g) => _openGame(t, g)) : _finalPhaseCard(t));
    } else if (t.format == Fmt.single) {
      final g = t.games.first;
      out.add(Boxed(children: [GameRow(t: t, g: g, onTap: () => _openGame(t, g))]));
    } else {
      out.add(Bracket(t: t, onOpen: (g) => _openGame(t, g)));
    }
    if (t.format == Fmt.league || t.format == Fmt.groups) {
      out.add(const SizedBox(height: 14));
      out.add(Hint(tr(s.tiebreak == 'h2h' ? 'tbExplainH2h' : 'tbExplainGoals', {'win': '${s.win}', 'draw': '${s.draw}'})));
      out.add(const SizedBox(height: 12));
      out.add(OutlinedButton.icon(
        onPressed: () => shareImage(context, (v) => ShareImages.standings(t, v), 'classement'),
        icon: const Icon(Icons.ios_share),
        label: Text(tr('shareStandings')),
      ));
    }
    if (t.format == Fmt.cup || t.format == Fmt.groups) {
      out.add(const SizedBox(height: 10));
      out.add(OutlinedButton.icon(
        onPressed: () => shareImage(context, (v) => ShareImages.draw(t, v), 'tirage'),
        icon: const Icon(Icons.casino_outlined),
        label: Text(tr('shareDraw')),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }

  // ------------------------------------------------------- statistiques
  Widget _stats(Tournament t) {
    final p = Pal.of(context);
    final stats = FZ.playerStats(t);
    final hasPlayers = t.teams.any((x) => x.players.isNotEmpty);
    final out = <Widget>[
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final o in [('goals', tr('statScorers')), ('assists', tr('statAssists')), ('cards', tr('statCards')), ('best', tr('statBest')), ('teams', tr('statTeams'))]) ...[
            ChoiceChip(label: Text(o.$2), selected: statTab == o.$1, onSelected: (_) => setState(() => statTab = o.$1)),
            const SizedBox(width: 8),
          ],
        ]),
      ),
      const SizedBox(height: 12),
    ];
    Widget row(int rank, PStat s, String value, {String? sub, bool first = false}) {
      final team = t.team(s.teamId);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          SizedBox(width: 28, child: Text('$rank', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, color: p.muted))),
          const SizedBox(width: 8),
          Crest(team, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(playerLabel(t, s.id, forPublic: true), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
              Text([team?.name ?? '', if (sub != null) sub].join(', '), style: TextStyle(color: p.muted, fontSize: 13)),
            ]),
          ),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: first ? p.cone : p.ink)),
        ]),
      );
    }

    Widget list(List<Widget> rows) => rows.isEmpty ? EmptyState(icon: Icons.bar_chart, text: tr('nothingYet')) : Boxed(children: rows);

    if (statTab == 'teams') {
      final all = FZ.standings(t.teams.map((x) => x.id).toList(), t.games, t.settings, t.lots).where((r) => r.j > 0).toList();
      final clean = <String, int>{};
      for (final m in t.games) {
        if (m.status != Status.done || !m.ready) continue;
        final sc = FZ.score(m, t.settings);
        if (sc.a == 0) clean[m.home!] = (clean[m.home!] ?? 0) + 1;
        if (sc.h == 0) clean[m.away!] = (clean[m.away!] ?? 0) + 1;
      }
      Widget teamList(String title, List<StandRow> rows, String Function(StandRow) val, String Function(StandRow) sub) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(title),
              const SizedBox(height: 8),
              list([
                for (var i = 0; i < rows.length && i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      SizedBox(width: 28, child: Text('${i + 1}', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, color: p.muted))),
                      const SizedBox(width: 8),
                      Crest(t.team(rows[i].team), size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(teamName(t, rows[i].team), style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(sub(rows[i]), style: TextStyle(color: p.muted, fontSize: 13)),
                        ]),
                      ),
                      Text(val(rows[i]), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: i == 0 ? p.cone : p.ink)),
                    ]),
                  ),
              ]),
              const SizedBox(height: 14),
            ],
          );
      out.add(teamList(tr('bestAttack'), List.of(all)..sort((a, b) => b.bp.compareTo(a.bp)), (r) => '${r.bp}', (r) => tr('nMatches', {'n': '${r.j}'})));
      out.add(teamList(tr('bestDefence'), List.of(all)..sort((a, b) => (a.bc / a.j).compareTo(b.bc / b.j)), (r) => '${r.bc}', (r) => tr('concededIn', {'n': '${r.j}'})));
      out.add(teamList(tr('cleanSheets'), all.where((r) => (clean[r.team] ?? 0) > 0).toList()..sort((a, b) => (clean[b.team] ?? 0).compareTo(clean[a.team] ?? 0)),
          (r) => '${clean[r.team] ?? 0}', (r) => tr('cleanSheetsSub')));
      out.add(teamList(tr('fairPlay'), List.of(all)..sort((a, b) => a.fp.compareTo(b.fp)), (r) => '${r.fp}', (r) => tr('fairPlaySub')));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
    }

    if (!hasPlayers) {
      out.add(EmptyState(
        icon: Icons.person_add_alt,
        text: tr('addPlayersFirst'),
        action: FilledButton(onPressed: () => setState(() => tab = 3), child: Text(tr('addPlayers'))),
      ));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
    }

    switch (statTab) {
      case 'goals':
        final sc = FZ.scorers(stats);
        out.add(list([
          for (var i = 0; i < sc.length; i++)
            row(sc[i].rank, sc[i].s, '${sc[i].s.goals}', sub: _scorerSub(sc[i].s), first: sc[i].rank == 1),
        ]));
        if (sc.isNotEmpty) {
          out.add(const SizedBox(height: 12));
          out.add(OutlinedButton.icon(
            onPressed: () => shareImage(context, (v) => ShareImages.scorers(t, v), 'buteurs'),
            icon: const Icon(Icons.ios_share),
            label: Text(tr('shareScorers')),
          ));
        }
        break;
      case 'assists':
        final r = FZ.rankBy(stats, (x) => x.assists);
        out.add(list([for (final x in r) row(x.rank, x.s, '${x.s.assists}', first: x.rank == 1)]));
        break;
      case 'cards':
        final sus = FZ.suspensions(t);
        final banned = sus.remaining.entries.where((e) => e.value > 0).map((e) => (e, t.player(e.key))).where((x) => x.$2 != null && !x.$2!.team.withdrawn).toList();
        if (banned.isNotEmpty) {
          out.add(Panel(title: tr('suspendedNext'), children: [
            for (final b in banned)
              Row(children: [
                Crest(b.$2!.team, size: 28),
                const SizedBox(width: 10),
                Expanded(child: Text('${playerLabel(t, b.$1.key)} (${b.$2!.team.name})${b.$1.value > 1 ? ', ${tr('nMatches', {'n': '${b.$1.value}'})}' : ''}')),
              ]),
          ]));
          out.add(const SizedBox(height: 12));
        }
        final rows = stats.where((x) => x.yellow > 0 || x.red > 0).toList()..sort((a, b) => (b.red * 3 + b.yellow).compareTo(a.red * 3 + a.yellow));
        out.add(list([
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                SizedBox(width: 28, child: Text('${i + 1}', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, color: p.muted))),
                const SizedBox(width: 8),
                Crest(t.team(rows[i].teamId), size: 32),
                const SizedBox(width: 10),
                Expanded(child: Text(playerLabel(t, rows[i].id, forPublic: true), style: const TextStyle(fontWeight: FontWeight.w700))),
                if (rows[i].yellow > 0) ...[const CardMark(), const SizedBox(width: 4), Text('${rows[i].yellow}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))],
                if (rows[i].red > 0) ...[const SizedBox(width: 10), const CardMark(red: true), const SizedBox(width: 4), Text('${rows[i].red}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))],
              ]),
            ),
        ]));
        out.add(const SizedBox(height: 10));
        out.add(Hint(t.settings.yellowLimit > 0
            ? tr('suspensionRule', {'y': '${t.settings.yellowLimit}', 'r': '${t.settings.redBan}'})
            : tr('suspensionRuleNoYellow', {'r': '${t.settings.redBan}'})));
        break;
      case 'best':
        final finished = FZ.finished(t);
        final ranked = List<PStat>.of(stats.where((x) => x.played > 0))..sort((a, b) => b.rating.compareTo(a.rating));
        final best = t.player(t.bestPlayer);
        out.add(Panel(title: tr('bestOfTournament'), children: [
          if (best != null)
            Row(children: [
              Icon(Icons.emoji_events, color: p.yellow, size: 36),
              const SizedBox(width: 10),
              Expanded(child: Text('${playerLabel(t, t.bestPlayer, forPublic: true)} (${best.team.name})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            ])
          else
            Hint(finished ? tr('bestChooseHint') : tr('bestAfterEnd')),
          if (finished)
            OutlinedButton.icon(
              onPressed: () => _chooseBest(t, ranked),
              icon: const Icon(Icons.star_outline),
              label: Text(best == null ? tr('chooseBest') : tr('changeBest')),
            ),
        ]));
        out.add(const SizedBox(height: 12));
        out.add(list([
          for (var i = 0; i < ranked.length && i < 20; i++)
            row(i + 1, ranked[i], '${ranked[i].rating}',
                sub: tr('ratingSub', {'g': '${ranked[i].goals}', 'a': '${ranked[i].assists}', 'm': '${ranked[i].motm}'}), first: i == 0),
        ]));
        out.add(const SizedBox(height: 10));
        out.add(Hint(tr('ratingExplain')));
        break;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }

  String? _scorerSub(PStat s) {
    final parts = [
      if (s.pens > 0) tr('nPens', {'n': '${s.pens}'}),
      if (s.assists > 0) tr('nAssists', {'n': '${s.assists}'}),
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  Future<void> _chooseBest(Tournament t, List<PStat> ranked) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * .8),
          child: ListView(shrinkWrap: true, children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(tr('chooseBest'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Hint(tr('bestSuggestion'))),
            for (final x in t.teams.expand((tm) => tm.players.map((pl) => (tm, pl))).toList()
              ..sort((a, b) {
                final ra = ranked.indexWhere((r) => r.id == a.$2.id), rb = ranked.indexWhere((r) => r.id == b.$2.id);
                return (ra < 0 ? 9999 : ra).compareTo(rb < 0 ? 9999 : rb);
              }))
              ListTile(
                leading: Crest(x.$1, size: 32),
                title: Text(playerLabel(t, x.$2.id)),
                subtitle: Text(x.$1.name),
                trailing: t.bestPlayer == x.$2.id ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(c, x.$2.id),
              ),
          ]),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    t.bestPlayer = picked;
    StoreScope.read(context).save(t);
    snack(context, tr('bestSaved'));
  }

  // ------------------------------------------------------------ équipes
  Widget _teams(Tournament t) {
    final p = Pal.of(context);
    final sus = FZ.suspensions(t);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Boxed(children: [
        for (final x in t.teams)
          InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeamPage(tid: t.id, teamId: x.id))),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Crest(x, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(x.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5)),
                    Text(
                      [
                        tr('nPlayers', {'n': '${x.players.length}'}),
                        if (x.players.where((pl) => (sus.remaining[pl.id] ?? 0) > 0).isNotEmpty)
                          tr('nSuspended', {'n': '${x.players.where((pl) => (sus.remaining[pl.id] ?? 0) > 0).length}'}),
                      ].join(', '),
                      style: TextStyle(color: p.muted, fontSize: 13.5),
                    ),
                  ]),
                ),
                if (x.withdrawn) Chip2(tr('withdrawn'), bg: Color.alphaBlend(p.red.withValues(alpha: .18), p.surface), fg: p.red) else Icon(Icons.chevron_right, color: p.muted),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      Hint(tr('teamsTabHint')),
    ]);
  }

  // ----------------------------------------------------------- réglages
  Widget _settings(Tournament t) {
    final store = StoreScope.read(context);
    final s = t.settings;
    void upd(VoidCallback f) {
      f();
      store.save(t);
    }

    final hasTable = t.format == Fmt.league || t.format == Fmt.groups;
    final hasKo = t.format != Fmt.league;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(title: tr('tournament'), children: [
        _EditField(label: tr('tournamentName'), value: t.name, max: 60, onSave: (v) => upd(() => t.name = v)),
        _EditField(label: tr('placeOptional'), value: t.place, max: 60, allowEmpty: true, onSave: (v) => upd(() => t.place = v)),
        Hint('${formatLabel(t.format)}, ${tr('nTeams', {'n': '${t.teams.length}'})}${t.format == Fmt.groups ? ', ${tr('groupsSummary', {'g': '${s.groupCount}', 'q': '${s.qualifiers}'})}' : ''}'),
      ]),
      const SizedBox(height: 12),
      Panel(title: tr('rules'), children: [
        Hint(tr('rulesLive')),
        if (hasTable) ...[
          Row(children: [
            Expanded(child: NumStepper(label: tr('win'), value: s.win, min: 1, max: 5, onChanged: (v) => upd(() => s.win = v))),
            const SizedBox(width: 12),
            Expanded(child: NumStepper(label: tr('draw'), value: s.draw, min: 0, max: 3, onChanged: (v) => upd(() => s.draw = v))),
          ]),
          Text(tr('tiebreakTitle'), style: const TextStyle(fontWeight: FontWeight.w700)),
          Choice<String>(options: [('h2h', tr('tbH2h')), ('goals', tr('tbGoals'))], value: s.tiebreak, onChanged: (v) => upd(() => s.tiebreak = v)),
        ],
        if (hasKo && s.koLegs == 2) SwitchRow(label: tr('awayGoals'), hint: tr('awayGoalsHint'), value: s.awayGoals, onChanged: (v) => upd(() => s.awayGoals = v)),
        if (hasKo) SwitchRow(label: tr('extraTime'), hint: tr('extraTimeHint'), value: s.extraTime, onChanged: (v) => upd(() => s.extraTime = v)),
        Row(children: [
          Expanded(child: NumStepper(label: tr('halfMinutes'), value: s.halfMinutes, min: 5, max: 60, onChanged: (v) => upd(() => s.halfMinutes = v))),
          if (hasKo) ...[
            const SizedBox(width: 12),
            Expanded(child: NumStepper(label: tr('etMinutes'), value: s.etMinutes, min: 3, max: 20, onChanged: (v) => upd(() => s.etMinutes = v))),
          ],
        ]),
        Row(children: [
          Expanded(child: NumStepper(label: tr('yellowLimit'), hint: tr('zeroNever'), value: s.yellowLimit, min: 0, max: 10, onChanged: (v) => upd(() => s.yellowLimit = v))),
          const SizedBox(width: 12),
          Expanded(child: NumStepper(label: tr('redBan'), hint: tr('matches'), value: s.redBan, min: 1, max: 5, onChanged: (v) => upd(() => s.redBan = v))),
        ]),
        SwitchRow(label: tr('showNames'), hint: tr('showNamesHint'), value: s.showNames, onChanged: (v) => upd(() => s.showNames = v)),
      ]),
      const SizedBox(height: 12),
      Panel(title: tr('backup'), children: [
        Hint(tr('backupHint')),
        OutlinedButton.icon(
          onPressed: () async {
            try {
              final f = await store.exportFile(t);
              await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/json')], subject: t.name));
            } catch (_) {
              if (mounted) snack(context, tr('shareFailed'));
            }
          },
          icon: const Icon(Icons.save_alt),
          label: Text(tr('saveCopy')),
        ),
      ]),
      const SizedBox(height: 12),
      Panel(title: tr('deleteTitle'), children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Pal.of(context).red),
          onPressed: () async {
            final ok = await confirm(context, title: tr('deleteConfirmTitle', {'name': t.name}), body: tr('deleteConfirmBody'), ok: tr('deleteIt'), danger: true);
            if (!ok || !mounted) return;
            store.remove(t.id);
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.delete_outline),
          label: Text(tr('deleteTournament')),
        ),
      ]),
      const SizedBox(height: 14),
      Hint(tr('aboutLine'), align: TextAlign.center),
    ]);
  }
}

/// Champ texte enregistré quand on quitte le champ ou qu'on valide.
class _EditField extends StatefulWidget {
  final String label;
  final String value;
  final int max;
  final bool allowEmpty;
  final ValueChanged<String> onSave;
  const _EditField({required this.label, required this.value, required this.max, required this.onSave, this.allowEmpty = false});
  @override
  State<_EditField> createState() => _EditFieldState();
}

class _EditFieldState extends State<_EditField> {
  late final TextEditingController c = TextEditingController(text: widget.value);
  final FocusNode f = FocusNode();

  @override
  void initState() {
    super.initState();
    f.addListener(() {
      if (!f.hasFocus) _save();
    });
  }

  void _save() {
    final v = c.text.trim();
    if (v == widget.value) return;
    if (v.isEmpty && !widget.allowEmpty) {
      c.text = widget.value;
      return;
    }
    widget.onSave(v);
  }

  @override
  void dispose() {
    c.dispose();
    f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: c,
        focusNode: f,
        maxLength: widget.max,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(labelText: widget.label),
      );
}

// ================================================================ widgets

class GameRow extends StatelessWidget {
  final Tournament t;
  final Game g;
  final bool showGroup;
  final VoidCallback onTap;
  const GameRow({super.key, required this.t, required this.g, this.showGroup = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    String? w;
    if (g.status == Status.done && g.ready) {
      if (g.stage == 'ko') {
        w = g.leg == 1 ? null : FZ.winner(t, g);
      } else {
        final sc = FZ.score(g, t.settings);
        w = sc.h > sc.a ? g.home : (sc.a > sc.h ? g.away : null);
      }
    }
    Widget side(String? id, bool right) {
      final lose = w != null && w != id;
      final children = [
        Crest(t.team(id), size: 30),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            id == null ? tr('tbd') : teamName(t, id),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: right ? TextAlign.right : TextAlign.left,
            style: TextStyle(fontWeight: lose ? FontWeight.w500 : FontWeight.w700, color: lose ? p.muted : p.ink, fontSize: 15, fontStyle: id == null ? FontStyle.italic : null),
          ),
        ),
      ];
      return Row(mainAxisAlignment: right ? MainAxisAlignment.end : MainAxisAlignment.start, children: right ? children.reversed.toList() : children);
    }

    Widget center;
    if (!g.ready) {
      center = Text(tr('upcoming'), style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600));
    } else if (g.status == Status.scheduled) {
      center = Text(g.when.isEmpty ? tr('toPlay') : g.when, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600));
    } else {
      final sc = FZ.score(g, t.settings);
      String? note;
      if (g.status == Status.live) {
        final c = FZ.clock(g, t.settings);
        note = c.label ?? tr('phase_${c.state}');
      } else if (g.forfeit != null) {
        note = tr('forfeitShort');
      } else if (g.hasPens && g.pensH != g.pensA) {
        note = tr('pensShort', {'h': '${g.pensH}', 'a': '${g.pensA}'});
      } else if (g.leg == 2) {
        final agg = FZ.aggregate(t, g);
        if (agg != null) note = tr('aggShort', {'h': '${agg.h}', 'a': '${agg.a}'});
      }
      center = Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${sc.h} - ${sc.a}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: g.status == Status.live ? p.cone : p.ink)),
        if (note != null) Text(note, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: g.status == Status.live ? p.cone : p.muted)),
      ]);
    }
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if ((showGroup && g.group != null) || g.leg > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                [if (showGroup && g.group != null) tr('groupN', {'g': g.group!}), if (g.leg == 1) tr('leg1'), if (g.leg == 2) tr('leg2')].join(', '),
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
            ),
          Row(children: [
            Expanded(child: side(g.home, false)),
            SizedBox(width: 84, child: Center(child: center)),
            Expanded(child: side(g.away, true)),
          ]),
        ]),
      ),
    );
  }
}

class ChampionCard extends StatelessWidget {
  final Tournament t;
  final String teamId;
  const ChampionCard({super.key, required this.t, required this.teamId});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: p.board, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(Icons.emoji_events, color: p.yellow, size: 44),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('champion'), style: TextStyle(color: Colors.white.withValues(alpha: .85))),
            Text(teamName(t, teamId), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          ]),
        ),
        Crest(t.team(teamId), size: 48),
      ]),
    );
  }
}

class StandingsTable extends StatelessWidget {
  final Tournament t;
  final List<String> ids;
  final List<Game> games;
  final int qualified;
  const StandingsTable({super.key, required this.t, required this.ids, required this.games, required this.qualified});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final rows = FZ.standings(ids, games, t.settings, t.lots, live: true);
    final withdrawn = t.teams.where((x) => x.withdrawn).map((x) => x.id).toSet();
    // Places qualificatives : les équipes retirées sont sautées.
    final qualifiedIds = rows.where((r) => !withdrawn.contains(r.team)).take(qualified).map((r) => r.team).toSet();
    const numStyle = TextStyle(fontSize: 14.5, fontFeatures: [FontFeature.tabularFigures()]);
    final head = TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w700);
    Widget cell(String s, {double w = 30, TextStyle? style}) => SizedBox(width: w, child: Text(s, textAlign: TextAlign.center, style: style ?? numStyle));
    final anyLive = rows.any((r) => r.live), anyLot = rows.any((r) => r.lot);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Boxed(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: Row(children: [
            cell('#', w: 30, style: head),
            Expanded(child: Text(tr('team'), style: head)),
            cell(tr('colJ'), style: head),
            cell(tr('colW'), style: head),
            cell(tr('colD'), style: head),
            cell(tr('colL'), style: head),
            cell(tr('colGD'), w: 38, style: head),
            cell(tr('colPts'), w: 38, style: head),
          ]),
        ),
        for (final r in rows)
          Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: qualifiedIds.contains(r.team) ? p.board2 : Colors.transparent, width: 4)),
            ),
            padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
            child: Row(children: [
              cell('${r.rank}', w: 30, style: TextStyle(fontWeight: FontWeight.w800, color: qualifiedIds.contains(r.team) ? p.board2 : p.muted)),
              Expanded(
                child: Row(children: [
                  Crest(t.team(r.team), size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${teamName(t, r.team)}${r.lot ? ' *' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: withdrawn.contains(r.team) ? p.muted : p.ink, decoration: withdrawn.contains(r.team) ? TextDecoration.lineThrough : null)),
                      const SizedBox(height: 3),
                      Row(children: [
                        for (final f in r.form)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 3),
                            decoration: BoxDecoration(shape: BoxShape.circle, color: f == 'V' ? p.win : (f == 'N' ? p.draw : p.loss)),
                          ),
                        if (r.live) ...[const SizedBox(width: 4), Container(width: 8, height: 8, decoration: BoxDecoration(color: p.cone, shape: BoxShape.circle))],
                      ]),
                    ]),
                  ),
                ]),
              ),
              cell('${r.j}'),
              cell('${r.g}'),
              cell('${r.n}'),
              cell('${r.p}'),
              cell('${r.diff > 0 ? '+' : ''}${r.diff}', w: 38),
              cell('${r.pts}', w: 38, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            ]),
          ),
      ]),
      if (qualified > 0 || anyLive || anyLot) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 4, children: [
          if (qualified > 0)
            Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 10, height: 10, color: p.board2), const SizedBox(width: 6), Hint(tr('qualifiedLegend'))]),
          if (anyLive) Hint(tr('provisional')),
          if (anyLot) Hint(tr('lotLegend')),
        ]),
      ],
    ]);
  }
}

class Bracket extends StatelessWidget {
  final Tournament t;
  final ValueChanged<Game> onOpen;
  const Bracket({super.key, required this.t, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final ko = t.games.where((g) => g.stage == 'ko').toList();
    if (ko.isEmpty) return const SizedBox.shrink();
    final rounds = ko.map((g) => g.kround).toSet().toList()..sort();
    final cols = <Widget>[];
    for (final r in rounds) {
      // Une case par confrontation : le match décisif (retour ou match sec).
      final ties = ko.where((g) => g.kround == r && !g.third && g.leg != 1).toList()..sort((a, b) => a.pos.compareTo(b.pos));
      final third = ko.where((g) => g.kround == r && g.third).toList();
      cols.add(SizedBox(
        width: 216,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(roundName(t, ties.first.roundSize), textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, color: p.muted, fontSize: 15)),
          const SizedBox(height: 8),
          for (final g in ties) ...[_TieBox(t: t, g: g, onOpen: onOpen), const SizedBox(height: 10)],
          if (third.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(tr('thirdPlace'), textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, color: p.muted, fontSize: 15)),
            const SizedBox(height: 8),
            _TieBox(t: t, g: third.first, onOpen: onOpen),
          ],
        ]),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < cols.length; i++) ...[if (i > 0) const SizedBox(width: 14), cols[i]],
        ]),
      ),
      const SizedBox(height: 6),
      Hint(tr('scrollBracket')),
    ]);
  }
}

class _TieBox extends StatelessWidget {
  final Tournament t;
  final Game g;
  final ValueChanged<Game> onOpen;
  const _TieBox({required this.t, required this.g, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final w = FZ.winner(t, g);
    final leg1 = g.leg == 2 ? t.game(g.pairId) : null;
    // Équipes dans l'ordre de l'aller (ou du match sec).
    final a = leg1?.home ?? g.home, b = leg1?.away ?? g.away;
    String goals(String? team) {
      if (team == null || g.bye) return '';
      if (leg1 != null) {
        final s1 = FZ.score(leg1, t.settings), s2 = FZ.score(g, t.settings);
        if (leg1.status == Status.scheduled) return '';
        final x = (leg1.home == team ? s1.h : s1.a) + (g.status == Status.scheduled ? 0 : (g.home == team ? s2.h : s2.a));
        return '$x';
      }
      if (g.status == Status.scheduled) return '';
      final s = FZ.score(g, t.settings);
      return '${g.home == team ? s.h : s.a}';
    }

    String pens(String? team) {
      if (!g.hasPens || g.pensH == g.pensA || team == null) return '';
      return ' (${g.home == team ? g.pensH : g.pensA})';
    }

    Widget line(String? team) {
      final known = team != null;
      final label = known ? teamName(t, team) : (g.bye ? tr('exempt') : tr('tbd'));
      return Container(
        color: (w != null && w == team && !g.bye) || (g.bye && known) ? p.qual : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(children: [
          if (known) Crest(t.team(team), size: 24) else const SizedBox(width: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: known ? FontWeight.w700 : FontWeight.w500, fontStyle: known ? null : FontStyle.italic, color: known ? p.ink : p.muted)),
          ),
          Text('${goals(team)}${pens(team)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        ]),
      );
    }

    final live = g.status == Status.live || (leg1?.status == Status.live);
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: g.bye
            ? null
            : () async {
                if (leg1 == null) {
                  onOpen(g);
                  return;
                }
                final pick = await showModalBottomSheet<Game>(
                  context: context,
                  showDragHandle: true,
                  builder: (c) => SafeArea(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      ListTile(leading: const Icon(Icons.looks_one_outlined), title: Text(tr('leg1')), subtitle: Text('${teamName(t, leg1.home)} - ${teamName(t, leg1.away)}'), onTap: () => Navigator.pop(c, leg1)),
                      ListTile(leading: const Icon(Icons.looks_two_outlined), title: Text(tr('leg2')), subtitle: Text('${teamName(t, g.home)} - ${teamName(t, g.away)}'), onTap: () => Navigator.pop(c, g)),
                      const SizedBox(height: 8),
                    ]),
                  ),
                );
                if (pick != null) onOpen(pick);
              },
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: live ? p.cone : p.line, width: live ? 2 : 1)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [line(a), Divider(height: 1, color: p.line), line(b)]),
        ),
      ),
    );
  }
}
