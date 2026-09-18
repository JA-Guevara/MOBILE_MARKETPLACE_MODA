import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Marco con la barra inferior de la aplicación.
///
/// En la web la navegación principal vive en una barra superior con menús; en
/// un teléfono el patrón equivalente es una barra inferior con pocos destinos,
/// alcanzables con el pulgar. Son los cuatro que un cliente usa siempre:
/// catálogo, carrito, reservas y cuenta. La administración no está: sigue
/// siendo web.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navegacion});

  final StatefulNavigationShell navegacion;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navegacion,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navegacion.currentIndex,
        // `initialLocation: true` al tocar la pestaña activa vuelve a su raíz,
        // que es lo que la gente espera de una barra inferior.
        onDestinationSelected: (indice) => navegacion.goBranch(
          indice,
          initialLocation: indice == navegacion.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Catálogo',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon: Icon(Icons.shopping_bag),
            label: 'Carrito',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_outlined),
            selectedIcon: Icon(Icons.event),
            label: 'Reservas',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Cuenta',
          ),
        ],
      ),
    );
  }
}
