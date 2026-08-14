#include <glib.h>

#include <cstdio>
#include <cstring>

#include "my_application.h"

namespace {

// Lines that GTK, GDK and ATK log from inside our process on every launch. They
// say nothing to a user and nothing to us — each is an upstream defect we cannot
// act on — and no environment variable suppresses them (NO_AT_BRIDGE=1 and
// GTK_A11Y=none were both tested and are no-ops). Matched by domain, level and
// text so that every other diagnostic from those same domains stays visible.
struct KnownNoise {
  const char* domain;
  GLogLevelFlags level;
  const char* substring;
};

const KnownNoise kKnownNoise[] = {
    // "Atk-CRITICAL **: atk_socket_embed: assertion 'plug_id != NULL' failed"
    // Engine a11y bug; fires once while the window is being embedded.
    {"Atk", G_LOG_LEVEL_CRITICAL, "atk_socket_embed"},

    // "Gdk-Message: Unable to load  from the cursor theme"
    // The two spaces are not a typo: the engine asks GDK for a cursor under an
    // empty name, GDK does not find it and falls back to the default one. The
    // empty name is part of the pattern, so a genuinely missing cursor is still
    // reported.
    {"Gdk", G_LOG_LEVEL_MESSAGE, "Unable to load  from the cursor theme"},

    // "Gdk-WARNING **: Error converting selection from UTF8_STRING"
    // GdkClipboard; can repeat by the hundreds while a text field has focus.
    {"Gdk", G_LOG_LEVEL_WARNING, "Error converting selection"},
};

bool is_known_noise(const char* domain, GLogLevelFlags level,
                    const char* message) {
  for (const KnownNoise& noise : kKnownNoise) {
    if ((level & G_LOG_LEVEL_MASK) == noise.level &&
        g_strcmp0(domain, noise.domain) == 0 &&
        strstr(message, noise.substring) != nullptr) {
      return true;
    }
  }
  return false;
}

// Swallows the lines above and hands everything else to GLib's own writer, which
// keeps the usual behaviour (stderr/stdout split, journald, fatal levels).
//
// This has to be a writer rather than a g_log_set_handler() per domain: GDK logs
// through the structured API (g_log_structured), which does not consult domain
// handlers at all — measured, the ATK line disappeared with handlers and the GDK
// one did not. Legacy g_log() callers reach the writer too, so one hook covers
// both APIs.
GLogWriterOutput log_writer(GLogLevelFlags level, const GLogField* fields,
                            gsize n_fields, gpointer user_data) {
  const char* domain = nullptr;
  const char* message = nullptr;
  for (gsize i = 0; i < n_fields; i++) {
    // Only length == -1 marks a NUL-terminated string; other fields may be
    // binary.
    if (fields[i].length != -1) {
      continue;
    }
    if (strcmp(fields[i].key, "GLIB_DOMAIN") == 0) {
      domain = static_cast<const char*>(fields[i].value);
    } else if (strcmp(fields[i].key, "MESSAGE") == 0) {
      message = static_cast<const char*>(fields[i].value);
    }
  }

  if (message != nullptr && is_known_noise(domain, level, message)) {
    return G_LOG_WRITER_HANDLED;
  }
  return g_log_writer_default(level, fields, n_fields, user_data);
}

}  // namespace

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

  // Must run before GTK is touched: GLib only accepts one writer, and it has to
  // be in place before the first message is logged.
  g_log_set_writer_func(log_writer, nullptr, nullptr);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
