/**
 * The parsed, validated representation of the JSON:API query parameters that
 * shape a fetch: `include`, sparse `fields[TYPE]`, `sort`, `page[...]` and
 * `filter[...]`.
 * @see https://jsonapi.org/format/#fetching
 */
public class JsonApiQueryOptions {

    /** A single sort directive: a field and its direction.
     *  (Named SortField because "Sort" is a reserved identifier in Apex.) */
    public class SortField {
        public String attribute;
        public Boolean ascending;
        public SortField(String attribute, Boolean ascending) {
            this.attribute = attribute;
            this.ascending = ascending;
        }
    }

    /** Relationship paths to include, e.g. ['account', 'contacts']. */
    public List<String> includePaths = new List<String>();

    /** type -> requested attribute names (sparse fieldsets). */
    public Map<String, Set<String>> sparseFields = new Map<String, Set<String>>();

    /** Extra attribute groups requested via `extend` (the base group is implicit). */
    public Set<String> extendGroups = new Set<String>();

    public List<SortField> sorts = new List<SortField>();

    /** filter attribute name -> value (equality). */
    public Map<String, String> filters = new Map<String, String>();

    public Integer pageSize = JsonApiConstants.DEFAULT_PAGE_SIZE;
    public Integer pageOffset = 0;
    /** Present only for page[number] pagination; null for offset pagination. */
    public Integer pageNumber;

    public Boolean hasSparseFieldsFor(String type) {
        return sparseFields.containsKey(type == null ? null : type.toLowerCase());
    }

    public Set<String> sparseFieldsFor(String type) {
        return sparseFields.get(type == null ? null : type.toLowerCase());
    }
}
