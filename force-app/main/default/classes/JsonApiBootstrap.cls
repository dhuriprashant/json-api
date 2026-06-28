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

    public static void registerAll() {
        for (JsonApiResource__mdt record : loadConfigRecords()) {
            JsonApiRegistry.register(instantiate(record.Apex_Class__c, record.DeveloperName));
        }
    }

    private static List<JsonApiResource__mdt> loadConfigRecords() {
        if (configOverride != null) {
            return configOverride;
        }
        return [
            SELECT DeveloperName, Apex_Class__c
            FROM JsonApiResource__mdt
            WHERE Is_Active__c = true
        ];
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
