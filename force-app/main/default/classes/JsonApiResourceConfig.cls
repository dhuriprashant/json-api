/**
 * Maps a JSON:API resource `type` onto a Salesforce SObject and declares which
 * fields are exposed as attributes and how relationships are traversed.
 *
 * Attributes are organized into named groups. The {@link #BASE_GROUP} ("base")
 * is always returned; any other group is returned only when the client opts in
 * via the `extend` query parameter (e.g. `?extend=financials,contactInfo`). This
 * lets a resource keep its default payload lean while still exposing richer
 * fields on demand.
 *
 * Subclass this for each SObject you want to expose, then register it. Subclasses
 * must implement {@link #getType}, {@link #getSObjectType} and
 * {@link #getAttributeGroups}; everything else has a sensible default.
 */
public abstract class JsonApiResourceConfig {

    /** The always-returned attribute group. */
    public static final String BASE_GROUP = 'base';

    /** The JSON:API `type` for this resource, e.g. "accounts". */
    public abstract String getType();

    /** The SObjectType this resource is backed by, e.g. Account.SObjectType. */
    public abstract Schema.SObjectType getSObjectType();

    /**
     * Attribute groups: group name -> ( JSON:API attribute name -> SObject field
     * API name ). Must contain a {@link #BASE_GROUP} entry. Example:
     * <pre>
     * {
     *   'base'       => { 'name' => 'Name', 'industry' => 'Industry' },
     *   'financials' => { 'annualRevenue' => 'AnnualRevenue' }
     * }
     * </pre>
     * The resource `id` is handled separately and must NOT appear here.
     */
    public abstract Map<String, Map<String, String>> getAttributeGroups();

    /** Relationship name -> definition. Empty by default. */
    public virtual Map<String, JsonApiRelationshipDef> getRelationships() {
        return new Map<String, JsonApiRelationshipDef>();
    }

    // ---------------------------------------------------------------------
    // Derived helpers (do not override)
    // ---------------------------------------------------------------------

    /** The flattened union of every group: attribute name -> field API name. */
    public Map<String, String> getAttributeMap() {
        Map<String, String> all = new Map<String, String>();
        for (Map<String, String> grp : getAttributeGroups().values()) {
            all.putAll(grp);
        }
        return all;
    }

    /** Whether a named attribute group exists on this resource. */
    public Boolean hasGroup(String groupName) {
        return getAttributeGroups().containsKey(groupName);
    }

    /**
     * Attribute names to expose for the given `extend` groups: always the base
     * group, plus each requested group that exists on this resource. Unknown
     * groups are ignored here (the parser validates them against the primary
     * resource), so this is safe to apply to related resources of other types.
     */
    public Set<String> attributesForGroups(Set<String> extendGroups) {
        Map<String, Map<String, String>> groups = getAttributeGroups();
        Set<String> names = new Set<String>();
        if (groups.containsKey(BASE_GROUP)) {
            names.addAll(groups.get(BASE_GROUP).keySet());
        }
        if (extendGroups != null) {
            for (String g : extendGroups) {
                if (groups.containsKey(g)) {
                    names.addAll(groups.get(g).keySet());
                }
            }
        }
        return names;
    }

    /**
     * The attribute names to expose for a request. A sparse fieldset
     * (`fields[type]`) takes precedence when present; otherwise the base group
     * plus any `extend` groups apply.
     */
    public Set<String> resolveAttributeNames(JsonApiQueryOptions options) {
        if (options != null && options.hasSparseFieldsFor(getType())) {
            Set<String> result = new Set<String>();
            for (String attr : options.sparseFieldsFor(getType())) {
                if (hasAttribute(attr)) {
                    result.add(attr);
                }
            }
            return result;
        }
        return attributesForGroups(options == null ? null : options.extendGroups);
    }

    /** Reverse of getAttributeMap: SObject field API name -> attribute name. */
    public Map<String, String> getFieldToAttributeMap() {
        Map<String, String> reverse = new Map<String, String>();
        for (String attr : getAttributeMap().keySet()) {
            reverse.put(getAttributeMap().get(attr).toLowerCase(), attr);
        }
        return reverse;
    }

    /** All SObject field API names backing this resource's attributes. */
    public Set<String> getAttributeFieldNames() {
        return new Set<String>(getAttributeMap().values());
    }

    public Boolean hasAttribute(String attributeName) {
        return getAttributeMap().containsKey(attributeName);
    }

    public String fieldFor(String attributeName) {
        return getAttributeMap().get(attributeName);
    }

    public JsonApiRelationshipDef relationshipFor(String name) {
        return getRelationships().get(name);
    }
}
