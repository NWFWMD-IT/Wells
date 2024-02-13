################################################################################
# Name:
#	create_feature_classes_system_integration.py
#
# Purpose:
#	Create feature class for integration with nonspatial NWFWMD business
#	systems
#
# Environment:
#	ArcGIS 10.6.1
#	Python 2.7.14
#
# Notes:
#	This script creates a new, empty copy of feature classes in the GIS
#	schema that are used for storing spatially-enabled copies of information
#	from other business systems containing numeric longitude/latitude columns.
#	The feature classes will be populated and maintained by Oracle stored
#	procedures that harvest coordinate and attribute information from the
#	systems of record.
#
# History:
#	20140919 MCM Created
#	20150126 MCM Added GIS.DATABASES_ORPHAN_WELLS
#	20150219 MCM Moved feature class creation out of main body and into
#	               functions to allow easier commenting/uncommenting in
#	               main when recreating a subset of feature classes
#	             Added LOC_METHOD columns to:
#	               DATABASES_ERP
#	               DATABASES_ORPHAN_WELLS
#	               DATABASES_WELL_INVENTORY
#	               DATABASES_WUP_SURFACE
#	               DATABASES_WUP_WELLS
#	             Changed data type of GIS.DATABASES_WELL_PERMITS.LOC_METHOD
#	               from LONG to TEXT,30 to match LOC_METHOD implementation
#	               for other feature classes
#	20150601 MCM Updated for NWPROD data sources
#	20150601 MCM Updated for NWPROD data sources
#	             For tables with NWPROD sources, changed LONG columns to
#	               FLOAT to avoid integer overflow issues
#	20150707 MCM Updated all FLOAT columns from NWPROD to DOUBLE to clarify
#	               semantics; both physically stored as NUMBER(38,8), and
#	               both reported as DOUBLE after creation
#	             Removed precision/scale for numeric columns derived from
#	               NWPROD
#	20150909 MCM Added consolidated DATABASES_ERP_SITE / DATABASES_STATION
#	               feature classes
#	20151013 MCM Added two feature classes that should not have been
#	               removed during prior cleanup:
#	                 DATABASES_WELL_INVENTORY
#	                 DATABASES_WELL_PERMITS
#	             Reverted temporary feature class names with _SJ suffixes
#	               to original names
#	             Clarified WUP-related variable names
#	20151028 MCM For DATABASES_ERP_SITE (per NWFWMDDI-38):
#	               Added PARTY_ROLE column
#	               Renamed 'APPLICANT_%' columns to 'PARTY_%'
#	20151115 MCM Added DATABASES_ERP_SITE_<subset> feature classes (NWFWMDDI-40)
#	             Renamed DATABASES_STATION to DATABASES_REG_STATION (NWFWMDDI-39)
#	20160104 MCM Added columns to DATABASES_WELL_PERMITS (NWFWMDDI-41)
#	20160121 MCM Added columns to DATABASES_ORPHAN_WELLS (NWFWMDDI-42)
#	20160630 MCM Added columns to DATABASES_ERP% tables (NWFWMDDI-43)
#	20160803 MCM Added column to DATABASES_WELL_PERMITS (NWFWMDDI-44)
#	20160829 MCM Added columns to DATABASES_WELL_PERMITS (NWFWMDDI-45)
#	             Updated remaining FLOAT columns to DOUBLE
#	             Removed precision/scale from DOUBLE columns
#	20161016 MCM Added ITEM_NUMBER columns to GIS.DATABASES_ERP_SITE% tables
#	               (NWFWMDDI-46)
#	20170106 MCM Added REVIEW_DATE columns to GIS.DATABASES_ERP_SITE% tables
#	               (NWFWMDDI-48)
#	20170130 MCM Removed create_databases_orphan_wells function (NWFWMDDI-49)
#	20170330 MCM Added attribute indexes to support groundwater web app
#	               (NWFWMDDI-50)
#	20170930 MCM Update DATABASES_WELL_PERMITS to accommodate new remote
#	               SJRWMD data sources / structures, and additional
#	               miscellaneous changes (NWFWMDDI-71)
#	             Added proper __main__ test for executable statements
#	20190830 MCM Overhauled GIS.DATABASES_WELL_PERMITS
#	20190831 MCM Standardized LOCATION_METHOD column width to 16
#	               (NWFWMDDI-89)
#	20190905 MCM Expanded DATABASES_WELL_PERMITS.RELATED_PERMIT to
#	               RELATED_PERMIT_1 and RELATED_PERMIT_2 (NWFWMDDI-90)
#
# To do:
#	Evaluate changing other/all LONG to DOUBLE (without P,S?) to avoid
#	overflow
#
# Copyright 2003-2023. Mannion Geosystems, LLC. http://www.manniongeo.com
################################################################################


#
# Modules
#

import arcpy
import os



#
# Constants
#

OUTPUT_GEODATABASE = r'Database Connections\orcl$gis.sde'
UTM_16N_NAD83 = arcpy.SpatialReference(26916) # NAD_1983_UTM_Zone_16N

# Feature class names
FC_NAME_ERP = 'GIS.DATABASES_ERP'
FC_NAME_ERP_SITE = 'GIS.DATABASES_ERP_SITE'
FC_NAME_ERP_SITE_40A_4 = 'GIS.DATABASES_ERP_SITE_40A_4'
FC_NAME_ERP_SITE_40A_44 = 'GIS.DATABASES_ERP_SITE_40A_44'
FC_NAME_ERP_SITE_62_330 = 'GIS.DATABASES_ERP_SITE_62_330'
FC_NAME_ERP_SITE_FORESTRY = 'GIS.DATABASES_ERP_SITE_FORESTRY'
FC_NAME_MSSW = 'GIS.DATABASES_MSSW'
FC_NAME_REG_STATION = 'GIS.DATABASES_REG_STATION'
FC_NAME_WI = 'GIS.DATABASES_WELL_INVENTORY'
FC_NAME_WPS = 'GIS.DATABASES_WELL_PERMITS'
FC_NAME_WUP_PERMITTED = 'GIS.DATABASES_WUP_PERMITTED'
FC_NAME_WUP_SURFACE = 'GIS.DATABASES_WUP_SURFACE'
FC_NAME_WUP_WELLS = 'GIS.DATABASES_WUP_WELLS'



################################################################################
# Utility functions
################################################################################

def add_fields (
	table
	,fields_spec
):

	for field_spec in fields_spec:

		arcpy.AddMessage('\t\tAdding {field_name}'.format(field_name = field_spec[0]))

		arcpy.AddField_management(
			in_table = table
			,field_name = field_spec[0]
			,field_type = field_spec[1]
			,field_precision = field_spec[2]
			,field_scale = field_spec[3]
			,field_length = field_spec[4]
			,field_alias = field_spec[5]
			,field_is_nullable = field_spec[6]
			,field_is_required = field_spec[7]
			,field_domain = field_spec[8]
		)



################################################################################
# Feature class creation functions
################################################################################


#
# GIS.DATABASES_ERP
#

def create_databases_erp():

	arcpy.AddMessage('\n\nCreating feature class {fc_name}'.format(fc_name = FC_NAME_ERP))

	fc_erp = os.path.join(
		OUTPUT_GEODATABASE
		,FC_NAME_ERP
	)


	arcpy.CreateFeatureclass_management(
		out_path = OUTPUT_GEODATABASE
		,out_name = FC_NAME_ERP
		,geometry_type = 'POINT'
		,spatial_reference = UTM_16N_NAD83
	)


	arcpy.AddMessage('\tAdding fields')

	fields_spec = [
		#name				,type		,precision	,scale	,length		,alias	,nullable	,required	,domain
		('application_number'		,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('permit_number'		,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('legacy_permit_number'	,'TEXT'		,''		,''	,35		,''	,True		,''		,'')
		,('applicant_first_name'	,'TEXT'		,''		,''	,30		,''	,True		,''		,'')
		,('applicant_last_name'		,'TEXT'		,''		,''	,30		,''	,True		,''		,'')
		,('applicant_company_name'	,'TEXT'		,''		,''	,150		,''	,True		,''		,'')
		,('project_name'		,'TEXT'		,''		,''	,200		,''	,True		,''		,'')
		,('project_address'		,'TEXT'		,''		,''	,1000		,''	,True		,''		,'')
		,('issue_date'			,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('expiration_date'		,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('rule_type'			,'TEXT'		,''		,''	,17		,''	,True		,''		,'')
	]


	add_fields(
		table = fc_erp
		,fields_spec = fields_spec
	)


	arcpy.AddMessage('\tGranting privileges')

	arcpy.ChangePrivileges_management(
		in_dataset = fc_erp
		,user = 'GIS_READ'
		,View = 'GRANT'
		,Edit = 'AS_IS'
	)



#
# GIS.DATABASES_ERP_SITE
#

def create_databases_erp_site():

	arcpy.AddMessage('\n\nCreating feature class {fc_name}'.format(fc_name = FC_NAME_ERP_SITE))

	fc_erp_site = os.path.join(
		OUTPUT_GEODATABASE
		,FC_NAME_ERP_SITE
	)


	arcpy.CreateFeatureclass_management(
		out_path = OUTPUT_GEODATABASE
		,out_name = FC_NAME_ERP_SITE
		,geometry_type = 'POINT'
		,spatial_reference = UTM_16N_NAD83
	)


	arcpy.AddMessage('\tAdding fields')

	fields_spec = [
		#name				,type		,precision	,scale	,length		,alias	,nullable	,required	,domain
		('site_id'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('permit_number'		,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('project_number'		,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('permit_type'			,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('county_fips'			,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('official_permit_number'	,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('sequence_number'		,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('application_status'		,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('rule_code'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('rule_description'		,'TEXT'		,''		,''	,200		,''	,True		,''		,'')
		,('project_name'		,'TEXT'		,''		,''	,200		,''	,True		,''		,'')
		,('project_county'		,'TEXT'		,''		,''	,20		,''	,True		,''		,'')
		,('site_location'		,'TEXT'		,''		,''	,1000		,''	,True		,''		,'')
		,('party_role'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('party_company_name'		,'TEXT'		,''		,''	,150		,''	,True		,''		,'')
		,('party_first_name'		,'TEXT'		,''		,''	,30		,''	,True		,''		,'')
		,('party_last_name'		,'TEXT'		,''		,''	,30		,''	,True		,''		,'')
		,('expiration_date'		,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('issue_date'			,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('review_date'			,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('legacy_permit_number'	,'TEXT'		,''		,''	,35		,''	,True		,''		,'')
		,('item_number'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('item_type'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('item_stage'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
	]


	add_fields(
		table = fc_erp_site
		,fields_spec = fields_spec
	)


	arcpy.AddMessage('\tGranting privileges')

	arcpy.ChangePrivileges_management(
		in_dataset = fc_erp_site
		,user = 'GIS_READ'
		,View = 'GRANT'
		,Edit = 'AS_IS'
	)



#
# GIS.DATABASES_ERP_SITE_40A_4
#

def create_databases_erp_site_40a_4():

	arcpy.AddMessage('\n\nCreating feature class {fc_name}'.format(fc_name = FC_NAME_ERP_SITE_40A_4))

	fc_erp_site_40a_4 = os.path.join(
		OUTPUT_GEODATABASE
		,FC_NAME_ERP_SITE_40A_4
	)


	arcpy.CreateFeatureclass_management(
		out_path = OUTPUT_GEODATABASE
		,out_name = FC_NAME_ERP_SITE_40A_4
		,geometry_type = 'POINT'
		,spatial_reference = UTM_16N_NAD83
	)


	arcpy.AddMessage('\tAdding fields')

	fields_spec = [
		#name				,type		,precision	,scale	,length		,alias	,nullable	,required	,domain
		('site_id'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('permit_number'		,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('project_number'		,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('permit_type'			,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('county_fips'			,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('official_permit_number'	,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('sequence_number'		,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('application_status'		,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('rule_code'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('rule_description'		,'TEXT'		,''		,''	,200		,''	,True		,''		,'')
		,('project_name'		,'TEXT'		,''		,''	,200		,''	,True		,''		,'')
		,('project_county'		,'TEXT'		,''		,''	,20		,''	,True		,''		,'')
		,('site_location'		,'TEXT'		,''		,''	,1000		,''	,True		,''		,'')
		,('expiration_date'		,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('issue_date'			,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('review_date'			,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('legacy_permit_number'	,'TEXT'		,''		,''	,35		,''	,True		,''		,'')
		,('item_number'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('item_type'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('item_stage'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
	]


	add_fields(
		table = fc_erp_site_40a_4
		,fields_spec = fields_spec
	)


	arcpy.AddMessage('\tGranting privileges')

	arcpy.ChangePrivileges_management(
		in_dataset = fc_erp_site_40a_4
		,user = 'GIS_READ'
		,View = 'GRANT'
		,Edit = 'AS_IS'
	)



#
# GIS.DATABASES_ERP_SITE_40A_44
#

def create_databases_erp_site_40a_44():

	arcpy.AddMessage('\n\nCreating feature class {fc_name}'.format(fc_name = FC_NAME_ERP_SITE_40A_44))

	fc_erp_site_40a_44 = os.path.join(
		OUTPUT_GEODATABASE
		,FC_NAME_ERP_SITE_40A_44
	)


	arcpy.CreateFeatureclass_management(
		out_path = OUTPUT_GEODATABASE
		,out_name = FC_NAME_ERP_SITE_40A_44
		,geometry_type = 'POINT'
		,spatial_reference = UTM_16N_NAD83
	)


	arcpy.AddMessage('\tAdding fields')

	fields_spec = [
		#name				,type		,precision	,scale	,length		,alias	,nullable	,required	,domain
		('site_id'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('permit_number'		,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('project_number'		,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('permit_type'			,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('county_fips'			,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('official_permit_number'	,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('sequence_number'		,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('application_status'		,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('rule_code'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('rule_description'		,'TEXT'		,''		,''	,200		,''	,True		,''		,'')
		,('project_name'		,'TEXT'		,''		,''	,200		,''	,True		,''		,'')
		,('project_county'		,'TEXT'		,''		,''	,20		,''	,True		,''		,'')
		,('site_location'		,'TEXT'		,''		,''	,1000		,''	,True		,''		,'')
		,('expiration_date'		,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('issue_date'			,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('review_date'			,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('legacy_permit_number'	,'TEXT'		,''		,''	,35		,''	,True		,''		,'')
		,('item_number'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('item_type'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('item_stage'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
	]


	add_fields(
		table = fc_erp_site_40a_44
		,fields_spec = fields_spec
	)


	arcpy.AddMessage('\tGranting privileges')

	arcpy.ChangePrivileges_management(
		in_dataset = fc_erp_site_40a_44
		,user = 'GIS_READ'
		,View = 'GRANT'
		,Edit = 'AS_IS'
	)



#
# GIS.DATABASES_ERP_SITE_62_330
#

def create_databases_erp_site_62_330():

	arcpy.AddMessage('\n\nCreating feature class {fc_name}'.format(fc_name = FC_NAME_ERP_SITE_62_330))

	fc_erp_site_62_330 = os.path.join(
		OUTPUT_GEODATABASE
		,FC_NAME_ERP_SITE_62_330
	)


	arcpy.CreateFeatureclass_management(
		out_path = OUTPUT_GEODATABASE
		,out_name = FC_NAME_ERP_SITE_62_330
		,geometry_type = 'POINT'
		,spatial_reference = UTM_16N_NAD83
	)


	arcpy.AddMessage('\tAdding fields')

	fields_spec = [
		#name				,type		,precision	,scale	,length		,alias	,nullable	,required	,domain
		('site_id'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('permit_number'		,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('project_number'		,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('permit_type'			,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('county_fips'			,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('official_permit_number'	,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('sequence_number'		,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('application_status'		,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('rule_code'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('rule_description'		,'TEXT'		,''		,''	,200		,''	,True		,''		,'')
		,('project_name'		,'TEXT'		,''		,''	,200		,''	,True		,''		,'')
		,('project_county'		,'TEXT'		,''		,''	,20		,''	,True		,''		,'')
		,('site_location'		,'TEXT'		,''		,''	,1000		,''	,True		,''		,'')
		,('expiration_date'		,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('issue_date'			,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('review_date'			,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('legacy_permit_number'	,'TEXT'		,''		,''	,35		,''	,True		,''		,'')
		,('item_number'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('item_type'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('item_stage'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
	]


	add_fields(
		table = fc_erp_site_62_330
		,fields_spec = fields_spec
	)


	arcpy.AddMessage('\tGranting privileges')

	arcpy.ChangePrivileges_management(
		in_dataset = fc_erp_site_62_330
		,user = 'GIS_READ'
		,View = 'GRANT'
		,Edit = 'AS_IS'
	)



#
# GIS.DATABASES_ERP_SITE_FORESTRY
#

def create_databases_erp_site_forestry():

	arcpy.AddMessage('\n\nCreating feature class {fc_name}'.format(fc_name = FC_NAME_ERP_SITE_FORESTRY))

	fc_erp_site_forestry = os.path.join(
		OUTPUT_GEODATABASE
		,FC_NAME_ERP_SITE_FORESTRY
	)


	arcpy.CreateFeatureclass_management(
		out_path = OUTPUT_GEODATABASE
		,out_name = FC_NAME_ERP_SITE_FORESTRY
		,geometry_type = 'POINT'
		,spatial_reference = UTM_16N_NAD83
	)


	arcpy.AddMessage('\tAdding fields')

	fields_spec = [
		#name				,type		,precision	,scale	,length		,alias	,nullable	,required	,domain
		('site_id'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('permit_number'		,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('project_number'		,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('permit_type'			,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('county_fips'			,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('official_permit_number'	,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('sequence_number'		,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('application_status'		,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('rule_code'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('rule_description'		,'TEXT'		,''		,''	,200		,''	,True		,''		,'')
		,('project_name'		,'TEXT'		,''		,''	,200		,''	,True		,''		,'')
		,('project_county'		,'TEXT'		,''		,''	,20		,''	,True		,''		,'')
		,('site_location'		,'TEXT'		,''		,''	,1000		,''	,True		,''		,'')
		,('expiration_date'		,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('issue_date'			,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('review_date'			,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('legacy_permit_number'	,'TEXT'		,''		,''	,35		,''	,True		,''		,'')
		,('item_number'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('item_type'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('item_stage'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
	]


	add_fields(
		table = fc_erp_site_forestry
		,fields_spec = fields_spec
	)


	arcpy.AddMessage('\tGranting privileges')

	arcpy.ChangePrivileges_management(
		in_dataset = fc_erp_site_forestry
		,user = 'GIS_READ'
		,View = 'GRANT'
		,Edit = 'AS_IS'
	)



#
# GIS.DATABASES_MSSW
#

def create_databases_mssw():

	arcpy.AddMessage('\n\nCreating feature class {fc_name}'.format(fc_name = FC_NAME_MSSW))

	fc_mssw = os.path.join(
		OUTPUT_GEODATABASE
		,FC_NAME_MSSW
	)


	arcpy.CreateFeatureclass_management(
		out_path = OUTPUT_GEODATABASE
		,out_name = FC_NAME_MSSW
		,geometry_type = 'POINT'
		,spatial_reference = UTM_16N_NAD83
	)


	arcpy.AddMessage('\tAdding fields')

	fields_spec = [
		#name				,type		,precision	,scale	,length		,alias	,nullable	,required	,domain
		('permit_number'		,'TEXT'		,''		,''	,35		,''	,True		,''		,'')
		,('appl_first_name'		,'TEXT'		,''		,''	,30		,''	,True		,''		,'')
		,('appl_last_name'		,'TEXT'		,''		,''	,30		,''	,True		,''		,'')
		,('applicant_company_name'	,'TEXT'		,''		,''	,150		,''	,True		,''		,'')
		,('project_name'		,'TEXT'		,''		,''	,200		,''	,True		,''		,'')
		,('appl_received'		,'DATE'		,''		,''	,''		,''	,True		,''		,'')
	]


	add_fields(
		table = fc_mssw
		,fields_spec = fields_spec
	)


	arcpy.AddMessage('\tGranting privileges')

	arcpy.ChangePrivileges_management(
		in_dataset = fc_mssw
		,user = 'GIS_READ'
		,View = 'GRANT'
		,Edit = 'AS_IS'
	)



#
# GIS.DATABASES_REG_STATION
#

def create_databases_reg_station():

	arcpy.AddMessage('\n\nCreating feature class {fc_name}'.format(fc_name = FC_NAME_REG_STATION))

	fc_reg_station = os.path.join(
		OUTPUT_GEODATABASE
		,FC_NAME_REG_STATION
	)


	arcpy.CreateFeatureclass_management(
		out_path = OUTPUT_GEODATABASE
		,out_name = FC_NAME_REG_STATION
		,geometry_type = 'POINT'
		,spatial_reference = UTM_16N_NAD83
	)


	arcpy.AddMessage('\tAdding fields')

	fields_spec = [
		#name				,type		,precision	,scale	,length		,alias	,nullable	,required	,domain
		('station_id'			,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('project_number'		,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('permit_type'			,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('county_fips'			,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('official_permit_number'	,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('sequence_number'		,'TEXT'		,''		,''	,8		,''	,True		,''		,'')
		,('fluwid'			,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('station_type'		,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('monitoring_well_type'	,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('station_name'		,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('station_status'		,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('water_source_type'		,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('water_source_name'		,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('meter_type'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('diameter'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('casing_depth'		,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('well_depth'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('pump_rate'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('pumping_report'		,'TEXT'		,''		,''	,7		,''	,True		,''		,'')
		,('wq_mi'			,'TEXT'		,''		,''	,7		,''	,True		,''		,'')
		,('wq_lp'			,'TEXT'		,''		,''	,7		,''	,True		,''		,'')
		,('wl_gw'			,'TEXT'		,''		,''	,7		,''	,True		,''		,'')
		,('station_county'		,'TEXT'		,''		,''	,20		,''	,True		,''		,'')
		,('station_location'		,'TEXT'		,''		,''	,1000		,''	,True		,''		,'')
		,('location_method'		,'TEXT'		,''		,''	,16		,''	,True		,''		,'')
		,('project_primary_use'		,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('project_secondary_use'	,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('water_use_level_1'		,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('water_use_level_2'		,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('water_use_level_3'		,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('water_use_level_4'		,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('station_allocation_gpd'	,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('project_allocation_gpd'	,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('project_allocation_monthly'	,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('application_status'		,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('expiration_date'		,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('owner_company_name'		,'TEXT'		,''		,''	,150		,''	,True		,''		,'')
		,('owner_first_name'		,'TEXT'		,''		,''	,30		,''	,True		,''		,'')
		,('owner_last_name'		,'TEXT'		,''		,''	,30		,''	,True		,''		,'')
		,('legacy_apnum'		,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('legacy_permit_number'	,'TEXT'		,''		,''	,35		,''	,True		,''		,'')
		,('nwf_id'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('wps_permit'			,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
	]


	add_fields(
		table = fc_reg_station
		,fields_spec = fields_spec
	)


	arcpy.AddMessage('\tCreating indexes')

	arcpy.AddIndex_management(
		fc_reg_station
		,'FLUWID'
		,'{table_name}__I1'.format(table_name = FC_NAME_REG_STATION)
	)

	arcpy.AddIndex_management(
		fc_reg_station
		,'LEGACY_PERMIT_NUMBER'
		,'{table_name}__I2'.format(table_name = FC_NAME_REG_STATION)
	)


	arcpy.AddMessage('\tGranting privileges')

	arcpy.ChangePrivileges_management(
		in_dataset = fc_reg_station
		,user = 'GIS_READ'
		,View = 'GRANT'
		,Edit = 'AS_IS'
	)



#
# GIS.DATABASES_WELL_INVENTORY
#

def create_databases_well_inventory():

	arcpy.AddMessage('\n\nCreating feature class {fc_name}'.format(fc_name = FC_NAME_WI))

	fc_wi = os.path.join(
		OUTPUT_GEODATABASE
		,FC_NAME_WI
	)


	arcpy.CreateFeatureclass_management(
		out_path = OUTPUT_GEODATABASE
		,out_name = FC_NAME_WI
		,geometry_type = 'POINT'
		,spatial_reference = UTM_16N_NAD83
	)


	arcpy.AddMessage('\tAdding fields')

	fields_spec = [
		#name				,type		,precision	,scale	,length		,alias	,nullable	,required	,domain
		('nwf_id'			,'LONG'		,''		,''	,''		,''	,True		,''		,'')
		,('site_id'			,'TEXT'		,''		,''	,15		,''	,True		,''		,'')
		,('site_type'			,'TEXT'		,''		,''	,1		,''	,True		,''		,'')
		,('well_name'			,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('first_name'			,'TEXT'		,''		,''	,30		,''	,True		,''		,'')
		,('last_name'			,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('well_depth'			,'LONG'		,''		,''	,''		,''	,True		,''		,'')
		,('casing_depth'		,'LONG'		,''		,''	,''		,''	,True		,''		,'')
		,('use_permit'			,'LONG'		,''		,''	,''		,''	,True		,''		,'')
		,('cps_permit'			,'TEXT'		,''		,''	,10		,''	,True		,''		,'')
		,('state_id'			,'TEXT'		,''		,''	,7		,''	,True		,''		,'')
		,('spcap'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('calc_trans'			,'LONG'		,''		,''	,''		,''	,True		,''		,'')
		,('loc_method'			,'TEXT'		,''		,''	,30		,''	,True		,''		,'')
	]


	add_fields(
		table = fc_wi
		,fields_spec = fields_spec
	)


	arcpy.AddMessage('\tCreating indexes')

	arcpy.AddIndex_management(
		fc_wi
		,'NWF_ID'
		,'{table_name}__I1'.format(table_name = FC_NAME_WI)
	)

	arcpy.AddIndex_management(
		fc_wi
		,'STATE_ID'
		,'{table_name}__I2'.format(table_name = FC_NAME_WI)
	)


	arcpy.AddMessage('\tGranting privileges')

	arcpy.ChangePrivileges_management(
		in_dataset = fc_wi
		,user = 'GIS_READ'
		,View = 'GRANT'
		,Edit = 'AS_IS'
	)



#
# GIS.DATABASES_WELL_PERMITS
#

def create_databases_well_permits():

	arcpy.AddMessage('\n\nCreating feature class {fc_name}'.format(fc_name = FC_NAME_WPS))

	fc_wps = os.path.join(
		OUTPUT_GEODATABASE
		,FC_NAME_WPS
	)


	arcpy.CreateFeatureclass_management(
		out_path = OUTPUT_GEODATABASE
		,out_name = FC_NAME_WPS
		,geometry_type = 'POINT'
		,spatial_reference = UTM_16N_NAD83
	)


	arcpy.AddMessage('\tAdding fields')

	fields_spec = [
		#name				,type		,precision	,scale	,length		,alias	,nullable	,required	,domain
		('permit_number'		,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('legacy_permit_number'	,'TEXT'		,''		,''	,35		,''	,True		,''		,'')
		,('related_permit_1'		,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('related_permit_2'		,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('job_type'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('status'			,'TEXT'		,''		,''	,200		,''	,True		,''		,'')
		,('official_id'			,'LONG'		,''		,''	,''		,''	,True		,''		,'')
		,('issue_date'			,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('expiration_date'		,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('completion_date'		,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('exemption'			,'TEXT'		,''		,''	,7		,''	,True		,''		,'')
		,('owner_first'			,'TEXT'		,''		,''	,30		,''	,True		,''		,'')
		,('owner_last'			,'TEXT'		,''		,''	,30		,''	,True		,''		,'')
		,('well_use'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('diameter'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('appl_well_depth'		,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('appl_casing_depth'		,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('wcr_well_depth'		,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('wcr_casing_depth'		,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('open_hole_from'		,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('open_hole_to'		,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('screen_from'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('screen_to'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('well_street'			,'TEXT'		,''		,''	,60		,''	,True		,''		,'')
		,('well_street_2'		,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('well_city'			,'TEXT'		,''		,''	,30		,''	,True		,''		,'')
		,('well_county'			,'TEXT'		,''		,''	,20		,''	,True		,''		,'')
		,('parcel_id'			,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('latitude'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('longitude'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('township'			,'TEXT'		,''		,''	,3		,''	,True		,''		,'')
		,('range'			,'TEXT'		,''		,''	,3		,''	,True		,''		,'')
		,('section'			,'SHORT'	,''		,''	,''		,''	,True		,''		,'')
		,('cu_permit'			,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('fluwid'			,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('location_method'		,'TEXT'		,''		,''	,16		,''	,True		,''		,'')
		,('contractor_license'		,'LONG'		,''		,''	,''		,''	,True		,''		,'')
		,('contractor_name'		,'TEXT'		,''		,''	,70		,''	,True		,''		,'')
		,('wrca'			,'TEXT'		,''		,''	,7		,''	,True		,''		,'')
		,('arc'				,'TEXT'		,''		,''	,7		,''	,True		,''		,'')
		,('grout_line'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('construction_method'		,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('w62_524'			,'TEXT'		,''		,''	,7		,''	,True		,''		,'')
		,('stn_id'			,'LONG'		,''		,''	,''		,''	,True		,''		,'')
	]


	add_fields(
		table = fc_wps
		,fields_spec = fields_spec
	)


	arcpy.AddMessage('\tCreating indexes')

	arcpy.AddIndex_management(
		fc_wps
		,'FLUWID'
		,'{table_name}__I1'.format(table_name = FC_NAME_WPS)
	)

	arcpy.AddIndex_management(
		fc_wps
		,'PERMIT_NUMBER'
		,'{table_name}__I2'.format(table_name = FC_NAME_WPS)
	)


	arcpy.AddMessage('\tGranting privileges')

	arcpy.ChangePrivileges_management(
		in_dataset = fc_wps
		,user = 'GIS_READ'
		,View = 'GRANT'
		,Edit = 'AS_IS'
	)



#
# GIS.DATABASES_WUP_PERMITTED
#

def create_databases_wup_permitted():

	arcpy.AddMessage('\n\nCreating feature class {fc_name}'.format(fc_name = FC_NAME_WUP_PERMITTED))

	fc_wup = os.path.join(
		OUTPUT_GEODATABASE
		,FC_NAME_WUP_PERMITTED
	)


	arcpy.CreateFeatureclass_management(
		out_path = OUTPUT_GEODATABASE
		,out_name = FC_NAME_WUP_PERMITTED
		,geometry_type = 'POINT'
		,spatial_reference = UTM_16N_NAD83
	)


	arcpy.AddMessage('\tAdding fields')

	fields_spec = [
		#name				,type		,precision	,scale	,length		,alias	,nullable	,required	,domain
		('permit_number'		,'LONG'		,''		,''	,''		,''	,True		,''		,'')
		,('owner_first_name'		,'TEXT'		,''		,''	,20		,''	,True		,''		,'')
		,('owner_last_name'		,'TEXT'		,''		,''	,40		,''	,True		,''		,'')
		,('project_name'		,'TEXT'		,''		,''	,80		,''	,True		,''		,'')
		,('issue_date'			,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('expiration_date'		,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('rule_type'			,'TEXT'		,''		,''	,15		,''	,True		,''		,'')
	]


	add_fields(
		table = fc_wup
		,fields_spec = fields_spec
	)


	arcpy.AddMessage('\tGranting privileges')

	arcpy.ChangePrivileges_management(
		in_dataset = fc_wup
		,user = 'GIS_READ'
		,View = 'GRANT'
		,Edit = 'AS_IS'
	)



#
# GIS.DATABASES_WUP_SURFACE
#

def create_databases_wup_surface():

	arcpy.AddMessage('\n\nCreating feature class {fc_name}'.format(fc_name = FC_NAME_WUP_SURFACE))

	fc_wup_surf = os.path.join(
		OUTPUT_GEODATABASE
		,FC_NAME_WUP_SURFACE
	)


	arcpy.CreateFeatureclass_management(
		out_path = OUTPUT_GEODATABASE
		,out_name = FC_NAME_WUP_SURFACE
		,geometry_type = 'POINT'
		,spatial_reference = UTM_16N_NAD83
	)


	arcpy.AddMessage('\tAdding fields')

	fields_spec = [
		#name				,type		,precision	,scale	,length		,alias	,nullable	,required	,domain
		('cu_apnum'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('cu_permit'			,'TEXT'		,''		,''	,35		,''	,True		,''		,'')
		,('ownerlast'			,'TEXT'		,''		,''	,30		,''	,True		,''		,'')
		,('ownerfirst'			,'TEXT'		,''		,''	,30		,''	,True		,''		,'')
		,('address'			,'TEXT'		,''		,''	,500		,''	,True		,''		,'')
		,('pmtmaxmonthly'		,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('pmtavggpd'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('primaryuse'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('other_uses'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('expire_date'			,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('swstateid'			,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('swkey'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('loc_method'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
	]


	add_fields(
		table = fc_wup_surf
		,fields_spec = fields_spec
	)


	arcpy.AddMessage('\tGranting privileges')

	arcpy.ChangePrivileges_management(
		in_dataset = fc_wup_surf
		,user = 'GIS_READ'
		,View = 'GRANT'
		,Edit = 'AS_IS'
	)



#
# GIS.DATABASES_WUP_WELLS
#

def create_databases_wup_wells():

	arcpy.AddMessage('\n\nCreating feature class {fc_name}'.format(fc_name = FC_NAME_WUP_WELLS))

	fc_wup_wells = os.path.join(
		OUTPUT_GEODATABASE
		,FC_NAME_WUP_WELLS
	)


	arcpy.CreateFeatureclass_management(
		out_path = OUTPUT_GEODATABASE
		,out_name = FC_NAME_WUP_WELLS
		,geometry_type = 'POINT'
		,spatial_reference = UTM_16N_NAD83
	)


	arcpy.AddMessage('\tAdding fields')

	fields_spec = [
		#name				,type		,precision	,scale	,length		,alias	,nullable	,required	,domain
		('cu_apnum'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('cu_permit'			,'TEXT'		,''		,''	,35		,''	,True		,''		,'')
		,('ownerlast'			,'TEXT'		,''		,''	,30		,''	,True		,''		,'')
		,('ownerfirst'			,'TEXT'		,''		,''	,30		,''	,True		,''		,'')
		,('address'			,'TEXT'		,''		,''	,500		,''	,True		,''		,'')
		,('diameter'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('pmtmaxgpd'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('pmtavggpd'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('primaryuse'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('other_uses'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
		,('expire_date'			,'DATE'		,''		,''	,''		,''	,True		,''		,'')
		,('fluwid'			,'TEXT'		,''		,''	,50		,''	,True		,''		,'')
		,('wps_permit'			,'TEXT'		,''		,''	,10		,''	,True		,''		,'')
		,('nwf_id'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('well_key'			,'DOUBLE'	,''		,''	,''		,''	,True		,''		,'')
		,('loc_method'			,'TEXT'		,''		,''	,100		,''	,True		,''		,'')
	]


	add_fields(
		table = fc_wup_wells
		,fields_spec = fields_spec
	)


	arcpy.AddMessage('\tGranting privileges')

	arcpy.ChangePrivileges_management(
		in_dataset = fc_wup_wells
		,user = 'GIS_READ'
		,View = 'GRANT'
		,Edit = 'AS_IS'
	)


################################################################################
# Main
################################################################################

if __name__ == '__main__':


	#
	# Create feature classes
	#

	# create_databases_erp()
	# create_databases_mssw()
	# create_databases_erp_site()
	# create_databases_erp_site_40a_4()
	# create_databases_erp_site_40a_44()
	# create_databases_erp_site_62_330()
	# create_databases_erp_site_forestry()
	# create_databases_reg_station()
	# create_databases_well_inventory()
	create_databases_well_permits()
	# create_databases_wup_permitted()
	# create_databases_wup_surface()
	# create_databases_wup_wells()



	#
	# Display notice to manually update feature class extents
	#
	# Automated option being investigated per Esri Support incident #01659132
	#

	arcpy.AddMessage('\n')
	arcpy.AddWarning('************************************************************')
	arcpy.AddWarning('REMINDER: Manually set feature extent to district boundary')
	arcpy.AddWarning('          for new feature classes')
	arcpy.AddWarning('REMINDER: Manually import metadata from template file geodatabase')
	arcpy.AddWarning('************************************************************')
	arcpy.AddMessage('\n')


################################################################################
# END
################################################################################

