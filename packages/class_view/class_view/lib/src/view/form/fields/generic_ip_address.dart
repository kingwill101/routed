import 'dart:io' show InternetAddress, InternetAddressType;

import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/text_input.dart';
import 'field.dart';

/// Maximum length of an IPv6 address
const maxIpv6AddressLength = 39;

/// A field for handling IP addresses (both IPv4 and IPv6).
class GenericIPAddressField extends Field<String> {
  /// The protocol to validate against.
  /// Can be 'both', 'IPv4', or 'IPv6'.
  final String protocol;

  /// Creates a new generic IP address field.
  GenericIPAddressField({
    this.protocol = 'both',
    super.required = true,
    Widget? widget,
    super.label,
    super.initial,
    super.helpText,
    super.errorMessages,
    super.showHiddenInitial = false,
    super.validators = const [],
    super.localize = false,
    super.disabled = false,
    super.labelSuffix,
    int? maxLength,
  }) : super(
         widget:
             widget ??
             TextInput(
               attrs: {
                 'maxlength': (maxLength ?? maxIpv6AddressLength).toString(),
               },
             ),
       ) {
    if (!['both', 'ipv4', 'ipv6'].contains(protocol.toLowerCase())) {
      throw ArgumentError(
        "The protocol '$protocol' is unknown. Supported: both, IPv4, IPv6",
      );
    }
  }

  @override
  String? toDart(dynamic value) {
    if (value == null || value == '') {
      if (required) {
        throw ValidationError({
          'required': ['This field is required.'],
        });
      }
      return null;
    }

    String ipStr = value.toString().trim();

    try {
      final addr = InternetAddress.tryParse(ipStr);
      if (addr == null) {
        switch (protocol.toLowerCase()) {
          case 'ipv4':
            throw ValidationError({
              'invalid': ['Enter a valid IPv4 address.'],
            });
          case 'ipv6':
            throw ValidationError({
              'invalid': ['This is not a valid IPv6 address.'],
            });
          default:
            throw ValidationError({
              'invalid': ['Enter a valid IPv4 or IPv6 address.'],
            });
        }
      }

      if (protocol.toLowerCase() == 'ipv4' &&
          addr.type != InternetAddressType.IPv4) {
        throw ValidationError({
          'invalid': ['Enter a valid IPv4 address.'],
        });
      }

      if (protocol.toLowerCase() == 'ipv6' &&
          addr.type != InternetAddressType.IPv6) {
        throw ValidationError({
          'invalid': ['This is not a valid IPv6 address.'],
        });
      }

      return addr.address;
    } catch (e) {
      if (e is ValidationError) {
        rethrow;
      }
      // If we get here, there was a parsing error
      switch (protocol.toLowerCase()) {
        case 'ipv4':
          throw ValidationError({
            'invalid': ['Enter a valid IPv4 address.'],
          });
        case 'ipv6':
          throw ValidationError({
            'invalid': ['This is not a valid IPv6 address.'],
          });
        default:
          throw ValidationError({
            'invalid': ['Enter a valid IPv4 or IPv6 address.'],
          });
      }
    }
  }
}
