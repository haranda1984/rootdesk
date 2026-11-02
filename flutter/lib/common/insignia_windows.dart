import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'insignia_logic.dart';

// win32 5.x no trae ITaskbarList3, así que se llama su tabla de funciones a mano.
const _clsidTaskbarList = '{56FDF344-FD6D-11D0-958A-006097C9A090}';
const _iidTaskbarList3 = '{EA1AFB91-9E28-4B86-90E9-9E9F8A5EEFAF}';
const _posRelease = 2;
const _posHrInit = 3;
const _posSetOverlayIcon = 18; // IUnknown 0-2, ITaskbarList 3-7, ITaskbarList2 8, ITaskbarList3 9-20

typedef _SoloSelfNativo = Int32 Function(Pointer<Void> self);
typedef _SoloSelf = int Function(Pointer<Void> self);
typedef _ReleaseNativo = Uint32 Function(Pointer<Void> self);
typedef _Release = int Function(Pointer<Void> self);
typedef _SetOverlayNativo = Int32 Function(Pointer<Void> self, IntPtr hwnd, IntPtr icono, Pointer<Utf16> descripcion);
typedef _SetOverlay = int Function(Pointer<Void> self, int hwnd, int icono, Pointer<Utf16> descripcion);

Pointer<NativeFunction<T>> _metodo<T extends Function>(Pointer<Void> objeto, int posicion) {
  final tabla = Pointer<IntPtr>.fromAddress(Pointer<IntPtr>.fromAddress(objeto.address).value);
  return Pointer<NativeFunction<T>>.fromAddress(tabla[posicion]);
}

/// Icono de 32 bits con alfa a partir de los bytes BGRA de [insigniaBgra]; 0 si falla.
int _crearIcono(Uint8List bgra) {
  final info = calloc<BITMAPINFO>();
  final bits = calloc<Pointer<Void>>();
  final iconInfo = calloc<ICONINFO>();
  final hdc = GetDC(0);
  var color = 0, mascara = 0;
  try {
    info.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
    info.ref.bmiHeader.biWidth = kTamInsignia;
    info.ref.bmiHeader.biHeight = -kTamInsignia; // de arriba hacia abajo
    info.ref.bmiHeader.biPlanes = 1;
    info.ref.bmiHeader.biBitCount = 32;
    info.ref.bmiHeader.biCompression = BI_RGB;
    color = CreateDIBSection(hdc, info, DIB_RGB_COLORS, bits, 0, 0);
    if (color == 0) return 0;
    bits.value.cast<Uint8>().asTypedList(bgra.length).setAll(0, bgra);
    mascara = CreateBitmap(kTamInsignia, kTamInsignia, 1, 1, nullptr);
    iconInfo.ref.fIcon = TRUE;
    iconInfo.ref.hbmMask = mascara;
    iconInfo.ref.hbmColor = color;
    return CreateIconIndirect(iconInfo);
  } finally {
    if (color != 0) DeleteObject(color);
    if (mascara != 0) DeleteObject(mascara);
    ReleaseDC(0, hdc);
    calloc.free(iconInfo);
    calloc.free(bits);
    calloc.free(info);
  }
}

/// Pone en el botón de la barra de tareas de [hwnd] el globo rojo con el número [n] (como en WhatsApp), o lo quita si
/// [n] <= 0. Devuelve si Windows lo aceptó.
bool establecerInsigniaBarra(int hwnd, int n, {String descripcion = ''}) {
  final hrCom = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  final ppv = calloc<Pointer<Void>>();
  final clsid = calloc<GUID>()..ref.setGUID(_clsidTaskbarList);
  final iid = calloc<GUID>()..ref.setGUID(_iidTaskbarList3);
  Pointer<Void> objeto = nullptr;
  Pointer<Utf16> texto = nullptr;
  var icono = 0;
  try {
    if (FAILED(CoCreateInstance(clsid, nullptr, CLSCTX_INPROC_SERVER, iid, ppv.cast()))) return false;
    objeto = ppv.value;
    final hrInit = _metodo<_SoloSelfNativo>(objeto, _posHrInit).asFunction<_SoloSelf>();
    if (FAILED(hrInit(objeto))) return false;
    if (n > 0) {
      icono = _crearIcono(insigniaBgra(n));
      if (icono == 0) return false;
      texto = descripcion.toNativeUtf16();
    }
    final setOverlay = _metodo<_SetOverlayNativo>(objeto, _posSetOverlayIcon).asFunction<_SetOverlay>();
    return SUCCEEDED(setOverlay(objeto, hwnd, icono, texto));
  } finally {
    if (objeto != nullptr) _metodo<_ReleaseNativo>(objeto, _posRelease).asFunction<_Release>()(objeto);
    if (icono != 0) DestroyIcon(icono);
    if (texto != nullptr) calloc.free(texto);
    calloc.free(iid);
    calloc.free(clsid);
    calloc.free(ppv);
    if (SUCCEEDED(hrCom)) CoUninitialize();
  }
}
