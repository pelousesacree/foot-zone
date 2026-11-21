// Foot Zone — images à partager (résultat, classement, programme, tirage, buteurs).
// Dessinées directement sur un canevas : carré pour les messages, vertical 9:16 pour les statuts.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../engine/engine.dart';
import '../engine/models.dart';
import '../l10n/strings.dart';
import 'widgets.dart';

typedef ImageMaker = Future<Uint8List> Function(bool vertical);

Future<void> shareImage(BuildContext context, ImageMaker make, String name) async {
  final vertical = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(tr('shareFormat'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ),
        ListTile(leading: const Icon(Icons.crop_square, size: 32), title: Text(tr('formatSquare')), subtitle: Text(tr('formatSquareHint')), onTap: () => Navigator.pop(c, false)),
        ListTile(leading: const Icon(Icons.crop_portrait, size: 32), title: Text(tr('formatVertical')), subtitle: Text(tr('formatVerticalHint')), onTap: () => Navigator.pop(c, true)),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (vertical == null) return;
  try {
    final bytes = await make(vertical);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/footzone-$name-${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'image/png')], text: tr('shareText')));
  } catch (_) {
    if (context.mounted) snack(context, tr('shareFailed'));
  }
}

class _Board {
  static const blue = Color(0xFF1B3B8F);
  static const cone = Color(0xFFEC6417);
  static const yellow = Color(0xFFF4C21B);
  final double w = 1080;
  final double h;
  final ui.PictureRecorder rec = ui.PictureRecorder();
  late final Canvas c;
  final Map<String, ui.Image?> logos;

  _Board(bool vertical, this.logos) : h = vertical ? 1920 : 1080 {
    c = Canvas(rec, Rect.fromLTWH(0, 0, w, h));
    c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = blue);
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    c.drawRect(Rect.fromLTWH(40, 40, w - 80, h - 160), line);
    c.drawLine(Offset(40, (h - 120) / 2 + 20), Offset(w - 40, (h - 120) / 2 + 20), line);
    c.drawCircle(Offset(w / 2, (h - 120) / 2 + 20), 130, line);
    c.drawRect(Rect.fromLTWH(0, h - 110, w, 110), Paint()..color = cone);
    text('FOOT ZONE', 0, h - 92, w, size: 50, weight: FontWeight.w900, align: TextAlign.center);
  }

  static Future<_Board> create(Tournament t, bool vertical, Iterable<String?> teamIds) async {
    final logos = <String, ui.Image?>{};
    for (final id in teamIds) {
      if (id == null || logos.containsKey(id)) continue;
      final bytes = logoBytes(t.team(id));
      if (bytes == null) {
        logos[id] = null;
        continue;
      }
      try {
        final codec = await ui.instantiateImageCodec(bytes, targetWidth: 256);
        final frame = await codec.getNextFrame();
        logos[id] = frame.image;
      } catch (_) {
        logos[id] = null;
      }
    }
    return _Board(vertical, logos);
  }

  double text(String s, double x, double y, double maxW,
      {double size = 34, FontWeight weight = FontWeight.w600, Color color = Colors.white, TextAlign align = TextAlign.left, int maxLines = 1}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, fontWeight: weight, color: color, height: 1.15)),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(minWidth: maxW, maxWidth: maxW);
    tp.paint(c, Offset(x, y));
    return tp.height;
  }

  void header(String title, String sub) {
    text(title, 80, 100, w - 160, size: 64, weight: FontWeight.w900, align: TextAlign.center, maxLines: 2);
    text(sub, 80, 190, w - 160, size: 34, color: Colors.white.withValues(alpha: .82), align: TextAlign.center);
  }

  void crest(Tournament t, String? id, double cx, double cy, double r) {
    final team = t.team(id);
    final img = id == null ? null : logos[id];
    final circle = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    if (img != null) {
      c.save();
      c.clipPath(Path()..addOval(circle));
      c.drawRect(circle, Paint()..color = Colors.white);
      paintImage(canvas: c, rect: circle, image: img, fit: BoxFit.cover);
      c.restore();
    } else {
      c.drawCircle(Offset(cx, cy), r, Paint()..color = team == null ? Colors.grey : Color(team.color));
      final tp = TextPainter(
        text: TextSpan(text: team == null ? '?' : initials(team.name), style: TextStyle(fontSize: r * .8, fontWeight: FontWeight.w800, color: Colors.white)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset(cx - tp.width / 2, cy - tp.height / 2));
    }
    c.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = Colors.white.withValues(alpha: .85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r > 40 ? 6 : 3);
  }

  Future<Uint8List> png() async {
    final pic = rec.endRecording();
    final img = await pic.toImage(w.toInt(), h.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }
}

class ShareImages {
  static String _sub(Tournament t, List<String> parts) => [t.place, ...parts].where((x) => x.trim().isNotEmpty).join(', ');

  static Future<Uint8List> result(Tournament t, Game g, bool vertical) async {
    final b = await _Board.create(t, vertical, [g.home, g.away]);
    final s = t.settings;
    final sc = FZ.score(g, s);
    b.header(t.name, _sub(t, [if (g.group != null) tr('groupN', {'g': g.group!}), roundTitle(t, g), if (g.when.isNotEmpty) g.when]));
    final top = vertical ? 420.0 : 300.0;
    final r = vertical ? 130.0 : 105.0;
    b.crest(t, g.home, 250, top + r, r);
    b.crest(t, g.away, b.w - 250, top + r, r);
    b.text(teamName(t, g.home), 50, top + 2 * r + 24, 400, size: 40, weight: FontWeight.w800, align: TextAlign.center, maxLines: 2);
    b.text(teamName(t, g.away), b.w - 450, top + 2 * r + 24, 400, size: 40, weight: FontWeight.w800, align: TextAlign.center, maxLines: 2);
    b.text('${sc.h}-${sc.a}', 0, top + r - 110, b.w, size: 170, weight: FontWeight.w900, align: TextAlign.center);
    String note;
    if (g.status == Status.live) {
      final ck = FZ.clock(g, s);
      note = '${tr('live')} ${ck.label ?? tr('phase_${ck.state}')}';
    } else if (g.forfeit != null) {
      note = tr('forfeitWin');
    } else if (g.hasPens && g.pensH != g.pensA) {
      note = tr('pensLine', {'h': '${g.pensH}', 'a': '${g.pensA}'});
    } else {
      note = tr('fullTime');
    }
    b.text(note, 0, top + r + 80, b.w, size: 32, color: g.status == Status.live ? _Board.yellow : Colors.white.withValues(alpha: .85), align: TextAlign.center, weight: FontWeight.w700);
    final agg = FZ.aggregate(t, g);
    if (agg != null) b.text(tr('aggregate', {'h': '${agg.h}', 'a': '${agg.a}'}), 0, top + r + 124, b.w, size: 30, align: TextAlign.center);
    List<String> scorers(String? side) {
      final list = g.events.where((e) => !e.cancelled && e.isGoal && e.teamId == side && (e.playerId != null || e.minute != null)).toList()
        ..sort((a, c) => (a.minute ?? 0).compareTo(c.minute ?? 0));
      return list.map((e) {
        final who = e.playerId == null ? tr('evGoal') : playerLabel(t, e.playerId, forPublic: true, withNum: false);
        final kind = e.type == 'pen' ? ' ${tr('penShortTag')}' : (e.type == 'og' ? ' ${tr('ogShortTag')}' : '');
        final min = e.minute == null ? '' : " ${e.minute}${e.extra != null ? '+${e.extra}' : ''}'";
        return '$who$kind$min';
      }).toList();
    }

    var y = top + 2 * r + 130;
    final maxLines = vertical ? 12 : 5;
    final homeLines = scorers(g.home), awayLines = scorers(g.away);
    for (var i = 0; i < maxLines && i < homeLines.length; i++) {
      b.text(homeLines[i], 50, y + i * 46, 440, size: 32, align: TextAlign.center);
    }
    for (var i = 0; i < maxLines && i < awayLines.length; i++) {
      b.text(awayLines[i], b.w - 490, y + i * 46, 440, size: 32, align: TextAlign.center);
    }
    y = b.h - 200;
    if (g.motm != null && t.player(g.motm) != null) {
      b.text('${tr('motm')} : ${playerLabel(t, g.motm, forPublic: true, withNum: false)}', 80, y, b.w - 160, size: 36, color: _Board.yellow, align: TextAlign.center, weight: FontWeight.w800);
    }
    return b.png();
  }

  static Future<Uint8List> standings(Tournament t, bool vertical) async {
    final s = t.settings;
    final blocks = t.format == Fmt.league
        ? [('', t.teams.map((x) => x.id).toList(), t.games, 0)]
        : t.groups.map((g) => (tr('groupN', {'g': g.name}), g.teamIds, t.games.where((m) => m.group == g.name).toList(), s.qualifiers)).toList();
    final b = await _Board.create(t, vertical, t.teams.map((x) => x.id));
    b.header(t.name, _sub(t, [tr('standingsTitle')]));
    final totalRows = blocks.fold<double>(0, (a, x) => a + x.$2.length + 1 + (x.$1.isEmpty ? 0.0 : 1.2) + .5);
    final avail = b.h - 290 - 170;
    final rowH = (avail / totalRows).clamp(26.0, 72.0);
    var y = 280.0;
    const left = 80.0, right = 1000.0;
    for (final blk in blocks) {
      final rows = FZ.standings(blk.$2, blk.$3, s, t.lots);
      if (blk.$1.isNotEmpty) {
        b.text(blk.$1, left, y, 600, size: rowH * .75, weight: FontWeight.w900, color: _Board.cone);
        y += rowH * 1.2;
      }
      final cols = [(tr('colJ'), right - 330), (tr('colW'), right - 270), (tr('colD'), right - 210), (tr('colL'), right - 150), (tr('colGD'), right - 80), (tr('colPts'), right)];
      for (final col in cols) {
        b.text(col.$1, col.$2 - 70, y + rowH * .2, 70, size: rowH * .4, color: Colors.white.withValues(alpha: .7), align: TextAlign.right);
      }
      y += rowH;
      for (final r in rows) {
        if (blk.$4 > 0 && r.rank <= blk.$4) {
          b.c.drawRect(Rect.fromLTWH(left - 20, y + 3, right - left + 40, rowH - 6), Paint()..color = Colors.white.withValues(alpha: .12));
        }
        final ty = y + (rowH - rowH * .5 * 1.15) / 2;
        b.text('${r.rank}', left, ty, 50, size: rowH * .5, weight: FontWeight.w800);
        b.crest(t, r.team, left + 80, y + rowH / 2, rowH * .36);
        b.text(teamName(t, r.team), left + 115, ty, right - 360 - (left + 115), size: rowH * .48);
        final vals = ['${r.j}', '${r.g}', '${r.n}', '${r.p}', '${r.diff > 0 ? '+' : ''}${r.diff}'];
        for (var i = 0; i < vals.length; i++) {
          b.text(vals[i], cols[i].$2 - 70, ty, 70, size: rowH * .48, align: TextAlign.right);
        }
        b.text('${r.pts}', right - 70, y + (rowH - rowH * .6 * 1.15) / 2, 70, size: rowH * .6, weight: FontWeight.w900, align: TextAlign.right);
        y += rowH;
      }
      y += rowH * .5;
    }
    return b.png();
  }

  static Future<Uint8List> round(Tournament t, List<Game> games, String title, bool vertical) async {
    final list = games.where((g) => !g.bye).toList();
    final b = await _Board.create(t, vertical, list.expand((g) => [g.home, g.away]));
    b.header(t.name, _sub(t, [title]));
    final avail = b.h - 290 - 170;
    final rowH = (avail / (list.isEmpty ? 1 : list.length)).clamp(60.0, 150.0);
    var y = 290.0;
    for (final g in list) {
      final mid = y + rowH / 2;
      final size = (rowH * .3).clamp(24.0, 40.0);
      b.crest(t, g.home, 110, mid, rowH * .28);
      b.text(g.home == null ? tr('tbd') : teamName(t, g.home), 160, mid - size * .6, 300, size: size, weight: FontWeight.w700);
      b.crest(t, g.away, b.w - 110, mid, rowH * .28);
      b.text(g.away == null ? tr('tbd') : teamName(t, g.away), b.w - 460, mid - size * .6, 300, size: size, weight: FontWeight.w700, align: TextAlign.right);
      String center;
      if (!g.ready || g.status == Status.scheduled) {
        center = g.when.isEmpty ? tr('vs') : g.when;
        b.text(center, 470, mid - size * .55, 140, size: size * .8, align: TextAlign.center, maxLines: 2, color: Colors.white.withValues(alpha: .85));
      } else {
        final sc = FZ.score(g, t.settings);
        b.text('${sc.h}-${sc.a}', 460, mid - size * .8, 160, size: size * 1.4, weight: FontWeight.w900, align: TextAlign.center, color: g.status == Status.live ? _Board.yellow : Colors.white);
      }
      y += rowH;
    }
    return b.png();
  }

  static Future<Uint8List> draw(Tournament t, bool vertical) async {
    final b = await _Board.create(t, vertical, t.teams.map((x) => x.id));
    b.header(t.name, _sub(t, [tr('drawImageTitle')]));
    if (t.format == Fmt.groups) {
      final cols = t.groups.length <= 2 || !vertical ? (t.groups.length <= 4 ? 2 : 3) : 2;
      final colW = (b.w - 160) / cols;
      final rowsOfGroups = (t.groups.length / cols).ceil();
      final maxTeams = t.groups.fold<int>(0, (m, g) => g.teamIds.length > m ? g.teamIds.length : m);
      final blockH = (b.h - 290 - 170) / rowsOfGroups;
      final lineH = (blockH / (maxTeams + 1.6)).clamp(30.0, 80.0);
      for (var i = 0; i < t.groups.length; i++) {
        final g = t.groups[i];
        final x = 80 + (i % cols) * colW;
        var y = 290 + (i ~/ cols) * blockH;
        b.text(tr('groupN', {'g': g.name}), x, y, colW - 20, size: lineH * .7, weight: FontWeight.w900, color: _Board.cone);
        y += lineH * 1.1;
        for (final id in g.teamIds) {
          b.crest(t, id, x + lineH * .4, y + lineH / 2, lineH * .34);
          b.text(teamName(t, id), x + lineH * .95, y + lineH * .2, colW - lineH - 30, size: lineH * .48, weight: FontWeight.w700);
          y += lineH;
        }
      }
    } else {
      final first = t.games.where((g) => g.stage == 'ko' && g.kround == 1 && g.leg != 2).toList()..sort((a, c) => a.pos.compareTo(c.pos));
      final avail = b.h - 290 - 170;
      final rowH = (avail / (first.isEmpty ? 1 : first.length)).clamp(50.0, 140.0);
      var y = 290.0;
      for (final g in first) {
        final mid = y + rowH / 2;
        final size = (rowH * .3).clamp(22.0, 38.0);
        b.crest(t, g.home, 110, mid, rowH * .26);
        b.text(g.home == null ? tr('exempt') : teamName(t, g.home), 160, mid - size * .6, 320, size: size, weight: FontWeight.w700);
        if (g.bye) {
          b.text(tr('qualifiedBye'), b.w - 480, mid - size * .6, 400, size: size * .85, align: TextAlign.right, color: Colors.white.withValues(alpha: .8));
        } else {
          b.crest(t, g.away, b.w - 110, mid, rowH * .26);
          b.text(teamName(t, g.away), b.w - 480, mid - size * .6, 320, size: size, weight: FontWeight.w700, align: TextAlign.right);
          b.text(tr('vs'), 480, mid - size * .55, 120, size: size * .8, align: TextAlign.center, color: Colors.white.withValues(alpha: .8));
        }
        y += rowH;
      }
    }
    return b.png();
  }

  static Future<Uint8List> scorers(Tournament t, bool vertical) async {
    final list = FZ.scorers(FZ.playerStats(t)).take(vertical ? 15 : 10).toList();
    final b = await _Board.create(t, vertical, list.map((x) => x.s.teamId));
    b.header(t.name, _sub(t, [tr('topScorers')]));
    final avail = b.h - 290 - 170;
    final rowH = (avail / (list.isEmpty ? 1 : list.length)).clamp(56.0, 100.0);
    var y = 290.0;
    for (final x in list) {
      final size = rowH * .42;
      final ty = y + (rowH - size * 1.15) / 2;
      b.text('${x.rank}', 80, ty, 60, size: size, weight: FontWeight.w900, color: x.rank == 1 ? _Board.yellow : Colors.white);
      b.crest(t, x.s.teamId, 175, y + rowH / 2, rowH * .32);
      b.text(playerLabel(t, x.s.id, forPublic: true, withNum: false), 225, ty - size * .3, 560, size: size, weight: FontWeight.w800);
      b.text(teamName(t, x.s.teamId), 225, ty + size * .85, 560, size: size * .62, color: Colors.white.withValues(alpha: .75));
      b.text('${x.s.goals}', 860, y + (rowH - size * 1.5 * 1.15) / 2, 140, size: size * 1.5, weight: FontWeight.w900, align: TextAlign.right, color: x.rank == 1 ? _Board.yellow : Colors.white);
      y += rowH;
    }
    return b.png();
  }
}
