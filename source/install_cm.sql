--------------------------------------------------------------------------------
-- Users and privileges
--------------------------------------------------------------------------------

--------------------
-- User: CM
--------------------

CREATE USER cm
IDENTIFIED BY cm
DEFAULT TABLESPACE users
QUOTA UNLIMITED ON users
PASSWORD EXPIRE
ACCOUNT LOCK
;


GRANT
	CREATE TABLE
	,CREATE VIEW
TO
	cm
;



--------------------
-- Roles
--------------------

CREATE ROLE cm_read;

CREATE ROLE cm_write;



--------------------------------------------------------------------------------
-- Tables
--------------------------------------------------------------------------------


--------------------
-- Table: CM.NWFWMD
--------------------

CREATE TABLE cm.nwfwmd (
	id			NUMBER -- Single column unique ID, for ArcGIS
	,owner_name		VARCHAR2(30)
	,table_name		VARCHAR2(30)
	,column_name		VARCHAR2(30)
	,description		CLOB
	,comments		CLOB
	,CONSTRAINT nwfwmd_pk PRIMARY KEY (id)
	,CONSTRAINT nwfwmd_u1 UNIQUE (
		owner_name
		,table_name
		,column_name
	)
)
;


CREATE SEQUENCE cm.nwfwmd_id;


CREATE OR REPLACE TRIGGER cm.nwfwmd_id
BEFORE
	INSERT 
	OR UPDATE OF id
ON cm.nwfwmd
FOR EACH ROW
BEGIN

	CASE
		WHEN INSERTING THEN
		
			IF :NEW.id IS NOT NULL THEN
			
				RAISE_APPLICATION_ERROR(
					-20000
					,'Primary key (ID) is set automatically on INSERT, and cannot be set explicitly'
				);
				
			END IF;

			:NEW.id := cm.nwfwmd_id.NEXTVAL;
			:NEW.owner_name := UPPER(:NEW.owner_name);
			:NEW.table_name := UPPER(:NEW.table_name);
			:NEW.column_name := UPPER(:NEW.column_name);
				
				
		WHEN UPDATING ('id') THEN
		
			IF :NEW.id != :OLD.id THEN
			
				RAISE_APPLICATION_ERROR(
					-20001
					,'Primary key (ID) value cannot be changed'
				);
				
			END IF;
			
		WHEN UPDATING ('owner_name') THEN
		
			:NEW.owner_name := UPPER(:NEW.owner_name);

		WHEN UPDATING ('table_name') THEN
		
			:NEW.table_name := UPPER(:NEW.table_name);

		WHEN UPDATING ('column_name') THEN
		
			:NEW.column_name := UPPER(:NEW.column_name);
			
	END CASE;

END;
/


GRANT
	SELECT
ON
	cm.nwfwmd
TO
	cm_read
;


GRANT
	DELETE
	,INSERT
	,SELECT
	,UPDATE
ON
	cm.nwfwmd
TO
	cm_write
;
	


--------------------
-- Table: CM.SJRWMD
--------------------

CREATE TABLE cm.sjrwmd (
	id			NUMBER -- Single column unique ID, for ArcGIS
	,owner_name		VARCHAR2(30)
	,table_name		VARCHAR2(30)
	,column_name		VARCHAR2(30)
	,description		CLOB
	,comments		CLOB
	,CONSTRAINT sjrwmd_pk PRIMARY KEY (id)
	,CONSTRAINT sjrwmd_u1 UNIQUE (
		owner_name
		,table_name
		,column_name
	)
)
;


CREATE SEQUENCE cm.sjrwmd_id;


CREATE OR REPLACE TRIGGER cm.sjrwmd_id
BEFORE
	INSERT 
	OR UPDATE OF id
ON cm.sjrwmd
FOR EACH ROW
BEGIN

	CASE
		WHEN INSERTING THEN
		
			IF :NEW.id IS NOT NULL THEN
			
				RAISE_APPLICATION_ERROR(
					-20000
					,'Primary key (ID) is set automatically on INSERT, and cannot be set explicitly'
				);
				
			END IF;

			:NEW.id := cm.sjrwmd_id.NEXTVAL;
			:NEW.owner_name := UPPER(:NEW.owner_name);
			:NEW.table_name := UPPER(:NEW.table_name);
			:NEW.column_name := UPPER(:NEW.column_name);
				
				
		WHEN UPDATING ('id') THEN
		
			IF :NEW.id != :OLD.id THEN
			
				RAISE_APPLICATION_ERROR(
					-20001
					,'Primary key (ID) value cannot be changed'
				);
				
			END IF;
			
		WHEN UPDATING ('owner_name') THEN
		
			:NEW.owner_name := UPPER(:NEW.owner_name);

		WHEN UPDATING ('table_name') THEN
		
			:NEW.table_name := UPPER(:NEW.table_name);

		WHEN UPDATING ('column_name') THEN
		
			:NEW.column_name := UPPER(:NEW.column_name);
			
	END CASE;

END;
/


GRANT
	SELECT
ON
	cm.sjrwmd
TO
	cm_read
;


GRANT
	DELETE
	,INSERT
	,SELECT
	,UPDATE
ON
	cm.sjrwmd
TO
	cm_write
;



--------------------
-- Table: CM.DERIVED
--------------------

CREATE TABLE cm.derived (
	id			NUMBER -- Single column unique ID, for ArcGIS
	,owner_name		VARCHAR2(30)
	,table_name		VARCHAR2(30)
	,column_name		VARCHAR2(30)
	,description		CLOB
	,comments		CLOB
	,CONSTRAINT derived_pk PRIMARY KEY (id)
	,CONSTRAINT derived_u1 UNIQUE (
		owner_name
		,table_name
		,column_name
	)
)
;


CREATE SEQUENCE cm.derived_id;


CREATE OR REPLACE TRIGGER cm.derived_id
BEFORE
	INSERT 
	OR UPDATE OF id
ON cm.derived
FOR EACH ROW
BEGIN

	CASE
		WHEN INSERTING THEN
		
			IF :NEW.id IS NOT NULL THEN
			
				RAISE_APPLICATION_ERROR(
					-20000
					,'Primary key (ID) is set automatically on INSERT, and cannot be set explicitly'
				);
				
			END IF;

			:NEW.id := cm.derived_id.NEXTVAL;
			:NEW.owner_name := UPPER(:NEW.owner_name);
			:NEW.table_name := UPPER(:NEW.table_name);
			:NEW.column_name := UPPER(:NEW.column_name);
				
				
		WHEN UPDATING ('id') THEN
		
			IF :NEW.id != :OLD.id THEN
			
				RAISE_APPLICATION_ERROR(
					-20001
					,'Primary key (ID) value cannot be changed'
				);
				
			END IF;
			
		WHEN UPDATING ('owner_name') THEN
		
			:NEW.owner_name := UPPER(:NEW.owner_name);

		WHEN UPDATING ('table_name') THEN
		
			:NEW.table_name := UPPER(:NEW.table_name);

		WHEN UPDATING ('column_name') THEN
		
			:NEW.column_name := UPPER(:NEW.column_name);
			
	END CASE;

END;
/


GRANT
	SELECT
ON
	cm.derived
TO
	cm_read
;


GRANT
	DELETE
	,INSERT
	,SELECT
	,UPDATE
ON
	cm.derived
TO
	cm_write
;



--------------------
-- Table: CM.J_NWFWMD__SJRWMD
--------------------

CREATE TABLE cm.j_nwfwmd__sjrwmd (
	nwfwmd_id		NUMBER
	,sjrwmd_id		NUMBER
	,comments		CLOB
	,CONSTRAINT j_nwfwmd__sjrwmd_pk PRIMARY KEY (
		nwfwmd_id
		,sjrwmd_id
	)
	,CONSTRAINT j_nwfwmd__sjrwmd_f1 FOREIGN KEY (nwfwmd_id) REFERENCES cm.nwfwmd (id)
	,CONSTRAINT j_nwfmwd__sjrwmd_f2 FOREIGN KEY (sjrwmd_id) REFERENCES cm.sjrwmd (id)
)
;


GRANT
	SELECT
ON
	cm.j_nwfwmd__sjrwmd
TO
	cm_read
;


GRANT
	DELETE
	,INSERT
	,SELECT
	,UPDATE
ON
	cm.j_nwfwmd__sjrwmd
TO
	cm_write
;



--------------------
-- Table: CM.J_SJRWMD__DERIVED
--------------------

CREATE TABLE cm.j_sjrwmd__derived (
	sjrwmd_id		NUMBER
	,derived_id		NUMBER
	,comments		CLOB
	,CONSTRAINT j_sjrwmd__derived_pk PRIMARY KEY (
		sjrwmd_id
		,derived_id
	)
	,CONSTRAINT j_sjrwmd__derived_f1 FOREIGN KEY (sjrwmd_id) REFERENCES cm.sjrwmd (id)
	,CONSTRAINT j_sjrwmd__derived_f2 FOREIGN KEY (derived_id) REFERENCES cm.derived (id)
)
;


GRANT
	SELECT
ON
	cm.j_sjrwmd__derived
TO
	cm_read
;


GRANT
	DELETE
	,INSERT
	,SELECT
	,UPDATE
ON
	cm.j_sjrwmd__derived
TO
	cm_write
;



--------------------------------------------------------------------------------
-- Views
--------------------------------------------------------------------------------


--------------------
-- View: CM.NWFWMD_SJRWMD_MAPPING
--------------------

CREATE OR REPLACE VIEW cm.nwfwmd_sjrwmd_mapping
AS
SELECT
	n.owner_name nwfwmd_owner
	,n.table_name nwfwmd_table
	,n.column_name nwfwmd_column
	,s.owner_name sjrwmd_owner
	,s.table_name sjrwmd_table
	,s.column_name sjrwmd_column
	,n.description nwfwmd_description
	,n.comments nwfwmd_comments
	,s.description sjrwmd_description
	,s.comments sjrwmd_comments
	,jns.comments mapping_comments
FROM cm.nwfwmd n
INNER JOIN cm.j_nwfwmd__sjrwmd jns
	ON
		n.id = jns.nwfwmd_id
INNER JOIN cm.sjrwmd s
	ON
		jns.sjrwmd_id = s.id
;


GRANT
	SELECT
ON
	cm.nwfwmd_sjrwmd_mapping
TO
	cm_read
	,cm_write
;



--------------------
-- View: CM.NWFWMD_NO_TARGET
--------------------

CREATE OR REPLACE VIEW cm.nwfwmd_no_target
AS
SELECT
	n.owner_name nwfwmd_owner
	,n.table_name nwfwmd_table
	,n.column_name nwfwmd_column
	,n.description nwfwmd_description
	,n.comments nwfwmd_comments
FROM cm.nwfwmd n
LEFT JOIN cm.j_nwfwmd__sjrwmd jns
	ON
		n.id = jns.nwfwmd_id
WHERE
	jns.nwfwmd_id IS NULL
;


GRANT
	SELECT
ON
	cm.nwfwmd_no_target
TO
	cm_read
	,cm_write
;



--------------------
-- View: CM.SJRWMD_NO_SOURCE
--------------------

CREATE OR REPLACE VIEW cm.sjrwmd_no_source
AS
SELECT
	s.owner_name sjrwmd_owner
	,s.table_name sjrwmd_table
	,s.column_name sjrwmd_column
	,s.description sjrwmd_description
	,s.comments sjrwmd_comments
FROM cm.sjrwmd s
LEFT JOIN cm.j_nwfwmd__sjrwmd jns
	ON
		s.id = jns.sjrwmd_id
WHERE
	jns.sjrwmd_id IS NULL
;


GRANT
	SELECT
ON
	cm.sjrwmd_no_source
TO
	cm_read
	,cm_write
;


--------------------
-- View: CM.SJRWMD_DERIVED_MAPPING
--------------------

CREATE OR REPLACE VIEW cm.sjrwmd_derived_mapping
AS
SELECT
	s.owner_name sjrwmd_owner
	,s.table_name sjrwmd_table
	,s.column_name sjrwmd_column
	,d.owner_name derived_owner
	,d.table_name derived_table
	,d.column_name derived_column
	,s.description sjrwmd_description
	,s.comments sjrwmd_comments
	,d.description derived_description
	,d.comments derived_comments
	,jsd.comments mapping_comments
FROM cm.sjrwmd s
INNER JOIN cm.j_sjrwmd__derived jsd
	ON
		s.id = jsd.sjrwmd_id
INNER JOIN cm.derived d
	ON
		jsd.derived_id = d.id
;


GRANT
	SELECT
ON
	cm.sjrwmd_derived_mapping
TO
	cm_read
	,cm_write
;



--------------------
-- View: CM.SJRWMD_NO_TARGET
--------------------

CREATE OR REPLACE VIEW cm.sjrwmd_no_target
AS
SELECT
	s.owner_name sjrwmd_owner
	,s.table_name sjrwmd_table
	,s.column_name sjrwmd_column
	,s.description sjrwmd_description
	,s.comments sjrwmd_comments
FROM cm.sjrwmd s
LEFT JOIN cm.j_sjrwmd__derived jsd
	ON
		s.id = jsd.sjrwmd_id
WHERE
	jsd.sjrwmd_id IS NULL
;


GRANT
	SELECT
ON
	cm.sjrwmd_no_target
TO
	cm_read
	,cm_write
;



--------------------
-- View: CM.DERIVED_NO_SOURCE
--------------------

CREATE OR REPLACE VIEW cm.derived_no_source
AS
SELECT
	d.owner_name derived_owner
	,d.table_name derived_table
	,d.column_name derived_column
	,d.description derived_description
	,d.comments derived_comments
FROM cm.derived d
LEFT JOIN cm.j_sjrwmd__derived jsd
	ON
		d.id = jsd.derived_id
WHERE
	jsd.derived_id IS NULL
;


GRANT
	SELECT
ON
	cm.derived_no_source
TO
	cm_read
	,cm_write
;


--------------------------------------------------------------------------------
-- END
--------------------------------------------------------------------------------