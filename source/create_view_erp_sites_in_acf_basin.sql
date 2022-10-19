CREATE OR REPLACE VIEW gis.basin_sites
AS
SELECT
	des.shape
	,des.objectid
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
	,des.party_role
	,des.party_company_name
	,des.party_first_name
	,des.party_last_name
	,des.expiration_date
	,des.issue_date
	,des.legacy_permit_number
	,sde.st_x(des.shape) longitude
	,sde.st_y(des.shape) latitude
FROM
	gis.databases_erp_site des
	,gis.acf_basin ab
WHERE
	sde.st_intersects(
		des.shape
		,ab.shape
	) = 1
	AND des.rule_description NOT IN (
		'ERP Permit Determination/Exemption'
		,'Forestry Authorization'
	)
;

