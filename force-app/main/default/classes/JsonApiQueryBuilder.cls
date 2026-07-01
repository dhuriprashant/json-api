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
    private String cachedWhere;
    private Boolean whereBuilt = false;

    public JsonApiQueryBuilder(JsonApiResourceConfig config, JsonApiQueryOptions options) {
        this.config = config;
        this.options = options == null ? new JsonApiQueryOptions() : options;
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
        for (JsonApiQueryOptions.FilterCondition fc : options.filters) {
            clauses.add(buildClause(fc));
        }
        return String.join(clauses, ' AND ');
    }

    /**
     * Renders one filter condition into a SOQL fragment, binding its value(s).
     * The field name comes from the config (never user input); every value is a
     * bind variable, so the result is injection-safe.
     */
    private String buildClause(JsonApiQueryOptions.FilterCondition fc) {
        // The id "attribute" maps to the SObject Id field (it is not in any group).
        String fieldName = fc.attribute.equalsIgnoreCase(JsonApiConstants.ID_ATTRIBUTE)
            ? JsonApiConstants.ID_FIELD
            : config.fieldFor(fc.attribute);
        String bindName = 'f' + (bindCounter++);
        switch on fc.operator {
            when 'ne' {
                binds.put(bindName, coerce(fieldName, fc.rawValue));
                return fieldName + ' != :' + bindName;
            }
            when 'gt' {
                binds.put(bindName, coerce(fieldName, fc.rawValue));
                return fieldName + ' > :' + bindName;
            }
            when 'gte' {
                binds.put(bindName, coerce(fieldName, fc.rawValue));
                return fieldName + ' >= :' + bindName;
            }
            when 'lt' {
                binds.put(bindName, coerce(fieldName, fc.rawValue));
                return fieldName + ' < :' + bindName;
            }
            when 'lte' {
                binds.put(bindName, coerce(fieldName, fc.rawValue));
                return fieldName + ' <= :' + bindName;
            }
            when 'like' {
                // Bound as a string; wildcards (% _) come from the client.
                binds.put(bindName, fc.rawValue);
                return fieldName + ' LIKE :' + bindName;
            }
            when 'in' {
                binds.put(bindName, coerceList(fieldName, fc.rawValue));
                return fieldName + ' IN :' + bindName;
            }
            when 'nin' {
                binds.put(bindName, coerceList(fieldName, fc.rawValue));
                return fieldName + ' NOT IN :' + bindName;
            }
            when else {
                // 'eq' and any unrecognized operator (the parser already rejects
                // unsupported ones) fall back to equality.
                binds.put(bindName, coerce(fieldName, fc.rawValue));
                return fieldName + ' = :' + bindName;
            }
        }
    }

    /**
     * Splits a comma-separated value into a *typed* list for IN / NOT IN binds.
     * SOQL rejects a `List<Object>` (ANY) bind, so the list's element type must
     * match the column (e.g. `List<String>` for a picklist, `List<Integer>` for a
     * number). Values are still bound, never interpolated.
     */
    private Object coerceList(String fieldApiName, String csv) {
        List<String> raw = new List<String>();
        if (String.isNotBlank(csv)) {
            for (String part : csv.split(',')) {
                raw.add(part.trim());
            }
        }
        Schema.SObjectField field = config.fieldMap().get(fieldApiName.toLowerCase());
        Schema.DisplayType dt = field == null ? Schema.DisplayType.STRING : field.getDescribe().getType();
        try {
            switch on dt {
                when Integer {
                    List<Integer> out = new List<Integer>();
                    for (String s : raw) { out.add(Integer.valueOf(s)); }
                    return out;
                }
                when Double, Currency, Percent {
                    List<Double> out = new List<Double>();
                    for (String s : raw) { out.add(Double.valueOf(s)); }
                    return out;
                }
                when Date {
                    List<Date> out = new List<Date>();
                    for (String s : raw) { out.add(Date.valueOf(s)); }
                    return out;
                }
                when Datetime {
                    List<Datetime> out = new List<Datetime>();
                    for (String s : raw) { out.add(Datetime.valueOf(s)); }
                    return out;
                }
                when Boolean {
                    List<Boolean> out = new List<Boolean>();
                    for (String s : raw) { out.add(Boolean.valueOf(s)); }
                    return out;
                }
                when ID {
                    List<Id> out = new List<Id>();
                    for (String s : raw) { out.add(parseId(s)); }
                    return out;
                }
                when else {
                    // Text, picklist, reference, email, phone, … all bind as strings.
                    return raw;
                }
            }
        } catch (JsonApiException je) {
            throw je; // precise id errors must survive the generic fallback below
        } catch (Exception e) {
            throw JsonApiException.badRequest(
                'Filter list value "' + csv + '" is not valid for this field.',
                JsonApiErrorSource.forParameter('filter'));
        }
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
        Schema.SObjectField field = config.fieldMap().get(fieldApiName.toLowerCase());
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
                when ID {
                    return parseId(value);
                }
                when else {
                    return value;
                }
            }
        } catch (JsonApiException je) {
            throw je; // a precise id error must survive the generic fallback below
        } catch (Exception e) {
            throw JsonApiException.badRequest(
                'Filter value "' + value + '" is not valid for this field.',
                JsonApiErrorSource.forParameter('filter'));
        }
    }

    /** Validates an id string's format and that it belongs to this resource's SObject. */
    private Id parseId(String value) {
        Id parsed;
        try {
            parsed = Id.valueOf(value == null ? null : value.trim());
        } catch (Exception e) {
            throw JsonApiException.badRequest(
                '"' + value + '" is not a valid id.',
                JsonApiErrorSource.forParameter('filter[id]'));
        }
        if (parsed.getSObjectType() != config.getSObjectType()) {
            throw JsonApiException.badRequest(
                '"' + value + '" is not a valid id for ' + config.getType() + '.',
                JsonApiErrorSource.forParameter('filter[id]'));
        }
        return parsed;
    }
}
