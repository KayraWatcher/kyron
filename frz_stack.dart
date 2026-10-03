// GECICI - donma teshisi araci. Olcumden sonra SILINECEK.
// Kullanim: dart frz_stack.dart <port> <authCode> [stack|cpu]
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('kullanim: dart frz_stack.dart <port> <authCode> [stack|cpu]');
    exitCode = 2;
    return;
  }
  final port = args[0];
  final auth = args[1];
  final mode = args.length > 2 ? args[2] : 'stack';
  final ws = await WebSocket.connect('ws://127.0.0.1:$port/$auth/ws')
      .timeout(const Duration(seconds: 6));

  var id = 0;
  final pending = <int, Completer<Map<String, dynamic>>>{};
  ws.listen((data) {
    final m = jsonDecode(data as String) as Map<String, dynamic>;
    final rid = m['id'];
    if (rid is int && pending.containsKey(rid)) {
      pending.remove(rid)!.complete(m);
    }
  });

  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    final rid = ++id;
    final c = Completer<Map<String, dynamic>>();
    pending[rid] = c;
    ws.add(jsonEncode({
      'jsonrpc': '2.0',
      'id': rid,
      'method': method,
      'params': params ?? <String, dynamic>{},
    }));
    final r = await c.future.timeout(const Duration(seconds: 10));
    pending.remove(rid);
    return r;
  }

  try {
    final vm = await rpc('getVM');
    final isolates = ((vm['result']?['isolates']) as List?) ?? const [];
    print('isolate sayisi: ${isolates.length}');

    if (mode == 'cpu') {
      // Calisan isolate icin CPU ornegi al: hangi method donuyor?
      final now = DateTime.now().microsecondsSinceEpoch;
      await rpc('clearCpuSamples', {'isolateId': isolates.first['id']});
      await Future<void>.delayed(const Duration(seconds: 2));
      final end = DateTime.now().microsecondsSinceEpoch;
      final res = await rpc('getCpuSamples', {
        'isolateId': isolates.first['id'],
        'timeOriginMicros': now,
        'timeExtentMicros': end - now,
      });
      final r = res['result'];
      if (r == null) {
        print('getCpuSamples hatasi: $res');
      } else {
        print('sample sayisi: ${r['sampleCount']} '
            'isolateWait: ${r['isolateWaitMicros']} '
            'isolateExec: ${r['isolateExecutionMicros']}');
        final samples = (r['samples'] as List?) ?? const [];
        final funcs = <String, int>{};
        for (final s in samples) {
          final stack = (s['stack'] as List?) ?? const [];
          if (stack.isEmpty) continue;
          final top = stack.first as Map<String, dynamic>?;
          final nm = top?['name'] ?? '?';
          funcs[nm] = (funcs[nm] ?? 0) + 1;
        }
        final sorted = funcs.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        print('en cok orneklenen tepe fonksiyonlari:');
        for (final e in sorted.take(15)) {
          print('  ${e.value}\t${e.key}');
        }
        // en zengin stack'leri de goster
        var shown = 0;
        for (final s in samples) {
          final stack = (s['stack'] as List?) ?? const [];
          if (stack.length < 3) continue;
          print('--- stack (${stack.length} frame):');
          for (final f in stack.take(18)) {
            print('    ${f['name']}');
          }
          shown++;
          if (shown >= 6) break;
        }
      }
      return;
    }

    for (final iso in isolates) {
      final isoId = iso['id'] as String;
      final name = iso['name'] ?? '';
      final isoInfo = await rpc('getIsolate', {'isolateId': isoId});
      final pauseEvent = isoInfo['result']?['pauseEvent']?['kind'];
      print('--- isolate: $name ($isoId) pause=$pauseEvent');
      try {
        final st = await rpc('getStack', {'isolateId': isoId});
        final res = st['result'] as Map<String, dynamic>?;
        if (res == null) {
          print('  getStack sonucu yok: $st');
        } else {
          final frames = (res['frames'] as List?) ?? const [];
          final asyncCbs = (res['asyncCausalFrames'] as List?) ?? const [];
          print('  frames: ${frames.length}  async: ${asyncCbs.length}');
          for (final f in frames.take(30)) {
            print('    ${f['function']?['name']}  @ '
                '${f['location']?['script']?['uri']}:${f['location']?['line']}');
          }
          for (final f in asyncCbs.take(15)) {
            print('    [async] ${f['function']?['name']}');
          }
        }
      } catch (e) {
        print('  getStack hatasi: $e');
      }
      try {
        final mu = await rpc('getMemoryUsage', {'isolateId': isoId});
        final r = mu['result'];
        print('  mem heap=${r?['heapUsage']} external=${r?['externalUsage']}');
      } catch (_) {}
    }
  } finally {
    await ws.close();
  }
}
