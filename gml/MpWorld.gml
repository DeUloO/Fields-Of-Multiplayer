#macro MP_WORLD_SNAPSHOT_VER 1
#macro MP_WORLD_SNAPSHOT_FILE "/world_snapshot.json"
#macro MP_WORLD_TERRAIN_FILE  "/world_farm_terrain.bin"

function mp_serialize_world_facts() {
    return {
        facts:     T2R.read_world(),
        expirator: T2R.schedule_serialize_expirator(),
    };
}

global.mp_world_adopted = false;

function mp_world_serialize() {
    if GRIDS == undefined { return -1; }
    if !instance_exists(obj_ari) { return -1; }

    var locations = [];
    var farm_terrain_saved = false;

    for (var i = 0; i < LocationId.LEN; i++) {
        if i == LocationId.Dungeon { continue; }
        if GRIDS[i] == undefined { continue; }
        if LOCATIONS[i].serializable == false { continue; }

        var blob = create_grid_serialization_data(GRIDS[i]);

        if blob[$ "terrain_buffer"] != undefined {
            buffer_save(blob.terrain_buffer, mp_dir() + MP_WORLD_TERRAIN_FILE);
            buffer_delete(blob.terrain_buffer);
            blob.terrain_buffer = undefined;
            farm_terrain_saved = true;
        }

        array_push(locations, {
            loc:  i,
            data: {
                object_list: blob.object_list,
                inventories: blob.inventories,
                size_x:      blob.size_x,
                size_y:      blob.size_y,
                location_id: blob.location_id,
                dyn_index:   blob.dyn_index,
            },
        });
    }

    var dyn_grids = [];
    if DYNAMIC_GRIDS != undefined {
        for (var di = 0; di < DYNAMIC_GRIDS.count(); di++) {
            var dg = DYNAMIC_GRIDS.get(di);
            if dg == undefined {
                array_push(dyn_grids, { nil: true });
                continue;
            }
            var dblob = create_grid_serialization_data(dg);
            if dblob[$ "terrain_buffer"] != undefined {
                buffer_delete(dblob.terrain_buffer);
                dblob.terrain_buffer = undefined;
            }
            array_push(dyn_grids, {
                object_list: dblob.object_list,
                inventories: dblob.inventories,
                size_x:      dblob.size_x,
                size_y:      dblob.size_y,
                location_id: dblob.location_id,
                dyn_index:   dblob.dyn_index,
            });
        }
    }

    var header = {
        weather:          WEATHER.serialize(),
        cal:              CALENDAR.time,
        clk:              CLOCK.time,
        farm_expanded:    FARM_EXPANDED,
        home_upgrade:     DECOR.size_upgrade,
        floorings:        DECOR.serialize_floorings(),
        wallpapers:       DECOR.serialize_wallpapers(),
        has_farm_terrain: farm_terrain_saved,
        max_dungeon:      MAXIMUM_REACHED_DUNGEON_LEVEL,
    };

    var snapshot = {
        ver:       MP_WORLD_SNAPSHOT_VER,
        host_pid:  string(ARI.name) + "|" + string(ARI.farm_name),
        header:    header,
        dyn_grids: dyn_grids,
        locations: locations,
        world_facts: mp_serialize_world_facts(),
    };

    save_json_file(mp_dir() + MP_WORLD_SNAPSHOT_FILE, snapshot);
    show_debug_message("[MOMI-MP] world snapshot written: "
        + string(array_length(locations)) + " locations, "
        + string(array_length(dyn_grids)) + " dyn grids, farm_terrain="
        + string(farm_terrain_saved));
    return array_length(locations);
}

function mp_collect_turn_in_boxes() {
    var _out = [];
    if GRIDS == undefined { return _out; }
    for (var _i = 0; _i < LocationId.LEN; _i++) {
        var _g = GRIDS[_i];
        if _g == undefined { continue; }
        var _seen = {};
        var _wn = _g.dims.x * _g.dims.y;
        for (var _ni = 0; _ni < _wn; _ni++) {
            if _g.node_object_id[_ni] != ObjectId.TurnInBox { continue; }
            var _p = _g.node_parent[_ni];
            if _p == undefined { continue; }
            var _key = string(_p.top_left_x) + ":" + string(_p.top_left_y);
            if _seen[$ _key] != undefined { continue; }
            _seen[$ _key] = true;
            try {
                var _invlist = List();
                var _obj = create_grid_object_serialization_data(_p, _invlist);
                array_push(_out, { loc: _i, obj: _obj, invs: _invlist.to_array() });
            } catch (_ce) {
                show_debug_message("[MOMI-MP] capture turn-in box @ " + string(_i) + " failed: " + string(_ce));
            }
        }
    }
    return _out;
}

function mp_strip_turn_in_boxes() {
    if GRIDS == undefined { return; }
    for (var _i = 0; _i < LocationId.LEN; _i++) {
        var _g = GRIDS[_i];
        if _g == undefined { continue; }
        var _wn = _g.dims.x * _g.dims.y;
        for (var _ni = 0; _ni < _wn; _ni++) {
            if _g.node_object_id[_ni] != ObjectId.TurnInBox { continue; }
            try { erase_object_node(_g, _ni); }
            catch (_ee) { show_debug_message("[MOMI-MP] strip turn-in box @ " + string(_i) + " failed: " + string(_ee)); }
        }
    }
}

function mp_reinsert_turn_in_boxes(_boxes) {
    for (var _b = 0; _b < array_length(_boxes); _b++) {
        var _entry = _boxes[_b];
        if _entry.loc < 0 || _entry.loc >= array_length(GRIDS) { continue; }
        var _g = GRIDS[_entry.loc];
        if _g == undefined { continue; }
        try {
            var _invs = (_entry[$ "invs"] != undefined) ? _entry.invs : [];
            for (var _ii = 0; _ii < array_length(_invs); _ii++) {
                var _arr = _invs[_ii];
                var _inv = Inventory(array_length(_arr));
                _inv.deserialize(_arr);
                _invs[_ii] = _inv;
            }
            _g.load_objects([_entry.obj], _invs);
        } catch (_re) {
            show_debug_message("[MOMI-MP] reinsert turn-in box @ " + string(_entry.loc) + " failed: " + string(_re));
        }
    }
}

function mp_is_personal_fact(_name) {
    if _name == "has_spouse" || _name == "has_fiance" { return true; }
    return string_ends_with(_name, "_status")
        || string_ends_with(_name, "_is_best_friend")
        || string_ends_with(_name, "_is_dating")
        || string_ends_with(_name, "_is_fiance")
        || string_ends_with(_name, "_is_spouse")
        || string_ends_with(_name, "_is_partner");
}

function mp_apply_world_facts(snapshot) {
    if snapshot[$ "world_facts"] == undefined { return; }
    var _wf = snapshot.world_facts;
    if _wf[$ "facts"] == undefined { return; }
    try {
        var _keys = struct_get_names(_wf.facts);
        for (var _i = 0; _i < array_length(_keys); _i++) {
            var _name = _keys[_i];
            if matches(_name, "date_time", "day_time", "ari_birthday", "ari_name", "is_ari_birthday") { continue; }
            if mp_is_personal_fact(_name) { continue; }
            T2R.write(_name, _wf.facts[$ _name]);
        }
        if _wf[$ "expirator"] != undefined { T2R.schedule_deserialize_expirator(_wf.expirator); }
        T2R.update();
        show_debug_message("[MOMI-MP] adopted host world facts (areas / milestones)");
    } catch (_e) { show_debug_message("[MOMI-MP] adopt world facts failed: " + string(_e)); }
}

function mp_room_pos_has_object(_gx, _gy) {
    if GRID == undefined { return false; }
    var _ni = GRID.try_node_index_for_room_position(_gx, _gy);
    if _ni == undefined { return false; }
    return GRID.node_object_id[_ni] != undefined;
}

function mp_safe_room_position_near(_gx, _gy) {
    if GRID == undefined { return undefined; }
    for (var _r = 8; _r <= 96; _r += 8) {
        for (var _dy = -_r; _dy <= _r; _dy += 8) {
            for (var _dx = -_r; _dx <= _r; _dx += 8) {
                if abs(_dx) != _r && abs(_dy) != _r { continue; }   // ring perimeter only
                var _tx = _gx + _dx;
                var _ty = _gy + _dy;
                var _ni = GRID.try_node_index_for_room_position(_tx, _ty);
                if _ni == undefined { continue; }
                if GRID.node_object_id[_ni] == undefined { return { x: _tx, y: _ty }; }
            }
        }
    }
    return undefined;
}

function mp_world_apply(snapshot) {
    if snapshot == undefined { return false; }
    if snapshot[$ "locations"] == undefined { return false; }
    if GRIDS == undefined { return false; }
    if !instance_exists(obj_ari) { return false; }

    if !deulo_mp_sync_world_enabled() { return false; }

    var _my_pid = string(ARI.name) + "|" + string(ARI.farm_name);
    if snapshot[$ "host_pid"] != undefined && string(snapshot.host_pid) == _my_pid {
        show_debug_message("[MOMI-MP] world snapshot rejected: host_pid == self (stale/own session)");
        return false;
    }
    if mp_is_host() {
        show_debug_message("[MOMI-MP] world snapshot rejected: we are the host, not a joiner");
        return false;
    }

    if !global.mp_world_adopted {
        deulo_mp_hard_save("client joining host — preserving original world");
        global.mp_world_adopted = true;
    }

    var _turn_in_boxes = [];
    try { _turn_in_boxes = mp_collect_turn_in_boxes(); } catch (_tibe) {}

    var header = snapshot[$ "header"];

    with obj_player_animal { instance_destroy(); }

    var farm_buffer = undefined;
    if header != undefined && header[$ "has_farm_terrain"] == true {
        var tpath = mp_dir() + MP_WORLD_TERRAIN_FILE;
        if file_exists(tpath) { farm_buffer = buffer_load(tpath); }
    }

    if snapshot[$ "dyn_grids"] != undefined {
        var dgs    = snapshot.dyn_grids;
        var dcount = array_length(dgs);
        global.__dynamic_grids = ListFromArray(array_create(dcount, undefined));
        for (var i = 0; i < dcount; i++) {
            var dg = dgs[i];
            if dg == undefined { continue; }
            if dg[$ "nil"] == true { continue; }
            try {
                var loc = string_to_location_id(dg.location_id);
                var dyi = (dg.dyn_index == -1) ? undefined : dg.dyn_index;
                var g = initialize_grid(loc, dyi);
                DYNAMIC_GRIDS.set(i, g);
                g.load(dg);
                g.is_setup = true;
            } catch (e) {
                show_debug_message("[MOMI-MP] apply: dyn grid " + string(i) + " failed: " + string(e));
            }
        }
    }

    var locs = snapshot.locations;
    var applied = 0;
    for (var li = 0; li < array_length(locs); li++) {
        var entry = locs[li];
        var i     = entry.loc;
        var data  = entry.data;

        try {
            var grid = initialize_grid(i);

            if i == LocationId.PlayerHome {
                DECOR.size_upgrade = -1;
                var hu = (header != undefined && header[$ "home_upgrade"] != undefined)
                    ? header.home_upgrade : HomeUpgrade.Small;
                DECOR.apply_house_upgrade(grid, hu);
            }

            if i == LocationId.Farm {
                room_data_initialize_post_init_flags(location_id_to_gm_room(grid.location_id), grid.node_flags);
            } else if i == LocationId.PriestessQuarters {
                setup_priestess_quarters(grid);
            }

            var tb = (i == LocationId.Farm) ? farm_buffer : undefined;
            grid.load(data, tb);
            load_npc_farms(grid);
            grid.is_setup = true;
            GRIDS[i] = grid;
            applied++;
        } catch (e) {
            show_debug_message("[MOMI-MP] apply: location " + string(i) + " failed: " + string(e));
        }
    }

    if farm_buffer != undefined { buffer_delete(farm_buffer); }

    mp_apply_world_facts(snapshot);

    mp_strip_turn_in_boxes();
    mp_reinsert_turn_in_boxes(_turn_in_boxes);

    if header != undefined {
        try {
            if header[$ "cal"] != undefined { CALENDAR.time = header.cal; }
            if header[$ "clk"] != undefined { CLOCK.time = header.clk; }
            if header[$ "farm_expanded"] != undefined { FARM_EXPANDED = header.farm_expanded; }

            if header[$ "max_dungeon"] != undefined {
                MAXIMUM_REACHED_DUNGEON_LEVEL = max(MAXIMUM_REACHED_DUNGEON_LEVEL, header.max_dungeon);
            }
            if header[$ "floorings"]  != undefined { DECOR.floorings  = deserialize_floorings(header.floorings); }
            if header[$ "wallpapers"] != undefined { DECOR.wallpapers = deserialize_wallpapers(header.wallpapers); }
            if header[$ "weather"] != undefined {
                WEATHER.deserialize(header.weather);
                WEATHER.set_weather(WEATHER.forecast[CALENDAR.day()]);
            }
        } catch (e) {
            show_debug_message("[MOMI-MP] apply: header failed: " + string(e));
        }
    }

    GRID = GRIDS[CURRENT_LOCATION_ID];

    global.mp_grid_loc    = -1;
    global.mp_ev_queue    = [];
    global.mp_items_prev  = undefined;
    global.mp_recv_pickup = {};
    global.mp_animal_prev = {};
    global.mp_bldg_out    = {};

    show_debug_message("[MOMI-MP] world applied: " + string(applied) + "/"
        + string(array_length(locs)) + " locations");

    var keep_x   = obj_ari.x;
    var keep_y   = obj_ari.y;
    var keep_dir = obj_ari.dir;

    var target_x = keep_x;
    var target_y = keep_y;
    if mp_room_pos_has_object(keep_x, keep_y) {
        var _moved = false;
        if snapshot[$ "host_pid"] != undefined {
            var _hg = mp_find_ghost(string(snapshot.host_pid));
            if _hg != undefined && instance_exists(_hg) && _hg.visible
                && !mp_room_pos_has_object(_hg.x, _hg.y) {
                target_x = _hg.x;
                target_y = _hg.y;
                _moved = true;
            }
        }
        if !_moved {
            var _safe = mp_safe_room_position_near(keep_x, keep_y);
            if _safe != undefined { target_x = _safe.x; target_y = _safe.y; _moved = true; }
        }
        obj_ari.x = target_x;
        obj_ari.y = target_y;
        show_debug_message("[MOMI-MP] player overlapped a host object on apply; teleport "
            + (_moved ? ("-> (" + string(target_x) + "," + string(target_y) + ")")
                      : "FAILED (no clear tile; kept original)"));
    }

    var itin = TaxiItinerary(location_id_to_gm_room(CURRENT_LOCATION_ID));
    itin.set_instant(true);
    itin.set_exact_position(target_x, target_y);
    itin.set_arrival_callback(function(kx, ky, kdir) {
        obj_ari.x = kx;
        obj_ari.y = ky;
        obj_ari.face_dir(kdir);
    }, [target_x, target_y, keep_dir]);
    TAXI.taxi_player(itin);
    return true;
}

function mp_clear_session_files() {
    var _d = mp_dir();
    var _files = [
        "/world_snapshot.json", "/world_farm_terrain.bin",
        "/mp_apply_world", "/mp_snap_ready", "/mp_snap_request", "/mp_dump_world", "/mp_resync",
        "/remote.json", "/out.json",
    ];
    for (var _i = 0; _i < array_length(_files); _i++) {
        var _p = _d + _files[_i];
        if file_exists(_p) { try { file_delete(_p); } catch (_e) {} }
    }
    show_debug_message("[MOMI-MP] cleared stale session files in " + _d);
}

function mp_request_world_resync() {
    if mp_is_host() { return; }
    save_json_file(mp_dir() + "/mp_resync", { t: CALENDAR.time });
    show_debug_message("[MOMI-MP] new day — requesting world re-sync from host");
}

function mp_client_reset_watered() {
    if GRIDS == undefined { return; }
    for (var _i = 0; _i < LocationId.LEN; _i++) {
        var _g = GRIDS[_i];
        if _g == undefined { continue; }
        var _arr = _g[$ "node_terrain_is_watered"];
        if _arr == undefined { continue; }
        for (var _ni = 0; _ni < array_length(_arr); _ni++) { _arr[_ni] = false; }
    }

    try {
        if GRID != undefined && LOCATIONS[GRID.location_id].farm {
            for (var _xx = 0; _xx < GRID.dims.x; _xx += 2) {
                for (var _yy = 0; _yy < GRID.dims.y; _yy += 2) {
                    GRID.auto_tile_tile(_xx, _yy);
                }
            }
        }
        if instance_exists(obj_ari) && GRID != undefined {
            var _post = mp_grid_snapshot();
            global.mp_grid_prev    = _post.nodes;
            global.mp_terr_prev_gk = _post.gk;
            global.mp_terr_prev_w  = _post.w;
        }
    } catch (_e) { show_debug_message("[MOMI-MP] reset watered retile failed: " + string(_e)); }
}

function mp_world_tick() {
    if mp_is_host() {

        var dump_trig = mp_dir() + "/mp_dump_world";
        if file_exists(dump_trig) {
            file_delete(dump_trig);
            mp_world_serialize();
        }

        var req = mp_dir() + "/mp_snap_request";
        if file_exists(req) {
            file_delete(req);
            mp_world_serialize();
            save_json_file(mp_dir() + "/mp_snap_ready", { ok: true });
        }
        return;
    }

    var apply_trig = mp_dir() + "/mp_apply_world";
    if file_exists(apply_trig) {
        if !instance_exists(obj_ari) { return; }
        file_delete(apply_trig);
        var snap = try_read_json_file(mp_dir() + MP_WORLD_SNAPSHOT_FILE);
        if snap == undefined {
            show_debug_message("[MOMI-MP] apply: no world_snapshot.json in " + mp_dir());
        } else {
            mp_world_apply(snap);
        }
    }
}
