--------------------------------------------------------------------------------
-- Name:
--	create_well_permits_diag.sql
--
-- Purpose:
--	Create table and supporting objects to diagnose changes in well permit
--	coordinates from old (REGUSER.WELL_PROJ_ET) to new (SJR.STN_ET) source
--	tables in E-Reg production database
--
-- Dependencies:
--	PACKAGE		GIS.GIS_REFRESH
--
-- Usage:
--	As GIS user:
--		@create_well_permits_diag.sql
--
-- Environment:
--	Oracle Database 11.2.0.4.0
--	ArcGIS for 10.6.1
--
-- Notes:
--
--	CONTEXT
--
--	The GIS.DATABASES_WELL_PERMITS table is a geodatabae feature class in
--	a local production geodatabase at NWFWMD, whose content is derived from
--	source tables in the remote E-Reg production database at SRJWMD.
--
--	In August 2019, we implemented multiple updates to the structure of the
--	DATABASES_WELL_PERMITS table, as well as the procedure that refreshes
--	its content (GIS.GIS_REFRESH.REFRESH_DATABASES_WELL_PERMITS). One of
--	those changes included fetching coordinate data from a different source
--	table - SJR.STN_ET, instead of REGUSER.WELL_PROJ_ET. In short,
--	coordinates can be collected at various stages of a well project, and
--	the new table is supposed to contain the best available coordinates.
--
--	As part of this change, however, many permits that used to have points
--	no longer do. While some changes are expected, initial analysis suggests
--	that possibly rows in teh 10^5 range are missing shapes that should
--	exist, or have shapes in the wrong location.
--
--
--	SOLUTION
--
--	This script creates a table of diagnostic information, and various
--	supporting objects, to help describe the old > new geometry changes.
--	This includes information to identify shapes that are currently missing,
--	but that can potentially be salvaged through a bulk update on the
--	source table.
--
--	At a high level, this script creates a diagnostic table that includes:
--
--		o All of the attributes (excepting internal geodatabase columns)
--		  from the DATABASES_WELL_PERMITS table
--
--		o Various additional diagnostic columns (prefixed with DIAG_) to
--		  describe the old and new coordinate data, and the changes
--		  between them
--
--	See supporting documentation, and embedded comments below, for details
--	on the diagnostic columns.
--
--	The diagnostic table is named WP_DIAG. This table contains three spatial
--	columns (ST_GEOMETRY), as well as several columns of numeric coordinates
--	in decimal degree format from which ArcGIS event layers can be created.
--
--	Because ArcGIS only supports a single spatial column per feature class,
--	three supporting views serve as proxies for the master WP_DIAG table,
--	each exposing a single spatial column, for use with ArcGIS:
--
--		WP_DIAG_NEW
--		WP_DIAG_OLD
--		WP_DIAG_SALVAGE
--
--	In each case, the ROW_ID column serves as an arbitrary, unique, integer
--	identifier that can be used when displaying these non-geodatabase
--	(i.e. unregistered) tables as layers in ArcGIS clients.
--
--	The spatial reference for all spatial columns is EPSG WKID 26916
--	(NAD 1983 UTM Zone 16N).
--
-- History:
--	2020-01-13 MCM Created
--
-- To do:
--	none
--
-- Copyright 2003-2020. Mannion Geosystems, LLC. http://www.manniongeo.com
--------------------------------------------------------------------------------

SET ECHO OFF
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET TIMING ON



SELECT SYSDATE FROM dual;



--------------------------------------------------------------------------------
-- Create table
--------------------------------------------------------------------------------

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Creating table GIS.WP_DIAG');
SET FEEDBACK ON
SET TIMING ON

CREATE TABLE gis.wp_diag (
	row_id				NUMBER(38)
	,permit_number			NVARCHAR2(50)
	,legacy_permit_number		NVARCHAR2(35)
	,related_permit_1		NVARCHAR2(50)
	,related_permit_2		NVARCHAR2(50)
	,job_type			NVARCHAR2(100)
	,status				NVARCHAR2(200)
	,official_id			NUMBER(38)
	,issue_date			TIMESTAMP(6)
	,expiration_date		TIMESTAMP(6)
	,completion_date		TIMESTAMP(6)
	,exemption			NVARCHAR2(7)
	,owner_first			NVARCHAR2(30)
	,owner_last			NVARCHAR2(30)
	,well_use			NVARCHAR2(100)
	,diameter			NUMBER(38,8)
	,appl_well_depth		NUMBER(38,8)
	,appl_casing_depth		NUMBER(38,8)
	,wcr_well_depth			NUMBER(38,8)
	,wcr_casing_depth		NUMBER(38,8)
	,open_hole_from			NUMBER(38,8)
	,open_hole_to			NUMBER(38,8)
	,screen_from			NUMBER(38,8)
	,screen_to			NUMBER(38,8)
	,well_street			NVARCHAR2(60)
	,well_street_2			NVARCHAR2(50)
	,well_city			NVARCHAR2(30)
	,well_county			NVARCHAR2(20)
	,parcel_id			NVARCHAR2(50)
	,latitude			NUMBER(38,8)
	,longitude			NUMBER(38,8)
	,township			NVARCHAR2(3)
	,range				NVARCHAR2(3)
	,section			NUMBER(5)
	,cu_permit			NVARCHAR2(50)
	,fluwid				NVARCHAR2(50)
	,location_method		NVARCHAR2(16)
	,contractor_license		NUMBER(38)
	,contractor_name		NVARCHAR2(70)
	,wrca				NVARCHAR2(7)
	,arc				NVARCHAR2(7)
	,grout_line			NVARCHAR2(100)
	,construction_method		NVARCHAR2(100)
	,w62_524			NVARCHAR2(7)
	,stn_id				NUMBER(38)
	,shape				SDE.ST_GEOMETRY
	,diag_shape_old			SDE.ST_GEOMETRY
	,diag_shape_salvage		SDE.ST_GEOMETRY
	,diag_longitude			NUMBER(38,8)
	,diag_latitude			NUMBER(38,8)
	,diag_longitude_old		NUMBER(38,8)
	,diag_latitude_old		NUMBER(38,8)
	,diag_longitude_salvage		NUMBER(38,8)
	,diag_latitude_salvage		NUMBER(38,8)
	,diag_raw_longitude		NUMBER(38,8)
	,diag_raw_latitude		NUMBER(38,8)
	,diag_raw_longitude_old		NUMBER(38,8)
	,diag_raw_latitude_old		NUMBER(38,8)
	,diag_coord_code		NVARCHAR2(32)
	,diag_coord_code_old		NVARCHAR2(32)
	,diag_coord_code_salvage	NVARCHAR2(32)
	,diag_status_shape		NVARCHAR2(32)
	,diag_status_shape_old		NVARCHAR2(32)
	,diag_status_shape_salvage	NVARCHAR2(32)
	,diag_status_ll			NVARCHAR2(32)
	,diag_status_ll_old		NVARCHAR2(32)
	,diag_status_longitude		NVARCHAR2(32)
	,diag_status_latitude		NVARCHAR2(32)
	,diag_status_longitude_old	NVARCHAR2(32)
	,diag_status_latitude_old	NVARCHAR2(32)
	,diag_status_coord_code		NVARCHAR2(32)
	,diag_status_coord_code_old	NVARCHAR2(32)
	,diag_status_coord_code_salvage	NVARCHAR2(32)
	,diag_status_move		NVARCHAR2(32)
	,diag_move_distance		NUMBER(38,8)
	,diag_move_bearing		NUMBER(38)
)
;


--------------------------------------------------------------------------------
-- Populate table
--
-- Code below is adapted from GIS.GIS_REFRESH.REFRESH_DATABASES_WELL_PERMITS,
-- with the following changes:
--
--	o Load all rows with a single INSERT, then UPDATE shapes subsequently.
--	  This is possible here, because we are keeping the raw coordinates /
--	  coordinate codes, which are only used dynamically in the real
--	  refresh procedure.
--
--	o Omit the call to SDE.GDB_UTIL.NEXT_ROWID. Because this is not a
--	  registered geodatabase table, there is no OBJECTID sequence. Instead,
--	  we assign arbitrary IDs (via Oracle ROWNUM) later.
--------------------------------------------------------------------------------


--------------------
-- Load data from source
--------------------


--
-- Insert production attributes, and raw coordinates
--

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Loading rows from NWPROD.SJRWMD.COM');
SET FEEDBACK ON
SET TIMING ON

INSERT INTO gis.wp_diag (
	permit_number
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
	,diag_raw_longitude
	,diag_raw_latitude
	,diag_raw_longitude_old
	,diag_raw_latitude_old
	,diag_coord_code
	,diag_coord_code_old
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
				,'No'
				,0
				,'No'
				,1
				,'Yes'
				,'Unknown'
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
				,'No'
				,1
				,'Yes'
				,'Unknown'
			) AS NVARCHAR2(7)
		) wrca
		,CAST(
			DECODE(
				wpe.arc_cd
				,NULL
				,'No'
				,0
				,'No'
				,1
				,'Yes'
				,'Unknown'
			) AS NVARCHAR2(7)
		) arc
		,d6.tp_dsc grout_line
		,d7.tp_dsc construction_method
		,CAST(
			DECODE(
				wpe.delin_cd
				,0
				,'No'
				,1
				,'Yes'
				,'Unknown'
			) AS NVARCHAR2(7)
		) w62_524
		,ps.stn_id
		,se.crdnt_cd -- Spatial reference filter predicate
		,wpe.long_no diag_raw_longitude_old
		,wpe.lat_no diag_raw_latitude_old
		,d1.tp_dsc diag_coord_code
		,d10.tp_dsc diag_coord_code_old
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
	LEFT JOIN ingres.sjr_abbr_def_et@nwprod.sjrwmd.com d10 ON -- Coordinate format
		wpe.crdnt_cd = d10.tp_id
	WHERE
		rpe1.fac_rule_id = 498
		AND d8.tp_dsc != 'RESC' -- Rescinded
		AND d9.tp_dsc NOT IN (
			'Administrative Denial'
			,'Substantive Denial'
			,'Withdrawn'
		)
)
SELECT
	/*+
		NO_MERGE(remote)
	*/
	remote.permit_number
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
	,remote.raw_longitude -- diag_raw_longitude
	,remote.raw_latitude -- diag_raw_latitude
	,remote.diag_raw_longitude_old
	,remote.diag_raw_latitude_old
	,remote.diag_coord_code
	,remote.diag_coord_code_old
FROM remote
;



--
-- Assign new/old shapes
--


-- New DD

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning SHAPE: DD');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	shape = sde.st_transform(
		sde.st_point(
			pt_x => diag_raw_longitude
			,pt_y => diag_raw_latitude
			,srid => gis.gis_refresh.get_wkid(name => 'GCS_North_American_1983')
		)
		,gis.gis_refresh.get_wkid(name => 'NAD_1983_UTM_Zone_16N')
	)
WHERE
	diag_coord_code = 'DD'
	AND diag_raw_longitude IS NOT NULL
	AND diag_raw_longitude > gis.gis_refresh.get_ordinate_dd_xmin
	AND diag_raw_longitude < gis.gis_refresh.get_ordinate_dd_xmax
	AND diag_raw_latitude IS NOT NULL
	AND diag_raw_latitude > gis.gis_refresh.get_ordinate_dd_ymin
	AND diag_raw_latitude < gis.gis_refresh.get_ordinate_dd_ymax
;



-- New DMS

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning SHAPE: DMS');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	shape = sde.st_transform(
		sde.st_point(
			pt_x => (gis.gis_refresh.dms_to_dd(ordinate => diag_raw_longitude)) * -1
			,pt_y => gis.gis_refresh.dms_to_dd(ordinate => diag_raw_latitude)
			,srid => gis.gis_refresh.get_wkid(name => 'GCS_North_American_1983')
		)
		,gis.gis_refresh.get_wkid(name => 'NAD_1983_UTM_Zone_16N')
	)
WHERE
	diag_coord_code = 'DMS'
	AND diag_raw_longitude IS NOT NULL
	AND (diag_raw_longitude * -1) > gis.gis_refresh.get_ordinate_dms_xmin
	AND (diag_raw_longitude * -1) < gis.gis_refresh.get_ordinate_dms_xmax
	AND diag_raw_latitude IS NOT NULL
	AND diag_raw_latitude > gis.gis_refresh.get_ordinate_dms_ymin
	AND diag_raw_latitude < gis.gis_refresh.get_ordinate_dms_ymax
;



-- New UTM

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning SHAPE: UTM');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	shape = sde.st_point(
		pt_x => diag_raw_longitude
		,pt_y => diag_raw_latitude
		,srid => gis.gis_refresh.get_wkid(name => 'GCS_North_American_1983')
	)
WHERE
	diag_coord_code = 'UTM'
	AND diag_raw_longitude IS NOT NULL
	AND diag_raw_longitude > gis.gis_refresh.get_ordinate_utm_xmin
	AND diag_raw_longitude < gis.gis_refresh.get_ordinate_utm_xmax
	AND diag_raw_latitude IS NOT NULL
	AND diag_raw_latitude > gis.gis_refresh.get_ordinate_utm_ymin
	AND diag_raw_latitude < gis.gis_refresh.get_ordinate_utm_ymax
;



-- Old DD

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning DIAG_SHAPE_OLD: DD');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_shape_old = sde.st_transform(
		sde.st_point(
			pt_x => diag_raw_longitude_old
			,pt_y => diag_raw_latitude_old
			,srid => gis.gis_refresh.get_wkid(name => 'GCS_North_American_1983')
		)
		,gis.gis_refresh.get_wkid(name => 'NAD_1983_UTM_Zone_16N')
	)
WHERE
	diag_coord_code_old = 'DD'
	AND diag_raw_longitude_old IS NOT NULL
	AND diag_raw_longitude_old > gis.gis_refresh.get_ordinate_dd_xmin
	AND diag_raw_longitude_old < gis.gis_refresh.get_ordinate_dd_xmax
	AND diag_raw_latitude_old IS NOT NULL
	AND diag_raw_latitude_old > gis.gis_refresh.get_ordinate_dd_ymin
	AND diag_raw_latitude_old < gis.gis_refresh.get_ordinate_dd_ymax
;



-- Old DMS

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning DIAG_SHAPE_OLD: DMS');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_shape_old = sde.st_transform(
		sde.st_point(
			pt_x => (gis.gis_refresh.dms_to_dd(ordinate => diag_raw_longitude_old)) * -1
			,pt_y => gis.gis_refresh.dms_to_dd(ordinate => diag_raw_latitude_old)
			,srid => gis.gis_refresh.get_wkid(name => 'GCS_North_American_1983')
		)
		,gis.gis_refresh.get_wkid(name => 'NAD_1983_UTM_Zone_16N')
	)
WHERE
	diag_coord_code_old = 'DMS'
	AND diag_raw_longitude_old IS NOT NULL
	AND (diag_raw_longitude_old * -1) > gis.gis_refresh.get_ordinate_dms_xmin
	AND (diag_raw_longitude_old * -1) < gis.gis_refresh.get_ordinate_dms_xmax
	AND diag_raw_latitude_old IS NOT NULL
	AND diag_raw_latitude_old > gis.gis_refresh.get_ordinate_dms_ymin
	AND diag_raw_latitude_old < gis.gis_refresh.get_ordinate_dms_ymax
;



-- Old UTM

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning DIAG_SHAPE_OLD: UTM');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_shape_old = sde.st_point(
		pt_x => diag_raw_longitude_old
		,pt_y => diag_raw_latitude_old
		,srid => gis.gis_refresh.get_wkid(name => 'GCS_North_American_1983')
	)
WHERE
	diag_coord_code_old = 'UTM'
	AND diag_raw_longitude_old IS NOT NULL
	AND diag_raw_longitude_old > gis.gis_refresh.get_ordinate_utm_xmin
	AND diag_raw_longitude_old < gis.gis_refresh.get_ordinate_utm_xmax
	AND diag_raw_latitude_old IS NOT NULL
	AND diag_raw_latitude_old > gis.gis_refresh.get_ordinate_utm_ymin
	AND diag_raw_latitude_old < gis.gis_refresh.get_ordinate_utm_ymax
;



--
-- Numeric representation of shape as longitude/latitude
--


-- New: Production LONGITUDE/LATITUDE attributes

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning:' || CHR(10) || CHR(9) || 'LONGITUDE' || CHR(10) || CHR(9) || 'LATITUDE');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	longitude = sde.st_x(
		sde.st_transform(
			shape
			,gis.gis_refresh.get_wkid(name => 'GCS_NORTH_AMERICAN_1983')
		)
	)
	,latitude = sde.st_y(
		sde.st_transform(
			shape
			,gis.gis_refresh.get_wkid(name => 'GCS_NORTH_AMERICAN_1983')
		)
	)
;



-- New: Diagnostic copy of production attributes (same values, different names)

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning:' || CHR(10) || CHR(9) || 'DIAG_LONGITUDE' || CHR(10) || CHR(9) || 'DIAG_LATITUDE');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_longitude = longitude
	,diag_latitude = latitude
;



-- Old

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning:' || CHR(10) || CHR(9) || 'DIAG_LONGITUDE_OLD' || CHR(10) || CHR(9) || 'DIAG_LATITUDE_OLD');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_longitude_old = sde.st_x(
		sde.st_transform(
			diag_shape_old
			,gis.gis_refresh.get_wkid(name => 'GCS_NORTH_AMERICAN_1983')
		)
	)
	,diag_latitude_old = sde.st_y(
		sde.st_transform(
			diag_shape_old
			,gis.gis_refresh.get_wkid(name => 'GCS_NORTH_AMERICAN_1983')
		)
	)
;



--------------------
-- Assign unique row IDs
--------------------

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning ROW_ID');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	row_id = ROWNUM
;



--------------------
-- Assign diagnostics (except salvage)
--------------------


--
-- Shape status
--

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning:' || CHR(10) || CHR(9) || 'DIAG_STATUS_SHAPE' || CHR(10) || CHR(9) || 'DIAG_STATUS_SHAPE_OLD');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_status_shape = CASE sde.st_isempty(shape)
		WHEN 0 THEN 'Valid'
		ELSE 'Missing'
	END
	,diag_status_shape_old = CASE sde.st_isempty(diag_shape_old)
		WHEN 0 THEN 'Valid'
		ELSE 'Missing'
	END
;



--
-- Longitude / latitude status
--


-- Individual

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning:' || CHR(10) || CHR(9) || 'DIAG_STATUS_LONGITUDE' || CHR(10) || CHR(9) || 'DIAG_STATUS_LATITUDE' || CHR(10) || CHR(9) || 'DIAG_STATUS_LONGITUDE_OLD' || CHR(10) || CHR(9) || 'DIAG_STATUS_LATITUDE_OLD');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_status_longitude = CASE
		WHEN diag_raw_longitude IS NULL THEN 'Missing'
		WHEN (
			diag_coord_code IS NULL
			OR diag_coord_code NOT IN ('DD', 'DMS', 'UTM')
		) THEN 'Invalid: Unknown coord code'
		WHEN (
			diag_coord_code = 'DD' AND diag_raw_longitude < gis.gis_refresh.get_ordinate_dd_xmin
			OR diag_coord_code = 'DMS' AND (diag_raw_longitude * -1) < gis.gis_refresh.get_ordinate_dms_xmin
			OR diag_coord_code = 'UTM' AND diag_raw_longitude < gis.gis_refresh.get_ordinate_utm_xmin
		) THEN 'Invalid: Too small'
		WHEN (
			diag_coord_code = 'DD' AND diag_raw_longitude > gis.gis_refresh.get_ordinate_dd_xmax
			OR diag_coord_code = 'DMS' AND (diag_raw_longitude * -1) > gis.gis_refresh.get_ordinate_dms_xmax
			OR diag_coord_code = 'UTM' AND diag_raw_longitude > gis.gis_refresh.get_ordinate_utm_xmax
		) THEN 'Invalid: Too large'
		ELSE 'Valid'
	END
	,diag_status_latitude = CASE
		WHEN diag_raw_latitude IS NULL THEN 'Missing'
		WHEN (
			diag_coord_code IS NULL
			OR diag_coord_code NOT IN ('DD', 'DMS', 'UTM')
		) THEN 'Invalid: Unknown coord code'
		WHEN (
			diag_coord_code = 'DD' AND diag_raw_latitude < gis.gis_refresh.get_ordinate_dd_ymin
			OR diag_coord_code = 'DMS' AND diag_raw_latitude < gis.gis_refresh.get_ordinate_dms_ymin
			OR diag_coord_code = 'UTM' AND diag_raw_latitude < gis.gis_refresh.get_ordinate_utm_ymin
		) THEN 'Invalid: Too small'
		WHEN (
			diag_coord_code = 'DD' AND diag_raw_latitude > gis.gis_refresh.get_ordinate_dd_ymax
			OR diag_coord_code = 'DMS' AND diag_raw_latitude > gis.gis_refresh.get_ordinate_dms_ymax
			OR diag_coord_code = 'UTM' AND diag_raw_latitude > gis.gis_refresh.get_ordinate_utm_ymax
		) THEN 'Invalid: Too large'
		ELSE 'Valid'
	END
	,diag_status_longitude_old = CASE
		WHEN diag_raw_longitude_old IS NULL THEN 'Missing'
		WHEN (
			diag_coord_code_old IS NULL
			OR diag_coord_code_old NOT IN ('DD', 'DMS', 'UTM')
		) THEN 'Invalid: Unknown coord code'
		WHEN (
			diag_coord_code_old = 'DD' AND diag_raw_longitude_old < gis.gis_refresh.get_ordinate_dd_xmin
			OR diag_coord_code_old = 'DMS' AND (diag_raw_longitude_old * -1) < gis.gis_refresh.get_ordinate_dms_xmin
			OR diag_coord_code_old = 'UTM' AND diag_raw_longitude_old < gis.gis_refresh.get_ordinate_utm_xmin
		) THEN 'Invalid: Too small'
		WHEN (
			diag_coord_code_old = 'DD' AND diag_raw_longitude_old > gis.gis_refresh.get_ordinate_dd_xmax
			OR diag_coord_code_old = 'DMS' AND (diag_raw_longitude_old * -1) > gis.gis_refresh.get_ordinate_dms_xmax
			OR diag_coord_code_old = 'UTM' AND diag_raw_longitude_old > gis.gis_refresh.get_ordinate_utm_xmax
		) THEN 'Invalid: Too large'
		ELSE 'Valid'
	END
	,diag_status_latitude_old = CASE
		WHEN diag_raw_latitude_old IS NULL THEN 'Missing'
		WHEN (
			diag_coord_code_old IS NULL
			OR diag_coord_code_old NOT IN ('DD', 'DMS', 'UTM')
		) THEN 'Invalid: Unknown coord code'
		WHEN (
			diag_coord_code_old = 'DD' AND diag_raw_latitude_old < gis.gis_refresh.get_ordinate_dd_ymin
			OR diag_coord_code_old = 'DMS' AND diag_raw_latitude_old < gis.gis_refresh.get_ordinate_dms_ymin
			OR diag_coord_code_old = 'UTM' AND diag_raw_latitude_old < gis.gis_refresh.get_ordinate_utm_ymin
		) THEN 'Invalid: Too small'
		WHEN (
			diag_coord_code_old = 'DD' AND diag_raw_latitude_old > gis.gis_refresh.get_ordinate_dd_ymax
			OR diag_coord_code_old = 'DMS' AND diag_raw_latitude_old > gis.gis_refresh.get_ordinate_dms_ymax
			OR diag_coord_code_old = 'UTM' AND diag_raw_latitude_old > gis.gis_refresh.get_ordinate_utm_ymax
		) THEN 'Invalid: Too large'
		ELSE 'Valid'
	END
;



-- Summarized

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning:' || CHR(10) || CHR(9) || 'DIAG_STATUS_LL' || CHR(10) || CHR(9) || 'DIAG_STATUS_LL_OLD');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_status_ll = CASE
		WHEN (
			diag_status_longitude = 'Valid'
			AND diag_status_latitude = 'Valid'
		) THEN 'Valid'
		WHEN (
			diag_status_longitude = 'Missing'
			AND diag_status_latitude = 'Missing'
		) THEN 'Missing'
		ELSE 'Invalid'
	END
	,diag_status_ll_old = CASE
		WHEN (
			diag_status_longitude_old = 'Valid'
			AND diag_status_latitude_old = 'Valid'
		) THEN 'Valid'
		WHEN (
			diag_status_longitude_old = 'Missing'
			AND diag_status_latitude_old = 'Missing'
		) THEN 'Missing'
		ELSE 'Invalid'
	END
;



--
-- Coordinate code status
--

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning:' || CHR(10) || CHR(9) || 'DIAG_STATUS_COORD_CODE' || CHR(10) || CHR(9) || 'DIAG_STATUS_COORD_CODE_OLD');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_status_coord_code = CASE
		WHEN diag_coord_code IS NULL THEN 'Missing'
		WHEN diag_coord_code IN ('DD', 'DMS', 'UTM') THEN 'Valid'
		ELSE 'Invalid'
	END
	,diag_status_coord_code_old = CASE
		WHEN diag_coord_code_old IS NULL THEN 'Missing'
		WHEN diag_coord_code_old IN ('DD', 'DMS', 'UTM') THEN 'Valid'
		ELSE 'Invalid'
	END
;



--
-- Old > new shape movement
--


-- Movement status

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning DIAG_STATUS_MOVE');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_status_move = CASE
		WHEN shape = diag_shape_old THEN 'Same'
		WHEN shape IS NULL AND diag_shape_old IS NULL THEN 'Missing: Both'
		WHEN shape IS NULL AND diag_shape_old IS NOT NULL THEN 'Missing: New'
		WHEN shape IS NOT NULL AND diag_shape_old IS NULL THEN 'Missing: Old'
		ELSE 'Moved'
	END
;


-- Distance

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning DIAG_MOVE_DISTANCE');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_move_distance = sde.st_distance(
		shape
		,diag_shape_old
	)
;



-- Bearing
--
-- For points that have moved location, the compass bearing that point moved
-- (old > new)
--
-- Technical notes:
--
--	o In this context, the bearing is the approximate compass direction from
--	  the old point to the new point. This is "approximate" because
--	  navigational bearings can vary based on the users's goal (e.g. constant
--	  bearing, shortest distance). Additionally, we compute the bearing in
--	  planar space, using basic trigonometry. This approach meets our needs
--	  for generally pointing the user in the right direction.
--
--	o We compute deltas as (new - old) in order to get the bearing from the
--	  old point to the new one, as opposed to vice versa.
--
--	o The ATAN2 function takes delta Y as the first argument, and delta X as
--	  the second. This is ambiguous in the Oracle documentation.
--
--	o ATAN2 yields:
--		o Radians
--		o Zero radians to the East
--		o Positive radians going counter-clockwise (0 East to +pi West)
--		o Negative radians going clockwise (0 East to -pi West)
--
--	o We convert ATAN2 radians to compass bearings (0 North, 0 to 360,
--	  positive clockwise) by:
--
--		o Multiplying by -1 to make clockwise positive
--
--		o Add 450 degrees:
--			o 90 degrees rotates zero from East to North
--			o 360 degrees pushes remaining negative coordinates to
--			  positive values
--
--		o Mod 360, to scale back to 0 to 360 range
--
--	o We must limit the ATAN2 function to points which have actually moved,
--	  in order to avoid an "ORA-01426: numeric overflow" error.
--
--	o SQL and PL/SQL do not include a pi constant/function. To avoid
--	  switching languages (e.g. Java), we use SDO_UTIL.CONVERT_UNIT to
--	  convert radians to degrees.

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning DIAG_MOVE_BEARING');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_move_bearing = MOD(
		(
			SDO_UTIL.CONVERT_UNIT(
				ATAN2(
					sde.st_y(shape) - sde.st_y(diag_shape_old)
					,sde.st_x(shape) - sde.st_x(diag_shape_old)
				)
				,'Radian'
				,'Degree'
			) * -1
		) + 450
		,360
	)
WHERE
	diag_move_distance > 0
;



--------------------
-- Assign salvage diagnostics
--
-- Only process potentially salvageable rows - that is, rows where the new:
--	o Coordinate code IS NULL
--	o Longitude IS NOT NULL
--	o Latitude IS NOT NULL
--------------------


--
-- Coordinate code
--

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning DIAG_COORD_CODE_SALVAGE');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_coord_code_salvage = CASE
		WHEN (
			diag_raw_longitude > gis.gis_refresh.get_ordinate_dd_xmin
			AND diag_raw_longitude < gis.gis_refresh.get_ordinate_dd_xmax
			AND diag_raw_latitude > gis.gis_refresh.get_ordinate_dd_ymin
			AND diag_raw_latitude < gis.gis_refresh.get_ordinate_dd_ymax
		) THEN 'DD'
		WHEN (
			(diag_raw_longitude * -1) > gis.gis_refresh.get_ordinate_dms_xmin
			AND (diag_raw_longitude * -1) < gis.gis_refresh.get_ordinate_dms_xmax
			AND diag_raw_latitude > gis.gis_refresh.get_ordinate_dms_ymin
			AND diag_raw_latitude < gis.gis_refresh.get_ordinate_dms_ymax
		) THEN 'DMS'
		WHEN (
			(diag_raw_longitude * -1) > gis.gis_refresh.get_ordinate_dms_xmin
			AND (diag_raw_longitude * -1) < gis.gis_refresh.get_ordinate_dms_xmax
			AND diag_raw_latitude > gis.gis_refresh.get_ordinate_dms_ymin
			AND diag_raw_latitude < gis.gis_refresh.get_ordinate_dms_ymax
		) THEN 'UTM'
		ELSE 'Invalid'
	END
WHERE
	diag_coord_code IS NULL
	AND diag_raw_longitude IS NOT NULL
	AND diag_raw_latitude IS NOT NULL
;



--
-- Coordinate code summary
--

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning DIAG_STATUS_COORD_CODE_SALVAGE');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_status_coord_code_salvage = CASE
		WHEN diag_coord_code_salvage IN ('DD', 'DMS', 'UTM') THEN 'Valid'
		ELSE 'Invalid'
	END
WHERE
	diag_coord_code_salvage IS NOT NULL
;



--
-- Shape
--


-- DD

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning DIAG_SHAPE_SALVAGE: DD');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_shape_salvage = sde.st_transform(
		sde.st_point(
			pt_x => diag_raw_longitude
			,pt_y => diag_raw_latitude
			,srid => gis.gis_refresh.get_wkid(name => 'GCS_North_American_1983')
		)
		,gis.gis_refresh.get_wkid(name => 'NAD_1983_UTM_Zone_16N')
	)
WHERE
	diag_coord_code_salvage = 'DD'
;



-- DMS

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning DIAG_SHAPE_SALVAGE: DMS');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_shape_salvage = sde.st_transform(
		sde.st_point(
			pt_x => (gis.gis_refresh.dms_to_dd(ordinate => diag_raw_longitude)) * -1
			,pt_y => gis.gis_refresh.dms_to_dd(ordinate => diag_raw_latitude)
			,srid => gis.gis_refresh.get_wkid(name => 'GCS_North_American_1983')
		)
		,gis.gis_refresh.get_wkid(name => 'NAD_1983_UTM_Zone_16N')
	)
WHERE
	diag_coord_code_salvage = 'DMS'
;


	
-- UTM

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning DIAG_SHAPE_SALVAGE: UTM');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_shape_salvage = sde.st_point(
		pt_x => diag_raw_longitude
		,pt_y => diag_raw_latitude
		,srid => gis.gis_refresh.get_wkid(name => 'GCS_North_American_1983')
	)
WHERE
	diag_coord_code_salvage = 'UTM'
;



--
-- Shape status
--

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning DIAG_STATUS_SHAPE_SALVAGE');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_status_shape_salvage = CASE sde.st_isempty(diag_shape_salvage)
		WHEN 0 THEN 'Valid'
		ELSE 'Missing'
	END
WHERE
	diag_coord_code IS NULL
	AND diag_raw_longitude IS NOT NULL
	AND diag_raw_latitude IS NOT NULL
;



--
-- Numeric representation of shape as longitude/latitude
--

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Assigning:' || CHR(10) || CHR(9) || 'DIAG_LONGITUDE_SALVAGE' || CHR(10) || CHR(9) || 'DIAG_SHAPE_LATITUDE_SALVAGE');
SET FEEDBACK ON
SET TIMING ON

UPDATE gis.wp_diag
SET
	diag_longitude_salvage = sde.st_x(
		sde.st_transform(
			diag_shape_salvage
			,gis.gis_refresh.get_wkid(name => 'GCS_NORTH_AMERICAN_1983')
		)
	)
	,diag_latitude_salvage = sde.st_y(
		sde.st_transform(
			diag_shape_salvage
			,gis.gis_refresh.get_wkid(name => 'GCS_NORTH_AMERICAN_1983')
		)
	)
WHERE
	diag_status_shape_salvage = 'Valid'
;



--------------------
-- Commit
--------------------

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Committing');
SET FEEDBACK ON
SET TIMING ON

COMMIT;



--------------------------------------------------------------------------------
-- Create indexes
--------------------------------------------------------------------------------


--------------------
-- Spatial
--------------------

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Creating index: SHAPE');
SET FEEDBACK ON
SET TIMING ON

CREATE INDEX gis.wp_diag_shape_new
ON gis.wp_diag (
	shape
)
INDEXTYPE IS sde.st_spatial_index
PARAMETERS (
	'ST_GRIDS=1000,0,0 ST_SRID=26916'
)
;


SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Creating index: DIAG_SHAPE_OLD');
SET FEEDBACK ON
SET TIMING ON

CREATE INDEX gis.wp_diag_shape_old
ON gis.wp_diag (
	diag_shape_old
)
INDEXTYPE IS sde.st_spatial_index
PARAMETERS (
	'ST_GRIDS=1000,0,0 ST_SRID=26916'
)
;


SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Creating index: DIAG_SHAPE_SALVAGE');
SET FEEDBACK ON
SET TIMING ON

CREATE INDEX gis.wp_diag_shape_salvage
ON gis.wp_diag (
	diag_shape_salvage
)
INDEXTYPE IS sde.st_spatial_index
PARAMETERS (
	'ST_GRIDS=1000,0,0 ST_SRID=26916'
)
;



--------------------
-- Non-spatial
--------------------

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Creating index: ROW_ID');
SET FEEDBACK ON
SET TIMING ON

CREATE UNIQUE INDEX gis.wp_diag_row_id
ON gis.wp_diag (
	row_id
)
;



SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Creating index: PERMIT_NUMBER');
SET FEEDBACK ON
SET TIMING ON

CREATE INDEX gis.wp_diag_permit_number
ON gis.wp_diag (
	permit_number
)
;



SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Creating index: LEGACY_PERMIT_NUMBER');
SET FEEDBACK ON
SET TIMING ON

CREATE INDEX gis.wp_diag_legacy_permit_number
ON gis.wp_diag (
	legacy_permit_number
)
;



--------------------------------------------------------------------------------
-- Create views
--------------------------------------------------------------------------------


--------------------
-- Feature class views
--
-- WP_DIAG has three spatial columns. ArcGIS only supports one spatial column
-- per table. Therefore, create three view, each of which contains:
--
--	o One of the spatial columns (new, old, salvage)
--
--	o All of the other attributes
--------------------


-- New shape as spatial column

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Creating view: WP_DIAG_NEW');
SET FEEDBACK ON
SET TIMING ON

CREATE OR REPLACE VIEW gis.wp_diag_new AS
SELECT
	row_id
	,shape AS shape
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
	,diag_longitude
	,diag_latitude
	,diag_longitude_old
	,diag_latitude_old
	,diag_longitude_salvage
	,diag_latitude_salvage
	,diag_raw_longitude
	,diag_raw_latitude
	,diag_raw_longitude_old
	,diag_raw_latitude_old
	,diag_coord_code
	,diag_coord_code_old
	,diag_coord_code_salvage
	,diag_status_shape
	,diag_status_shape_old
	,diag_status_shape_salvage
	,diag_status_ll
	,diag_status_ll_old
	,diag_status_longitude
	,diag_status_latitude
	,diag_status_longitude_old
	,diag_status_latitude_old
	,diag_status_coord_code
	,diag_status_coord_code_old
	,diag_status_coord_code_salvage
	,diag_status_move
	,diag_move_distance
	,diag_move_bearing
FROM gis.wp_diag
;



-- Old shape as spatial column

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Creating view: WP_DIAG_OLD');
SET FEEDBACK ON
SET TIMING ON

CREATE OR REPLACE VIEW gis.wp_diag_old AS
SELECT
	row_id
	,diag_shape_old AS shape
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
	,diag_longitude
	,diag_latitude
	,diag_longitude_old
	,diag_latitude_old
	,diag_longitude_salvage
	,diag_latitude_salvage
	,diag_raw_longitude
	,diag_raw_latitude
	,diag_raw_longitude_old
	,diag_raw_latitude_old
	,diag_coord_code
	,diag_coord_code_old
	,diag_coord_code_salvage
	,diag_status_shape
	,diag_status_shape_old
	,diag_status_shape_salvage
	,diag_status_ll
	,diag_status_ll_old
	,diag_status_longitude
	,diag_status_latitude
	,diag_status_longitude_old
	,diag_status_latitude_old
	,diag_status_coord_code
	,diag_status_coord_code_old
	,diag_status_coord_code_salvage
	,diag_status_move
	,diag_move_distance
	,diag_move_bearing
FROM gis.wp_diag
;



-- Salvage shape as spatial column

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Creating view: WP_DIAG_SALVAGE');
SET FEEDBACK ON
SET TIMING ON

CREATE OR REPLACE VIEW gis.wp_diag_salvage AS
SELECT
	row_id
	,diag_shape_salvage AS shape
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
	,diag_longitude
	,diag_latitude
	,diag_longitude_old
	,diag_latitude_old
	,diag_longitude_salvage
	,diag_latitude_salvage
	,diag_raw_longitude
	,diag_raw_latitude
	,diag_raw_longitude_old
	,diag_raw_latitude_old
	,diag_coord_code
	,diag_coord_code_old
	,diag_coord_code_salvage
	,diag_status_shape
	,diag_status_shape_old
	,diag_status_shape_salvage
	,diag_status_ll
	,diag_status_ll_old
	,diag_status_longitude
	,diag_status_latitude
	,diag_status_longitude_old
	,diag_status_latitude_old
	,diag_status_coord_code
	,diag_status_coord_code_old
	,diag_status_coord_code_salvage
	,diag_status_move
	,diag_move_distance
	,diag_move_bearing
FROM gis.wp_diag
;



--------------------
-- Non-spatial
--------------------


--
-- WP_DIAG_EXPORT
--
-- All columns except the three spatial column, to facilitate exporting >
-- reporting in non-GIS appliations
--

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Creating view: WP_DIAG_EXPORT');
SET FEEDBACK ON
SET TIMING ON

CREATE OR REPLACE VIEW gis.wp_diag_export AS
SELECT
	row_id
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
	,diag_longitude
	,diag_latitude
	,diag_longitude_old
	,diag_latitude_old
	,diag_longitude_salvage
	,diag_latitude_salvage
	,diag_raw_longitude
	,diag_raw_latitude
	,diag_raw_longitude_old
	,diag_raw_latitude_old
	,diag_coord_code
	,diag_coord_code_old
	,diag_coord_code_salvage
	,diag_status_shape
	,diag_status_shape_old
	,diag_status_shape_salvage
	,diag_status_ll
	,diag_status_ll_old
	,diag_status_longitude
	,diag_status_latitude
	,diag_status_longitude_old
	,diag_status_latitude_old
	,diag_status_coord_code
	,diag_status_coord_code_old
	,diag_status_coord_code_salvage
	,diag_status_move
	,diag_move_distance
	,diag_move_bearing
FROM gis.wp_diag
;



--
-- WP_DIAG_XYTOLINE
--
-- Expose attributes required for running the XYToLine_management geoprocessing
-- tool, which is used to create the WP_DIAG_MOVE feature class
--

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Creating view: WP_DIAG_XYTOLINE');
SET FEEDBACK ON
SET TIMING ON

CREATE OR REPLACE VIEW wp_diag_xytoline AS
SELECT
	row_id
	,sde.st_x(diag_shape_old) x_old
	,sde.st_y(diag_shape_old) y_old
	,sde.st_x(shape) x_new
	,sde.st_y(shape) y_new
FROM gis.wp_diag
WHERE
	diag_move_distance > 0
;



--------------------------------------------------------------------------------
-- Grants
--------------------------------------------------------------------------------

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || '--------------------' || CHR(10) || 'Granting SELECT to MAPSERVER');
SET FEEDBACK ON
SET TIMING ON


-- Feature class views

GRANT SELECT ON gis.wp_diag_new TO mapserver;
GRANT SELECT ON gis.wp_diag_old TO mapserver;
GRANT SELECT ON gis.wp_diag_salvage TO mapserver;


-- Attribute-only view

GRANT SELECT ON gis.wp_diag_export TO mapserver;



--------------------------------------------------------------------------------
-- Manual tasks
--------------------------------------------------------------------------------

SET FEEDBACK OFF
SET TIMING OFF
EXECUTE DBMS_OUTPUT.PUT_LINE(CHR(10) || CHR(10) || '********************************************************************************');
EXECUTE DBMS_OUTPUT.PUT_LINE('View source code for manual follow-up tasks');
EXECUTE DBMS_OUTPUT.PUT_LINE('********************************************************************************');
SET FEEDBACK ON
SET TIMING ON



-- --------------------
-- -- Create lines from old > new shapes, for shapes that have moved
-- --
-- -- Also:
-- --	o Append WP_DIAG columns to business table, to facilitate finding
-- --	  attributes of interest, especially for users without thick client
-- --	  access / skills
-- --
-- --	o Grant read to MAPSERVER
-- --
-- --	o Add relates (in existing ArcGIS Pro project) to old and new layers
-- --------------------


-- #
-- # Create feature class
-- #

-- arcpy.management.XYToLine(
	-- r'C:\Users\m_mannion\AppData\Roaming\ESRI\Desktop10.6\ArcCatalog\orcl$gis.sde\gis.wp_diag_xytoline'
	-- ,r'C:\Users\m_mannion\AppData\Roaming\ESRI\Desktop10.6\ArcCatalog\orcl$gis.sde\gis.wp_diag_move'
	-- ,'x_old'
	-- ,'y_old'
	-- ,'x_new'
	-- ,'y_new'
	-- ,'GEODESIC'
	-- ,'row_id'
	-- ,arcpy.SpatialReference(26916)
-- )



-- #
-- # Append additional attribute columns: Python
-- #
-- # *** DO NOT USE ***
-- #
-- # JoinField runs indefinitely (at least > 8 hours). Retaining this code for
-- # reference. Use SQL implementation below, instead.
-- #

-- # arcpy.management.JoinField(
-- #	r'C:\Users\m_mannion\AppData\Roaming\ESRI\Desktop10.6\ArcCatalog\orcl$gis.sde\gis.wp_diag_move'
-- #	,'row_id'
-- #	,r'C:\Users\m_mannion\AppData\Roaming\ESRI\Desktop10.6\ArcCatalog\orcl$gis.sde\gis.wp_diag_export'
-- #	,'row_id'
-- # )


-- --
-- -- Append additional attribute columns
-- --


-- -- Drop extraneous columns from XYToLine

-- ALTER TABLE gis.wp_diag_move
-- DROP (
	-- x_old
	-- ,y_old
	-- ,x_new
	-- ,y_new
-- )
-- ;


-- -- Add new columns

-- ALTER TABLE gis.wp_diag_move
-- ADD (
	-- permit_number			NVARCHAR2(50)
	-- ,legacy_permit_number		NVARCHAR2(35)
	-- ,related_permit_1		NVARCHAR2(50)
	-- ,related_permit_2		NVARCHAR2(50)
	-- ,job_type			NVARCHAR2(100)
	-- ,status				NVARCHAR2(200)
	-- ,official_id			NUMBER(38)
	-- ,issue_date			TIMESTAMP(6)
	-- ,expiration_date		TIMESTAMP(6)
	-- ,completion_date		TIMESTAMP(6)
	-- ,exemption			NVARCHAR2(7)
	-- ,owner_first			NVARCHAR2(30)
	-- ,owner_last			NVARCHAR2(30)
	-- ,well_use			NVARCHAR2(100)
	-- ,diameter			NUMBER(38,8)
	-- ,appl_well_depth		NUMBER(38,8)
	-- ,appl_casing_depth		NUMBER(38,8)
	-- ,wcr_well_depth			NUMBER(38,8)
	-- ,wcr_casing_depth		NUMBER(38,8)
	-- ,open_hole_from			NUMBER(38,8)
	-- ,open_hole_to			NUMBER(38,8)
	-- ,screen_from			NUMBER(38,8)
	-- ,screen_to			NUMBER(38,8)
	-- ,well_street			NVARCHAR2(60)
	-- ,well_street_2			NVARCHAR2(50)
	-- ,well_city			NVARCHAR2(30)
	-- ,well_county			NVARCHAR2(20)
	-- ,parcel_id			NVARCHAR2(50)
	-- ,latitude			NUMBER(38,8)
	-- ,longitude			NUMBER(38,8)
	-- ,township			NVARCHAR2(3)
	-- ,range				NVARCHAR2(3)
	-- ,section			NUMBER(5)
	-- ,cu_permit			NVARCHAR2(50)
	-- ,fluwid				NVARCHAR2(50)
	-- ,location_method		NVARCHAR2(16)
	-- ,contractor_license		NUMBER(38)
	-- ,contractor_name		NVARCHAR2(70)
	-- ,wrca				NVARCHAR2(7)
	-- ,arc				NVARCHAR2(7)
	-- ,grout_line			NVARCHAR2(100)
	-- ,construction_method		NVARCHAR2(100)
	-- ,w62_524			NVARCHAR2(7)
	-- ,stn_id				NUMBER(38)
	-- ,diag_longitude			NUMBER(38,8)
	-- ,diag_latitude			NUMBER(38,8)
	-- ,diag_longitude_old		NUMBER(38,8)
	-- ,diag_latitude_old		NUMBER(38,8)
	-- ,diag_longitude_salvage		NUMBER(38,8)
	-- ,diag_latitude_salvage		NUMBER(38,8)
	-- ,diag_raw_longitude		NUMBER(38,8)
	-- ,diag_raw_latitude		NUMBER(38,8)
	-- ,diag_raw_longitude_old		NUMBER(38,8)
	-- ,diag_raw_latitude_old		NUMBER(38,8)
	-- ,diag_coord_code		NVARCHAR2(32)
	-- ,diag_coord_code_old		NVARCHAR2(32)
	-- ,diag_coord_code_salvage	NVARCHAR2(32)
	-- ,diag_status_shape		NVARCHAR2(32)
	-- ,diag_status_shape_old		NVARCHAR2(32)
	-- ,diag_status_shape_salvage	NVARCHAR2(32)
	-- ,diag_status_ll			NVARCHAR2(32)
	-- ,diag_status_ll_old		NVARCHAR2(32)
	-- ,diag_status_longitude		NVARCHAR2(32)
	-- ,diag_status_latitude		NVARCHAR2(32)
	-- ,diag_status_longitude_old	NVARCHAR2(32)
	-- ,diag_status_latitude_old	NVARCHAR2(32)
	-- ,diag_status_coord_code		NVARCHAR2(32)
	-- ,diag_status_coord_code_old	NVARCHAR2(32)
	-- ,diag_status_coord_code_salvage	NVARCHAR2(32)
	-- ,diag_status_move		NVARCHAR2(32)
	-- ,diag_move_distance		NUMBER(38,8)
	-- ,diag_move_bearing		NUMBER(38)
-- )
-- ;


-- -- Populate new columns

-- UPDATE gis.wp_diag_move
-- SET (
	-- permit_number
	-- ,legacy_permit_number
	-- ,related_permit_1
	-- ,related_permit_2
	-- ,job_type
	-- ,status
	-- ,official_id
	-- ,issue_date
	-- ,expiration_date
	-- ,completion_date
	-- ,exemption
	-- ,owner_first
	-- ,owner_last
	-- ,well_use
	-- ,diameter
	-- ,appl_well_depth
	-- ,appl_casing_depth
	-- ,wcr_well_depth
	-- ,wcr_casing_depth
	-- ,open_hole_from
	-- ,open_hole_to
	-- ,screen_from
	-- ,screen_to
	-- ,well_street
	-- ,well_street_2
	-- ,well_city
	-- ,well_county
	-- ,parcel_id
	-- ,latitude
	-- ,longitude
	-- ,township
	-- ,range
	-- ,section
	-- ,cu_permit
	-- ,fluwid
	-- ,location_method
	-- ,contractor_license
	-- ,contractor_name
	-- ,wrca
	-- ,arc
	-- ,grout_line
	-- ,construction_method
	-- ,w62_524
	-- ,stn_id
	-- ,diag_longitude
	-- ,diag_latitude
	-- ,diag_longitude_old
	-- ,diag_latitude_old
	-- ,diag_longitude_salvage
	-- ,diag_latitude_salvage
	-- ,diag_raw_longitude
	-- ,diag_raw_latitude
	-- ,diag_raw_longitude_old
	-- ,diag_raw_latitude_old
	-- ,diag_coord_code
	-- ,diag_coord_code_old
	-- ,diag_coord_code_salvage
	-- ,diag_status_shape
	-- ,diag_status_shape_old
	-- ,diag_status_shape_salvage
	-- ,diag_status_ll
	-- ,diag_status_ll_old
	-- ,diag_status_longitude
	-- ,diag_status_latitude
	-- ,diag_status_longitude_old
	-- ,diag_status_latitude_old
	-- ,diag_status_coord_code
	-- ,diag_status_coord_code_old
	-- ,diag_status_coord_code_salvage
	-- ,diag_status_move
	-- ,diag_move_distance
	-- ,diag_move_bearing
-- ) = (
	-- SELECT
		-- permit_number
		-- ,legacy_permit_number
		-- ,related_permit_1
		-- ,related_permit_2
		-- ,job_type
		-- ,status
		-- ,official_id
		-- ,issue_date
		-- ,expiration_date
		-- ,completion_date
		-- ,exemption
		-- ,owner_first
		-- ,owner_last
		-- ,well_use
		-- ,diameter
		-- ,appl_well_depth
		-- ,appl_casing_depth
		-- ,wcr_well_depth
		-- ,wcr_casing_depth
		-- ,open_hole_from
		-- ,open_hole_to
		-- ,screen_from
		-- ,screen_to
		-- ,well_street
		-- ,well_street_2
		-- ,well_city
		-- ,well_county
		-- ,parcel_id
		-- ,latitude
		-- ,longitude
		-- ,township
		-- ,range
		-- ,section
		-- ,cu_permit
		-- ,fluwid
		-- ,location_method
		-- ,contractor_license
		-- ,contractor_name
		-- ,wrca
		-- ,arc
		-- ,grout_line
		-- ,construction_method
		-- ,w62_524
		-- ,stn_id
		-- ,diag_longitude
		-- ,diag_latitude
		-- ,diag_longitude_old
		-- ,diag_latitude_old
		-- ,diag_longitude_salvage
		-- ,diag_latitude_salvage
		-- ,diag_raw_longitude
		-- ,diag_raw_latitude
		-- ,diag_raw_longitude_old
		-- ,diag_raw_latitude_old
		-- ,diag_coord_code
		-- ,diag_coord_code_old
		-- ,diag_coord_code_salvage
		-- ,diag_status_shape
		-- ,diag_status_shape_old
		-- ,diag_status_shape_salvage
		-- ,diag_status_ll
		-- ,diag_status_ll_old
		-- ,diag_status_longitude
		-- ,diag_status_latitude
		-- ,diag_status_longitude_old
		-- ,diag_status_latitude_old
		-- ,diag_status_coord_code
		-- ,diag_status_coord_code_old
		-- ,diag_status_coord_code_salvage
		-- ,diag_status_move
		-- ,diag_move_distance
		-- ,diag_move_bearing
	-- FROM wp_diag
	-- WHERE
		-- wp_diag_move.row_id = wp_diag.row_id
-- )
-- ;


-- COMMIT;


-- #
-- # Assign privileges
-- #

-- arcpy.management.ChangePrivileges(
	-- r'C:\Users\m_mannion\AppData\Roaming\ESRI\Desktop10.6\ArcCatalog\orcl$gis.sde\gis.wp_diag_move'
	-- ,'mapserver'
	-- ,'GRANT'
	-- ,'AS_IS'
-- )



-- #
-- # Create ArcGIS Pro relates
-- #

-- arcpy.management.AddRelate(
	-- 'wp_diag_move'
	-- ,'row_id'
	-- ,'wp_diag_old'
	-- ,'row_id'
	-- ,'Old'
	-- ,'ONE_TO_ONE'
-- )


-- arcpy.management.AddRelate(
	-- 'wp_diag_move'
	-- ,'row_id'
	-- ,'wp_diag_new'
	-- ,'row_id'
	-- ,'New'
	-- ,'ONE_TO_ONE'
-- )



SELECT SYSDATE FROM dual;

--------------------------------------------------------------------------------
-- END
--------------------------------------------------------------------------------
