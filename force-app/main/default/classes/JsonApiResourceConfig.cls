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

    // Memoized results — populated on first use, reused for the life of the instance.
    private Map<String, Map<String, String>> memoGroups;
    private Map<String, String> memoAttrMap;
    private Map<String, String> memoFieldToAttr;
    private Set<String> memoAttrFields;
    private Map<String, JsonApiRelationshipDef> memoRels;
    private Map<String, Schema.SObjectField> memoFieldMap;

    /**
     * The API version this resource belongs to (the first path segment:
     * /jsonapi/{version}/{type}). Defaults to {@link JsonApiConstants#DEFAULT_VERSION}.
     * Override to expose a resource under a different version; register one config
     * class per (version, type) pair to offer the same type in multiple versions.
     */
    public virtual String getVersion() {
        return JsonApiConstants.DEFAULT_VERSION;
    }

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
        if (memoAttrMap == null) {
            memoAttrMap = new Map<String, String>();
            for (Map<String, String> grp : cachedGroups().values()) {
                memoAttrMap.putAll(grp);
            }
        }
        return memoAttrMap;
    }

    /**
     * Memoized accessor for relationship definitions. All framework code calls
     * this rather than {@link #getRelationships()} directly so the map is built
     * at most once per config instance per transaction.
     */
    public Map<String, JsonApiRelationshipDef> relationships() {
        if (memoRels == null) {
            memoRels = getRelationships();
        }
        return memoRels;
    }

    /** Whether a named attribute group exists on this resource. */
    public Boolean hasGroup(String groupName) {
        return cachedGroups().containsKey(groupName);
    }

    /**
     * Attribute names to expose for the given `extend` groups: always the base
     * group, plus each requested group that exists on this resource. Unknown
     * groups are ignored here (the parser validates them against the primary
     * resource), so this is safe to apply to related resources of other types.
     */
    public Set<String> attributesForGroups(Set<String> extendGroups) {
        Map<String, Map<String, String>> groups = cachedGroups();
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
        if (memoFieldToAttr == null) {
            memoFieldToAttr = new Map<String, String>();
            Map<String, String> attrMap = getAttributeMap();
            for (String attr : attrMap.keySet()) {
                memoFieldToAttr.put(attrMap.get(attr).toLowerCase(), attr);
            }
        }
        return memoFieldToAttr;
    }

    /** All SObject field API names backing this resource's attributes. */
    public Set<String> getAttributeFieldNames() {
        if (memoAttrFields == null) {
            memoAttrFields = new Set<String>(getAttributeMap().values());
        }
        return memoAttrFields;
    }

    public Boolean hasAttribute(String attributeName) {
        return getAttributeMap().containsKey(attributeName);
    }

    public String fieldFor(String attributeName) {
        return getAttributeMap().get(attributeName);
    }

    public JsonApiRelationshipDef relationshipFor(String name) {
        return relationships().get(name);
    }

    /**
     * Memoized SObject field describe map (lower-cased field API name -> token).
     * The query builder is instantiated several times per request (collection,
     * count, each related collection); memoizing here on the singleton config
     * means the {@code getDescribe()} call happens once per type per transaction.
     */
    public Map<String, Schema.SObjectField> fieldMap() {
        if (memoFieldMap == null) {
            memoFieldMap = getSObjectType().getDescribe().fields.getMap();
        }
        return memoFieldMap;
    }

    /** Memoizes the result of {@link #getAttributeGroups()} — called at most once. */
    private Map<String, Map<String, String>> cachedGroups() {
        if (memoGroups == null) {
            memoGroups = getAttributeGroups();
        }
        return memoGroups;
    }
}
