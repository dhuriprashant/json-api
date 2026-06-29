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

    @IsTest
    static void includePathsWithSharedPrefixAreCoalesced() {
        Id acctId = [SELECT Id FROM Account WHERE Name = 'Acme' LIMIT 1].Id;

        // 'contacts' appears as both a leaf and the prefix of 'contacts.account';
        // the resolver must fetch contacts ONCE, not once per path.
        Integer before = Limits.getQueries();
        JsonApiResponse r = new JsonApiService().handle('GET',
            new List<String>{ 'accounts', acctId },
            new Map<String, String>{ 'include' => 'contacts,contacts.account' });
        Integer used = Limits.getQueries() - before;

        System.assertEquals(200, r.statusCode);
        // primary account + contacts + contacts' account = 3 queries (no duplicate contacts query).
        System.assert(used <= 3, 'expected <=3 SOQL, got ' + used);
        Set<String> types = new Set<String>();
        for (JsonApiResourceObject obj : r.document.included) {
            types.add(obj.type);
        }
        System.assert(types.contains('contacts') && types.contains('accounts'));
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
    static void bootstrapSkipsBadRecordButLoadsGoodOnes() {
        // A bad record alongside a healthy one must not take the good one down.
        JsonApiBootstrap.configOverride = new List<JsonApiResource__mdt>{
            new JsonApiResource__mdt(DeveloperName = 'Accounts', Apex_Class__c = 'AccountResourceConfig', Is_Active__c = true),
            new JsonApiResource__mdt(DeveloperName = 'Bad', Apex_Class__c = 'NoSuchClass__X', Is_Active__c = true)
        };
        JsonApiRegistry.reset();

        System.assert(JsonApiRegistry.isRegistered('accounts'), 'good record loaded despite a bad sibling');
        Map<String, String> errors = JsonApiBootstrap.getRegistrationErrors();
        System.assert(errors.containsKey('Bad'), 'bad record captured: ' + errors);
    }

    @IsTest
    static void bootstrapSkipsUnknownApexClassWithCleanNotFound() {
        JsonApiBootstrap.configOverride = new List<JsonApiResource__mdt>{
            new JsonApiResource__mdt(DeveloperName = 'Bad', Apex_Class__c = 'NoSuchClass__X', Is_Active__c = true)
        };
        JsonApiRegistry.reset();

        // The skipped type resolves to a 404, not a 500.
        try {
            JsonApiRegistry.forType('accounts');
            System.assert(false, 'expected not-found');
        } catch (JsonApiException e) {
            System.assertEquals(404, e.httpStatus);
        }
        System.assert(JsonApiBootstrap.getRegistrationErrors().containsKey('Bad'));
    }

    @IsTest
    static void bootstrapSkipsNonConfigClass() {
        // A real class that exists but does not extend JsonApiResourceConfig.
        JsonApiBootstrap.configOverride = new List<JsonApiResource__mdt>{
            new JsonApiResource__mdt(DeveloperName = 'Bad', Apex_Class__c = 'JsonApiConstants', Is_Active__c = true)
        };
        JsonApiRegistry.reset();
        JsonApiRegistry.isRegistered('accounts'); // force lazy initialization

        System.assert(JsonApiBootstrap.getRegistrationErrors().containsKey('Bad'),
            'non-config class recorded as a registration error');
    }
}
