global.mp_item_ctr    = 0;
global.mp_items_prev  = undefined;
global.mp_recv_pickup = {};
global.mp_picked_up   = {};

function mp_local_pid() {
    return string(ARI.name) + "|" + string(ARI.farm_name);
}

function mp_item_gid(inst) {
    return string(CURRENT_LOCATION_ID) + ":"
         + string(floor(inst.final_x)) + ":"
         + string(floor(inst.final_y)) + ":"
         + string(inst.items.count());
}

function mp_serialize_obj_item(inst) {
    var out = [];
    for (var i = 0; i < inst.items.count(); i++) {
        array_push(out, inst.items.get(i).serialize());
    }
    return out;
}

function mp_scan_items() {
    if !instance_exists(obj_ari) { return; }

    var cur = {};
    var pid = mp_local_pid();

    with obj_item {
        if self[$ "mp_gid"] == undefined {
            self.mp_gid = mp_item_gid(self);

            if global.mp_picked_up[$ self.mp_gid] != undefined {
                global.mp_picked_up[$ self.mp_gid] = undefined;
                instance_destroy(self);
            } else {
                var its = mp_serialize_obj_item(self);
                mp_emit_event({
                    k:   "isp",
                    g:   self.mp_gid,
                    x:   self.final_x,
                    y:   self.final_y,
                    its: its,
                });
                cur[$ self.mp_gid] = true;
            }
        } else if (is_string(self.mp_gid)) {
            cur[$ self.mp_gid] = true;
        }
    }

    if global.mp_items_prev != undefined {
        var pkeys = struct_get_names(global.mp_items_prev);
        for (var i = 0; i < array_length(pkeys); i++) {
            var g = pkeys[i];
            if cur[$ g] != undefined { continue; }

            if global.mp_recv_pickup[$ g] != undefined { continue; }
            mp_emit_event({ k: "ipk", g: g });
        }
    }

    global.mp_items_prev = cur;
}

function mp_items_reset_on_location_change() {
    global.mp_items_prev  = undefined;
    global.mp_recv_pickup = {};
}
