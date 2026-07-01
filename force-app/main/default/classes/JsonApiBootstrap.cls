/**
 * Registers resource configs from the {@code JsonApiResource__mdt} Custom
 * Metadata Type. Each active record names an Apex class that extends
 * {@link JsonApiResourceConfig}; this loader instantiates it via reflection and
 * registers it.
 *
 * To expose a new resource you add a CMDT record (Setup → Custom Metadata Types
 * → JSON:API Resource → Manage Records, or deploy a {@code *.md-meta.xml} file) —
 * no Apex change is required here.
 */
public with sharing class JsonApiBootstrap {

    /** Test hook: when set, used instead of querying the CMDT. */
    @TestVisible
    private static List<JsonApiResource__mdt> configOverride;

    /** DeveloperName -> reason, for any CMDT record that failed to load. */
    private static Map<String, String> registrationErrors = new Map<String, String>();

    public static void registerAll() {
        registrationErrors = new Map<String, String>();
        for (JsonApiResource__mdt record : loadConfigRecords()) {
            try {
                JsonApiResourceConfig config = instantiate(record.Apex_Class__c, record.DeveloperName);
                // A record may expose the same config under several versions.
                for (String version : versionsFor(record, config)) {
                    JsonApiRegistry.registerFor(version, config);
                }
            } catch (Exception e) {
                // One misconfigured record must not take down every endpoint:
                // skip it, remember why, and keep loading the rest. A later
                // lookup for the skipped type then returns a clean 404 instead
                // of a 500 that also breaks every healthy resource.
                registrationErrors.put(record.DeveloperName, e.getMessage());
                System.debug(LoggingLevel.ERROR,
                    'JSON:API: skipping resource "' + record.DeveloperName + '" - ' + e.getMessage());
            }
        }
    }

    /**
     * DeveloperName -> failure reason for every CMDT record that could not be
     * loaded on the last {@link #registerAll}. Empty when all records loaded.
     * Useful for a health check or admin diagnostics.
     */
    public static Map<String, String> getRegistrationErrors() {
        return registrationErrors.clone();
    }

    private static List<JsonApiResource__mdt> loadConfigRecords() {
        if (configOverride != null) {
            return configOverride;
        }
        return [
            SELECT DeveloperName, Apex_Class__c, Versions__c
            FROM JsonApiResource__mdt
            WHERE Is_Active__c = true
        ];
    }

    /**
     * The versions a record is exposed under: the comma-separated {@code Versions__c}
     * when set, otherwise the config's own {@code getVersion()} (defaults to v1).
     */
    private static List<String> versionsFor(JsonApiResource__mdt record, JsonApiResourceConfig config) {
        List<String> versions = new List<String>();
        if (String.isNotBlank(record.Versions__c)) {
            for (String token : record.Versions__c.split(',')) {
                String v = token.trim();
                if (String.isNotBlank(v)) {
                    versions.add(v);
                }
            }
        }
        if (versions.isEmpty()) {
            versions.add(config.getVersion());
        }
        return versions;
    }

    private static JsonApiResourceConfig instantiate(String className, String developerName) {
        Type configType = Type.forName(className);
        if (configType == null) {
            throw JsonApiException.internal(
                'JSON:API resource "' + developerName + '" references unknown Apex class "' +
                className + '".');
        }
        Object instance;
        try {
            instance = configType.newInstance();
        } catch (Exception e) {
            throw JsonApiException.internal(
                'Could not instantiate "' + className + '" - it needs a public no-argument constructor.');
        }
        if (!(instance instanceof JsonApiResourceConfig)) {
            throw JsonApiException.internal(
                'Apex class "' + className + '" does not extend JsonApiResourceConfig.');
        }
        return (JsonApiResourceConfig) instance;
    }
}
