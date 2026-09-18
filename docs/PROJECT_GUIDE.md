# FashionStore Móvil — guía del proyecto

## 1. Qué es y qué no es

Aplicación de **cliente** en Flutter. Consume exactamente los mismos endpoints que el frontend web: no existe una API para móvil.

Cubre los tres requisitos que hoy no tienen implementación:

| Requisito | Qué significa acá |
|---|---|
| RF07 | Consultar el catálogo desde el móvil |
| RF13 | Vestidor virtual en la aplicación móvil |
| RF16 | Comprar desde la aplicación móvil |

Alrededor de eso va lo que un cliente necesita para que esos tres tengan sentido: cuenta, direcciones guardadas, carrito, pedidos con seguimiento, devoluciones y reservas.

**La administración no está.** Pedidos, caja, existencias, devoluciones, bitácora y reportes siguen siendo web: son tareas de escritorio, con tablas anchas y formularios largos que en un teléfono se vuelven inservibles. Un encargado que despacha treinta pedidos no lo hace con el pulgar.

## 2. Organización del código

La misma separación por capas que el backend y el frontend web.

```
lib/
  main.dart                        arranque
  app/
    app.dart                       MaterialApp.router y tema
    router.dart                    rutas y guardia de sesión (equivale a app.routes.ts)
    home_shell.dart                barra inferior de navegación
    theme.dart                     identidad visual compartida con la web
  core/                            lo que no pertenece a ninguna función
    config/environment.dart        a qué backend apunta la app
    network/api_client.dart        cliente HTTP y desarmado del envoltorio
    network/api_exception.dart     errores del backend en español
    network/auth_interceptor.dart  bearer y renovación de sesión
    storage/token_store.dart       refresh token cifrado por el sistema
  features/<módulo>/
    domain/                        modelos y reglas, sin Flutter ni HTTP
    infrastructure/                llamadas al backend
    application/                   estado y casos de uso
    presentation/                  pantallas y widgets
  shared/
    models/                        ApiResponse y Page
    widgets/                       piezas reutilizables
    pose/                          vestidor: pose, ajuste y dibujo de la prenda
```

Los módulos de `features/` llevan el nombre de los del backend: `auth`, `usuarios_catalogo`, `ventas_pagos`, `reservas_vestidor`, `inventario_sucursales`.

### Por qué estas bibliotecas

| Elección | Motivo |
|---|---|
| `flutter_riverpod` | Es lo más parecido a las señales de Angular: un valor observable del que la vista se redibuja sola. Cumple además el papel de `providedIn: 'root'`. |
| `go_router` | Rutas declarativas con nombres, guardia y anidamiento, como `app.routes.ts`. |
| `dio` | Hace falta un interceptor para el bearer y la renovación; el cliente `http` no los tiene. |
| `flutter_secure_storage` | El refresh token no puede quedar en texto plano. |
| `camera` + `google_mlkit_pose_detection` | Equivalente nativo de MediaPipe Pose: los 33 puntos del cuerpo, calculados en el dispositivo. |
| `url_launcher` | Abrir el checkout de Stripe en el navegador del sistema. |
| `cached_network_image` | El catálogo son fotos y el móvil paga datos. |

## 3. Estado actual

**Listo y verificado** (`flutter analyze` sin observaciones, 11 pruebas en verde):

- Núcleo de red: cliente que desarma `{success, message, data}`, errores traducidos, interceptor con bearer y renovación, almacenamiento cifrado del refresh.
- Sesión completa: login, renovación, cierre y restauración al abrir la app.
- Router con guardia y barra inferior de cuatro destinos.
- Tema compartido con la web.

**Marcadores**: catálogo, detalle de prenda, probador, carrito, pedidos, reservas, cuenta y direcciones. Cada uno es una pantalla que dice qué va ahí y **qué endpoints consume**, así la navegación se recorre entera desde hoy y no hay que buscar el endpoint cuando toque implementarla.

## 4. Mapa de pantallas

| Pantalla | Ruta | Endpoints | Requisito |
|---|---|---|---|
| Catálogo | `/` | `GET /catalog/products`, `GET /catalog/categories`, `GET /commerce/recommendations` | RF07 |
| Detalle de prenda | `/prendas/:slug` | `GET /catalog/products/{slug}`, `GET /commerce/branches`, `PUT /commerce/cart/items/{variant_id}` | RF04, RF08 |
| Probador virtual | `/prendas/:slug/vestidor` | `POST /vestidor/sessions` | RF13 |
| Carrito y compra | `/carrito` | `GET /commerce/cart`, `POST /commerce/orders`, `POST /commerce/orders/{id}/checkout`, `POST /commerce/orders/{id}/payment-status` | RF14, RF16, RF19 |
| Mis pedidos y devoluciones | `/mi-cuenta/pedidos` | `GET /commerce/orders`, `GET`/`POST /commerce/orders/{id}/returns` | CU15, CU19 |
| Agendar visita | `/reservar` | `GET /reservations/availability`, `POST /reservations` | RF09, RF10 |
| Mis reservas | `/mi-cuenta/reservas` | `GET /reservations`, `POST /reservations/{id}/cancel` | RF12 |
| Mi cuenta | `/mi-cuenta` | `GET /auth/me`, `PATCH /commerce/profile` | RF01 |
| Mis direcciones | `/mi-cuenta/direcciones` | `GET`/`POST`/`PATCH /users/me/addresses` | RF01 |
| Iniciar sesión | `/iniciar-sesion` | `POST /auth/login`, `POST /auth/refresh` | RF02 |
| Crear cuenta | `/registrarse` | `POST /auth/register` | RF01 |

Las rutas conservan los nombres de la web a propósito: los correos que manda el backend enlazan a esas direcciones, así que un enlace profundo puede abrir la app en el mismo lugar sin inventar un mapa aparte.

## 5. A qué backend apunta

La URL entra por `--dart-define`, no por archivos duplicados:

```powershell
# Backend local desde el emulador de Android.
flutter run --dart-define=API_URL=http://10.0.2.2:8000/api/v1

# Backend de Railway.
flutter build apk --dart-define=API_URL=https://backendmarketplacemoda-production.up.railway.app/api/v1
```

`10.0.2.2` es cómo el emulador ve el `localhost` de la PC; `127.0.0.1` apuntaría al propio emulador y no encontraría nada.

Con un teléfono físico contra el backend local: `API_URL` es la IP de la PC en la red (`http://192.168.x.x:8000/api/v1`) y uvicorn tiene que escuchar en `--host 0.0.0.0`.

**Importante**: `MEDIA_PUBLIC_BASE_URL` del backend también tiene que ser una dirección alcanzable desde el teléfono. Con `http://localhost:8000/...` las fotos del catálogo no cargan aunque el resto funcione.

## 6. Sesión

El **access token** vive solo en memoria y muere con el proceso. El **refresh token** se guarda cifrado por el sistema —Keystore en Android, Keychain en iOS—, nunca en `SharedPreferences`, que es texto plano legible en un equipo con root. Es la misma decisión del frontend web.

Ante un `401`, el interceptor renueva una vez y reintenta. Tres detalles que están cubiertos por pruebas:

- Si varias peticiones fallan a la vez, **comparten una sola renovación**.
- Si una petición llega cuando otra ya renovó, **reintenta con el token nuevo** en lugar de pedir otro: con rotación de refresh tokens, pedir de más invalida el que acaba de emitirse.
- Si el reintento vuelve a dar `401`, la sesión se cierra en vez de entrar en bucle.

Un `401` del propio login no dispara renovación: credenciales incorrectas no son una sesión vencida.

## 7. Pago con Stripe

El backend crea la sesión con `success_url` hacia el **frontend web**, así que en el teléfono el usuario paga en el navegador y aterriza en la página web, no vuelve solo a la app.

Se resuelve **sin tocar el backend**: la app abre el enlace en el navegador del sistema y, al volver, llama a `POST /commerce/orders/{id}/payment-status`, que consulta Stripe desde el servidor y acredita el pedido si el cobro se completó. Ese endpoint ya existía como red de seguridad para confirmaciones atrasadas.

Si más adelante se quiere un retorno limpio con enlace profundo, *ahí* sí habría que cambiar el backend para aceptar una URL de retorno según el canal.

## 8. Probador virtual en móvil

La web detecta la pose con MediaPipe en el navegador; el móvil lo hace con `google_mlkit_pose_detection`, que entrega los mismos 33 puntos del cuerpo y corre en el dispositivo.

La lógica que ya existe en el frontend web es portable casi en su totalidad, porque son funciones puras sobre coordenadas:

| Web (`src/shared/`) | Móvil (`lib/shared/pose/`) |
|---|---|
| `pose-projection.ts` | proyección de los puntos a la pantalla |
| `garment-fit.ts` | ubicación automática y mensajes de postura |
| `garment-renderer.ts` | dibujo de la prenda por forma |

En Flutter el dibujo va en un `CustomPainter` en lugar de un canvas 2D, pero los polígonos y el suavizado se calculan igual. **Conviene portarlas con sus pruebas**: fueron esas pruebas las que detectaron que la cámara espejada daba la prenda al revés.

## 9. Comprobaciones

```powershell
flutter analyze
flutter test
```

Las pruebas actuales cubren el núcleo: traducción de errores del backend y comportamiento del interceptor ante sesión vencida. A medida que se implementen las pantallas, la lógica que se pueda probar sin interfaz debe vivir en `domain/`, igual que en los otros dos proyectos.

## 10. Orden sugerido de trabajo

1. **Catálogo** (RF07): sostiene a todas las demás pantallas y no necesita sesión, así que se puede probar de inmediato.
2. **Detalle de prenda**: tallas, colores y disponibilidad por sucursal.
3. **Carrito y compra** (RF16): incluye el retorno de Stripe descrito arriba.
4. **Mis pedidos**: seguimiento y devoluciones.
5. **Reservas** (RF09, RF10, RF12).
6. **Probador virtual** (RF13): el más caro; conviene hacerlo con el resto andando, y requiere permisos de cámara en Android e iOS.
7. Cuenta y direcciones.
