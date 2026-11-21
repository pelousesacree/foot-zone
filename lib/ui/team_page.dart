// Foot Zone — fiche d'une équipe : nom, couleur, logo, joueurs, retrait.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/store.dart';
import '../engine/engine.dart';
import '../engine/models.dart';
import '../l10n/strings.dart';
import 'theme.dart';
import 'widgets.dart';

class TeamPage extends StatefulWidget {
  final String tid;
  final String teamId;
  const TeamPage({super.key, required this.tid, required this.teamId});
  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  final bulk = TextEditingController();
  late final TextEditingController nameC;
  bool _init = false;

  @override
  void dispose() {
    bulk.dispose();
    if (_init) nameC.dispose();
    super.dispose();
  }

  static List<Player> parsePlayers(String text) {
    final out = <Player>[];
    for (final raw in text.split('\n')) {
      final l = raw.trim();
      if (l.isEmpty) continue;
      final m = RegExp(r'^(\d{1,2})[\s.,;:-]+(.+)$').firstMatch(l);
      final name = (m?.group(2) ?? l).trim();
      out.add(Player(id: newId('p'), num: m?.group(1) ?? '', name: name.length > 40 ? name.substring(0, 40) : name));
    }
    return out;
  }

  Future<void> _pickLogo(Tournament t, Team team) async {
    try {
      final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 256, maxHeight: 256, imageQuality: 80);
      if (img == null) return;
      final bytes = await img.readAsBytes();
      if (bytes.length > 400 * 1024) {
        if (mounted) snack(context, tr('logoTooBig'));
        return;
      }
      team.logo = base64Encode(bytes);
      if (mounted) StoreScope.read(context).save(t);
    } catch (_) {
      if (mounted) snack(context, tr('logoFailed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = store.byId(widget.tid);
    final team = t?.team(widget.teamId);
    if (t == null || team == null) {
      return Scaffold(appBar: FzAppBar(), body: EmptyState(icon: Icons.groups_outlined, text: tr('teamGone')));
    }
    if (!_init) {
      nameC = TextEditingController(text: team.name);
      _init = true;
    }
    final p = Pal.of(context);
    final sus = FZ.suspensions(t);
    final players = List<Player>.of(team.players)..sort((a, b) => (int.tryParse(a.num) ?? 999).compareTo(int.tryParse(b.num) ?? 999));

    void saveName() {
      final v = nameC.text.trim();
      if (v.isEmpty || v == team.name) {
        nameC.text = team.name;
        return;
      }
      if (t.teams.any((o) => o.id != team.id && o.name.toLowerCase() == v.toLowerCase())) {
        snack(context, tr('nameTaken'));
        nameC.text = team.name;
        return;
      }
      team.name = v.length > 40 ? v.substring(0, 40) : v;
      store.save(t);
    }

    return Scaffold(
      appBar: FzAppBar(title: Text(team.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          Panel(children: [
            Row(children: [
              Crest(team, size: 72),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  OutlinedButton.icon(
                    onPressed: () => _pickLogo(t, team),
                    icon: const Icon(Icons.image_outlined),
                    label: Text(team.logo == null ? tr('addLogo') : tr('changeLogo')),
                  ),
                  if (team.logo != null)
                    TextButton(
                      onPressed: () {
                        team.logo = null;
                        store.save(t);
                      },
                      child: Text(tr('removeLogo')),
                    ),
                ]),
              ),
            ]),
            Hint(tr('logoHint')),
            Focus(
              onFocusChange: (has) {
                if (!has) saveName();
              },
              child: TextField(
                controller: nameC,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                onSubmitted: (_) => saveName(),
                decoration: InputDecoration(labelText: tr('teamName')),
              ),
            ),
            Text(tr('color'), style: const TextStyle(fontWeight: FontWeight.w700)),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final c in teamPalette)
                Semantics(
                  button: true,
                  selected: team.color == c,
                  label: tr('color'),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      team.color = c;
                      store.save(t);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(color: team.color == c ? p.ink : p.surface, width: 3),
                      ),
                      child: team.color == c ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                    ),
                  ),
                ),
            ]),
          ]),
          const SizedBox(height: 14),
          Panel(title: '${tr('players')} (${team.players.length})', children: [
            if (players.isEmpty) Hint(tr('noPlayers')),
            for (final pl in players)
              _PlayerRow(
                key: ValueKey(pl.id),
                player: pl,
                suspended: (sus.remaining[pl.id] ?? 0) > 0,
                yellows: sus.yellows[pl.id] ?? 0,
                onChanged: () => store.save(t),
                onDelete: () async {
                  final used = t.games.any((m) => m.motm == pl.id || m.events.any((e) => e.playerId == pl.id || e.assistId == pl.id || e.inId == pl.id));
                  final ok = await confirm(context, title: tr('deletePlayerTitle'), body: used ? tr('deletePlayerUsed') : tr('deletePlayerBody'), ok: tr('deleteIt'), danger: true);
                  if (!ok) return;
                  team.players.removeWhere((x) => x.id == pl.id);
                  store.save(t);
                },
              ),
            const Divider(),
            Text(tr('addPlayers'), style: const TextStyle(fontWeight: FontWeight.w700)),
            Hint(tr('addPlayersHint')),
            TextField(controller: bulk, minLines: 3, maxLines: 10, textCapitalization: TextCapitalization.words, decoration: InputDecoration(hintText: tr('addPlayersPlaceholder'))),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: p.board),
              onPressed: () {
                final list = parsePlayers(bulk.text);
                if (list.isEmpty) {
                  snack(context, tr('addPlayersEmpty'));
                  return;
                }
                if (team.players.length + list.length > 40) {
                  snack(context, tr('maxPlayers'));
                  return;
                }
                team.players.addAll(list);
                bulk.clear();
                store.save(t);
                snack(context, tr('playersAdded', {'n': '${list.length}'}));
              },
              icon: const Icon(Icons.person_add_alt),
              label: Text(tr('add')),
            ),
          ]),
          const SizedBox(height: 14),
          Panel(title: tr('withdrawTitle'), children: [
            if (team.withdrawn)
              Hint(tr('withdrawnInfo'))
            else ...[
              Hint(tr('withdrawHint', {'n': '${t.settings.forfeitGoals}'})),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: p.red),
                onPressed: () async {
                  final ok = await confirm(context,
                      title: tr('withdrawConfirmTitle', {'name': team.name}), body: tr('withdrawConfirmBody', {'n': '${t.settings.forfeitGoals}'}), ok: tr('withdrawIt'), danger: true);
                  if (!ok || !context.mounted) return;
                  final n = FZ.withdrawTeam(t, team.id);
                  store.save(t);
                  snack(context, tr('withdrawDone', {'n': '$n'}));
                },
                icon: const Icon(Icons.flag_outlined),
                label: Text(tr('withdrawIt')),
              ),
            ],
          ]),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatefulWidget {
  final Player player;
  final bool suspended;
  final int yellows;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  const _PlayerRow({super.key, required this.player, required this.suspended, required this.yellows, required this.onChanged, required this.onDelete});
  @override
  State<_PlayerRow> createState() => _PlayerRowState();
}

class _PlayerRowState extends State<_PlayerRow> {
  late final TextEditingController numC = TextEditingController(text: widget.player.num);
  late final TextEditingController name = TextEditingController(text: widget.player.name);

  @override
  void dispose() {
    numC.dispose();
    name.dispose();
    super.dispose();
  }

  void _save() {
    final n = numC.text.replaceAll(RegExp(r'\D'), '');
    final nm = name.text.trim();
    var changed = false;
    if (n != widget.player.num) {
      widget.player.num = n.length > 2 ? n.substring(0, 2) : n;
      changed = true;
    }
    if (nm.isNotEmpty && nm != widget.player.name) {
      widget.player.name = nm.length > 40 ? nm.substring(0, 40) : nm;
      changed = true;
    }
    if (nm.isEmpty) name.text = widget.player.name;
    if (changed) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Row(children: [
      SizedBox(
        width: 64,
        child: Focus(
          onFocusChange: (h) {
            if (!h) _save();
          },
          child: TextField(controller: numC, keyboardType: TextInputType.number, maxLength: 2, decoration: InputDecoration(counterText: '', labelText: tr('numShort'), isDense: true)),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Focus(
          onFocusChange: (h) {
            if (!h) _save();
          },
          child: TextField(controller: name, maxLength: 40, textCapitalization: TextCapitalization.words, decoration: InputDecoration(counterText: '', labelText: tr('name'), isDense: true)),
        ),
      ),
      const SizedBox(width: 6),
      if (widget.suspended)
        Chip2(tr('suspended'), bg: Color.alphaBlend(p.red.withValues(alpha: .18), p.surface), fg: p.red)
      else if (widget.yellows > 0)
        Row(mainAxisSize: MainAxisSize.min, children: [const CardMark(h: 16), const SizedBox(width: 2), Text('${widget.yellows}')]),
      IconButton(tooltip: tr('deleteIt'), onPressed: widget.onDelete, icon: Icon(Icons.delete_outline, color: p.muted)),
    ]);
  }
}
