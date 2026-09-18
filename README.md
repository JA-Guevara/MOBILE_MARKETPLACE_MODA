# FashionStore — aplicación móvil

Aplicación de cliente en **Flutter** para FashionStore. Consume **los mismos endpoints**
que el frontend web: no hay una API aparte para móvil.

Cubre RF07 (catálogo desde el móvil), RF13 (vestidor virtual en la app) y RF16 (comprar desde
la app), más lo que un cliente necesita alrededor: cuenta, direcciones, carrito, pedidos con
seguimiento, reservas y devoluciones.

**La administración no está acá.** Pedidos, caja, existencias, devoluciones, bitácora y
reportes siguen siendo web: son tareas de escritorio, con tablas anchas y formularios largos.

---

## Contenido

1. [Estado de los módulos](#estado-de-los-módulos)
2. [Requisitos](#requisitos)
3. [Configuración y variables de entorno](#configuración-y-variables-de-entorno)
4. [Cómo correr la app](#cómo-correr-la-app)
5. [Estructura del proyecto](#estructura-del-proyecto)
6. [Arquitectura](#arquitectura)
7. [Pantallas y rutas](#pantallas-y-rutas)
8. [Identidad visual](#identidad-visual)
9. [Sesión](#sesión)
10. [Pago con Stripe](#pago-con-stripe)
11. [Comprobaciones y tests](#comprobaciones-y-tests)
12. [Solución de problemas](#solución-de-problemas)
13. [Documentación relacionada](#documentación-relacionada)

---

## Estado de los módulos

| Área | Módulo | Estado |
|---|---|---|
| Auth | Iniciar sesión, registrarse, recuperar contraseña, verificar/reenviar correo, cambiar contraseña, Mi cuenta | **Implementado** |
| Catálogo | Home, búsqueda (`search`), filtro por categoría/destacadas, scroll infinito (12 por página), tarjetas con imágenes y precios, recomendaciones sin sesión, pull-to-refresh | **Implementado** |
| Prenda | `/prendas/:slug` — fotos, tallas, colores, disponibilidad por sucursal | Pendiente |
| Probador virtual | `/prendas/:slug/vestidor` — cámara + pose (RF13) | Pendiente |
| Carrito y pago | `/carrito` — reserva, checkout y pago Stripe (RF14, RF16) | Pendiente |
| Reservas | `/reservar` y `/mi-cuenta/reservas` — agendar visita (RF09–RF12) | Pendiente |
| Pedidos | `/mi-cuenta/pedidos` — seguimiento y devoluciones (CU19) | Pendiente |
| Direcciones | `/mi-cuenta/direcciones` | Pendiente |

Los módulos pendientes muestran `PantallaPendiente` (una descripción de lo que harán y los
endpoints que consumirán). Su plan y contrato están en `docs/PROJECT_GUIDE.md`.

**Contrato verificado contra el backend real:** el catálogo usa `GET /catalog/products`
paginado (`page`, `page_size`, `search`, `category_id`, `brand`, `featured`, `min_price`,
`max_price`), las referencias por `GET /catalog/{recurso}`, el home carga recomendaciones con
`GET /commerce/recommendations` (sin sesión) y el perfil con `GET /commerce/profile`.

## Requisitos

- **Flutter 3.47+** (Dart 3.13+), según `pubspec.yaml` (`sdk: ^3.10.0`).
- Android SDK (para compilar APK).
- Para emulador: Android Studio / un emulador creado (`flutter emulators`).
- Para teléfono físico: modo desarrollador + depuración USB activada.
- Opcional: el backend corriendo en local (ver [Configuración](#configuración-y-variables-de-entorno)).

## Configuración y variables de entorno

No hay archivos de entorno duplicados: los valores entran por `--dart-define`, leyéndose en
`lib/core/config/environment.dart`.

| Variable | Qué es | Default |
|---|---|---|
| `API_URL` | Base del backend (sin barra final). La única obligatoria. | `https://backendmarketplacemoda-production.up.railway.app/api/v1` |
| `WEB_URL` | URL del frontend web. No se usa todavía: solo sirve para que la app reconozca la vuelta del checkout de Stripe. | `https://frontendmarketplacemoda-production.up.railway.app` |

La app **no toca el frontend web**: habla directo con la API. `WEB_URL` puede omitirse.

### El archivo `.env` (opcional)

`flutter run` **no lee `.env` por sí solo**: solo tiene efecto si se pasa con el flag. Sirve
para cambiar de backend sin tocar código:

```powershell
# 1) Copiar la plantilla
copy .env.example .env

# 2) El .env se lee SOLO si se pasa explícito
flutter run --dart-define-from-file=.env
```

`.env` y `.env.*` están en `.gitignore`: se sube a git solo `.env.example`.

## Cómo correr la app

### Backend de producción (recomendado, no requiere backend local)

```powershell
flutter run
```

Usa el default de `environment.dart` → Railway. No hay que levantar nada más.

### Emulador de Android contra el backend local

```powershell
flutter run --dart-define=API_URL=http://10.0.2.2:8000/api/v1
```

`10.0.2.2` es cómo el emulador ve el `localhost` de la PC. El backend debe escuchar en el
puerto 8000. *Solo funciona en emulador, no en teléfono físico.*

### Teléfono físico contra el backend local

```powershell
flutter run --dart-define=API_URL=http://192.168.x.x:8000/api/v1
```

- `192.168.x.x` = IP de la PC en la red (`ipconfig`).
- El backend tiene que escuchar en toda la red:
  `uvicorn src.main:app --reload --port 8000 --host 0.0.0.0`
- Aceptar el permiso de Windows Firewall para el puerto 8000.
- Teléfono y PC en la misma red Wi-Fi.

### Build del APK

```powershell
flutter build apk --debug
# o con ambiente específico
flutter build apk --release --dart-define-from-file=.env
```

El APK queda en `build\app\outputs\flutter-apk\`.

## Estructura del proyecto

Misma separación por capas que el backend y el frontend web, para que una función se busque en
el mismo lugar en los tres proyectos:

```
lib/
  main.dart                     arranque de la app
  app/
    app.dart                    MaterialApp.router y tema
    router.dart                 rutas y guardia de sesión (equivale a app.routes.ts)
    home_shell.dart             barra inferior de navegación
    theme.dart                  colores e identidad compartida con la web
  core/                         lo que no pertenece a ninguna función
    config/environment.dart     a qué backend apunta la app
    network/api_client.dart     cliente HTTP y desarmado del envoltorio ApiResponse
    network/api_exception.dart  errores del backend en español
    network/auth_interceptor.dart  bearer y renovación de sesión
    storage/token_store.dart    refresh token cifrado por el sistema
  features/<módulo>/
    domain/                     modelos y reglas, sin Flutter ni HTTP
    infrastructure/             llamadas al backend (API)
    application/                estado y casos de uso (Riverpod)
    presentation/               pantallas y widgets
  shared/
    models/                     ApiResponse y Page
    widgets/                    piezas reutilizables
    pose/                       vestidor: pose, ajuste y dibujo de la prenda (RF13)
```

Los módulos de `features/` llevan el nombre de los módulos del backend: `auth`,
`usuarios_catalogo`, `ventas_pagos`, `reservas_vestidor`, `inventario_sucursales`.

## Arquitectura

- **Estado**: Riverpod (`flutter_riverpod`). Los controllers expuestos por providers; la vista
  escucha y se redibuja sola, igual que las señales del Angular.
- **Navegación**: `go_router`, rutas nombradas igual que la web. `StatefulShellRoute.indexedStack`
  mantiene el estado de cada pestaña de la barra inferior.
- **Red**: `dio` con interceptores para el bearer y la renovación de sesión. La respuesta del
  backend viene envuelta (`success`, `data`, `Error`...) y `api_client.dart` la desarma.
- **Errores**: `ApiException` traduce los códigos del backend a mensajes en español rioplatense
  (campos vacíos, sesión vencida, sin conexión...).
- **Almacenamiento del token**: ver [Sesión](#sesión).

## Pantallas y rutas

Rutas públicas:

| Ruta | Pantalla |
|---|---|
| `/` | Catálogo (home) |
| `/iniciar-sesion?volverA=` | Iniciar sesión (con enlaces a registrar/recuperar/reenviar) |
| `/registrarse` | Registrarse |
| `/recuperar-contrasena?token=` | Recuperar contraseña |
| `/verificar-correo?token=&email=` | Verificar correo |
| `/reenviar-verificacion?email=` | Reenviar verificación |

Rutas privadas (sin sesión redirigen a `/iniciar-sesion`):

| Ruta | Pantalla |
|---|---|
| `/mi-cuenta` | Mi cuenta (perfil) — **implementada** |
| `/mi-cuenta/seguridad` | Cambiar contraseña — **implementada** |
| `/mi-cuenta/pedidos` | Mis pedidos (pendiente) |
| `/mi-cuenta/reservas` | Mis reservas (pendiente) |
| `/mi-cuenta/direcciones` | Mis direcciones (pendiente) |
| `/carrito` | Carrito (pendiente) |
| `/reservar` | Agendar visita (pendiente) |
| `/prendas/:slug` | Detalle de prenda (pendiente) |
| `/prendas/:slug/vestidor` | Probador virtual (pendiente) |

`/cambiar-contrasena` redirige a `/mi-cuenta/seguridad`, igual que en la web.

## Identidad visual

El tema se construye con la **paleta de la web** (`frontend_marketplace_moda/src/styles.scss`):

| Token | Valor |
|---|---|
| Acento | `#74394E` (vino) |
| Tinta | `#24231F` |
| Papel | `#FAF9F6` |
| Línea | `#E5E2DA` |

Definidos en `lib/app/theme.dart` (`_acento`, `_tinta`, `_papel`, `_linea`).

## Sesión

- El **access token** vive solo en memoria y muere con el proceso.
- El **refresh token** se guarda cifrado por el sistema (Keystore en Android, Keychain en iOS),
  nunca en `SharedPreferences` (texto plano legible en un equipo con root). Es la misma decisión
  del frontend web.
- Ante un 401, el interceptor renueva una sola vez y reintenta. Varias peticiones fallidas a la
  vez comparten una única renovación; si una llega cuando otra ya renovó, reintenta con el token
  nuevo en vez de pedir otro —con rotación de refresh tokens, pedir de más invalida el que acaba
  de emitirse—.
- Al cerrar sesión (o al vencer el refresh) el router expulsa de las rutas privadas al momento.

## Pago con Stripe

El backend crea la sesión de Stripe con `success_url` hacia el **frontend web**. La app abre ese
enlace en el navegador del sistema y, al volver, llama a
`POST /commerce/orders/{id}/payment-status`, que consulta Stripe desde el servidor y acredita el
pago si corresponde. Por eso la app no necesita un endpoint propio ni un enlace profundo: ese
endpoint ya existía como red de seguridad para confirmaciones que llegan tarde.

## Comprobaciones y tests

```powershell
flutter analyze
flutter test
```

Tests actuales (`test/`): reglas de contraseña, mapeo de errores HTTP (`ApiException`) y
renovación/rotación de tokens en el `AuthInterceptor`.

## Solución de problemas

**"No hay conexión con el servidor"**
- Confirmá que el backend al que apunta `API_URL` esté arriba (`http://127.0.0.1:8000/docs`
  local, o https://...railway.app/docs ).
- En teléfono físico contra backend local: la IP del `.env`/`--dart-define` debe ser la IP LAN de
  la PC (no `10.0.2.2`, que es solo para emulador) y el backend debe correr con `--host 0.0.0.0`.
- `flutter run` **a secas** usa el default de `environment.dart` (Railway). Para apuntar a otro
  lado, pasá `--dart-define=...` o `--dart-define-from-file=.env`.
- Verificá que teléfono y PC estén en la misma red y que el firewall deje pasar el puerto.

## Documentación relacionada

- `docs/PROJECT_GUIDE.md`: arquitectura, mapa de pantallas con sus endpoints y orden de trabajo.
- `../backend_marketplace_moda/docs/API_CONTRACT.md`: contrato de los endpoints que consume la app.
- `../backend_marketplace_moda/docs/TRAZABILIDAD_RF.md`: estado de cada RF en los tres proyectos.# MOBILE_MARKETPLACE_MODA
