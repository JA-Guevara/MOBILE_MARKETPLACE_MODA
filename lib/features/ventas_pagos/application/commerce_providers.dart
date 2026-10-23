import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../usuarios_catalogo/application/session_controller.dart';
import '../infrastructure/commerce_api.dart';

/// Punto único de acceso a `/commerce` para toda la app.
///
/// `CommerceApi` ya estaba escrito y no lo usaba nadie: faltaba justamente
/// esto, el proveedor que lo cuelga del mismo `ApiClient` que lleva el bearer
/// y renueva la sesión. Construirlo a mano en cada pantalla habría dejado
/// peticiones sin token.
final Provider<CommerceApi> commerceApiProvider =
    Provider<CommerceApi>((ref) => CommerceApi(ref.watch(apiClientProvider)));
