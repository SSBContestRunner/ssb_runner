/// Implementation reported by the web database connection.
///
/// Written by `database_connection_web.dart` when drift chooses a storage
/// backend; read by the status and health probes.
String? webDatabaseImplementation;

/// False when drift had to fall back to an in-memory database.
bool webDatabasePersistent = true;
