import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/core/utils/spawn_directory.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// [TerminalGateway] inerte — não sobe PTY nenhum; só satisfaz o construtor da
/// [TerminalSession] pra testar a máquina de status de turno isoladamente.
class _NoopGateway implements TerminalGateway {
  // `implements` não herda o corpo default do contrato: precisa declarar.
  @override
  SpawnDirectory? get spawnDirectory => null;

  @override
  int? get rootProcessId => null;

  final _out = StreamController<List<int>>();

  @override
  Stream<List<int>> get output => _out.stream;
  @override
  void start({
    required String workingDirectory,
    required TerminalProfile profile,
    int rows = 25,
    int columns = 80,
    Map<String, String> extraEnv = const <String, String>{},
  }) {}
  @override
  void write(List<int> data) {}
  @override
  void resize(int rows, int columns) {}
  @override
  void acknowledgeOutput() {}
  @override
  Future<void> kill() async {
    await _out.close();
  }
}

TerminalSession _session() => TerminalSession(
  id: 't1',
  projectId: 'p1',
  workingDirectory: '/tmp',
  gateway: _NoopGateway(),
  profile: const TerminalProfile(
    id: 'login-shell',
    label: 'sh (login)',
    executable: '/bin/sh',
    args: ['-l'],
  ),
);

void main() {
  group('TerminalSession — status de turno (spinner)', () {
    test('working → idle: spinner liga e desliga', () async {
      final s = _session();
      expect(s.isWorking, isFalse);

      s.applyClaudeStatus(
        status: TerminalStatus.working,
        isTurnStart: true,
      ); // UserPromptSubmit
      expect(s.isWorking, isTrue);

      s.applyClaudeStatus(status: TerminalStatus.idle); // Stop
      expect(s.isWorking, isFalse);
      await s.dispose();
    });

    test(
      'FIX: working mid-turn reordenado que chega DEPOIS do idle é descartado',
      () async {
        final s = _session();
        s.applyClaudeStatus(status: TerminalStatus.working, isTurnStart: true);
        s.applyClaudeStatus(status: TerminalStatus.idle); // Stop → idle
        expect(s.isWorking, isFalse);

        // PostToolUse('working') do MESMO turno, entregue fora de ordem depois do
        // Stop (processos/sockets separados). Sem o guard, o spinner voltaria e
        // ficaria girando pra sempre.
        s.applyClaudeStatus(status: TerminalStatus.working, isTurnStart: false);
        expect(
          s.isWorking,
          isFalse,
          reason: 'working mid-turn órfão pós-idle deve ser ignorado',
        );
        await s.dispose();
      },
    );

    test(
      'follow-up enfileirado (UserPromptSubmit) logo após idle LIGA o spinner',
      () async {
        final s = _session();
        s.applyClaudeStatus(status: TerminalStatus.working, isTurnStart: true);
        s.applyClaudeStatus(status: TerminalStatus.idle);
        expect(s.isWorking, isFalse);

        // Turno novo (não é reordenação): isTurnStart pula o guard.
        s.applyClaudeStatus(status: TerminalStatus.working, isTurnStart: true);
        expect(s.isWorking, isTrue);
        await s.dispose();
      },
    );

    test('working mid-turn DENTRO de um turno ativo é aceito', () async {
      final s = _session();
      s.applyClaudeStatus(status: TerminalStatus.working, isTurnStart: true);
      // PreToolUse volta a idle? não — segue working. Simula waiting→working:
      s.applyClaudeStatus(status: TerminalStatus.waiting); // Notification
      expect(s.isWorking, isFalse);
      // Aprovou → PreToolUse('working') com turno ainda ativo → volta a working.
      s.applyClaudeStatus(status: TerminalStatus.working, isTurnStart: false);
      expect(s.isWorking, isTrue);
      await s.dispose();
    });
  });

  group('TerminalSession — interrupt do usuário (ESC) limpa o spinner', () {
    // O construtor liga `terminal.onOutput` ao detector de interrupt; alimentar
    // esse callback simula o usuário digitando, sem precisar de uma view.
    void typeRaw(TerminalSession s, String data) =>
        s.terminal.onOutput!(Uint8List.fromList(utf8.encode(data)));

    test('ESC cru (\\x1b) enquanto working volta a idle', () async {
      final s = _session();
      s.applyClaudeStatus(status: TerminalStatus.working, isTurnStart: true);
      expect(s.isWorking, isTrue);
      typeRaw(s, '\x1b');
      expect(s.isWorking, isFalse, reason: 'ESC deve abortar o turno otimista');
      await s.dispose();
    });

    test('ESC do kitty keyboard protocol (\\x1b[27u) também aborta', () async {
      // Encoding do Ghostty/libghostty quando o app ativa o protocolo kitty —
      // era exatamente o caso que o match só-`\\x1b` perdia (spinner eterno).
      final s = _session();
      s.applyClaudeStatus(status: TerminalStatus.working, isTurnStart: true);
      typeRaw(s, '\x1b[27u');
      expect(s.isWorking, isFalse);
      await s.dispose();
    });

    test('ESC kitty com modificador/tipo-de-evento (\\x1b[27;1:3u) aborta', () async {
      final s = _session();
      s.applyClaudeStatus(status: TerminalStatus.working, isTurnStart: true);
      typeRaw(s, '\x1b[27;1:3u');
      expect(s.isWorking, isFalse);
      await s.dispose();
    });

    test('controle negativo: ESC sem turno (idle) não força transição', () async {
      final s = _session();
      expect(s.isWorking, isFalse);
      typeRaw(s, '\x1b');
      expect(s.isWorking, isFalse);
      await s.dispose();
    });

    test('controle negativo: seta pra cima (\\x1b[A) enquanto working NÃO aborta', () async {
      // Discrimina a regex: uma CSI de seta não é ESC e não pode abortar o turno.
      final s = _session();
      s.applyClaudeStatus(status: TerminalStatus.working, isTurnStart: true);
      typeRaw(s, '\x1b[A');
      expect(
        s.isWorking,
        isTrue,
        reason: 'só o ESC aborta, não sequências CSI de setas/função',
      );
      await s.dispose();
    });
  });
}
