--------------------------------------------------------------------------------
-- Name:
--	create_database_link_prod.nwfwmd.state.fl.us.sql
--
-- Purpose:
--	Create database link required for system integration procedures to
--	to access source data in legacy database
--
-- Usage:
--	@create_database_link_prod.nwfwmd.state.fl.us.sql
--
-- Environment:
--	Oracle Database 11.2.0.4.0
--
-- Notes:
--	This script should be run while connected as the Oracle user GIS,
--	the owner of the GIS_REFRESH package. The GIS.GIS_REFRESH package
--	depends on the database link created below for accessing source data
--	in the legacy database.
--
--	The database link connects as the READONLY user in the legacy database.
--	This is the same user as whom the original system integration solution
--	connected. In turn, READONLY has access to the source data required
--	for populating the derived feature classes in the geodatabase. The
--	script will prompt interactively for the READONLY user's password.
--
--	The database link is configured using a connect descriptor, directly,
--	rather than an Oracle Net alias (e.g. tnsnames.ora entry).
--
-- History:
--	20140919 MCM Created
--
-- To do:
--	none
--
-- Copyright 2003-2014. Mannion Geosystems, LLC. http://www.manniongeo.com
--------------------------------------------------------------------------------

SET VERIFY OFF



ACCEPT password_readonly PROMPT "Enter password for READONLY" HIDE

CREATE DATABASE LINK prod.nwfwmd.state.fl.us
CONNECT TO readonly
	IDENTIFIED BY &password_readonly
USING '(DESCRIPTION=(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=oracle)(PORT=1521)))(CONNECT_DATA=(SERVICE_NAME=prod)))'
;



SET VERIFY ON
