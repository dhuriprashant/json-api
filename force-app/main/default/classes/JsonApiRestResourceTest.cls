@IsTest
private class JsonApiRestResourceTest {

    @TestSetup
    static void setup() {
        insert new Account(Name = 'Acme', Industry = 'Technology');
    }

    private static RestRequest newRequest(String method, String uri) {
        RestRequest req = new RestRequest();
        req.httpMethod = method;
        req.requestURI = uri;
        RestContext.request = req;
        RestContext.response = new RestResponse();
        return req;
    }

    @IsTest
    static void getCollectionReturnsJsonApiDocument() {
        newRequest('GET', '/services/apexrest/jsonapi/accounts');

        Test.startTest();
        JsonApiRestResource.doGet();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(JsonApiConstants.MEDIA_TYPE,
            RestContext.response.headers.get('Content-Type'));
        String body = RestContext.response.responseBody.toString();
        System.assert(body.contains('"type":"accounts"'), 'body: ' + body);
    }

    @IsTest
    static void getsSingleResourceViaDoGet() {
        Id id = [SELECT Id FROM Account WHERE Name = 'Acme' LIMIT 1].Id;
        newRequest('GET', '/services/apexrest/jsonapi/accounts/' + id);

        JsonApiRestResource.doGet();

        System.assertEquals(200, RestContext.response.statusCode);
        String body = RestContext.response.responseBody.toString();
        System.assert(body.contains('"type":"accounts"'), body);
    }

    @IsTest
    static void getsToManyLinkageViaDoGet() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Acme' LIMIT 1];
        insert new Contact(FirstName = 'Jane', LastName = 'Doe', AccountId = acc.Id);
        newRequest('GET',
            '/services/apexrest/jsonapi/accounts/' + acc.Id + '/relationships/contacts');

        JsonApiRestResource.doGet();

        System.assertEquals(200, RestContext.response.statusCode);
        String body = RestContext.response.responseBody.toString();
        // A to-many linkage document's data is an array of identifier objects.
        System.assert(body.contains('"data":['), body);
    }

    @IsTest
    static void exactMediaTypeAcceptIsAccepted() {
        RestRequest req = newRequest('GET', '/services/apexrest/jsonapi/accounts');
        req.addHeader('Accept', JsonApiConstants.MEDIA_TYPE);

        JsonApiRestResource.doGet();

        System.assertEquals(200, RestContext.response.statusCode);
    }

    @IsTest
    static void unknownTypeRendersErrorDocument() {
        newRequest('GET', '/services/apexrest/jsonapi/widgets');

        JsonApiRestResource.doGet();

        System.assertEquals(404, RestContext.response.statusCode);
        String body = RestContext.response.responseBody.toString();
        System.assert(body.contains('"errors"'), 'body: ' + body);
        System.assert(body.contains('NOT_FOUND'));
    }

    @IsTest
    static void parameterizedAcceptIsNotAcceptable() {
        RestRequest req = newRequest('GET', '/services/apexrest/jsonapi/accounts');
        req.addHeader('Accept', JsonApiConstants.MEDIA_TYPE + ';charset=utf-8');

        JsonApiRestResource.doGet();

        System.assertEquals(406, RestContext.response.statusCode);
    }

    private class CapturingObserver implements JsonApiObserver {
        public JsonApiRequestLog last;
        public void observe(JsonApiRequestLog log) {
            last = log;
        }
    }

    @IsTest
    static void observabilityCapturesSuccessfulRequest() {
        CapturingObserver obs = new CapturingObserver();
        JsonApiObservability.setObserver(obs);
        newRequest('GET', '/services/apexrest/jsonapi/accounts');

        JsonApiRestResource.doGet();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertNotEquals(null, obs.last, 'observer received a log');
        System.assertEquals(200, obs.last.statusCode);
        System.assertEquals('accounts', obs.last.resourceType);
        System.assertEquals('GET', obs.last.method);
        System.assert(obs.last.rows >= 1, 'rows recorded');
        System.assert(obs.last.soqlQueries >= 1, 'soql recorded');
        System.assert(obs.last.durationMs >= 0, 'duration recorded');
    }

    @IsTest
    static void observabilityCapturesError() {
        CapturingObserver obs = new CapturingObserver();
        JsonApiObservability.setObserver(obs);
        newRequest('GET', '/services/apexrest/jsonapi/widgets');

        JsonApiRestResource.doGet();

        System.assertEquals(404, RestContext.response.statusCode);
        System.assertEquals(404, obs.last.statusCode);
        System.assertEquals('NOT_FOUND', obs.last.errorCode);
    }

    private class FakeException extends Exception {}

    @IsTest
    static void internalErrorDoesNotLeakDetails() {
        List<JsonApiError> errors =
            JsonApiRestResource.internalError(new FakeException('SECRET stack trace detail'));

        System.assertEquals(1, errors.size());
        System.assertEquals('500', errors[0].status);
        System.assert(!errors[0].detail.contains('SECRET'), 'must not leak the raw message');
        System.assert(errors[0].detail.contains('Reference:'), 'should include a support reference');
    }

    @IsTest
    static void segmentsAreExtractedAfterBase() {
        List<String> segments = JsonApiRestResource.segmentsOf(
            '/services/apexrest/jsonapi/accounts/001000000000001/contacts');
        System.assertEquals(
            new List<String>{ 'accounts', '001000000000001', 'contacts' }, segments);
    }

    @IsTest
    static void blankUriYieldsNoSegments() {
        System.assertEquals(0, JsonApiRestResource.segmentsOf('').size());
        System.assertEquals(0, JsonApiRestResource.segmentsOf(null).size());
    }
}
