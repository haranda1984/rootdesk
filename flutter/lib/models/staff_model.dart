import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common/staff_notificaciones.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/staff_aviso_logic.dart';
import 'package:flutter_hbb/models/staff_logic.dart';
import 'package:flutter_hbb/models/support_logic.dart';
import 'package:flutter_hbb/models/support_model.dart';

import '../common.dart';

enum StaffVista { mios, sinAsignar, enCurso, equipo }

enum StaffStatus { idle, loading, ready, noLogin, noStaff, notConfigured, error }

/// Edición "Soporte": habla con el API del personal del portal (/api/staff) con la sesión del panel.
class StaffModel with ChangeNotifier {
  // Los avisos llegan en vivo por una conexión abierta; esta revisión completa es solo un respaldo.
  static const _respaldo = Duration(minutes: 5);
  static const _sinNoticias = Duration(seconds: 70); // el servidor manda un latido cada 25 s
  static const _seenKey = 'staff-seen';
  static const _vistaApi = {
    StaffVista.mios: 'mios',
    StaffVista.sinAsignar: 'sin_asignar',
    StaffVista.enCurso: 'en_curso',
  };

  StaffStatus status = StaffStatus.idle;
  String errorMessage = '';
  StaffYo? yo;
  StaffVista vista = StaffVista.mios;
  final Map<StaffVista, List<StaffCaso>> casos = {};
  List<EquipoFila> equipo = const [];
  Timer? _timer;
  Map<String, DateTime> _seen = {};
  bool _seenLoaded = false;
  bool _eventosActivos = false;
  HttpClient? _http;
  String? _ultimoEventoId;
  int _intentos = 0;
  final List<String> _vistos = [];

  /// Caso que la persona pidió abrir desde una notificación; la pantalla de Casos lo abre y lo borra.
  String? casoPendiente;

  /// Caso cuya conversación está abierta ahora, para no avisar de lo que ya está viendo.
  String? casoAbierto;

  /// Cambia cuando llega un mensaje nuevo de un caso ("<id del caso>|<id del aviso>"); la conversación abierta se refresca.
  final ValueNotifier<String> casoActualizado = ValueNotifier('');

  // ---- mensajes de clientes sin leer (se recuerdan entre sesiones) ----

  void _loadSeen() {
    if (_seenLoaded) return;
    _seenLoaded = true;
    try {
      final raw = bind.mainGetLocalOption(key: _seenKey);
      if (raw.isNotEmpty) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        _seen = m.map((k, v) => MapEntry(k, DateTime.parse(v as String)));
      }
    } catch (e) {
      debugPrint('staff: could not read seen messages: $e');
    }
  }

  bool sinLeer(StaffCaso c) {
    _loadSeen();
    return clienteEscribioSinLeer(c, _seen);
  }

  List<StaffCaso> get _mios => casos[StaffVista.mios] ?? const [];
  List<StaffCaso> get _sinAsignar => casos[StaffVista.sinAsignar] ?? const [];

  /// Casos que piden atención: con mensaje del cliente sin leer entre los míos, y los que nadie ha tomado.
  int get alertas {
    _loadSeen();
    return casosConMensajeNuevo(_mios, _seen) + _sinAsignar.length;
  }

  void markSeen(String id, DateTime? ultimoCliente) {
    _loadSeen();
    if (ultimoCliente == null) return;
    final cur = _seen[id];
    if (cur != null && !ultimoCliente.isAfter(cur)) return;
    _seen[id] = ultimoCliente;
    bind.mainSetLocalOption(
        key: _seenKey, value: jsonEncode(_seen.map((k, v) => MapEntry(k, v.toUtc().toIso8601String()))));
    StaffNotificaciones.actualizarInsignia(alertas);
    notifyListeners();
  }

  // ---- red ----

  Future<dynamic> _get(String path) async => supportModel.apiJson(await supportModel.apiCall('GET', path));

  Future<void> start() async {
    _timer ??= Timer.periodic(_respaldo, (_) {
      if (supportModel.loggedIn) load(quiet: true);
    });
    _iniciarEventos();
    if (status == StaffStatus.idle) await load();
  }

  void pedirAbrirCaso(String id) {
    casoPendiente = id;
    notifyListeners();
  }

  // ---- avisos en vivo ----

  void _iniciarEventos() {
    if (_eventosActivos) return;
    _eventosActivos = true;
    _bucleEventos();
  }

  /// Mantiene abierta la conexión de avisos del portal; si se corta, espera y reconecta, y al volver recupera lo perdido.
  Future<void> _bucleEventos() async {
    while (_eventosActivos) {
      var esperar = true;
      try {
        if (!supportModel.loggedIn) {
          await Future.delayed(const Duration(seconds: 10));
          continue;
        }
        final base = await supportModel.portalUrl();
        if (base == null) {
          await Future.delayed(const Duration(seconds: 60));
          continue;
        }
        final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 15);
        _http = cliente;
        final req = await cliente.getUrl(Uri.parse(joinUrl(base, '/api/staff/eventos')));
        req.headers.set('Authorization', 'Bearer ${supportModel.token}');
        req.headers.set('Accept', 'text/event-stream');
        req.headers.set('Cache-Control', 'no-cache');
        if (_ultimoEventoId != null) req.headers.set('Last-Event-ID', _ultimoEventoId!);
        final resp = await req.close();
        if (resp.statusCode == 401 || resp.statusCode == 403) {
          await resp.drain<void>();
          await Future.delayed(const Duration(seconds: 60));
          continue;
        }
        if (resp.statusCode != 200) {
          await resp.drain<void>();
          throw HttpException('avisos: HTTP ${resp.statusCode}');
        }
        _intentos = 0;
        esperar = false;
        final parser = SseParser();
        // Al (re)conectar, una consulta completa deja la lista al día con lo que pasó mientras no había conexión.
        load(quiet: true);
        await for (final trozo in resp.transform(utf8.decoder).timeout(_sinNoticias)) {
          for (final e in parser.add(trozo)) {
            if (e.id != null) _ultimoEventoId = e.id;
            final aviso = avisoDeEvento(e);
            if (aviso != null) await _alAviso(aviso);
          }
        }
      } catch (e) {
        debugPrint('staff: conexión de avisos: $e');
      } finally {
        _http?.close(force: true);
        _http = null;
      }
      if (!_eventosActivos) break;
      _intentos++;
      await Future.delayed(esperar ? esperaReconexion(_intentos) : const Duration(seconds: 2));
    }
  }

  Future<void> _alAviso(StaffAviso a) async {
    if (a.id.isNotEmpty) {
      if (_vistos.contains(a.id)) return;
      _vistos.add(a.id);
      if (_vistos.length > 60) _vistos.removeAt(0);
    }
    await load(quiet: true);
    if (a.tipo == TipoAviso.mensajeCliente) casoActualizado.value = '${a.ticketId}|${a.id}';
    // Si ya está leyendo esa conversación, el mensaje aparece ahí y no hace falta avisar.
    if (a.tipo == TipoAviso.mensajeCliente && casoAbierto == a.ticketId && await StaffNotificaciones.ventanaALaVista()) return;
    final t = textoAviso(a, translate);
    if (await StaffNotificaciones.ventanaALaVista()) {
      BotToast.showText(text: '${t.titulo}\n${t.cuerpo}', duration: const Duration(seconds: 6));
      return;
    }
    await StaffNotificaciones.mostrar(
      titulo: t.titulo,
      cuerpo: t.cuerpo,
      alHacerClic: () {
        gFFI.peerTabModel.setCurrentTab(kSupportTabIndex);
        pedirAbrirCaso(a.ticketId);
      },
    );
  }

  void setVista(StaffVista v) {
    vista = v;
    notifyListeners();
    load(quiet: true);
  }

  /// Carga lo que el personal ve: quién es, sus casos, los sin asignar y, si supervisa, la vista activa.
  Future<void> load({bool quiet = false}) async {
    if (!supportModel.loggedIn) {
      status = StaffStatus.noLogin;
      notifyListeners();
      return;
    }
    if (!quiet) {
      status = StaffStatus.loading;
      notifyListeners();
    }
    try {
      yo ??= StaffYo.fromJson(await _get('/api/staff/yo') as Map<String, dynamic>);
      await _cargarCasos(StaffVista.mios);
      await _cargarCasos(StaffVista.sinAsignar);
      if (yo!.supervisa && vista == StaffVista.enCurso) await _cargarCasos(StaffVista.enCurso);
      if (yo!.supervisa && vista == StaffVista.equipo) await cargarEquipo();
      status = StaffStatus.ready;
      StaffNotificaciones.actualizarInsignia(alertas);
    } on SupportException catch (e) {
      if (e.status == 403) {
        status = StaffStatus.noStaff;
      } else if (e.code == 'sin_portal') {
        status = StaffStatus.notConfigured;
      } else if (!quiet || status != StaffStatus.ready) {
        status = StaffStatus.error;
        errorMessage = e.unauthorized ? 'session_expired' : (e.code.isEmpty ? 'unknown_error' : e.code);
      }
    } catch (e) {
      debugPrint('staff load failed: $e');
      if (!quiet || status != StaffStatus.ready) {
        status = StaffStatus.error;
        errorMessage = 'network_error';
      }
    }
    notifyListeners();
  }

  Future<void> _cargarCasos(StaffVista v) async {
    final list = await _get('/api/staff/casos?vista=${_vistaApi[v]}') as List;
    casos[v] = list.map((e) => StaffCaso.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> cargarEquipo() async {
    final list = await _get('/api/staff/equipo') as List;
    equipo = list.map((e) => EquipoFila.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<StaffDetalle> detalle(String id) async {
    final d = StaffDetalle.fromJson(await _get('/api/staff/casos/$id') as Map<String, dynamic>);
    markSeen(id, d.ultimoClienteEn);
    return d;
  }

  Future<void> comentar(String id, String texto, {required bool interno}) async {
    supportModel.apiJson(
        await supportModel.apiCall('POST', '/api/staff/casos/$id/comentarios',
            body: {'mensaje': texto, 'visible_cliente': !interno}),
        ok: 201);
    await load(quiet: true);
  }

  /// ID y contraseña de la ventana de soporte para entrar directo al equipo.
  Future<({String id, String password})> conectar(String id) async {
    final j = supportModel.apiJson(await supportModel.apiCall('POST', '/api/staff/casos/$id/conectar')) as Map<String, dynamic>;
    return (id: j['rustdesk_id'] as String, password: j['password'] as String);
  }

  Future<List<StaffPersona>> personal() async {
    final list = await _get('/api/staff/personal') as List;
    return list.map((e) => StaffPersona.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<String> invitar(String id, String usuarioId) async {
    final j = supportModel.apiJson(await supportModel.apiCall('POST', '/api/staff/casos/$id/invitar', body: {'usuario_id': usuarioId})) as Map<String, dynamic>;
    await load(quiet: true);
    return (j['mensaje'] ?? '') as String;
  }

  Future<String> transferir(String id, String usuarioId, String nota) async {
    final j = supportModel.apiJson(await supportModel.apiCall('POST', '/api/staff/casos/$id/transferir', body: {'usuario_id': usuarioId, 'nota': nota})) as Map<String, dynamic>;
    await load(quiet: true);
    return (j['mensaje'] ?? '') as String;
  }
}

final StaffModel staffModel = StaffModel();
