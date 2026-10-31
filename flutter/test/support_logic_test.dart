import 'package:flutter_hbb/models/support_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2030, 1, 1, 12);

  TicketSummary ticket(String id, {String? hasta}) => TicketSummary.fromJson({
        'id': id,
        'folio': 'RD-$id',
        'titulo': 'Titulo $id',
        'estado': 'nuevo',
        'creado_en': '2030-01-01T10:00:00Z',
        'soporte_hasta': hasta,
      });

  test('parsea un ticket de la lista', () {
    final t = ticket('1', hasta: '2030-01-02T00:00:00Z');
    expect(t.folio, 'RD-1');
    expect(t.soporteHasta, isNotNull);
    expect(t.soporteActivo(now), isTrue);
  });

  test('un permiso vencido o ausente no está activo', () {
    expect(ticket('1', hasta: '2030-01-01T11:00:00Z').soporteActivo(now), isFalse);
    expect(ticket('2').soporteActivo(now), isFalse);
  });

  test('activeSupportTicket elige el permiso que vence más tarde', () {
    final list = [
      ticket('a', hasta: '2030-01-01T13:00:00Z'),
      ticket('b', hasta: '2030-01-01T20:00:00Z'),
      ticket('c', hasta: '2030-01-01T09:00:00Z'),
      ticket('d'),
    ];
    expect(activeSupportTicket(list, now)?.id, 'b');
  });

  test('activeSupportTicket devuelve null si ninguno sigue vigente', () {
    expect(activeSupportTicket([ticket('c', hasta: '2030-01-01T09:00:00Z'), ticket('d')], now), isNull);
    expect(activeSupportTicket([], now), isNull);
  });

  test('el detalle trae descripción y comentarios', () {
    final d = TicketDetail.fromJson({
      'id': '1',
      'folio': 'RD-1',
      'titulo': 'T',
      'estado': 'en_proceso',
      'descripcion': 'No abre',
      'comentarios': [
        {'autor': 'Ana', 'mensaje': 'Hola', 'creado_en': '2030-01-01T10:30:00Z'}
      ],
    });
    expect(d.descripcion, 'No abre');
    expect(d.comentarios.single.autor, 'Ana');
  });

  test('CreatedTicket guarda el estado del permiso de soporte', () {
    final c = CreatedTicket.fromJson({'id': '1', 'folio': 'RD-1', 'soporte': 'no_vinculado', 'soporte_hasta': null});
    expect(c.soporte, 'no_vinculado');
    expect(c.soporteHasta, isNull);
  });

  TicketSummary t2(String id, String estado, String actividad, {String? soporte}) => TicketSummary.fromJson({
        'id': id,
        'folio': 'RD-$id',
        'titulo': 'T$id',
        'estado': estado,
        'creado_en': '2030-01-01T08:00:00Z',
        'ultima_actividad_en': actividad,
        'mensajes': 2,
        'ultimo_soporte_en': soporte,
      });

  test('la lista pone primero lo que sigue en atención y, dentro de cada grupo, lo más reciente', () {
    final list = [
      t2('cerrado-nuevo', 'cerrado', '2030-01-01T11:00:00Z'),
      t2('abierto-viejo', 'en_proceso', '2030-01-01T09:00:00Z'),
      t2('abierto-nuevo', 'nuevo', '2030-01-01T10:30:00Z'),
      t2('resuelto-viejo', 'resuelto', '2030-01-01T08:30:00Z'),
    ];
    expect(sortTickets(list).map((t) => t.id).toList(),
        ['abierto-nuevo', 'abierto-viejo', 'cerrado-nuevo', 'resuelto-viejo']);
  });

  test('ordenar no modifica la lista original', () {
    final list = [t2('a', 'cerrado', '2030-01-01T09:00:00Z'), t2('b', 'nuevo', '2030-01-01T08:00:00Z')];
    sortTickets(list);
    expect(list.first.id, 'a');
  });

  test('mensaje sin leer: soporte escribió después de lo último que se vio', () {
    final t = t2('1', 'en_proceso', '2030-01-01T12:00:00Z', soporte: '2030-01-01T12:00:00Z');
    expect(hasUnread(t, {}), isTrue);
    expect(hasUnread(t, {'1': DateTime.utc(2030, 1, 1, 11)}), isTrue);
    expect(hasUnread(t, {'1': DateTime.utc(2030, 1, 1, 12)}), isFalse);
    expect(hasUnread(t2('2', 'nuevo', '2030-01-01T12:00:00Z'), {}), isFalse);
  });

  test('un ticket sin mensajes de soporte no marca nada pendiente y el resumen lee los contadores', () {
    final t = t2('1', 'nuevo', '2030-01-01T12:00:00Z');
    expect(t.mensajes, 2);
    expect(t.ultimoSoporteEn, isNull);
    expect(t.abierto, isTrue);
    expect(t2('3', 'resuelto', '2030-01-01T12:00:00Z').abierto, isFalse);
  });

  test('el detalle sabe cuándo escribió soporte por última vez', () {
    final d = TicketDetail.fromJson({
      'id': '1',
      'folio': 'RD-1',
      'titulo': 'T',
      'estado': 'en_proceso',
      'descripcion': 'x',
      'comentarios': [
        {'autor': 'Yo', 'mensaje': 'a', 'creado_en': '2030-01-01T10:00:00Z', 'es_mio': true},
        {'autor': 'Ana', 'mensaje': 'b', 'creado_en': '2030-01-01T11:00:00Z', 'es_mio': false},
        {'autor': 'Yo', 'mensaje': 'c', 'creado_en': '2030-01-01T12:00:00Z', 'es_mio': true},
      ],
    });
    expect(d.ultimoSoporteEn, DateTime.parse('2030-01-01T11:00:00Z').toLocal());
    expect(d.comentarios.first.esMio, isTrue);
  });

  test('tiempo relativo en español', () {
    final now = DateTime(2030, 1, 5, 12, 0);
    expect(relativeTime(now.subtract(const Duration(seconds: 20)), now), 'hace un momento');
    expect(relativeTime(now.subtract(const Duration(minutes: 5)), now), 'hace 5 min');
    expect(relativeTime(now.subtract(const Duration(hours: 3)), now), 'hace 3 h');
    expect(relativeTime(now.subtract(const Duration(hours: 30)), now), 'ayer');
    expect(relativeTime(DateTime(2030, 1, 1, 8, 5), now), '01/01/2030');
  });

  test('fecha y hora de 24 horas, con ceros a la izquierda', () {
    expect(formatDateTime(DateTime(2026, 10, 31, 1, 37)), '31/10/2026 01:37');
    expect(formatDateTime(DateTime(2026, 3, 5, 13, 7)), '05/03/2026 13:07');
  });

  test('estados en español', () {
    expect(ticketStateLabel('en_proceso'), 'En atención');
    expect(ticketStateLabel('en_espera_cliente'), 'Esperando tu respuesta');
    expect(ticketStateLabel('raro'), 'raro');
  });

  test('joinUrl no duplica ni pierde barras', () {
    expect(joinUrl('https://t.example.com/', '/api/x'), 'https://t.example.com/api/x');
    expect(joinUrl('https://t.example.com', 'api/x'), 'https://t.example.com/api/x');
  });

  test('parseTicketsUrl ignora valores vacíos o ausentes', () {
    expect(parseTicketsUrl({'tickets_url': ' https://t.example.com '}), 'https://t.example.com');
    expect(parseTicketsUrl({'tickets_url': ''}), isNull);
    expect(parseTicketsUrl({}), isNull);
  });

  test('supportErrorFrom lee el código y detalle del cuerpo', () {
    final e = supportErrorFrom(422, {'error': 'datos_invalidos', 'detalle': 'Mínimo 5 caracteres'});
    expect(e.code, 'datos_invalidos');
    expect(e.detail, 'Mínimo 5 caracteres');
    expect(supportErrorFrom(401, null).unauthorized, isTrue);
  });
}
