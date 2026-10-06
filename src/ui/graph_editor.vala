using Gtk;

namespace Singularity.Apps.Keyframe {

    public class GraphEditor : DrawingArea {
        public Document doc;
        public bool speed_mode = false;
        private double t_min = 0;
        private double t_max = 5;
        private double v_min = -100;
        private double v_max = 100;
        private string drag = "";
        private Keyframe? drag_key = null;
        private int drag_seg = -1;
        private bool drag_out = false;
        private double press_x;
        private double press_y;
        private double key_t0;
        private double[] key_v0;
        private const int MARGIN = 28;
        private double[,] dim_colors = { { 0.95, 0.35, 0.35 }, { 0.35, 0.85, 0.4 }, { 0.35, 0.6, 1 }, { 0.9, 0.9, 0.9 } };

        public GraphEditor (Document doc) {
            this.doc = doc;
            hexpand = true;
            vexpand = true;
            set_draw_func (draw);
            add_css_class ("keyframe-graph");
            var click = new GestureClick ();
            click.pressed.connect (on_press);
            add_controller (click);
            var dr = new GestureDrag ();
            dr.drag_update.connect (on_drag);
            dr.drag_end.connect ((x, y) => {
                if (drag == "key" || drag == "handle") {
                    doc.end_edit ();
                    doc.content_changed ();
                }
                drag = "";
            });
            add_controller (dr);
            var scroll = new EventControllerScroll (EventControllerScrollFlags.VERTICAL);
            scroll.scroll.connect ((dx, dy) => {
                double f = dy < 0 ? 0.85 : 1 / 0.85;
                double c = (t_min + t_max) / 2, half = (t_max - t_min) / 2 * f;
                t_min = c - half;
                t_max = c + half;
                queue_draw ();
                return true;
            });
            add_controller (scroll);
            doc.selection_changed.connect (() => {
                fit ();
                queue_draw ();
            });
            doc.content_changed.connect (queue_draw);
            doc.time_changed.connect (queue_draw);
        }

        public bool has_curve () {
            var p = property ();
            return p != null && p.owner_layer () != null && p.dims > 0 && p.kind != PropKind.PATH;
        }

        public Property? property () {
            return doc.active_property;
        }

        private Layer? layer () {
            var p = property ();
            return p != null ? p.owner_layer () : null;
        }

        public void fit () {
            var p = property ();
            var l = layer ();
            if (p == null || l == null || doc.comp == null || p.dims == 0) return;
            if (p.keys.size >= 2) {
                t_min = l.comp_time (p.keys[0].time);
                t_max = l.comp_time (p.keys[p.keys.size - 1].time);
            } else {
                t_min = 0;
                t_max = doc.comp.duration;
            }
            double pad = (t_max - t_min) * 0.08 + 0.05;
            t_min -= pad;
            t_max += pad;
            v_min = double.MAX;
            v_max = -double.MAX;
            int n = 200;
            for (int i = 0; i <= n; i++) {
                double t = t_min + (t_max - t_min) * i / n;
                double lt = l.layer_time (t);
                if (speed_mode) {
                    double s = p.speed_at (lt);
                    v_min = double.min (v_min, s);
                    v_max = double.max (v_max, s);
                } else {
                    var v = p.value_at (lt);
                    for (int d = 0; d < int.min (p.dims, 3); d++) {
                        v_min = double.min (v_min, v[d]);
                        v_max = double.max (v_max, v[d]);
                    }
                }
            }
            if (speed_mode) v_min = double.min (0, v_min);
            double vp = (v_max - v_min) * 0.12 + 1e-3;
            if (v_max - v_min < 1e-6) vp = double.max (1, v_max.abs () * 0.2);
            v_min -= vp;
            v_max += vp;
            queue_draw ();
        }

        private double tx (double t) {
            return MARGIN + (t - t_min) / (t_max - t_min) * (get_width () - MARGIN * 2);
        }

        private double vy (double v) {
            return get_height () - MARGIN - (v - v_min) / (v_max - v_min) * (get_height () - MARGIN * 2);
        }

        private double xt (double x) {
            return t_min + (x - MARGIN) / (get_width () - MARGIN * 2) * (t_max - t_min);
        }

        private double yv (double y) {
            return v_min + (get_height () - MARGIN - y) / (get_height () - MARGIN * 2) * (v_max - v_min);
        }

        private void color (Cairo.Context cr, string name, double alpha) {
            Gdk.RGBA c;
            if (get_style_context ().lookup_color (name, out c)) cr.set_source_rgba (c.red, c.green, c.blue, c.alpha * alpha);
            else cr.set_source_rgba (0.85, 0.85, 0.85, alpha);
        }

        private void draw (DrawingArea a, Cairo.Context cr, int w, int h) {
            color (cr, "view_bg_color", 1);
            cr.paint ();
            var p = property ();
            var l = layer ();
            var layout = create_pango_layout ("");
            if (!has_curve ()) {
                return;
            }
            color (cr, "window_fg_color", 0.08);
            cr.set_line_width (1);
            for (int i = 0; i <= 4; i++) {
                double y = MARGIN + (h - MARGIN * 2) * i / 4.0;
                cr.move_to (MARGIN, y);
                cr.line_to (w - MARGIN, y);
                cr.stroke ();
                layout.set_text ("%.1f".printf (yv (y)), -1);
                color (cr, "window_fg_color", 0.5);
                cr.move_to (2, y - 8);
                Pango.cairo_show_layout (cr, layout);
                color (cr, "window_fg_color", 0.08);
            }
            layout.set_text ("%s  %s".printf (p.name, speed_mode ? _("Speed Graph") : _("Value Graph")), -1);
            color (cr, "window_fg_color", 0.8);
            cr.move_to (MARGIN, 4);
            Pango.cairo_show_layout (cr, layout);
            int n = int.max (100, w);
            if (speed_mode) {
                cr.set_source_rgba (0.95, 0.8, 0.3, 1);
                cr.set_line_width (1.6);
                for (int i = 0; i <= n; i++) {
                    double t = t_min + (t_max - t_min) * i / n;
                    double s = p.speed_at (l.layer_time (t));
                    if (i == 0) cr.move_to (tx (t), vy (s));
                    else cr.line_to (tx (t), vy (s));
                }
                cr.stroke ();
            } else {
                for (int d = 0; d < int.min (p.dims, 4); d++) {
                    if (p.kind == PropKind.COLOR) cr.set_source_rgba (dim_colors[d, 0], dim_colors[d, 1], dim_colors[d, 2], 1);
                    else cr.set_source_rgba (dim_colors[d, 0], dim_colors[d, 1], dim_colors[d, 2], d == 0 ? 1 : 0.8);
                    if (!l.three_d && (p.key == "position" || p.key == "anchor" || p.key == "scale") && d == 2) continue;
                    cr.set_line_width (1.6);
                    for (int i = 0; i <= n; i++) {
                        double t = t_min + (t_max - t_min) * i / n;
                        var v = p.value_at (l.layer_time (t));
                        if (i == 0) cr.move_to (tx (t), vy (v[d]));
                        else cr.line_to (tx (t), vy (v[d]));
                    }
                    cr.stroke ();
                }
            }
            var times = p.effective_times ();
            for (int k = 0; k < p.keys.size; k++) {
                var key = p.keys[k];
                double kt = l.comp_time (times[k]);
                double kv = speed_mode ? p.speed_at (times[k] + (k == p.keys.size - 1 ? -1e-3 : 1e-3)) : key.value[0];
                if (k < p.keys.size - 1 && (key.out_interp == Interp.BEZIER || p.keys[k + 1].in_interp == Interp.BEZIER)) draw_handles (cr, p, l, k, times);
                bool sel = doc.selected_keys.contains (key);
                cr.set_source_rgba (sel ? 1 : 0.9, sel ? 0.85 : 0.9, sel ? 0.25 : 0.9, 1);
                cr.rectangle (tx (kt) - 4, vy (kv) - 4, 8, 8);
                cr.fill ();
            }
            cr.set_source_rgba (0.93, 0.33, 0.25, 1);
            cr.move_to (tx (doc.time), MARGIN);
            cr.line_to (tx (doc.time), h - MARGIN);
            cr.stroke ();
        }

        private void handle_points (Property p, Layer l, int s, Gee.List<double?> times, out double hx1, out double hy1, out double hx2, out double hy2) {
            double x1, y1, x2, y2;
            p.segment_ease (s, times, out x1, out y1, out x2, out y2);
            double t0 = l.comp_time (times[s]), t1 = l.comp_time (times[s + 1]);
            double dt = t1 - t0;
            if (speed_mode) {
                double dv = p.dims == 1 ? (p.keys[s + 1].value[0] - p.keys[s].value[0]).abs () : seg_length (p, s);
                double sp1 = x1 > 1e-6 ? y1 / x1 * dv / dt : 0;
                double sp2 = (1 - x2) > 1e-6 ? (1 - y2) / (1 - x2) * dv / dt : 0;
                hx1 = t0 + x1 * dt;
                hy1 = sp1;
                hx2 = t0 + x2 * dt;
                hy2 = sp2;
                return;
            }
            double v0 = p.keys[s].value[0], v1 = p.keys[s + 1].value[0];
            hx1 = t0 + x1 * dt;
            hy1 = v0 + y1 * (v1 - v0);
            hx2 = t0 + x2 * dt;
            hy2 = v0 + y2 * (v1 - v0);
        }

        private double seg_length (Property p, int s) {
            double d = 0;
            for (int c = 0; c < p.dims; c++) d += Math.pow (p.keys[s + 1].value[c] - p.keys[s].value[c], 2);
            return Math.sqrt (d);
        }

        private void draw_handles (Cairo.Context cr, Property p, Layer l, int s, Gee.List<double?> times) {
            double hx1, hy1, hx2, hy2;
            handle_points (p, l, s, times, out hx1, out hy1, out hx2, out hy2);
            double t0 = l.comp_time (times[s]), t1 = l.comp_time (times[s + 1]);
            double a0 = speed_mode ? hy1 : p.keys[s].value[0];
            double a1 = speed_mode ? hy2 : p.keys[s + 1].value[0];
            cr.set_source_rgba (0.95, 0.8, 0.3, 0.9);
            cr.set_line_width (1);
            if (p.keys[s].out_interp == Interp.BEZIER) {
                cr.move_to (tx (t0), vy (a0));
                cr.line_to (tx (hx1), vy (hy1));
                cr.stroke ();
                cr.arc (tx (hx1), vy (hy1), 3.5, 0, Math.PI * 2);
                cr.fill ();
            }
            if (p.keys[s + 1].in_interp == Interp.BEZIER) {
                cr.move_to (tx (t1), vy (a1));
                cr.line_to (tx (hx2), vy (hy2));
                cr.stroke ();
                cr.arc (tx (hx2), vy (hy2), 3.5, 0, Math.PI * 2);
                cr.fill ();
            }
        }

        private void on_press (Gesture g, int n, double x, double y) {
            press_x = x;
            press_y = y;
            drag = "";
            var p = property ();
            var l = layer ();
            if (p == null || l == null || p.dims == 0) return;
            var times = p.effective_times ();
            for (int s = 0; s < p.keys.size - 1; s++) {
                double hx1, hy1, hx2, hy2;
                handle_points (p, l, s, times, out hx1, out hy1, out hx2, out hy2);
                if (p.keys[s].out_interp == Interp.BEZIER && Math.hypot (tx (hx1) - x, vy (hy1) - y) < 7) {
                    drag = "handle";
                    drag_seg = s;
                    drag_out = true;
                    doc.begin_edit (_("Edit Easing"));
                    return;
                }
                if (p.keys[s + 1].in_interp == Interp.BEZIER && Math.hypot (tx (hx2) - x, vy (hy2) - y) < 7) {
                    drag = "handle";
                    drag_seg = s;
                    drag_out = false;
                    doc.begin_edit (_("Edit Easing"));
                    return;
                }
            }
            for (int k = 0; k < p.keys.size; k++) {
                double kt = l.comp_time (times[k]);
                double kv = speed_mode ? p.speed_at (times[k] + (k == p.keys.size - 1 ? -1e-3 : 1e-3)) : p.keys[k].value[0];
                if (Math.hypot (tx (kt) - x, vy (kv) - y) < 7) {
                    var st = ((GestureClick) g).get_current_event_state ();
                    doc.select_key (p, p.keys[k], (st & Gdk.ModifierType.SHIFT_MASK) != 0);
                    if (!speed_mode) {
                        drag = "key";
                        drag_key = p.keys[k];
                        key_t0 = drag_key.time;
                        key_v0 = drag_key.value;
                        doc.begin_edit (_("Move Keyframe"));
                    }
                    return;
                }
            }
            doc.seek (xt (x));
        }

        private void on_drag (double dx, double dy) {
            var p = property ();
            var l = layer ();
            if (p == null || l == null || doc.comp == null) return;
            double x = press_x + dx, y = press_y + dy;
            if (drag == "key") {
                double fps = doc.comp.fps;
                double nt = Math.round (l.comp_time (key_t0) * fps + dx / (get_width () - MARGIN * 2) * (t_max - t_min) * fps) / fps;
                drag_key.time = l.layer_time (nt);
                var nv = key_v0;
                if (p.dims == 1) nv = { yv (y) };
                drag_key.value = p.clamp_value (nv);
                p.sort_keys ();
                p.touch ();
                queue_draw ();
            } else if (drag == "handle") {
                var times = p.effective_times ();
                int s = drag_seg;
                double t0 = l.comp_time (times[s]), t1 = l.comp_time (times[s + 1]);
                double dt = t1 - t0;
                double u = ((xt (x) - t0) / dt).clamp (0, 1);
                if (speed_mode) {
                    double dv = p.dims == 1 ? (p.keys[s + 1].value[0] - p.keys[s].value[0]).abs () : seg_length (p, s);
                    double sp = yv (y);
                    if (drag_out) {
                        double infl = u.clamp (0.01, 1);
                        p.keys[s].ease_out_x = infl;
                        p.keys[s].ease_out_y = dv > 1e-9 ? sp * infl * dt / dv : 0;
                        p.keys[s].auto_bezier = false;
                    } else {
                        double infl = (1 - u).clamp (0.01, 1);
                        p.keys[s + 1].ease_in_x = 1 - infl;
                        p.keys[s + 1].ease_in_y = dv > 1e-9 ? 1 - sp * infl * dt / dv : 1;
                        p.keys[s + 1].auto_bezier = false;
                    }
                } else {
                    double v0 = p.keys[s].value[0], v1 = p.keys[s + 1].value[0];
                    double ny = (v1 - v0).abs () > 1e-12 ? (yv (y) - v0) / (v1 - v0) : (drag_out ? 0 : 1);
                    if (drag_out) {
                        p.keys[s].ease_out_x = u;
                        p.keys[s].ease_out_y = ny;
                        p.keys[s].auto_bezier = false;
                    } else {
                        p.keys[s + 1].ease_in_x = u;
                        p.keys[s + 1].ease_in_y = ny;
                        p.keys[s + 1].auto_bezier = false;
                    }
                }
                p.touch ();
                queue_draw ();
            }
        }
    }
}
