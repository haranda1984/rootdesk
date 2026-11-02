import 'dart:math' as math;
import 'dart:typed_data';

/// Lado, en píxeles, del dibujo de la insignia (Windows lo reduce a 16 lógicos y lo agranda en pantallas de alta densidad).
const int kTamInsignia = 32;

/// Lo que dice la insignia: el número, con 99 como tope porque más dígitos no caben en un icono tan pequeño.
String textoInsignia(int n) => n <= 0 ? '' : '${math.min(n, 99)}';

// Dígitos de 5 x 7 puntos. El número se dibuja con esta fuente propia para no depender de GDI ni del motor de texto.
const List<List<String>> _fuente = [
  ['.###.', '#...#', '#..##', '#.#.#', '##..#', '#...#', '.###.'], // 0
  ['..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.'], // 1
  ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'], // 2
  ['####.', '....#', '....#', '.###.', '....#', '....#', '####.'], // 3
  ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'], // 4
  ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'], // 5
  ['..##.', '.#...', '#....', '####.', '#...#', '#...#', '.###.'], // 6
  ['#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...'], // 7
  ['.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.'], // 8
  ['.###.', '#...#', '#...#', '.####', '....#', '...#.', '.##..'], // 9
];

const int _rojoB = 0x2F, _rojoG = 0x24, _rojoR = 0xE0;

/// Círculo rojo con el número en blanco, como bytes BGRA con el alfa ya multiplicado (lo que pide un icono de 32 bits).
/// Con [n] <= 0 devuelve todo transparente.
Uint8List insigniaBgra(int n) {
  const tam = kTamInsignia;
  final px = Uint8List(tam * tam * 4);
  final texto = textoInsignia(n);
  if (texto.isEmpty) return px;

  const centro = (tam - 1) / 2;
  const radio = tam / 2 - 0.5;
  for (var y = 0; y < tam; y++) {
    for (var x = 0; x < tam; x++) {
      final d = math.sqrt((x - centro) * (x - centro) + (y - centro) * (y - centro));
      final cobertura = (radio + 0.5 - d).clamp(0.0, 1.0);
      if (cobertura <= 0) continue;
      final i = (y * tam + x) * 4;
      px[i] = (_rojoB * cobertura).round();
      px[i + 1] = (_rojoG * cobertura).round();
      px[i + 2] = (_rojoR * cobertura).round();
      px[i + 3] = (255 * cobertura).round();
    }
  }

  final escala = texto.length == 1 ? 3 : 2;
  final ancho = texto.length * 5 * escala + (texto.length - 1) * escala;
  final x0 = (tam - ancho) ~/ 2;
  final y0 = (tam - 7 * escala) ~/ 2;
  for (var k = 0; k < texto.length; k++) {
    final digito = _fuente[int.parse(texto[k])];
    final dx = x0 + k * 6 * escala;
    for (var fila = 0; fila < 7; fila++) {
      for (var col = 0; col < 5; col++) {
        if (digito[fila][col] != '#') continue;
        for (var sy = 0; sy < escala; sy++) {
          for (var sx = 0; sx < escala; sx++) {
            final i = ((y0 + fila * escala + sy) * tam + dx + col * escala + sx) * 4;
            px[i] = px[i + 1] = px[i + 2] = px[i + 3] = 255;
          }
        }
      }
    }
  }
  return px;
}
