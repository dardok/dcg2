-- ============================================================
-- KEA UTILITY FUNCTIONS
-- ============================================================

-- audit helpers
CREATE OR REPLACE FUNCTION audit_dhcp4_server(action text, item text) RETURNS void AS $$
BEGIN
    PERFORM createAuditRevisionDHCP4(action || ' dhcp4_server ' || item);
END
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION audit_dhcp4_subnet(action text, item text) RETURNS void AS $$
BEGIN
    PERFORM createAuditRevisionDHCP4(action || ' dhcp4_subnet ' || item);
END
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION audit_dhcp4_client_class(action text, item text) RETURNS void AS $$
BEGIN
    PERFORM createAuditRevisionDHCP4(action || ' dhcp4_client_class ' || item);
END
$$ LANGUAGE plpgsql;

-- Parse DHCP option strings: "name value", "space.name value", 'name "quoted value"'
-- Returns SETOF (space text, name text, value text)
CREATE OR REPLACE FUNCTION _parse_dhcp_options(p_opts text[])
RETURNS SETOF record AS $$
DECLARE
    v_opt text;
    v_match text[];
BEGIN
    IF p_opts IS NULL THEN RETURN; END IF;
    FOREACH v_opt IN ARRAY p_opts LOOP
        v_match := regexp_match(trim(v_opt), '^([a-zA-Z0-9_-]+\.)?([a-zA-Z0-9_-]+)\s+"?([^"]+)"?$', 'i');
        IF v_match IS NULL THEN
            RAISE EXCEPTION 'Option ''%'' not parsed', v_opt;
        END IF;
        RETURN NEXT ROW(
            COALESCE(rtrim(v_match[1], '.'), 'dhcp4'),
            v_match[2],
            v_match[3]
        );
    END LOOP;
END
$$ LANGUAGE plpgsql;

-- Convert option text_value to (bytea value, text formatted_value) based on option definition
CREATE OR REPLACE FUNCTION _convert_dhcp_option_value(p_code smallint, p_space text, p_text_value text)
RETURNS record AS $$
DECLARE
    v_type_name text;
    v_value bytea;
    v_formatted_value text;
BEGIN
    -- TODO: figure out why we can't use formatted_value for custom options,
    --       kea complains that 'option has formatted_value but no option def'
    SELECT t.name INTO v_type_name
    FROM kea_dhcp4_option_def_lookup l
    JOIN kea_option_def_data_type t ON l.type = t.id
    WHERE l.code = p_code AND l.space = p_space;

    IF v_type_name IS NULL THEN
        RAISE EXCEPTION 'Option def not found: code=% space=%', p_code, p_space;
    END IF;

    v_value := CASE v_type_name 
        WHEN 'empty' THEN NULL
        WHEN 'binary' THEN decode(p_text_value, 'hex')
        WHEN 'boolean' THEN CASE WHEN p_text_value = 'true' THEN '\x01'::bytea ELSE '\x00'::bytea END
        WHEN 'int8' THEN decode(lpad(to_hex(p_text_value::bigint & 255), 2, '0'), 'hex')
        WHEN 'int16' THEN decode(lpad(to_hex(p_text_value::bigint & 65535), 4, '0'), 'hex')
        WHEN 'int32' THEN decode(lpad(to_hex(p_text_value::bigint & 4294967295), 8, '0'), 'hex')
        WHEN 'uint8' THEN decode(lpad(to_hex(p_text_value::bigint), 2, '0'), 'hex')
        WHEN 'uint16' THEN decode(lpad(to_hex(p_text_value::bigint), 4, '0'), 'hex')
        WHEN 'uint32' THEN decode(lpad(to_hex(p_text_value::bigint), 8, '0'), 'hex')
        WHEN 'string' THEN p_text_value::bytea
        WHEN 'fqdn' THEN p_text_value::bytea
        ELSE NULL -- let kea format others (probably won't work for our custom options if we add any that use other types, see TODO)
    END;

    IF v_type_name <> 'empty' AND v_value IS NULL THEN
        v_formatted_value := p_text_value;
    END IF;

    RETURN ROW(v_value, v_formatted_value);
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION _insert_dhcp_option(
    p_code smallint,
    p_text_value text,
    p_space varchar(128),
    p_persistent boolean,
    p_dhcp_client_class varchar(128),
    p_dhcp4_subnet_id bigint,
    p_host_id integer,
    p_scope_name varchar(32),
    p_user_context text,
    p_shared_network_name varchar(128),
    p_pool_id bigint,
    p_server_id integer
) RETURNS void AS $$
DECLARE
    v_conv record;
    v_scope_id smallint;
    v_opt_id integer;
BEGIN
    SELECT * INTO v_conv FROM _convert_dhcp_option_value(p_code, p_space, p_text_value)
        AS r(v_value bytea, v_formatted_value text);

    SELECT scope_id FROM kea_dhcp_option_scope
    WHERE scope_name = p_scope_name
    INTO v_scope_id;

    INSERT INTO kea_dhcp4_options (
        code,
        value,
        formatted_value,
        space,
        persistent,
        dhcp_client_class,
        dhcp4_subnet_id,
        host_id,
        scope_id,
        user_context,
        shared_network_Name,
        pool_id
    ) VALUES (
        p_code,
        v_conv.v_value,
        v_conv.v_formatted_value,
        p_space,
        p_persistent,
        p_dhcp_client_class,
        p_dhcp4_subnet_id,
        p_host_id,
        v_scope_id,
        p_user_context,
        p_shared_network_Name,
        p_pool_id
    ) RETURNING option_id INTO v_opt_id;

    INSERT INTO kea_dhcp4_options_server (option_id, server_id)
    VALUES (v_opt_id, p_server_id);
END
$$ LANGUAGE plpgsql;

-- Ensure encapsulation option exists for a vendor space (e.g., 'ipxe', 'APC')
CREATE OR REPLACE FUNCTION _ensure_encapsulation_option(
    p_vendor_space text,
    p_scope_name text,
    p_client_class text,
    p_host_id int,
    p_subnet_id bigint,
    p_persistent boolean,
    p_server_id int DEFAULT 1
) RETURNS void AS $$
DECLARE
    v_encap_code smallint;
    v_scope_id smallint;
    v_opt_id integer;
BEGIN
    SELECT code INTO v_encap_code
    FROM kea_dhcp4_option_def_lookup
    WHERE encapsulate = p_vendor_space AND space = 'dhcp4';

    IF v_encap_code IS NULL THEN RETURN; END IF;

    SELECT scope_id INTO v_scope_id
    FROM kea_dhcp_option_scope
    WHERE scope_name = p_scope_name;

    SELECT option_id INTO v_opt_id
    FROM kea_dhcp4_options
    WHERE code = v_encap_code AND space = 'dhcp4'
      AND (p_scope_name = 'subnet' AND dhcp4_subnet_id = p_subnet_id OR
           p_scope_name = 'client-class' AND dhcp_client_class = p_client_class OR
           p_scope_name = 'host' AND host_id = p_host_id OR
           p_scope_name = 'global' AND dhcp4_subnet_id IS NULL AND dhcp_client_class IS NULL AND host_id IS NULL)
      AND scope_id = v_scope_id
      AND pool_id IS NULL AND shared_network_name IS NULL
    LIMIT 1;

    IF v_opt_id IS NOT NULL THEN
        UPDATE kea_dhcp4_options
            SET modification_ts = CURRENT_TIMESTAMP
        WHERE option_id = v_opt_id;
    ELSE
        PERFORM _insert_dhcp_option(
            v_encap_code,
            NULL,
            'dhcp4',
            p_persistent,
            p_client_class,
            p_subnet_id,
            p_host_id,
            p_scope_name,
            NULL,
            NULL,
            NULL,
            p_server_id
        );
    END IF;
END
$$ LANGUAGE plpgsql;

-- Generic sync for kea_dhcp4_options across all scopes
-- p_old_opts/p_new_opts: text[] of "name value" strings (NULL for insert/delete)
CREATE OR REPLACE FUNCTION apply_dhcp4_options(
    p_scope_name text,          -- 'subnet', 'client-class', 'host', 'global'
    p_client_class text,        -- for client-class scope
    p_host_id int,              -- for host scope
    p_subnet_id bigint,         -- for subnet scope
    p_old_opts text[],          -- NULL for INSERT
    p_new_opts text[],          -- NULL for DELETE
    p_persistent_default boolean DEFAULT false,
    p_server_id int DEFAULT 1
) RETURNS void AS $$
DECLARE
    v_scope_id smallint;
    v_rec record;
    v_code smallint;
    v_persistent boolean;
    v_conv record;
    v_opt_id integer;
    v_encap_spaces text[] := '{}';
BEGIN
    SELECT scope_id INTO v_scope_id FROM kea_dhcp_option_scope WHERE scope_name = p_scope_name;

    -- DELETE removed options
    IF p_old_opts IS NOT NULL THEN
        DELETE FROM kea_dhcp4_options
        WHERE option_id IN (
            SELECT o.option_id FROM kea_dhcp4_options o
            JOIN kea_dhcp4_option_def_lookup d ON o.code = d.code AND o.space = d.space
            WHERE o.scope_id = v_scope_id
            AND (p_scope_name = 'subnet' AND o.dhcp4_subnet_id = p_subnet_id OR
                p_scope_name = 'client-class' AND o.dhcp_client_class = p_client_class OR
                p_scope_name = 'host' AND o.host_id = p_host_id OR
                p_scope_name = 'global' AND o.dhcp4_subnet_id IS NULL AND o.dhcp_client_class IS NULL AND o.host_id IS NULL)
            AND o.pool_id IS NULL AND o.shared_network_name IS NULL
            AND NOT EXISTS (
                SELECT 1 FROM _parse_dhcp_options(p_new_opts) AS n(space text, name text, value text)
                WHERE n.space = o.space AND n.name = d.name
            )
        );
    END IF;

    -- UPSERT new/changed options
    IF p_new_opts IS NOT NULL THEN
        FOR v_rec IN SELECT * FROM _parse_dhcp_options(p_new_opts) AS n(space text, name text, value text) LOOP
            SELECT code INTO v_code
            FROM kea_dhcp4_option_def_lookup
            WHERE name = v_rec.name AND space = v_rec.space;

            IF v_code IS NULL THEN
                RAISE EXCEPTION 'Option %.% not found', v_rec.space, v_rec.name;
            END IF;

            v_persistent := p_persistent_default OR v_rec.name LIKE 'dcg-%';

            SELECT * INTO v_conv FROM _convert_dhcp_option_value(v_code, v_rec.space, v_rec.value)
                AS r(v_value bytea, v_formatted_value text);

            SELECT option_id INTO v_opt_id
            FROM kea_dhcp4_options
            WHERE code = v_code AND space = v_rec.space
                AND (p_scope_name = 'subnet' AND dhcp4_subnet_id = p_subnet_id OR
                    p_scope_name = 'client-class' AND dhcp_client_class = p_client_class OR
                    p_scope_name = 'host' AND host_id = p_host_id OR
                    p_scope_name = 'global' AND dhcp4_subnet_id IS NULL AND dhcp_client_class IS NULL AND host_id IS NULL)
                AND scope_id = v_scope_id
                AND pool_id IS NULL AND shared_network_name IS NULL
            LIMIT 1;

            IF v_opt_id IS NOT NULL THEN
                UPDATE kea_dhcp4_options
                SET value = v_conv.v_value,
                    formatted_value = v_conv.v_formatted_value,
                    persistent = v_persistent,
                    modification_ts = CURRENT_TIMESTAMP
                WHERE option_id = v_opt_id;
            ELSE
                PERFORM _insert_dhcp_option(
                    v_code,
                    v_rec.value,
                    v_rec.space,
                    v_persistent,
                    p_client_class,
                    p_subnet_id,
                    p_host_id,
                    p_scope_name,
                    NULL,
                    NULL,
                    NULL,
                    p_server_id
                );
            END IF;

            -- Encapsulation
            IF v_rec.space <> 'dhcp4' AND NOT (v_rec.space = ANY(v_encap_spaces)) THEN
                PERFORM _ensure_encapsulation_option(
                    v_rec.space,
                    p_scope_name,
                    p_client_class,
                    p_host_id,
                    p_subnet_id,
                    v_persistent,
                    p_server_id
                );
                v_encap_spaces := v_encap_spaces || v_rec.space;
            END IF;
        END LOOP;
    END IF;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION append_string_array_item(string text, new_item text) RETURNS text AS $$
BEGIN
    RETURN array_to_string(
        array_append(
            array_remove(
                regexp_split_to_array(string, ',\s*'),
            ''),
            new_item
        ), ', '
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION replace_string_array_item(string text, old_item text, new_item text) RETURNS text AS $$
BEGIN
    RETURN array_to_string(
        array_replace(
            array_remove(
                regexp_split_to_array(string, ',\s*'),
                ''
            ),
            old_item,
            new_item
        ), ', '
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION remove_string_array_item(string text, old_item text) RETURNS text AS $$
BEGIN
    RETURN array_to_string(
        array_remove(
            array_remove(
                regexp_split_to_array(string, ',\s*'),
                ''
            ),
            old_item
        ), ', '
    );
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION parse_match_statement(
    p_statement text,
    p_name text
) RETURNS text AS $$
DECLARE
    v_test_expr text;
    v_regex_match text[];
    v_test_val text;
    v_slice_len integer;
BEGIN
    IF p_statement ILIKE '%hardware%' THEN
        v_test_expr := format('pkt4.mac == 0x%s', replace(substring(p_name, 3, 19), ':', ''));
    ELSIF p_statement ILIKE '%substring%' THEN
        v_regex_match := regexp_matches(p_statement, '\s*([a-zA-Z-]+),\s*0,\s*([0-9]+)', 'i');
        IF v_regex_match IS NOT NULL THEN
            v_test_val := v_regex_match[1];
            v_slice_len := v_regex_match[2]::INT;
            v_test_expr := format('substring(option[%s].text, 0, %s) == ''%s''', v_test_val, v_slice_len, p_name);
        END IF;
    ELSIF p_statement ILIKE '%vendor-class-identifier%' THEN
        v_test_expr := format('option[vendor-class-identifier].text == ''%s''', p_name);
    ELSE
        RAISE EXCEPTION 'Match expression ''%'' not recognized', p_statement;
    END IF;

    RETURN v_test_expr;
END
$$ LANGUAGE plpgsql;

-- set common options at the dhcp4_subnet or dhcp4_client_class scopes
CREATE OR REPLACE FUNCTION apply_dhcp4_statements(
    p_target_table text,
    p_id_column text,
    p_id_value anyelement,
    p_statements text[]
) RETURNS void AS $$
DECLARE
    v_statement text;
    v_parts     text[];
    v_col       text;
    v_val       text;
BEGIN
    -- Reset known columns to NULL first
    EXECUTE format(
        'UPDATE %I SET
            next_server = NULL,
            boot_file_name = NULL,
            valid_lifetime = NULL,
            min_valid_lifetime = NULL,
            max_valid_lifetime = NULL,
            offer_lifetime = NULL
        WHERE %I = $1',
        p_target_table, p_id_column
    ) USING p_id_value;

    FOREACH v_statement IN ARRAY COALESCE(p_statements, '{}') LOOP
        v_parts := regexp_split_to_array(trim(v_statement), '\s+');
        v_col   := v_parts[1];
        v_val   := v_parts[2];

        CASE v_col
            WHEN 'next-server' THEN
                EXECUTE format('UPDATE %I SET next_server = $1::inet WHERE %I = $2', p_target_table, p_id_column)
                USING v_val, p_id_value;
            WHEN 'filename' THEN
                EXECUTE format('UPDATE %I SET boot_file_name = trim($1, ''"'') WHERE %I = $2', p_target_table, p_id_column)
                USING v_val, p_id_value;
            WHEN 'valid-lifetime' THEN
                EXECUTE format('UPDATE %I SET valid_lifetime = $1::bigint WHERE %I = $2', p_target_table, p_id_column)
                USING v_val, p_id_value;
            WHEN 'min-valid-lifetime' THEN
                EXECUTE format('UPDATE %I SET min_valid_lifetime = $1::bigint WHERE %I = $2', p_target_table, p_id_column)
                USING v_val, p_id_value;
            WHEN 'max-valid-lifetime' THEN
                EXECUTE format('UPDATE %I SET max_valid_lifetime = $1::bigint WHERE %I = $2', p_target_table, p_id_column)
                USING v_val, p_id_value;
            WHEN 'offer-lifetime' THEN
                EXECUTE format('UPDATE %I SET offer_lifetime = $1::bigint WHERE %I = $2', p_target_table, p_id_column)
                USING v_val, p_id_value;
            WHEN 'vendor-option-space' THEN
                RETURN; -- silently ignore vendor-option-space, it gets parsed from the value
            ELSE
                RAISE EXCEPTION 'unexpected statement %', v_statement;
        END CASE;
    END LOOP;
END;
$$ LANGUAGE plpgsql;