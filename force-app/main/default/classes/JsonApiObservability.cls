/**
 * Holds the active {@link JsonApiObserver} and emits request telemetry to it.
 * Defaults to {@link JsonApiDebugObserver}; call {@link #setObserver} (e.g. from a
 * one-time bootstrap or a test) to route telemetry elsewhere.
 *
 * Emission never throws: a misbehaving observer must not break the API response.
 */
public with sharing class JsonApiObservability {

    @TestVisible
    private static JsonApiObserver observer = new JsonApiDebugObserver();

    public static void setObserver(JsonApiObserver newObserver) {
        if (newObserver != null) {
            observer = newObserver;
        }
    }

    public static void emit(JsonApiRequestLog log) {
        try {
            observer.observe(log);
        } catch (Exception e) {
            // Observability must be best-effort — log and move on.
            System.debug(LoggingLevel.ERROR, 'JSON:API observer failed: ' + e.getMessage());
        }
    }
}
