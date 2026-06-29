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

    /**
     * A single filter directive: an attribute, a comparison operator and the raw
     * (uncoerced) value. The builder coerces the value to the field's type and
     * renders the SOQL clause. The operator defaults to `eq`.
     */
    public class FilterCondition {
        public String attribute;
        public String operator;
        public String rawValue;
        public FilterCondition(String attribute, String operator, String rawValue) {
            this.attribute = attribute;
            this.operator = operator;
            this.rawValue = rawValue;
        }
    }

    /** Relationship paths to include, e.g. ['account', 'contacts']. */
    public List<String> includePaths = new List<String>();

    /** type -> requested attribute names (sparse fieldsets). */
    public Map<String, Set<String>> sparseFields = new Map<String, Set<String>>();

    /** Extra attribute groups requested via `extend` (the base group is implicit). */
    public Set<String> extendGroups = new Set<String>();

    public List<SortField> sorts = new List<SortField>();

    /** Filter directives, AND-ed together. Multiple conditions may target the
     *  same attribute (e.g. a gt/lt range). */
    public List<FilterCondition> filters = new List<FilterCondition>();

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
