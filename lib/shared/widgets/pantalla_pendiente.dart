import 'package:flutter/material.dart';

/// Pantalla todavía sin construir.
///
/// Existe para que la navegación completa se pueda recorrer desde el primer
/// día: cada ruta de la app ya lleva a algún lado, y a medida que se implementa
/// una función se reemplaza este widget por la pantalla real. Deja a la vista
/// qué endpoint va a consumir, para que nadie tenga que buscarlo.
class PantallaPendiente extends StatelessWidget {
  const PantallaPendiente({
    super.key,
    required this.titulo,
    required this.descripcion,
    this.endpoints = const <String>[],
  });

  final String titulo;
  final String descripcion;
  final List<String> endpoints;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(descripcion, style: tema.textTheme.bodyLarge),
            if (endpoints.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Endpoints que consume', style: tema.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final endpoint in endpoints)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('· $endpoint', style: tema.textTheme.bodySmall),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
