/**
 * Targeted unit tests for the configuration helpers, the deserializer's
 * validation/coercion branches, nested includes and the document model -
 * the paths not exercised by the higher-level service tests.
 */
@IsTest
private class JsonApiCoverageTest {

    @TestSetup
    static void setup() {
        Account a = new Account(Name = 'Acme', Industry = 'Technology');
        insert a;
        insert new Contact(FirstName = 'Jane', LastName = 'Doe', AccountId = a.Id);
    }

    // ---- JsonApiResourceConfig helpers ----

    @IsTest
    static void resourceConfigHelpers() {
        JsonApiResourceConfig cfg = new AccountResourceConfig();
        System.assertEquals('Name', cfg.fieldFor('name'));
        System.assert(cfg.hasAttribute('industry'));
        System.assert(!cfg.hasAttribute('nope'));
        System.assertEquals('name', cfg.getFieldToAttributeMap().get('name'));
        System.assert(cfg.getAttributeFieldNames().contains('Name'));
        System.assert(cfg.hasGroup('financials'));
        System.assert(cfg.attributesForGroups(new Set<String>{ 'financials' }).contains('annualRevenue'));
        System.assertNotEquals(null, cfg.relationshipFor('parent'));
        System.assertEquals(null, cfg.relationshipFor('missing'));
    }

    // ---- Nested include (to-many then to-one) ----

    @IsTest
    static void nestedIncludeResolvesBothLevels() {
        Id acctId = [SELECT Id FROM Account WHERE Name = 'Acme' LIMIT 1].Id;
        JsonApiResponse r = new JsonApiService().handle('GET',
            new List<String>{ 'accounts', acctId },
            new Map<String, String>{ 'include' => 'contacts.account' });

        System.assertEquals(200, r.statusCode);
        Set<String> types = new Set<String>();
        for (JsonApiResourceObject obj : r.document.included) {
            types.add(obj.type);
        }
        System.assert(types.contains('contacts'), 'contacts side-loaded');
        System.assert(types.contains('accounts'), 'nested account side-loaded');
    }

    // ---- Document model helpers ----

    @IsTest
    static void documentAndErrorHelpers() {
        JsonApiDocument doc = JsonApiDocument.ofData(null);
        doc.addIncluded(new JsonApiResourceObject('accounts', '001'));
        System.assertEquals(1, doc.included.size());

        JsonApiError err = new JsonApiError(400, 'X', 'Title', 'Detail')
            .withSource(JsonApiErrorSource.forParameter('sort'));
        JsonApiDocument errDoc = JsonApiDocument.ofErrors(new List<JsonApiError>{ err });
        System.assert(errDoc.toJson().contains('"sort"'));
        System.assertEquals('sort', err.source.parameter);
    }

    // ---- CMDT-driven registration (JsonApiBootstrap) ----

    @IsTest
    static void bootstrapRegistersConfigsFromCmdt() {
        JsonApiRegistry.reset();
        System.assert(JsonApiRegistry.isRegistered('accounts'), 'accounts registered from CMDT');
        System.assert(JsonApiRegistry.isRegistered('contacts'), 'contacts registered from CMDT');
    }

    @IsTest
    static void bootstrapRejectsUnknownApexClass() {
        JsonApiBootstrap.configOverride = new List<JsonApiResource__mdt>{
            new JsonApiResource__mdt(DeveloperName = 'Bad', Apex_Class__c = 'NoSuchClass__X', Is_Active__c = true)
        };
        JsonApiRegistry.reset();
        try {
            JsonApiRegistry.forType('accounts');
            System.assert(false, 'expected configuration exception');
        } catch (JsonApiException e) {
            System.assertEquals(500, e.httpStatus);
        }
    }

    @IsTest
    static void bootstrapRejectsNonConfigClass() {
        // A real class that exists but does not extend JsonApiResourceConfig.
        JsonApiBootstrap.configOverride = new List<JsonApiResource__mdt>{
            new JsonApiResource__mdt(DeveloperName = 'Bad', Apex_Class__c = 'JsonApiConstants', Is_Active__c = true)
        };
        JsonApiRegistry.reset();
        try {
            JsonApiRegistry.forType('accounts');
            System.assert(false, 'expected configuration exception');
        } catch (JsonApiException e) {
            System.assertEquals(500, e.httpStatus);
        }
    }
}
