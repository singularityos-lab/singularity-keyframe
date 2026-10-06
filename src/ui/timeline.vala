using Gtk;

namespace Singularity.Apps.Keyframe {

    public enum RowKind {
        LAYER,
        GROUP,
        PROPERTY
    }

    public class TimelineRow {
        public RowKind kind;
        public Layer layer;
        public PropGroup? group;
        public Property? prop;
        public int depth;
        public double y;

        public TimelineRow (RowKind kind, Layer layer, int depth) {
            this.kind = kind;
            this.layer = layer;
            this.depth = depth;
        }
    }

    public class AudioPeaks {
        public float[] values = {};
        public double duration = 0;
        public bool ready = false;
    }

    public class Timeline : DrawingArea {
        public const int ROW_HEIGHT = 24;
        public const int HEADER = 34;
        public int left_width = 590;
        public const int LEFT_MIN = 460;
        public const int LEFT_MAX = 900;
        private int user_left = -1;
        private int left0 = 0;
        public Document doc;
        public double px_per_sec = 120;
        public double scroll_time = 0;
        public double scroll_y = 0;
        public bool only_animated = false;
        public Gee.ArrayList<TimelineRow> rows = new Gee.ArrayList<TimelineRow> ();
        private Gee.HashSet<string> expanded = new Gee.HashSet<string> ();
        private string drag = "";
        private double press_x;
        private double press_y;
        private TimelineRow? drag_row = null;
        private double drag_value0 = 0;
        private double[] drag_vec0 = {};
        private Gee.HashMap<Keyframe, double?> key_start = new Gee.HashMap<Keyframe, double?> ();
        private double layer_in0;
        private double layer_out0;
        private double layer_start0;
        private double box_x0;
        private double box_y0;
        private double box_x1;
        private double box_y1;
        private Pango.Layout? text_layout = null;
        private Gee.HashMap<string, AudioPeaks> peaks = new Gee.HashMap<string, AudioPeaks> ();
        public static double[,] label_colors = {
            { 0.55, 0.55, 0.58 }, { 0.84, 0.32, 0.32 }, { 0.93, 0.76, 0.27 }, { 0.38, 0.72, 0.89 }, { 0.89, 0.53, 0.75 },
            { 0.62, 0.53, 0.93 }, { 0.91, 0.62, 0.38 }, { 0.47, 0.77, 0.47 }, { 0.31, 0.53, 0.89 }, { 0.36, 0.78, 0.71 }
        };

        public signal void request_expression (Property p);
        public signal void request_layer_menu (Layer l, double x, double y);
        public signal void request_key_menu (double x, double y);
        public signal void request_value_edit (Property p, double x, double y);
        public signal void request_parent_menu (Layer l, double x, double y);
        public signal void request_blend_menu (Layer l, double x, double y);
        public signal void request_mask_menu (PropGroup mask, double x, double y);
        public signal void request_rename (Layer l);
        public signal void request_key_dialog (Property p, Keyframe k);

        public Timeline (Document doc) {
            this.doc = doc;
            hexpand = true;
            vexpand = true;
            focusable = true;
            set_draw_func (draw);
            add_css_class ("keyframe-timeline");
            var click = new GestureClick ();
            click.set_button (0);
            click.pressed.connect (on_press);
            add_controller (click);
            var motion = new EventControllerMotion ();
            motion.motion.connect ((mx, my) => set_cursor_from_name ((mx - left_width).abs () <= 4 || drag == "divider" ? "col-resize" : null));
            add_controller (motion);
            var dr = new GestureDrag ();
            dr.drag_update.connect (on_drag);
            dr.drag_end.connect ((x, y) => end_drag ());
            add_controller (dr);
            var scroll = new EventControllerScroll (EventControllerScrollFlags.BOTH_AXES);
            scroll.scroll.connect ((dx, dy) => {
                var st = scroll.get_current_event_state ();
                if ((st & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    px_per_sec = (px_per_sec * (dy < 0 ? 1.2 : 1 / 1.2)).clamp (5, 4000);
                } else if ((st & Gdk.ModifierType.SHIFT_MASK) != 0 || dx != 0) {
                    scroll_time = double.max (0, scroll_time + (dx != 0 ? dx : dy) * 30 / px_per_sec);
                } else {
                    scroll_y = double.max (0, scroll_y + dy * ROW_HEIGHT);
                }
                queue_draw ();
                return true;
            });
            add_controller (scroll);
            doc.time_changed.connect (queue_draw);
            doc.content_changed.connect (rebuild);
            doc.structure_changed.connect (rebuild);
            doc.selection_changed.connect (queue_draw);
            doc.comp_switched.connect (() => {
                scroll_time = 0;
                scroll_y = 0;
                fit_time ();
                rebuild ();
            });
            doc.service_changed.connect (() => {
                doc.service.prefetch_progress.connect ((c, f) => queue_draw ());
                rebuild ();
            });
            doc.service.prefetch_progress.connect ((c, f) => queue_draw ());
        }

        public void fit_time () {
            if (doc.comp == null) return;
            int w = get_width () - left_width - 20;
            if (w > 50) px_per_sec = (w / double.max (0.1, doc.comp.duration)).clamp (5, 4000);
            scroll_time = 0;
        }

        public override void size_allocate (int width, int height, int baseline) {
            base.size_allocate (width, height, baseline);
            int want = user_left > 0 ? user_left : int.min ((int) (width * 0.4), 590);
            left_width = want.clamp (LEFT_MIN, int.max (LEFT_MIN, int.min (LEFT_MAX, width - 200)));
            if (doc.comp != null && px_per_sec * doc.comp.duration < width - left_width - 20 && scroll_time == 0) fit_time ();
        }

        private string row_key (Layer l, PropNode? n) {
            return l.id + "/" + (n != null ? n.path_string () : "");
        }

        public bool is_expanded (Layer l, PropNode? n) {
            return expanded.contains (row_key (l, n));
        }

        public void toggle_expanded (Layer l, PropNode? n) {
            var k = row_key (l, n);
            if (expanded.contains (k)) expanded.remove (k);
            else expanded.add (k);
            rebuild ();
        }

        public void reveal_animated (Layer l) {
            expanded.add (row_key (l, null));
            only_animated = true;
            rebuild ();
        }

        private bool group_visible (Layer l, PropGroup g) {
            switch (g.type) {
                case "material":
                    return l.three_d && l.kind != LayerKind.CAMERA && l.kind != LayerKind.LIGHT;
                case "audio":
                    if (l.kind == LayerKind.AUDIO) return true;
                    if (l.kind == LayerKind.FOOTAGE || l.kind == LayerKind.PRECOMP) {
                        var f = doc.project.footage_by_id (l.source_id);
                        return f != null ? f.has_audio : l.kind == LayerKind.PRECOMP;
                    }
                    return false;
                case "masks":
                case "effects":
                    return g.children.size > 0;
                default:
                    return true;
            }
        }

        private bool has_animation (PropNode n) {
            var p = n as Property;
            if (p != null) return p.keys.size > 0 || p.has_expression ();
            foreach (var c in ((PropGroup) n).children) if (has_animation (c)) return true;
            return false;
        }

        public void rebuild () {
            rows.clear ();
            if (doc.comp == null) {
                queue_draw ();
                return;
            }
            foreach (var l in doc.comp.layers) {
                if (doc.comp.hide_shy && l.shy) continue;
                var r = new TimelineRow (RowKind.LAYER, l, 0);
                rows.add (r);
                if (!is_expanded (l, null)) continue;
                foreach (var c in l.root.children) add_node (l, c, 1);
            }
            double y = HEADER;
            foreach (var r in rows) {
                r.y = y;
                y += ROW_HEIGHT;
            }
            set_size_request (-1, -1);
            queue_draw ();
        }

        private void add_node (Layer l, PropNode n, int depth) {
            if (only_animated && !has_animation (n)) return;
            var p = n as Property;
            if (p != null) {
                if (p.key == "time-remap" && !l.time_remap) return;
                if (!l.three_d && (p.key == "orientation" || p.key == "rotation-x" || p.key == "rotation-y")) return;
                var r = new TimelineRow (RowKind.PROPERTY, l, depth);
                r.prop = p;
                rows.add (r);
                return;
            }
            var g = (PropGroup) n;
            if (depth == 1 && !group_visible (l, g)) return;
            if (g.type == "text.path" || g.type == "text.more") {
                if (!is_expanded (l, null)) return;
            }
            var r = new TimelineRow (RowKind.GROUP, l, depth);
            r.group = g;
            rows.add (r);
            if (!is_expanded (l, g) && !(only_animated && has_animation (g))) return;
            foreach (var c in g.children) add_node (l, c, depth + 1);
        }

        public double time_to_x (double t) {
            return left_width + (t - scroll_time) * px_per_sec;
        }

        public double x_to_time (double x) {
            return (x - left_width) / px_per_sec + scroll_time;
        }

        private TimelineRow? row_at (double y) {
            foreach (var r in rows) {
                double ry = r.y - scroll_y;
                if (y >= ry && y < ry + ROW_HEIGHT) return r;
            }
            return null;
        }

        private void color (Cairo.Context cr, string name, double alpha = 1, double r = 0.8, double g = 0.8, double b = 0.8) {
            Gdk.RGBA c;
            if (get_style_context ().lookup_color (name, out c)) cr.set_source_rgba (c.red, c.green, c.blue, c.alpha * alpha);
            else cr.set_source_rgba (r, g, b, alpha);
        }

        private void text (Cairo.Context cr, string s, double x, double y, double max_w = 0, bool dim = false, bool bold = false) {
            if (text_layout == null) text_layout = create_pango_layout ("");
            text_layout.set_text (s, -1);
            var fd = get_pango_context ().get_font_description ().copy ();
            fd.set_weight (bold ? Pango.Weight.BOLD : Pango.Weight.NORMAL);
            text_layout.set_font_description (fd);
            if (max_w > 0) {
                text_layout.set_width ((int) (max_w * Pango.SCALE));
                text_layout.set_ellipsize (Pango.EllipsizeMode.END);
            } else {
                text_layout.set_width (-1);
            }
            int lw, lh;
            text_layout.get_pixel_size (out lw, out lh);
            color (cr, "window_fg_color", dim ? 0.6 : 1);
            cr.move_to (x, y - lh / 2.0);
            Pango.cairo_show_layout (cr, text_layout);
        }

        public static string format_value (Property p, double[] v) {
            switch (p.kind) {
                case PropKind.PATH: return _("Path");
                case PropKind.TEXT: return _("Text");
                case PropKind.COLOR: return "#%02X%02X%02X".printf ((int) (v[0].clamp (0, 1) * 255), (int) (v[1].clamp (0, 1) * 255), (int) (v[2].clamp (0, 1) * 255));
                case PropKind.CHOICE: return p.choice_label ((int) Math.round (v[0]));
                case PropKind.TOGGLE: return v[0] > 0.5 ? _("On") : _("Off");
                case PropKind.LAYER: return v[0] < 0 ? _("None") : "%d".printf ((int) v[0] + 1);
                default:
                    var sb = new StringBuilder ();
                    int n = p.dims;
                    for (int i = 0; i < n && i < v.length; i++) {
                        if (i > 0) sb.append (", ");
                        sb.append ("%.1f".printf (v[i]));
                    }
                    if (p.unit != "") sb.append (p.unit);
                    return sb.str;
            }
        }

        private void draw (DrawingArea area, Cairo.Context cr, int w, int h) {
            color (cr, "view_bg_color", 1, 0.15, 0.15, 0.16);
            cr.paint ();
            if (doc.comp == null) return;
            var comp = doc.comp;
            cr.save ();
            cr.rectangle (0, HEADER, w, h - HEADER);
            cr.clip ();
            foreach (var r in rows) {
                double y = r.y - scroll_y;
                if (y + ROW_HEIGHT < HEADER || y > h) continue;
                draw_row (cr, r, y, w);
            }
            cr.restore ();
            draw_header (cr, w, comp);
            double cx = time_to_x (doc.time);
            if (cx >= left_width) {
                cr.set_source_rgba (0.93, 0.33, 0.25, 1);
                cr.set_line_width (1.5);
                cr.move_to (cx, 4);
                cr.line_to (cx, h);
                cr.stroke ();
                cr.move_to (cx - 6, 4);
                cr.line_to (cx + 6, 4);
                cr.line_to (cx, 13);
                cr.close_path ();
                cr.fill ();
            }
            color (cr, "borders", 1, 0.3, 0.3, 0.3);
            cr.set_line_width (1);
            cr.move_to (left_width - 0.5, 0);
            cr.line_to (left_width - 0.5, h);
            cr.stroke ();
            if (drag == "box") {
                cr.set_source_rgba (0.4, 0.7, 1, 0.25);
                cr.rectangle (double.min (box_x0, box_x1), double.min (box_y0, box_y1), (box_x1 - box_x0).abs (), (box_y1 - box_y0).abs ());
                cr.fill ();
            }
        }

        private void draw_header (Cairo.Context cr, int w, Composition comp) {
            color (cr, "headerbar_bg_color", 1, 0.2, 0.2, 0.21);
            cr.rectangle (0, 0, w, HEADER);
            cr.fill ();
            text (cr, Timecode.format (doc.time, comp.fps), 12, HEADER / 2.0, 0, false, true);
            text (cr, _("Frame %d").printf (doc.frame ()), 130, HEADER / 2.0, 0, true);
            double ws = time_to_x (comp.work_start), we = time_to_x (comp.work_area_end ());
            cr.set_source_rgba (0.36, 0.6, 1, 0.35);
            cr.rectangle (double.max (left_width, ws), 2, double.max (0, we - double.max (left_width, ws)), 6);
            cr.fill ();
            var cached = doc.service.renderer.cache.cached_frames (comp.id, doc.current_settings ().key ());
            cr.set_source_rgba (0.3, 0.8, 0.4, 0.9);
            foreach (var f in cached) {
                double x = time_to_x (f / comp.fps);
                if (x < left_width) continue;
                cr.rectangle (x, HEADER - 4, double.max (1, px_per_sec / comp.fps), 3);
            }
            cr.fill ();
            double step = nice_step ();
            double t = Math.floor (scroll_time / step) * step;
            cr.set_line_width (1);
            while (time_to_x (t) < w) {
                double x = time_to_x (t);
                if (x >= left_width) {
                    color (cr, "window_fg_color", 0.4);
                    cr.move_to (x + 0.5, HEADER - 10);
                    cr.line_to (x + 0.5, HEADER);
                    cr.stroke ();
                    text (cr, Timecode.short_label (t, comp.fps), x + 3, HEADER - 20, 0, true);
                }
                t += step;
            }
            foreach (var m in comp.markers) {
                double x = time_to_x (m.time);
                if (x < left_width) continue;
                cr.set_source_rgba (0.95, 0.75, 0.25, 1);
                cr.move_to (x - 4, HEADER - 12);
                cr.line_to (x + 4, HEADER - 12);
                cr.line_to (x, HEADER - 5);
                cr.close_path ();
                cr.fill ();
            }
        }

        private double nice_step () {
            double target = 80 / px_per_sec;
            double[] steps = { 1.0 / 30, 1.0 / 10, 0.25, 0.5, 1, 2, 5, 10, 30, 60, 300 };
            foreach (var s in steps) if (s >= target) return s;
            return 600;
        }

        private void draw_row (Cairo.Context cr, TimelineRow r, double y, int w) {
            bool selected = doc.selection.contains (r.layer) && r.kind == RowKind.LAYER;
            if (selected) {
                color (cr, "accent_bg_color", 0.25, 0.3, 0.5, 0.9);
                cr.rectangle (0, y, w, ROW_HEIGHT);
                cr.fill ();
            } else if (r.kind == RowKind.PROPERTY && doc.active_property == r.prop) {
                color (cr, "accent_bg_color", 0.12, 0.3, 0.5, 0.9);
                cr.rectangle (0, y, w, ROW_HEIGHT);
                cr.fill ();
            }
            color (cr, "borders", 0.5, 0.3, 0.3, 0.3);
            cr.set_line_width (1);
            cr.move_to (0, y + ROW_HEIGHT - 0.5);
            cr.line_to (w, y + ROW_HEIGHT - 0.5);
            cr.stroke ();
            double cy = y + ROW_HEIGHT / 2.0;
            if (r.kind == RowKind.LAYER) draw_layer_row (cr, r, y, cy, w);
            else draw_prop_row (cr, r, y, cy, w);
        }

        private void glyph_eye (Cairo.Context cr, double x, double cy, bool on) {
            color (cr, "window_fg_color", on ? 0.9 : 0.25);
            cr.save ();
            cr.translate (x, cy);
            cr.scale (1, 0.55);
            cr.arc (0, 0, 6, 0, Math.PI * 2);
            cr.restore ();
            cr.set_line_width (1.3);
            cr.stroke ();
            if (on) {
                cr.arc (x, cy, 2, 0, Math.PI * 2);
                cr.fill ();
            }
        }

        private void glyph_dot (Cairo.Context cr, double x, double cy, bool on, double r = 3.5) {
            color (cr, "window_fg_color", on ? 0.9 : 0.2);
            cr.arc (x, cy, r, 0, Math.PI * 2);
            if (on) cr.fill ();
            else {
                cr.set_line_width (1);
                cr.stroke ();
            }
        }

        private void glyph_twirl (Cairo.Context cr, double x, double cy, bool open) {
            color (cr, "window_fg_color", 0.8);
            if (open) {
                cr.move_to (x - 4, cy - 2);
                cr.line_to (x + 4, cy - 2);
                cr.line_to (x, cy + 3);
            } else {
                cr.move_to (x - 2, cy - 4);
                cr.line_to (x + 3, cy);
                cr.line_to (x - 2, cy + 4);
            }
            cr.close_path ();
            cr.fill ();
        }

        private void glyph_text (Cairo.Context cr, double x, double cy, string s, bool on) {
            if (text_layout == null) text_layout = create_pango_layout ("");
            text_layout.set_width (-1);
            text_layout.set_text (s, -1);
            int lw, lh;
            text_layout.get_pixel_size (out lw, out lh);
            if (on) {
                color (cr, "accent_bg_color", 1, 0.21, 0.52, 0.89);
                rounded (cr, x - lw / 2.0 - 4, cy - lh / 2.0 - 1, lw + 8, lh + 2, (lh + 2) / 2.0);
                cr.fill ();
                color (cr, "accent_fg_color", 1, 1, 1, 1);
            } else {
                color (cr, "window_fg_color", 0.3);
            }
            cr.move_to (x - lw / 2.0, cy - lh / 2.0);
            Pango.cairo_show_layout (cr, text_layout);
        }

        public const int COL_EYE = 14;
        public const int COL_SOLO = 34;
        public const int COL_LOCK = 52;
        public const int COL_LABEL = 70;
        public const int COL_TWIRL = 84;
        public const int COL_NAME = 96;
        private bool show_parent {
            get { return left_width >= 540; }
        }
        private int COL_PARENT {
            get { return left_width - 90; }
        }
        private int COL_MODE {
            get { return show_parent ? left_width - 170 : left_width - 80; }
        }
        private int COL_SWITCH {
            get { return COL_MODE - 148; }
        }

        private void draw_layer_row (Cairo.Context cr, TimelineRow r, double y, double cy, int w) {
            var l = r.layer;
            glyph_eye (cr, COL_EYE, cy, l.video);
            glyph_dot (cr, COL_SOLO, cy, l.solo);
            color (cr, "window_fg_color", l.locked ? 0.9 : 0.2);
            cr.rectangle (COL_LOCK - 4, cy - 1, 8, 6);
            cr.fill ();
            cr.set_line_width (1.2);
            cr.arc (COL_LOCK, cy - 1, 3, Math.PI, 0);
            cr.stroke ();
            int lc = l.label.clamp (0, 9);
            cr.set_source_rgb (label_colors[lc, 0], label_colors[lc, 1], label_colors[lc, 2]);
            cr.rectangle (COL_LABEL - 5, cy - 5, 10, 10);
            cr.fill ();
            glyph_twirl (cr, COL_TWIRL, cy, is_expanded (l, null));
            int index = doc.comp.index_of (l) + 1;
            text (cr, "%d  %s".printf (index, l.name), COL_NAME, cy, COL_SWITCH - COL_NAME - 6, false, true);
            glyph_text (cr, COL_SWITCH, cy, _("Shy"), l.shy);
            glyph_text (cr, COL_SWITCH + 32, cy, "fx", l.effects != null && l.effects.children.size > 0);
            glyph_text (cr, COL_SWITCH + 58, cy, "MB", l.motion_blur);
            glyph_text (cr, COL_SWITCH + 88, cy, "Adj", l.adjustment);
            glyph_text (cr, COL_SWITCH + 118, cy, "3D", l.three_d);
            text (cr, l.blend.label (), COL_MODE - 14, cy, 60, true);
            string parent = _("None");
            var p = l.parent_layer ();
            if (p != null) parent = "%d. %s".printf (doc.comp.index_of (p) + 1, p.name);
            string matte = l.matte_mode != MatteMode.NONE ? (l.matte_mode == MatteMode.ALPHA ? _("Alpha") : (l.matte_mode == MatteMode.ALPHA_INVERTED ? _("Alpha Inv") : (l.matte_mode == MatteMode.LUMA ? _("Luma") : _("Luma Inv")))) : "";
            if (show_parent) text (cr, matte != "" ? matte + "  " + parent : parent, COL_PARENT - 14, cy, left_width - COL_PARENT + 8, true);
            double x0 = time_to_x (l.in_point), x1 = time_to_x (l.out_point);
            x0 = double.max (x0, left_width);
            if (x1 > x0) {
                cr.set_source_rgba (label_colors[lc, 0], label_colors[lc, 1], label_colors[lc, 2], doc.selection.contains (l) ? 0.85 : 0.55);
                rounded (cr, x0, y + 4, x1 - x0, ROW_HEIGHT - 8, 3);
                cr.fill ();
            }
            draw_waveform (cr, l, y, x0, x1);
            foreach (var t in l.key_times ()) {
                double kx = time_to_x (l.comp_time (t));
                if (kx < left_width) continue;
                color (cr, "window_fg_color", 0.7);
                diamond (cr, kx, cy, 3.5);
                cr.fill ();
            }
        }

        private AudioPeaks? peaks_for (Footage f) {
            var existing = peaks[f.id];
            if (existing != null) return existing.ready ? existing : null;
            var entry = new AudioPeaks ();
            peaks[f.id] = entry;
            string path = f.effective_path ();
            new Thread<bool> ("keyframe-peaks", () => {
                var clip = MediaPool.decode_audio (path, 8000);
                Idle.add (() => {
                    if (clip != null) {
                        entry.values = clip.peaks (4000);
                        entry.duration = clip.duration ();
                    }
                    entry.ready = true;
                    queue_draw ();
                    return false;
                });
                return true;
            });
            return null;
        }

        private void draw_waveform (Cairo.Context cr, Layer l, double y, double x0, double x1) {
            if (!l.audio || (l.kind != LayerKind.AUDIO && l.kind != LayerKind.FOOTAGE)) return;
            var f = doc.project.footage_by_id (l.source_id);
            if (f == null || !(f.has_audio || f.kind == FootageKind.AUDIO)) return;
            var pk = peaks_for (f);
            if (pk == null || pk.values.length == 0 || pk.duration <= 0) return;
            int buckets = pk.values.length / 2;
            double mid = y + ROW_HEIGHT / 2.0, half = ROW_HEIGHT / 2.0 - 5;
            var levels = l.root.group ("audio") != null ? l.root.group ("audio").prop ("levels") : null;
            cr.set_source_rgba (0.15, 0.55, 0.35, 0.85);
            for (double x = x0; x < x1; x += 1) {
                double ct = x_to_time (x);
                double st = l.source_time (ct);
                if (st < 0 || st >= pk.duration) continue;
                int b = ((int) (st / pk.duration * buckets)).clamp (0, buckets - 1);
                double gain = 1;
                if (levels != null) gain = Math.pow (10, levels.value_at (l.layer_time (ct))[0] / 20.0);
                double lo = pk.values[b * 2] * gain, hi = pk.values[b * 2 + 1] * gain;
                cr.rectangle (x, mid - hi.clamp (-1, 1) * half, 1, double.max (1, (hi - lo).clamp (0, 2) * half));
            }
            cr.fill ();
        }

        private void rounded (Cairo.Context cr, double x, double y, double w, double h, double r) {
            cr.new_sub_path ();
            cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
            cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
            cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
            cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
            cr.close_path ();
        }

        private void diamond (Cairo.Context cr, double x, double y, double s) {
            cr.move_to (x, y - s);
            cr.line_to (x + s, y);
            cr.line_to (x, y + s);
            cr.line_to (x - s, y);
            cr.close_path ();
        }

        private void draw_prop_row (Cairo.Context cr, TimelineRow r, double y, double cy, int w) {
            double indent = COL_TWIRL + (r.depth - 1) * 14;
            if (r.kind == RowKind.GROUP) {
                glyph_twirl (cr, indent, cy, is_expanded (r.layer, r.group));
                text (cr, r.group.name, indent + 12, cy, left_width - indent - 20, !r.group.enabled);
                if (r.group.type == "mask") text (cr, mask_mode_label (r.group.attr ("mode", "add")), COL_MODE - 14, cy, 70, true);
                return;
            }
            var p = r.prop;
            double lt = r.layer.layer_time (doc.time);
            if (p.animatable) {
                color (cr, "window_fg_color", p.keys.size > 0 ? 0.95 : 0.35);
                cr.set_line_width (1.3);
                cr.arc (indent, cy, 5, 0, Math.PI * 2);
                cr.stroke ();
                cr.move_to (indent, cy);
                cr.line_to (indent, cy - 3.5);
                cr.move_to (indent, cy);
                cr.line_to (indent + 3, cy);
                cr.stroke ();
            }
            text (cr, p.name, indent + 12, cy, COL_MODE - indent - 40, false);
            string val = format_value (p, p.kind == PropKind.PATH || p.kind == PropKind.TEXT ? new double[] { 0 } : p.value_at (lt));
            color (cr, "accent_color", 1, 0.4, 0.65, 1);
            if (text_layout == null) text_layout = create_pango_layout ("");
            text_layout.set_width ((int) ((left_width - COL_MODE + 30) * Pango.SCALE));
            text_layout.set_ellipsize (Pango.EllipsizeMode.END);
            text_layout.set_text (val, -1);
            int lw, lh;
            text_layout.get_pixel_size (out lw, out lh);
            cr.move_to (COL_MODE - 30, cy - lh / 2.0);
            Pango.cairo_show_layout (cr, text_layout);
            glyph_text (cr, left_width - 14, cy, "=", p.has_expression ());
            if (p.has_expression () && p.expression_error != "") {
                cr.set_source_rgba (0.95, 0.35, 0.3, 1);
                cr.arc (left_width - 26, cy, 3, 0, Math.PI * 2);
                cr.fill ();
            }
            foreach (var k in p.keys) {
                double kx = time_to_x (r.layer.comp_time (k.time));
                if (kx < left_width - 4) continue;
                bool sel = doc.selected_keys.contains (k);
                if (sel) cr.set_source_rgba (1, 0.85, 0.25, 1);
                else color (cr, "window_fg_color", 0.85);
                if (k.out_interp == Interp.HOLD) {
                    cr.rectangle (kx - 4, cy - 4, 8, 8);
                } else if (k.out_interp == Interp.BEZIER || k.in_interp == Interp.BEZIER) {
                    cr.arc (kx, cy, 4.5, 0, Math.PI * 2);
                } else {
                    diamond (cr, kx, cy, 5);
                }
                cr.fill ();
            }
        }

        public static string mask_mode_label (string mode) {
            switch (mode) {
                case "subtract": return _("Subtract");
                case "intersect": return _("Intersect");
                case "lighten": return _("Lighten");
                case "darken": return _("Darken");
                case "difference": return _("Difference");
                case "none": return _("None");
                default: return _("Add");
            }
        }

        private Keyframe? key_at (TimelineRow r, double x, out Property? owner) {
            owner = null;
            if (r.kind == RowKind.PROPERTY) {
                foreach (var k in r.prop.keys) {
                    if ((time_to_x (r.layer.comp_time (k.time)) - x).abs () <= 6) {
                        owner = r.prop;
                        return k;
                    }
                }
            }
            return null;
        }

        private void on_press (Gesture g, int n, double x, double y) {
            grab_focus ();
            press_x = x;
            press_y = y;
            drag = "";
            if ((x - left_width).abs () <= 4) {
                drag = "divider";
                left0 = left_width;
                return;
            }
            if (doc.comp == null) return;
            var gc = (GestureClick) g;
            uint button = gc.get_current_button ();
            var state = gc.get_current_event_state ();
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
            if (y < HEADER) {
                if (x >= left_width) {
                    if (y < 10) {
                        double ws = time_to_x (doc.comp.work_start), we = time_to_x (doc.comp.work_area_end ());
                        drag = (x - ws).abs () < (x - we).abs () ? "work-start" : "work-end";
                        doc.begin_edit (_("Work Area"));
                    } else {
                        drag = "cti";
                        doc.seek (x_to_time (x));
                    }
                }
                return;
            }
            var r = row_at (y);
            if (r == null) {
                if (x >= left_width) {
                    drag = "box";
                    box_x0 = box_x1 = x;
                    box_y0 = box_y1 = y;
                    if (!shift) doc.clear_keys ();
                } else {
                    doc.select_layer (null);
                }
                return;
            }
            if (button == 3) {
                Property? owner;
                var k = key_at (r, x, out owner);
                if (k != null) {
                    if (!doc.selected_keys.contains (k)) doc.select_key (owner, k, false);
                    request_key_menu (x, y);
                } else {
                    doc.select_layer (r.layer, shift);
                    request_layer_menu (r.layer, x, y);
                }
                return;
            }
            if (x < left_width) {
                press_left (r, x, y, n, shift, ctrl);
                return;
            }
            Property? owner;
            var k = key_at (r, x, out owner);
            if (k != null) {
                if (n == 2) {
                    request_key_dialog (owner, k);
                    return;
                }
                if (!doc.selected_keys.contains (k) || shift) doc.select_key (owner, k, shift);
                drag = "keys";
                key_start.clear ();
                foreach (var sk in doc.selected_keys) key_start[sk] = sk.time;
                doc.begin_edit (_("Move Keyframes"));
                return;
            }
            if (r.kind == RowKind.LAYER) {
                var l = r.layer;
                double x0 = time_to_x (l.in_point), x1 = time_to_x (l.out_point);
                if (x >= x0 - 4 && x <= x1 + 4) {
                    if (!doc.selection.contains (l)) doc.select_layer (l, shift);
                    layer_in0 = l.in_point;
                    layer_out0 = l.out_point;
                    layer_start0 = l.start_time;
                    if ((x - x0).abs () <= 5) drag = "trim-in";
                    else if ((x - x1).abs () <= 5) drag = "trim-out";
                    else drag = "layer-move";
                    drag_row = r;
                    doc.begin_edit (_("Edit Layer Timing"));
                    return;
                }
            }
            if (!shift) doc.clear_keys ();
            drag = "box";
            box_x0 = box_x1 = x;
            box_y0 = box_y1 = y;
        }

        private void press_left (TimelineRow r, double x, double y, int n, bool shift, bool ctrl) {
            var l = r.layer;
            if (r.kind == RowKind.LAYER) {
                if ((x - COL_EYE).abs () < 9) {
                    doc.edit (_("Toggle Video"), () => { l.video = !l.video; l.mark_changed (); });
                } else if ((x - COL_SOLO).abs () < 9) {
                    doc.edit (_("Toggle Solo"), () => { l.solo = !l.solo; l.mark_changed (); });
                } else if ((x - COL_LOCK).abs () < 9) {
                    doc.edit (_("Toggle Lock"), () => { l.locked = !l.locked; l.mark_changed (); });
                } else if ((x - COL_LABEL).abs () < 7) {
                    doc.edit (_("Label"), () => { l.label = (l.label + 1) % 10; l.mark_changed (); });
                } else if ((x - COL_TWIRL).abs () < 8) {
                    toggle_expanded (l, null);
                } else if (x >= COL_SWITCH - 14 && x < COL_SWITCH + 16) {
                    doc.edit (_("Toggle Shy"), () => { l.shy = !l.shy; l.mark_changed (); });
                } else if (x >= COL_SWITCH + 20 && x < COL_SWITCH + 45) {
                    if (l.effects != null && l.effects.children.size > 0) {
                        doc.edit (_("Toggle Effects"), () => {
                            bool any_on = false;
                            foreach (var c in l.effects.children) if (((PropGroup) c).enabled) any_on = true;
                            foreach (var c in l.effects.children) ((PropGroup) c).enabled = !any_on;
                            l.mark_changed ();
                        });
                    }
                } else if (x >= COL_SWITCH + 45 && x < COL_SWITCH + 73) {
                    doc.edit (_("Toggle Motion Blur"), () => { l.motion_blur = !l.motion_blur; l.mark_changed (); });
                } else if (x >= COL_SWITCH + 73 && x < COL_SWITCH + 103) {
                    doc.edit (_("Toggle Adjustment Layer"), () => { l.adjustment = !l.adjustment; l.mark_changed (); });
                } else if (x >= COL_SWITCH + 103 && x < COL_SWITCH + 133) {
                    doc.edit (_("Toggle 3D Layer"), () => { l.three_d = !l.three_d; l.mark_changed (); });
                    rebuild ();
                } else if (x >= COL_MODE - 16 && (!show_parent || x < COL_PARENT - 16)) {
                    request_blend_menu (l, x, y);
                } else if (show_parent && x >= COL_PARENT - 16) {
                    request_parent_menu (l, x, y);
                } else {
                    if (n == 2) {
                        request_rename (l);
                        return;
                    }
                    doc.select_layer (l, shift || ctrl);
                    drag = "reorder";
                    drag_row = r;
                }
                return;
            }
            double indent = COL_TWIRL + (r.depth - 1) * 14;
            if (r.kind == RowKind.GROUP) {
                if (x < indent + 10) {
                    toggle_expanded (l, r.group);
                } else if (r.group.type == "mask" && x >= COL_MODE - 16) {
                    request_mask_menu (r.group, x, y);
                } else {
                    if (n == 2) toggle_expanded (l, r.group);
                    doc.select_layer (l);
                }
                return;
            }
            var p = r.prop;
            doc.active_property = p;
            if (!doc.selection.contains (l)) doc.select_layer (l);
            else doc.selection_changed ();
            if ((x - indent).abs () < 8 && p.animatable) {
                doc.edit (_("Toggle Animation"), () => {
                    if (p.keys.size > 0) p.clear_keys ();
                    else add_key_now (p, l);
                });
                rebuild ();
                return;
            }
            if (x > left_width - 24) {
                request_expression (p);
                return;
            }
            if (x >= COL_MODE - 30) {
                if (n == 2 || p.kind == PropKind.COLOR || p.kind == PropKind.CHOICE || p.kind == PropKind.TOGGLE || p.kind == PropKind.LAYER || p.kind == PropKind.TEXT || p.kind == PropKind.PATH) {
                    request_value_edit (p, x, y);
                    return;
                }
                if (p.dims >= 1 && p.kind != PropKind.PATH) {
                    drag = "scrub";
                    drag_row = r;
                    drag_vec0 = p.value_at (l.layer_time (doc.time));
                    doc.begin_edit (_("Change Value"));
                }
            }
        }

        public void add_key_now (Property p, Layer l) {
            double lt = l.layer_time (doc.time);
            if (p.kind == PropKind.PATH) p.set_path_key (lt, p.path_at (lt));
            else if (p.kind == PropKind.TEXT) p.set_text_key (lt, p.text_at (lt));
            else p.set_key (lt, p.value_at (lt));
        }

        private void on_drag (double dx, double dy) {
            if (doc.comp == null) return;
            double x = press_x + dx, y = press_y + dy;
            double fps = doc.comp.fps;
            switch (drag) {
                case "divider":
                    user_left = ((int) (left0 + dx)).clamp (LEFT_MIN, int.max (LEFT_MIN, int.min (LEFT_MAX, get_width () - 200)));
                    left_width = user_left;
                    queue_draw ();
                    return;
                case "cti":
                    doc.seek (x_to_time (x));
                    return;
                case "work-start":
                    doc.comp.work_start = Math.round (x_to_time (x) * fps).clamp (0, doc.comp.work_area_end () * fps - 1) / fps;
                    queue_draw ();
                    return;
                case "work-end":
                    doc.comp.work_end = Math.round (x_to_time (x) * fps).clamp (doc.comp.work_start * fps + 1, doc.comp.duration * fps) / fps;
                    queue_draw ();
                    return;
                case "box":
                    box_x1 = x;
                    box_y1 = y;
                    select_box ();
                    queue_draw ();
                    return;
                case "keys":
                    double delta = Math.round (dx / px_per_sec * fps) / fps;
                    foreach (var kv in key_start.entries) {
                        var owner = doc.key_owner[kv.key];
                        var l = owner != null ? owner.owner_layer () : null;
                        double st = l != null ? l.stretch : 1;
                        kv.key.time = kv.value + delta / st;
                    }
                    foreach (var p in doc.key_owner.values) {
                        p.sort_keys ();
                        p.touch ();
                    }
                    queue_draw ();
                    return;
                case "trim-in":
                case "trim-out":
                case "layer-move":
                    var l = drag_row.layer;
                    double d = Math.round (dx / px_per_sec * fps) / fps;
                    if (drag == "trim-in") l.in_point = double.min (layer_in0 + d, l.out_point - 1 / fps);
                    else if (drag == "trim-out") l.out_point = double.max (layer_out0 + d, l.in_point + 1 / fps);
                    else {
                        l.in_point = layer_in0 + d;
                        l.out_point = layer_out0 + d;
                        l.start_time = layer_start0 + d;
                    }
                    l.mark_changed ();
                    queue_draw ();
                    return;
                case "scrub":
                    var p = drag_row.prop;
                    var v = drag_vec0;
                    var nv = new double[v.length];
                    double span = (p.ui_max - p.ui_min).abs ();
                    double sens = span > 0 && span < 50 ? span / 400 : 1;
                    if (p.kind == PropKind.PERCENT || p.kind == PropKind.ANGLE) sens = 0.5;
                    for (int i = 0; i < v.length; i++) nv[i] = v[i] + dx * sens;
                    if (p.kind == PropKind.COLOR) return;
                    p.set_value_at (drag_row.layer.layer_time (doc.time), nv);
                    queue_draw ();
                    return;
                case "reorder":
                    var target = row_at (y);
                    if (target != null && target.kind == RowKind.LAYER && target.layer != drag_row.layer) {
                        int idx = doc.comp.index_of (target.layer);
                        doc.edit (_("Reorder Layers"), () => doc.comp.move_layer (drag_row.layer, idx));
                        rebuild ();
                        drag_row = row_for_layer (drag_row.layer);
                    }
                    return;
            }
        }

        private TimelineRow? row_for_layer (Layer l) {
            foreach (var r in rows) if (r.kind == RowKind.LAYER && r.layer == l) return r;
            return null;
        }

        private void select_box () {
            double x0 = double.min (box_x0, box_x1), x1 = double.max (box_x0, box_x1);
            double y0 = double.min (box_y0, box_y1), y1 = double.max (box_y0, box_y1);
            foreach (var r in rows) {
                if (r.kind != RowKind.PROPERTY) continue;
                double ry = r.y - scroll_y + ROW_HEIGHT / 2.0;
                if (ry < y0 || ry > y1) continue;
                foreach (var k in r.prop.keys) {
                    double kx = time_to_x (r.layer.comp_time (k.time));
                    if (kx >= x0 && kx <= x1 && !doc.selected_keys.contains (k)) {
                        doc.selected_keys.add (k);
                        doc.key_owner[k] = r.prop;
                    }
                }
            }
            doc.selection_changed ();
        }

        private void end_drag () {
            switch (drag) {
                case "keys":
                case "trim-in":
                case "trim-out":
                case "layer-move":
                case "scrub":
                case "work-start":
                case "work-end":
                    doc.end_edit ();
                    doc.content_changed ();
                    break;
            }
            drag = "";
            queue_draw ();
        }
    }

    namespace Timecode {
        public string format (double t, double fps) {
            int total = (int) Math.round (t * fps);
            int f = (int) Math.round (fps);
            if (f <= 0) f = 30;
            int frames = total % f;
            int secs = total / f;
            return "%d:%02d:%02d:%02d".printf (secs / 3600, (secs / 60) % 60, secs % 60, frames);
        }

        public string short_label (double t, double fps) {
            if (t < 60) {
                if ((t - Math.round (t)).abs () < 1e-6) return "%ds".printf ((int) Math.round (t));
                return "%df".printf ((int) Math.round (t * fps));
            }
            return "%d:%02d".printf ((int) t / 60, (int) t % 60);
        }

        public double parse (string s, double fps) {
            var parts = s.strip ().split (":");
            if (parts.length == 1) return double.parse (parts[0]) / fps;
            double total = 0;
            int n = parts.length;
            total += double.parse (parts[n - 1]) / fps;
            if (n >= 2) total += double.parse (parts[n - 2]);
            if (n >= 3) total += double.parse (parts[n - 3]) * 60;
            if (n >= 4) total += double.parse (parts[n - 4]) * 3600;
            return total;
        }
    }
}
