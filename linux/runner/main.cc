#include <cstdio>
#include <cstring>

#include "my_application.h"

int main(int argc, char** argv) {
  // `knitcalc --version` must answer without touching GTK: package managers
  // (mise's registry test, our release smoke check) run it on machines with no
  // display. Handled here because Dart's main() only runs after the window is
  // created. KNITCALC_VERSION is the full pubspec version ("1.2.3+45").
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--version") == 0) {
      printf("knitcalc %s\n", KNITCALC_VERSION);
      return 0;
    }
  }

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
