import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Caché propia de larga duración, precargada durante «Preparar».
class ImagenesOffline {
  ImagenesOffline({BaseCacheManager? cache}) : _cache = cache;
  BaseCacheManager? _cache;
  BaseCacheManager get cache => _cache ??= CacheManager(
    Config(
      'fashionstore-catalogo-offline',
      stalePeriod: const Duration(days: 365),
      maxNrOfCacheObjects: 5000,
    ),
  );
  Future<void> preparar(
    Iterable<String> urls, {
    void Function(int, int)? progreso,
  }) async {
    final unicas = urls.where((u) => u.isNotEmpty).toSet();
    var numero = 0;
    var faltantes = false;
    for (final url in unicas) {
      try {
        await cache.getSingleFile(url).timeout(const Duration(seconds: 8));
      } catch (_) {
        faltantes = true;
      }
      progreso?.call(++numero, unicas.length);
    }
    if (faltantes) throw StateError('No se guardaron todas las imágenes.');
  }

  Future<File?> leer(String url) async =>
      (await cache.getFileFromCache(url))?.file;
}
