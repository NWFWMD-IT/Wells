--------------------------------------------------------------------------------
-- Name:
--	create_database_links_sjrwmd.sql
--
-- Purpose:
--	Create database links for system integration with NWFWMD databases
--	hosted at SJRWMD
--
-- Usage:
--	@create_database_link_sjrwmd.sql
--
-- Environment:
--	Oracle Database 11.2.0.4.0
--
-- Notes:
--	This script should be run while connected as the Oracle user GIS,
--	the owner of the GIS_REFRESH package. The GIS.GIS_REFRESH package
--	depends on the database links created below for accessing source data
--	in the SJRWMD-hosted databases.
--
--	The database links connect as the ANONYMOUS user in the SJRWMD
--	databases. This general purpose, read-only user has access to
--	a variety of source data of interest to users and applications
--	at NWFWMD. This script assumes that the ANONYMOUS users in all
--	remote databases share the same password.
--
--	The database links are configured using connect descriptors, directly,
--	rather than Oracle Net aliases (e.g. tnsnames.ora entry).
--
-- History:
--	20150601 MCM Created
--
-- To do:
--	Determine equivalent user to ANONYMOUS in NWSDE; update corresponding
--	 CREATE statement below
--
-- Copyright 2003-2015. Mannion Geosystems, LLC. http://www.manniongeo.com
--------------------------------------------------------------------------------

SET VERIFY OFF



ACCEPT password_anonymous PROMPT "Enter password for ANONYMOUS: " HIDE

--
-- NWPROD
--

CREATE DATABASE LINK nwprod.sjrwmd.com
CONNECT TO anonymous
	IDENTIFIED BY &password_anonymous
USING '(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=nwdbprod1.sjrwmd.com)(PORT=1521)))(CONNECT_DATA=(SERVER=)(SERVICE_NAME=nwprod)))'
;



--
-- NWSDE
--

-- CREATE DATABASE LINK nwsde.sjrwmd.com
-- CONNECT TO anonymous
	-- IDENTIFIED BY &password_anonymous
-- USING '(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=nwdbprod1.sjrwmd.com)(PORT=1521))(LOAD_BALANCE=yes))(CONNECT_DATA=(SERVER=)(SERVICE_NAME=nwsde)(FAILOVER_MODE=(TYPE=SELECT)(METHOD=BASIC))))'
-- ;



--
-- NWWHP
--

CREATE DATABASE LINK nwwhp.sjrwmd.com
CONNECT TO anonymous
	IDENTIFIED BY &password_anonymous
USING '(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=nwdbprod1.sjrwmd.com)(PORT=1521)))(CONNECT_DATA=(SERVER=)(SERVICE_NAME=nwwhp)))'
;



SET VERIFY ON
