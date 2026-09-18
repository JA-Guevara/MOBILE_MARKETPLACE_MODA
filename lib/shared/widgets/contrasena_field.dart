import 'package:flutter/material.dart';

/// Campo de contraseña con ojo para mostrar/ocultar.
///
/// La web lo resuelve con un botón al lado del input (`auth-page.component.ts`);
/// acá queda como widget propio porque aparece en login, registro, recuperación,
/// verificación y cambio de contraseña.
class ContrasenaField extends StatefulWidget {
  const ContrasenaField({
    super.key,
    required this.controller,
    this.label = 'Contraseña',
    this.validator,
    this.autofillHints,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  @override
  State<ContrasenaField> createState() => _ContrasenaFieldState();
}

class _ContrasenaFieldState extends State<ContrasenaField> {
  bool _oculta = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _oculta,
      autofillHints: widget.autofillHints,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: IconButton(
          onPressed: () => setState(() => _oculta = !_oculta),
          icon: Icon(_oculta ? Icons.visibility : Icons.visibility_off),
          tooltip: _oculta ? 'Mostrar' : 'Ocultar',
        ),
      ),
      validator: widget.validator,
      onFieldSubmitted: widget.onSubmitted,
    );
  }
}