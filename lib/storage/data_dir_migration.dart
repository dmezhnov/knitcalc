/// Moves the per-user data directory from a previous location to the current one
/// when the app's identity changes. Only the dart:io (desktop/mobile) variant
/// does real work — see [data_dir_migration_io.dart]; on web it is a no-op.
///
/// Needed because on Windows path_provider derives the app-support directory
/// (`%APPDATA%\<CompanyName>\<ProductName>`) from the executable's version-info
/// resource (windows/runner/Runner.rc). Renaming CompanyName from the template
/// `com.example` to `dmezhnov` shifts that folder, so an existing install's
/// saved projects (shared_preferences.json) and sign-in (auth_session.json)
/// must be carried over once.
library;

export 'data_dir_migration_stub.dart'
    if (dart.library.io) 'data_dir_migration_io.dart';
