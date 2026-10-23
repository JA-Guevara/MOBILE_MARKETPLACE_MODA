# Auditoría de migración a Flutter

Fecha de última actualización: 22 de septiembre de 2026.

## Dictamen

La aplicación Flutter implementa el flujo de cliente de punta a punta: sesión, catálogo, detalle, favoritos, carrito, cupón, direcciones, pedido, Stripe, seguimiento, devoluciones, reservas y probador. El panel administrativo permanece en la web. La aprobación final del APK queda condicionada a repetir las pruebas Flutter en un SDK operativo y a probar el pago con una cuenta de Stripe de prueba.

## Implementado y revisado

| Área | Estado | Evidencia |
| --- | --- | --- |
| Configuración, red y sesión | Implementado | `dio`, interceptor Bearer/refresh, almacenamiento seguro y guardia de rutas. |
| Autenticación y cuenta | Implementado | Login, registro, verificación, recuperación, cambio de contraseña y perfil. |
| Catálogo básico | Implementado | Paginación, búsqueda, categoría, destacadas, recomendaciones y caché de imágenes. |
| Detalle de prenda | Implementado | Carrusel, variante talla/color, favorito, reserva, carrito y acceso al probador. |
| Carrito, cupón y pago | Implementado | Cantidades, cupón, dirección, pedido, checkout Stripe y conciliación al volver. |
| Pedidos y devoluciones | Implementado | Lista, detalle, seguimiento, reintento de pago y solicitud de devolución. |
| Reservas | Implementado | Disponibilidad, creación, cancelación, horario y listado de visitas. |
| Favoritos y alertas | Implementado | Lista de prendas guardadas y preferencias de aviso de stock/precio. |
| Direcciones | Implementado | Alta, edición, predeterminada y uso en checkout. |
| Cámara, pose y recurso preparado | Implementado | La cámara y ML Kit detectan pose en el dispositivo. La app pide `POST /vestidor/sessions` con prenda y color, descarga el PNG/WebP transparente preparado y lo alinea mediante sus anclajes. |
| Permisos de cámara | Implementado | Android e iOS declaran el uso de cámara. |

## Fuera del alcance móvil actual

| Flujo web | Situación móvil actual | Trabajo necesario |
| --- | --- | --- |
| Administración | Web | Catálogo, inventario, sucursales, proveedores, reservas operativas, pagos, usuarios, bitácora y dashboard se gestionan en el frontend web. |
| Foto realista con IA | Pendiente | Requiere consentimiento, carga de foto, trabajos asíncronos y eliminación. |

## Inconsistencias encontradas

1. El recurso del vestidor depende de que cada color tenga una imagen preparada en el backend. Si el servidor responde 404, la persona verá un aviso claro y el administrador debe preparar o aprobar ese recurso.
2. La navegación inferior prioriza catálogo, carrito, reservas y cuenta. Pedidos, favoritos, direcciones y seguridad se abren desde **Mi cuenta** para mantener una barra manejable en teléfono.
3. El panel administrativo quedó fuera del alcance móvil deliberadamente. Si se decide incluirlo, debe diseñarse como tarjetas y detalle, no como copia de tablas de escritorio.

## Validación realizada

- Se revisaron rutas, módulos Flutter, dependencias, permisos Android/iOS y pruebas disponibles.
- El 21/09 se corrigieron 44 diagnósticos del editor: 41 eran efectos de una importación inválida en `CommerceApi`; los otros tres eran una dependencia de sesión perdida por la reorganización, una etiqueta de seguimiento mal nombrada y un formato de fecha sin uso. Además se incorporaron los DTO que faltaban para sucursales, puntos de caja, disponibilidad de devolución y búsqueda de mostrador, y se corrigió la ruta de puntos de caja al contrato del backend.
- Se verificó de forma estática que todas las importaciones relativas internas de `lib/` apuntan a archivos existentes y que no quedan referencias a las rutas movidas.
- `flutter analyze` no devolvió resultado en el entorno actual tras varios minutos, por lo que se canceló y **no se declara aprobado**.
- Antes de entregar un APK debe ejecutarse en una máquina con Flutter/SDK operativo:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

## Corrección de integración del 22/09

- **Carrito:** `PUT /commerce/cart/items/{variant_id}` confirma con `data: null`. El móvil trataba esa respuesta como un carrito y fallaba después de que el backend ya había hecho el cambio. Ahora ejecuta el comando sin deserializarlo, vuelve a consultar `GET /commerce/cart` y suma una unidad a una línea ya existente.
- **Probador:** se agregó `VestidorApi` y el componente que dibuja el recurso transparente devuelto por el backend. Se conserva la detección de pose local; ninguna imagen de cámara se sube al servidor en este flujo.
- **Prueba manual requerida:** iniciar sesión, abrir una prenda con una variante activa, tocar **Agregar al carrito**, verificar la línea en `/carrito`; volver a la prenda, tocar **Probarme**, permitir cámara y comprobar que aparece la imagen real preparada al quedar de frente. Si aparece el mensaje de recurso no preparado, verificar en administración que exista un activo para ese producto y color.

## Revisión de compra, reservas y pagos del 22/09

| Flujo móvil | Resultado de revisión | Corrección aplicada |
| --- | --- | --- |
| Catálogo y variante | La variante es la identidad que exige inventario, reserva y carrito. | El detalle conserva talla, color y sus identificadores. |
| Agregar al carrito | `PUT /commerce/cart/items/{variant_id}` guarda pero responde sin carrito. | Se procesa como comando y luego se relee `GET /commerce/cart`; al repetir la acción suma una unidad. |
| Carrito | Cantidad, eliminación, cupón, sucursal y entrega coinciden con el contrato. | Luego de cambiar o quitar una línea se relee el servidor; se agregó `DELETE /commerce/cart` para vaciarlo. |
| Reserva | Cuerpo y disponibilidad coinciden con `/reservations`. | Se valida que el horario elegido sea posterior al momento actual antes de enviar. |
| Mis reservas | El backend devuelve una página y el móvil la procesa como tal. | Crear, listar y cancelar usan las rutas autenticadas correctas. |
| Mis pedidos | El backend devuelve una lista directa, no una página. | Se corrigió el lector del móvil que esperaba erróneamente `items`. |
| Stripe | Stripe se ejecuta en el navegador externo y el servidor acredita el resultado. | Se informa si no se pudo abrir el navegador y el detalle incorpora **Actualizar pago**, que reconcilia con el servidor al volver. |

### Ajuste de salida a Stripe

El checkout puede fallar después de crear el pedido, por ejemplo si Railway no alcanza la API de Stripe o la clave no es válida. El móvil conserva ese pedido pendiente, muestra el motivo y abre su detalle para reintentar; ya no queda con un indicador de carga sin salida. Android declara el enlace HTTPS navegable para que Stripe Checkout se abra en el navegador externo.

Cuando la creación es correcta, el carrito se vacía a propósito porque las prendas quedan apartadas en el pedido. Si por cualquier razón no se abre automáticamente el detalle, el carrito vacío ofrece **Ver pedido y pagar**, enlazado al último pedido creado en esa sesión.

La apertura de Checkout prueba vista de navegador integrada, navegador externo y modo Android predeterminado. Si el teléfono no puede resolver ninguno, muestra una opción para copiar el enlace de Stripe y usarlo en el navegador, sin duplicar el pedido.

### Ajuste de lectura de reservas

`GET /reservations`, el detalle, la cancelación y las respuestas de creación incluyen ahora `branch_name` y las prendas guardadas en el snapshot. Si una reserva histórica solo conserva `variant_id`, el backend completa nombre, SKU, talla, color e imagen sin modificar su historial. Así **Mis reservas** puede mostrar qué se va a probar y en qué sucursal.

### Revisión pública del probador

El 22/09 se consultaron cinco prendas del catálogo desplegado contra `POST /vestidor/sessions`. Solo una tenía recurso, pero su URL apuntaba a `http://localhost:8000`, que un teléfono interpreta como sí mismo y no como Railway; tres colores respondieron `404` porque todavía no tienen recurso preparado. Al consultar la misma ruta usando el dominio público, el archivo respondió también `404`: la fila del recurso existe, pero su archivo no está servido en Railway. El móvil ahora corrige una URL local conservando su ruta y usando el origen configurado. En Railway debe definirse `MEDIA_PUBLIC_BASE_URL` con la URL pública de `/api/v1/media/files`, usar almacenamiento persistente para los archivos y reprocesar/aprobar cada color que se quiera probar.

### Correcciones detectadas en dispositivo

El registro de Android mostró que el probador intentaba actualizar `VestidorController` durante el primer `build`, una operación prohibida por Riverpod. La inicialización de cámara se difiere ahora al final del primer cuadro. El mismo registro detectó un desborde de 12 píxeles en el control de cantidad del carrito; se reemplazó la fila rígida por una disposición adaptable y se agregó una prueba para un ancho de 320 píxeles.

La URL pública respondió el 22/09 con `GET /api/v1/commerce/branches` → HTTP 200 y cuatro sucursales. Las rutas privadas no se probaron contra producción porque requieren una cuenta de cliente y una operación real; se cubren con pruebas locales del contrato.

En backend se ejecutaron `tests/unit/test_openapi_packages.py` y `tests/integration/auth/test_api_smoke.py`: **4 pruebas aprobadas**. Estas cubren la exposición del nuevo `DELETE /commerce/cart`, el empaquetado de las rutas y el arranque de la API.

La ejecución de `flutter test` del entorno actual se bloqueó dentro del SDK de Dart y no produjo resultado, por lo que no se declara aprobada. Debe repetirse desde una terminal limpia antes de generar el APK.

## Orden de finalización

1. Repetir análisis, pruebas y compilación Flutter en un SDK operativo.
2. Probar en Android físico: agregar carrito, cupón, pedido Stripe, retorno y actualización de pago.
3. Probar reservas: seleccionar prendas, comprobar disponibilidad, crear, ver detalle y cancelar.
4. Probar favoritos: guardar, cambiar ambos avisos y quitar.
5. Verificar un recurso preparado real por color en el probador.

## Criterio de aprobación

La migración estará aprobada cuando las pruebas de dispositivo confirmen que un cliente puede registrarse, seleccionar una variante, agregarla al carrito, aplicar un cupón, pagar, revisar seguimiento, reservar una visita, ver y cancelar su reserva, gestionar favoritos y usar el probador con una imagen preparada real. Cada flujo debe probarse contra el backend desplegado y documentarse con su endpoint y evidencia de prueba.
