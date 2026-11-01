import 'dart:convert';

/// Lógica pura de los avisos en vivo de la edición Soporte (sin Flutter, para probarla con `flutter test`).

enum TipoAviso { mensajeCliente, casoNuevo, casoAsignado, casoInvitado }

const _tipos = {
  'mensaje_cliente': TipoAviso.mensajeCliente,
  'caso_nuevo': TipoAviso.casoNuevo,
  'caso_asignado': TipoAviso.casoAsignado,
  'caso_invitado': TipoAviso.casoInvitado,
};

class StaffAviso {
  final String id;
  final TipoAviso tipo;
  final String ticketId;
  final String folio;
  final String titulo;
  final String de;
  final String mensaje;

  const StaffAviso({
    required this.id,
    required this.tipo,
    required this.ticketId,
    required this.folio,
    required this.titulo,
    required this.de,
    required this.mensaje,
  });

  /// `null` si el tipo es desconocido (un servidor más nuevo que la app) o faltan datos: se ignora sin romper nada.
  static StaffAviso? fromJson(Map<String, dynamic> j) {
    final tipo = _tipos[j['tipo']];
    final ticketId = j['ticketId'];
    if (tipo == null || ticketId is! String || ticketId.isEmpty) return null;
    String s(String k) => (j[k] ?? '').toString();
    return StaffAviso(
      id: s('id'),
      tipo: tipo,
      ticketId: ticketId,
      folio: s('folio'),
      titulo: s('titulo'),
      de: s('de'),
      mensaje: s('mensaje'),
    );
  }
}

/// Un evento SSE completo.
class SseEvento {
  final String? id;
  final String evento;
  final String datos;
  const SseEvento({this.id, required this.evento, required this.datos});
}

/// Lector incremental de Server-Sent Events: recibe el texto en trozos de cualquier tamaño (un evento puede llegar
/// partido) y devuelve los eventos que ya están completos. Ignora comentarios (latidos) y eventos sin datos.
class SseParser {
  String _pendiente = '';
  String? ultimoId;

  List<SseEvento> add(String trozo) {
    _pendiente += trozo.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final salida = <SseEvento>[];
    int corte;
    while ((corte = _pendiente.indexOf('\n\n')) != -1) {
      final bloque = _pendiente.substring(0, corte);
      _pendiente = _pendiente.substring(corte + 2);
      final e = _bloque(bloque);
      if (e != null) salida.add(e);
    }
    return salida;
  }

  SseEvento? _bloque(String bloque) {
    String? id;
    var evento = 'message';
    final datos = <String>[];
    for (final linea in bloque.split('\n')) {
      if (linea.isEmpty || linea.startsWith(':')) continue;
      final i = linea.indexOf(':');
      final campo = i == -1 ? linea : linea.substring(0, i);
      var valor = i == -1 ? '' : linea.substring(i + 1);
      if (valor.startsWith(' ')) valor = valor.substring(1);
      switch (campo) {
        case 'id':
          id = valor;
        case 'event':
          evento = valor;
        case 'data':
          datos.add(valor);
      }
    }
    if (id != null) ultimoId = id;
    if (datos.isEmpty) return null;
    return SseEvento(id: id, evento: evento, datos: datos.join('\n'));
  }
}

/// Convierte un evento del servidor en un aviso; `null` si no es un aviso o viene mal formado.
StaffAviso? avisoDeEvento(SseEvento e) {
  if (e.evento != 'aviso') return null;
  try {
    final j = jsonDecode(e.datos);
    return j is Map<String, dynamic> ? StaffAviso.fromJson(j) : null;
  } catch (_) {
    return null;
  }
}

/// Espera antes de reconectar: 2 s, 4 s, 8 s… hasta un minuto.
Duration esperaReconexion(int intentos) {
  final n = intentos < 1 ? 1 : intentos;
  final seg = 2 * (1 << (n > 5 ? 5 : n - 1));
  return Duration(seconds: seg > 60 ? 60 : seg);
}

/// Título y cuerpo del aviso; [t] traduce.
({String titulo, String cuerpo}) textoAviso(StaffAviso a, String Function(String) t) {
  switch (a.tipo) {
    case TipoAviso.mensajeCliente:
      return (titulo: '${a.de} · ${a.folio}', cuerpo: a.mensaje);
    case TipoAviso.casoNuevo:
      return (titulo: '${t('New case')} · ${a.folio}', cuerpo: '${a.de}: ${a.titulo}');
    case TipoAviso.casoAsignado:
      return (titulo: '${t('A case was assigned to you')} · ${a.folio}', cuerpo: '${a.de}: ${a.mensaje}');
    case TipoAviso.casoInvitado:
      return (titulo: '${t('You were invited to a case')} · ${a.folio}', cuerpo: '${a.de} · ${a.titulo}');
  }
}

/// Título de la ventana con el número de casos que piden atención.
String tituloConInsignia(String base, int n) => n > 0 ? '($n) $base' : base;
