object_create("obj_mp_ghost", undefined, {
    sprite_index: spr_npc_mask,
    create: function() {
        mask_index = spr_npc_mask;
        z = 0;
        self.par = new PlayerAnimationRuntime();
        self.par.cardinal = Cardinal.South;

        self.par.set_animation(AnimationName.Idle);
        self.par_offset           = obj_ari.par_offset;
        self.default_par_offset   = obj_ari.default_par_offset;
        self.default_par_anim_spd = obj_ari.default_par_anim_spd;
        self.par_anim_spd         = self.default_par_anim_spd;
        self.cardinal             = Cardinal.South;
        self.mp_player_id         = "";
        self.mp_appearance_key    = "";
        self.mp_applied_assets    = [];
        self.mp_current_animation = AnimationName.Idle;
        self.mp_last_update       = 0;
        self.mp_liveness_seq      = -1;

        self.mp_buf               = [];
        self.mp_last_i            = -1;
        self.mp_play              = -1;

        self.mp_last_ma           = -1;
        self.mp_last_att          = -1;
        self.mp_held_key          = "";
        self.mp_remote_ba         = -1;
        self.mp_last_evseq        = undefined;
        self.mp_render_broken     = false;
        self.mp_render_fails      = 0;
        self.mp_use_offscreen     = (self.par[$ "render_offscreen"] != undefined);
        depth = get_instance_depth(self.y);
    },
    step: function() {

        self.mp_last_update++;
        if self.mp_last_update > 180 {
            instance_destroy();
            return;
        }

        var moved = false;
        var cur_c = self.cardinal;
        var play_anim = undefined;
        var n = array_length(self.mp_buf);

        if n > 0 {
            var latest_i = self.mp_buf[n - 1].i;
            var oldest_i = self.mp_buf[0].i;

            if self.mp_play < 0 {
                self.mp_play = latest_i - MP_TARGET_LAG;
                if self.mp_play < oldest_i { self.mp_play = oldest_i; }
            }

            var lag  = latest_i - self.mp_play;
            var rate = 1 + clamp((lag - MP_TARGET_LAG) * 0.02, -0.2, 0.2);
            self.mp_play += rate;
            if self.mp_play > latest_i { self.mp_play = latest_i; }
            if self.mp_play < oldest_i { self.mp_play = oldest_i; }

            var a = self.mp_buf[0];
            var b = self.mp_buf[n - 1];
            for (var k = 0; k < n - 1; k++) {
                if self.mp_buf[k].i <= self.mp_play && self.mp_buf[k + 1].i >= self.mp_play {
                    a = self.mp_buf[k];
                    b = self.mp_buf[k + 1];
                    break;
                }
            }
            var span = b.i - a.i;
            var t = (span > 0) ? (self.mp_play - a.i) / span : 0;

            var nx = lerp(a.x, b.x, t);
            var ny = lerp(a.y, b.y, t);
            var nz = lerp(a.z, b.z, t);
            if abs(nx - self.x) > 0.5 || abs(ny - self.y) > 0.5 { moved = true; }
            self.x = nx;
            self.y = ny;
            self.z = nz;
            cur_c  = (t < 0.5) ? a.c : b.c;
            play_anim = (t < 0.5) ? a[$ "an"] : b[$ "an"];

            var cutoff = floor(self.mp_play) - 2;
            while (array_length(self.mp_buf) > 2 && self.mp_buf[0].i < cutoff) {
                array_delete(self.mp_buf, 0, 1);
            }
        }
        self.depth = get_instance_depth(self.y);

        if instance_exists(obj_ari) {
            self.par_offset           = obj_ari.par_offset;
            self.default_par_offset   = obj_ari.default_par_offset;
            self.default_par_anim_spd = obj_ari.default_par_anim_spd;

            var ci = floor(cur_c);
            var card = Cardinal.East;
            if ci == 1 { card = Cardinal.North; }
            if ci == 2 { card = Cardinal.West;  }
            if ci == 3 { card = Cardinal.South; }
            if self.cardinal != card {
                self.cardinal = card;
                self.par.set_cardinal(card);
            }

            var rba = play_anim;
            if (rba == undefined) { rba = self.mp_remote_ba; }
            var is_move = (rba == -1
                        || rba == undefined
                        || rba == AnimationName.Idle
                        || rba == AnimationName.Walk
                        || rba == AnimationName.Run);
            var new_anim = is_move
                ? (moved ? AnimationName.Walk : AnimationName.Idle)
                : rba;
            if self.mp_current_animation != new_anim {
                self.par.set_animation(new_anim);
                self.mp_current_animation = new_anim;
            }
            self.par.animate(obj_ari.par_anim_spd);
        }
    },
    draw: function() {

        if !instance_exists(obj_ari) { return; }

        if self.mp_render_broken { return; }

        try {
            var ratio  = DISPLAY.asset_resize();
            var draw_x = floor((self.x + obj_ari.par_offset.x) * ratio) / ratio;
            var draw_y = floor((self.y + obj_ari.par_offset.y + self.z) * ratio) / ratio;
            if self.mp_use_offscreen {
                self.par.render_offscreen();
                self.par.draw(draw_x, draw_y);
                obj_ari.par.render_offscreen();
            } else {
                self.par.draw(draw_x, draw_y, self.depth);
            }
            self.mp_render_fails = 0;
        } catch (_e) {
            surface_reset_target();
            if self.mp_use_offscreen { try { obj_ari.par.render_offscreen(); } catch (_e2) {} }
            self.mp_render_fails += 1;
            if self.mp_render_fails == 1 {
                show_debug_message("[MOMI-MP] ghost render failed: " + string(_e));
            }
            if self.mp_render_fails >= 10 {
                self.mp_render_broken = true;
                show_debug_message("[MOMI-MP] ghost rendering disabled this session.");
            }
        }
    },
});
