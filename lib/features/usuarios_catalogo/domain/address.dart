/// Dirección del perfil, reutilizada al comprar. Mismo contrato que la
/// interfaz `Address` de `account-page.component.ts` en la web.
class Direccion {
  const Direccion({
    required this.id,
    required this.label,
    required this.recipientName,
    required this.phone,
    required this.addressLine,
    required this.city,
    this.postalCode,
    this.country,
    this.reference,
    this.isDefault = false,
  });

  final String id;
  final String label;
  final String recipientName;
  final String phone;
  final String addressLine;
  final String city;
  final String? postalCode;
  final String? country;
  final String? reference;
  final bool isDefault;

  factory Direccion.desdeJson(Map<String, dynamic> json) => Direccion(
        id: '${json['id']}',
        label: json['label'] as String? ?? '',
        recipientName: json['recipient_name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        addressLine: json['address_line'] as String? ?? '',
        city: json['city'] as String? ?? '',
        postalCode: json['postal_code'] as String?,
        country: json['country'] as String?,
        reference: json['reference'] as String?,
        isDefault: json['is_default'] as bool? ?? false,
      );
}
