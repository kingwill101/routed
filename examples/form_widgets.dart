// import 'package:class_view/class_view.dart'
//     show
//         CharField,
//         EmailField,
//         Field,
//         Form,
//         MinLengthValidator,
//         Select,
//         TextInput,
//         TypedChoiceField;
// import 'package:routed/routed.dart'
//     show
//         ContextRender,
//         Engine,
//         EngineContext,
//         EngineRouting,
//         ServerExtension,
//         View;
//
// /// A form for user registration
// class RegistrationForm extends Form {
//   late final Field<String> usernameField;
//   late final Field<String> emailField;
//   late final Field<String> passwordField;
//   late final Field<String> countryField;
//
//   RegistrationForm()
//       : super(
//           isBound: true,
//           data: {},
//           files: {},
//           fields: {},
//         ) {
//     usernameField = CharField(
//       label: 'Username',
//       required: true,
//       helpText: 'Choose a unique username',
//       widget: TextInput(attrs: {'class': 'form-control'}),
//     );
//
//     emailField = EmailField(
//       label: 'Email Address',
//       required: true,
//       widget: TextInput(
//           attrs: {'class': 'form-control', 'placeholder': 'you@example.com'}),
//     );
//
//     passwordField = CharField(
//       label: 'Password',
//       required: true,
//       helpText: 'At least 8 characters',
//       widget: TextInput(attrs: {'class': 'form-control', 'type': 'password'}),
//       validators: [MinLengthValidator(8)],
//     );
//
//     countryField = TypedChoiceField<String>(
//       label: 'Country',
//       required: true,
//       choices: [
//         ['', 'Choose your country'],
//         ['us', 'United States'],
//         ['ca', 'Canada'],
//         ['uk', 'United Kingdom'],
//       ],
//       coerce: (value) => value.toString(),
//       emptyValue: '',
//       widget: Select(
//         choices: [
//           ['', 'Choose your country'],
//           ['us', 'United States'],
//           ['ca', 'Canada'],
//           ['uk', 'United Kingdom'],
//         ],
//         attrs: {'class': 'form-control'},
//       ),
//     );
//
//     fields.addAll({
//       'username': usernameField,
//       'email': emailField,
//       'password': passwordField,
//       'country': countryField,
//     });
//   }
//
//   @override
//   Future<void> clean() async {
//     // Additional form-wide validation can go here
//     if (cleanedData['password'] != null &&
//         cleanedData['password'].toString().length < 8) {
//       addError('password', 'Password must be at least 8 characters');
//     }
//   }
// }
//
// /// A view that handles the registration form
// class RegistrationView extends View {
//   final form = RegistrationForm();
//
//   @override
//   Future<void> get(EngineContext context) async {
//     await context.html('''
//       <!DOCTYPE html>
//       <html>
//         <head>
//           <title>Register</title>
//           <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
//         </head>
//         <body>
//           <div class="container mt-5">
//             <h1>Register</h1>
//             <form method="post" class="registration-form">
//               ${await form['username'].toHtml()}
//               ${await form['email'].toHtml()}
//               ${await form['password'].toHtml()}
//               ${await form['country'].toHtml()}
//               <button type="submit" class="btn btn-primary mt-3">Register</button>
//             </form>
//           </div>
//         </body>
//       </html>
//     ''');
//   }
//
//   @override
//   Future<void> post(EngineContext context) async {
//     final formData = context.request.body as Map<String, dynamic>;
//     form.data.addAll(formData);
//
//     if (await form.isValid()) {
//       // Process the form data
//       print('Registration data: ${form.cleanedData}');
//       await context.redirect('/registration-success');
//     } else {
//       await context.html('''
//         <!DOCTYPE html>
//         <html>
//           <head>
//             <title>Register</title>
//             <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
//           </head>
//           <body>
//             <div class="container mt-5">
//               <h1>Register</h1>
//               <div class="alert alert-danger">
//                 Please correct the errors below.
//               </div>
//               <form method="post" class="registration-form">
//                 ${await form['username'].render()}
//                 ${await form['email'].render()}
//                 ${await form['password'].render()}
//                 ${await form['country'].render()}
//                 <button type="submit" class="btn btn-primary mt-3">Register</button>
//               </form>
//             </div>
//           </body>
//         </html>
//       ''');
//     }
//   }
// }
//
// void main() async {
//   final app = Engine();
//
//   app.get('/', RegistrationView().get);
//   app.post('/', RegistrationView().post);
//   app.get('/registration-success', (context) {
//     context.html('''
//       <!DOCTYPE html>
//       <html>
//         <head>
//           <title>Registration Success</title>
//           <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
//         </head>
//         <body>
//           <div class="container mt-5">
//             <h1>Registration Successful!</h1>
//             <p>Thank you for registering.</p>
//             <a href="/" class="btn btn-primary">Back to Home</a>
//           </div>
//         </body>
//       </html>
//     ''');
//   });
//
//   await app.serve(port: 3000);
//   print('Server running on http://localhost:3000');
// }
