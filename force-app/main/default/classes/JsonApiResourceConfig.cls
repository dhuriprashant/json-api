/**
 * Maps a JSON:API resource `type` onto a Salesforce SObject and declares which
 * fields are exposed as attributes and how relationships are traversed.
 *
 * Subclass this for each SObject you want to expose, then register it in
 * {@link JsonApiBootstrap}. Subclasses must implement {@link #getType},
 * {@link #getSObjectType} and {@link #getAttributeMap}; everything else has a
 * sensible default that can be overridden.
 */
public abstract class JsonApiResourceConfig {

    /** The JSON:API `type` for this resource, e.g. "accounts". */
    public abstract String getType();

    /** The SObjectType this resource is backed by, e.g. Account.SObjectType. */
    public abstract Schema.SObjectType getSObjectType();

    /**
     * Maps each exposed attribute name to its SObject field API name, e.g.
     * { 'name' => 'Name', 'industry' => 'Industry' }. The resource `id` is
     * handled separately and must NOT appear here.
     */
    public abstract Map<String, String> getAttributeMap();

    /** Relationship name -> definition. Empty by default. */
    public virtual Map<String, JsonApiRelationshipDef> getRelationships() {
        return new Map<String, JsonApiRelationshipDef>();
    }

    /**
     * Attribute names that may be set on create/update. Defaults to every
     * mapped attribute; override to exclude formula/rollup/system fields.
     */
    public virtual Set<String> getWritableAttributes() {
        return getAttributeMap().keySet().clone();
    }

    // ---------------------------------------------------------------------
    // Derived helpers (do not override)
    // ---------------------------------------------------------------------

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
