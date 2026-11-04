import 'dart:async';
import 'dart:io';

import 'package:helpdesk_backend/helpdesk_backend.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final config = AppConfig.fromMap(loadSettings());
  final clock = Clock();
  final log = Log(filePath: config.logFile, now: clock.now);
  final store = config.dataFile == null ? JsonStore.memory() : await JsonStore.open(config.dataFile!);

  final ctx = buildApp(
    config: config,
    store: store,
    clock: clock,
    log: log,
    gateway: HttpNotificationGateway(baseUrl: config.gatewayUrl, apiKey: config.gatewayApiKey, timeout: config.gatewayTimeout),
  );

  final recovered = await ctx.outbox.recoverInFlight();
  log.info('app.starting', {...config.describe(), 'recoveredInFlight': recovered});

  startAutomation(ctx);
  final server = await io.serve(buildHandler(ctx), config.host, config.port);
  log.info('app.listening', {'url': 'http://${server.address.host}:${server.port}'});

  late StreamSubscription<ProcessSignal> sub;
  sub = ProcessSignal.sigint.watch().listen((_) async {
    log.info('app.stopping', {});
    ctx.scheduler.stop();
    await server.close();
    await log.close();
    await sub.cancel();
    exit(0);
  });
}
