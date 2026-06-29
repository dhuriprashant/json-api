/**
 * Sink for per-request telemetry. Implement this to route {@link JsonApiRequestLog}
 * wherever you need it — `System.debug`, a Platform Event, a custom logging object,
 * or an external service — and register it via {@link JsonApiObservability}.
 */
public interface JsonApiObserver {
    void observe(JsonApiRequestLog log);
}
