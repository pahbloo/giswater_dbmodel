/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/

--FUNCTION CODE: 2108

CREATE OR REPLACE FUNCTION "SCHEMA_NAME".gw_fct_anl_node_duplicated(p_data json) RETURNS json AS 
$BODY$
/*EXAMPLE
SELECT gw_fct_anl_node_duplicated($${"client":{"device":4, "infoType":1, "lang":"ES"},
"form":{},"feature":{"tableName":"v_edit_node", "featureType":"NODE", "id":[]}, 
"data":{"filterFields":{}, "pageInfo":{}, "selectionMode":"wholeSelection",
"parameters":{"nodeTolerance":"3.0"}}}$$)::text

-- fid: 106

*/

DECLARE
    
v_id json;
v_selectionmode text;
v_nodetolerance float;
v_worklayer text;
v_result json;
v_result_info json;
v_result_point json;
v_array text;
v_version text;
v_error_context text;
v_count integer;

BEGIN

	-- Search path
	SET search_path = "SCHEMA_NAME", public;

	-- select version
	SELECT giswater INTO v_version FROM sys_version order by 1 desc limit 1;
	
	-- getting input data 	
	v_id :=  ((p_data ->>'feature')::json->>'id')::json;
	v_worklayer := ((p_data ->>'feature')::json->>'tableName')::text;
	v_selectionmode :=  ((p_data ->>'data')::json->>'selectionMode')::text;
	v_nodetolerance := ((p_data ->>'data')::json->>'parameters')::json->>'nodeTolerance';

	select string_agg(quote_literal(a),',') into v_array from json_array_elements_text(v_id) a;

	-- Reset values
	DELETE FROM anl_node WHERE cur_user="current_user"() AND fid=106;
	DELETE FROM audit_check_data WHERE cur_user="current_user"() AND fid=106;	
	
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (106, null, 4, concat('NODE DUPLICATED ANALYSIS'));
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (106, null, 4, '-------------------------------------------------------------');

	-- Computing process
	IF v_selectionmode = 'previousSelection' THEN
		EXECUTE 'INSERT INTO anl_node (node_id, nodecat_id, state, node_id_aux, nodecat_id_aux, state_aux, expl_id, fid, the_geom)
				SELECT * FROM (
				SELECT DISTINCT t1.node_id, t1.nodecat_id, t1.state as state1, t2.node_id, t2.nodecat_id, t2.state as state2, t1.expl_id, 106, t1.the_geom
				FROM '||v_worklayer||' AS t1 JOIN '||v_worklayer||' AS t2 ON ST_Dwithin(t1.the_geom, t2.the_geom,('||v_nodetolerance||')) 
				WHERE t1.node_id != t2.node_id AND t1.node_id IN ('||v_array||') ORDER BY t1.node_id ) a where a.state1 > 0 AND a.state2 > 0';
	ELSE
		EXECUTE 'INSERT INTO anl_node (node_id, nodecat_id, state, node_id_aux, nodecat_id_aux, state_aux, expl_id, fid, the_geom)
				SELECT * FROM (
				SELECT DISTINCT t1.node_id, t1.nodecat_id, t1.state as state1, t2.node_id, t2.nodecat_id, t2.state as state2, t1.expl_id, 106, t1.the_geom
				FROM '||v_worklayer||' AS t1 JOIN '||v_worklayer||' AS t2 ON ST_Dwithin(t1.the_geom, t2.the_geom,('||v_nodetolerance||')) 
				WHERE t1.node_id != t2.node_id ORDER BY t1.node_id ) a where a.state1 > 0 AND a.state2 > 0';
	END IF;

	-- set selector
	DELETE FROM selector_audit WHERE fid=106 AND cur_user=current_user;
	INSERT INTO selector_audit (fid,cur_user) VALUES (106, current_user);

	-- get results
	--points
	v_result = null;
	SELECT jsonb_agg(features.feature) INTO v_result
	FROM (
  	SELECT jsonb_build_object(
     'type',       'Feature',
    'geometry',   ST_AsGeoJSON(the_geom)::jsonb,
    'properties', to_jsonb(row) - 'the_geom'
  	) AS feature
  	FROM (SELECT id, node_id, nodecat_id, state, node_id_aux,nodecat_id_aux, state_aux, expl_id, descript, fid, the_geom
  	FROM  anl_node WHERE cur_user="current_user"() AND fid=106) row) features;

	v_result := COALESCE(v_result, '{}'); 
	v_result_point = concat ('{"geometryType":"Point", "features":',v_result, '}'); 

	SELECT count(*)/2 INTO v_count FROM anl_node WHERE cur_user="current_user"() AND fid=106;

	IF v_count = 0 THEN
		INSERT INTO audit_check_data(fid,  error_message, fcount)
		VALUES (106,  'There are no duplicated nodes.', v_count);
	ELSE
		INSERT INTO audit_check_data(fid,  error_message, fcount)
		VALUES (106,  concat ('There are ',v_count,' duplicated nodes.'), v_count);

		INSERT INTO audit_check_data(fid,  error_message, fcount)
		SELECT 106,  concat ('Node_id: ',string_agg(node_id, ', '), '.' ), v_count 
		FROM anl_node WHERE cur_user="current_user"() AND fid=106;

	END IF;
	
	-- info
	SELECT array_to_json(array_agg(row_to_json(row))) INTO v_result 
	FROM (SELECT id, error_message as message FROM audit_check_data WHERE cur_user="current_user"() AND fid=106 order by  id asc) row;
	v_result := COALESCE(v_result, '{}'); 
	v_result_info = concat ('{"geometryType":"", "values":',v_result, '}');
	
	--    Control nulls
	v_result_info := COALESCE(v_result_info, '{}'); 
	v_result_point := COALESCE(v_result_point, '{}'); 

	--  Return
	RETURN gw_fct_json_create_return(('{"status":"Accepted", "message":{"level":1, "text":"Analysis done successfully"}, "version":"'||v_version||'"'||
             ',"body":{"form":{}'||
		     ',"data":{ "info":'||v_result_info||','||
				'"point":'||v_result_point||
			'}}'||
	    '}')::json, 2108, null, null, null);

	EXCEPTION WHEN OTHERS THEN
	GET STACKED DIAGNOSTICS v_error_context = PG_EXCEPTION_CONTEXT;
	RETURN ('{"status":"Failed","NOSQLERR":' || to_json(SQLERRM) || ',"SQLSTATE":' || to_json(SQLSTATE) ||',"SQLCONTEXT":' || to_json(v_error_context) || '}')::json;

END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;