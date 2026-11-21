// Foot Zone — composants partagés.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../l10n/strings.dart';
import 'theme.dart';

String initials(String name) {
  final words = name
      .replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  const skip = {'fc', 'as', 'ac', 'us', 'sc', 'cf', 'cs', 'de', 'du', 'des', 'la', 'le', 'les', 'the'};
  var ws = words.where((w) => !skip.contains(w.toLowerCase())).toList();
  if (ws.isEmpty) ws = words;
  if (ws.isEmpty) return '?';
  if (ws.length > 1) return (ws[0].characters.first + ws[1].characters.first).toUpperCase();
  return ws[0].characters.take(2).toString().toUpperCase();
}

final Map<String, Uint8List> _logoCache = {};

Uint8List? logoBytes(Team? t) {
  final logo = t?.logo;
  if (t == null || logo == null) return null;
  final key = '${t.id}:${logo.length}:${logo.hashCode}';
  final hit = _logoCache[key];
  if (hit != null) return hit;
  try {
    final b = base64Decode(logo);
    _logoCache[key] = b;
    return b;
  } catch (_) {
    return null;
  }
}

String teamName(Tournament t, String? id) => t.team(id)?.name ?? tr('tbd');

class Crest extends StatelessWidget {
  final Team? team;
  final double size;
  const Crest(this.team, {super.key, this.size = 34});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final t = team;
    final bytes = logoBytes(t);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: t == null ? p.line : (bytes != null ? Colors.white : Color(t.color)),
        border: Border.all(color: Colors.white.withValues(alpha: .8), width: size > 50 ? 3 : 2),
        boxShadow: [BoxShadow(color: p.line, spreadRadius: 1)],
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: bytes != null
          ? Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true)
          : Text(
              t == null ? '?' : initials(t.name),
              style: TextStyle(color: t == null ? p.muted : Colors.white, fontWeight: FontWeight.w800, fontSize: size * .38, height: 1),
            ),
    );
  }
}

class Panel extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final EdgeInsets padding;
  const Panel({super.key, this.title, required this.children, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.line)),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(title!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
          ],
          ..._spaced(children, 12),
        ],
      ),
    );
  }
}

List<Widget> _spaced(List<Widget> list, double gap) {
  final out = <Widget>[];
  for (var i = 0; i < list.length; i++) {
    if (i > 0) out.add(SizedBox(height: gap));
    out.add(list[i]);
  }
  return out;
}

class Hint extends StatelessWidget {
  final String text;
  final TextAlign align;
  const Hint(this.text, {super.key, this.align = TextAlign.start});
  @override
  Widget build(BuildContext context) =>
      Text(text, textAlign: align, style: TextStyle(color: Pal.of(context).muted, fontSize: 14, height: 1.35));
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2, left: 2, right: 2),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
          if (trailing != null) trailing!,
        ]),
      );
}

class NumStepper extends StatelessWidget {
  final String label;
  final String? hint;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const NumStepper({super.key, required this.label, this.hint, required this.value, required this.min, required this.max, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget btn(IconData icon, int delta, String sem) => Semantics(
          label: sem,
          button: true,
          child: InkWell(
            onTap: (value + delta < min || value + delta > max) ? null : () => onChanged(value + delta),
            child: SizedBox(width: 52, height: 50, child: Icon(icon, color: (value + delta < min || value + delta > max) ? p.line : p.board2, size: 26)),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      if (hint != null) Text(hint!, style: TextStyle(color: p.muted, fontSize: 13)),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line, width: 2)),
        child: Row(children: [
          btn(Icons.remove, -1, tr('less')),
          Expanded(child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]))),
          btn(Icons.add, 1, tr('more')),
        ]),
      ),
    ]);
  }
}

class SwitchRow extends StatelessWidget {
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  const SwitchRow({super.key, required this.label, this.hint, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              if (hint != null) Hint(hint!),
            ]),
          ),
          Switch(value: value, onChanged: onChanged),
        ]),
      );
}

/// Choix exclusif en pastilles (segments).
class Choice<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const Choice({super.key, required this.options, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: Semantics(
                selected: o.$1 == value,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => onChanged(o.$1),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    decoration: BoxDecoration(
                      color: o.$1 == value ? p.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: o.$1 == value ? [BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 2, offset: const Offset(0, 1))] : null,
                    ),
                    child: Text(o.$2,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: o.$1 == value ? p.ink : p.muted)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: p.cone, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(tr('live'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
      ]),
    );
  }
}

class Chip2 extends StatelessWidget {
  final String text;
  final Color? bg;
  final Color? fg;
  const Chip2(this.text, {super.key, this.bg, this.fg});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg ?? p.qual, borderRadius: BorderRadius.circular(99)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg ?? p.ink)),
    );
  }
}

class CardMark extends StatelessWidget {
  final bool red;
  final double h;
  const CardMark({super.key, this.red = false, this.h = 20});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(width: h * .72, height: h, decoration: BoxDecoration(color: red ? p.red : p.yellow, borderRadius: BorderRadius.circular(3)));
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.text, this.action});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      child: Column(children: [
        Icon(icon, size: 44, color: p.muted),
        const SizedBox(height: 10),
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 15)),
        if (action != null) ...[const SizedBox(height: 14), action!],
      ]),
    );
  }
}

class Banner2 extends StatelessWidget {
  final String text;
  final IconData? icon;
  const Banner2(this.text, {super.key, this.icon});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(p.cone.withValues(alpha: .12), p.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color.alphaBlend(p.cone.withValues(alpha: .4), p.line)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null) ...[Icon(icon, size: 20, color: p.cone), const SizedBox(width: 10)],
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.35))),
      ]),
    );
  }
}

/// Liste encadrée de lignes séparées par un trait.
class Boxed extends StatelessWidget {
  final List<Widget> children;
  const Boxed({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) out.add(Divider(height: 1, color: p.line));
      out.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out),
    );
  }
}

Future<bool> confirm(BuildContext context, {required String title, required String body, required String ok, bool danger = false}) async {
  final p = Pal.of(context);
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(danger ? Icons.warning_amber_rounded : Icons.help_outline, color: danger ? p.red : p.board2, size: 34),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(body),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: danger ? p.red : p.cone, minimumSize: const Size(64, 46)),
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

void snack(BuildContext context, String text, {String? actionLabel, VoidCallback? onAction, int seconds = 3}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(text),
    duration: Duration(seconds: seconds),
    action: actionLabel != null && onAction != null ? SnackBarAction(label: actionLabel, onPressed: onAction) : null,
  ));
}

/// Nom d'un joueur selon le réglage « Afficher les noms des joueurs ».
String playerLabel(Tournament t, String? playerId, {bool forPublic = false, bool withNum = true}) {
  final x = t.player(playerId);
  if (x == null) return tr('unknownPlayer');
  final num = x.player.num;
  if (forPublic && !t.settings.showNames) return num.isEmpty ? tr('playerOf', {'team': x.team.name}) : tr('numberShort', {'n': num});
  if (withNum && num.isNotEmpty) return '$num. ${x.player.name}';
  return x.player.name;
}

String roundTitle(Tournament t, Game g) {
  if (t.format == Fmt.single) return tr('theMatch');
  if (g.stage != 'ko') return tr('matchday', {'n': '${g.round}'});
  if (g.third) return tr('thirdPlace');
  String base;
  switch (g.roundSize) {
    case 2:
      base = tr('final');
      break;
    case 4:
      base = tr('semis');
      break;
    case 8:
      base = tr('quarters');
      break;
    case 16:
      base = tr('roundOf16');
      break;
    default:
      base = tr('roundOfN', {'n': '${g.roundSize}'});
  }
  if (g.leg == 1) return '$base, ${tr('leg1')}';
  if (g.leg == 2) return '$base, ${tr('leg2')}';
  return base;
}

String roundName(Tournament t, int roundSize) {
  switch (roundSize) {
    case 2:
      return tr('final');
    case 4:
      return tr('semis');
    case 8:
      return tr('quarters');
    case 16:
      return tr('roundOf16');
    default:
      return tr('roundOfN', {'n': '$roundSize'});
  }
}

String formatLabel(String f) => tr('fmt_$f');
