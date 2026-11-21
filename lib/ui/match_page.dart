// Foot Zone — feuille de match en direct : chrono, buts, cartons, remplacements,
// prolongations, tirs au but, corrections et partage.
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../engine/engine.dart';
import '../engine/models.dart';
import '../l10n/strings.dart';
import 'share_images.dart';
import 'theme.dart';
import 'widgets.dart';

class MatchPage extends StatefulWidget {
  final String tid;
  final String gid;
  const MatchPage({super.key, required this.tid, required this.gid});
  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final t = StoreScope.read(context).byId(widget.tid);
      final g = t?.game(widget.gid);
      if (mounted && g != null && g.status == Status.live) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  AppStore get store => StoreScope.read(context);

  void _save(Tournament t) => store.save(t);

  // --------------------------------------------------------------- phases
  void _setPhase(Tournament t, Game g, String phase) {
    g.phase = phase;
    g.phaseStart = nowMs();
    g.added = 0;
    if (phase == Phase.pens) {
      g.pensH ??= 0;
      g.pensA ??= 0;
    }
    g.status = Status.live;
    _save(t);
  }

  Future<void> _end(Tournament t, Game g) async {
    if (FZ.koLevel(t, g)) {
      if (g.phase == Phase.h2 && t.settings.extraTime) {
        final choice = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(tr('levelTitle')),
            content: Text(tr('levelBody')),
            actionsOverflowDirection: VerticalDirection.down,
            actionsOverflowButtonSpacing: 8,
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('cancel'))),
              OutlinedButton(onPressed: () => Navigator.pop(c, Phase.pens), child: Text(tr('goPens'))),
              FilledButton(onPressed: () => Navigator.pop(c, Phase.et1), child: Text(tr('goExtraTime', {'n': '${t.settings.etMinutes}'}))),
            ],
          ),
        );
        if (choice != null && mounted) _setPhase(t, g, choice);
        return;
      }
      _setPhase(t, g, Phase.pens);
      return;
    }
    _finish(t, g);
  }

  void _finish(Tournament t, Game g) {
    g.phase = Phase.ft;
    g.status = Status.done;
    g.phaseStart = nowMs();
    _save(t);
    final ch = FZ.champion(t);
    final isFinal = g.stage == 'ko' && g.roundSize == 2 && !g.third;
    snack(context, ch != null && isFinal ? tr('championToast', {'name': teamName(t, ch)}) : tr('matchOver'));
  }

  Future<void> _addedTime(Tournament t, Game g) async {
    final v = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('addedTitle'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Hint(tr('addedHint')),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i <= 12; i++)
                ChoiceChip(label: Text(i == 0 ? tr('none') : '+$i'), selected: g.added == i, onSelected: (_) => Navigator.pop(c, i)),
            ]),
          ]),
        ),
      ),
    );
    if (v == null) return;
    g.added = v;
    _save(t);
  }

  Future<void> _quickScore(Tournament t, Game g) async {
    final sc = FZ.score(g, t.settings);
    var h = sc.h, a = sc.a;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tr('finalScore')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            NumStepper(label: teamName(t, g.home), value: h, min: 0, max: 99, onChanged: (v) => set(() => h = v)),
            const SizedBox(height: 12),
            NumStepper(label: teamName(t, g.away), value: a, min: 0, max: 99, onChanged: (v) => set(() => a = v)),
            const SizedBox(height: 10),
            Hint(tr('quickScoreHint')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('saveScore'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    _setGoals(g, g.home!, h);
    _setGoals(g, g.away!, a);
    if (FZ.koLevel(t, g)) {
      g.status = Status.live;
      g.phase = Phase.pens;
      g.pensH ??= 0;
      g.pensA ??= 0;
      _save(t);
      snack(context, tr('levelNeedPens'));
      return;
    }
    _finish(t, g);
  }

  /// Ajuste le nombre de buts d'une équipe en gardant les buteurs déjà connus.
  void _setGoals(Game g, String teamId, int target) {
    List<MatchEvent> mine() => g.events.where((e) => !e.cancelled && e.isGoal && e.teamId == teamId).toList();
    while (mine().length < target) {
      g.events.add(MatchEvent(id: newId('e'), type: 'goal', teamId: teamId));
    }
    while (mine().length > target) {
      final list = mine();
      final anon = list.where((e) => e.playerId == null).toList();
      final victim = (anon.isNotEmpty ? anon : list).last;
      g.events.remove(victim);
    }
  }

  Future<void> _forfeit(Tournament t, Game g) async {
    final who = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(tr('forfeitWho')),
        children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Hint(tr('forfeitHint', {'n': '${t.settings.forfeitGoals}'}))),
          const SizedBox(height: 8),
          for (final id in [g.home!, g.away!])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, id),
              child: Row(children: [Crest(t.team(id), size: 30), const SizedBox(width: 10), Expanded(child: Text(teamName(t, id), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))]),
            ),
          SimpleDialogOption(onPressed: () => Navigator.pop(c), child: Text(tr('cancel'))),
        ],
      ),
    );
    if (who == null || !mounted) return;
    g.forfeit = who;
    g.status = Status.done;
    g.phase = Phase.ft;
    _save(t);
    snack(context, tr('forfeitSaved'));
  }

  // --------------------------------------------------------- événements
  Future<void> _newEvent(Tournament t, Game g, String kind, {String? teamId}) async {
    final ck = FZ.clock(g, t.settings);
    final e = await showModalBottomSheet<MatchEvent>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _EventSheet(
        t: t,
        g: g,
        kind: kind,
        teamId: teamId,
        minute: ck.running ? ck.minute : null,
        extra: ck.running && ck.extra > 0 ? ck.extra : null,
        onAddPlayer: (team, p) {
          team.players.add(p);
          _save(t);
        },
      ),
    );
    if (e == null || !mounted) return;
    g.events.add(e);
    _save(t);
    String msg;
    switch (e.type) {
      case 'yellow':
        final n = g.events.where((x) => !x.cancelled && x.type == 'yellow' && x.playerId != null && x.playerId == e.playerId).length;
        msg = n >= 2 ? tr('secondYellow') : tr('yellowSaved');
        break;
      case 'red':
        msg = tr('redSaved');
        break;
      case 'sub':
        msg = tr('subSaved');
        break;
      default:
        msg = tr('goalSaved', {'team': teamName(t, e.teamId)});
    }
    final st = store;
    snack(context, msg, actionLabel: tr('undo'), seconds: 10, onAction: () {
      final tt = st.byId(t.id);
      final gg = tt?.game(g.id);
      if (tt == null || gg == null) return;
      gg.events.removeWhere((x) => x.id == e.id);
      st.save(tt);
    });
  }

  Future<void> _toggleCancel(Tournament t, Game g, MatchEvent e) async {
    if (!e.cancelled) {
      final ok = await confirm(context, title: tr('cancelFactTitle'), body: tr('cancelFactBody'), ok: tr('cancelFact'), danger: true);
      if (!ok || !mounted) return;
    }
    e.cancelled = !e.cancelled;
    _save(t);
  }

  Future<void> _pickMotm(Tournament t, Game g) async {
    final players = [t.team(g.home), t.team(g.away)].whereType<Team>().expand((tm) => tm.players.map((p) => (tm, p))).toList();
    final v = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * .8),
          child: ListView(shrinkWrap: true, children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(tr('motm'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
            ListTile(leading: const Icon(Icons.clear), title: Text(tr('motmNone')), onTap: () => Navigator.pop(c, '')),
            for (final x in players)
              ListTile(
                leading: Crest(x.$1, size: 30),
                title: Text(playerLabel(t, x.$2.id)),
                subtitle: Text(x.$1.name),
                trailing: g.motm == x.$2.id ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(c, x.$2.id),
              ),
          ]),
        ),
      ),
    );
    if (v == null || !mounted) return;
    g.motm = v.isEmpty ? null : v;
    _save(t);
  }

  // -------------------------------------------------------------- écran
  @override
  Widget build(BuildContext context) {
    final storeW = StoreScope.of(context);
    final t = storeW.byId(widget.tid);
    final g = t?.game(widget.gid);
    if (t == null || g == null) {
      return Scaffold(appBar: FzAppBar(), body: EmptyState(icon: Icons.sports_soccer, text: tr('matchGone')));
    }
    final p = Pal.of(context);
    final s = t.settings;
    final locked = FZ.koLocked(t, g);
    final canEdit = g.ready && g.forfeit == null && !locked;
    final canEvent = canEdit && g.status != Status.scheduled;
    final out = <Widget>[_Scoreboard(t: t, g: g), const SizedBox(height: 14)];

    if (!g.ready) {
      out.add(Banner2(tr('teamsLater'), icon: Icons.hourglass_empty));
    } else if (g.forfeit != null) {
      out.add(Banner2(tr('forfeitBanner', {'team': teamName(t, g.forfeit), 'n': '${s.forfeitGoals}', 'winner': teamName(t, g.forfeit == g.home ? g.away : g.home)}), icon: Icons.flag_outlined));
      if (!(t.team(g.forfeit)?.withdrawn ?? false) && !locked) {
        out.add(const SizedBox(height: 10));
        out.add(OutlinedButton(
          onPressed: () {
            g.forfeit = null;
            g.status = Status.scheduled;
            g.phase = Phase.pre;
            _save(t);
          },
          child: Text(tr('cancelForfeit')),
        ));
      }
    } else if (locked) {
      out.add(Banner2(tr('lockedBanner'), icon: Icons.lock_outline));
    } else {
      out.addAll(_controls(t, g));
    }

    if (canEvent) {
      final hc = t.team(g.home)!, ac = t.team(g.away)!;
      out.add(const SizedBox(height: 14));
      out.add(Row(children: [
        Expanded(child: _GoalButton(team: hc, label: tr('goalFor', {'team': hc.name}), onTap: () => _newEvent(t, g, 'goal', teamId: hc.id))),
        const SizedBox(width: 10),
        Expanded(child: _GoalButton(team: ac, label: tr('goalFor', {'team': ac.name}), onTap: () => _newEvent(t, g, 'goal', teamId: ac.id))),
      ]));
      out.add(const SizedBox(height: 10));
      out.add(Row(children: [
        Expanded(child: _SmallAction(icon: const CardMark(), label: tr('yellowCard'), onTap: () => _newEvent(t, g, 'yellow'))),
        const SizedBox(width: 8),
        Expanded(child: _SmallAction(icon: const CardMark(red: true), label: tr('redCard'), onTap: () => _newEvent(t, g, 'red'))),
        const SizedBox(width: 8),
        Expanded(child: _SmallAction(icon: Icon(Icons.swap_horiz, color: p.board2), label: tr('substitution'), onTap: () => _newEvent(t, g, 'sub'))),
      ]));
    }

    final sus = g.ready ? (FZ.suspensions(t).byGame[g.id] ?? const <String>[]) : const <String>[];
    if (sus.isNotEmpty) {
      out.add(const SizedBox(height: 12));
      out.add(Banner2('${tr('suspendedThisMatch')} ${sus.map((pid) => '${playerLabel(t, pid)} (${t.player(pid)?.team.name ?? ''})').join(', ')}', icon: Icons.block));
    }

    // Déroulement
    final evs = List<MatchEvent>.of(g.events)
      ..sort((a, b) {
        final c = (a.minute ?? 0).compareTo(b.minute ?? 0);
        if (c != 0) return c;
        final d = (a.extra ?? 0).compareTo(b.extra ?? 0);
        if (d != 0) return d;
        return a.at.compareTo(b.at);
      });
    if (evs.isNotEmpty) {
      final yellowSeen = <String, int>{};
      out.add(const SizedBox(height: 14));
      out.add(Panel(title: tr('timeline'), padding: const EdgeInsets.fromLTRB(16, 16, 8, 8), children: [
        for (final e in evs) _eventRow(t, g, e, yellowSeen, canEvent),
      ]));
    }

    if (g.ready && g.status != Status.scheduled && g.forfeit == null) {
      out.add(const SizedBox(height: 14));
      final motm = t.player(g.motm);
      out.add(Panel(title: tr('motm'), children: [
        if (motm != null)
          Row(children: [Icon(Icons.star, color: p.yellow), const SizedBox(width: 8), Expanded(child: Text('${playerLabel(t, g.motm)} (${motm.team.name})', style: const TextStyle(fontWeight: FontWeight.w700)))]),
        OutlinedButton.icon(
          onPressed: [t.team(g.home), t.team(g.away)].any((x) => (x?.players.length ?? 0) > 0) ? () => _pickMotm(t, g) : null,
          icon: const Icon(Icons.star_outline),
          label: Text(motm == null ? tr('chooseMotm') : tr('changeMotm')),
        ),
        if ([t.team(g.home), t.team(g.away)].every((x) => (x?.players.length ?? 0) == 0)) Hint(tr('motmNeedsPlayers')),
      ]));
    }

    if (g.ready && !locked) {
      out.add(const SizedBox(height: 14));
      out.add(Panel(title: tr('matchInfo'), children: [
        _InfoField(key: ValueKey('w${g.id}'), label: tr('whenLabel'), hint: tr('whenHint'), value: g.when, onSave: (v) => setState(() {
              g.when = v;
              _save(t);
            })),
        _InfoField(key: ValueKey('v${g.id}'), label: tr('venueLabel'), hint: tr('venueHint'), value: g.venue, onSave: (v) => setState(() {
              g.venue = v;
              _save(t);
            })),
        _InfoField(key: ValueKey('r${g.id}'), label: tr('refereeLabel'), hint: tr('refereeHint'), value: g.referee, onSave: (v) => setState(() {
              g.referee = v;
              _save(t);
            })),
      ]));
    }

    if (g.ready && g.status != Status.scheduled) {
      out.add(const SizedBox(height: 14));
      out.add(FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: p.board),
        onPressed: () => shareImage(context, (v) => ShareImages.result(t, g, v), 'resultat'),
        icon: const Icon(Icons.ios_share),
        label: Text(g.status == Status.done ? tr('shareResult') : tr('shareScore')),
      ));
    }

    return Scaffold(
      appBar: FzAppBar(title: Text(roundTitle(t, g))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: out),
    );
  }

  List<Widget> _controls(Tournament t, Game g) {
    final p = Pal.of(context);
    Widget big(IconData icon, String label, VoidCallback onTap, {bool primary = true}) => FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 60), backgroundColor: primary ? p.cone : p.board),
          onPressed: onTap,
          icon: Icon(icon, size: 26),
          label: Text(label, style: const TextStyle(fontSize: 18)),
        );
    Widget added() => OutlinedButton.icon(
          onPressed: () => _addedTime(t, g),
          icon: const Icon(Icons.more_time),
          label: Text(g.added > 0 ? tr('addedSet', {'n': '${g.added}'}) : tr('announceAdded')),
        );
    final level = FZ.koLevel(t, g);
    switch (g.phase) {
      case Phase.pre:
        return [
          big(Icons.sports, tr('startMatch'), () => _setPhase(t, g, Phase.h1)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _quickScore(t, g), icon: const Icon(Icons.edit_note), label: Text(tr('enterScore')))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: () => _forfeit(t, g), icon: const Icon(Icons.flag_outlined), label: Text(tr('forfeit')))),
          ]),
        ];
      case Phase.h1:
        return [big(Icons.sports, tr('whistleHalfTime'), () => _setPhase(t, g, Phase.ht), primary: false), const SizedBox(height: 10), added()];
      case Phase.ht:
        return [big(Icons.play_arrow, tr('startSecondHalf'), () => _setPhase(t, g, Phase.h2))];
      case Phase.h2:
        return [big(Icons.sports, tr('whistleEnd'), () => _end(t, g), primary: false), const SizedBox(height: 10), added()];
      case Phase.et1:
        return [big(Icons.sports, tr('endEt1'), () => _setPhase(t, g, Phase.et2), primary: false), const SizedBox(height: 10), added()];
      case Phase.et2:
        return [big(Icons.sports, tr('endEt2'), () => _end(t, g), primary: false), const SizedBox(height: 10), added()];
      case Phase.pens:
        return [_PensPanel(t: t, g: g, live: true, onChanged: () => _save(t), onValidate: () {
          if (g.pensH == null || g.pensA == null || g.pensH == g.pensA) {
            snack(context, tr('pensNeedWinner'));
            return;
          }
          _finish(t, g);
        })];
      default:
        return [
          OutlinedButton.icon(onPressed: () => _quickScore(t, g), icon: const Icon(Icons.edit_note), label: Text(tr('fixScore'))),
          if (level) ...[const SizedBox(height: 12), _PensPanel(t: t, g: g, live: false, onChanged: () => _save(t))],
        ];
    }
  }

  Widget _eventRow(Tournament t, Game g, MatchEvent e, Map<String, int> yellowSeen, bool canEdit) {
    final p = Pal.of(context);
    Widget icon;
    String what;
    switch (e.type) {
      case 'pen':
        icon = Icon(Icons.sports_soccer, color: p.ink);
        what = tr('evPen');
        break;
      case 'og':
        icon = Icon(Icons.sports_soccer, color: p.red);
        what = tr('evOg');
        break;
      case 'yellow':
        if (!e.cancelled && e.playerId != null) yellowSeen[e.playerId!] = (yellowSeen[e.playerId!] ?? 0) + 1;
        icon = const CardMark();
        what = (!e.cancelled && e.playerId != null && yellowSeen[e.playerId!] == 2) ? tr('evSecondYellow') : tr('evYellow');
        break;
      case 'red':
        icon = const CardMark(red: true);
        what = tr('evRed');
        break;
      case 'sub':
        icon = Icon(Icons.swap_horiz, color: p.board2);
        what = tr('evSub');
        break;
      default:
        icon = Icon(Icons.sports_soccer, color: p.ink);
        what = tr('evGoal');
    }
    String who;
    String sub;
    if (e.type == 'sub') {
      who = '${playerLabel(t, e.inId)}  ↑';
      sub = '${playerLabel(t, e.playerId)} ↓, ${teamName(t, e.teamId)}';
    } else {
      who = e.playerId == null ? what : playerLabel(t, e.playerId);
      final team = e.type == 'og' ? tr('forTeam', {'team': teamName(t, e.teamId)}) : teamName(t, e.teamId);
      sub = [if (e.playerId != null) what, team, if (e.assistId != null) tr('assistBy', {'name': playerLabel(t, e.assistId, withNum: false)})].join(', ');
    }
    final minute = e.minute == null ? '–' : "${e.minute}${e.extra != null && e.extra! > 0 ? '+${e.extra}' : ''}'";
    final style = TextStyle(decoration: e.cancelled ? TextDecoration.lineThrough : null, color: e.cancelled ? p.muted : null);
    return Opacity(
      opacity: e.cancelled ? .6 : 1,
      child: Row(children: [
        SizedBox(width: 48, child: Text(minute, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: p.muted))),
        SizedBox(width: 30, child: Center(child: icon)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(who, style: style.copyWith(fontWeight: FontWeight.w700, fontSize: 15.5)),
            Text(e.cancelled ? '${tr('cancelled')}, $sub' : sub, style: style.copyWith(fontSize: 13, color: p.muted)),
          ]),
        ),
        if (canEdit)
          IconButton(
            tooltip: e.cancelled ? tr('restoreFact') : tr('cancelFact'),
            onPressed: () => _toggleCancel(t, g, e),
            icon: Icon(e.cancelled ? Icons.restore : Icons.undo, color: p.muted),
          ),
      ]),
    );
  }
}

// ============================================================ composants

class _Scoreboard extends StatelessWidget {
  final Tournament t;
  final Game g;
  const _Scoreboard({required this.t, required this.g});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final sc = FZ.score(g, t.settings);
    final ck = FZ.clock(g, t.settings);
    final agg = FZ.aggregate(t, g);
    final label = [
      if (g.group != null) tr('groupN', {'g': g.group!}),
      roundTitle(t, g),
      if (g.when.isNotEmpty) g.when,
    ].join(', ');
    final showScore = g.ready && g.status != Status.scheduled;
    Widget side(String? id) => Expanded(
          child: Column(children: [
            Crest(t.team(id), size: 64),
            const SizedBox(height: 8),
            Text(id == null ? tr('tbd') : teamName(t, id),
                textAlign: TextAlign.center, maxLines: 3, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16, height: 1.15)),
          ]),
        );
    return Container(
      decoration: BoxDecoration(color: p.board, borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
      child: CustomPaint(
        painter: _PitchLines(),
        child: Column(children: [
          Text(label, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 14)),
          if (g.venue.isNotEmpty || g.referee.isNotEmpty)
            Text([if (g.venue.isNotEmpty) g.venue, if (g.referee.isNotEmpty) tr('refShort', {'name': g.referee})].join(', '),
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 13)),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            side(g.home),
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: .2), borderRadius: BorderRadius.circular(12)),
              child: Text(
                showScore ? '${sc.h} - ${sc.a}' : '–',
                style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w900, height: 1.05, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
            side(g.away),
          ]),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              decoration: BoxDecoration(color: ck.running ? p.cone : Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(8)),
              child: Text(ck.label ?? tr('phase_${ck.state}'), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
          ),
          if (g.added > 0 && ck.running)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('addedSet', {'n': '${g.added}'}), style: TextStyle(color: Colors.white.withValues(alpha: .8)))),
          if (agg != null && showScore)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr('aggregate', {'h': '${agg.h}', 'a': '${agg.a}'}), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          if (g.hasPens && ((g.pensH ?? 0) + (g.pensA ?? 0) > 0 || g.phase == Phase.pens))
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('pensLine', {'h': '${g.pensH}', 'a': '${g.pensA}'}), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        ]),
      ),
    );
  }
}

class _PitchLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-4, -6, s.width + 8, s.height + 12), const Radius.circular(12)), paint);
    canvas.drawLine(Offset(s.width / 2, -6), Offset(s.width / 2, s.height + 6), paint);
    canvas.drawCircle(Offset(s.width / 2, s.height / 2), 56, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GoalButton extends StatelessWidget {
  final Team team;
  final String label;
  final VoidCallback onTap;
  const _GoalButton({required this.team, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: Color(team.color),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 84),
            padding: const EdgeInsets.all(8),
            alignment: Alignment.center,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.sports_soccer, color: Colors.white, size: 30),
              const SizedBox(height: 4),
              Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
          ),
        ),
      );
}

class _SmallAction extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback onTap;
  const _SmallAction({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: p.line, width: 2)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            icon,
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.1)),
          ]),
        ),
      ),
    );
  }
}

class _PensPanel extends StatelessWidget {
  final Tournament t;
  final Game g;
  final bool live;
  final VoidCallback onChanged;
  final VoidCallback? onValidate;
  const _PensPanel({required this.t, required this.g, required this.live, required this.onChanged, this.onValidate});
  @override
  Widget build(BuildContext context) => Panel(title: tr('penaltyShootout'), children: [
        Row(children: [
          Expanded(
              child: NumStepper(
                  label: teamName(t, g.home),
                  value: g.pensH ?? 0,
                  min: 0,
                  max: 30,
                  onChanged: (v) {
                    g.pensH = v;
                    g.pensA ??= 0;
                    onChanged();
                  })),
          const SizedBox(width: 12),
          Expanded(
              child: NumStepper(
                  label: teamName(t, g.away),
                  value: g.pensA ?? 0,
                  min: 0,
                  max: 30,
                  onChanged: (v) {
                    g.pensA = v;
                    g.pensH ??= 0;
                    onChanged();
                  })),
        ]),
        if (live && onValidate != null) FilledButton(onPressed: onValidate, child: Text(tr('validatePens'))) else Hint(tr('pensHint')),
      ]);
}

class _InfoField extends StatefulWidget {
  final String label;
  final String hint;
  final String value;
  final ValueChanged<String> onSave;
  const _InfoField({super.key, required this.label, required this.hint, required this.value, required this.onSave});
  @override
  State<_InfoField> createState() => _InfoFieldState();
}

class _InfoFieldState extends State<_InfoField> {
  late final TextEditingController c = TextEditingController(text: widget.value);
  final FocusNode f = FocusNode();
  @override
  void initState() {
    super.initState();
    f.addListener(() {
      if (!f.hasFocus && c.text.trim() != widget.value) widget.onSave(c.text.trim());
    });
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
        maxLength: 60,
        onSubmitted: (v) {
          if (v.trim() != widget.value) widget.onSave(v.trim());
        },
        decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
      );
}

/// Fenêtre de saisie d'un fait de match. Un but tient en 3 touches :
/// « But » → buteur → passeur (ou « Passer »).
class _EventSheet extends StatefulWidget {
  final Tournament t;
  final Game g;
  final String kind; // goal, yellow, red, sub
  final String? teamId;
  final int? minute;
  final int? extra;
  final void Function(Team team, Player p) onAddPlayer;
  const _EventSheet({required this.t, required this.g, required this.kind, this.teamId, this.minute, this.extra, required this.onAddPlayer});
  @override
  State<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<_EventSheet> {
  late String? teamId = widget.teamId;
  String goalType = 'goal';
  String? scorer;
  bool scorerChosen = false;
  String? outId;
  bool outChosen = false;
  late final TextEditingController minute = TextEditingController(text: widget.minute?.toString() ?? '');
  final TextEditingController newPlayer = TextEditingController();

  @override
  void dispose() {
    minute.dispose();
    newPlayer.dispose();
    super.dispose();
  }

  Tournament get t => widget.t;
  Game get g => widget.g;

  String? get listTeamId {
    if (teamId == null) return null;
    if (widget.kind == 'goal' && goalType == 'og') return teamId == g.home ? g.away : g.home;
    return teamId;
  }

  void _done({String? playerId, String? assistId, String? inId}) {
    final m = int.tryParse(minute.text.trim());
    final type = widget.kind == 'goal' ? goalType : widget.kind;
    final e = MatchEvent(
      id: newId('e'),
      type: type,
      teamId: teamId!,
      playerId: widget.kind == 'sub' ? outId : playerId,
      assistId: assistId,
      inId: inId,
      minute: m != null && m > 0 && m < 200 ? m : null,
      extra: (m != null && m == widget.minute) ? widget.extra : null,
    );
    Navigator.pop(context, e);
  }

  void _addPlayer() {
    final tm = t.team(listTeamId);
    final raw = newPlayer.text.trim();
    if (tm == null || raw.isEmpty) return;
    final m = RegExp(r'^(\d{1,2})[\s.,;:-]+(.+)$').firstMatch(raw);
    final p = Player(id: newId('p'), num: m?.group(1) ?? '', name: (m?.group(2) ?? raw).trim());
    widget.onAddPlayer(tm, p);
    newPlayer.clear();
    setState(() {});
  }

  Widget _grid(List<Player> players, String? selected, ValueChanged<String?> onPick, {bool allowNone = true, String? noneLabel, Set<String> exclude = const {}}) {
    final p = Pal.of(context);
    final sus = FZ.suspensions(t).byGame[g.id]?.toSet() ?? <String>{};
    final off = FZ.sentOff(g);
    final list = players.where((x) => !exclude.contains(x.id)).toList()..sort((a, b) => (int.tryParse(a.num) ?? 999).compareTo(int.tryParse(b.num) ?? 999));
    return LayoutBuilder(builder: (c, box) {
      final w = (box.maxWidth - 8) / 2;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final pl in list)
          SizedBox(
            width: w,
            child: _PlayerChip(
              num: pl.num,
              name: pl.name,
              note: sus.contains(pl.id) ? tr('suspended') : (off.contains(pl.id) ? tr('sentOff') : null),
              selected: selected == pl.id,
              onTap: () => onPick(pl.id),
            ),
          ),
        if (allowNone)
          SizedBox(
            width: w,
            child: _PlayerChip(num: '?', name: noneLabel ?? tr('noName'), selected: false, onTap: () => onPick(null), muted: p.muted),
          ),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final kind = widget.kind;
    final children = <Widget>[];
    String title;
    switch (kind) {
      case 'goal':
        title = tr('goalFor', {'team': teamName(t, teamId)});
        break;
      case 'yellow':
        title = tr('yellowCard');
        break;
      case 'red':
        title = tr('redCard');
        break;
      default:
        title = tr('substitution');
    }
    children.add(Row(children: [
      Expanded(child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
      SizedBox(
        width: 92,
        child: TextField(controller: minute, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('minute'), isDense: true)),
      ),
    ]));
    children.add(const SizedBox(height: 12));

    if (kind != 'goal') {
      children.add(Choice<String>(
        options: [(g.home!, teamName(t, g.home)), (g.away!, teamName(t, g.away))],
        value: teamId ?? '',
        onChanged: (v) => setState(() {
          teamId = v;
          outId = null;
          outChosen = false;
        }),
      ));
      children.add(const SizedBox(height: 12));
    } else {
      children.add(Choice<String>(
        options: [('goal', tr('evGoal')), ('pen', tr('penalty')), ('og', tr('ownGoal'))],
        value: goalType,
        onChanged: (v) => setState(() {
          goalType = v;
          scorer = null;
          scorerChosen = false;
        }),
      ));
      children.add(const SizedBox(height: 12));
    }

    final tm = t.team(listTeamId);
    if (tm == null) {
      children.add(Hint(tr('pickTeamFirst')));
    } else if (kind == 'goal' && goalType == 'goal' && scorerChosen) {
      // Étape passeur (facultative)
      children.add(Text(tr('assistOptional'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)));
      children.add(const SizedBox(height: 8));
      children.add(FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: p.board),
        onPressed: () => _done(playerId: scorer),
        icon: const Icon(Icons.skip_next),
        label: Text(tr('skip')),
      ));
      children.add(const SizedBox(height: 10));
      children.add(_grid(tm.players, null, (id) => _done(playerId: scorer, assistId: id), allowNone: false, exclude: {if (scorer != null) scorer!}));
    } else if (kind == 'sub' && outChosen) {
      children.add(Text(tr('playerIn'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)));
      children.add(const SizedBox(height: 8));
      children.add(_grid(tm.players, null, (id) => _done(inId: id), exclude: {if (outId != null) outId!}));
    } else {
      final label = kind == 'sub'
          ? tr('playerOut')
          : (kind == 'goal' ? (goalType == 'og' ? tr('ogPlayer', {'team': tm.name}) : tr('scorer')) : tr('whichPlayer'));
      children.add(Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)));
      children.add(const SizedBox(height: 8));
      children.add(_grid(tm.players, null, (id) {
        if (kind == 'goal' && goalType == 'goal') {
          setState(() {
            scorer = id;
            scorerChosen = true;
          });
          if (id == null) _done();
          return;
        }
        if (kind == 'sub') {
          setState(() {
            outId = id;
            outChosen = true;
          });
          return;
        }
        _done(playerId: id);
      }));
    }

    if (tm != null) {
      children.add(const SizedBox(height: 12));
      children.add(Row(children: [
        Expanded(
          child: TextField(
            controller: newPlayer,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _addPlayer(),
            decoration: InputDecoration(hintText: tr('newPlayerHint'), isDense: true),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(64, 46)), onPressed: _addPlayer, child: Text(tr('add'))),
      ]));
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .85),
          child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children)),
        ),
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  final String num;
  final String name;
  final String? note;
  final bool selected;
  final VoidCallback onTap;
  final Color? muted;
  const _PlayerChip({required this.num, required this.name, this.note, required this.selected, required this.onTap, this.muted});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Material(
      color: selected ? Color.alphaBlend(p.cone.withValues(alpha: .12), p.surface) : p.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: selected ? p.cone : p.line, width: 2)),
          child: Row(children: [
            SizedBox(width: 30, child: Text(num, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: muted ?? p.board2))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.15, color: note != null ? p.muted : p.ink)),
                if (note != null) Text(note!, style: TextStyle(fontSize: 12, color: p.red, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
