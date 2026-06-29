/**
 * Default {@link JsonApiObserver}: writes one structured JSON line per request to
 * the debug log. Errors log at ERROR level, successes at INFO — so they're easy to
 * grep/parse. Swap in a Platform Event or custom-object observer for durable
 * production telemetry via {@link JsonApiObservability#setObserver}.
 */
public with sharing class JsonApiDebugObserver implements JsonApiObserver {
    public void observe(JsonApiRequestLog log) {
        LoggingLevel level = log.isError() ? LoggingLevel.ERROR : LoggingLevel.INFO;
        System.debug(level, 'JSONAPI ' + JSON.serialize(log, true));
    }
}
