# RootDesk

Cliente de escritorio remoto para uso interno, derivado de **RustDesk 1.5.0**
(https://github.com/rustdesk/rustdesk, licencia **AGPL-3.0**; ver `LICENCE`).
Este repositorio contiene el codigo fuente completo, incluido `libs/hbb_common`
(antes submodulo de https://github.com/rustdesk/hbb_common, commit 229b904).

## Cambios respecto a RustDesk 1.5.0

| Archivo | Cambio |
|---|---|
| `libs/hbb_common/src/config.rs` | Servidor por defecto `id.rootinc.mx`; clave publica del servidor propio |
| `src/common.rs` | API por defecto `https://rootdesk.rootinc.mx` (un dominio anterior `rustdesk.rootinc.mx` guardado en el equipo se cambia solo al nuevo); comprobacion de actualizaciones desactivada |
| `libs/hbb_common/src/lib.rs` | URL de version apunta al servidor propio, no a `api.rustdesk.com` |
| `libs/hbb_common/src/config.rs` | Nombre de la aplicacion `RootDesk` (servicio, carpetas, instalador) |
| `src/client.rs` | La ficha de sesion del panel ya no se envia a hbbs/hbbr: el hbbs de codigo abierto no cifra ese canal y la conexion fallaba con "Failed to secure tcp" al estar con sesion iniciada |
| `src/hbbs_http/sync.rs` | El panel puede entregar la contrasena permanente (modo desatendido) en la respuesta del latido |
| `res/*.ico`, `res/*.png`, `flutter/assets/{icon,logo}.png`, `flutter/windows/runner/` | Icono y textos de recursos de RootDesk |
| `.github/workflows/` | Solo `rootdesk-windows.yml` (Windows x64, disparo manual) y sus dos workflows reutilizables |

Las marcas RustDesk(R) pertenecen a sus titulares; la AGPL no concede derechos de marca.
Si se entrega este software a terceros, tambien debe ofrecerseles este codigo fuente.
