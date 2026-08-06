import 'dart:convert';

import 'package:xml/xml.dart';

/// Interface for objects that can be encoded to XML.
abstract class XmlEncodable {
  /// Converts the object into a `Map<String, dynamic>` for XML encoding.
  Map<String, dynamic> toXml();
}

/// Interface for objects that can be decoded from XML.
abstract class XmlDecodable<T> {
  /// Constructs an instance of [T] from a `Map<String, dynamic>`.
  T fromXml(Map<String, dynamic> xmlMap);
}

/// Converts an XML string into a `Map<String, dynamic>`.
class XmlMapDecoder extends Converter<String, Map<String, dynamic>> {
  /// Creates a constant [XmlMapDecoder].
  const XmlMapDecoder();

  /// Converts an XML string [input] into a `Map<String, dynamic>`.
  @override
  Map<String, dynamic> convert(String input) {
    final document = XmlDocument.parse(input);
    final root = document.rootElement;
    return {root.name.local: _elementToMap(root)};
  }

  /// Recursively converts an [XmlElement] into a `Map<String, dynamic>`.
  Map<String, dynamic> _elementToMap(XmlElement element) {
    final Map<String, dynamic> map = {};

    // Process attributes
    if (element.attributes.isNotEmpty) {
      map['@attributes'] = {
        for (var attr in element.attributes) attr.name.local: attr.value,
      };
    }

    // Process child elements and text
    final children = element.children.where(
      (node) =>
          node is XmlElement ||
          (node is XmlText && node.value.trim().isNotEmpty),
    );

    for (var child in children) {
      if (child is XmlElement) {
        final childName = child.name.local;
        final childMap = _elementToMap(child);

        if (map.containsKey(childName)) {
          if (map[childName] is List) {
            (map[childName] as List).add(childMap);
          } else {
            map[childName] = [map[childName], childMap];
          }
        } else {
          map[childName] = childMap;
        }
      } else if (child is XmlText) {
        map['#text'] = child.value.trim();
      }
    }

    return map;
  }
}

/// Converts a `Map<String, dynamic>` into an XML string.
class XmlMapEncoder extends Converter<Map<String, dynamic>, String> {
  /// Creates a constant [XmlMapEncoder].
  const XmlMapEncoder();

  /// Converts a `Map<String, dynamic>` [input] into an XML string.
  @override
  String convert(Map<String, dynamic> input) {
    if (input.isEmpty) {
      throw ArgumentError('Input map is empty. XML requires a root element.');
    }

    if (input.length != 1) {
      throw ArgumentError('Input map must have exactly one root element.');
    }

    final rootName = input.keys.first;
    final rootContent = input[rootName];

    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    _buildElement(builder, rootName, rootContent);
    final document = builder.buildDocument();
    return document.toXmlString(pretty: true);
  }

  /// Recursively builds XML elements from the map.
  void _buildElement(XmlBuilder builder, String name, dynamic content) {
    if (content is Map<String, dynamic>) {
      builder.element(
        name,
        nest: () {
          content.forEach((key, value) {
            if (key == '@attributes') {
              if (value is Map<String, dynamic>) {
                value.forEach((attrKey, attrValue) {
                  builder.attribute(attrKey, attrValue);
                });
              }
            } else if (key == '#text') {
              builder.text(value.toString());
            } else if (value is List) {
              for (var item in value) {
                _buildElement(builder, key, item);
              }
            } else {
              _buildElement(builder, key, value);
            }
          });
        },
      );
    } else if (content is List) {
      for (var item in content) {
        _buildElement(builder, name, item);
      }
    } else {
      builder.element(name, nest: content?.toString() ?? '');
    }
  }
}

/// A Codec that encodes and decodes XML strings to and from `Map<String, dynamic>`.
class XmlMapCodec extends Codec<Map<String, dynamic>, String> {
  /// Creates a constant [XmlMapCodec].
  const XmlMapCodec();

  /// The encoder that converts a `Map<String, dynamic>` to an XML string.
  @override
  final Converter<Map<String, dynamic>, String> encoder = const XmlMapEncoder();

  /// The decoder that converts an XML string to a `Map<String, dynamic>`.
  @override
  final Converter<String, Map<String, dynamic>> decoder = const XmlMapDecoder();
}

/// Example class implementing [XmlEncodable] and [XmlDecodable].
class User implements XmlEncodable, XmlDecodable<User> {
  /// The name of the user.
  final String name;

  /// The age of the user.
  final int age;

  /// The list of email addresses of the user.
  final List<String> emails;

  /// Whether the user is active.
  final bool isActive;

  /// Creates a [User] instance with the given [name], [age], [emails], and [isActive] status.
  User({
    this.name = '',
    this.age = -1,
    this.emails = const [],
    this.isActive = false,
  });

  /// Converts the [User] instance into a `Map<String, dynamic>` for XML encoding.
  @override
  Map<String, dynamic> toXml() {
    return {
      'name': {'#text': name},
      'age': {'#text': age.toString()},
      'emails': {
        'email': emails.map((email) => {'#text': email}).toList(),
      },
      'active': {'#text': isActive.toString()},
    };
  }

  /// Constructs a [User] instance from a `Map<String, dynamic>`.
  @override
  User fromXml(Map<String, dynamic> xmlMap) {
    return User(
      name: xmlMap['name']['#text'] as String,
      age: int.parse(xmlMap['age']['#text'] as String),
      emails: (xmlMap['emails']['email'] as List)
          .map((e) => e['#text'] as String)
          .toList(),
      isActive: xmlMap['active']['#text'].toLowerCase() == 'true',
    );
  }

  /// Returns a string representation of the [User] instance.
  @override
  String toString() {
    return 'User(name: $name, age: $age, emails: $emails, isActive: $isActive)';
  }
}

void main() {
  const codec = XmlMapCodec();

  // Example 1: Encoding and Decoding a Map
  print('--- Example 1: Map Encoding & Decoding ---');
  final xmlString = '''
  <?xml version="1.0" encoding="UTF-8"?>
  <person id="123">
    <name>John Doe</name>
    <age>30</age>
    <emails>
      <email>john@example.com</email>
      <email>doe@example.com</email>
    </emails>
    <active>true</active>
  </person>
  ''';

  // Decode XML to Map
  final decodedMap = codec.decode(xmlString);
  print('Decoded Map:\n$decodedMap\n');

  // Encode Map back to XML
  final encodedXml = codec.encode(decodedMap);
  print('Encoded XML:\n$encodedXml\n');

  // Example 2: Encoding and Decoding a Custom Object
  print('--- Example 2: Custom Object Encoding & Decoding ---');
  final user = User(
    name: 'Alice',
    age: 28,
    emails: ['alice@example.com', 'alice@work.com'],
    isActive: true,
  );

  // Encode User to XML
  final userMap = {'user': user.toXml()};
  final userXml = codec.encode(userMap);
  print('Encoded User XML:\n$userXml\n');

  // Decode XML back to User object
  final decodedUserMap = codec.decode(userXml);
  final userFromXml = User().fromXml(
    decodedUserMap['user'] as Map<String, dynamic>,
  );
  print('Decoded User Object:\n$userFromXml');
}
