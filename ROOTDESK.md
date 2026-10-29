# RootDesk

Cliente de escritorio remoto para uso interno, derivado de **RustDesk 1.5.0**
(https://github.com/rustdesk/rustdesk, licencia **AGPL-3.0**; ver `LICENCE`).
Este repositorio contiene el codigo fuente completo, incluido `libs/hbb_common`
(antes submodulo de https://github.com/rustdesk/hbb_common, commit 229b904).

## Cambios respecto a RustDesk 1.5.0

| Archivo | Cambio |
|---|---|
| `libs/hbb_common/src/config.rs` | Servidor por defecto `id.rootinc.mx`; clave publica del servidor propio |
| `src/common.rs` | API por defecto `https://rustdesk.rootinc.mx`; comprobacion de actualizaciones desactivada |
| `libs/hbb_common/src/lib.rs` | URL de version apunta al servidor propio, no a `api.rustdesk.com` |
| `.github/workflows/` | Solo `rootdesk-windows.yml` (Windows x64, disparo manual) y sus dos workflows reutilizables |

Las marcas RustDesk(R) pertenecen a sus titulares; la AGPL no concede derechos de marca.
Si se entrega este software a terceros, tambien debe ofrecerseles este codigo fuente.
