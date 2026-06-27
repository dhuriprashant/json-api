/**
 * Central lookup of all registered {@link JsonApiResourceConfig}s, keyed by
 * JSON:API type and by SObjectType. {@link JsonApiBootstrap} populates it on
 * first use.
 */
public with sharing class JsonApiRegistry {
    private static Map<String, JsonApiResourceConfig> byType =
        new Map<String, JsonApiResourceConfig>();
    private static Map<String, JsonApiResourceConfig> bySObject =
        new Map<String, JsonApiResourceConfig>();
    private static Boolean initialized = false;

    public static void register(JsonApiResourceConfig config) {
        byType.put(config.getType().toLowerCase(), config);
        bySObject.put(
            String.valueOf(config.getSObjectType()).toLowerCase(),
            config
        );
    }

    /** Ensures the registry has been populated before any lookup. */
    private static void ensureInitialized() {
        if (!initialized) {
            initialized = true;
            JsonApiBootstrap.registerAll();
        }
    }

    /** Returns the config for a JSON:API type, or throws 404 if unknown. */
    public static JsonApiResourceConfig forType(String type) {
        ensureInitialized();
        JsonApiResourceConfig config = byType.get(
            type == null ? null : type.toLowerCase()
        );
        if (config == null) {
            throw JsonApiException.notFound('No resource is registered for type "' + type + '".');
        }
        return config;
    }

    public static JsonApiResourceConfig forSObjectType(Schema.SObjectType sObjType) {
        ensureInitialized();
        return bySObject.get(String.valueOf(sObjType).toLowerCase());
    }

    public static Boolean isRegistered(String type) {
        ensureInitialized();
        return byType.containsKey(type == null ? null : type.toLowerCase());
    }

    /** Test hook: clears the registry and forces re-initialization. */
    @TestVisible
    private static void reset() {
        byType.clear();
        bySObject.clear();
        initialized = false;
    }
}
