/**
 * In-memory {@link JsonApiQueryGateway} for unit tests. Seed it with rows per
 * SObjectType; `query()` returns the seeded rows for the object named in the
 * SOQL `FROM` clause (it ignores the WHERE — the test controls exactly what each
 * object returns). It also records every SOQL string so tests can assert on
 * query shape/count without touching the database.
 */
@IsTest
public class JsonApiTestQueryGateway implements JsonApiQueryGateway {

    private final Map<String, List<SObject>> rowsByObject = new Map<String, List<SObject>>();
    /** Every SOQL string passed to query()/countQuery(), in order. */
    public final List<String> queries = new List<String>();
    /** Value returned by countQuery(). */
    public Integer countValue = 0;

    public JsonApiTestQueryGateway seed(Schema.SObjectType type, List<SObject> rows) {
        rowsByObject.put(String.valueOf(type).toLowerCase(), rows);
        return this;
    }

    public List<SObject> query(String soql, Map<String, Object> binds) {
        queries.add(soql);
        List<SObject> rows = rowsByObject.get(objectOf(soql));
        return rows == null ? new List<SObject>() : rows;
    }

    public Integer countQuery(String soql, Map<String, Object> binds) {
        queries.add(soql);
        return countValue;
    }

    /** Number of recorded queries against a given object (case-insensitive). */
    public Integer queryCountFor(Schema.SObjectType type) {
        String name = String.valueOf(type).toLowerCase();
        Integer n = 0;
        for (String q : queries) {
            if (objectOf(q) == name) {
                n++;
            }
        }
        return n;
    }

    /** Extracts the object name following the first " FROM " token. */
    private String objectOf(String soql) {
        String afterFrom = soql.substringAfter(' FROM ').trim();
        return afterFrom.split(' ')[0].toLowerCase();
    }
}
