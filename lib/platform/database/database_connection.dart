/// Opens the platform database connection.
///
/// The implementation is chosen by conditional import, so the schema,
/// migrations and the rest of the app are identical on both targets.
library;

export 'database_connection_native.dart'
    if (dart.library.js_interop) 'database_connection_web.dart';
