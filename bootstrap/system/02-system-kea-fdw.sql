CREATE EXTENSION IF NOT EXISTS postgres_fdw;

CREATE SERVER kea_server FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host '127.0.0.1', port '5432', dbname 'kea', options '-c kea.audit_revision_id=1');
CREATE USER MAPPING FOR system SERVER kea_server OPTIONS (user 'kea');

-- hack kea's audit revision/entry refresh-based mechanism
CREATE FOREIGN TABLE kea_dhcp4_audit_revision (
    id integer NOT NULL,
    modification_ts timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    log_message text,
    server_id bigint DEFAULT 1 -- 'all'
)
SERVER kea_server OPTIONS (schema_name 'public', table_name 'dhcp4_audit_revision');
CREATE FOREIGN TABLE kea_dhcp4_audit_revision_id_seq (
    seq bigint
) SERVER kea_server OPTIONS (schema_name 'public', table_name 'dhcp4_audit_revision_id_seq_view');
CREATE OR REPLACE FUNCTION kea_dhcp4_audit_revision_id_seq_nextval() RETURNS bigint AS $$
    SELECT seq FROM kea_dhcp4_audit_revision_id_seq;
$$ LANGUAGE sql;
CREATE OR REPLACE FUNCTION createAuditRevisionDHCP4(log_message text) RETURNS integer AS $$
DECLARE
    audit_revision_id bigint;
BEGIN
    INSERT INTO kea_dhcp4_audit_revision (
        id,
        log_message
    ) VALUES (
        (select * from kea_dhcp4_audit_revision_id_seq_nextval()),
        log_message
    ) RETURNING id INTO audit_revision_id;

    EXECUTE format(
        'ALTER SERVER kea_server OPTIONS (SET options %L)', 
        '-c kea.audit_revision_id=' || audit_revision_id
    );

    -- RAISE NOTICE 'audit_revision_id set to %', audit_revision_id;

    RETURN audit_revision_id;
END
$$ LANGUAGE plpgsql;

CREATE FOREIGN TABLE kea_dhcp4_server (
    id integer NOT NULL,
    tag varchar(64) NOT NULL,
    description text,
    modification_ts timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
)
SERVER kea_server OPTIONS (schema_name 'public', table_name 'dhcp4_server');

CREATE FOREIGN TABLE kea_parameter_data_type (
    id smallint NOT NULL,
    name varchar(32) NOT NULL
)
SERVER kea_server OPTIONS (schema_name 'public', table_name 'parameter_data_type');

CREATE FOREIGN TABLE kea_dhcp4_global_parameter (
    id serial NOT NULL,
    name varchar(128) NOT NULL,
    value text NOT NULL,
    modification_ts timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    parameter_type smallint NOT NULL
)
SERVER kea_server OPTIONS (schema_name 'public', table_name 'dhcp4_global_parameter');

CREATE FOREIGN TABLE kea_dhcp4_global_parameter_server (
    parameter_id bigint NOT NULL,
    server_id bigint NOT NULL,
    modification_ts timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
)
SERVER kea_server OPTIONS (schema_name 'public', table_name 'dhcp4_global_parameter_server');

CREATE FOREIGN TABLE kea_dhcp4_subnet (
    subnet_id bigint NOT NULL,
    subnet_prefix varchar(64) NOT NULL,
    interface_4o6 varchar(128) DEFAULT NULL::varchar,
    interface_id_4o6 varchar(128) DEFAULT NULL::varchar,
    subnet_4o6 varchar(64) DEFAULT NULL::varchar,
    boot_file_name varchar(128) DEFAULT NULL::varchar,
    client_classes text DEFAULT NULL::varchar,
    interface varchar(128) DEFAULT NULL::varchar,
    match_client_id boolean,
    modification_ts timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    next_server inet,
    rebind_timer bigint,
    relay text,
    renew_timer bigint,
    evaluate_additional_classes text,
    server_hostname varchar(64) DEFAULT NULL::varchar,
    shared_network_name varchar(128) DEFAULT NULL::varchar,
    user_context json,
    valid_lifetime bigint,
    authoritative boolean,
    calculate_tee_times boolean,
    t1_percent double precision,
    t2_percent double precision,
    min_valid_lifetime bigint,
    max_valid_lifetime bigint,
    ddns_send_updates boolean,
    ddns_override_no_update boolean,
    ddns_override_client_update boolean,
    ddns_replace_client_name bigint,
    ddns_generated_prefix varchar(255) DEFAULT NULL::varchar,
    ddns_qualifying_suffix varchar(255) DEFAULT NULL::varchar,
    reservations_global boolean,
    reservations_in_subnet boolean,
    reservations_out_of_pool boolean,
    cache_threshold double precision,
    cache_max_age bigint,
    offer_lifetime bigint,
    allocator text,
    ddns_ttl_percent double precision,
    ddns_ttl bigint,
    ddns_ttl_min bigint,
    ddns_ttl_max bigint
)
SERVER kea_server OPTIONS (schema_name 'public', table_name 'dhcp4_subnet');

CREATE FOREIGN TABLE kea_dhcp4_subnet_server (
    subnet_id bigint NOT NULL,
    server_id bigint NOT NULL,
    modification_ts timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
)
SERVER kea_server OPTIONS (schema_name 'public', table_name 'dhcp4_subnet_server');

-- Subnets are all always associated with server id '1' (aka 'all')
CREATE OR REPLACE FUNCTION proc_kea_dhcp4_subnet_insert() RETURNS trigger AS $$
BEGIN
    INSERT INTO kea_dhcp4_subnet_server (subnet_id, server_id) VALUES (new.subnet_id, 1);

    RETURN NULL;
END
$$ LANGUAGE plpgsql;
CREATE TRIGGER kea_dhcp4_subnet_insert AFTER INSERT ON kea_dhcp4_subnet FOR EACH ROW EXECUTE FUNCTION proc_kea_dhcp4_subnet_insert();

CREATE FOREIGN TABLE kea_dhcp4_client_class (
    id serial,
    name varchar(128) NOT NULL,
    test text,
    next_server inet,
    server_hostname varchar(128) DEFAULT NULL::varchar,
    boot_file_name varchar(512) DEFAULT NULL::varchar,
    only_in_additional_list boolean DEFAULT false CONSTRAINT dhcp4_client_class_only_if_required_not_null NOT NULL,
    valid_lifetime bigint,
    min_valid_lifetime bigint,
    max_valid_lifetime bigint,
    depend_on_known_directly boolean DEFAULT false NOT NULL,
    follow_class_name varchar(128) DEFAULT NULL::varchar,
    modification_ts timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    user_context json,
    offer_lifetime bigint
)
SERVER kea_server OPTIONS (schema_name 'public', table_name 'dhcp4_client_class');

CREATE FOREIGN TABLE kea_dhcp4_client_class_server (
    class_id bigint NOT NULL,
    server_id bigint NOT NULL,
    modification_ts timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
)
SERVER kea_server OPTIONS (schema_name 'public', table_name 'dhcp4_client_class_server');

-- Client classes are all always associated with server id '1' (aka 'all')
CREATE OR REPLACE FUNCTION proc_kea_dhcp4_client_class_insert() RETURNS trigger AS $$
BEGIN
    INSERT INTO kea_dhcp4_client_class_server (class_id, server_id) VALUES (new.id, 1);

    RETURN NULL;
END
$$ LANGUAGE plpgsql;
CREATE TRIGGER kea_dhcp4_client_class_insert AFTER INSERT ON kea_dhcp4_client_class FOR EACH ROW EXECUTE FUNCTION proc_kea_dhcp4_client_class_insert();

CREATE FOREIGN TABLE kea_dhcp_option_scope (
    scope_id smallint NOT NULL,
    scope_name varchar(32) DEFAULT NULL::varchar
)
SERVER kea_server OPTIONS (schema_name 'public', table_name 'dhcp_option_scope');

CREATE FOREIGN TABLE kea_dhcp4_options (
    option_id serial NOT NULL,
    code smallint NOT NULL,
    value bytea,
    formatted_value text,
    space varchar(128) DEFAULT NULL::varchar,
    persistent boolean DEFAULT false NOT NULL,
    dhcp_client_class varchar(128) DEFAULT NULL::varchar,
    dhcp4_subnet_id bigint,
    host_id integer,
    scope_id smallint NOT NULL,
    user_context text,
    shared_network_name varchar(128) DEFAULT NULL::varchar,
    pool_id bigint,
    modification_ts timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    cancelled boolean DEFAULT false NOT NULL,
    client_classes text
)
SERVER kea_server OPTIONS (schema_name 'public', table_name 'dhcp4_options');

CREATE FOREIGN TABLE kea_dhcp4_options_server (
    option_id bigint NOT NULL,
    server_id bigint NOT NULL,
    modification_ts timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
)
SERVER kea_server OPTIONS (schema_name 'public', table_name 'dhcp4_options_server');

CREATE FOREIGN TABLE kea_host_identifier_type (
    type smallint NOT NULL,
    name varchar(32) DEFAULT NULL::varchar
)
SERVER kea_server OPTIONS (schema_name 'public', table_name 'host_identifier_type');

CREATE FOREIGN TABLE kea_hosts (
    host_id integer NOT NULL,
    dhcp_identifier bytea NOT NULL,
    dhcp_identifier_type smallint NOT NULL,
    dhcp4_subnet_id bigint,
    dhcp6_subnet_id bigint,
    ipv4_address bigint,
    hostname varchar(255) DEFAULT NULL::varchar,
    dhcp4_client_classes varchar(255) DEFAULT NULL::varchar,
    dhcp6_client_classes varchar(255) DEFAULT NULL::varchar,
    dhcp4_next_server bigint,
    dhcp4_server_hostname varchar(64) DEFAULT NULL::varchar,
    dhcp4_boot_file_name varchar(128) DEFAULT NULL::varchar,
    user_context text,
    auth_key varchar(32) DEFAULT NULL::varchar
)
SERVER kea_server OPTIONS (schema_name 'public', table_name 'hosts');

CREATE FOREIGN TABLE kea_dhcp4_option_def (
    id serial,
    code smallint NOT NULL,
    name varchar(128) NOT NULL,
    space varchar(128) NOT NULL,
    type smallint NOT NULL,
    modification_ts timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    is_array boolean NOT NULL,
    encapsulate varchar(128) NOT NULL,
    record_types varchar,
    user_context json,
    class_id bigint
)
SERVER kea_server OPTIONS (schema_name 'public', table_name 'dhcp4_option_def');

CREATE FOREIGN TABLE kea_option_def_data_type (
    id smallint NOT NULL,
    name varchar(32) NOT NULL
)
SERVER kea_server OPTIONS (schema_name 'public', table_name 'option_def_data_type');

-- supports local code lookups 
CREATE TABLE dhcp4_option_def (
    id serial,
    code smallint NOT NULL,
    name varchar(128) NOT NULL,
    space varchar(128) NOT NULL,
    type smallint NOT NULL,
    modification_ts timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    is_array boolean NOT NULL,
    encapsulate varchar(128) NOT NULL,
    record_types varchar,
    user_context json,
    class_id bigint
);

-- dhcp4
INSERT INTO dhcp4_option_def (code, name, space, type, is_array, encapsulate, record_types) VALUES
--  (1, 'subnet-mask', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
    (2, 'time-offset', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'int32'), false, '', NULL)
,   (3, 'routers', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (4, 'time-servers', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (5, 'name-servers', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (6, 'domain-name-servers', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (7, 'log-servers', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (8, 'cookie-servers', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (9, 'lpr-servers', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (10, 'impress-servers', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (11, 'resource-location-servers', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
--  (12, 'host-name', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (13, 'boot-size', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'uint16'), false, '', NULL)
,   (14, 'merit-dump', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (15, 'domain-name', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'fqdn'), false, '', NULL)
,   (16, 'swap-server', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), false, '', NULL)
,   (17, 'root-path', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (18, 'extensions-path', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (19, 'ip-forwarding', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'boolean'), false, '', NULL)
,   (20, 'non-local-source-routing', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'boolean'), false, '', NULL)
,   (21, 'policy-filter', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (22, 'max-dgram-reassembly', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'uint16'), false, '', NULL)
,   (23, 'default-ip-ttl', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'uint8'), false, '', NULL)
,   (24, 'path-mtu-aging-timeout', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'uint32'), false, '', NULL)
,   (25, 'path-mtu-plateau-table', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'uint16'), true, '', NULL)
,   (26, 'interface-mtu', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'uint16'), false, '', NULL)
,   (27, 'all-subnets-local', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'boolean'), false, '', NULL)
,   (28, 'broadcast-address', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), false, '', NULL)
,   (29, 'perform-mask-discovery', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'boolean'), false, '', NULL)
,   (30, 'mask-supplier', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'boolean'), false, '', NULL)
,   (31, 'router-discovery', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'boolean'), false, '', NULL)
,   (32, 'router-solicitation-address', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), false, '', NULL)
,   (33, 'static-routes', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (34, 'trailer-encapsulation', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'boolean'), false, '', NULL)
,   (35, 'arp-cache-timeout', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'uint32'), false, '', NULL)
,   (36, 'ieee802-3-encapsulation', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'boolean'), false, '', NULL)
,   (37, 'default-tcp-ttl', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'uint8'), false, '', NULL)
,   (38, 'tcp-keepalive-interval', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'uint32'), false, '', NULL)
,   (39, 'tcp-keepalive-garbage', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'boolean'), false, '', NULL)
,   (40, 'nis-domain', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (41, 'nis-servers', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (42, 'ntp-servers', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (43, 'vendor-encapsulated-options', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'empty'), false, '', NULL)
,   (44, 'netbios-name-servers', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (45, 'netbios-dd-server', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (46, 'netbios-node-type', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'uint8'), false, '', NULL)
,   (47, 'netbios-scope', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (48, 'font-servers', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (49, 'x-display-manager', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (52, 'dhcp-option-overload', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'uint8'), false, '', NULL)
,   (54, 'dhcp-server-identifier', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), false, '', NULL)
,   (56, 'dhcp-message', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (57, 'dhcp-max-message-size', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'uint16'), false, '', NULL)
,   (60, 'vendor-class-identifier', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (62, 'nwip-domain-name', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (63, 'nwip-suboptions', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'binary'), false, '', NULL)
,   (64, 'nisplus-domain-name', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (65, 'nisplus-servers', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (66, 'tftp-server-name', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (67, 'boot-file-name', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (68, 'mobile-ip-home-agent', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (69, 'smtp-server', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (70, 'pop-server', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (71, 'nntp-server', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (72, 'www-server', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (73, 'finger-server', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (74, 'irc-server', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (75, 'streettalk-server', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (76, 'streettalk-directory-assistance-server', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (77, 'user-class', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'binary'), false, '', NULL)
,   (78, 'slp-directory-agent', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'record'), true, '', ('[' ||
                    (SELECT id FROM kea_option_def_data_type WHERE name = 'boolean')
        || ', ' ||  (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address')
    || ']'))
,   (79, 'slp-service-scope', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'record'), false, '', ('[' ||
                    (SELECT id FROM kea_option_def_data_type WHERE name = 'boolean')
        || ', ' ||  (SELECT id FROM kea_option_def_data_type WHERE name = 'string')
    || ']'))
,   (85, 'nds-server', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (86, 'nds-tree-name', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (87, 'nds-context', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (88, 'bcms-controller-names', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'fqdn'), true, '', NULL)
,   (89, 'bcms-controller-address', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (93, 'client-system', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'uint16'), true, '', NULL)
,   (94, 'client-ndi', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'record'), false, '', ('[' ||
                    (SELECT id FROM kea_option_def_data_type WHERE name = 'uint8')
        || ', ' ||  (SELECT id FROM kea_option_def_data_type WHERE name = 'uint8')
        || ', ' ||  (SELECT id FROM kea_option_def_data_type WHERE name = 'uint8')
    || ']'))
,   (97, 'uuid-guid', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'record'), false, '', ('[' ||
                    (SELECT id FROM kea_option_def_data_type WHERE name = 'uint8')
        || ', ' ||  (SELECT id FROM kea_option_def_data_type WHERE name = 'binary')
    || ']'))
,   (98, 'uap-servers', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (99, 'geoconf-civic', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'binary'), false, '', NULL)
,   (100, 'pcode', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (101, 'tcode', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (108, 'v6-only-preferred', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'uint32'), false, '', NULL)
,   (112, 'netinfo-server-address', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (113, 'netinfo-server-tag', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (114, 'v4-captive-portal', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'string'), false, '', NULL)
,   (116, 'auto-config', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'uint8'), false, '', NULL)
,   (117, 'name-service-search', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'uint16'), true, '', NULL)
,   (119, 'domain-search', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'fqdn'), true, '', NULL)
,   (124, 'vivco-suboptions', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'record'), false, '', ('[' ||
                    (SELECT id FROM kea_option_def_data_type WHERE name = 'uint32')
        || ', ' ||  (SELECT id FROM kea_option_def_data_type WHERE name = 'binary')
    || ']'))
,   (125, 'vivso-suboptions', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'uint32'), false, '', NULL)
,   (136, 'pana-agent', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (137, 'v4-lost', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'fqdn'), false, '', NULL)
,   (138, 'capwap-ac-v4', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address'), true, '', NULL)
,   (141, 'sip-ua-cs-domains', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'fqdn'), true, '', NULL)
,   (146, 'rdnss-selection', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'record'), true, '', ('[' ||
                    (SELECT id FROM kea_option_def_data_type WHERE name = 'uint8')
        || ', ' ||  (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address')
        || ', ' ||  (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address')
        || ', ' ||  (SELECT id FROM kea_option_def_data_type WHERE name = 'fqdn')
    || ']'))
,   (159, 'v4-portparams', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'record'), false, '', ('[' ||
                    (SELECT id FROM kea_option_def_data_type WHERE name = 'uint8')
        || ', ' ||  (SELECT id FROM kea_option_def_data_type WHERE name = 'psid')
    || ']'))
,   (212, 'option-6rd', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'record'), true, '', ('[' ||
                    (SELECT id FROM kea_option_def_data_type WHERE name = 'uint8')
        || ', ' ||  (SELECT id FROM kea_option_def_data_type WHERE name = 'uint8')
        || ', ' ||  (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv6-address')
        || ', ' ||  (SELECT id FROM kea_option_def_data_type WHERE name = 'ipv4-address')
    || ']'))
,   (213, 'v4-access-domain', 'dhcp4', (SELECT id FROM kea_option_def_data_type WHERE name = 'fqdn'), false, '', NULL)
;

CREATE OR REPLACE VIEW kea_dhcp4_option_def_lookup AS
    SELECT * FROM kea_dhcp4_option_def
    UNION ALL
    SELECT * FROM dhcp4_option_def;
