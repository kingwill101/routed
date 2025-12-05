class Documentation {
  final String title;
  final String description;
  final String version;
  final List<Map<String, dynamic>> servers;
  final Map<String, Map<String, dynamic>> paths;
  final Map<String, Map<String, dynamic>> components;

  const Documentation({
    this.title = 'API Documentation',
    this.description = 'API Documentation',
    this.version = '1.0.0',
    this.servers = const [],
    this.paths = const {},
    this.components = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'openapi': '3.0.0',
      'info': {'title': title, 'description': description, 'version': version},
      'servers': servers,
      'paths': paths,
      'components': components,
    };
  }
}
