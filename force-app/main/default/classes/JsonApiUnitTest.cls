/**
 * DML-free unit tests for the read/serialize/include pipeline. By injecting an
 * in-memory {@link JsonApiTestQueryGateway}, these exercise the framework with
 * fabricated SObjects — no inserts, so they run fast and are immune to org
 * triggers/validation rules. The DML-backed integration tests
 * ({@link JsonApiServiceTest} etc.) still cover the real SOQL + USER_MODE paths.
 */
@IsTest
private class JsonApiUnitTest {

    private static Id fakeId(Schema.SObjectType type, Integer n) {
        return Id.valueOf(type.getDescribe().getKeyPrefix() +
            String.valueOf(n).leftPad(12).replace(' ', '0'));
    }

    private class RecordingObserver implements JsonApiObserver {
        public JsonApiRequestLog last;
        public void observe(JsonApiRequestLog log) {
            last = log;
        }
    }

    private class ThrowingObserver implements JsonApiObserver {
        public void observe(JsonApiRequestLog log) {
            throw new ObserverException('boom');
        }
    }

    private class ObserverException extends Exception {}

    @IsTest
    static void observabilityEmitsToObserverAndSwallowsFailures() {
        RecordingObserver rec = new RecordingObserver();
        JsonApiObservability.setObserver(rec);

        JsonApiRequestLog log = new JsonApiRequestLog();
        log.method = 'GET';
        log.statusCode = 200;
        log.resourceType = 'accounts';
        JsonApiObservability.emit(log);

        System.assertEquals(200, rec.last.statusCode);
        System.assertEquals('accounts', rec.last.resourceType);

        // A misbehaving observer must never propagate out of emit().
        JsonApiObservability.setObserver(new ThrowingObserver());
        JsonApiObservability.emit(log);
    }

    @IsTest
    static void debugObserverHandlesSuccessAndError() {
        JsonApiRequestLog ok = new JsonApiRequestLog();
        ok.statusCode = 200;
        JsonApiRequestLog bad = new JsonApiRequestLog();
        bad.statusCode = 500;

        new JsonApiDebugObserver().observe(ok);   // INFO branch
        new JsonApiDebugObserver().observe(bad);  // ERROR branch
        System.assertEquals(false, ok.isError());
        System.assertEquals(true, bad.isError());
    }

    @IsTest
    static void serializesSingleResourceWithoutDml() {
        Id accId = fakeId(Account.SObjectType, 1);
        Account acc = new Account(Name = 'Acme', Industry = 'Technology');
        acc.Id = accId;

        JsonApiTestQueryGateway mock =
            new JsonApiTestQueryGateway().seed(Account.SObjectType, new List<SObject>{ acc });

        JsonApiResponse r = new JsonApiService(mock).handle(
            'GET', new List<String>{ 'accounts', accId }, new Map<String, String>());

        System.assertEquals(200, r.statusCode);
        JsonApiResourceObject obj = (JsonApiResourceObject) r.document.data;
        System.assertEquals('accounts', obj.type);
        System.assertEquals(accId, (Id) obj.id);
        System.assertEquals('Acme', obj.attributes.get('name'));
        System.assertEquals(0, Limits.getDmlStatements(), 'no DML expected');
        System.assertEquals(1, mock.queryCountFor(Account.SObjectType));
    }

    @IsTest
    static void serializesCollectionWithMetaAndLinks() {
        Account a1 = new Account(Name = 'Acme');
        a1.Id = fakeId(Account.SObjectType, 1);
        Account a2 = new Account(Name = 'Globex');
        a2.Id = fakeId(Account.SObjectType, 2);

        JsonApiTestQueryGateway mock =
            new JsonApiTestQueryGateway().seed(Account.SObjectType, new List<SObject>{ a1, a2 });
        mock.countValue = 2;

        JsonApiResponse r = new JsonApiService(mock).handle(
            'GET', new List<String>{ 'accounts' }, new Map<String, String>());

        List<JsonApiResourceObject> data = (List<JsonApiResourceObject>) r.document.data;
        System.assertEquals(2, data.size());
        System.assertEquals(2, (Integer) r.document.meta.get('total'));
        System.assert(r.document.links.containsKey('first'));
        System.assertEquals(0, Limits.getDmlStatements());
    }

    @IsTest
    static void sideLoadsToManyIncludeWithoutDml() {
        Id accId = fakeId(Account.SObjectType, 1);
        Id conId = fakeId(Contact.SObjectType, 1);
        Account acc = new Account(Name = 'Acme');
        acc.Id = accId;
        Contact con = new Contact(LastName = 'Doe', AccountId = accId);
        con.Id = conId;

        JsonApiTestQueryGateway mock = new JsonApiTestQueryGateway()
            .seed(Account.SObjectType, new List<SObject>{ acc })
            .seed(Contact.SObjectType, new List<SObject>{ con });

        JsonApiResponse r = new JsonApiService(mock).handle(
            'GET', new List<String>{ 'accounts', accId },
            new Map<String, String>{ 'include' => 'contacts' });

        System.assertEquals(200, r.statusCode);
        System.assertEquals(1, r.document.included.size());
        System.assertEquals('contacts', r.document.included[0].type);
        System.assertEquals(conId, (Id) r.document.included[0].id);
        System.assertEquals(1, mock.queryCountFor(Contact.SObjectType), 'contacts fetched once');
        System.assertEquals(0, Limits.getDmlStatements());
    }

    @IsTest
    static void sideLoadsToOneIncludeWithoutDml() {
        Id accId = fakeId(Account.SObjectType, 1);
        Id conId = fakeId(Contact.SObjectType, 1);
        Account acc = new Account(Name = 'Parent Co');
        acc.Id = accId;
        Contact con = new Contact(LastName = 'Doe', AccountId = accId);
        con.Id = conId;

        JsonApiTestQueryGateway mock = new JsonApiTestQueryGateway()
            .seed(Contact.SObjectType, new List<SObject>{ con })
            .seed(Account.SObjectType, new List<SObject>{ acc });

        JsonApiResponse r = new JsonApiService(mock).handle(
            'GET', new List<String>{ 'contacts', conId },
            new Map<String, String>{ 'include' => 'account' });

        JsonApiResourceObject obj = (JsonApiResourceObject) r.document.data;
        System.assert(obj.relationships.containsKey('account'));
        System.assertEquals(1, r.document.included.size());
        System.assertEquals('accounts', r.document.included[0].type);
        System.assertEquals(0, Limits.getDmlStatements());
    }
}
