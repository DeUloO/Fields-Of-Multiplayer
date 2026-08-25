#macro obj_mp_ghost object("obj_mp_ghost")

function __deulo_multiplayer_runtime() {
    if (global[$ "__deulo_multiplayer"] == undefined) {
        global.__deulo_multiplayer = {
            registered:    undefined,
            hooks:         undefined,
            installed:     undefined,
            fc:            0,
            role:          "off",
            config:        undefined,
            config_loaded: false,
            host_ip:       "127.0.0.1",
            port:          7777,
            control_seq:   0,
            instance_id:   "",
            dir_cache:      undefined,
            dir_cache_id:   undefined,
            menu:          undefined,
            status_text:   undefined,
            status_prev_hb: undefined,
            status_stale:  0,
            status_fc:     0,
        };
    }
    return global.__deulo_multiplayer;
}

function deulo_multiplayer_register() {
    var _rt = __deulo_multiplayer_runtime();
    if (_rt.registered != undefined) { return; }
    _rt.registered = true;
    mmapi_register(deulo_multiplayer_frame);
}

function deulo_multiplayer_install() {
    var _rt = __deulo_multiplayer_runtime();
    if (_rt.installed != undefined) { return; }
    _rt.installed = true;
    deulo_multiplayer_config_ensure_loaded();
    deulo_mp_write_control();
}

function deulo_multiplayer_frame() {
    var _rt = __deulo_multiplayer_runtime();
    if (deulo_mp_role() == "off") { return; }

    mp_sample();
    _rt.fc += 1;
    if (_rt.fc % deulo_mp_sync_interval() == 0) {
        mp_tick();
        mp_world_tick();
    }
}

function deulo_multiplayer_register_callbacks() {
    var _rt = __deulo_multiplayer_runtime();
    if (_rt.hooks != undefined) { return; }
    _rt.hooks = true;

    mmapi_filter("local.missing", deulo_mp_local_missing);
    mmapi_on("ui.menu_opened", deulo_mp_on_menu_opened);
    mmapi_on("ui.menu_closed", deulo_mp_on_menu_closed);
    mmapi_register(deulo_multiplayer_install);
}

mmapi_mod_declare("deulo_multiplayer", "0.3.3");
deulo_multiplayer_register();
deulo_multiplayer_register_callbacks();
