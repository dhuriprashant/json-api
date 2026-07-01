/**
 * Central lookup of all registered {@link JsonApiResourceConfig}s, keyed by
 * (version, JSON:API type). {@link JsonApiBootstrap} populates it on first use.
 * The same type may be registered under several versions (e.g. v1/accounts and
 * v2/accounts), each backed by its own config class.
 */
public with sharing class JsonApiRegistry {
    private static Map<String, JsonApiResourceConfig> byKey =
        new Map<String, JsonApiResourceConfig>();
    private static Boolean initialized = false;

    /** Composite key: lowercased "version/type". */
    private static String keyOf(String version, String type) {
        return (version == null ? '' : version.toLowerCase()) + '/' +
               (type == null ? '' : type.toLowerCase());
    }

    /** Registers a config under its own {@code getVersion()}. */
    public static void register(JsonApiResourceConfig config) {
        registerFor(config.getVersion(), config);
    }

    /** Registers a config under an explicit version (a config may serve several). */
    public static void registerFor(String version, JsonApiResourceConfig config) {
        byKey.put(keyOf(version, config.getType()), config);
    }

    /** Ensures the registry has been populated before any lookup. */
    private static void ensureInitialized() {
        if (!initialized) {
            initialized = true;
            JsonApiBootstrap.registerAll();
        }
    }

    /** Returns the config for a (version, type), or throws 404 if unknown. */
    public static JsonApiResourceConfig forType(String version, String type) {
        ensureInitialized();
        JsonApiResourceConfig config = byKey.get(keyOf(version, type));
        if (config == null) {
            throw JsonApiException.notFound(
                'No resource is registered for type "' + type + '" in version "' + version + '".');
        }
        return config;
    }

    public static Boolean isRegistered(String version, String type) {
        ensureInitialized();
        return byKey.containsKey(keyOf(version, type));
    }

    /** Sorted "version/type" keys of every successfully registered resource.
     *  Forces initialization, so callers also see any registration errors. */
    public static List<String> registeredTypes() {
        ensureInitialized();
        List<String> keys = new List<String>(byKey.keySet());
        keys.sort();
        return keys;
    }

    /** Test hook: clears the registry and forces re-initialization. */
    @TestVisible
    private static void reset() {
        byKey.clear();
        initialized = false;
    }
}
