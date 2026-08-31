import 'package:flutter/material.dart';

/// A global way to show a SnackBar from services that don't have a
/// BuildContext handy — e.g. FavouritesService.toggleFuel/toggleEv are
/// called from many different screens, so routing an error back to
/// "whichever screen happened to call it" isn't practical. Wired up via
/// MaterialApp's `scaffoldMessengerKey` in main.dart.
class AppMessenger {
  static final GlobalKey<ScaffoldMessengerState> key = GlobalKey<ScaffoldMessengerState>();

  static void showError(String message) {
    key.currentState?.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }
}
