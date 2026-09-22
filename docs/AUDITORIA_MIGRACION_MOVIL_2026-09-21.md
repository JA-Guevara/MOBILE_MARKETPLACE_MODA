# Auditoría de migración a Flutter

Fecha: 21 de septiembre de 2026.

## Dictamen

La aplicación Flutter **no representa todavía una migración completa del frontend web**. Existe una base correcta de arquitectura, sesión y catálogo, pero varios flujos críticos siguen siendo marcadores (`PantallaPendiente`) en el enrutador. No debe presentarse como una app móvil funcional de punta a punta hasta cerrar esos flujos.

## Implementado y revisado

| Área | Estado | Evidencia |
| --- | --- | --- |
| Configuración, red y sesión | Implementado | `dio`, interceptor Bearer/refresh, almacenamiento seguro y guardia de rutas. |
| Autenticación y cuenta | Implementado | Login, registro, verificación, recuperación, cambio de contraseña y perfil. |
| Catálogo básico | Implementado | Paginación, búsqueda, categoría, destacadas, recomendaciones y caché de imágenes. |
| Cámara y pose nativa | Parcial | La cámara y ML Kit detectan pose en el dispositivo; aún no consumen el recurso preparado por producto/color. |
| Permisos de cámara | Implementado | Android e iOS declaran el uso de cámara. |

## Flujos que siguen pendientes

| Flujo web | Situación móvil actual | Trabajo necesario |
| --- | --- | --- |
| Detalle de prenda | Marcador | Fotos, carrusel, variantes, sucursal, stock, favoritos, carrito y acceso al vestidor. |
| Carrito y checkout | Marcador | Cantidades, cupón, dirección, pedido, Stripe y conciliación al volver. |
| Pedidos y devoluciones | Marcador | Detalle, línea de tiempo, reintento de pago y devolución. |
| Reservas | Marcador | Disponibilidad, creación, cancelación y mis reservas. |
| Direcciones | Marcador | CRUD de direcciones y selección para compra. |
| Favoritos y alertas | Ausente | Favoritos, alerta de stock y alerta de precio. |
| Cupones | Ausente | Aplicación y desglose de promociones en carrito. |
| Probador preparado | Incompleto | Consultar sesión pública y recurso `ready`/`manual` por producto y color; superponer imagen transparente real, no solo una forma dibujada. |
| Foto realista con IA | Ausente | Consentimiento, carga de foto, estados del trabajo y eliminación. |

## Inconsistencias encontradas

1. `router.dart` exige sesión para abrir el vestidor, mientras que el flujo web ya permite iniciar la sesión de espejo como visitante.
2. El vestidor usa una silueta por categoría y color fijo; no consulta el recurso transparente preparado ni respeta la variante elegida.
3. La documentación llama al catálogo terminado y al vestidor pendiente, pero el código contiene una primera versión de cámara. Se debe actualizar el estado para evitar confusión.
4. La navegación inferior no incluye sucursales ni pedidos como destinos principales y los módulos asociados aún no tienen vistas reales.
5. El panel administrativo quedó fuera del alcance móvil deliberadamente. Si se decide incluirlo, debe diseñarse como tarjetas y detalle, no como copia de tablas de escritorio.

## Validación realizada

- Se revisaron rutas, módulos Flutter, dependencias, permisos Android/iOS y pruebas disponibles.
- `flutter analyze` no devolvió resultado en el entorno actual tras varios minutos, por lo que se canceló y **no se declara aprobado**.
- Antes de entregar un APK debe ejecutarse en una máquina con Flutter/SDK operativo:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

## Orden de finalización

1. Detalle de prenda y variantes.
2. Carrito, cupón, pedido y retorno de Stripe.
3. Pedidos, seguimiento, direcciones y devoluciones.
4. Reservas.
5. Recurso real y foto IA del probador.
6. Favoritos y alertas.
7. Pruebas en teléfono físico Android y, si aplica, iPhone.

## Criterio de aprobación

La migración estará aprobada cuando un cliente pueda registrarse, seleccionar una variante, agregarla al carrito, aplicar un cupón, pagar, revisar seguimiento, reservar una visita y usar el probador con una imagen preparada real. Cada flujo debe probarse contra el backend desplegado y documentarse con su endpoint y evidencia de prueba.
