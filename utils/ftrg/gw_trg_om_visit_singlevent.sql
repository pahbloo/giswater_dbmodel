/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/

--FUNCTION CODE: 2942

CREATE OR REPLACE FUNCTION "SCHEMA_NAME".gw_trg_om_visit_singlevent()
  RETURNS trigger AS
$BODY$
DECLARE 
    visit_table varchar;
    v_sql varchar;
    v_pluginlot boolean;

BEGIN

    EXECUTE 'SET search_path TO '||quote_literal(TG_TABLE_SCHEMA)||', public';
    visit_table:= TG_ARGV[0];

    select value::json->>'lotManage'::boolean INTO v_pluginlot from config_param_system where parameter = 'plugin_lotmanage';

    IF TG_OP = 'INSERT' THEN

    	IF NEW.visit_id IS NULL THEN
		PERFORM setval('"SCHEMA_NAME".om_visit_id_seq', (SELECT max(id) FROM om_visit), true);
		NEW.visit_id = (SELECT nextval('om_visit_id_seq'));
	END IF;

	IF NEW.startdate IS NULL THEN
		--NEW.startdate = now();
		NEW.startdate = left (date_trunc('second', now())::text, 19);
	END IF;

    IF v_pluginlot AND v_visit_type=1 THEN
	    INSERT INTO om_visit(id, visitcat_id, ext_code, startdate, webclient_id, expl_id, the_geom, descript, is_done, class_id, lot_id, status) 
        VALUES (NEW.visit_id, NEW.visitcat_id, NEW.ext_code, NEW.startdate::timestamp, NEW.webclient_id, NEW.expl_id, NEW.the_geom, NEW.descript, 
        NEW.is_done, NEW.class_id, NEW.lot_id, NEW.status);
    ELSE
        INSERT INTO om_visit(id, visitcat_id, ext_code, startdate, webclient_id, expl_id, the_geom, descript, is_done, class_id, status) 
        VALUES (NEW.visit_id, NEW.visitcat_id, NEW.ext_code, NEW.startdate::timestamp, NEW.webclient_id, NEW.expl_id, NEW.the_geom, NEW.descript, 
        NEW.is_done, NEW.class_id, NEW.status);
    END IF;

    -- event table
    INSERT INTO om_visit_event( event_code, visit_id, position_id, position_value, parameter_id, value, value1, value2, geom1, geom2, geom3, xcoord, ycoord, 
    compass, tstamp, text, index_val, is_last)
    VALUES (NEW.event_code, NEW.visit_id, NEW.position_id, NEW.position_value, NEW.parameter_id, NEW.value, NEW.value1, NEW.value2, NEW.geom1, NEW.geom2, 
    NEW.geom3, NEW.xcoord, NEW.ycoord, NEW.compass, NEW.tstamp, NEW.text, NEW.index_val, NEW.is_last);

        IF visit_table = 'arc' THEN
            INSERT INTO  om_visit_x_arc (visit_id,arc_id) VALUES (NEW.visit_id, NEW.arc_id);

        ELSIF visit_table = 'node' THEN
            INSERT INTO  om_visit_x_node (visit_id,node_id) VALUES (NEW.visit_id, NEW.node_id);

        ELSIF visit_table = 'connec' THEN
            INSERT INTO  om_visit_x_connec (visit_id,connec_id) VALUES (NEW.visit_id, NEW.connec_id);

        ELSIF visit_table = 'gully' THEN
            INSERT INTO  om_visit_x_gully (visit_id,gully_id) VALUES (NEW.visit_id, NEW.gully_id);
            
        ELSIF visit_table = 'polygon' THEN
            INSERT INTO  om_visit_x_pol (visit_id,pol_id) VALUES (NEW.visit_id, NEW.pol_id);
        END IF;

        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
	    -- visit table
        IF v_pluginlot AND v_visit_type=1 THEN
            UPDATE om_visit SET id=NEW.visit_id, visitcat_id=NEW.visitcat_id, ext_code=NEW.ext_code, startdate=NEW.startdate::timestamp, enddate=null,
            webclient_id=NEW.webclient_id, expl_id=NEW.expl_id, the_geom=NEW.the_geom, descript=NEW.descript, is_done=NEW.is_done, class_id=NEW.class_id,
            lot_id=NEW.lot_id, status=NEW.status WHERE id=NEW.visit_id;
        ELSE
            UPDATE om_visit SET id=NEW.visit_id, visitcat_id=NEW.visitcat_id, ext_code=NEW.ext_code, startdate=NEW.startdate::timestamp, enddate=null,
            webclient_id=NEW.webclient_id, expl_id=NEW.expl_id, the_geom=NEW.the_geom, descript=NEW.descript, is_done=NEW.is_done, class_id=NEW.class_id,
            status=NEW.status WHERE id=NEW.visit_id;
        END IF;
        
        -- event table           
  	    -- Delete parameters in case of inconsistency againts visitclass and events (due class of visit have been changed)
   	    DELETE FROM om_visit_event WHERE visit_id=NEW.visit_id AND parameter_id NOT IN 
        (SELECT parameter_id FROM config_visit_class_x_parameter WHERE class_id=NEW.class_id AND active IS TRUE);

	    UPDATE om_visit_event SET event_code=NEW.event_code, visit_id=NEW.visit_id, position_id=NEW.position_id, position_value=NEW.position_value, 
        parameter_id=NEW.parameter_id, value=NEW.value, value1=NEW.value1, value2=NEW.value2, geom1=NEW.geom1, geom2=NEW.geom2, geom3=NEW.geom3,
        xcoord=NEW.xcoord, ycoord=NEW.ycoord, compass=NEW.compass, tstamp=NEW.tstamp, text=NEW.text , index_val=NEW.index_val, is_last=NEW.is_last 
        WHERE id=NEW.event_id;

    RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        DELETE FROM om_visit CASCADE WHERE id = OLD.visit_id ;

    --PERFORM gw_fct_getmessage($${"client":{"device":4, "infoType":1, "lang":"ES"},"feature":{},"data":{"message":"XXX", "function":"XXX","debug_msg":null, "variables":null}}$$)

        RETURN NULL;
    
    END IF;
    
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
