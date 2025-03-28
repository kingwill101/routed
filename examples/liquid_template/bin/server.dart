import 'package:routed/routed.dart';

void main() async {
  final engine = Engine();

  // Configure Liquid template engine
  engine.useLiquid(directory: 'templates');

  // Home page
  engine.get('/', (ctx) {
    return ctx.html('home.liquid', data: {
      'page_title': 'Home Page',
      'welcome_message': 'Welcome to the Liquid Template Example!',
      'features': [
        'Fast and flexible routing',
        'Middleware support',
        'Template engine integration',
        'Static file serving'
      ]
    });
  });

  // Basic template with variables and loops
  engine.get('/hello', (ctx) {
    return ctx.html('hello.liquid', data: {
      'page_title': 'Hello Example',
      'name': 'World',
      'show_list': true,
      'items': [
        'Welcome to Liquid templating',
        'Try the extended template',
        'Or the dynamic data example'
      ]
    });
  });
  // Extended route
  engine.get('/extended', (ctx) {
    return ctx.html('extended.liquid', data: {
      'page_title': 'Extended Example',
      'name': 'Template User',
      'message': 'This is an extended template example!',
      'features': [
        'Template includes using {% raw %}{% render %}{% endraw %}',
        'Variable assignment: {% raw %}{% assign %}{% endraw %}',
        'Filters: {{ "hello world" | capitalize }}',
        'Conditionals: {% raw %}{% if/else %}{% endraw %}',
        'Loops: {% raw %}{% for/in %}{% endraw %}'
      ],
      'current_time': DateTime.now().toString()
    });
  });

  // Dynamic route
  engine.get('/data/{name}', (ctx) {
    final name = ctx.param('name');
    return ctx.html('dynamic.liquid', data: {
      'page_title': '$name\'s Page',
      'name': name,
      'items': [
        'Welcome $name',
        'Current time: ${DateTime.now()}',
        'Your IP: ${ctx.request.clientIP}'
      ],
      'ip_address': ctx.request.clientIP
    });
  });

  // About page
  engine.get('/about', (ctx) {
    return ctx.html('about.liquid', data: {
      'page_title': 'About Us',
      'description': 'Learn more about our project and team.',
      'team_members': [
        {'name': 'John Doe', 'role': 'Developer'},
        {'name': 'Jane Smith', 'role': 'Designer'},
        {'name': 'Alice Johnson', 'role': 'Project Manager'}
      ]
    });
  });

  // Contact page with form example
  engine.get('/contact', (ctx) {
    return ctx.html('contact.liquid', data: {
      'page_title': 'Contact Us',
      'contact_info': {
        'email': 'support@example.com',
        'phone': '+1-234-5678',
        'address': '123 Main St, City, Country'
      }
    });
  });

  // Handle form submission
  engine.post('/submit-contact', (ctx) async {
    // Parse form data
    final name = await ctx.postForm('name');
    final email = await ctx.postForm('email');
    final message = await ctx.postForm('message');

    // Validate form data
    if (name.isEmpty || email.isEmpty || message.isEmpty) {
      return ctx.string('All fields are required!', statusCode: 400);
    }

    // Process the form data (e.g., save to database, send email, etc.)
    print('Received contact form submission:');
    print('Name: $name');
    print('Email: $email');
    print('Message: $message');

    // Return a success response
    return await ctx.redirect('/contact-success');
  });

  // Success page after form submission
  engine.get('/contact-success', (ctx) {
    return ctx.html('contact_success.liquid', data: {
      'page_title': 'Contact Form Submitted',
      'message': 'Thank you for contacting us! We will get back to you soon.'
    });
  });

  // Start the server
  await engine.serve(port: 3000);
}
