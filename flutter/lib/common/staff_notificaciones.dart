import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/staff_aviso_logic.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:win32/win32.dart' as w32;
import 'package:window_manager/window_manager.dart';

import '../common.dart';

// FLASHWINFO de user32 (win32 5.x no lo trae): hace parpadear el botón de la barra de tareas.
final class _FlashInfo extends Struct {
  @Uint32()
  external int cbSize;
  @IntPtr()
  external int hwnd;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int uCount;
  @Uint32()
  external int dwTimeout;
}

const _flashwAll = 3; // FLASHW_ALL: ícono de la barra de tareas y borde de la ventana
const _flashwTimerNoFg = 12; // FLASHW_TIMERNOFG: hasta que la ventana pase al frente

/// Avisos de la edición Soporte que salen de la ventana: notificación del sistema, número en el Dock (Mac),
/// número en el título y parpadeo en la barra de tareas (Windows). Todo es opcional: si algo falla solo se registra.
class StaffNotificaciones {
  static const _canalMac = MethodChannel('org.rustdesk.rustdesk/host');
  static bool _listo = false;
  static int _insignia = -1;
  static String _tituloActual = '';

  static Future<void> _iniciar() async {
    if (_listo || !isDesktop) return;
    try {
      await localNotifier.setup(appName: 'RootDesk Soporte', shortcutPolicy: ShortcutPolicy.requireCreate);
      _listo = true;
    } catch (e) {
      debugPrint('staff: no se pudo preparar las notificaciones del sistema: $e');
    }
  }

  /// ¿La persona está mirando la aplicación ahora mismo? Entonces basta el aviso dentro de ella.
  static Future<bool> ventanaALaVista() async {
    try {
      return await windowManager.isVisible() && await windowManager.isFocused() && !await windowManager.isMinimized();
    } catch (_) {
      return false;
    }
  }

  /// Notificación del sistema; al hacer clic trae la ventana al frente y llama a [alHacerClic].
  static Future<void> mostrar({required String titulo, required String cuerpo, required VoidCallback alHacerClic}) async {
    await _iniciar();
    if (!_listo) return;
    try {
      final n = LocalNotification(title: titulo, body: cuerpo);
      n.onClick = () async {
        await traerAlFrente();
        alHacerClic();
      };
      await n.show();
    } catch (e) {
      debugPrint('staff: no se pudo mostrar la notificación: $e');
    }
  }

  static Future<void> traerAlFrente() async {
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('staff: no se pudo traer la ventana al frente: $e');
    }
  }

  /// Número de casos que piden atención: Dock en Mac, título de la ventana y, si sube, parpadeo en Windows.
  static Future<void> actualizarInsignia(int n) async {
    if (!isDesktop || n == _insignia) return;
    final subio = n > _insignia && _insignia >= 0;
    _insignia = n;
    try {
      if (isMacOS) await _canalMac.invokeMethod('setBadge', n > 0 ? '$n' : '');
      final base = bind.mainGetAppNameSync();
      final titulo = tituloConInsignia(base, n);
      await windowManager.setTitle(titulo);
      _tituloActual = titulo;
      if (isWindows && subio && !await ventanaALaVista()) _parpadear(titulo);
    } catch (e) {
      debugPrint('staff: no se pudo actualizar la insignia: $e');
    }
  }

  /// Hace parpadear el botón de la barra de tareas hasta que la ventana pase al frente.
  static void _parpadear(String titulo) {
    final nombre = titulo.toNativeUtf16();
    final info = calloc<_FlashInfo>();
    try {
      final hwnd = w32.FindWindow(nullptr, nombre);
      if (hwnd == 0) return;
      info.ref.cbSize = sizeOf<_FlashInfo>();
      info.ref.hwnd = hwnd;
      info.ref.dwFlags = _flashwAll | _flashwTimerNoFg;
      info.ref.uCount = 0;
      info.ref.dwTimeout = 0;
      final flashWindowEx = DynamicLibrary.open('user32.dll')
          .lookupFunction<Int32 Function(Pointer<_FlashInfo>), int Function(Pointer<_FlashInfo>)>('FlashWindowEx');
      flashWindowEx(info);
    } catch (e) {
      debugPrint('staff: no se pudo hacer parpadear la barra de tareas: $e');
    } finally {
      calloc.free(info);
      calloc.free(nombre);
    }
  }

  @visibleForTesting
  static String get tituloActual => _tituloActual;
}
