import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/support_logic.dart';
import 'package:http/http.dart' as http;

import '../common.dart';

enum SupportStatus { idle, loading, ready, noLogin, notConfigured, error }

/// Sección Soporte: habla con el portal de tickets usando la sesión del panel (el token que la
/// aplicación ya guarda al iniciar sesión). La dirección del portal la anuncia el propio panel.
class SupportModel with ChangeNotifier {
  static const _pollInterval = Duration(seconds: 60);
  static const _timeout = Duration(seconds: 15);
  static const _seenKey = 'support-seen';

  SupportStatus status = SupportStatus.idle;
  String errorMessage = '';
  List<TicketSummary> tickets = const [];
  Timer? _timer;
  String? _ticketsUrl;
  Map<String, DateTime> _seen = {};
  bool _seenLoaded = false;

  String get _token => bind.mainGetLocalOption(key: 'access_token');

  bool get loggedIn => _token.isNotEmpty;

  /// Ticket cuyo permiso de conexión sin aceptar sigue vigente (el que vence más tarde).
  TicketSummary? get activeTicket => activeSupportTicket(tickets, DateTime.now());

  // ---- mensajes sin leer (se recuerdan entre sesiones) ----

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
      debugPrint('support: could not read seen messages: $e');
    }
  }

  bool unread(TicketSummary t) {
    _loadSeen();
    return hasUnread(t, _seen);
  }

  /// Cuántos tickets tienen una respuesta de soporte sin leer.
  int get unreadTotal => tickets.where(unread).length;

  /// La persona leyó la conversación hasta el último mensaje de soporte.
  void markSeen(String id, DateTime? lastSupport) {
    _loadSeen();
    if (lastSupport == null) return;
    final cur = _seen[id];
    if (cur != null && !lastSupport.isAfter(cur)) return;
    _seen[id] = lastSupport;
    bind.mainSetLocalOption(
        key: _seenKey, value: jsonEncode(_seen.map((k, v) => MapEntry(k, v.toUtc().toIso8601String()))));
    notifyListeners();
  }

  // ---- red ----

  /// Consulta periódica mientras haya sesión: mantiene al día la lista y el aviso de permiso activo.
  void startPolling() {
    _timer ??= Timer.periodic(_pollInterval, (_) {
      if (loggedIn) refresh(quiet: true);
    });
    if (loggedIn && status == SupportStatus.idle) refresh(quiet: true);
  }

  Future<String?> _loadTicketsUrl() async {
    if (_ticketsUrl != null) return _ticketsUrl;
    final panel = await bind.mainGetApiServer();
    if (panel.isEmpty) return null;
    final resp = await http.get(Uri.parse(joinUrl(panel, '/api/support/config')),
        headers: {'Authorization': 'Bearer $_token'}).timeout(_timeout);
    if (resp.statusCode == 401) throw SupportException(401, 'no_autorizado');
    if (resp.statusCode != 200) return null;
    _ticketsUrl = parseTicketsUrl(jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
    return _ticketsUrl;
  }

  Future<http.Response> _call(String method, String path, {Object? body}) async {
    final base = await _loadTicketsUrl();
    if (base == null) throw SupportException(0, 'sin_portal');
    final uri = Uri.parse(joinUrl(base, path));
    final headers = {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'};
    final encoded = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'POST':
        return http.post(uri, headers: headers, body: encoded).timeout(_timeout);
      default:
        return http.get(uri, headers: headers).timeout(_timeout);
    }
  }

  dynamic _json(http.Response r, {int ok = 200}) {
    final text = utf8.decode(r.bodyBytes);
    Map<String, dynamic>? errBody;
    dynamic parsed;
    if (text.isNotEmpty) {
      try {
        parsed = jsonDecode(text);
        if (parsed is Map<String, dynamic>) errBody = parsed;
      } catch (_) {}
    }
    if (r.statusCode != ok) throw supportErrorFrom(r.statusCode, errBody);
    return parsed;
  }

  Future<void> refresh({bool quiet = false}) async {
    if (!loggedIn) {
      tickets = const [];
      status = SupportStatus.noLogin;
      notifyListeners();
      return;
    }
    if (!quiet) {
      status = SupportStatus.loading;
      notifyListeners();
    }
    try {
      if (await _loadTicketsUrl() == null) {
        status = SupportStatus.notConfigured;
      } else {
        final list = _json(await _call('GET', '/api/rootdesk/tickets')) as List;
        final before = unreadTotal;
        tickets = sortTickets(list.map((e) => TicketSummary.fromJson(e as Map<String, dynamic>)).toList());
        status = SupportStatus.ready;
        if (quiet && unreadTotal > before) {
          BotToast.showText(text: translate('Support replied to your ticket'));
        }
      }
    } on SupportException catch (e) {
      if (!quiet || status != SupportStatus.ready) {
        status = SupportStatus.error;
        errorMessage = e.unauthorized ? 'session_expired' : (e.code.isEmpty ? 'unknown_error' : e.code);
      }
    } catch (e) {
      debugPrint('support refresh failed: $e');
      if (!quiet || status != SupportStatus.ready) {
        status = SupportStatus.error;
        errorMessage = 'network_error';
      }
    }
    notifyListeners();
  }

  Future<List<TicketCategory>> categories() async {
    final list = _json(await _call('GET', '/api/rootdesk/categorias')) as List;
    return list.map((e) => TicketCategory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// El equipo está vinculado a la cuenta del panel (solo entonces se puede autorizar la conexión directa).
  Future<bool> deviceLinked() async {
    try {
      final panel = await bind.mainGetApiServer();
      final id = await bind.mainGetMyId();
      final resp = await http.get(Uri.parse('${joinUrl(panel, '/api/support/device')}?id=${Uri.encodeQueryComponent(id)}'),
          headers: {'Authorization': 'Bearer $_token'}).timeout(_timeout);
      if (resp.statusCode != 200) return false;
      return (jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>)['linked'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<CreatedTicket> create({
    required String titulo,
    required String descripcion,
    required String categoriaId,
    required bool autorizaSoporte,
  }) async {
    final body = {
      'titulo': titulo,
      'descripcion': descripcion,
      'categoria_id': categoriaId,
      'rustdesk_id': await bind.mainGetMyId(),
      'equipo_nombre': _hostname(),
      'autoriza_soporte': autorizaSoporte,
    };
    final created = CreatedTicket.fromJson(_json(await _call('POST', '/api/rootdesk/tickets', body: body), ok: 201) as Map<String, dynamic>);
    await refresh(quiet: true);
    return created;
  }

  /// Conversación completa de un ticket; al leerla, sus respuestas de soporte quedan como vistas.
  Future<TicketDetail> detail(String id) async {
    final d = TicketDetail.fromJson(_json(await _call('GET', '/api/rootdesk/tickets/$id')) as Map<String, dynamic>);
    markSeen(id, d.ultimoSoporteEn);
    return d;
  }

  /// La persona escribe un mensaje en la conversación de su ticket.
  Future<void> sendMessage(String id, String text) async {
    _json(await _call('POST', '/api/rootdesk/tickets/$id/comentarios', body: {'mensaje': text}), ok: 201);
    await refresh(quiet: true);
  }

  Future<void> revoke(String id) async {
    final r = await _call('POST', '/api/rootdesk/tickets/$id/revocar');
    if (r.statusCode != 204) _json(r, ok: 204);
    await refresh(quiet: true);
  }

  String _hostname() {
    try {
      final name = Platform.localHostname;
      return name.length > 80 ? name.substring(0, 80) : name;
    } catch (_) {
      return '';
    }
  }
}

final SupportModel supportModel = SupportModel();
