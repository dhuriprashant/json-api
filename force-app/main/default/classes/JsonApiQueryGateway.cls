/**
 * The single seam between the framework and the database. All reads go through
 * this interface, which lets the service and include resolver be unit-tested with
 * in-memory rows (no DML, no org-trigger coupling) by swapping in a test double.
 *
 * The production implementation ({@link JsonApiUserModeGateway}) runs every query
 * in AccessLevel.USER_MODE so CRUD/FLS is enforced for the running user.
 */
public interface JsonApiQueryGateway {
    /** Runs a parameterized SOQL query and returns the rows. */
    List<SObject> query(String soql, Map<String, Object> binds);

    /** Runs a parameterized SOQL COUNT() query and returns the total. */
    Integer countQuery(String soql, Map<String, Object> binds);
}
