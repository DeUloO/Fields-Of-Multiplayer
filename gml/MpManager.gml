global.mp_seq             = 0;
global.mp_samples         = [];
global.mp_last_weather    = undefined;

#macro MP_HISTORY    60
#macro MP_TARGET_LAG 6

function mp_dir() {
    var _rt = __deulo_multiplayer_runtime();
    var _id = _rt[$ "instance_id"];
    if (_id == undefined) { _id = ""; }
    if (_rt[$ "dir_cache"] == undefined || _rt[$ "dir_cache_id"] != _id) {
        var _dir = CONFIG_DIRECTORY + "/momi_mp";
        if (_id != "") { _dir += "_" + _id; }
        directory_create(_dir);
        _rt.dir_cache    = _dir;
        _rt.dir_cache_id = _id;
    }
    return _rt.dir_cache;
}

function mp_is_host() {
    return deulo_mp_role() == "host";
}

function mp_reset_session_state() {
    with obj_mp_ghost { instance_destroy(); }
    global.mp_samples      = [];
    global.mp_seq          = 0;
    global.mp_last_weather = undefined;
    global.mp_grid_prev    = undefined;
    global.mp_terr_prev_gk = undefined;
    global.mp_terr_prev_w  = undefined;
    global.mp_grid_loc     = -1;
    global.mp_ev_seq       = 0;
    global.mp_ev_queue     = [];
    global.mp_evseq_by_pid = {};
    global.mp_chest_prev   = {};
    global.mp_animal_prev  = {};
    global.mp_bldg_out     = {};
    global.mp_crop_prev    = {};
    global.mp_items_prev   = undefined;
    global.mp_recv_pickup  = {};
    global.mp_picked_up    = {};
    global.mp_client_epoch = mp_generate_client_epoch();
    global.mp_outbox_pending    = [];
    global.mp_outbox_seg_seq    = 0;
    global.mp_outbox_seg_init   = false;
    global.mp_applied_relay_seq = 0;
    show_debug_message("[MOMI-MP] session state reset (ghosts + diff baselines cleared)");
}

function mp_client_new_day_personal() {
    try {
        ARI.set_stamina(ARI.get_max_stamina(), true, true);
        ARI.set_health(ARI.get_max_health(), false, true);
    } catch (_e) {
        show_debug_message("[MOMI-MP] client new-day personal reset failed: " + string(_e));
    }
}

function mp_sample() {
    if !instance_exists(obj_ari) { return; }
    array_push(global.mp_samples, {
        i: global.mp_seq,
        x: obj_ari.x,
        y: obj_ari.y,
        z: obj_ari.z,
        c: obj_ari.cardinal,
        an: obj_ari.par.base_animation(),

    });
    global.mp_seq++;
    if array_length(global.mp_samples) > MP_HISTORY {
        array_delete(global.mp_samples, 0, 1);
    }
}

function mp_current_modifier() {
    var slots_ref = obj_ari.par.slots;
    for (var si = 0; si < array_length(slots_ref); si++) {
        var mn = slots_ref[si].modifier.animation_name;
        if mn != undefined { return mn; }
    }
    return -1;
}

function mp_current_held() {
    var hs = obj_ari.par.held_sprite;
    if hs == undefined { return { on: false }; }
    return {
        on:  true,
        s:   hs.sprite_index,
        idx: hs.image_index,
        xo:  hs.x_offset,
        fxo: hs.flipped_x_offset,
        yo:  hs.y_offset,
        fl:  hs.flips,
    };
}

function mp_tick() {
    mp_scan_grid();
    mp_scan_items();
    mp_scan_animals();
    mp_outbox_flush();
    mp_outbox_prune_acked();
    mp_inbox_process();
    mp_write_state();
    mp_read_state();
}

function mp_write_state() {
    if !instance_exists(obj_ari) { return; }

    var att = -1;
    if obj_ari.par.attachment != undefined {
        att = obj_ari.par.attachment.name;
    }

    var ba = obj_ari.par.base_animation();
    if ba == undefined { ba = -1; }
    var state = {
        player_id:   string(ARI.name) + "|" + string(ARI.farm_name),
        name:        string(ARI.name),
        location_id: CURRENT_LOCATION_ID,
        x:           obj_ari.x,
        y:           obj_ari.y,
        path:        global.mp_samples,
        ba:          ba,
        ma:          mp_current_modifier(),
        att:         att,
        held:        mp_current_held(),
        evs:         global.mp_ev_queue,
        cal:         CALENDAR.time,
        clk:         CLOCK.time,
        whost:       mp_is_host(),
        wthr:        (WEATHER != undefined) ? WEATHER.weather   : undefined,
        wfc:         (WEATHER != undefined) ? WEATHER.forecast  : undefined,
        appearance:  ARI.animation_assets().serialize(),
    };
    save_json_file(mp_dir() + "/out.json", state);
}

function mp_read_state() {

    var _remote = mp_dir() + "/remote.json";
    if !file_exists(_remote) { return; }
    var data = try_read_json_file(_remote);
    if data == undefined || data[$ "players"] == undefined {
        return;
    }
    var players = data.players;
    for (var i = 0; i < array_length(players); i++) {
        mp_update_ghost(players[i]);
        mp_apply_player_events(players[i]);
    }

    if !mp_is_host() {
        for (var i = 0; i < array_length(players); i++) {
            var s = players[i];
            if s[$ "whost"] != true { continue; }
            if s[$ "cal"] == undefined || s[$ "clk"] == undefined { break; }
            if s.cal != CALENDAR.time {
                CALENDAR.time = s.cal;
                CLOCK.time    = s.clk;
                mp_client_reset_watered();
                mp_client_new_day_personal();
                mp_request_world_resync();
            } else if CLOCK != undefined && CLOCK[$ "time_stopped"] != true {
                CLOCK.time = s.clk;
            }
            break;
        }
    }

    if !mp_is_host() && WEATHER != undefined {
        for (var i = 0; i < array_length(players); i++) {
            var s = players[i];
            if s[$ "whost"] != true { continue; }
            if s[$ "wfc"] != undefined { WEATHER.forecast = s.wfc; }
            var _want = s[$ "wthr"];
            if _want == undefined && WEATHER[$ "forecast"] != undefined {
                _want = WEATHER.forecast[CALENDAR.day()];
            }
            if _want != undefined && _want != WEATHER.weather {
                WEATHER.set_weather(_want);
                global.mp_last_weather = _want;
            }
            break;
        }
    }
}

function mp_find_ghost(pid) {
    with obj_mp_ghost {
        if self.mp_player_id == pid { return self; }
    }
    return undefined;
}

function mp_update_ghost(state) {
    var pid = string(state.player_id);

    var my_pid = string(ARI.name) + "|" + string(ARI.farm_name);
    if pid == my_pid { return; }

    var same_location = (state.location_id == CURRENT_LOCATION_ID);
    var ghost = mp_find_ghost(pid);
    if ghost == undefined && same_location && instance_exists(obj_ari) {
        ghost = instance_create_depth(state.x, state.y, 0, obj_mp_ghost);
        ghost.mp_player_id = pid;
        ghost.x = state.x;
        ghost.y = state.y;
    }
    if ghost == undefined { return; }

    var _pth = state[$ "path"];
    if _pth != undefined && array_length(_pth) > 0 {
        var _maxi = _pth[array_length(_pth) - 1].i;
        if _maxi > ghost.mp_liveness_seq {
            ghost.mp_liveness_seq = _maxi;
            ghost.mp_last_update  = 0;
        }
    }
    ghost.visible = same_location;

    if !same_location {

        ghost.mp_buf    = [];
        ghost.mp_last_i = -1;
        ghost.mp_play   = -1;
        return;
    }

    if state[$ "ba"] != undefined { ghost.mp_remote_ba = state.ba; }

    if state[$ "ma"] != undefined {
        if state.ma != ghost.mp_last_ma {
            if state.ma == -1 {
                ghost.par.unset_all_modifiers();
            } else {
                ghost.par.set_animation(state.ma);
            }
            ghost.mp_last_ma = state.ma;
        }
    }

    if state[$ "att"] != undefined {
        if state.att != ghost.mp_last_att {
            if state.att == -1 {
                ghost.par.remove_attachment();
            } else {
                ghost.par.set_attachment(state.att);
            }
            ghost.mp_last_att = state.att;
        }
    }

    if state[$ "held"] != undefined {
        var h = state.held;
        var key = h.on ? (string(h.s) + "|" + string(h.idx) + "|" + string(h.fl)) : "";
        if key != ghost.mp_held_key {
            if !h.on {
                ghost.par.remove_held_sprite();
            } else {
                ghost.par.set_held_sprite(h.s, h.idx, h.xo, h.yo, h.fxo, h.fl);
            }
            ghost.mp_held_key = key;
        }
    }

    if state[$ "appearance"] != undefined {
        var app = state.appearance;
        var assets = app.assets;
        var key = string(app.skin_tone) + "|" + string(app.eyes);
        for (var i = 0; i < array_length(assets); i++) {
            key = key + "|" + string(assets[i].name) + ":" + string(assets[i].lut_index);
        }
        if ghost.mp_appearance_key != key {

            var new_names = [];
            for (var i = 0; i < array_length(assets); i++) {
                array_push(new_names, assets[i].name);
            }
            for (var oi = 0; oi < array_length(ghost.mp_applied_assets); oi++) {
                var old_name = ghost.mp_applied_assets[oi];
                var still_present = false;
                for (var ni = 0; ni < array_length(new_names); ni++) {
                    if new_names[ni] == old_name { still_present = true; break; }
                }
                if !still_present {
                    ghost.par.remove_asset(old_name);
                }
            }
            var paa = player_animation_assets_deserialize(app);
            paa.apply_to_par(ghost.par);
            ghost.mp_applied_assets = new_names;
            ghost.mp_appearance_key = key;
        }
    }

    if state[$ "path"] != undefined {
        var path = state.path;
        for (var i = 0; i < array_length(path); i++) {
            var s = path[i];
            if s.i > ghost.mp_last_i {
                var sz = 0;
                if s[$ "z"] != undefined { sz = s.z; }
                array_push(ghost.mp_buf, { i: s.i, x: s.x, y: s.y, z: sz, c: s.c, an: s[$ "an"] });
                ghost.mp_last_i = s.i;
            }
        }

        while (array_length(ghost.mp_buf) > 200) {
            array_delete(ghost.mp_buf, 0, 1);
        }
    }

}
