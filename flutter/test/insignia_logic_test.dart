import 'package:flutter_hbb/common/insignia_logic.dart';
import 'package:flutter_test/flutter_test.dart';

// Alfa del píxel (x, y) del dibujo.
int _alfa(List<int> px, int x, int y) => px[(y * kTamInsignia + x) * 4 + 3];

// ¿Hay algún píxel blanco (el número) dentro del rectángulo?
bool _hayBlanco(List<int> px, int x0, int x1) {
  for (var y = 0; y < kTamInsignia; y++) {
    for (var x = x0; x < x1; x++) {
      final i = (y * kTamInsignia + x) * 4;
      if (px[i] == 255 && px[i + 1] == 255 && px[i + 2] == 255 && px[i + 3] == 255) return true;
    }
  }
  return false;
}

void main() {
  group('textoInsignia', () {
    test('sin pendientes no hay texto', () {
      expect(textoInsignia(0), '');
      expect(textoInsignia(-3), '');
    });
    test('muestra el número y se detiene en 99', () {
      expect(textoInsignia(1), '1');
      expect(textoInsignia(42), '42');
      expect(textoInsignia(99), '99');
      expect(textoInsignia(250), '99');
    });
  });

  group('insigniaBgra', () {
    test('tiene el tamaño de un icono de 32 x 32 con 4 bytes por píxel', () {
      expect(insigniaBgra(5).length, kTamInsignia * kTamInsignia * 4);
    });
    test('en cero todo es transparente', () {
      expect(insigniaBgra(0).every((b) => b == 0), isTrue);
    });
    test('es un círculo: las esquinas quedan transparentes y el borde superior es rojo opaco', () {
      final px = insigniaBgra(7);
      for (final (x, y) in [(0, 0), (31, 0), (0, 31), (31, 31)]) {
        expect(_alfa(px, x, y), 0, reason: 'esquina $x,$y');
      }
      expect(_alfa(px, 16, 3), 255);
      final i = (3 * kTamInsignia + 16) * 4;
      expect([px[i], px[i + 1], px[i + 2]], [0x2F, 0x24, 0xE0]); // BGR del rojo
    });
    test('lleva el número en blanco; uno de dos cifras ocupa las dos mitades', () {
      expect(_hayBlanco(insigniaBgra(7), 8, 24), isTrue);
      final dos = insigniaBgra(42);
      expect(_hayBlanco(dos, 5, 16), isTrue);
      expect(_hayBlanco(dos, 16, 27), isTrue);
    });
    test('no se sale del dibujo con ninguna cifra', () {
      for (var n = 0; n <= 100; n++) {
        expect(insigniaBgra(n).length, kTamInsignia * kTamInsignia * 4, reason: 'n=$n');
      }
    });
    test('números distintos se dibujan distinto', () {
      expect(insigniaBgra(1), isNot(equals(insigniaBgra(2))));
      expect(insigniaBgra(10), isNot(equals(insigniaBgra(11))));
    });
  });
}
