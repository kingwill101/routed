// XML model interfaces are intentionally abstract public extension points.
// ignore_for_file: one_member_abstracts
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
    final map = <String, dynamic>{};

    // Process attributes
    if (element.attributes.isNotEmpty) {
      map['@attributes'] = {
        for (final attr in element.attributes) attr.name.local: attr.value,
      };
    }

    // Process child elements and text
    final children = element.children.where(
      (node) =>
          node is XmlElement ||
          (node is XmlText && node.value.trim().isNotEmpty),
    );

    for (final child in children) {
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

    final builder = XmlBuilder()
      ..processing('xml', 'version="1.0" encoding="UTF-8"');
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
              for (final item in value) {
                _buildElement(builder, key, item);
              }
            } else {
              _buildElement(builder, key, value);
            }
          });
        },
      );
    } else if (content is List) {
      for (final item in content) {
        _buildElement(builder, name, item);
      }
    } else {
      builder.element(name, nest: content?.toString() ?? '');
    }
  }
}

/// A codec that converts XML strings to and from `Map<String, dynamic>`.
class XmlMapCodec extends Codec<Map<String, dynamic>, String> {
  /// Creates a constant [XmlMapCodec].
  const XmlMapCodec();

  /// The encoder that converts a map to an XML string.
  @override
  Converter<Map<String, dynamic>, String> get encoder => const XmlMapEncoder();

  /// The decoder that converts an XML string to a map.
  @override
  Converter<String, Map<String, dynamic>> get decoder => const XmlMapDecoder();
}

/// Example class implementing [XmlEncodable] and [XmlDecodable].
class User implements XmlEncodable, XmlDecodable<User> {
  /// Creates a [User] with [name], [age], [emails], and [isActive] status.
  User({
    this.name = '',
    this.age = -1,
    this.emails = const [],
    this.isActive = false,
  });

  /// The name of the user.
  final String name;

  /// The age of the user.
  final int age;

  /// The list of email addresses of the user.
  final List<String> emails;

  /// Whether the user is active.
  final bool isActive;

  /// Converts this [User] into a map for XML encoding.
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
    final name = xmlMap['name'] as Map<String, dynamic>;
    final age = xmlMap['age'] as Map<String, dynamic>;
    final emails = xmlMap['emails'] as Map<String, dynamic>;
    final active = xmlMap['active'] as Map<String, dynamic>;
    final emailValues = (emails['email'] as List).cast<Map<String, dynamic>>();
    return User(
      name: name['#text'] as String,
      age: int.parse(age['#text'] as String),
      emails: emailValues.map((email) => email['#text'] as String).toList(),
      isActive: (active['#text'] as String).toLowerCase() == 'true',
    );
  }

  /// Returns a string representation of the [User] instance.
  @override
  String toString() {
    return 'User(name: $name, age: $age, emails: $emails, isActive: $isActive)';
  }
}
