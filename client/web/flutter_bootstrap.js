{{flutter_js}}
{{flutter_build_config}}

// Substitutes to the version hash for offline-first release builds, and to null
// otherwise. Kept conditional below so debug runs don't register a service
// worker, matching Flutter's default bootstrap.
const swVersion = {{flutter_service_worker_version}};

// Flutter's loader allow-lists Wasm to blink only — gecko and webkit default to
// false in defaultWasmSupport — so a --wasm build refuses to start in Firefox
// even though it supports WasmGC. Debug --wasm emits no JS fallback, so the
// symptom is a blank page rather than a downgrade.
//
// Opt gecko in for local runs only. Prod keeps whatever upstream decides, so
// Firefox users get the dart2js/canvaskit fallback until Flutter enables gecko
// itself — at which point this override becomes a no-op.
const isLocal = location.hostname === 'localhost' || location.hostname === '127.0.0.1';

_flutter.loader.load({
  ...(swVersion ? {serviceWorkerSettings: {serviceWorkerVersion: swVersion}} : {}),
  ...(isLocal ? {config: {wasmAllowList: {gecko: true}, verboseBuildSelection: true}} : {}),
});
