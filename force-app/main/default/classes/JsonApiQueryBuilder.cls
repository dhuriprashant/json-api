/**
 * Builds parameterized SOQL from a {@link JsonApiResourceConfig} and parsed
 * {@link JsonApiQueryOptions}. All object and field names are sourced from the
 * config (never from user input), and all filter values are passed as bind
 * variables, so the generated SOQL is safe from injection. Execute the result
 * with Database.queryWithBinds(query, builder.binds, AccessLevel.USER_MODE).
 */
public with sharing class JsonApiQueryBuilder {

    /** Bind variables referenced by the generated SOQL. */
    public Map<String, Object> binds = new Map<String, Object>();

    private final JsonApiResourceConfig config;
    private final JsonApiQueryOptions options;
    private Integer bindCounter = 0;
    private Map<String, Schema.SObjectField> fieldMap;
    private String cachedWhere;
    private Boolean whereBuilt = false;

    public JsonApiQueryBuilder(JsonApiResourceConfig config, JsonApiQueryOptions options) {
        this.config = config;
        this.options = options == null ? new JsonApiQueryOptions() : options;
        this.fieldMap = config.getSObjectType().getDescribe().fields.getMap();
    }

    public String buildCollectionQuery() {
        String soql = 'SELECT ' + String.join(new List<String>(selectFields()), ', ') +
            ' FROM ' + objectName();
        String whereClause = buildWhere();
        if (whereClause != null) {
            soql += ' WHERE ' + whereClause;
        }
        soql += buildOrderBy();
        soql += ' LIMIT ' + effectiveLimit() + ' OFFSET ' + effectiveOffset();
        return soql;
    }

    public String buildSingleQuery(Id recordId) {
        binds.put('recordId', recordId);
        return 'SELECT ' + String.join(new List<String>(selectFields()), ', ') +
            ' FROM ' + objectName() + ' WHERE Id = :recordId LIMIT 1';
    }

    public String buildCountQuery() {
        String soql = 'SELECT COUNT() FROM ' + objectName();
        String whereClause = buildWhere();
        if (whereClause != null) {
            soql += ' WHERE ' + whereClause;
        }
        return soql;
    }

    public Integer effectiveLimit() {
        return options.pageSize;
    }

    public Integer effectiveOffset() {
        Integer offset = options.pageNumber != null
            ? (options.pageNumber - 1) * options.pageSize
            : options.pageOffset;
        return Math.min(Math.max(offset, 0), JsonApiConstants.MAX_OFFSET);
    }

    // ---------------------------------------------------------------------

    private String objectName() {
        return String.valueOf(config.getSObjectType());
    }

    private Set<String> selectFields() {
        Set<String> fields = new Set<String>{ 'Id' };

        // Sparse fieldset (if any) or base + `extend` groups decide the columns.
        for (String attr : config.resolveAttributeNames(options)) {
            fields.add(config.fieldFor(attr));
        }

        // Always select to-one lookup fields so we can emit relationship linkage.
        for (JsonApiRelationshipDef def : config.relationships().values()) {
            if (!def.isToMany && def.lookupField != null) {
                fields.add(def.lookupField);
            }
        }
        return fields;
    }

    /** Memoized so collection + count queries share one set of bind variables. */
    private String buildWhere() {
        if (!whereBuilt) {
            whereBuilt = true;
            cachedWhere = computeWhere();
        }
        return cachedWhere;
    }

    private String computeWhere() {
        if (options.filters.isEmpty()) {
            return null;
        }
        List<String> clauses = new List<String>();
        for (String attr : options.filters.keySet()) {
            String fieldName = config.fieldFor(attr);
            String bindName = 'f' + (bindCounter++);
            binds.put(bindName, coerce(fieldName, options.filters.get(attr)));
            clauses.add(fieldName + ' = :' + bindName);
        }
        return String.join(clauses, ' AND ');
    }

    private String buildOrderBy() {
        if (options.sorts.isEmpty()) {
            return '';
        }
        List<String> clauses = new List<String>();
        for (JsonApiQueryOptions.SortField s : options.sorts) {
            clauses.add(config.fieldFor(s.attribute) + (s.ascending ? ' ASC NULLS LAST' : ' DESC NULLS LAST'));
        }
        return ' ORDER BY ' + String.join(clauses, ', ');
    }

    /** Coerces a string filter value into the field's native type for binding. */
    private Object coerce(String fieldApiName, String value) {
        Schema.SObjectField field = fieldMap.get(fieldApiName.toLowerCase());
        if (field == null || value == null) {
            return value;
        }
        Schema.DisplayType dt = field.getDescribe().getType();
        try {
            switch on dt {
                when Boolean {
                    return Boolean.valueOf(value);
                }
                when Integer {
                    return Integer.valueOf(value);
                }
                when Double, Currency, Percent {
                    return Double.valueOf(value);
                }
                when Date {
                    return Date.valueOf(value);
                }
                when Datetime {
                    return Datetime.valueOf(value);
                }
                when else {
                    return value;
                }
            }
        } catch (Exception e) {
            throw JsonApiException.badRequest(
                'Filter value "' + value + '" is not valid for this field.',
                JsonApiErrorSource.forParameter('filter'));
        }
    }
}
