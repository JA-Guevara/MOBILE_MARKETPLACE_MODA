import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

bool hayConexion(List<ConnectivityResult> resultados) =>
    resultados.any((r) => r != ConnectivityResult.none);

final conectividadProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  yield hayConexion(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(hayConexion).distinct();
});
