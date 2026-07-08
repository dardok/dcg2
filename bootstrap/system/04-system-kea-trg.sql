-- SYSTEM DB TRIGGERS

-- networks
CREATE OR REPLACE FUNCTION proc_networks_insert() RETURNS trigger AS $$
BEGIN
    -- only sync networks with dhcp statements or options
    IF new.dhcp_statements IS NULL AND new.dhcp_options IS NULL THEN
        RETURN NULL;
    END IF;

    PERFORM audit_dhcp4_subnet(
        'insert',
        new.cidr::text
    );

    INSERT INTO kea_dhcp4_subnet (
        subnet_id, subnet_prefix
    ) VALUES (
        new.id, new.cidr::text
    );

    PERFORM apply_dhcp4_statements(
        'kea_dhcp4_subnet',
        'subnet_id',
        new.id,
        new.dhcp_statements
    );

    PERFORM apply_dhcp4_options(
        'subnet',
        NULL::text,
        NULL::int,
        new.id::bigint,
        NULL,
        new.dhcp_options
    );

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER networks_insert AFTER INSERT ON networks FOR EACH ROW EXECUTE FUNCTION proc_networks_insert();

CREATE OR REPLACE FUNCTION proc_networks_update() RETURNS trigger AS $$
BEGIN
    PERFORM audit_dhcp4_subnet(
        'update',
        old.cidr::text
    );

    -- unsync networks without dhcp statements or options
    IF new.dhcp_statements IS NULL AND new.dhcp_options IS NULL THEN
        DELETE FROM kea_dhcp4_subnet
        WHERE subnet_id = old.id;

        PERFORM apply_dhcp4_options(
            'subnet',
            NULL::text,
            NULL::int,
            old.id::bigint,
            old.dhcp_options,
            NULL
        );

        RETURN NULL;
    END IF;

    IF new.id IS DISTINCT FROM old.id THEN
        RAISE EXCEPTION 'Updating network id is not allowed';
    END IF;

    -- sync networks without old dhcp statements or options,
    -- they would not be present if they didn't previously
    -- have statements or options
    IF old.dhcp_statements IS NULL AND old.dhcp_options IS NULL THEN
        INSERT INTO kea_dhcp4_subnet (
            subnet_id, subnet_prefix
        ) VALUES (
            new.id, new.cidr::text
        );
    -- this is correct since the subnet would only have existed
    -- if old statements or options were present
    ELSIF new.cidr IS DISTINCT FROM old.cidr THEN
        UPDATE kea_dhcp4_subnet SET
            subnet_prefix = new.cidr::text
        WHERE subnet_id = new.id;
    END IF;

    PERFORM apply_dhcp4_statements(
        'kea_dhcp4_subnet',
        'subnet_id',
        new.id,
        new.dhcp_statements
    );

    PERFORM apply_dhcp4_options(
        'subnet',
        NULL::text,
        NULL::int,
        new.id::bigint,
        old.dhcp_options,
        new.dhcp_options
    );

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER networks_update AFTER UPDATE ON networks FOR EACH ROW EXECUTE FUNCTION proc_networks_update();

CREATE OR REPLACE FUNCTION proc_networks_delete() RETURNS trigger AS $$
BEGIN
    PERFORM audit_dhcp4_subnet(
        'delete',
        old.cidr::text
    );

    PERFORM apply_dhcp4_options(
        'subnet',
        NULL::text,
        NULL::int,
        old.id::bigint,
        old.dhcp_options,
        NULL
    );

    DELETE FROM kea_dhcp4_subnet
    WHERE subnet_id = old.id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER networks_delete AFTER DELETE ON networks FOR EACH ROW EXECUTE FUNCTION proc_networks_delete();

-- device_groups
CREATE OR REPLACE FUNCTION proc_device_groups_insert() RETURNS trigger AS $$
DECLARE
    v_class_name text := 'device_group_' || new.name;
    v_class_id integer;
BEGIN
    PERFORM audit_dhcp4_client_class(
        'insert',
        v_class_name
    );

    INSERT INTO kea_dhcp4_client_class (
        name
    ) VALUES (
        v_class_name
    ) RETURNING id INTO v_class_id;

    PERFORM apply_dhcp4_statements(
        'kea_dhcp4_client_class',
        'id',
        v_class_id,
        new.dhcp_statements
    );

    PERFORM apply_dhcp4_options(
        'client-class',
        v_class_name,
        NULL::int,
        NULL::bigint,
        NULL,
        COALESCE(new.dhcp_options, '{}') || ('dcg-device-group ' || new.name)
    );

    RETURN NULL;
END
$$ LANGUAGE plpgsql;
CREATE TRIGGER device_groups_insert AFTER INSERT ON device_groups FOR EACH ROW EXECUTE FUNCTION proc_device_groups_insert();

CREATE OR REPLACE FUNCTION proc_device_groups_update() RETURNS trigger AS $$
DECLARE
    v_old_class_name text := 'device_group_' || old.name;
    v_new_class_name text := 'device_group_' || new.name;
BEGIN
    PERFORM audit_dhcp4_client_class(
        'update',
        v_old_class_name
    );

    IF old.name IS DISTINCT FROM new.name THEN
        UPDATE kea_dhcp4_client_class SET
            name = v_new_class_name
        WHERE name = v_old_class_name;
    END IF;

    PERFORM apply_dhcp4_statements(
        'kea_dhcp4_client_class',
        'name',
        v_new_class_name,
        new.dhcp_statements
    );

    PERFORM apply_dhcp4_options(
        'client-class',
        v_new_class_name,
        NULL::int,
        NULL::bigint,
        COALESCE(old.dhcp_options, '{}') || ('dcg-device-group ' || old.name),
        COALESCE(new.dhcp_options, '{}') || ('dcg-device-group ' || new.name)
    );

    IF v_old_class_name IS DISTINCT FROM v_new_class_name THEN
        UPDATE kea_hosts SET
            dhcp4_client_classes = replace_string_array_item(
                dhcp4_client_classes,
                v_old_class_name,
                v_new_class_name
            )
        WHERE v_old_class_name = ANY(regexp_split_to_array(dhcp4_client_classes, ',\s*'));

        DELETE FROM kea_dhcp4_options
        WHERE scope_id = (
            SELECT scope_id FROM kea_dhcp_option_scope
            WHERE scope_name = 'client-class'
        ) AND dhcp_client_class = v_old_class_name;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER device_groups_update AFTER UPDATE ON device_groups FOR EACH ROW EXECUTE FUNCTION proc_device_groups_update();

CREATE OR REPLACE FUNCTION proc_device_groups_delete() RETURNS trigger AS $$
DECLARE
    v_old_class_name text := 'device_group_' || old.name;
BEGIN
    PERFORM audit_dhcp4_client_class(
        'delete',
        v_old_class_name
    );

    PERFORM apply_dhcp4_options(
        'client-class',
        v_old_class_name,
        NULL::int,
        NULL::bigint,
        COALESCE(old.dhcp_options, '{}') || ('dcg-device-group ' || old.name),
        NULL
    );

    DELETE FROM kea_dhcp4_client_class
    WHERE name = v_old_class_name;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER device_groups_delete AFTER DELETE ON device_groups FOR EACH ROW EXECUTE FUNCTION proc_device_groups_delete();

-- devices
CREATE OR REPLACE FUNCTION proc_devices_insert() RETURNS trigger AS $$
DECLARE
    v_device_group_name text;
    v_device_group_client_class text := '';
BEGIN
    -- only link devices with both mac and ip
    IF new.mac IS NULL OR new.ip IS NULL THEN
        RETURN NULL;
    END IF;

    IF new.group_id IS NOT NULL THEN
        SELECT name FROM device_groups WHERE id = new.group_id INTO v_device_group_name;
        IF FOUND THEN
            v_device_group_client_class := 'device_group_' || v_device_group_name;
        END IF;
    END IF;

    INSERT INTO kea_hosts (
        host_id,
        dhcp_identifier,
        dhcp_identifier_type,
        dhcp4_subnet_id,
        ipv4_address,
        hostname,
        dhcp4_client_classes
    ) VALUES (
        new.id,
        decode(replace(new.mac::text, ':', ''), 'hex'),
        (select type from kea_host_identifier_type where name = 'hw-address'),
        (select id from networks where new.ip << networks.cidr),
        (new.ip - '0.0.0.0'::inet),
        new.name,
        v_device_group_client_class
    );

    RETURN NULL;
END
$$ LANGUAGE plpgsql;
CREATE TRIGGER devices_insert AFTER INSERT ON devices FOR EACH ROW EXECUTE FUNCTION proc_devices_insert();

CREATE OR REPLACE FUNCTION proc_devices_update() RETURNS trigger AS $$
DECLARE
    v_old_device_group_name text;
    v_new_device_group_name text;
BEGIN
    -- unlink devices without both mac and ip
    IF new.mac IS NULL OR new.ip IS NULL THEN
        DELETE FROM kea_hosts WHERE host_id = new.id;
        RETURN NULL;
    END IF;

    IF new.id IS DISTINCT FROM old.id THEN
        RAISE EXCEPTION 'Updating device id is not allowed';
    END IF;

    UPDATE kea_hosts SET
        dhcp_identifier = decode(replace(new.mac::text, ':', ''), 'hex'),
        dhcp4_subnet_id = (select id from networks where new.ip << networks.cidr),
        ipv4_address = (new.ip - '0.0.0.0'::inet),
        hostname = new.name
    WHERE host_id = new.id;

    IF new.group_id IS DISTINCT FROM old.group_id THEN
        SELECT name FROM device_groups WHERE id = old.group_id INTO v_old_device_group_name;
        SELECT name FROM device_groups WHERE id = new.group_id INTO v_new_device_group_name;

        IF v_old_device_group_name IS NULL THEN
            UPDATE kea_hosts SET
                dhcp4_client_classes = append_string_array_item(
                    dhcp4_client_classes,
                    'device_group_' || v_new_device_group_name
                )
            WHERE host_id = new.id;
        ELSIF v_new_device_group_name IS NULL THEN
            UPDATE kea_hosts SET
                dhcp4_client_classes = remove_string_array_item(
                    dhcp4_client_classes,
                    'device_group_' || v_old_device_group_name
                )
            WHERE host_id = new.id;
        ELSE
            UPDATE kea_hosts SET
                dhcp4_client_classes = replace_string_array_item(
                    dhcp4_client_classes,
                    'device_group_' || v_old_device_group_name,
                    'device_group_' || v_new_device_group_name
                )
            WHERE host_id = new.id;
        END IF;
    END IF;

    RETURN NULL;
END
$$ LANGUAGE plpgsql;
CREATE TRIGGER devices_update AFTER UPDATE ON devices FOR EACH ROW EXECUTE FUNCTION proc_devices_update();

CREATE OR REPLACE FUNCTION proc_devices_delete() RETURNS trigger AS $$
BEGIN
    DELETE FROM kea_hosts
    WHERE host_id = old.id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER devices_delete AFTER DELETE ON devices FOR EACH ROW EXECUTE FUNCTION proc_devices_delete();

-- dhcp_servers
CREATE OR REPLACE FUNCTION proc_dhcp_servers_insert() RETURNS trigger AS $$
DECLARE
    v_dhcp4_server_id integer;
    v_service record;
    v_statement text;
    v_name text;
    v_value text;
    v_type text;
    v_parameter_id integer;
BEGIN
    PERFORM audit_dhcp4_server(
        'insert',
        new.name
    );

    INSERT INTO kea_dhcp4_server (
        id,
        tag
    ) VALUES (
        new.id + 1, -- 1 is reserved for 'all'
        new.name
    ) RETURNING id INTO v_dhcp4_server_id;

    IF new.config IS NOT NULL THEN
        SELECT * INTO v_service FROM dhcp_services WHERE id = new.config;
        
        IF FOUND THEN
            FOREACH v_statement IN ARRAY COALESCE(v_service.statements, '{}') LOOP
                -- <option-no-spaces> <value-no-spaces> [<type-no-spaces>] 
                v_name := split_part(v_statement, ' ', 1);
                v_value := split_part(v_statement, ' ', 2);
                v_type := split_part(v_statement, ' ', 3);
                IF v_type = '' THEN
                    v_type := 'string';  -- default type
                END IF;

                INSERT INTO kea_dhcp4_global_parameter (name, value, parameter_type)
                VALUES (v_name, v_value, (SELECT id FROM kea_parameter_data_type WHERE name = v_type))
                RETURNING id INTO v_parameter_id;

                INSERT INTO kea_dhcp4_global_parameter_server (parameter_id, server_id)
                VALUES (v_parameter_id, v_dhcp4_server_id);
            END LOOP;

            PERFORM apply_dhcp4_options(
                'global',
                NULL::text,
                NULL::int,
                NULL::bigint,
                NULL,
                v_service.options,
                false,
                v_dhcp4_server_id
            );
        END IF;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER dhcp_servers_insert AFTER INSERT ON dhcp_servers FOR EACH ROW EXECUTE FUNCTION proc_dhcp_servers_insert();

CREATE OR REPLACE FUNCTION proc_dhcp_servers_update() RETURNS trigger AS $$
DECLARE
    v_service record;
    v_statement text;
    v_name text;
    v_value text;
    v_type text;
    v_parameter_id integer;
BEGIN
    PERFORM audit_dhcp4_server(
        'update',
        old.name
    );

    IF new.id IS DISTINCT FROM old.id THEN
        RAISE EXCEPTION 'Updating dhcp server id is not allowed';
    END IF;

    IF new.name IS DISTINCT FROM old.name THEN
        UPDATE kea_dhcp4_server SET
            tag = new.name
        WHERE id = new.id + 1;
    END IF;

    IF new.config IS DISTINCT FROM old.config THEN
        DELETE FROM kea_dhcp4_options
        WHERE scope_id = (
            SELECT scope_id FROM kea_dhcp_option_scope
            WHERE scope_name = 'global'
        ) AND option_id IN (
            SELECT option_id FROM kea_dhcp4_options_server
            WHERE server_id = old.id + 1
        );

        DELETE FROM kea_dhcp4_global_parameter
        WHERE id IN (
            SELECT parameter_id FROM kea_dhcp4_global_parameter_server
            WHERE server_id = old.id + 1
        );

        SELECT * INTO v_service FROM dhcp_services WHERE id = new.config;
        
        IF FOUND THEN
            FOREACH v_statement IN ARRAY COALESCE(v_service.statements, '{}') LOOP
                -- <option-no-spaces> <value-no-spaces> [<type-no-spaces>] 
                v_name := split_part(v_statement, ' ', 1);
                v_value := split_part(v_statement, ' ', 2);
                v_type := split_part(v_statement, ' ', 3);
                IF v_type = '' THEN
                    v_type := 'string';  -- default type
                END IF;

                INSERT INTO kea_dhcp4_global_parameter (name, value, parameter_type)
                VALUES (v_name, v_value, (SELECT id FROM kea_parameter_data_type WHERE name = v_type))
                RETURNING id INTO v_parameter_id;

                INSERT INTO kea_dhcp4_global_parameter_server (parameter_id, server_id)
                VALUES (v_parameter_id, new.id + 1);
            END LOOP;

            PERFORM apply_dhcp4_options(
                'global',
                NULL::text,
                NULL::int,
                NULL::bigint,
                NULL,
                v_service.options,
                false,
                new.id + 1
            );
        END IF;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER dhcp_servers_update AFTER UPDATE ON dhcp_servers FOR EACH ROW EXECUTE FUNCTION proc_dhcp_servers_update();

CREATE OR REPLACE FUNCTION proc_dhcp_servers_delete() RETURNS trigger AS $$
BEGIN
    PERFORM audit_dhcp4_server(
        'delete',
        old.name
    );

    DELETE FROM kea_dhcp4_options
    WHERE scope_id = (
        SELECT scope_id FROM kea_dhcp_option_scope
        WHERE scope_name = 'global'
    ) AND option_id IN (
        SELECT option_id FROM kea_dhcp4_options_server
        WHERE server_id = old.id + 1
    );

    DELETE FROM kea_dhcp4_global_parameter
    WHERE id IN (
        SELECT parameter_id FROM kea_dhcp4_global_parameter_server
        WHERE server_id = old.id + 1
    );

    DELETE FROM kea_dhcp4_server
    WHERE id = old.id + 1;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER dhcp_servers_delete AFTER DELETE ON dhcp_servers FOR EACH ROW EXECUTE FUNCTION proc_dhcp_servers_delete();

-- dhcp_classes/dhcp_subclasses
CREATE OR REPLACE FUNCTION proc_dhcp_subclasses_insert() 
RETURNS trigger AS $$
DECLARE
    v_dhcp_class record;
    v_class_name text;
    v_class_id integer;
BEGIN
    SELECT * INTO v_dhcp_class FROM dhcp_classes WHERE id = new.class_id AND statements IS NOT NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'dhcp_class with no match statements';
    END IF;

    v_class_name := v_dhcp_class.name || '-' || new.name;

    PERFORM audit_dhcp4_client_class(
        'insert',
        v_class_name
    );

    INSERT INTO kea_dhcp4_client_class (
        name,
        test
    ) VALUES (
        v_class_name,
        parse_match_statement(v_dhcp_class.statements[1], new.name)
    ) RETURNING id INTO v_class_id;

    PERFORM apply_dhcp4_statements(
        'kea_dhcp4_client_class',
        'id',
        v_class_id,
        new.statements
    );

    PERFORM apply_dhcp4_options(
        'client-class',
        v_class_name,
        NULL::int,
        NULL::bigint,
        NULL,
        new.options
    );

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER dhcp_subclasses_insert AFTER INSERT ON dhcp_subclasses FOR EACH ROW EXECUTE FUNCTION proc_dhcp_subclasses_insert();

CREATE OR REPLACE FUNCTION proc_dhcp_subclasses_update() 
RETURNS trigger AS $$
DECLARE
    v_old_dhcp_class record;
    v_new_dhcp_class record;
    v_old_class_name text;
    v_new_class_name text;
BEGIN
    SELECT * INTO v_old_dhcp_class FROM dhcp_classes WHERE id = old.class_id;
    SELECT * INTO v_new_dhcp_class FROM dhcp_classes WHERE id = new.class_id AND statements IS NOT NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'dhcp_class with no match statements';
    END IF;

    v_old_class_name := v_old_dhcp_class.name || '-' || old.name;
    v_new_class_name := v_new_dhcp_class.name || '-' || new.name;

    PERFORM audit_dhcp4_client_class(
        'update',
        v_old_class_name
    );

    UPDATE kea_dhcp4_client_class SET
        name = v_new_class_name,
        test = parse_match_statement(v_new_dhcp_class.statements[1], new.name)
    WHERE name = v_old_class_name;

    PERFORM apply_dhcp4_statements(
        'kea_dhcp4_client_class',
        'name',
        v_new_class_name,
        new.statements
    );

    PERFORM apply_dhcp4_options(
        'client-class',
        v_new_class_name,
        NULL::int,
        NULL::bigint,
        old.options,
        new.options
    );

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER dhcp_subclasses_update AFTER UPDATE ON dhcp_subclasses FOR EACH ROW EXECUTE FUNCTION proc_dhcp_subclasses_update();

CREATE OR REPLACE FUNCTION proc_dhcp_subclasses_delete() 
RETURNS trigger AS $$
DECLARE
    v_old_dhcp_class record;
    v_old_class_name text;
BEGIN
    SELECT * INTO v_old_dhcp_class FROM dhcp_classes WHERE id = old.class_id;

    v_old_class_name := v_old_dhcp_class.name || '-' || old.name;

    PERFORM audit_dhcp4_client_class(
        'delete',
        v_old_class_name
    );

    PERFORM apply_dhcp4_options(
        'client-class',
        v_old_class_name,
        NULL::int,
        NULL::bigint,
        old.options,
        NULL
    );

    DELETE FROM kea_dhcp4_client_class
    WHERE name = v_old_class_name;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER dhcp_subclasses_delete AFTER DELETE ON dhcp_subclasses FOR EACH ROW EXECUTE FUNCTION proc_dhcp_subclasses_delete();

-- host_groups
CREATE OR REPLACE FUNCTION proc_host_groups_insert() RETURNS trigger AS $$
DECLARE
    v_class_name text := 'host_group_' || new.name;
    v_class_id integer;
    v_boot_default_opt_name text := 'dcg-boot-default';
BEGIN
    PERFORM audit_dhcp4_client_class(
        'insert',
        v_class_name
    );

    INSERT INTO kea_dhcp4_client_class (
        name
    ) VALUES (
        v_class_name
    ) RETURNING id INTO v_class_id;

    IF new.boot_default IS NOT NULL THEN
        PERFORM apply_dhcp4_options(
            'client-class',
            v_class_name,
            NULL::int,
            NULL::bigint,
            NULL,
            ARRAY[v_boot_default_opt_name || ' ' || new.boot_default]::text[]
        );
    END IF;

    RETURN NULL;
END
$$ LANGUAGE plpgsql;
CREATE TRIGGER host_groups_insert AFTER INSERT ON host_groups FOR EACH ROW EXECUTE FUNCTION proc_host_groups_insert();

CREATE OR REPLACE FUNCTION proc_host_groups_update() RETURNS trigger AS $$
DECLARE
    v_old_class_name text := 'host_group_' || old.name;
    v_new_class_name text := 'host_group_' || new.name;
    v_boot_default_opt_name text := 'dcg-boot-default';
BEGIN
    PERFORM audit_dhcp4_client_class(
        'update',
        v_old_class_name
    );

    if old.name IS DISTINCT FROM new.name THEN
        UPDATE kea_dhcp4_client_class SET
            name = v_new_class_name
        WHERE name = v_old_class_name;

        UPDATE kea_dhcp4_options SET
            dhcp_client_class = v_new_class_name
        WHERE dhcp_client_class = v_old_class_name AND
            scope_id = (SELECT scope_id FROM kea_dhcp_option_scope WHERE scope_name = 'client-class');

        UPDATE kea_hosts SET
            dhcp4_client_classes = replace_string_array_item(
                dhcp4_client_classes,
                v_old_class_name,
                v_new_class_name
            )
        WHERE v_old_class_name = ANY(regexp_split_to_array(dhcp4_client_classes, ',\s*'));
    END IF;

    IF new.boot_default IS DISTINCT FROM old.boot_default THEN
        PERFORM apply_dhcp4_options(
            'client-class',
            v_new_class_name,
            NULL::int,
            NULL::bigint,
            CASE WHEN old.boot_default IS NULL THEN NULL ELSE ARRAY[v_boot_default_opt_name || ' ' || old.boot_default]::text[] END,
            CASE WHEN new.boot_default IS NULL THEN NULL ELSE ARRAY[v_boot_default_opt_name || ' ' || new.boot_default]::text[] END
        );
    END IF;

    RETURN NULL;
END
$$ LANGUAGE plpgsql;
CREATE TRIGGER host_groups_update AFTER UPDATE ON host_groups FOR EACH ROW EXECUTE FUNCTION proc_host_groups_update();

CREATE OR REPLACE FUNCTION proc_host_groups_delete() RETURNS trigger AS $$
DECLARE
    v_old_class_name text := 'host_group_' || old.name;
    v_boot_default_opt_name text := 'dcg-boot-default';
BEGIN
    PERFORM audit_dhcp4_client_class(
        'delete',
        v_old_class_name
    );

    IF old.boot_default IS NOT NULL THEN
        PERFORM apply_dhcp4_options(
            'client-class',
            v_old_class_name,
            NULL::int,
            NULL::bigint,
            ARRAY[v_boot_default_opt_name || ' ' || old.boot_default]::text[],
            NULL
        );
    END IF;

    DELETE FROM kea_dhcp4_client_class
    WHERE name = v_old_class_name;

    RETURN NULL;
END
$$ LANGUAGE plpgsql;
CREATE TRIGGER host_groups_delete AFTER DELETE ON host_groups FOR EACH ROW EXECUTE FUNCTION proc_host_groups_delete();

-- hosts
CREATE OR REPLACE FUNCTION proc_hosts_insert() RETURNS trigger AS $$
DECLARE
    v_host_group_name text;
    v_boot_default_opt_name text := 'dcg-boot-default';
BEGIN
    IF new.group_id IS NOT NULL THEN
        SELECT name FROM host_groups WHERE id = new.group_id INTO v_host_group_name;

        IF FOUND THEN
            UPDATE kea_hosts SET
                dhcp4_client_classes = append_string_array_item(
                    dhcp4_client_classes,
                    'host_group_' || v_host_group_name
                )
            WHERE host_id = new.mgmt_device_id;
        END IF;
    END IF;

    IF new.boot_default IS NOT NULL THEN
        PERFORM apply_dhcp4_options(
            'host',
            NULL::text,
            new.mgmt_device_id,
            NULL::bigint,
            NULL,
            ARRAY[v_boot_default_opt_name || ' ' || new.boot_default]::text[]
        );
    END IF;

    RETURN NULL;
END
$$ LANGUAGE plpgsql;
CREATE TRIGGER hosts_insert AFTER INSERT ON hosts FOR EACH ROW EXECUTE FUNCTION proc_hosts_insert();

CREATE OR REPLACE FUNCTION proc_hosts_update() RETURNS trigger AS $$
DECLARE
    v_old_host_group_name text;
    v_new_host_group_name text;
    v_boot_default_opt_name text := 'dcg-boot-default';
BEGIN
    IF new.mgmt_device_id IS DISTINCT FROM old.mgmt_device_id THEN
        RAISE EXCEPTION 'Updating hosts->device reference is not allowed';
    END IF;

    IF new.group_id IS DISTINCT FROM old.group_id THEN
        SELECT name FROM host_groups WHERE id = old.group_id INTO v_old_host_group_name;
        SELECT name FROM host_groups WHERE id = new.group_id INTO v_new_host_group_name;

        IF v_old_host_group_name IS NULL THEN
            UPDATE kea_hosts SET
                dhcp4_client_classes = append_string_array_item(
                    dhcp4_client_classes,
                    'host_group_' || v_new_host_group_name
                )
            WHERE host_id = old.mgmt_device_id;
        ELSIF v_new_host_group_name IS NULL THEN
            UPDATE kea_hosts SET
                dhcp4_client_classes = remove_string_array_item(
                    dhcp4_client_classes,
                    'host_group_' || v_old_host_group_name
                )
            WHERE host_id = old.mgmt_device_id;
        ELSE
            UPDATE kea_hosts SET
                dhcp4_client_classes = replace_string_array_item(
                    dhcp4_client_classes,
                    'host_group_' || v_old_host_group_name,
                    'host_group_' || v_new_host_group_name
                )
            WHERE host_id = old.mgmt_device_id;
        END IF;
    END IF;

    IF new.boot_default IS DISTINCT FROM old.boot_default THEN
        PERFORM apply_dhcp4_options(
            'host',
            NULL::text,
            new.mgmt_device_id,
            NULL::bigint,
            CASE WHEN old.boot_default IS NULL THEN NULL ELSE ARRAY[v_boot_default_opt_name || ' ' || old.boot_default]::text[] END,
            CASE WHEN new.boot_default IS NULL THEN NULL ELSE ARRAY[v_boot_default_opt_name || ' ' || new.boot_default]::text[] END
        );
    END IF;

    RETURN NULL;
END
$$ LANGUAGE plpgsql;
CREATE TRIGGER hosts_update AFTER UPDATE ON hosts FOR EACH ROW EXECUTE FUNCTION proc_hosts_update();

CREATE OR REPLACE FUNCTION proc_hosts_delete() RETURNS trigger AS $$
DECLARE
    v_old_host_group_name text;
    v_boot_default_opt_name text := 'dcg-boot-default';
BEGIN
    IF old.group_id IS NOT NULL THEN
        SELECT name FROM host_groups WHERE id = old.group_id INTO v_old_host_group_name;

        UPDATE kea_hosts SET
            dhcp4_client_classes = remove_string_array_item(
                dhcp4_client_classes,
                'host_group_' || v_old_host_group_name
            )
        WHERE host_id = old.mgmt_device_id;
    END IF;

    IF old.boot_default IS NOT NULL THEN
        PERFORM apply_dhcp4_options(
            'host',
            NULL::text,
            old.mgmt_device_id,
            NULL::bigint,
            ARRAY[v_boot_default_opt_name || ' ' || old.boot_default]::text[],
            NULL
        );
    END IF;

    RETURN NULL;
END
$$ LANGUAGE plpgsql;
CREATE TRIGGER hosts_delete AFTER DELETE ON hosts FOR EACH ROW EXECUTE FUNCTION proc_hosts_delete();
