--------------------------------------------------------------------------------
-- Name:
--	create_package_gis_refresh.sql
--
-- Purpose:
--	Create GIS.GIS_REFRESH package and package body for managing geodatabase
--	feature classes that are derived from numeric coordinate data and
--	attributes in other business systems
--
-- Usage:
--	As DBA user:
--		@create_package_gis_refresh.sql
--
-- Environment:
--	Oracle Database 11.2.0.4.0
--	ArcGIS for Server 10.6.1
--
-- Notes:
--	This package maintains the contents of ArcGIS feature classes in the
--	NWFWMD enterprise geodatabase from source data stored in other
--	business systems. The refresh procedures below convert longitude and
--	latitude values stored in numeric columns to geodatabase geometries
--	for consumption by ArcGIS client applications, and potentially
--	database-level tools that leverage the ArcGIS SQL API.
--
--	Currently, some of these procedures harvest data from the NWPROD
--	database hosted by St. Johns River Water Management District. NWFWMD
--	has determined that the datum metadata stored in that system is
--	sufficiently unreliable (due both to the quality of the legacy
--	data, as well as the migration process and new eReg workflows) to
--	warrant ignoring the datum metadata altogether (see NWFWMDDI-27).
--	As a result, the refresh procedures assume that the input datum for
--	the numeric coordinates is the same as the output datum for the
--	geometries being constructed (currently NAD83) and does not perform
--	a datum transformation, even if the datum metadata suggests a mismatch.
--
-- History:
--	20140919 MCM Created
--	20150126 MCM Added procedure GIS.GIS_REFRESH.REFRESH_DATABASES_ORPHAN_WELLS
--	20150219 MCM Added DECODE_LOC_METHOD function
--	             Added LOC_METHOD column support for:
--	               DATABASES_ERP
--	               DATABASES_ORPHAN_WELLS
--	               DATABASES_WELL_INVENTORY
--	               DATABASES_WUP_SURFACE
--	               DATABASES_WUP_WELLS
--	             Changed GIS.DATABASES_WELL_PERMITS.LOC_METHOD from number to
--	               text (in feature class creation Python script) and updated
--	               GIS.GIS_REFRESH.REFRESH_WELL_PERMITS to decode source
--	               number values to friendly text values
--	20150404 MCM Removed references to database link in order to use local
--	               tables after database consolidation
--	20150601 MCM Added support for draft "_SJ" feature classes, for evaluating
--	               integration with new NWPROD database at SJRWMD
--	20150911 MCM Added support for consolidated DATABASES_ERP_SITE and
--	               DATABASES_STATION feature classes, including
--	               procedures:
--	                 REFRESH_DATABASES_ERP_SITE
--	                 REFRESH_DATABASES_STATION
--	               functions:
--	                 GET_LOCATION_METHOD
--	                 GET_PERMIT_TYPE
--	               constants:
--	                 ORDINATE_<format>_<boundary>
--	             Change SQL templates from VARCHAR2(4000) to CLOB to
--	               accommodate longer text strings
--	20150916 MCM Removed datum handling code and assume NAD83, per
--	               NWFWMDDI-27
--	             Removed legacy refresh procedures and grants (fetch
--	               from prior Mercurial commit, if required); retained
--	               legacy exceptions and helper functions, for possible
--	               future use
--	20150927 MCM Added PARSE_FULL_APP_NO function; replaced direct fetches
--	              of individual FULL_APP_NO components, and GET_PERMIT_TYPE
--	             Removed legacy helper functions (contrary to decision in
--	               prior update)
--	20151013 MCM Restored two procedures that should not have been removed
--	               during prior cleanup:
--	                 REFRESH_DATABASES_WELL_INV
--	                 REFRESH_DATABASES_WELL_PERMITS
--	             Overhauled to match new semantics and style of ERP_SITE /
--	               STATION procedures
--	             Restored DECODE_LOC_METHOD function
--	             Restored relevant dependency grants on local (ORCL) objects
--	20151115 MCM Added subset feature classes (NWFWMDDI-40):
--	               DATABASES_ERP_SITE_40A_4
--	               DATABASES_ERP_SITE_40A_44
--	               DATABASES_ERP_SITE_62_330
--	               DATABASES_ERP_SITE_FORESTRY
--	             Renamed DATABASES_STATION to DATABASES_REG_STATION (NWFWMDDI-39)
--	20160104 MCM Added attribute columns to DATABASES_WELL_PERMITS (NWFWMDDI-41)
--	             Granted SELECT access to WPS.WPSLUSTAT
--	             Granted SELECT access to WPS.WPSDRILLERS
--	20160121 MCM Restored REFRESH_DATABASES_ORPHAN_WELLS procedure (NWFWMDDI-42)
--	             Updated REFRESH_DATABAES_ORPHAN_WELLS to match current
--	               SQL standards for similar refresh procedures
--	             Added grant for WPS.ORPHAN_WELLS table
--	20160803 MCM Added GIS.DATABASES_WELL_PERMITS.WELL_COUNTY column
--	               (NWFWMDDI-44)
--	20160829 MCM Added columns to GIS.DATABASES_WELL_PERMITS (NWFWMDDI-45)
--	             Granted SELECT access to WPS.SCREEN_TYPES
--	20161016 MCM Added ITEM_NUMBER columns to GIS.DATABASES_ERP_SITE% tables
--	               (NWFWMDDI-46)
--	20161205 MCM For GIS.DATABASES_REG_STATION, changed party role filter
--	               from 'Land Owner' to 'Applicant' (NWFWMDDI-47)
--	20170106 MCM Added REVIEW_DATE columns to GIS.DATABASES_ERP_SITE% tables
--	               (NWFWMDDI-48)
--	20170130 MCM Remove REFRESH_DATABASES_ORPHAN_WELLS procedure (NWFWMDDI-49)
--	20170530 MCM Add value to DECODE_LOC_METHOD function (NWFWMDDI-51)
--	             Allow GET_LOCATION_METHOD to return NULL instead of raising
--	               exception on unknown input (NWFWMDDI-52)
--	20180927 MCM Update REFRESH_DATABASES_WELL_PERMITS to use remote database
--	               with new eReg wells data structures, and miscellaneous
--	               output schema changes (NWFWMDDI-71)
--	             Minor reformatting
--	20180227 MCM Set REVIEW_DATE values to NULL (NWFWMDDI-74)
--	20190830 MCM Overhauled DATABASES_WELL_PERMITS schema and refresh query
--	             Updated value mappings in GET_LOCATION_METHOD (NWFWMDDI-89)
--	20190905 MCM Expanded DATABASES_WELL_PERMITS.RELATED_PERMIT to
--	               RELATED_PERMIT_1 and RELATED_PERMIT_2 (NWFWMDDI-90)
--	20200109 MCM Added getter functions for boundary coordinates (NWFWMDDI-119)
--
-- To do:
--	none
--
-- Copyright 2003-2019. Mannion Geosystems, LLC. http://www.manniongeo.com
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- Grant privileges on dependencies
--------------------------------------------------------------------------------

GRANT SELECT ON	well_inv.wi_well_inv TO gis
/
GRANT SELECT ON wps.screen_types TO GIS
/
GRANT SELECT ON	wps.well_completion TO gis
/
GRANT SELECT ON	wps.well_permits TO gis
/
GRANT SELECT ON	wps.wpslustat TO gis
/
GRANT SELECT ON	wps.wpsdrillers TO gis
/



--------------------------------------------------------------------------------
-- Create package
--------------------------------------------------------------------------------

CREATE OR REPLACE PACKAGE gis.gis_refresh
AUTHID DEFINER
AS
	
	----------------------------------------
	-- Constants
	----------------------------------------
	
	
	-- Envelope outside of which coordinates are considered to be invalid
	-- (currently envelope of 100 mile buffer of NWFWMD boundary)
	
	ORDINATE_DD_XMIN			CONSTANT NUMBER := -89.3;
	ORDINATE_DD_XMAX			CONSTANT NUMBER := -82.0;
	ORDINATE_DD_YMIN			CONSTANT NUMBER := 28.1;
	ORDINATE_DD_YMAX			CONSTANT NUMBER := 32.4;
	
	ORDINATE_DMS_XMIN			CONSTANT NUMBER := -891800;
	ORDINATE_DMS_XMAX			CONSTANT NUMBER := -820000;
	ORDINATE_DMS_YMIN			CONSTANT NUMBER := 280600;
	ORDINATE_DMS_YMAX			CONSTANT NUMBER := 322400;
	
	ORDINATE_UTM_XMIN			CONSTANT NUMBER := 278384;
	ORDINATE_UTM_XMAX			CONSTANT NUMBER := 970683;
	ORDINATE_UTM_YMIN			CONSTANT NUMBER := 3113692;
	ORDINATE_UTM_YMAX			CONSTANT NUMBER := 3592337;


	
	----------------------------------------
	-- Exceptions
	--
	-- Includes legacy exceptions, for context and possible future reuse
	----------------------------------------

	invalid_ordinate		EXCEPTION;
	
	PRAGMA EXCEPTION_INIT(
		invalid_ordinate
		,-20000
	);
	

	unknown_spatial_reference	EXCEPTION;
	
	PRAGMA EXCEPTION_INIT(
		unknown_spatial_reference
		,-20001
	);
	

	unknown_permit_type		EXCEPTION;
	
	PRAGMA EXCEPTION_INIT(
		unknown_permit_type
		,-20002
	);
	

	unknown_ordinate_format		EXCEPTION;
	
	PRAGMA EXCEPTION_INIT(
		unknown_ordinate_format
		,-20003
	);
	

	unknown_limit_name		EXCEPTION;
	
	PRAGMA EXCEPTION_INIT(
		unknown_limit_name
		,-20004
	);
	

	unknown_location_method		EXCEPTION;
	
	PRAGMA EXCEPTION_INIT(
		unknown_location_method
		,-20005
	);
	

	invalid_component_index		EXCEPTION;
	
	PRAGMA EXCEPTION_INIT(
		invalid_component_index
		,-20006
	);
	


	----------------------------------------
	-- Subprograms
	----------------------------------------

	--
	-- Functions
	--
	-- Includes legacy helper functions, for context and possible future reuse
	--
	
	FUNCTION decode_loc_method (
		source_value		IN	NUMBER
	)
	RETURN VARCHAR2
	DETERMINISTIC
	;
	
	
	FUNCTION dms_to_dd (
		ordinate		IN	NUMBER
	)
	RETURN NUMBER
	DETERMINISTIC
	;


	FUNCTION get_location_method (
		location_method		IN	VARCHAR2
	)
	RETURN VARCHAR2
	DETERMINISTIC
	;

	
	FUNCTION get_wkid (
		name			IN	VARCHAR2
	)
	RETURN NUMBER
	DETERMINISTIC
	;


	FUNCTION parse_full_app_no (
		full_app_no		IN	VARCHAR2
		,component		IN	NUMBER
	)
	RETURN VARCHAR2
	DETERMINISTIC
	;
	
	
	
	-- Envelope getter functions
	
	FUNCTION get_ordinate_dd_xmin RETURN NUMBER DETERMINISTIC;
	FUNCTION get_ordinate_dd_xmax RETURN NUMBER DETERMINISTIC;
	FUNCTION get_ordinate_dd_ymin RETURN NUMBER DETERMINISTIC;
	FUNCTION get_ordinate_dd_ymax RETURN NUMBER DETERMINISTIC;

	FUNCTION get_ordinate_dms_xmin RETURN NUMBER DETERMINISTIC;
	FUNCTION get_ordinate_dms_xmax RETURN NUMBER DETERMINISTIC;
	FUNCTION get_ordinate_dms_ymin RETURN NUMBER DETERMINISTIC;
	FUNCTION get_ordinate_dms_ymax RETURN NUMBER DETERMINISTIC;

	FUNCTION get_ordinate_utm_xmin RETURN NUMBER DETERMINISTIC;
	FUNCTION get_ordinate_utm_xmax RETURN NUMBER DETERMINISTIC;
	FUNCTION get_ordinate_utm_ymin RETURN NUMBER DETERMINISTIC;
	FUNCTION get_ordinate_utm_ymax RETURN NUMBER DETERMINISTIC;



	--
	-- Procedures
	--

	PROCEDURE refresh_databases_erp_site;
	PROCEDURE refresh_databases_reg_station;
	PROCEDURE refresh_databases_well_inv;
	PROCEDURE refresh_databases_well_permits;

	
END;
/

SHOW ERRORS



--------------------------------------------------------------------------------
-- Create package body
--------------------------------------------------------------------------------

CREATE OR REPLACE PACKAGE BODY gis.gis_refresh
AS

	--------------------
	-- Getter functions for package constants
	--------------------

	FUNCTION get_ordinate_dd_xmin RETURN NUMBER DETERMINISTIC AS BEGIN RETURN gis.gis_refresh.ORDINATE_DD_XMIN; END;
	FUNCTION get_ordinate_dd_xmax RETURN NUMBER DETERMINISTIC AS BEGIN RETURN gis.gis_refresh.ORDINATE_DD_XMAX; END;
	FUNCTION get_ordinate_dd_ymin RETURN NUMBER DETERMINISTIC AS BEGIN RETURN gis.gis_refresh.ORDINATE_DD_YMIN; END;
	FUNCTION get_ordinate_dd_ymax RETURN NUMBER DETERMINISTIC AS BEGIN RETURN gis.gis_refresh.ORDINATE_DD_YMAX; END;

	FUNCTION get_ordinate_dms_xmin RETURN NUMBER DETERMINISTIC AS BEGIN RETURN gis.gis_refresh.ORDINATE_DMS_XMIN; END;
	FUNCTION get_ordinate_dms_xmax RETURN NUMBER DETERMINISTIC AS BEGIN RETURN gis.gis_refresh.ORDINATE_DMS_XMAX; END;
	FUNCTION get_ordinate_dms_ymin RETURN NUMBER DETERMINISTIC AS BEGIN RETURN gis.gis_refresh.ORDINATE_DMS_YMIN; END;
	FUNCTION get_ordinate_dms_ymax RETURN NUMBER DETERMINISTIC AS BEGIN RETURN gis.gis_refresh.ORDINATE_DMS_YMAX; END;

	FUNCTION get_ordinate_utm_xmin RETURN NUMBER DETERMINISTIC AS BEGIN RETURN gis.gis_refresh.ORDINATE_UTM_XMIN; END;
	FUNCTION get_ordinate_utm_xmax RETURN NUMBER DETERMINISTIC AS BEGIN RETURN gis.gis_refresh.ORDINATE_UTM_XMAX; END;
	FUNCTION get_ordinate_utm_ymin RETURN NUMBER DETERMINISTIC AS BEGIN RETURN gis.gis_refresh.ORDINATE_UTM_YMIN; END;
	FUNCTION get_ordinate_utm_ymax RETURN NUMBER DETERMINISTIC AS BEGIN RETURN gis.gis_refresh.ORDINATE_UTM_YMAX; END;



	--------------------
	-- Normal subprograms
	--------------------

	FUNCTION decode_loc_method (
		source_value		IN	NUMBER
	)
	RETURN VARCHAR2
	DETERMINISTIC
	--------------------------------------------------------------------------------
	-- Purpose:
	--	Convert numeric code for coordinate collection method to friendly text
	--	value
	--
	-- Arguments:
	--	source_value
	--		Integer identifying coordinate collection method. See function
	--		body for source value > return value mapping.
	--
	-- Returns:
	--	VARCHAR2
	--		Text description for corresponding numeric input value. See
	--		function body for source value > return value mapping.
	--
	-- Environment:
	--	Oracle 11.2.0.4.0
	--
	-- Notes:
	--	This function returns NULL when receiving an unexpected input value.
	--
	-- History:
	--	20150219 MCM Created
	--	20151015 MCM Updated output names (NWFWMDDI-26)
	--	20170530 MCM Add input value 8 (NWFWMDDI-51)
	--
	-- To do:
	--	none
	--
	-- Copyright 2003-2019. Mannion Geosystems, LLC. http://www.manniongeo.com
	--------------------------------------------------------------------------------
	AS
	
		friendly_value			VARCHAR2(30);
		
	BEGIN

		SELECT
			DECODE(
				source_value
				,0	,'Other'	-- Originally 'Unknown'
				,1	,'GIS'
				,2	,'GPS'
				,3	,'GPS'		-- Originally 'Survey'
				,4	,'Other'	-- Originally 'Topo Map'
				,5	,'Other'	-- Originally 'Driller'
				,6	,'Other'	-- Originally 'STR Centroid'
				,7	,'Other'	-- Originally 'Google Maps'
				,8	,'GIS'		-- Originally 'Geocode-Exact'
				,NULL
			)
		INTO
			friendly_value
		FROM
			dual
		;
		
		
		
		RETURN friendly_value;
		
		
	END decode_loc_method;



	FUNCTION dms_to_dd (
		ordinate		IN	NUMBER
	)
	RETURN NUMBER
	DETERMINISTIC
	--------------------------------------------------------------------------------
	-- Purpose:
	--	Convert number with encoded degrees/minutes/seconds (DMS) values to
	--	decimal degrees
	--
	-- Arguments:
	--	ordinate
	--		Longitude or latitude ordinate in the form
	--
	--			[dd]dmmss[.s]
	--
	--		where:
	--
	--			[dd]d
	--				Degrees, specified using one, two, or three
	--				digits
	--
	--			mm
	--				Minutes, specified using two digits
	--
	--			ss[.s]
	--				Seconds, specified using two whole digits, and
	--				optionally one or more decimal digits
	--
	-- Returns:
	--	NUMBER
	--		Ordinate in decimal degrees
	--
	-- Environment:
	--	Oracle 11.2.0.4.0
	--
	-- Notes:
	--	This same function can be used to convert longitude or latitude values.
	--	As protection against errant values, the function will raise an
	--	exception for values outside the range of -200 to 200 degrees
	--	(i.e. 'ordinate' parameter values outside the range of
	--	-2000000 to 2000000).
	--
	-- History:
	--	20140919 MCM Created
	--
	-- To do:
	--	none
	--
	-- Copyright 2003-2019. Mannion Geosystems, LLC. http://www.manniongeo.com
	--------------------------------------------------------------------------------
	AS

		seconds				NUMBER(38,6);
		minutes				NUMBER(38);
		degrees				NUMBER(38);

		
	BEGIN

		--
		-- Check if ordinate is out of reasonable range
		--
		
		IF
			ordinate > 2000000
			OR ordinate < -2000000
		THEN
		
			RAISE_APPLICATION_ERROR(
				-20000
				,'DMS ordinate value outside expected range (-2000000 to 2000000)'
			);
			
		END IF;
		
		

		--
		-- Extract degrees, minutes, and seconds components
		-- from input value
		--
		
		
		-- Right-most two whole digits, plus decimal digits
		
		seconds := MOD(
			ordinate
			,100
		);
		
		
		-- Third and fourth right-most whole digits
		
		minutes := MOD(
			TRUNC(
				ordinate
				,-2
			)
			,10000
		) / 100
		;
		
		
		-- Fifth and above right-most whole digits
		
		degrees := MOD(
			TRUNC(
				ordinate
				,-4
			)
			,10000000
		) / 10000
		;
		
		
		--
		-- Return decimal degrees
		--
		
		-- DBMS_OUTPUT.PUT_LINE('Degrees: ' || degrees); -- DEBUG
		-- DBMS_OUTPUT.PUT_LINE('Minutes: ' || minutes); -- DEBUG
		-- DBMS_OUTPUT.PUT_LINE('Seconds: ' || seconds); -- DEBUG

		RETURN degrees + (minutes / 60) + (seconds / 3600);
		
	END dms_to_dd;

	
	
	FUNCTION get_location_method (
		location_method			IN	VARCHAR2
	)
	RETURN VARCHAR2
	DETERMINISTIC
	--------------------------------------------------------------------------------
	-- Purpose:
	--	Return simplified location method for NWFWMD users from detailed
	--	location method stored in NWPROD
	--
	-- Arguments:
	--	location_method
	--		Raw location method description stored in NWPROD, as reported by
	--		INGRES.SJR_ABBR_DEF_ET.TP_DSC
	--
	-- Returns:
	--	VARCHAR2
	--		Simplified location method description
	--
	-- Environment:
	--	Oracle 11.2.0.4.0
	--
	-- Notes:
	--	With respect to a station's location description, NWFWMD end users are
	--	primarily interested in whether the location was capture by GPS, or
	--	by some other method (e.g. map, survey). The details of which type
	--	of GPS or non-GPS method are not relevant in this context, so this
	--	function returns a simplified representation of the detailed values
	--	stored in the NWPROD database.
	--
	-- History:
	--	20140919 MCM Created
	--	20170530 MCM Return NULL instead of raising exception on unknown input
	--	               (NWFWMDDI-52)
	--	20190830 MCM Changed output value for DIGITIZE (NWFWMDDI-89)
	--
	-- To do:
	--	none
	--
	-- Copyright 2003-2019. Mannion Geosystems, LLC. http://www.manniongeo.com
	--------------------------------------------------------------------------------
	AS
	
		simplified_method		VARCHAR2(16);
		
	BEGIN
	
		simplified_method := CASE UPPER(location_method)
			WHEN 'GPS1'		THEN 'GPS'
			WHEN 'GPS2'		THEN 'GPS'
			WHEN 'GPS3'		THEN 'GPS'
			WHEN 'GPS3S'		THEN 'GPS'
			WHEN 'GPS4'		THEN 'GPS'
			WHEN 'CONTROL SURVEY'	THEN 'Other'
			WHEN 'DIGITIZE'		THEN 'Digitize'
			WHEN 'MAP'		THEN 'Other'
			WHEN 'OTHER/UNKNOWN'	THEN 'Other'
			WHEN 'RESOURCE SURVEY'	THEN 'Other'
			ELSE NULL
		END;
		

		
		RETURN simplified_method;
		

	END get_location_method;



	FUNCTION get_wkid (
		name				IN	VARCHAR2
	)
	RETURN NUMBER
	DETERMINISTIC
	--------------------------------------------------------------------------------
	-- Purpose:
	--	Return numeric well-known ID (WKID) for named spatial reference
	--	component
	--
	-- Arguments:
	--	name
	--		Name of geographic coordinate system, projected coordinate
	--		system, or datum transformation method
	--
	-- Returns:
	--	NUMBER
	--		WKID of spatial reference component
	--
	-- Environment:
	--	Oracle 11.2.0.4.0
	--	ArcGIS 10.6.1
	--
	-- Notes:
	--	This function returns the WKID of spatial reference components used
	--	by this package. The goal is to improve readability by allowing the
	--	use of component names within SQL statements where ST_GEOMETRY
	--	related functions and operators otherwise require the numeric WKID.
	--
	--	These keyword/value pairs were originally implemented as package
	--	variables, but needed to be moved to a function when refactoring to
	--	use EXECUTE IMMEDIATE. While package variables are generally
	--	accessible within the package body and other PL/SQL blocks, they are
	--	not visible within dynamic SQL executed by EXECUTE IMMEDIATE.
	--
	-- History:
	--	20140919 MCM Created
	--	20150911 MCM Added UTM 16N for NAD27 / WGS84
	--
	-- To do:
	--	none
	--
	-- Copyright 2003-2019. Mannion Geosystems, LLC. http://www.manniongeo.com
	--------------------------------------------------------------------------------
	AS
	
		wkid				NUMBER;
		
	BEGIN
	
		wkid := CASE LOWER(name)
			-- Geographic coordinate systems
			WHEN 'gcs_north_american_1927'		THEN 4267
			WHEN 'gcs_north_american_1983'		THEN 4269
			WHEN 'gcs_wgs_1984'			THEN 4326
			-- Projected coordinate systems
			WHEN 'nad_1927_utm_zone_16n'		THEN 26716
			WHEN 'nad_1983_utm_zone_16n'		THEN 26916
			WHEN 'wgs_1984_utm_zone_16n'		THEN 32616
			-- Datum transformations
			WHEN 'nad_1927_to_nad_1983_nadcon'	THEN 1241
			WHEN 'wgs_1984_(itrf00)_to_nad_1983'	THEN 108190
			ELSE NULL
		END;
		
		
		IF wkid IS NULL THEN
		
			RAISE_APPLICATION_ERROR(
				-20001
				,'Unknown spatial reference or datum transformation name (' || name || ')'
			);

		END IF;
		
		
		RETURN wkid;
		

	END get_wkid;



	FUNCTION parse_full_app_no (
		full_app_no		IN	VARCHAR2
		,component		IN	NUMBER
	)
	RETURN VARCHAR2
	DETERMINISTIC
	--------------------------------------------------------------------------------
	-- Purpose:
	--	Parse composite FULL_APP_NO value and return one of its four components
	--
	-- Arguments:
	--	full_app_no
	--		Composite FULL_APP_NO value
	--
	--	component
	--		Index number of component to return:
	--			1	Permit type
	--			2	County FIPS
	--			3	Official permit number
	--			4	Sequence number
	--
	-- Returns:
	--	VARCHAR2
	--		Requested FULL_APP_NO component, as text
	--
	-- Environment:
	--	Oracle 11.2.0.4.0
	--	ArcGIS 10.6.1
	--
	-- Notes:
	--	This function returns one of the four components of the composite
	--	FULL_APP_NO value. The GIS.DATABASES_ERP_SITE and GIS.DATABASES_STATION
	--	feature classes provided users both the composite value, and each
	--	component individually, to facilitate filtering and sorting.
	--
	--	In their original implementation, these feature classes fetched the
	--	the values for components 2-4 directly from the source columns use to
	--	create the composite value. Component 1 (permit type), however, is
	--	manifested by a mapping that exists solely within the function that
	--	generates the composite FULL_APP_NO values. This package included
	--	a function, GET_PERMIT_TYPE, that used the same mapping to convert
	--	raw FAC_RULE_ID values into the desired FULL_APP_NO component.
	--
	--	Given that GET_PERMIT_TYPE was decoupled from the authoritative
	--	function in NWPROD (or eReg?), the potential existed for GET_PERMIT_TYPE
	--	to become stale over time and, in turn, to return incorrect values as
	--	NWPROD evolves. Of lesser concern, but still theoretically possible,
	--	was the potential for one of the authoritative sources of components
	--	2-4 to change value after a FULL_APP_NO was generated from it. In
	--	such a case, fetching from the source would yield a different
	--	component value than was included in FULL_APP_NO, itself.
	--
	--	Therefore, to foster stability, PARSE_FULL_APP_NO replaces both the
	--	earlier GET_PERMIT_TYPE function, as well as the direct fetches from
	--	the individual components' authoritative source columns.
	--
	-- History:
	--	20140927 MCM Created
	--
	-- To do:
	--	none
	--
	-- Copyright 2003-2019. Mannion Geosystems, LLC. http://www.manniongeo.com
	--------------------------------------------------------------------------------
	AS
	
		delimiter		CONSTANT	CHAR(1) := '-';
		
		start_position				NUMBER;
		string_length				NUMBER;
		
		component_value				VARCHAR2(8);
		
	BEGIN
	
		-- Validate arguments
		
		IF
			component < 1
			OR component > 4
		THEN
		
			RAISE_APPLICATION_ERROR(
				-20006
				,'Invalid FULL_APP_NO component number (' || component || ')'
			);
			
		END IF;

	
		
		-- Find component endpoints within string
		
		IF component = 1 THEN
		
			start_position := 1;
			
		ELSE
			
			start_position := INSTR(
				full_app_no
				,delimiter
				,1 -- Beginning of string
				,component - 1 -- Delimiter occurrence at start of this component
			) + 1;
			
		END IF;
		
		
		IF component < 4 THEN
		
			string_length := INSTR(
				full_app_no
				,delimiter
				,1 -- Beginning of string
				,component -- Delimiter occurrence at end of this component
			) - start_position;
			
		ELSE
		
			string_length := LENGTH(full_app_no) + 1 - start_position;
			
		END IF;
			
		
		
		-- Extract component
		
		component_value := SUBSTR(
			full_app_no
			,start_position
			,string_length
		);
		

		
		RETURN component_value;
		

	END parse_full_app_no;



	PROCEDURE refresh_databases_erp_site
	--------------------------------------------------------------------------------
	-- Purpose:
	--	Overwrite contents of GIS.DATABASES_ERP_SITE feature class and related
	--	subset feature classes with current information from system of record
	--
	-- Arguments:
	--	none
	--
	-- Environment:
	--	Oracle 11.2.0.4.0
	--	ArcGIS 10.6.1
	--
	-- Notes:
	--	This procedure requires that the following tables exist, and are
	--	configured to match the structure used in the procedure code below:
	--
	--		GIS.DATABASES_ERP_SITE
	--		GIS.DATABASES_ERP_SITE_40A_4
	--		GIS.DATABASES_ERP_SITE_40A_44
	--		GIS.DATABASES_ERP_SITE_FORESTRY
	--		GIS.DATABASES_ERP_SITE_62_330
	--	
	--	To ensure full compatibility with geodatabase clients, the feature
	--	classes should be created using an ArcGIS application (e.g. arcpy),
	--	rather than directly through SQL.
	--
	--	The GIS.DATABASES_ERP_SITE feature class is the "master" feature class
	--	for this series of related feature classes. GIS.DATABASES_ERP_SITE is
	--	refreshed directly from the NWPROD source database, and includes all
	--	rows used by the various subset feature classes. As a result, for
	--	performance and simplicity, the subset feature classes are refrehsed
	--	from GIS.DATABASES_ERP_SITE, itself, rather than from NWPROD.
	--
	--	This procedure deletes the existing contents of all feature classes
	--	and inserts their new content within a single transaction. The DBA
	--	should ensure that sufficient undo space is available to support
	--	the transaction.
	--
	--	To improve performance, rows fetched from the NWPROD source database are
	--	processed in batch based on their spatial reference. Calling
	--	ST_TRANSFORM uniformly for one SELECT statement yields an order-of-
	--	magnitude performance improvement compared with calling the appropriate
	--	ST_TRANSFORM operator on a row-by-row basis (using CASE).
	--
	-- History:
	--	20150911 MCM Created
	--	20150916 MCM Removed all datum-related code, per NWFWMDDI-27
	--	20151028 MCM Assume DMS for input data with NULL CRDNT_CD values (NWFWMDDI-37)
	--	             For DATABASES_ERP_SITE (per NWFWMDDI-38):
	--	               Removed party role filter for 'Applicant'
	--	               Added PARTY_ROLE column
	--	               Renamed 'APPLICANT_%' columns to 'PARTY_%'
	--	20151115 MCM Added subset feature classes (NWFWMDDI-40):
	--	               DATABASES_ERP_SITE_40A_4
	--	               DATABASES_ERP_SITE_40A_44
	--	               DATABASES_ERP_SITE_62_330
	--	               DATABASES_ERP_SITE_FORESTRY
	--	20160630 MCM Added ITEM_TYPE / ITEM_STAGE columns (NWFWMDDI-43)
	--	20161016 MCM Added ITEM_NUMBER columns (NWFWMDDI-46)
	--	20170105 MCM Added REVIEW_DATE columns (NWFWMDDI-48)
	--	20180227 MCM Set dates < year 100 to NULL (NWFWMDDI-74)
	--
	-- To do:
	--	none
	--
	-- Copyright 2003-2019. Mannion Geosystems, LLC. http://www.manniongeo.com
	--------------------------------------------------------------------------------
	AS
	
		--
		-- Variables
		--
	
		sql_current			CLOB;
		


		--
		-- Templates
		--
		
		
		-- Spatial reference filters
		
		sql_sr_dd			CLOB := '
			(
				d1.tp_dsc = ''DD''
				AND main.longitude IS NOT NULL
				AND main.longitude > ' || gis.gis_refresh.ORDINATE_DD_XMIN || '
				AND main.longitude < ' || gis.gis_refresh.ORDINATE_DD_XMAX || '
				AND main.latitude IS NOT NULL
				AND main.latitude > ' || gis.gis_refresh.ORDINATE_DD_YMIN || '
				AND main.latitude < ' || gis.gis_refresh.ORDINATE_DD_YMAX || '
			)
		';
		
		sql_sr_dms			CLOB := '
			(
				(
					d1.tp_dsc = ''DMS''
					OR d1.tp_dsc IS NULL
				)
				AND main.longitude IS NOT NULL
				AND (main.longitude * -1) > ' || gis.gis_refresh.ORDINATE_DMS_XMIN || '
				AND (main.longitude * -1) < ' || gis.gis_refresh.ORDINATE_DMS_XMAX || '
				AND main.latitude IS NOT NULL
				AND main.latitude > ' || gis.gis_refresh.ORDINATE_DMS_YMIN || '
				AND main.latitude < ' || gis.gis_refresh.ORDINATE_DMS_YMAX || '
			)
		';
		
		sql_sr_utm			CLOB := '
			(
				d1.tp_dsc = ''UTM''
				AND main.longitude IS NOT NULL
				AND main.longitude > ' || gis.gis_refresh.ORDINATE_UTM_XMIN || '
				AND main.longitude < ' || gis.gis_refresh.ORDINATE_UTM_XMAX || '
				AND main.latitude IS NOT NULL
				AND main.latitude > ' || gis.gis_refresh.ORDINATE_UTM_YMIN || '
				AND main.latitude < ' || gis.gis_refresh.ORDINATE_UTM_XMAX || '
			)
		';
		
		sql_sr_invalid			CLOB := '
			(
				main.longitude IS NULL
				OR main.latitude IS NULL
				OR d1.tp_dsc NOT IN (
					''DD''
					,''DMS''
					,''UTM''
				)
				OR (
					d1.tp_dsc = ''DD''
					AND (
						main.longitude <= ' || gis.gis_refresh.ORDINATE_DD_XMIN || '
						OR main.longitude >= ' || gis.gis_refresh.ORDINATE_DD_XMAX || '
						OR main.latitude <= ' || gis.gis_refresh.ORDINATE_DD_YMIN || '
						OR main.latitude >= ' || gis.gis_refresh.ORDINATE_DD_YMAX || '
					)
				)
				OR (
					d1.tp_dsc = ''DMS''
					AND (
						(main.longitude * -1) <= ' || gis.gis_refresh.ORDINATE_DMS_XMIN || '
						OR (main.longitude * -1) >= ' || gis.gis_refresh.ORDINATE_DMS_XMAX || '
						OR main.latitude <= ' || gis.gis_refresh.ORDINATE_DMS_YMIN || '
						OR main.latitude >= ' || gis.gis_refresh.ORDINATE_DMS_YMAX || '
					)
				)
				OR (
					d1.tp_dsc = ''UTM''
					AND (
						main.longitude <= ' || gis.gis_refresh.ORDINATE_UTM_XMIN || '
						OR main.longitude >= ' || gis.gis_refresh.ORDINATE_UTM_XMAX || '
						OR main.latitude <= ' || gis.gis_refresh.ORDINATE_UTM_YMIN || '
						OR main.latitude >= ' || gis.gis_refresh.ORDINATE_UTM_YMAX || '
					)
				)		
			)
		';

		

		-- Shape generation
		
		sql_shape_dd			CLOB := '
			sde.st_transform(
				sde.st_point(
					pt_x => remote.longitude
					,pt_y => remote.latitude
					,srid => gis.gis_refresh.get_wkid(name => ''GCS_North_American_1983'')
				)
				,gis.gis_refresh.get_wkid(name => ''NAD_1983_UTM_Zone_16N'')
			) shape
		';

		sql_shape_dms			CLOB := '
			sde.st_transform(
				sde.st_point(
					pt_x => (gis.gis_refresh.dms_to_dd(ordinate => remote.longitude)) * -1
					,pt_y => gis.gis_refresh.dms_to_dd(ordinate => remote.latitude)
					,srid => gis.gis_refresh.get_wkid(name => ''GCS_North_American_1983'')
				)
				,gis.gis_refresh.get_wkid(name => ''NAD_1983_UTM_Zone_16N'')
			) shape
		';

		sql_shape_utm			CLOB := '
			sde.st_point(
				pt_x => remote.longitude
				,pt_y => remote.latitude
				,srid => gis.gis_refresh.get_wkid(name => ''NAD_1983_UTM_Zone_16N'')
			) shape
		';
		
		sql_shape_invalid		CLOB := 'NULL';
		
		
		
		-- Subset table names
		
		sql_subset_table_name_40a_4	CLOB := 'DATABASES_ERP_SITE_40A_4';
		sql_subset_table_name_40a_44	CLOB := 'DATABASES_ERP_SITE_40A_44';
		sql_subset_table_name_62_330	CLOB := 'DATABASES_ERP_SITE_62_330';
		sql_subset_table_name_forestry	CLOB := 'DATABASES_ERP_SITE_FORESTRY';



		-- Subset filters
		
		sql_subset_filter_40a_4		CLOB := 'des.rule_code = ''40A-4''';
		
		sql_subset_filter_40a_44	CLOB := '
			des.rule_description IN (
				''44 ERP General''
				,''44 ERP Individual''
		)';
		
		sql_subset_filter_62_330	CLOB := 'des.rule_code = ''62-330''';
		
		sql_subset_filter_forestry	CLOB := 'des.rule_description = ''Forestry Authorization''';



		-- INSERT statement: Master
		
		sql_insert_master		CLOB := '
			INSERT INTO gis.databases_erp_site (
				objectid
				,shape
				,site_id
				,permit_number
				,project_number
				,permit_type
				,county_fips
				,official_permit_number
				,sequence_number
				,application_status
				,rule_code
				,rule_description
				,project_name
				,project_county
				,site_location
				,party_role
				,party_company_name
				,party_first_name
				,party_last_name
				,expiration_date
				,issue_date
				,review_date
				,legacy_permit_number
				,item_number
				,item_type
				,item_stage
			)
			WITH remote AS (
				SELECT
					DISTINCT
					main.longitude
					,main.latitude
					,main.site_id
					,main.permit_number
					,main.project_number
					,d5.alias_tp_dsc application_status
					,d2.tp_dsc rule_code
					,d3.alias_tp_dsc rule_description
					,main.project_name
					,main.project_county
					,main.site_location
					,d4.tp_dsc party_role
					,main.party_company_name
					,main.party_first_name
					,main.party_last_name
					,main.expiration_date
					,main.issue_date
					,main.review_date
					,main.legacy_permit_number
					,main.item_number
					,d6.tp_dsc item_type
					,d7.tp_dsc item_stage
				FROM (
					SELECT
						ps.long_no longitude
						,ps.lat_no latitude
						,ps.site_id
						,rpe.cur_id permit_number
						,rpe.full_app_no project_number -- Also parsed to permit_type, county_fips, official_permit_number, and sequence_number
						,rpe.proj_stg_cd -- application_status
						,rpe.fac_rule_id -- rule_code, rule_description
						,rpe.proj_nm project_name
						,ce.cnty_nm project_county
						,ps.loc_dsc site_location
						,pr.prty_role_tp_cd -- party_role
						,pae.bsns_nm party_company_name
						,pae.frst_nm party_first_name
						,pae.last_nm party_last_name
						,CASE
							WHEN pt.expir_dt < TO_DATE(''0100-01-01'', ''YYYY-MM-DD'') THEN
								NULL
							ELSE
								pt.expir_dt
						END expiration_date
						,CASE
							WHEN pt.dcsn_dt < TO_DATE(''0100-01-01'', ''YYYY-MM-DD'') THEN
								NULL
							ELSE
								pt.dcsn_dt
						END issue_date
						,CASE
							WHEN cie.revw_due_dt < TO_DATE(''0100-01-01'', ''YYYY-MM-DD'') THEN
								NULL
							ELSE
								TRUNC(
									cie.revw_due_dt
									,''DD''
								)
						END review_date
						,rpe.lgcy_app_no legacy_permit_number
						,cie.cmplnc_item_id item_number
						,cie.cmplnc_item_tp_cd -- item_type
						,cie.item_stg_cd -- item_stage
						,ps.crdnt_cd -- WHERE predicate
					FROM reguser.proj_site@nwprod.sjrwmd.com ps
					INNER JOIN reguser.reg_proj_et@nwprod.sjrwmd.com rpe ON -- Inner join is safe, because PS.CUR_ID is NOT NULL
						ps.cur_id = rpe.cur_id
					LEFT JOIN reguser.prty_role@nwprod.sjrwmd.com pr ON
						rpe.cur_id = pr.cur_id
					LEFT JOIN reguser.prty_addr_et@nwprod.sjrwmd.com pae ON
						pr.prty_addr_id = pae.prty_addr_id
					LEFT JOIN sjr.cnty_et@nwprod.sjrwmd.com ce ON
						rpe.prmry_cnty_id = ce.cnty_id
					LEFT JOIN reguser.proj_timln@nwprod.sjrwmd.com pt ON
						rpe.cur_id = pt.cur_id
					LEFT JOIN reguser.cmplnc_item_et@nwprod.sjrwmd.com cie ON
						rpe.cur_id = cie.cur_id
				) main
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d1 ON -- Coordinate format
					main.crdnt_cd = d1.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d2 ON -- Rule code
					main.fac_rule_id = d2.tp_id
				LEFT JOIN ingres.sjr_abbr_alias@nwprod.sjrwmd.com d3 ON -- Rule description
					main.fac_rule_id = d3.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d4 ON -- Party role
					main.prty_role_tp_cd = d4.tp_id
				LEFT JOIN ingres.sjr_abbr_alias@nwprod.sjrwmd.com d5 ON -- Project stage
					main.proj_stg_cd = d5.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d6 ON -- Item type
					main.cmplnc_item_tp_cd = d6.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d7 ON -- Item stage
					main.item_stg_cd = d7.tp_id
				WHERE
					d2.tp_dsc IN ( -- Rule code
						''40A-4''
						,''40A-44''
						,''62-330''
					)
					AND __PLACEHOLDER__COORDINATES
			)
			SELECT
				/*+
					NO_MERGE(remote)
				*/
				sde.gdb_util.next_rowid(
					''GIS''
					,''DATABASES_ERP_SITE''
				) objectid
				,__PLACEHOLDER__SHAPE
				,remote.site_id
				,remote.permit_number
				,remote.project_number
				,gis.gis_refresh.parse_full_app_no(remote.project_number, 1) permit_type
				,gis.gis_refresh.parse_full_app_no(remote.project_number, 2) county_fips
				,gis.gis_refresh.parse_full_app_no(remote.project_number, 3) official_permit_number
				,gis.gis_refresh.parse_full_app_no(remote.project_number, 4) sequence_number
				,remote.application_status
				,remote.rule_code
				,remote.rule_description
				,remote.project_name
				,remote.project_county
				,remote.site_location
				,remote.party_role
				,remote.party_company_name
				,remote.party_first_name
				,remote.party_last_name
				,remote.expiration_date
				,remote.issue_date
				,remote.review_date
				,remote.legacy_permit_number
				,remote.item_number
				,remote.item_type
				,remote.item_stage
			FROM remote
		';
		
		
		-- INSERT statement: Subset
		
		sql_insert_subset		CLOB := '
			INSERT INTO gis.__PLACEHOLDER__SUBSET_TABLE_NAME (
				objectid
				,shape
				,site_id
				,permit_number
				,project_number
				,permit_type
				,county_fips
				,official_permit_number
				,sequence_number
				,application_status
				,rule_code
				,rule_description
				,project_name
				,project_county
				,site_location
				,expiration_date
				,issue_date
				,review_date
				,legacy_permit_number
				,item_number
				,item_type
				,item_stage
			)
			SELECT
				sde.gdb_util.next_rowid(
					''GIS''
					,''__PLACEHOLDER__SUBSET_TABLE_NAME''
				)
				,master.shape
				,master.site_id
				,master.permit_number
				,master.project_number
				,master.permit_type
				,master.county_fips
				,master.official_permit_number
				,master.sequence_number
				,master.application_status
				,master.rule_code
				,master.rule_description
				,master.project_name
				,master.project_county
				,master.site_location
				,master.expiration_date
				,master.issue_date
				,master.review_date
				,master.legacy_permit_number
				,master.item_number
				,master.item_type
				,master.item_stage
			FROM (
				SELECT
					DISTINCT
					des.shape
					,des.site_id
					,des.permit_number
					,des.project_number
					,des.permit_type
					,des.county_fips
					,des.official_permit_number
					,des.sequence_number
					,des.application_status
					,des.rule_code
					,des.rule_description
					,des.project_name
					,des.project_county
					,des.site_location
					,des.expiration_date
					,des.issue_date
					,des.review_date
					,des.legacy_permit_number
					,des.item_number
					,des.item_type
					,des.item_stage
				FROM
					gis.databases_erp_site des
				WHERE
					__PLACEHOLDER__SUBSET_FILTER
			) master
		';


	BEGIN
	
		--------------------
		-- Refresh master feature class: GIS.DATABASES_ERP_SITE
		--------------------
		
		--
		-- Delete existing rows
		--
		
		DELETE FROM gis.databases_erp_site;
		
		
		
		--
		-- Insert new rows
		--
		
		
		-- DD
		
		sql_current :=
			REPLACE(
				REPLACE(
					sql_insert_master
					,'__PLACEHOLDER__SHAPE'
					,sql_shape_dd
				)
				,'__PLACEHOLDER__COORDINATES'
				,sql_sr_dd
			)
		;
		
		EXECUTE IMMEDIATE sql_current;

		
		-- DMS
		
		sql_current :=
			REPLACE(
				REPLACE(
					sql_insert_master
					,'__PLACEHOLDER__SHAPE'
					,sql_shape_dms
				)
				,'__PLACEHOLDER__COORDINATES'
				,sql_sr_dms
			)
		;
		
		EXECUTE IMMEDIATE sql_current;
		
		
		-- UTM
		
		sql_current :=
			REPLACE(
				REPLACE(
					sql_insert_master
					,'__PLACEHOLDER__SHAPE'
					,sql_shape_utm
				)
				,'__PLACEHOLDER__COORDINATES'
				,sql_sr_utm
			)
		;
		
		EXECUTE IMMEDIATE sql_current;
		
		
		
		-- Attributes only (missing or invalid coordinates)
		
		sql_current :=
			REPLACE(
				REPLACE(
					sql_insert_master
					,'__PLACEHOLDER__SHAPE'
					,sql_shape_invalid
				)
				,'__PLACEHOLDER__COORDINATES'
				,sql_sr_invalid
			)
		;
		
		EXECUTE IMMEDIATE sql_current;



		--------------------
		-- Refresh subset feature class: GIS.DATABASES_ERP_SITE_40A_4
		--------------------
		
		--
		-- Delete existing rows
		--
	
		DELETE FROM gis.databases_erp_site_40a_4;
		
		
		
		--
		-- Insert new rows
		--
		
		sql_current :=
			REPLACE(
				REPLACE(
					sql_insert_subset
					,'__PLACEHOLDER__SUBSET_TABLE_NAME'
					,sql_subset_table_name_40a_4
				)
				,'__PLACEHOLDER__SUBSET_FILTER'
				,sql_subset_filter_40a_4
			)
		;
		
		EXECUTE IMMEDIATE sql_current;



		--------------------
		-- Refresh subset feature class: GIS.DATABASES_ERP_SITE_40A_44
		--------------------
		
		--
		-- Delete existing rows
		--
		
		DELETE FROM gis.databases_erp_site_40a_44;
		
		
		
		--
		-- Insert new rows
		--
		
		sql_current :=
			REPLACE(
				REPLACE(
					sql_insert_subset
					,'__PLACEHOLDER__SUBSET_TABLE_NAME'
					,sql_subset_table_name_40a_44
				)
				,'__PLACEHOLDER__SUBSET_FILTER'
				,sql_subset_filter_40a_44
			)
		;
		
		EXECUTE IMMEDIATE sql_current;



		--------------------
		-- Refresh subset feature class: GIS.DATABASES_ERP_SITE_62_330
		--------------------
	
		--
		-- Delete existing rows
		--
		
		DELETE FROM gis.databases_erp_site_62_330;
		
		
		
		--
		-- Insert new rows
		--
		
		sql_current :=
			REPLACE(
				REPLACE(
					sql_insert_subset
					,'__PLACEHOLDER__SUBSET_TABLE_NAME'
					,sql_subset_table_name_62_330
				)
				,'__PLACEHOLDER__SUBSET_FILTER'
				,sql_subset_filter_62_330
			)
		;
		
		EXECUTE IMMEDIATE sql_current;



		--------------------
		-- Refresh subset feature class: GIS.DATABASES_ERP_SITE_FORESTRY
		--------------------
	
		--
		-- Delete existing rows
		--
		
		DELETE FROM gis.databases_erp_site_forestry;
		
		
		
		--
		-- Insert new rows
		--
		
		sql_current :=
			REPLACE(
				REPLACE(
					sql_insert_subset
					,'__PLACEHOLDER__SUBSET_TABLE_NAME'
					,sql_subset_table_name_forestry
				)
				,'__PLACEHOLDER__SUBSET_FILTER'
				,sql_subset_filter_forestry
			)
		;
		
		EXECUTE IMMEDIATE sql_current;



		----------
		-- Commit changes
		----------
		
		COMMIT;

	
	EXCEPTION
	
		WHEN OTHERS THEN
		
			-- Rollback on any error to restore original rows

			ROLLBACK;
			
			DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
			
			RAISE;
			
	END refresh_databases_erp_site;



	PROCEDURE refresh_databases_reg_station
	--------------------------------------------------------------------------------
	-- Purpose:
	--	Overwrite contents of GIS.DATABASES_REG_STATION table with current
	--	information from system of record
	--
	-- Arguments:
	--	none
	--
	-- Environment:
	--	Oracle 11.2.0.4.0
	--	ArcGIS 10.6.1
	--
	-- Notes:
	--	This procedure requires that the GIS.DATABASES_REG_STATION table exists,
	--	and is configured to match the structure used below. To ensure full
	--	compatibility with geodatabase clients, the feature class should be
	--	created using an ArcGIS application (e.g. arcpy), rather than directly
	--	through SQL.
	--
	--	This procedure deletes the existing contents of the feature class
	--	and inserts the new contents within a single transaction. The DBA
	--	should ensure that sufficient undo space is available to support
	--	the transaction.
	--
	--	To improve performance, source rows are processed in batch based on
	--	their spatial reference. Calling ST_TRANSFORM uniformly for one SELECT
	--	statement yields an order-of-magnitude performance improvement compared
	--	with calling the appropriate ST_TRANSFORM operator on a row-by-row basis
	--	(using CASE).
	--
	-- History:
	--	20150911 MCM Created
	--	20150916 MCM Removed all datum-related code, per NWFWMDDI-27
	--	20151115 MCM Renamed DATABASES_STATION to DATABASES_REG_STATION (NWFWMDDI-39)
	--	20161205 MCM Changed party role filter from 'Land Owner' to 'Applicant'
	--	               (NWFWMDDI-47)
	--
	-- To do:
	--	none
	--
	-- Copyright 2003-2019. Mannion Geosystems, LLC. http://www.manniongeo.com
	--------------------------------------------------------------------------------
	AS

		--
		-- Variables
		--
	
		sql_current			CLOB;
		


		--
		-- Templates
		--
		
		
		-- Spatial reference filters
		
		sql_sr_dd			CLOB := '
			(
				d1.tp_dsc = ''DD''
				AND main.longitude IS NOT NULL
				AND main.longitude > ' || gis.gis_refresh.ORDINATE_DD_XMIN || '
				AND main.longitude < ' || gis.gis_refresh.ORDINATE_DD_XMAX || '
				AND main.latitude IS NOT NULL
				AND main.latitude > ' || gis.gis_refresh.ORDINATE_DD_YMIN || '
				AND main.latitude < ' || gis.gis_refresh.ORDINATE_DD_YMAX || '
			)
		';
		
		sql_sr_dms			CLOB := '
			(
				d1.tp_dsc = ''DMS''
				AND main.longitude IS NOT NULL
				AND (main.longitude * -1) > ' || gis.gis_refresh.ORDINATE_DMS_XMIN || '
				AND (main.longitude * -1) < ' || gis.gis_refresh.ORDINATE_DMS_XMAX || '
				AND main.latitude IS NOT NULL
				AND main.latitude > ' || gis.gis_refresh.ORDINATE_DMS_YMIN || '
				AND main.latitude < ' || gis.gis_refresh.ORDINATE_DMS_YMAX || '
			)
		';
		
		sql_sr_utm			CLOB := '
			(
				d1.tp_dsc = ''UTM''
				AND main.longitude IS NOT NULL
				AND main.longitude > ' || gis.gis_refresh.ORDINATE_UTM_XMIN || '
				AND main.longitude < ' || gis.gis_refresh.ORDINATE_UTM_XMAX || '
				AND main.latitude IS NOT NULL
				AND main.latitude > ' || gis.gis_refresh.ORDINATE_UTM_YMIN || '
				AND main.latitude < ' || gis.gis_refresh.ORDINATE_UTM_XMAX || '
			)
		';
		
		sql_sr_invalid			CLOB := '
			(
				main.longitude IS NULL
				OR main.latitude IS NULL
				OR d1.tp_dsc IS NULL
				OR d1.tp_dsc NOT IN (
					''DD''
					,''DMS''
					,''UTM''
				)
				OR (
					d1.tp_dsc = ''DD''
					AND (
						main.longitude <= ' || gis.gis_refresh.ORDINATE_DD_XMIN || '
						OR main.longitude >= ' || gis.gis_refresh.ORDINATE_DD_XMAX || '
						OR main.latitude <= ' || gis.gis_refresh.ORDINATE_DD_YMIN || '
						OR main.latitude >= ' || gis.gis_refresh.ORDINATE_DD_YMAX || '
					)
				)
				OR (
					d1.tp_dsc = ''DMS''
					AND (
						(main.longitude * -1) <= ' || gis.gis_refresh.ORDINATE_DMS_XMIN || '
						OR (main.longitude * -1) >= ' || gis.gis_refresh.ORDINATE_DMS_XMAX || '
						OR main.latitude <= ' || gis.gis_refresh.ORDINATE_DMS_YMIN || '
						OR main.latitude >= ' || gis.gis_refresh.ORDINATE_DMS_YMAX || '
					)
				)
				OR (
					d1.tp_dsc = ''UTM''
					AND (
						main.longitude <= ' || gis.gis_refresh.ORDINATE_UTM_XMIN || '
						OR main.longitude >= ' || gis.gis_refresh.ORDINATE_UTM_XMAX || '
						OR main.latitude <= ' || gis.gis_refresh.ORDINATE_UTM_YMIN || '
						OR main.latitude >= ' || gis.gis_refresh.ORDINATE_UTM_YMAX || '
					)
				)		
			)
		';
		
		
		
		-- Shape generation
		
		sql_shape_dd			CLOB := '
			sde.st_transform(
				sde.st_point(
					pt_x => remote.longitude
					,pt_y => remote.latitude
					,srid => gis.gis_refresh.get_wkid(name => ''GCS_North_American_1983'')
				)
				,gis.gis_refresh.get_wkid(name => ''NAD_1983_UTM_Zone_16N'')
			) shape
		';

		sql_shape_dms			CLOB := '
			sde.st_transform(
				sde.st_point(
					pt_x => (gis.gis_refresh.dms_to_dd(ordinate => remote.longitude)) * -1
					,pt_y => gis.gis_refresh.dms_to_dd(ordinate => remote.latitude)
					,srid => gis.gis_refresh.get_wkid(name => ''GCS_North_American_1983'')
				)
				,gis.gis_refresh.get_wkid(name => ''NAD_1983_UTM_Zone_16N'')
			) shape
		';

		sql_shape_utm			CLOB := '
			sde.st_point(
				pt_x => remote.longitude
				,pt_y => remote.latitude
				,srid => gis.gis_refresh.get_wkid(name => ''NAD_1983_UTM_Zone_16N'')
			) shape
		';
		
		sql_shape_invalid		CLOB := 'NULL';



		-- INSERT statement
		
		sql_insert			CLOB := '
			INSERT INTO gis.databases_reg_station (
				objectid
				,shape
				,station_id
				,project_number
				,permit_type
				,county_fips
				,official_permit_number
				,sequence_number
				,fluwid
				,station_type
				,monitoring_well_type
				,station_name
				,station_status
				,water_source_type
				,water_source_name
				,meter_type
				,diameter
				,casing_depth
				,well_depth
				,pump_rate
				,pumping_report
				,wq_mi
				,wq_lp
				,wl_gw
				,station_county
				,station_location
				,location_method
				,project_primary_use
				,project_secondary_use
				,water_use_level_1
				,water_use_level_2
				,water_use_level_3
				,water_use_level_4
				,station_allocation_gpd
				,project_allocation_gpd
				,project_allocation_monthly
				,application_status
				,expiration_date
				,owner_company_name
				,owner_first_name
				,owner_last_name
				,legacy_apnum
				,legacy_permit_number
				,nwf_id
				,wps_permit
			)
			WITH remote AS (
				SELECT
					DISTINCT
					main.longitude
					,main.latitude
					,main.station_id
					,main.project_number
					,main.fluwid
					,d4.tp_dsc station_type
					,d10.tp_dsc monitoring_well_type
					,main.station_name
					,d5.tp_dsc station_status
					,DECODE(
						d11.tp_dsc
						,''Unconfined Aquifer'' -- NWFWMDDI-35
						,NULL
						,d11.tp_dsc
					) water_source_type
					,main.water_source_name
					,d7.tp_dsc meter_type
					,CASE d4.tp_dsc
						WHEN ''Pump'' THEN main.pmp_intk_dmtr
						WHEN ''Well'' THEN main.nomnl_csng_dmtr_qty
						ELSE NULL
					END diameter
					,main.casing_depth
					,main.well_depth
					,main.pump_rate
					,main.pumping_report
					,main.wq_mi
					,main.wq_lp
					,main.wl_gw
					,main.station_county
					,main.station_location
					,d6.tp_dsc location_method
					,d8.tp_dsc project_primary_use
					,d9.tp_dsc project_secondary_use
					,d12.tp_dsc water_use_level_1
					,d13.tp_dsc water_use_level_2
					,d14.tp_dsc water_use_level_3
					,d15.tp_dsc water_use_level_4
					,main.station_allocation_gpd
					,main.project_allocation_gpd
					,main.project_allocation_monthly
					,d2.alias_tp_dsc application_status
					,main.expiration_date
					,main.owner_company_name
					,main.owner_first_name
					,main.owner_last_name
					,main.legacy_apnum
					,main.legacy_permit_number
					,main.nwf_id
					,main.wps_permit
				FROM (
					SELECT
						se.org_long_no longitude -- shape
						,se.org_lat_no latitude -- shape
						,se.stn_id station_id
						,rpe.full_app_no project_number -- Also parsed to permit_type, county_fips, official_permit_number, and sequence_number
						,se.fl_unq_well_id fluwid
						,se.stn_tp_cd -- station_type
						,ps.mon_well_tp_cd -- monitoring_well_type
						,se.stn_nm station_name
						,se.stn_stts_cd -- station_status
						,pws.srce_tp_cd -- water_source_type
						,pws.srce_nm water_source_name
						,ps.acct_mthd_tp_cd -- meter_type
						,ps.pmp_intk_dmtr -- diameter
						,we.nomnl_csng_dmtr_qty -- diameter
						,we.totl_well_csng_dpth_qty casing_depth
						,we.cur_well_dpth_qty well_depth
						,ps.pmp_max_cap_qty pump_rate
						,DECODE(
							ps.en50_cd
							,0
							,''No''
							,1
							,''Yes''
							,''Unknown''
						) pumping_report
						,DECODE(
							ps.wtr_qual_mi_cd
							,0
							,''No''
							,1
							,''Yes''
							,''Unknown''
						) wq_mi
						,DECODE(
							ps.wtr_qual_lp_cd
							,0
							,''No''
							,1
							,''Yes''
							,''Unknown''
						) wq_lp
						,DECODE(
							ps.wtr_lvl_gw_cd
							,0
							,''No''
							,1
							,''Yes''
							,''Unknown''
						) wl_gw
						,ce1.cnty_nm station_county
						,se.pnt_loc_dsc station_location
						,se.mthd_dtrmn_cd -- location_method
						,ppc.proj_use_tp_cd -- project_primary_use
						,ppc.proj_use_sub_1_tp_cd -- project_primary_use
						,alloc.water_use_level_1
						,alloc.water_use_level_2
						,alloc.water_use_level_3
						,alloc.water_use_level_4
						,alloc.station_allocation_gpd
						,ppc.prmt_wtr_alloc_qty project_allocation_gpd
						,ppc.new_wtr_alloc_qty project_allocation_monthly
						,rpe.proj_stg_cd -- application_status
						,pt.expir_dt expiration_date
						,pae.bsns_nm owner_company_name
						,pae.frst_nm owner_first_name
						,pae.last_nm owner_last_name
						,CASE -- Limit CUR_IDs to values migrated from legacy system
							WHEN rpe.cur_id <= 7541 THEN rpe.cur_id
							ELSE NULL
						END legacy_apnum
						,rpe.lgcy_app_no legacy_permit_number
						,se.nwf_id nwf_id
						,ps.well_prmt_no wps_permit
						,pr.prty_role_tp_cd -- WHERE predicate
						,se.crdnt_cd -- WHERE predicate
					FROM sjr.stn_et@nwprod.sjrwmd.com se
					INNER JOIN reguser.proj_stn@nwprod.sjrwmd.com ps ON -- Inner join because we only want stations associated with projects
						se.stn_id = ps.stn_id
					INNER JOIN reguser.reg_proj_et@nwprod.sjrwmd.com rpe ON -- Inner join is safe, because PS.CUR_ID is NOT NULL
						ps.cur_id = rpe.cur_id
					LEFT JOIN sjr.well_et@nwprod.sjrwmd.com we ON
						se.stn_id = we.stn_id
					LEFT JOIN reguser.proj_timln@nwprod.sjrwmd.com pt ON
						rpe.cur_id = pt.cur_id
					LEFT JOIN reguser.proj_prpty_cup@nwprod.sjrwmd.com ppc ON
						rpe.cur_id = ppc.cur_id
					LEFT JOIN reguser.prty_role@nwprod.sjrwmd.com pr ON
						rpe.cur_id = pr.cur_id
					LEFT JOIN reguser.prty_addr_et@nwprod.sjrwmd.com pae ON
						pr.prty_addr_id = pae.prty_addr_id
					LEFT JOIN sjr.cnty_et@nwprod.sjrwmd.com ce1 ON
						se.cnty_id = ce1.cnty_id
					LEFT JOIN sjr.cnty_et@nwprod.sjrwmd.com ce2 ON
						rpe.prmry_cnty_id = ce2.cnty_id
					LEFT JOIN reguser.proj_wtr_srce@nwprod.sjrwmd.com pws ON
						ps.proj_wtr_srce_id = pws.proj_wtr_srce_id
					LEFT JOIN (
						SELECT
							passs.site_id
							,passs.proj_wtr_srce_id
							,passs.stn_id
							,pa.use_lvl_1_tp_cd water_use_level_1
							,pa.use_lvl_2_tp_cd water_use_level_2
							,pa.use_lvl_3_tp_cd water_use_level_3
							,pa.use_lvl_4_tp_cd water_use_level_4
							,CAST(AVG(passs.alloc_qty) AS NUMBER(38)) station_allocation_gpd -- Average allocation across all permitted years
						FROM reguser.proj_alloc_site_srce_stn@nwprod.sjrwmd.com passs
						INNER JOIN reguser.proj_alloc@nwprod.sjrwmd.com pa ON
							passs.alloc_id = pa.alloc_id
						GROUP BY
							passs.site_id
							,passs.proj_wtr_srce_id
							,passs.stn_id
							,pa.use_lvl_1_tp_cd
							,pa.use_lvl_2_tp_cd
							,pa.use_lvl_3_tp_cd
							,pa.use_lvl_4_tp_cd
					) alloc ON
						ps.site_id = alloc.site_id
						AND ps.proj_wtr_srce_id = alloc.proj_wtr_srce_id
						AND ps.stn_id = alloc.stn_id
				) main
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d1 ON -- Coordinate format
					main.crdnt_cd = d1.tp_id
				LEFT JOIN ingres.sjr_abbr_alias@nwprod.sjrwmd.com d2 ON -- Project stage
					main.proj_stg_cd = d2.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d3 ON -- Party role
					main.prty_role_tp_cd = d3.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d4 ON -- Station type
					main.stn_tp_cd = d4.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d5 ON -- Station status
					main.stn_stts_cd = d5.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d6 ON -- Location method
					main.mthd_dtrmn_cd = d6.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d7 ON -- Meter type
					main.acct_mthd_tp_cd = d7.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d8 ON -- Project primary use
					main.proj_use_tp_cd = d8.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d9 ON -- Project secondary use
					main.proj_use_sub_1_tp_cd = d9.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d10 ON -- Monitoring well type
					main.mon_well_tp_cd = d10.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d11 ON -- Water source type
					main.srce_tp_cd = d11.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d12 ON -- Water use level 1
					main.water_use_level_1 = d12.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d13 ON -- Water use level 2
					main.water_use_level_2 = d13.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d14 ON -- Water use level 3
					main.water_use_level_3 = d14.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d15 ON -- Water use level 4
					main.water_use_level_4 = d15.tp_id
				WHERE
					d3.tp_dsc = ''Applicant'' -- NWFWMDDI-47
					AND __PLACEHOLDER__COORDINATES
			)
			SELECT
				/*+
					NO_MERGE(remote)
				*/
				sde.gdb_util.next_rowid(
					''GIS''
					,''DATABASES_REG_STATION''
				) objectid
				,__PLACEHOLDER__SHAPE
				,remote.station_id
				,remote.project_number
				,gis.gis_refresh.parse_full_app_no(remote.project_number, 1) permit_type
				,gis.gis_refresh.parse_full_app_no(remote.project_number, 2) county_fips
				,gis.gis_refresh.parse_full_app_no(remote.project_number, 3) official_permit_number
				,gis.gis_refresh.parse_full_app_no(remote.project_number, 4) sequence_number
				,remote.fluwid
				,remote.station_type
				,remote.monitoring_well_type
				,remote.station_name
				,remote.station_status
				,remote.water_source_type
				,remote.water_source_name
				,remote.meter_type
				,remote.diameter
				,remote.casing_depth
				,remote.well_depth
				,remote.pump_rate
				,remote.pumping_report
				,remote.wq_mi
				,remote.wq_lp
				,remote.wl_gw
				,remote.station_county
				,remote.station_location
				,gis.gis_refresh.get_location_method(remote.location_method) location_method
				,remote.project_primary_use
				,remote.project_secondary_use
				,remote.water_use_level_1
				,remote.water_use_level_2
				,remote.water_use_level_3
				,remote.water_use_level_4
				,remote.station_allocation_gpd
				,remote.project_allocation_gpd
				,remote.project_allocation_monthly
				,remote.application_status
				,remote.expiration_date
				,remote.owner_company_name
				,remote.owner_first_name
				,remote.owner_last_name
				,remote.legacy_apnum
				,remote.legacy_permit_number
				,remote.nwf_id
				,remote.wps_permit
			FROM remote
		';

	
	BEGIN
	
		--
		-- Delete existing rows
		--
		
		DELETE FROM gis.databases_reg_station;
		
		
		
		--
		-- Insert new rows
		--
		
		
		-- DD
		
		sql_current :=
			REPLACE(
				REPLACE(
					sql_insert
					,'__PLACEHOLDER__SHAPE'
					,sql_shape_dd
				)
				,'__PLACEHOLDER__COORDINATES'
				,sql_sr_dd
			)
		;
		
		EXECUTE IMMEDIATE sql_current;

		
		-- DMS
		
		sql_current :=
			REPLACE(
				REPLACE(
					sql_insert
					,'__PLACEHOLDER__SHAPE'
					,sql_shape_dms
				)
				,'__PLACEHOLDER__COORDINATES'
				,sql_sr_dms
			)
		;
		
		EXECUTE IMMEDIATE sql_current;
		
		
		-- UTM
		
		sql_current :=
			REPLACE(
				REPLACE(
					sql_insert
					,'__PLACEHOLDER__SHAPE'
					,sql_shape_utm
				)
				,'__PLACEHOLDER__COORDINATES'
				,sql_sr_utm
			)
		;
		
		EXECUTE IMMEDIATE sql_current;
		
		
		
		-- Attributes only (missing or invalid coordinates)
		
		sql_current :=
			REPLACE(
				REPLACE(
					sql_insert
					,'__PLACEHOLDER__SHAPE'
					,sql_shape_invalid
				)
				,'__PLACEHOLDER__COORDINATES'
				,sql_sr_invalid
			)
		;
		
		EXECUTE IMMEDIATE sql_current;

		

		--
		-- Commit changes
		--
		
		COMMIT;

	
	EXCEPTION
	
		WHEN OTHERS THEN
		
			-- Rollback on any error to restore original rows

			ROLLBACK;
			
			DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
			
			RAISE;
			
	END refresh_databases_reg_station;

	
	
	PROCEDURE refresh_databases_well_inv
	--------------------------------------------------------------------------------
	-- Purpose:
	--	Overwrite contents of GIS.DATABASES_WELL_INVENTORY table with current
	--	information from system of record
	--
	-- Arguments:
	--	none
	--
	-- Environment:
	--	Oracle 11.2.0.4.0
	--	ArcGIS 10.6.1
	--
	-- Notes:
	--	This procedure requires that the GIS.DATABASES_WELL_INVENTORY table exists,
	--	and is configured to match the structure used below. To ensure full
	--	compatibility with geodatabase clients, the feature class should be
	--	created using an ArcGIS application (e.g. arcpy), rather than directly
	--	through SQL.
	--
	--	This procedure deletes the existing contents of the feature class
	--	and inserts the new contents within a single transaction. The DBA
	--	should ensure that sufficient undo space is available to support
	--	the transaction.
	--
	-- History:
	--	20140919 MCM Created
	--	20150219 MCM Added LOC_METHOD column
	--	20151013 MCM Removed all datum-related code, per NWFWMDDI-27
	--	             Overhauled SQL to follow newer ERP_SITE / STATION structure
	--	             Added invalid shape filter to capture attribute-only records
	--
	-- To do:
	--	none
	--
	-- Copyright 2003-2019. Mannion Geosystems, LLC. http://www.manniongeo.com
	--------------------------------------------------------------------------------
	AS
	
		--
		-- Variables
		--
	
		sql_current			CLOB;
		


		--
		-- Templates
		--
		
		
		-- Spatial reference filters
		
		sql_sr_dms			CLOB := '
			(
				wwi.longitude IS NOT NULL
				AND (wwi.longitude * -1) > ' || gis.gis_refresh.ORDINATE_DMS_XMIN || '
				AND (wwi.longitude * -1) < ' || gis.gis_refresh.ORDINATE_DMS_XMAX || '
				AND wwi.latitude IS NOT NULL
				AND wwi.latitude > ' || gis.gis_refresh.ORDINATE_DMS_YMIN || '
				AND wwi.latitude < ' || gis.gis_refresh.ORDINATE_DMS_YMAX || '
			)
		';
		
		sql_sr_invalid			CLOB := '
			(
				wwi.longitude IS NULL
				OR wwi.latitude IS NULL
				OR (wwi.longitude * -1) <= ' || gis.gis_refresh.ORDINATE_DMS_XMIN || '
				OR (wwi.longitude * -1) >= ' || gis.gis_refresh.ORDINATE_DMS_XMAX || '
				OR wwi.latitude <= ' || gis.gis_refresh.ORDINATE_DMS_YMIN || '
				OR wwi.latitude >= ' || gis.gis_refresh.ORDINATE_DMS_YMAX || '
			)
		';
		
		
		-- Shape generation
		
		sql_shape_dms			CLOB := '
			sde.st_transform(
					sde.st_point(
						pt_x => (gis.gis_refresh.dms_to_dd(ordinate => wwi.longitude)) * -1
						,pt_y => gis.gis_refresh.dms_to_dd(ordinate => wwi.latitude)
						,srid => gis.gis_refresh.get_wkid(name => ''GCS_North_American_1983'')
					)
					,gis.gis_refresh.get_wkid(name => ''NAD_1983_UTM_Zone_16N'')
				)
		';
		
		sql_shape_invalid		CLOB := 'NULL';
		

		
		-- INSERT statement
		
		sql_insert			CLOB := '
			INSERT INTO gis.databases_well_inventory (
				objectid
				,shape
				,nwf_id
				,site_id
				,site_type
				,well_name
				,first_name
				,last_name
				,well_depth
				,casing_depth
				,use_permit
				,cps_permit
				,state_id
				,spcap
				,calc_trans
				,loc_method
			)
			SELECT
				sde.gdb_util.next_rowid(
					''GIS''
					,''DATABASES_WELL_INVENTORY''
				)
				,__PLACEHOLDER__SHAPE
				,wwi.nwf_id
				,wwi.site_id
				,wwi.site_type
				,wwi.well_name
				,wwi.first_name
				,wwi.last_name
				,wwi.depth_of_well
				,wwi.depth_of_casing
				,wwi.use_permit
				,wwi.construction_permit
				,wwi.state_id
				,wwi.spcap
				,wwi.calc_trans
				,gis.gis_refresh.decode_loc_method(wwi.loc_method)
			FROM well_inv.wi_well_inv wwi
			WHERE
				__PLACEHOLDER__COORDINATES
		';
	
	BEGIN
	
		--
		-- Delete existing rows
		--
		
		DELETE FROM gis.databases_well_inventory;
		
		
		
		--
		-- Insert new rows
		--
		
		
		-- DMS
		
		sql_current :=
			REPLACE(
				REPLACE(
					sql_insert
					,'__PLACEHOLDER__SHAPE'
					,sql_shape_dms
				)
				,'__PLACEHOLDER__COORDINATES'
				,sql_sr_dms
			)
		;
		
		EXECUTE IMMEDIATE sql_current;

		
		-- Attributes only (missing or invalid coordiantes)
		
		sql_current := REPLACE(
			REPLACE(
				sql_insert
				,'__PLACEHOLDER__SHAPE'
				,sql_shape_invalid
			)
			,'__PLACEHOLDER__COORDINATES'
			,sql_sr_invalid
		);
		
		EXECUTE IMMEDIATE sql_current;

		
		
		--
		-- Commit changes
		--
		
		COMMIT;

	
	EXCEPTION
	
		WHEN OTHERS THEN
		
			-- Rollback on any error to restore original rows

			ROLLBACK;
			
			DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
			
			RAISE;
			
	END refresh_databases_well_inv;



	PROCEDURE refresh_databases_well_permits
	--------------------------------------------------------------------------------
	-- Purpose:
	--	Overwrite contents of GIS.DATABASES_WELL_PERMITS table with current
	--	information from system of record
	--
	-- Arguments:
	--	none
	--
	-- Environment:
	--	Oracle 11.2.0.4.0
	--	ArcGIS 10.6.1
	--
	-- Notes:
	--	This procedure requires that the GIS.DATABASES_WELL_PERMITS table exists,
	--	and is configured to match the structure used below. To ensure full
	--	compatibility with geodatabase clients, the feature class should be
	--	created using an ArcGIS application (e.g. arcpy), rather than directly
	--	through SQL.
	--
	--	This procedure deletes the existing contents of the feature class
	--	and inserts the new contents within a single transaction. The DBA
	--	should ensure that sufficient undo space is available to support
	--	the transaction.
	--
	--	PERFORMANCE
	--
	--	To improve performance, rows fetched from the NWPROD source database are
	--	processed in batch based on their spatial reference. Calling
	--	ST_TRANSFORM uniformly for one SELECT statement yields an order-of-
	--	magnitude performance improvement compared with calling the appropriate
	--	ST_TRANSFORM operator on a row-by-row basis (using CASE).
	--
	--	COORDINATES
	--
	--	Note that the workflow below uses two sets of longitude/latitude values.
	--	Firstly, raw values are harvested from the production database at SJRWMD,
	--	erroneous / suspect values filtered out, and the remaining values
	--	standardized to produce ST_GEOMETRY geometries.
	--
	--	These raw coordinate values, however, are not stored directly in the
	--	LONGITUDE and LATITUDE attributes in the business table. Rather, those
	--	attributes are populated by extracting cleansed, numeric coordinates values
	--	from the new geometries. Therefore, the resulting SHAPE and LONGITUDE/
	--	LATITUDE values are semantically equivalent, differing only in their
	--	physical formats (data type and coordinate system). This design is
	--	intentional, per guidance from NWFWMD.
	--
	--	QUERY DESIGN
	--
	--	As of the 2019-08-23 update, this query diverges in structure from
	--	similar queries in this package. Firstly, all remote components are
	--	represented in a single CTE, "remote", rather than the pair of
	--	"main" and "remote" CTEs. This arguably reduces readability, but is
	--	more self-consistent given the inclusion of WHERE predicates that rely
	--	on decoded values from the INGRES tables.
	--
	--	Secondly, removing the "main" CTE requires changing the spatial SQL
	--	templates to reference the actual table containing the source
	--	coordinate data, rather than the generic "main" alias.
	--
	--	Thirdly, the output feature class now contains columns named LATITUDE
	--	and LONGITUDE, which report numeric coordinates derived from each row's
	--	ST_GEOMETRY value. Accordingly, this presents a name conflict with the
	--	standard (within this package) alias for the columns containing the raw
	--	source coordinates. Therefore, we prefix the aliases here with "RAW_",
	--	and update the spatial SQL templates to match, where required.
	--
	--	*** Note *** that there are references to the raw coordinates at two
	--	levels within the query: one inside (__PLACEHOLDER__COORDINATES)
	--	and one outside (__PLACEHOLDER_SHAPE) of the "remote" CTE. The inner
	--	reference uses the actual source column names (i.e. se.lat_no /
	--	se.long_no), and the outer reference uses the aliases (i.e.
	--	remote.raw_latitude / remote.raw_longitude).
	--
	-- History:
	--	20140919 MCM Created
	--	20150127 MCM Updated header comments to clarify handling of <other>
	--	              values
	--	20150219 MCM Added number > text translation for
	--	               GIS.DATABASES_WELL_PERMITS.LOC_METHOD values, per
	--	               data type change for that column
	--	20151013 MCM Removed all datum-related code, per NWFWMDDI-27
	--	             Overhauled SQL to follow newer ERP_SITE / STATION structure
	--	             Added invalid shape filter to capture attribute-only records
	--	20160104 MCM Added attribute columns (NWFWMDDI-41)
	--	20160803 MCM Added WELL_COUNTY column (NWFWMDDI-44)
	--	20160829 MCM Added columns (NWFWMDDI-45)
	--	20180927 MCM Update REFRESH_DATABASES_WELL_PERMITS to use remote database
	--	               with new eReg wells data structures, and miscellaneous
	--	               output schema changes (NWFWMDDI-71)
	--	20190823 MCM Overhauled to use REG_PROJ_ET as primary table, and myriad
	--	               additional changes to adcommodate eReg data model / user
	--	               feedback
	--	20190905 MCM Expanded RELATED_PERMIT to RELATED_PERMIT_1 and
	--	               RELATED_PERMIT_2 (NWFWMDDI-90)
	--
	-- To do:
	--	none
	--
	-- Copyright 2003-2019. Mannion Geosystems, LLC. http://www.manniongeo.com
	--------------------------------------------------------------------------------
	AS
	
		--
		-- Variables
		--
	
		sql_current			CLOB;
		


		--
		-- Templates
		--
		
		
		-- Spatial reference filters

		sql_sr_dd			CLOB := '
			(
				d1.tp_dsc = ''DD''
				AND se.long_no IS NOT NULL
				AND se.long_no > ' || gis.gis_refresh.ORDINATE_DD_XMIN || '
				AND se.long_no < ' || gis.gis_refresh.ORDINATE_DD_XMAX || '
				AND se.lat_no IS NOT NULL
				AND se.lat_no > ' || gis.gis_refresh.ORDINATE_DD_YMIN || '
				AND se.lat_no < ' || gis.gis_refresh.ORDINATE_DD_YMAX || '
			)
		';

		sql_sr_dms			CLOB := '
			(
				d1.tp_dsc = ''DMS''
				AND se.long_no IS NOT NULL
				AND (se.long_no * -1) > ' || gis.gis_refresh.ORDINATE_DMS_XMIN || '
				AND (se.long_no * -1) < ' || gis.gis_refresh.ORDINATE_DMS_XMAX || '
				AND se.lat_no IS NOT NULL
				AND se.lat_no > ' || gis.gis_refresh.ORDINATE_DMS_YMIN || '
				AND se.lat_no < ' || gis.gis_refresh.ORDINATE_DMS_YMAX || '
			)
		';

		sql_sr_utm			CLOB := '
			(
				d1.tp_dsc = ''UTM''
				AND se.long_no IS NOT NULL
				AND se.long_no > ' || gis.gis_refresh.ORDINATE_UTM_XMIN || '
				AND se.long_no < ' || gis.gis_refresh.ORDINATE_UTM_XMAX || '
				AND se.lat_no IS NOT NULL
				AND se.lat_no > ' || gis.gis_refresh.ORDINATE_UTM_YMIN || '
				AND se.lat_no < ' || gis.gis_refresh.ORDINATE_UTM_XMAX || '
			)
		';

		sql_sr_invalid			CLOB := '
			(
				se.long_no IS NULL
				OR se.lat_no IS NULL
				OR d1.tp_dsc IS NULL
				OR d1.tp_dsc NOT IN (
					''DD''
					,''DMS''
					,''UTM''
				)
				OR (
					d1.tp_dsc = ''DD''
					AND (
						se.long_no <= ' || gis.gis_refresh.ORDINATE_DD_XMIN || '
						OR se.long_no >= ' || gis.gis_refresh.ORDINATE_DD_XMAX || '
						OR se.lat_no <= ' || gis.gis_refresh.ORDINATE_DD_YMIN || '
						OR se.lat_no >= ' || gis.gis_refresh.ORDINATE_DD_YMAX || '
					)
				)
				OR (
					d1.tp_dsc = ''DMS''
					AND (
						(se.long_no * -1) <= ' || gis.gis_refresh.ORDINATE_DMS_XMIN || '
						OR (se.long_no * -1) >= ' || gis.gis_refresh.ORDINATE_DMS_XMAX || '
						OR se.lat_no <= ' || gis.gis_refresh.ORDINATE_DMS_YMIN || '
						OR se.lat_no >= ' || gis.gis_refresh.ORDINATE_DMS_YMAX || '
					)
				)
				OR (
					d1.tp_dsc = ''UTM''
					AND (
						se.long_no <= ' || gis.gis_refresh.ORDINATE_UTM_XMIN || '
						OR se.long_no >= ' || gis.gis_refresh.ORDINATE_UTM_XMAX || '
						OR se.lat_no <= ' || gis.gis_refresh.ORDINATE_UTM_YMIN || '
						OR se.lat_no >= ' || gis.gis_refresh.ORDINATE_UTM_YMAX || '
					)
				)		
			)
		';



		-- Shape generation

		sql_shape_dd			CLOB := '
			sde.st_transform(
				sde.st_point(
					pt_x => remote.raw_longitude
					,pt_y => remote.raw_latitude
					,srid => gis.gis_refresh.get_wkid(name => ''GCS_North_American_1983'')
				)
				,gis.gis_refresh.get_wkid(name => ''NAD_1983_UTM_Zone_16N'')
			) shape
		';

		sql_shape_dms			CLOB := '
			sde.st_transform(
				sde.st_point(
					pt_x => (gis.gis_refresh.dms_to_dd(ordinate => remote.raw_longitude)) * -1
					,pt_y => gis.gis_refresh.dms_to_dd(ordinate => remote.raw_latitude)
					,srid => gis.gis_refresh.get_wkid(name => ''GCS_North_American_1983'')
				)
				,gis.gis_refresh.get_wkid(name => ''NAD_1983_UTM_Zone_16N'')
			) shape
		';

		sql_shape_utm			CLOB := '
			sde.st_point(
				pt_x => remote.raw_longitude
				,pt_y => remote.raw_latitude
				,srid => gis.gis_refresh.get_wkid(name => ''NAD_1983_UTM_Zone_16N'')
			) shape
		';

		sql_shape_invalid		CLOB := 'NULL';


		
		-- INSERT statement
		
		sql_insert			CLOB := '
			INSERT INTO gis.databases_well_permits (
				objectid
				,shape
				,permit_number
				,legacy_permit_number
				,related_permit_1
				,related_permit_2
				,job_type
				,status
				,official_id
				,issue_date
				,expiration_date
				,completion_date
				,exemption
				,owner_first
				,owner_last
				,well_use
				,diameter
				,appl_well_depth
				,appl_casing_depth
				,wcr_well_depth
				,wcr_casing_depth
				,open_hole_from
				,open_hole_to
				,screen_from
				,screen_to
				,well_street
				,well_street_2
				,well_city
				,well_county
				,parcel_id
				,latitude
				,longitude
				,township
				,range
				,section
				,cu_permit
				,fluwid
				,location_method
				,contractor_license
				,contractor_name
				,wrca
				,arc
				,grout_line
				,construction_method
				,w62_524
				,stn_id
			)
			WITH ps AS ( -- Return one, arbitrary Station per Project
				SELECT
					ps.cur_id
					,MIN(ps.stn_id) stn_id
				FROM reguser.proj_stn@nwprod.sjrwmd.com ps
				GROUP BY
					ps.cur_id
			)
			,wcr AS ( -- Need INNER here, but LEFT in main query
				SELECT
					cie.cur_id
					,wse.stn_id
					,wse.cmplt_dt completion_date
					,wse.totl_well_dpth_qty wcr_well_depth
					,wse.csd_dpth_qty wcr_casing_depth
				FROM reguser.cmplnc_item_et@nwprod.sjrwmd.com cie
				INNER JOIN reguser.well_sbmttl_et@nwprod.sjrwmd.com wse ON
					cie.cmplnc_item_id = wse.cmplnc_item_id
			)
			,remote AS (
				SELECT
					se.long_no raw_longitude
					,se.lat_no raw_latitude
					,rpe1.full_app_no permit_number
					,rpe1.lgcy_app_no legacy_permit_number
					,rpe2.full_app_no related_permit_1
					,rp.rltd_txt related_permit_2
					,d2.tp_dsc job_type
					,d3.alias_tp_dsc status
					,rpe1.offcl_id official_id
					,pt.dcsn_dt issue_date
					,pt.expir_dt expiration_date
					,wcr.completion_date
					,CAST(
						DECODE(
							wpe.exmpt_cd
							,NULL
							,''No''
							,0
							,''No''
							,1
							,''Yes''
							,''Unknown''
						) AS NVARCHAR2(7)
					) exemption
					,wpe.ownr_frst_nm owner_first
					,wpe.ownr_last_nm owner_last
					,d4.tp_dsc well_use
					,wpe.prmry_csng_dmtr_qty diameter
					,wpe.est_well_dpth_qty appl_well_depth
					,wpe.est_csng_dpth_qty appl_casing_depth
					,wcr.wcr_well_depth
					,wcr.wcr_casing_depth
					,wpe.top_opn_intrvl_dpth_val open_hole_from
					,wpe.btm_opn_intrvl_dpth_val open_hole_to
					,wpe.top_scrn_intrvl_dpth_val screen_from
					,wpe.btm_scrn_intrvl_dpth_val screen_to
					,wpe.loc_frst_addr_txt well_street
					,wpe.loc_scnd_addr_txt well_street_2
					,wpe.loc_city_nm well_city
					,ce.cnty_nm well_county
					,wpe.prcl_id parcel_id
					,NULL latitude -- Derive from new, clean geometries using UPDATE
					,NULL longitude -- Derive from new, clean geometries using UPDATE
					,se.twnshp_id township
					,se.rng_id range
					,se.sect_id section
					,rpe3.full_app_no cu_permit
					,se.fl_unq_well_id fluwid
					,d5.tp_dsc location_method
					,wpe.dep_lic_no contractor_license
					,cle.cntrctr_nm contractor_name
					,CAST(
						DECODE(
							wpe.wrca_cd
							,0
							,''No''
							,1
							,''Yes''
							,''Unknown''
						) AS NVARCHAR2(7)
					) wrca
					,CAST(
						DECODE(
							wpe.arc_cd
							,NULL
							,''No''
							,0
							,''No''
							,1
							,''Yes''
							,''Unknown''
						) AS NVARCHAR2(7)
					) arc
					,d6.tp_dsc grout_line
					,d7.tp_dsc construction_method
					,CAST(
						DECODE(
							wpe.delin_cd
							,0
							,''No''
							,1
							,''Yes''
							,''Unknown''
						) AS NVARCHAR2(7)
					) w62_524
					,ps.stn_id
					,se.crdnt_cd -- Spatial reference filter predicate
				FROM reguser.reg_proj_et@nwprod.sjrwmd.com rpe1
				INNER JOIN ps ON
					rpe1.cur_id = ps.cur_id
				INNER JOIN sjr.stn_et@nwprod.sjrwmd.com se ON
					ps.stn_id = se.stn_id
				LEFT JOIN reguser.rltd_proj@nwprod.sjrwmd.com rp ON
					rpe1.cur_id = rp.cur_id
				LEFT JOIN reguser.reg_proj_et@nwprod.sjrwmd.com rpe2 ON
					rp.rltd_cur_id = rpe2.cur_id
				LEFT JOIN reguser.well_proj_et@nwprod.sjrwmd.com wpe ON
					rpe1.cur_id = wpe.cur_id
				INNER JOIN reguser.proj_timln@nwprod.sjrwmd.com pt ON
					rpe1.cur_id = pt.cur_id
				LEFT JOIN wcr ON
					rpe1.cur_id = wcr.cur_id
					AND ps.stn_id = wcr.stn_id
				LEFT JOIN sjr.cnty_et@nwprod.sjrwmd.com ce ON
					se.cnty_id = ce.cnty_id
				LEFT JOIN reguser.reg_proj_et@nwprod.sjrwmd.com rpe3 ON
					wpe.cup_cur_id = rpe3.cur_id
				LEFT JOIN reguser.cntrctr_lic_et@nwprod.sjrwmd.com cle ON
					wpe.dep_lic_no = cle.dep_lic_no
				-- Decode coded attributes
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d1 ON -- Coordinate format
					se.crdnt_cd = d1.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d2 ON -- job_type
					wpe.app_tp_cd = d2.tp_id
				LEFT JOIN ingres.sjr_abbr_alias@nwprod.sjrwmd.com d3 ON -- status
					rpe1.proj_stg_cd = d3.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d4 ON -- well_use
					wpe.well_use_cd = d4.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d5 ON -- location_method
					se.mthd_dtrmn_cd = d5.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d6 ON -- grout_line
					wpe.grout_ln_tp_cd = d6.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d7 ON -- construction_method
					wpe.well_constr_mthd_cd = d7.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d8 ON -- Project stage
					rpe1.proj_stg_cd = d8.tp_id
				LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d9 ON -- Project recommendation
					rpe1.proj_rcmmd_cd = d9.tp_id
				WHERE
					__PLACEHOLDER__COORDINATES
					AND rpe1.fac_rule_id = 498
					AND d8.tp_dsc != ''RESC'' -- Rescinded
					AND d9.tp_dsc NOT IN (
						''Administrative Denial''
						,''Substantive Denial''
						,''Withdrawn''
					)
			)
			SELECT
				/*+
					NO_MERGE(remote)
				*/
				sde.gdb_util.next_rowid(
					''GIS''
					,''DATABASES_WELL_PERMITS''
				) objectid
				,__PLACEHOLDER__SHAPE
				,remote.permit_number
				,remote.legacy_permit_number
				,remote.related_permit_1
				,remote.related_permit_2
				,remote.job_type
				,remote.status
				,remote.official_id
				,remote.issue_date
				,remote.expiration_date
				,remote.completion_date
				,remote.exemption
				,remote.owner_first
				,remote.owner_last
				,remote.well_use
				,remote.diameter
				,remote.appl_well_depth
				,remote.appl_casing_depth
				,remote.wcr_well_depth
				,remote.wcr_casing_depth
				,remote.open_hole_from
				,remote.open_hole_to
				,remote.screen_from
				,remote.screen_to
				,remote.well_street
				,remote.well_street_2
				,remote.well_city
				,remote.well_county
				,remote.parcel_id
				,remote.latitude
				,remote.longitude
				,remote.township
				,remote.range
				,remote.section
				,remote.cu_permit
				,remote.fluwid
				,gis.gis_refresh.get_location_method(remote.location_method) location_method
				,remote.contractor_license
				,remote.contractor_name
				,remote.wrca
				,remote.arc
				,remote.grout_line
				,remote.construction_method
				,remote.w62_524
				,remote.stn_id
			FROM remote
		';

		
	BEGIN
	
		--
		-- Delete existing rows
		--
		
		DELETE FROM gis.databases_well_permits;
		
		
		
		--
		-- Insert new rows
		--
		
		
		-- DD
		
		sql_current :=
			REPLACE(
				REPLACE(
					sql_insert
					,'__PLACEHOLDER__SHAPE'
					,sql_shape_dd
				)
				,'__PLACEHOLDER__COORDINATES'
				,sql_sr_dd
			)
		;
		
		EXECUTE IMMEDIATE sql_current;

		
		-- DMS
		
		sql_current :=
			REPLACE(
				REPLACE(
					sql_insert
					,'__PLACEHOLDER__SHAPE'
					,sql_shape_dms
				)
				,'__PLACEHOLDER__COORDINATES'
				,sql_sr_dms
			)
		;
		
		EXECUTE IMMEDIATE sql_current;
		
		
		-- UTM
		
		sql_current :=
			REPLACE(
				REPLACE(
					sql_insert
					,'__PLACEHOLDER__SHAPE'
					,sql_shape_utm
				)
				,'__PLACEHOLDER__COORDINATES'
				,sql_sr_utm
			)
		;
		
		EXECUTE IMMEDIATE sql_current;
		
		
		
		-- Attributes only (missing or invalid coordinates)
		
		sql_current :=
			REPLACE(
				REPLACE(
					sql_insert
					,'__PLACEHOLDER__SHAPE'
					,sql_shape_invalid
				)
				,'__PLACEHOLDER__COORDINATES'
				,sql_sr_invalid
			)
		;
		
		EXECUTE IMMEDIATE sql_current;



		--
		-- Update latitude / longitude
		--
		
		sql_current := '
			UPDATE gis.databases_well_permits
			SET
				latitude = sde.st_y(
					sde.st_transform(
						shape
						,gis.gis_refresh.get_wkid(name => ''GCS_NORTH_AMERICAN_1983'')
					)
				)
				,longitude = sde.st_x(
					sde.st_transform(
						shape
						,gis.gis_refresh.get_wkid(name => ''GCS_NORTH_AMERICAN_1983'')
					)
				)
		';
		
		EXECUTE IMMEDIATE sql_current;



		--
		-- Commit changes
		--
		
		COMMIT;

	
	EXCEPTION
	
		WHEN OTHERS THEN
		
			-- Rollback on any error to restore original rows

			ROLLBACK;
			
			DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
			
			RAISE;
			
	END refresh_databases_well_permits;


END gis_refresh;
/

SHOW ERRORS


--------------------------------------------------------------------------------
-- END
--------------------------------------------------------------------------------
