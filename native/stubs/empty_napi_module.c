#include <stddef.h>

// Minimal N-API types needed for a no-op module registration.
typedef struct napi_env__ *napi_env;
typedef struct napi_value__ *napi_value;

typedef napi_value (*napi_addon_register_func)(napi_env env, napi_value exports);

// These modules (cf-prefs, registry-js, windows-focus-assist,
// macos-notification-state) are macOS/Windows-only and are no-ops on Linux.
// The real Slack builds export nothing useful on Linux, so a minimal module
// that returns `exports` unchanged is a faithful arm64 stand-in.
napi_value napi_register_module_v1(napi_env env, napi_value exports) {
    return exports;
}
