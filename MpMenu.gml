#macro DEULO_MP_MOD            "deulo_multiplayer"
#macro DEULO_MP_CONFIG_VERSION 1
#macro DEULO_MP_CATEGORY       "multiplayer"
#macro DEULO_MP_ROW            33
#macro DEULO_MP_NOTE_ROW       24

#macro DEULO_MP_STATUS_READ_FRAMES 15
#macro DEULO_MP_STATUS_STALE_MAX   6

function deulo_mp_is_number(_value) {
    var _t = typeof(_value);
    return _t == "number" || _t == "int32" || _t == "int64";
}

function deulo_multiplayer_config_ensure_loaded() {
    var _rt = __deulo_multiplayer_runtime();
    if (_rt.config_loaded) { return; }

    var _src = mmapi_config_read_valid(DEULO_MP_MOD, DEULO_MP_CONFIG_VERSION);

    var _ip = _src[$ "host_ip"];
    if (!is_string(_ip) || _ip == "") { _ip = "127.0.0.1"; }

    var _port = _src[$ "port"];
    if (!deulo_mp_is_number(_port)) { _port = 7777; }
    _port = floor(real(_port));
    if (_port < 1 || _port > 65535) { _port = 7777; }

    var _sync_world = _src[$ "sync_world"];
    if (typeof(_sync_world) != "bool") { _sync_world = true; }

    var _sync_interval = _src[$ "sync_interval"];
    if (!deulo_mp_is_number(_sync_interval)) { _sync_interval = 3; }
    _sync_interval = floor(real(_sync_interval));
    if (_sync_interval < 1)  { _sync_interval = 1; }
    if (_sync_interval > 30) { _sync_interval = 30; }

    var _cfg = { host_ip: _ip, port: _port, sync_world: _sync_world, sync_interval: _sync_interval };
    mmapi_config_write(DEULO_MP_MOD, DEULO_MP_CONFIG_VERSION, _cfg);

    var _iid    = "";
    var _idfile = CONFIG_DIRECTORY + "/momi_mp_id.json";
    if (file_exists(_idfile)) {
        var _idd = try_read_json_file(_idfile, undefined, false);
        if (is_struct(_idd) && _idd[$ "id"] != undefined) { _iid = string(_idd.id); }
    }

    _rt.config        = _cfg;
    _rt.host_ip       = _ip;
    _rt.port          = _port;
    _rt.sync_world    = _sync_world;
    _rt.sync_interval = _sync_interval;
    _rt.role          = "off";
    _rt.instance_id   = deulo_mp_sanitize_instance(_iid);
    _rt.config_loaded = true;

    mmapi_log_info(DEULO_MP_MOD,
        "config loaded; host_ip=" + string(_ip) + " port=" + string(_port));
    mmapi_log_flush(DEULO_MP_MOD);
}

function deulo_mp_role() {
    var _rt = __deulo_multiplayer_runtime();
    deulo_multiplayer_config_ensure_loaded();
    var _r = _rt[$ "role"];
    if (_r == undefined) { return "off"; }
    return _r;
}

function deulo_mp_role_label(_role) {
    if (_role == "host") { return "Host"; }
    if (_role == "join") { return "Join"; }
    return "Off";
}

function deulo_mp_sync_world_enabled() {
    var _rt = __deulo_multiplayer_runtime();
    deulo_multiplayer_config_ensure_loaded();
    return (_rt[$ "sync_world"] != false);
}

function deulo_mp_toggle_sync_world() {
    var _rt = __deulo_multiplayer_runtime();
    deulo_multiplayer_config_ensure_loaded();
    _rt.sync_world        = !deulo_mp_sync_world_enabled();
    _rt.config.sync_world = _rt.sync_world;
    mmapi_config_write(DEULO_MP_MOD, DEULO_MP_CONFIG_VERSION, _rt.config);
}

function deulo_mp_sync_interval() {
    var _rt = __deulo_multiplayer_runtime();
    deulo_multiplayer_config_ensure_loaded();
    var _v = _rt[$ "sync_interval"];
    if (!deulo_mp_is_number(_v) || _v < 1) { return 3; }
    return _v;
}

function deulo_mp_apply_interval(_text) {
    var _rt = __deulo_multiplayer_runtime();
    var _n  = deulo_mp_parse_port(_text);
    if (_n == undefined || _n < 1 || _n > 30) {
        mmapi_log_warn(DEULO_MP_MOD, "sync interval must be 1-30; left unchanged");
        mmapi_log_flush(DEULO_MP_MOD);
        return;
    }
    _rt.sync_interval        = _n;
    _rt.config.sync_interval = _n;
    mmapi_config_write(DEULO_MP_MOD, DEULO_MP_CONFIG_VERSION, _rt.config);
}

function deulo_mp_write_control() {
    var _rt = __deulo_multiplayer_runtime();
    _rt.control_seq = ((_rt[$ "control_seq"] == undefined) ? 0 : _rt.control_seq) + 1;
    var _ctrl = {
        mode: deulo_mp_role(),
        ip:   string(_rt.host_ip),
        port: _rt.port,
        seq:  _rt.control_seq,
    };
    save_json_file(mp_dir() + "/mp_control.json", _ctrl);
    mmapi_log_info(DEULO_MP_MOD,
        "control -> " + _ctrl.mode + " " + _ctrl.ip + ":" + string(_ctrl.port)
        + " (seq " + string(_ctrl.seq) + ")");
    mmapi_log_flush(DEULO_MP_MOD);
}

function deulo_mp_set_role(_new_role) {
    var _rt = __deulo_multiplayer_runtime();
    deulo_multiplayer_config_ensure_loaded();

    var _old_role = deulo_mp_role();
    if (_new_role == _old_role) {

        deulo_mp_write_control();
        return;
    }

    if (_new_role == "host" || _new_role == "join") {
        deulo_mp_hard_save("activating " + _new_role);
    }

    if (_new_role == "join") { global.mp_world_adopted = false; }

    _rt.role            = _new_role;
    global.mp_last_weather = undefined;

    mp_reset_session_state();
    mp_clear_session_files();

    deulo_mp_write_control();
}

function deulo_mp_cycle_role() {
    var _r = deulo_mp_role();
    var _next = (_r == "off") ? "host" : ((_r == "host") ? "join" : "off");
    deulo_mp_set_role(_next);
}

function deulo_mp_apply_ip(_text) {
    var _rt = __deulo_multiplayer_runtime();
    var _s  = string_trim(string(_text));
    if (_s == "") { return; }
    _rt.host_ip        = _s;
    _rt.config.host_ip = _s;
    mmapi_config_write(DEULO_MP_MOD, DEULO_MP_CONFIG_VERSION, _rt.config);
    deulo_mp_write_control();
}

function deulo_mp_apply_port(_text) {
    var _rt = __deulo_multiplayer_runtime();
    var _s  = string_trim(string(_text));
    var _n  = deulo_mp_parse_port(_s);
    if (_n == undefined) {
        mmapi_log_warn(DEULO_MP_MOD, "'" + _s + "' is not a valid port; left unchanged");
        mmapi_log_flush(DEULO_MP_MOD);
        return;
    }
    _rt.port        = _n;
    _rt.config.port = _n;
    mmapi_config_write(DEULO_MP_MOD, DEULO_MP_CONFIG_VERSION, _rt.config);
    deulo_mp_write_control();
}

function deulo_mp_parse_port(_text) {
    var _len = string_length(_text);
    if (_len == 0) { return undefined; }
    for (var _i = 1; _i <= _len; _i++) {
        if (string_pos(string_char_at(_text, _i), "0123456789") == 0) { return undefined; }
    }
    var _n = floor(real(_text));
    if (_n < 1 || _n > 65535) { return undefined; }
    return _n;
}

function deulo_mp_sanitize_instance(_s) {
    var _out = "";
    for (var _i = 1; _i <= string_length(_s); _i++) {
        var _c = string_char_at(_s, _i);
        if (string_pos(_c, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-") > 0) {
            _out += _c;
        }
    }
    return _out;
}

function deulo_mp_instance_label(_id) {
    if (_id == undefined || _id == "") { return "main"; }
    return string(_id);
}

function deulo_mp_set_instance(_id) {
    var _rt = __deulo_multiplayer_runtime();
    _rt.instance_id = deulo_mp_sanitize_instance(string(_id));
    deulo_mp_write_control();
}

function deulo_mp_cycle_instance() {
    var _rt   = __deulo_multiplayer_runtime();
    var _cur  = _rt[$ "instance_id"];
    if (_cur == undefined) { _cur = ""; }
    var _slots = ["", "p2", "p3", "p4"];
    var _idx   = 0;
    for (var _i = 0; _i < array_length(_slots); _i++) {
        if (_slots[_i] == _cur) { _idx = _i; break; }
    }
    _idx = (_idx + 1) % array_length(_slots);
    deulo_mp_set_instance(_slots[_idx]);
}

function deulo_mp_hard_save(_reason) {
    if (!instance_exists(obj_ari)) {
        mmapi_log_info(DEULO_MP_MOD,
            "hard save skipped (" + string(_reason) + "): not in-world");
        mmapi_log_flush(DEULO_MP_MOD);
        return false;
    }

    var _ok = false;
    try {
        ARI.save_position = new LocationPosition(
            CURRENT_LOCATION_ID, Vec2(obj_ari.x, obj_ari.y));
        save_game(exact_save_path(Game.unique_identifier, true, irandom(I32_MAX)));
        _ok = true;
        mmapi_log_info(DEULO_MP_MOD, "hard save written (" + string(_reason) + ")");
    } catch (_e) {
        mmapi_log_warn(DEULO_MP_MOD,
            "hard save failed (" + string(_reason) + "): " + string(_e));
    }
    mmapi_log_flush(DEULO_MP_MOD);

    if (_ok) {
        try { create_save_notification(); } catch (_e2) {}
    }
    return _ok;
}

function deulo_mp_status_text() {
    var _rt = __deulo_multiplayer_runtime();

    var _fc = (_rt[$ "status_fc"] == undefined) ? 0 : _rt.status_fc;
    if (_fc <= 0) {
        deulo_mp_status_refresh();
        _rt.status_fc = DEULO_MP_STATUS_READ_FRAMES;
    } else {
        _rt.status_fc = _fc - 1;
    }

    return (_rt[$ "status_text"] == undefined) ? "Relay off" : _rt.status_text;
}

function deulo_mp_status_refresh() {
    var _rt   = __deulo_multiplayer_runtime();
    var _path = mp_dir() + "/mp_status.json";

    if (!file_exists(_path)) {
        _rt.status_text     = "Relay off";
        _rt.status_prev_hb  = undefined;
        _rt.status_stale    = 0;
        return;
    }

    var _data = try_read_json_file(_path, undefined, false);
    if (!is_struct(_data)) {

        return;
    }

    var _hb = _data[$ "hb"];
    if (_hb != undefined && _hb == _rt[$ "status_prev_hb"]) {
        _rt.status_stale = ((_rt[$ "status_stale"] == undefined) ? 0 : _rt.status_stale) + 1;
    } else {
        _rt.status_stale   = 0;
        _rt.status_prev_hb = _hb;
    }

    if (_rt.status_stale >= DEULO_MP_STATUS_STALE_MAX) {
        _rt.status_text = "Relay off";
        return;
    }

    _rt.status_text = deulo_mp_status_format(_data);
}

function deulo_mp_status_format(_data) {
    var _state = _data[$ "state"];
    if (!is_string(_state)) { _state = "idle"; }

    var _peers = _data[$ "peers"];
    if (!deulo_mp_is_number(_peers)) { _peers = 0; }
    _peers = floor(real(_peers));

    if (_state == "connected") {
        if (_peers == 1) { return "Connected (1 peer)"; }
        return "Connected (" + string(_peers) + " peers)";
    }
    if (_state == "listening")  { return (_peers > 0)
        ? ("Hosting (" + string(_peers) + ")") : "Hosting (waiting)"; }
    if (_state == "connecting") { return "Connecting..."; }
    if (_state == "error") {
        var _d = _data[$ "detail"];
        return is_string(_d) ? ("Error: " + _d) : "Error";
    }
    return "Idle";
}

function deulo_mp_cycle_row(_menu) {
    var _element = _menu.element(ANCHOR.wrap_for_local("Mode"), DEULO_MP_ROW, true)
        .set_tap_callback(deulo_mp_cycle_role, []);
    _element.text_label.set_max_width(92);

    var _value = ANCHOR.text(_element)
        .set_align(Align.RightIn, Align.Middle)
        .set_x(-7)
        .set_lut(COMMON_LUT)
        .set_max_width(58);
    _value.set_think_callback(function(_value) {
        _value.set_text(deulo_mp_role_label(deulo_mp_role()));
    }, [_value]);
}

function deulo_mp_ip_row(_menu) {
    var _element = _menu.element(ANCHOR.wrap_for_local("Host IP (Join)"), DEULO_MP_ROW, true)
        .set_tap_callback(function() {
            var _rt = __deulo_multiplayer_runtime();
            text_input_popup(
                ANCHOR.wrap_for_local("Host IP"),
                string(_rt.host_ip),
                120,
                deulo_mp_apply_ip,
                []);
        }, []);
    _element.text_label.set_max_width(70);

    var _value = ANCHOR.text(_element)
        .set_align(Align.RightIn, Align.Middle)
        .set_x(-7)
        .set_lut(COMMON_LUT)
        .set_max_width(84);
    _value.set_think_callback(function(_value) {
        _value.set_text(string(__deulo_multiplayer_runtime().host_ip));
    }, [_value]);
}

function deulo_mp_port_row(_menu) {
    var _element = _menu.element(ANCHOR.wrap_for_local("Port"), DEULO_MP_ROW, true)
        .set_tap_callback(function() {
            var _rt = __deulo_multiplayer_runtime();
            text_input_popup(
                ANCHOR.wrap_for_local("Port"),
                string(_rt.port),
                120,
                deulo_mp_apply_port,
                []);
        }, []);
    _element.text_label.set_max_width(92);

    var _value = ANCHOR.text(_element)
        .set_align(Align.RightIn, Align.Middle)
        .set_x(-7)
        .set_lut(COMMON_LUT)
        .set_max_width(58);
    _value.set_think_callback(function(_value) {
        _value.set_text(string(__deulo_multiplayer_runtime().port));
    }, [_value]);
}

function deulo_mp_interval_row(_menu) {
    var _element = _menu.element(ANCHOR.wrap_for_local("Sync interval"), DEULO_MP_ROW, true)
        .set_tap_callback(function() {
            text_input_popup(
                ANCHOR.wrap_for_local("Sync every N frames (1-30)"),
                string(deulo_mp_sync_interval()),
                120,
                deulo_mp_apply_interval,
                []);
        }, []);
    _element.text_label.set_max_width(92);

    var _value = ANCHOR.text(_element)
        .set_align(Align.RightIn, Align.Middle)
        .set_x(-7)
        .set_lut(COMMON_LUT)
        .set_max_width(58);
    _value.set_think_callback(function(_value) {
        _value.set_text(string(deulo_mp_sync_interval()));
    }, [_value]);
}

function deulo_mp_instance_row(_menu) {
    var _element = _menu.element(ANCHOR.wrap_for_local("Instance"), DEULO_MP_ROW, true)
        .set_tap_callback(deulo_mp_cycle_instance, []);
    _element.text_label.set_max_width(92);

    var _value = ANCHOR.text(_element)
        .set_align(Align.RightIn, Align.Middle)
        .set_x(-7)
        .set_lut(COMMON_LUT)
        .set_max_width(58);
    _value.set_think_callback(function(_value) {
        _value.set_text(deulo_mp_instance_label(__deulo_multiplayer_runtime().instance_id));
    }, [_value]);
}

function deulo_mp_sync_row(_menu) {
    var _element = _menu.element(ANCHOR.wrap_for_local("Sync world (Join)"), DEULO_MP_ROW, true)
        .set_tap_callback(deulo_mp_toggle_sync_world, []);
    _element.text_label.set_x(18).set_max_width(141);

    var _box = ANCHOR.sprite(_element)
        .set_x(4)
        .set_align(Align.LeftIn, Align.Middle);
    _box.set_think_callback(function(_box) {
        _box.set_sprite(deulo_mp_sync_world_enabled()
            ? spr_ui_generic_checkbox_on
            : spr_ui_generic_checkbox_off);
    }, [_box]);
}

function deulo_mp_status_row(_menu) {
    var _element = _menu.element(ANCHOR.wrap_for_local("Status"), DEULO_MP_ROW, false);
    _element.text_label.set_max_width(58);

    var _value = ANCHOR.text(_element)
        .set_align(Align.RightIn, Align.Middle)
        .set_x(-7)
        .set_lut(COMMON_LUT)
        .set_max_width(96);
    _value.set_think_callback(function(_value) {
        _value.set_text(deulo_mp_status_text());
    }, [_value]);
}

function deulo_mp_open_category() {
    var _rt   = __deulo_multiplayer_runtime();
    var _menu = _rt.menu;
    if (_menu == undefined) { return; }

    deulo_multiplayer_config_ensure_loaded();

    _menu.element(ANCHOR.wrap_for_local("Multiplayer"), DEULO_MP_ROW, false);
    _menu.element(ANCHOR.wrap_for_local("Host or join a shared world."), DEULO_MP_NOTE_ROW, false);

    deulo_mp_status_row(_menu);
    deulo_mp_instance_row(_menu);
    deulo_mp_cycle_row(_menu);
    deulo_mp_ip_row(_menu);
    deulo_mp_port_row(_menu);
    deulo_mp_sync_row(_menu);
    deulo_mp_interval_row(_menu);

    _menu.element(ANCHOR.wrap_for_local("Needs MomiMpRelay running."), DEULO_MP_NOTE_ROW, false);
    _menu.element(ANCHOR.wrap_for_local("Switching to Host/Join hard-saves."), DEULO_MP_NOTE_ROW, false);
    _menu.element(ANCHOR.wrap_for_local("Instance: use p2 for a 2nd local game."), DEULO_MP_NOTE_ROW, false);
}

function deulo_mp_on_menu_opened(_ctx) {
    if (!is_struct(_ctx)) { return; }
    if (_ctx[$ "kind"] != Menu.Settings) { return; }

    var _menu = _ctx[$ "menu"];
    if (_menu == undefined) { return; }
    if (_menu[$ "categories"] == undefined) { return; }

    var _rt = __deulo_multiplayer_runtime();
    _rt.menu = _menu;

    if (_menu.categories[$ DEULO_MP_CATEGORY] != undefined) { return; }

    try {
        _menu.categories[$ DEULO_MP_CATEGORY] = _menu.create_category(
            DEULO_MP_CATEGORY,
            deulo_mp_open_category,
            spr_ui_journal_settings_icon_gameplay);
    } catch (_err) {
        mmapi_log_warn(DEULO_MP_MOD, "could not add the tab: " + string(_err));
        mmapi_log_flush(DEULO_MP_MOD);
    }
}

function deulo_mp_on_menu_closed(_ctx) {
    if (!is_struct(_ctx)) { return; }
    if (_ctx[$ "kind"] != Menu.Settings) { return; }
    var _rt = __deulo_multiplayer_runtime();
    _rt.menu = undefined;
}

function deulo_mp_local_missing(_value, _ctx) {
    if (!is_struct(_ctx)) { return undefined; }
    if (_ctx[$ "key"] == "misc_local/" + DEULO_MP_CATEGORY) { return "Multiplayer"; }
    return undefined;
}
