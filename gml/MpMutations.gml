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
global.mp_client_epoch = undefined;

#macro MP_EV_HISTORY 320
#macro MP_PROTOCOL_VERSION 2

// Fresh per boot/session-reset identity; invalidates stale clientSeq after a restart.
function mp_generate_client_epoch() {
    var chars = "0123456789abcdef";
    var out = "";
    for (var i = 0; i < 16; i++) {
        out += string_char_at(chars, irandom(15) + 1);
    }
    return out;
}

function mp_client_epoch() {
    if global.mp_client_epoch == undefined {
        global.mp_client_epoch = mp_generate_client_epoch();
    }
    return global.mp_client_epoch;
}

function mp_make_event_id(pid, client_seq) {
    return string(pid) + ":" + string(mp_client_epoch()) + ":" + string(client_seq);
}

function mp_grid_snapshot() {
    var snap = { nodes: {}, gk: undefined, w: undefined };
    if !instance_exists(obj_ari) { return snap; }
    if GRID == undefined { return snap; }

    var wcells = GRID.dims.x;
    var hcells = GRID.dims.y;
    var n_len  = wcells * hcells;
    var oid_arr = GRID.node_object_id;
    var par_arr = GRID.node_parent;
    var gk_arr  = GRID.node_terrain_ground_kind;
    var wt_arr  = GRID.node_terrain_is_watered;

    var out_gk = array_create(n_len, undefined);
    var out_w  = array_create(n_len, undefined);
    var nodes  = {};

    for (var yy = 0; yy < hcells; yy++) {
        for (var xx = 0; xx < wcells; xx++) {
            var ni = yy * wcells + xx;
            out_gk[ni] = gk_arr[ni];
            out_w[ni]  = wt_arr[ni];

            if oid_arr[ni] == undefined { continue; }
            var p = par_arr[ni];
            if p == undefined { continue; }

            if p.object_id == ObjectId.TurnInBox { continue; }

            var key = string(p.top_left_x) + ":" + string(p.top_left_y);
            if nodes[$ key] == undefined {
                var hp_val = p[$ "hitpoints"];
                nodes[$ key] = {
                    tlx:  p.top_left_x,
                    tly:  p.top_left_y,
                    cx:   xx,
                    cy:   yy,
                    oid:  p.object_id,
                    hp:   hp_val,
                    node: p,
                };
            }
        }
    }

    snap.nodes = nodes;
    snap.gk    = out_gk;
    snap.w     = out_w;
    return snap;
}

function mp_scan_grid() {
    if !instance_exists(obj_ari) { return; }
    if GRID == undefined { return; }

    if global.mp_grid_loc != CURRENT_LOCATION_ID {
        global.mp_grid_loc = CURRENT_LOCATION_ID;
        var initial = mp_grid_snapshot();
        global.mp_grid_prev    = initial.nodes;
        global.mp_terr_prev_gk = initial.gk;
        global.mp_terr_prev_w  = initial.w;
        mp_node_state_baseline_from(initial.nodes);
        mp_items_reset_on_location_change();
        return;
    }

    var cur = mp_grid_snapshot();
    if global.mp_grid_prev == undefined {
        global.mp_grid_prev    = cur.nodes;
        global.mp_terr_prev_gk = cur.gk;
        global.mp_terr_prev_w  = cur.w;
        mp_node_state_baseline_from(cur.nodes);
        return;
    }

    var prev_nodes = global.mp_grid_prev;
    var prev_keys = struct_get_names(prev_nodes);
    for (var i = 0; i < array_length(prev_keys); i++) {
        var k = prev_keys[i];
        if cur.nodes[$ k] == undefined {
            var p = prev_nodes[$ k];
            mp_emit_event({ k: "gone", cx: p.cx, cy: p.cy, oid: p.oid });
        }
    }

    var cur_keys = struct_get_names(cur.nodes);
    for (var i = 0; i < array_length(cur_keys); i++) {
        var k = cur_keys[i];
        var c = cur.nodes[$ k];
        var p = prev_nodes[$ k];
        if p == undefined {
            mp_emit_spawn(c);
        } else if p.oid != c.oid {

            mp_emit_event({ k: "gone",  cx: p.cx, cy: p.cy, oid: p.oid });
            mp_emit_spawn(c);
        } else if c.hp != undefined && p.hp != undefined && p.hp > c.hp {
            mp_emit_event({
                k:   "hit",
                cx:  c.cx,
                cy:  c.cy,
                oid: c.oid,
                ehp: p.hp,
                rhp: c.hp,
            });
        }
    }

    for (var i = 0; i < array_length(cur_keys); i++) {
        var cc = cur.nodes[$ cur_keys[i]];
        var np = cc.node;
        if np == undefined { continue; }
        if np[$ "inventory"] == undefined { continue; }
        var ckey = string(cc.tlx) + ":" + string(cc.tly);
        var sig  = mp_inventory_sig(np.inventory);
        var prev_sig = global.mp_chest_prev[$ ckey];
        if prev_sig != sig {
            global.mp_chest_prev[$ ckey] = sig;
            var cinv_ev = { k: "cinv", tx: cc.tlx, ty: cc.tly, oid: cc.oid, inv: np.inventory.serialize() };
            if prev_sig != undefined { cinv_ev.esig = prev_sig; }
            mp_emit_event(cinv_ev);
        }
    }

    for (var i = 0; i < array_length(cur_keys); i++) {
        var pc = cur.nodes[$ cur_keys[i]];
        var pn = pc.node;
        if pn == undefined { continue; }
        if object_id_to_object_category(pc.oid) != ObjectCategory.Crop { continue; }
        var pkey = string(pc.tlx) + ":" + string(pc.tly);
        var psig = mp_crop_sig(pn);
        var prev_crop_sig = global.mp_crop_prev[$ pkey];
        if prev_crop_sig != psig {
            global.mp_crop_prev[$ pkey] = psig;
            var cstate_ev = {
                k:  "cstate",
                tx: pc.tlx, ty: pc.tly, oid: pc.oid,
                st: pn.stage,
                dc: pn.day_count,
                rc: pn.regrow_cycle,
                mt: (pn[$ "managed_timer"] == undefined) ? -1 : pn.managed_timer,
                cf: pn.ctx,
            };
            if prev_crop_sig != undefined { cstate_ev.esig = prev_crop_sig; }
            mp_emit_event(cstate_ev);
        }
    }

    var w_cells = GRID.dims.x;
    var prev_gk = global.mp_terr_prev_gk;
    var prev_w  = global.mp_terr_prev_w;
    var n_len   = array_length(cur.gk);
    for (var ni = 0; ni < n_len; ni++) {
        var new_gk = cur.gk[ni];
        var old_gk = prev_gk[ni];
        if new_gk != old_gk {
            var cy = ni div w_cells;
            var cx = ni - cy * w_cells;
            mp_emit_event({ k: "tgk", cx: cx, cy: cy, gk: new_gk });
        }
        var new_w = cur.w[ni];
        var old_w = prev_w[ni];
        if new_w != old_w {
            var cy = ni div w_cells;
            var cx = ni - cy * w_cells;
            mp_emit_event({ k: "tw", cx: cx, cy: cy, w: new_w });
        }
    }

    global.mp_grid_prev    = cur.nodes;
    global.mp_terr_prev_gk = cur.gk;
    global.mp_terr_prev_w  = cur.w;
}

function mp_emit_event(ev) {
    global.mp_ev_seq++;
    ev.s = global.mp_ev_seq;

    ev.loc = CURRENT_LOCATION_ID;
    array_push(global.mp_ev_queue, ev);
    while (array_length(global.mp_ev_queue) > MP_EV_HISTORY) {
        array_delete(global.mp_ev_queue, 0, 1);
    }
}

function mp_emit_spawn(c) {
    if c[$ "node"] != undefined {
        var cat = object_id_to_object_category(c.oid);
        if cat == ObjectCategory.Furniture {
            var inv_list = List();
            var fobj = create_grid_object_serialization_data(c.node, inv_list);
            mp_emit_event({ k: "fspawn", obj: fobj, invs: inv_list.to_array() });
            return;
        }
        if cat == ObjectCategory.Building {
            mp_emit_bspawn(c.node);
            return;
        }
    }
    mp_emit_event({ k: "spawn", tx: c.tlx, ty: c.tly, oid: c.oid, hp: c.hp });
}

function mp_emit_bspawn(node) {
    var inv_list = List();
    var bobj = create_grid_object_serialization_data(node, inv_list);

    var dyn_data = undefined;
    if node[$ "dyn_index"] != undefined && DYNAMIC_GRIDS != undefined {
        var dg = DYNAMIC_GRIDS.get(node.dyn_index);
        if dg != undefined {
            var dblob = create_grid_serialization_data(dg);
            if dblob[$ "terrain_buffer"] != undefined {
                buffer_delete(dblob.terrain_buffer);
                dblob.terrain_buffer = undefined;
            }
            dyn_data = {
                object_list: dblob.object_list,
                inventories: dblob.inventories,
                size_x:      dblob.size_x,
                size_y:      dblob.size_y,
                location_id: dblob.location_id,
                dyn_index:   dblob.dyn_index,
            };
        }
    }

    mp_emit_event({ k: "bspawn", obj: bobj, invs: inv_list.to_array(), dyn: dyn_data });
}

function mp_inventory_sig(inv) {
    return json_stringify(inv.serialize());
}

function mp_crop_sig(node) {
    return string(node[$ "stage"]) + "|" + string(node[$ "day_count"]) + "|"
         + string(node[$ "regrow_cycle"]) + "|" + string(node[$ "managed_timer"]) + "|"
         + string(node[$ "ctx"]);
}

function mp_animal_sig(an) {
    return string(an.has_been_pat) + "|" + string(an.has_eaten)
         + "|" + string(an.has_been_outside) + "|" + string(an.heart_points)
         + "|" + string(an[$ "production_days"]);
}

function mp_node_state_baseline_from(nodes) {
    global.mp_chest_prev = {};
    global.mp_crop_prev  = {};
    var keys = struct_get_names(nodes);
    for (var i = 0; i < array_length(keys); i++) {
        var c = nodes[$ keys[i]];
        var p = c[$ "node"];
        if p == undefined { continue; }
        if p[$ "inventory"] != undefined {
            global.mp_chest_prev[$ (string(c.tlx) + ":" + string(c.tly))] = mp_inventory_sig(p.inventory);
        }
        if object_id_to_object_category(p.object_id) == ObjectCategory.Crop {
            global.mp_crop_prev[$ (string(c.tlx) + ":" + string(c.tly))] = mp_crop_sig(p);
        }
    }
}

function mp_scan_animals() {
    if !instance_exists(obj_ari) { return; }
    if GRIDS == undefined { return; }
    if GRIDS[LocationId.Farm] == undefined { return; }

    var buildings = get_buildings();
    for (var bi = 0; bi < buildings.count(); bi++) {
        var b = buildings.get(bi);
        if b == undefined { continue; }
        if b[$ "stable"] == undefined { continue; }
        var stalls = b.stable.stalls;
        var b_out  = false;
        for (var si = 0; si < stalls.count(); si++) {
            var an = stalls.get(si);
            if an == undefined { continue; }
            if !an.is_home() { b_out = true; }
            var key = string(b.top_left_x) + ":" + string(b.top_left_y) + ":" + string(an.idx);
            var sig = mp_animal_sig(an);
            if global.mp_animal_prev[$ key] == undefined {
                global.mp_animal_prev[$ key] = sig;
            } else if global.mp_animal_prev[$ key] != sig {
                var prev_animal_sig = global.mp_animal_prev[$ key];
                global.mp_animal_prev[$ key] = sig;
                mp_emit_event({
                    k: "astate",
                    btlx: b.top_left_x, btly: b.top_left_y, oid: b.object_id, idx: an.idx,
                    esig: prev_animal_sig,
                    pat: an.has_been_pat, eat: an.has_eaten, out: an.has_been_outside,
                    hpts: an.heart_points, prod: an[$ "production_days"],
                });
            }
        }

        var bkey = string(b.top_left_x) + ":" + string(b.top_left_y);
        if global.mp_bldg_out[$ bkey] == undefined {
            global.mp_bldg_out[$ bkey] = b_out;
        } else if global.mp_bldg_out[$ bkey] != b_out {
            global.mp_bldg_out[$ bkey] = b_out;
            mp_emit_event({ k: "bell", btlx: b.top_left_x, btly: b.top_left_y, oid: b.object_id, out: b_out });
        }
    }
}

function mp_apply_bell(ev) {
    with obj_farm_bell {
        if self[$ "node"] == undefined || self.node == undefined { continue; }
        if self.node.top_left_x != ev.btlx || self.node.top_left_y != ev.btly { continue; }
        if self.chain != undefined { continue; }
        try {
            if ev.out { self.bell_out(false); } else { self.bell_in(false); }
        } catch (e) {
            show_debug_message("[MOMI-MP] bell failed: " + string(e));
        }
    }
}

function mp_apply_animal_state(ev) {
    if GRIDS == undefined || GRIDS[LocationId.Farm] == undefined { return; }
    var buildings = get_buildings();
    for (var bi = 0; bi < buildings.count(); bi++) {
        var b = buildings.get(bi);
        if b == undefined { continue; }
        if b[$ "stable"] == undefined { continue; }
        if b.top_left_x != ev.btlx || b.top_left_y != ev.btly { continue; }
        if b.object_id != ev.oid { continue; }
        var stalls = b.stable.stalls;
        for (var si = 0; si < stalls.count(); si++) {
            var an = stalls.get(si);
            if an == undefined { continue; }
            if an.idx != ev.idx { continue; }

            var astate_key = string(ev.btlx) + ":" + string(ev.btly) + ":" + string(ev.idx);
            if ev[$ "esig"] != undefined {
                var astate_current_sig = mp_animal_sig(an);
                var astate_new_sig = string(ev.pat) + "|" + string(ev.eat) + "|" + string(ev.out) + "|"
                    + string(ev.hpts) + "|" + string(ev[$ "prod"]);
                if astate_current_sig == astate_new_sig {
                    global.mp_animal_prev[$ astate_key] = astate_current_sig;
                    return;
                }
                if astate_current_sig != ev.esig { return; }
            }

            an.has_been_pat     = ev.pat;
            an.has_eaten        = ev.eat;
            an.has_been_outside = ev.out;
            an.heart_points     = ev.hpts;
            if ev[$ "prod"] != undefined { an.production_days = ev.prod; }

            global.mp_animal_prev[$ astate_key] = mp_animal_sig(an);
            return;
        }
    }
}

function mp_apply_player_events(state) {
    if state[$ "evs"] == undefined { return; }
    if state[$ "location_id"] == undefined { return; }

    var pid = string(state.player_id);
    var my_pid = string(ARI.name) + "|" + string(ARI.farm_name);
    if pid == my_pid { return; }

    if GRIDS == undefined { return; }
    var fallback_loc = state.location_id;
    var evs = state.evs;

    if global.mp_evseq_by_pid[$ pid] == undefined {
        var maxs = 0;
        for (var i = 0; i < array_length(evs); i++) {
            if evs[i].s > maxs { maxs = evs[i].s; }
        }
        global.mp_evseq_by_pid[$ pid] = maxs;
        return;
    }

    var applied_current = false;
    for (var i = 0; i < array_length(evs); i++) {
        var ev = evs[i];
        if ev.s <= global.mp_evseq_by_pid[$ pid] { continue; }
        global.mp_evseq_by_pid[$ pid] = ev.s;

        if ev.k == "astate" { mp_apply_animal_state(ev); continue; }
        if ev.k == "bell"   { mp_apply_bell(ev); continue; }

        var eloc = (ev[$ "loc"] != undefined) ? ev.loc : fallback_loc;
        if eloc < 0 || eloc >= array_length(GRIDS) { continue; }
        var egrid = GRIDS[eloc];
        if egrid == undefined { continue; }
        var e_is_current = (eloc == CURRENT_LOCATION_ID);

        var did = mp_apply_event(egrid, ev, e_is_current);
        if e_is_current && did { applied_current = true; }
    }

    if applied_current {
        var post = mp_grid_snapshot();
        global.mp_grid_prev    = post.nodes;
        global.mp_terr_prev_gk = post.gk;
        global.mp_terr_prev_w  = post.w;
    }
}

function mp_apply_event(grid, ev, is_current) {
    if grid == undefined { return false; }
    var kind = ev.k;

    if ev[$ "oid"] != undefined && ev.oid == ObjectId.TurnInBox { return false; }

    if kind == "hit" {
        if ev[$ "ehp"] == undefined || ev[$ "rhp"] == undefined { return false; }
        if ev.ehp < 0 || ev.rhp < 0 || ev.rhp >= ev.ehp { return false; }
        var ni = grid.try_node_index_for_cell(ev.cx, ev.cy);
        if ni == undefined { return false; }
        if grid.node_object_id[ni] == undefined { return false; }
        var node = grid.node_parent[ni];
        if node == undefined { return false; }

        if node.object_id != ev.oid { return false; }
        if node[$ "hitpoints"] == undefined { return false; }
        if node.hitpoints == ev.rhp { return true; }
        if node.hitpoints != ev.ehp { return false; }
        node.hitpoints = ev.rhp;
        return true;
    }

    if kind == "gone" {
        var ni = grid.try_node_index_for_cell(ev.cx, ev.cy);
        if ni == undefined { return false; }
        if grid.node_object_id[ni] == undefined { return false; }
        var node = grid.node_parent[ni];
        if node == undefined { return false; }

        if node.object_id != ev.oid { return false; }
        erase_object_node(grid, ni);
        return true;
    }

    if kind == "spawn" {
        var ni = grid.try_node_index_for_cell(ev.tx, ev.ty);
        if ni == undefined { return false; }

        if grid.node_object_id[ni] != undefined { return false; }
        var new_node = grid.write_node(ev.tx, ev.ty, ev.oid);
        if new_node != undefined && new_node[$ "hitpoints"] != undefined && ev[$ "hp"] != undefined {
            new_node.hitpoints = ev.hp;
        }
        return true;
    }

    if kind == "fspawn" {
        if ev[$ "obj" ] == undefined { return false; }
        var ni = grid.try_node_index_for_cell(ev.obj.top_left_x, ev.obj.top_left_y);
        if ni == undefined { return false; }
        if grid.node_object_id[ni] != undefined { return false; }
        try {
            var invs = ev[$ "invs"] != undefined ? ev.invs : [];
            for (var ii = 0; ii < array_length(invs); ii++) {
                var arr = invs[ii];
                var inv = Inventory(array_length(arr));
                inv.deserialize(arr);
                invs[ii] = inv;
            }
            grid.load_objects([ev.obj], invs);
        } catch (e) {
            show_debug_message("[MOMI-MP] fspawn failed: " + string(e));
            return false;
        }
        return true;
    }

    if kind == "bspawn" {
        if ev[$ "obj"] == undefined { return false; }
        var ni = grid.try_node_index_for_cell(ev.obj.top_left_x, ev.obj.top_left_y);
        if ni == undefined { return false; }
        if grid.node_object_id[ni] != undefined { return false; }
        if DYNAMIC_GRIDS == undefined { return false; }
        try {

            if ev[$ "dyn"] != undefined && ev.dyn != undefined {
                var dloc    = string_to_location_id(ev.dyn.location_id);
                var new_dyn = DYNAMIC_GRIDS.count();
                var dg      = initialize_grid(dloc, new_dyn);
                DYNAMIC_GRIDS.push(dg);
                dg.load(ev.dyn);
                dg.is_setup = true;
                ev.obj.dyn_index = new_dyn;
            }

            var binvs = ev[$ "invs"] != undefined ? ev.invs : [];
            for (var bi = 0; bi < array_length(binvs); bi++) {
                var barr = binvs[bi];
                var binv = Inventory(array_length(barr));
                binv.deserialize(barr);
                binvs[bi] = binv;
            }
            grid.load_objects([ev.obj], binvs);
            global.__buildings = undefined;
        } catch (e) {
            show_debug_message("[MOMI-MP] bspawn failed: " + string(e));
            return false;
        }
        return true;
    }

    if kind == "cinv" {
        if ev[$ "inv"] == undefined { return false; }
        var ni = grid.try_node_index_for_cell(ev.tx, ev.ty);
        if ni == undefined { return false; }
        var node = grid.node_parent[ni];
        if node == undefined { return false; }
        if node[$ "inventory"] == undefined { return false; }
        if node.object_id != ev.oid { return false; }

        if ev[$ "esig"] != undefined {
            var cinv_current_sig = mp_inventory_sig(node.inventory);
            var cinv_new_sig = json_stringify(ev.inv);
            if cinv_current_sig == cinv_new_sig {
                if is_current { global.mp_chest_prev[$ (string(ev.tx) + ":" + string(ev.ty))] = cinv_current_sig; }
                return false;
            }
            if cinv_current_sig != ev.esig { return false; }
        }

        try {
            node.inventory.deserialize(ev.inv);

            for (var si = 0; si < node.inventory.size(); si++) {
                var sl = node.inventory.slot(si);
                if sl.item == undefined { sl.count = 0; }
            }

            if is_current {
                global.mp_chest_prev[$ (string(ev.tx) + ":" + string(ev.ty))] = mp_inventory_sig(node.inventory);
            }
        } catch (e) {
            show_debug_message("[MOMI-MP] cinv failed: " + string(e));
        }
        return false;
    }

    if kind == "cstate" {
        var ni = grid.try_node_index_for_cell(ev.tx, ev.ty);
        if ni == undefined { return false; }
        var node = grid.node_parent[ni];
        if node == undefined { return false; }
        if node.object_id != ev.oid { return false; }

        if ev[$ "esig"] != undefined {
            var cstate_current_sig = mp_crop_sig(node);
            var cstate_new_sig = string(ev.st) + "|" + string(ev.dc) + "|" + string(ev.rc) + "|"
                + string((ev.mt == -1) ? undefined : ev.mt) + "|" + string(ev.cf);
            if cstate_current_sig == cstate_new_sig {
                if is_current { global.mp_crop_prev[$ (string(ev.tx) + ":" + string(ev.ty))] = cstate_current_sig; }
                return false;
            }
            if cstate_current_sig != ev.esig { return false; }
        }

        node.stage         = ev.st;
        node.day_count     = ev.dc;
        node.regrow_cycle  = ev.rc;
        node.managed_timer = (ev.mt == -1) ? undefined : ev.mt;
        node.ctx           = ev.cf;

        if is_current && node[$ "renderer"] != undefined && instance_exists(node.renderer) {
            try {
                var cspr;
                if has_flag(node.ctx, CropFlag.MANAGED) && node.managed_timer != undefined {
                    cspr = node.prototype.managed_regrow_sprite;
                } else {
                    var cst = clamp(node.stage, 0, array_length(node.prototype.sprites) - 1);
                    cspr = node.prototype.sprites[cst];
                }
                node.renderer.set_sprite(cspr);
            } catch (e) {
                show_debug_message("[MOMI-MP] cstate sprite failed: " + string(e));
            }
        }

        if is_current {
            global.mp_crop_prev[$ (string(ev.tx) + ":" + string(ev.ty))] = mp_crop_sig(node);
        }
        return false;
    }

    if kind == "tgk" {
        var ni = grid.try_node_index_for_cell(ev.cx, ev.cy);
        if ni == undefined { return false; }

        grid.write_ground(ev.cx, ev.cy, ev.gk);
        return true;
    }

    if kind == "tw" {
        var ni = grid.try_node_index_for_cell(ev.cx, ev.cy);
        if ni == undefined { return false; }
        grid.node_terrain_is_watered[ni] = ev.w;

        if is_current {
            grid.update_tilemap_for_node((ev.cx div 2) * 2, (ev.cy div 2) * 2);
        }
        return true;
    }

    if kind == "isp" {
        if !is_current {

            if global.mp_picked_up[$ ev.g] != undefined { return false; }
            var llst = grid.lost_items;
            for (var li = 0; li < llst.count(); li++) {
                var le = llst.get(li);
                if floor(le.x) == floor(ev.x) && floor(le.y) == floor(ev.y) { return false; }
            }
            var abs_list = List();
            for (var ai = 0; ai < array_length(ev.its); ai++) {
                abs_list.push(deserialize_live_item(ev.its[ai]));
            }
            if abs_list.count() == 0 { return false; }
            llst.push({ x: ev.x, y: ev.y, items: abs_list });
            return false;
        }
        var to_find = ev.g;
        var already = false;
        with obj_item {

            if (self[$ "mp_gid"] != undefined && self.mp_gid == to_find)
               || (floor(self.final_x) == floor(ev.x) && floor(self.final_y) == floor(ev.y)) {
                already = true;
            }
        }
        if already { return false; }

        var live_list = List();
        for (var i = 0; i < array_length(ev.its); i++) {
            live_list.push(deserialize_live_item(ev.its[i]));
        }
        if live_list.count() == 0 { return false; }

        var inst = instance_create_layer(ev.x, ev.y, "Instances", obj_item);
        inst.mp_gid  = ev.g;
        inst.final_x = ev.x;
        inst.final_y = ev.y;
        inst.setup(live_list);
        return false;
    }

    if kind == "ipk" {

        if (ev[$ "g"] == undefined || !is_string(ev.g)) {
            return false;
        }

        if is_current {

            var found = undefined;
            with obj_item {
                if self[$ "mp_gid"] != undefined && self.mp_gid == ev.g {
                    found = self;
                }
            }
            if (found != undefined && instance_exists(found)) { instance_destroy(found); }

            global.mp_recv_pickup[$ ev.g] = true;
        } else {

            global.mp_picked_up[$ ev.g] = true;
        }
        return false;
    }

    return false;
}
