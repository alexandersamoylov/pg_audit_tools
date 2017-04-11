-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_audit_tools" to load this file. \quit


COMMENT ON SCHEMA audit_tools IS 'pg_audit_tools extension';


-- Function: audit_tools.table_history_tf()

CREATE OR REPLACE FUNCTION audit_tools.table_history_tf()
    RETURNS trigger AS
$body$
DECLARE

    v_table_history text;
    v_table_history_seq text;
    v_sql_text text;

BEGIN

    SELECT quote_ident(nspname) || '.' || quote_ident(relname
            || '_history') AS table_history,
        quote_ident(nspname) || '.' || quote_ident(relname
            || '_history_aud_historyid_seq') AS table_history_seq
        INTO v_table_history, v_table_history_seq
    FROM pg_class pc
    INNER JOIN pg_namespace pn ON pc.relnamespace = pn.oid
    WHERE pc.oid = TG_RELID;

    v_sql_text = 'INSERT INTO ' || v_table_history
        || ' SELECT nextval(' || quote_literal(v_table_history_seq)
        || '), $1, now(), ($2).*;';
    
    IF (TG_OP = 'INSERT') THEN
        NEW.aud_create_time := now();
        NEW.aud_update_time := NULL;
        NEW.aud_user := session_user;
        RETURN NEW;
    ELSIF (TG_OP = 'UPDATE') THEN
        EXECUTE v_sql_text USING 'U', OLD;
        NEW.aud_create_time := OLD.aud_create_time;
        NEW.aud_update_time := now();
        NEW.aud_user := session_user;
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        EXECUTE v_sql_text USING 'D', OLD;
        RETURN OLD;
    END IF;

    RETURN NEW;

END;
$body$
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER;


-- Function: audit_tools.table_history_create(character varying,
--      character varying)

CREATE OR REPLACE FUNCTION audit_tools.table_history_create(
        p_table_schema character varying,
        p_table_name character varying)
    RETURNS text AS
$body$
DECLARE

    v_table text;
    v_table_history text;
    v_table_history_seq text;
    v_sql_text text;

BEGIN

    v_table := quote_ident(p_table_schema) || '.' || quote_ident(p_table_name);
    v_table_history := quote_ident(p_table_schema)
        || '.' || quote_ident(p_table_name || '_history');
    v_table_history_seq := quote_ident(p_table_schema)
        || '.' || quote_ident(p_table_name || '_history_aud_historyid_seq');
    
    -- Добавление полей аудита в таблицу
    
    v_sql_text := 'ALTER TABLE ' || v_table || '
    ADD COLUMN IF NOT EXISTS aud_create_time timestamp with time zone NOT NULL
    DEFAULT now(),
    ADD COLUMN IF NOT EXISTS aud_update_time timestamp with time zone,
    ADD COLUMN IF NOT EXISTS aud_user name NOT NULL DEFAULT now();';
    EXECUTE v_sql_text;
    
    -- Создание таблицы для истории изменений
     
    v_sql_text := 'CREATE TABLE '|| v_table_history || ' AS
SELECT
    1::bigint AS aud_historyid,
    ''1''::character varying(1) AS aud_history_reason,
    now()::timestamp with time zone AS aud_history_time,
    t.*
FROM ' || v_table || ' t
WHERE 1=2;';
    EXECUTE v_sql_text;
    
    -- Создание сиквенса для таблицы с историей

    v_sql_text := 'CREATE SEQUENCE ' || v_table_history_seq || '
    INCREMENT 1
    MINVALUE 0
    MAXVALUE 999999999999999
    START 1
    CACHE 1;';
    EXECUTE v_sql_text;
    
    -- Добавление констрейнтов для таблицы с историей
    
    v_sql_text := 'ALTER TABLE ' || v_table_history || '
    ALTER COLUMN aud_historyid SET NOT NULL,
    ALTER COLUMN aud_historyid SET DEFAULT nextval('''
    || v_table_history_seq || '''),
    ALTER COLUMN aud_history_reason SET NOT NULL,
    ALTER COLUMN aud_history_time SET NOT NULL,
    ADD CONSTRAINT ' || quote_ident(p_table_name || '_history_pk') || '
        PRIMARY KEY (aud_historyid);';
    EXECUTE v_sql_text;

    -- Создание триггера
    
    v_sql_text := 'CREATE TRIGGER ' || quote_ident(p_table_name
        || '_history') || '
    BEFORE INSERT OR UPDATE OR DELETE ON ' || v_table || '
    FOR EACH ROW EXECUTE PROCEDURE audit_tools.table_history_tf();';
    EXECUTE v_sql_text;
    

    RETURN 'successfuly';

END;
$body$
    LANGUAGE plpgsql VOLATILE SECURITY DEFINER;

