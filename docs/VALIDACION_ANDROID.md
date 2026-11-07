# Validación Android · FashionStore Móvil

## Avisos y pagos · APK 0.1.3 (código 4), 07/11/2026

Ventanas globales con importe, referencia y acceso al detalle. Al regresar de Stripe se consulta el servidor: únicamente `paid` muestra éxito; un resultado pendiente mantiene el pedido y pide verificar antes de volver a pagar. La verificación manual y el pago de diferencias de cambios usan la misma regla. El historial está en «Mi cuenta → Avisos y pagos». Las ventanas se separan por cuenta/empresa y se cierran al cambiar de sesión. Las novedades se consultan cada 45 segundos con la aplicación abierta y al reanudarla; no son notificaciones remotas del sistema con la app cerrada.

Resultados: 334 pruebas aprobadas y una externa optativa omitida, 24 pruebas focalizadas aprobadas después del último ajuste, análisis estático sin problemas y APK debug compilada. La prueba de widgets comprueba ventana, importe, cierre sin perder la pantalla y descarte al cambiar de empresa. Los ensayos de compra y webhook se hicieron con proveedor simulado y datos locales; no se hicieron cargos reales.

Instalador: `entregables/mobile/FashionStore-0.1.3-debug.apk` en la carpeta compartida. SHA-256: `CEF215E9E48EE407B619D9E09669BB5A38F46D7B6A1D938B0DCB9F01012CA38D`. No había teléfono detectado por ADB al cerrar esta tanda; la versión 0.1.3 no se instaló ni se validó en el dispositivo físico. La instalación anterior permanece intacta.

## Actualización del 07/11/2026

Se reprodujo y corrigió el fallo de inicio «No pudimos cargar las tiendas»: los interceptores consultaban proveedores que dependían del mismo cliente de red. La prueba con interceptores reales detectó `CircularDependencyError` antes de enviar cualquier petición. `SessionLink` separa esas dependencias y mantiene token, alcance y renovación de una sola sesión.

- **0.1.1 (código 2):** APK compilada desde el commit `4333c00`, instalada como actualización en VKP NX9 / Android 17. El usuario confirmó que la lista de tiendas ya aparece. No se desinstaló ni borró el almacenamiento.
- **0.1.2 (código 3):** añade invalidación del estado privado al cambiar de usuario o empresa. Carrito, favoritos, pedidos, direcciones, reservas y reportes no conservan el contexto anterior. Las respuestas tardías se descartan; una renovación de token de la misma cuenta conserva la selección actual.
- Análisis estático sin problemas y **329 pruebas aprobadas**; una prueba externa optativa omitida en la suite normal. Esta última se ejecutó por separado expresamente: cuatro controles aprobados, incluyendo lectura del directorio de producción (cuatro tiendas), una prenda, categorías y recomendaciones. Solo se leen datos públicos.
- Recuperación de directorio probada: error → reintento → selección → catálogo; ingreso por empresa y tienda del registro. El modo offline ya no se ofrece como salida genérica a un error interno y los clientes no consultan la administración de suscripciones.
- Historial offline integrado por el otro chat: SQLite v4 añade alcance de cuenta al historial. La suite incluye migración y aislamiento; no equivale a un ensayo de modo avión completo en el teléfono.
- Renovación y `401` tardíos: una sesión cerrada no se restaura ni vuelve a guardar sus credenciales por una respuesta en curso. Una solicitud de la cuenta anterior no se repite con el token de la siguiente cuenta. Los guardados y borrados locales se ordenan para conservar el resultado del último cambio de sesión.

Pruebas específicas: `test/core/public_stores_integration_test.dart`, `test/core/account_scope_test.dart`, `test/features/usuarios_catalogo/inicio_tiendas_test.dart`. La consulta externa se activa con `--dart-define=RUN_PUBLIC_API_SMOKE=true`; nunca usa cuentas o contraseñas reales.

**0.1.2 instalada el 07/11/2026:** compilada desde el código `4c62f82`, actualización por USB completada con `Success`, versión 0.1.2 / código 3 confirmada por Android. Se inició la aplicación y no se observaron errores circulares o de base local en los registros accesibles del proceso. No se borró el almacenamiento.

APK entregada en `../entregables/mobile/FashionStore-0.1.2-debug.apk`, SHA-256 `354C8109DAA2A8EDC0570B915531641C3AB3D7E9C6B64492FCF81C425CCAD1AC`. Es una compilación debug para prueba, no un lanzamiento firmado para tienda. La confirmación del usuario sobre la lista de tiendas corresponde a la actualización 0.1.1 previa; la instalación 0.1.2 incorpora el mismo arreglo más las protecciones posteriores.

Falta completar en el teléfono un recorrido autenticado y el ciclo modo avión → operación → reapertura → sincronización. Las pruebas automatizadas cubren esos componentes, pero no se procesaron cobros, cambios ni ventas reales en este dispositivo. Los resultados del 04/11 de abajo se conservan como registro histórico y no describen el estado actual de la APK.

## Registro histórico del 04/11/2026

Revisión de Q2.1 del 04/11/2026. **No se generó un APK ni se instaló en un teléfono durante esta revisión.** La alternativa de GitHub Actions está preparada y validada de forma estática; no se ejecutó ni se publicó un artefacto. Se retiraron las afirmaciones anteriores de instalación, capturas y resultados que no tenían evidencia.

## Resultado local observado

- Windows, Flutter **3.47.5 stable**, Dart **3.13.4**. La versión instalada se usó para fijar el workflow.
- Java **17** seleccionado solo en el proceso de compilación. No se cambió `JAVA_HOME` global ni la configuración del sistema.
- `gradle.properties` ya incluía heap de 2 GB, preferencia IPv4 y `org.gradle.daemon=false`; se conservaron. Estos ajustes **no resolvieron** el error observado.
- Se intentó `flutter build apk --release --dart-define=API_URL=http://10.0.2.2:8000/api/v1 --dart-define=TENANT_SLUG=urbano`, apuntando a un entorno de prueba local.
- Gradle terminó con `java.io.IOException: Unable to establish loopback connection`, antes de producir el APK. El registro está en `docs/evidencias-implementacion/2026-11-04/movil-apk-release.log` de la carpeta compartida.
- `flutter devices` mostró únicamente Windows, Chrome y Edge; no había dispositivo Android disponible.

Q2.1 conserva validación pendiente: su criterio exige un APK generado e instalado en Android real. Q2.2 (modo avión, cierre y reapertura en teléfono) no se ejecutó en esta tanda.

## Alternativa manual en GitHub Actions

El workflow `.github/workflows/android-apk.yml` usa Java 17 y Flutter **3.47.5**. Solo tiene `workflow_dispatch`, permisos de lectura y entradas explícitas `api_url` y `tenant_slug`. La API debe incluir `/api/v1`; el workflow valida su forma antes de compilar. No tiene una URL de producción por defecto.

Al ejecutarlo con autorización y contra el entorno de prueba elegido:

1. Instala dependencias, ejecuta `flutter analyze` y `flutter test`.
2. Compila release con los parámetros indicados.
3. Adjunta APK, versión/commit y SHA-256 como artefacto temporal de 7 días.
4. Si están presentes los cuatro secretos `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS` y `ANDROID_KEY_PASSWORD`, prepara una firma con ese keystore únicamente en el entorno temporal del trabajo. No guarda secretos ni keystore en Git. Una configuración parcial falla expresamente.
5. Si no hay secretos, mantiene la firma de depuración que ya usa `android/app/build.gradle.kts` para la demostración. No equivale a una firma preparada para distribución pública.

La revisión comprobó YAML y sintaxis del Python embebido; eso no demuestra que Actions haya compilado ni que exista un artefacto descargable. Se debe registrar aquí el enlace de la ejecución, commit, SHA-256 y resultado real cuando se ejecute.

## Checklist pendiente en un teléfono real

Antes de instalar, registrar modelo, versión Android y SHA-256 del APK. Usar cuentas y datos sintéticos del entorno de prueba; capturas sin tokens ni datos personales.

| Comprobación | Evidencia necesaria | Estado |
|---|---|---|
| Generar APK e instalar | Registro de build, SHA-256, modelo y Android | PENDIENTE |
| Inicio y cuenta de empresa | Captura con cuenta sintética y alcance esperado | PENDIENTE |
| Descargar y consultar catálogo sin red | Capturas online y modo avión | PENDIENTE |
| Reserva y venta local | Documento provisional y cola persistente | PENDIENTE |
| Cerrar y reabrir sin red | Misma operación, stock y cuenta tras reiniciar | PENDIENTE |
| Reconectar y sincronizar | Resultado por operación y ausencia de duplicación | PENDIENTE |
| Bloqueo de dispositivo | Resultado del flujo CU-12 cuando se integre y valide | PENDIENTE |
