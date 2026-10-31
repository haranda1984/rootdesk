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
