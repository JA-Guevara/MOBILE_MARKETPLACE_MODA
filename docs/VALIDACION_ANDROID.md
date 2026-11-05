# Validación Android · FashionStore Móvil

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
