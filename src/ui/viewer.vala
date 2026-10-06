using Gtk;
using Singularity.Vector;

namespace Singularity.Apps.Keyframe {

    public enum ViewerTool {
        SELECT,
        HAND,
        RECT,
        ELLIPSE,
        STAR,
        PEN,
        TEXT,
        PUPPET,
        ROI,
        TRACK
    }

    namespace LayerGeometry {
        public Rect bounds (Layer l, double t) {
            double lt = l.layer_time (t);
            switch (l.kind) {
                case LayerKind.SHAPE:
                    if (l.contents == null) return Rect (0, 0, 0, 0);
                    var scene = new ShapeRenderer (lt).build (l.contents, new Mat4 ());
                    var b = scene.bounds ();
                    return b.is_empty () ? Rect (-10, -10, 20, 20) : b;
                case LayerKind.TEXT:
                    var tg = l.text_group;
                    if (tg == null) return Rect (0, 0, 0, 0);
                    var doc = tg.prop ("source-text").text_at (lt);
                    var tl = TextRenderer.layout_glyphs (doc);
                    TextRenderer.apply_animators (tg, tl, lt, l, doc);
                    var b = TextRenderer.bounds (tl, tg, null, lt, doc);
                    return b.is_empty () ? Rect (-10, -10, 20, 20) : b;
                case LayerKind.CAMERA:
                case LayerKind.LIGHT:
                case LayerKind.AUDIO:
                    return Rect (-20, -20, 40, 40);
                default:
                    return Rect (0, 0, l.solid_width, l.solid_height);
            }
        }

        public Point[] corners (Renderer r, Layer l, double t) {
            var b = bounds (l, t);
            double[] xs = { b.x, b.x2 (), b.x2 (), b.x };
            double[] ys = { b.y, b.y, b.y2 (), b.y2 () };
            Point[] pts = new Point[4];
            if (l.is_three_d () && l.kind != LayerKind.CAMERA && l.kind != LayerKind.LIGHT && l.comp != null) {
                var s = new RenderSettings ();
                var cam = r.camera_info (l.comp, t, s);
                var hm = Homography.from_mat4_plane (r.model_view_projection (l, t, s, cam));
                for (int i = 0; i < 4; i++) {
                    double x, y;
                    hm.apply (xs[i], ys[i], out x, out y);
                    pts[i] = Point (x, y);
                }
                return pts;
            }
            var m = l.world_matrix (t);
            for (int i = 0; i < 4; i++) {
                var p = m.transform_point (Vec3 (xs[i], ys[i], 0));
                pts[i] = Point (p.x, p.y);
            }
            return pts;
        }

        public bool contains (Point[] q, double x, double y) {
            bool inside = false;
            for (int i = 0, j = q.length - 1; i < q.length; j = i++) {
                if (((q[i].y > y) != (q[j].y > y)) && (x < (q[j].x - q[i].x) * (y - q[i].y) / (q[j].y - q[i].y + 1e-12) + q[i].x)) inside = !inside;
            }
            return inside;
        }
    }

    public class Vals {
        public double[] v;

        public Vals (double[] v) {
            this.v = v;
        }
    }

    public class Viewer : DrawingArea {
        public Document doc;
        public const double PALETTE_INSET = 56;
        public double zoom = 0.5;
        public double offset_x = 20;
        public double offset_y = 20;
        public bool fit_mode = true;
        public ViewerTool tool = ViewerTool.SELECT;
        public bool checker = true;
        public bool show_paths = true;
        public bool show_safe = false;
        public bool show_grid = false;
        private Gdk.Texture? texture = null;
        private RenderRequest? shown = null;
        private uint last_serial = 0;
        private double drag_x;
        private double drag_y;
        private double press_x;
        private double press_y;
        private string drag_kind = "";
        private Gee.ArrayList<Vals> drag_start_values = new Gee.ArrayList<Vals> ();
        private EventControllerScroll scroll_ctl;
        private Property? drag_prop = null;
        private int drag_index = -1;
        private PropGroup? drag_mask = null;
        private BezPath? pen_path = null;
        private Layer? pen_layer = null;
        private double rubber_x0;
        private double rubber_y0;
        private double rubber_x1;
        private double rubber_y1;
        public string status = "";

        public signal void tool_finished ();
        public signal void request_text (double x, double y);
        public signal void request_track_point (double x, double y);
        public signal void request_puppet_pin (double x, double y);

        public Viewer (Document doc) {
            this.doc = doc;
            hexpand = true;
            vexpand = true;
            focusable = true;
            set_draw_func (draw);
            add_css_class ("keyframe-viewer");
            var click = new GestureClick ();
            click.set_button (0);
            click.pressed.connect (on_press);
            click.released.connect (on_release);
            add_controller (click);
            var drag = new GestureDrag ();
            drag.drag_update.connect (on_drag);
            drag.drag_end.connect ((x, y) => end_drag ());
            add_controller (drag);
            scroll_ctl = new EventControllerScroll (EventControllerScrollFlags.BOTH_AXES);
            scroll_ctl.scroll.connect (on_scroll);
            add_controller (scroll_ctl);
            var motion = new EventControllerMotion ();
            motion.motion.connect ((x, y) => {
                var c = to_comp (x, y);
                status = "%.0f, %.0f".printf (c.x, c.y);
            });
            add_controller (motion);
            doc.service.frame_ready.connect (on_frame);
            doc.service_changed.connect (rebind);
            doc.time_changed.connect (refresh);
            doc.content_changed.connect (refresh);
            doc.comp_switched.connect (() => {
                fit_mode = true;
                texture = null;
                refresh ();
            });
            doc.selection_changed.connect (queue_draw);
            notify["width"].connect (refresh);
        }

        public void rebind () {
            doc.service.frame_ready.connect (on_frame);
            refresh ();
        }

        public override void size_allocate (int width, int height, int baseline) {
            base.size_allocate (width, height, baseline);
            if (fit_mode) fit ();
        }

        public void fit () {
            if (doc.comp == null) return;
            int w = get_width (), h = get_height ();
            if (w <= 0 || h <= 0) return;
            double left = PALETTE_INSET;
            zoom = double.min ((w - left - 40.0) / doc.comp.width, (h - 40.0) / doc.comp.height);
            zoom = double.max (0.02, zoom);
            offset_x = left + (w - left - doc.comp.width * zoom) / 2;
            offset_y = (h - doc.comp.height * zoom) / 2;
            fit_mode = true;
            update_auto_downsample ();
            queue_draw ();
        }

        public void set_zoom (double z, double cx = -1, double cy = -1) {
            if (cx < 0) {
                cx = get_width () / 2.0;
                cy = get_height () / 2.0;
            }
            var c = to_comp (cx, cy);
            zoom = z.clamp (0.02, 32);
            offset_x = cx - c.x * zoom;
            offset_y = cy - c.y * zoom;
            fit_mode = false;
            update_auto_downsample ();
            refresh ();
        }

        private void update_auto_downsample () {
            int ds = 1;
            if (zoom < 0.2) ds = 4;
            else if (zoom < 0.34) ds = 3;
            else if (zoom < 0.6) ds = 2;
            if (ds != doc.auto_downsample) {
                doc.auto_downsample = ds;
            }
        }

        public Point to_comp (double x, double y) {
            return Point ((x - offset_x) / zoom, (y - offset_y) / zoom);
        }

        public Point to_view (double x, double y) {
            return Point (offset_x + x * zoom, offset_y + y * zoom);
        }

        public void refresh () {
            if (doc.comp == null) {
                queue_draw ();
                return;
            }
            last_serial = doc.service.request (doc.comp.id, doc.time, doc.current_settings ());
            queue_draw ();
        }

        private void on_frame (RenderRequest req, Singularity.Imaging.FloatImage img) {
            if (doc.comp == null || req.comp_id != doc.comp.id) return;
            if (req.serial < last_serial && shown != null && !doc.playing) return;
            shown = req;
            texture = Pixels.to_display_texture_managed (img, doc.project.working_space, doc.project.display_space, true);
            queue_draw ();
        }

        private void draw (DrawingArea area, Cairo.Context cr, int w, int h) {
            var style = get_style_context ();
            Gdk.RGBA bg;
            if (!style.lookup_color ("window_bg_color", out bg)) bg = { 0.12f, 0.12f, 0.13f, 1 };
            cr.set_source_rgb (bg.red * 0.85, bg.green * 0.85, bg.blue * 0.85);
            cr.paint ();
            if (doc.comp == null) return;
            var comp = doc.comp;
            cr.save ();
            cr.translate (offset_x, offset_y);
            cr.scale (zoom, zoom);
            if (!checker) {
                cr.set_source_rgb (comp.background[0], comp.background[1], comp.background[2]);
                cr.rectangle (0, 0, comp.width, comp.height);
                cr.fill ();
            }
            if (texture != null && shown != null) {
                double rx = shown.settings.roi ? shown.settings.roi_x : 0;
                double ry = shown.settings.roi ? shown.settings.roi_y : 0;
                double ds = shown.settings.downsample;
                cr.save ();
                cr.rectangle (0, 0, comp.width, comp.height);
                cr.clip ();
                cr.translate (rx, ry);
                cr.scale (ds, ds);
                var surface = texture_surface (texture);
                if (!checker) {
                    var un = surface;
                    cr.set_source_surface (un, 0, 0);
                } else {
                    cr.set_source_surface (surface, 0, 0);
                }
                cr.get_source ().set_filter (zoom * ds > 1.5 ? Cairo.Filter.NEAREST : Cairo.Filter.GOOD);
                cr.paint ();
                cr.restore ();
            }
            cr.restore ();
            cr.set_line_width (1);
            cr.set_source_rgba (1, 1, 1, 0.25);
            cr.rectangle (offset_x - 0.5, offset_y - 0.5, comp.width * zoom + 1, comp.height * zoom + 1);
            cr.stroke ();
            if (doc.roi_enabled && doc.roi_w > 0) {
                cr.set_source_rgba (1, 0.8, 0.2, 0.9);
                cr.set_dash ({ 4, 3 }, 0);
                var a = to_view (doc.roi_x, doc.roi_y);
                cr.rectangle (a.x, a.y, doc.roi_w * zoom, doc.roi_h * zoom);
                cr.stroke ();
                cr.set_dash ({}, 0);
            }
            if (show_safe) draw_safe (cr, comp);
            if (show_grid) draw_grid (cr, comp);
            draw_overlays (cr);
            if (drag_kind == "rubber" || drag_kind == "roi" || drag_kind == "shape") {
                cr.set_source_rgba (0.4, 0.7, 1, 0.9);
                cr.set_line_width (1);
                cr.rectangle (double.min (rubber_x0, rubber_x1), double.min (rubber_y0, rubber_y1), (rubber_x1 - rubber_x0).abs (), (rubber_y1 - rubber_y0).abs ());
                cr.stroke ();
            }
        }

        private Cairo.ImageSurface texture_surface (Gdk.Texture tex) {
            int w = tex.get_width (), h = tex.get_height ();
            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            surface.flush ();
            var downloader = new Gdk.TextureDownloader (tex);
            downloader.set_format (Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED);
            size_t stride;
            var bytes = downloader.download_bytes (out stride);
            unowned uint8[] src = bytes.get_data ();
            unowned uint8[] dst = surface.get_data ();
            int ds = surface.get_stride ();
            for (int y = 0; y < h; y++) Memory.copy (&dst[y * ds], &src[y * stride], w * 4);
            surface.mark_dirty ();
            return surface;
        }

        private void draw_safe (Cairo.Context cr, Composition comp) {
            cr.set_source_rgba (1, 1, 1, 0.35);
            foreach (var f in new double[] { 0.9, 0.8 }) {
                double w = comp.width * f, h = comp.height * f;
                var a = to_view ((comp.width - w) / 2, (comp.height - h) / 2);
                cr.rectangle (a.x, a.y, w * zoom, h * zoom);
                cr.stroke ();
            }
        }

        private void draw_grid (Cairo.Context cr, Composition comp) {
            cr.set_source_rgba (1, 1, 1, 0.15);
            for (int i = 1; i < 3; i++) {
                var a = to_view (comp.width * i / 3.0, 0);
                var b = to_view (comp.width * i / 3.0, comp.height);
                cr.move_to (a.x, a.y);
                cr.line_to (b.x, b.y);
                a = to_view (0, comp.height * i / 3.0);
                b = to_view (comp.width, comp.height * i / 3.0);
                cr.move_to (a.x, a.y);
                cr.line_to (b.x, b.y);
            }
            cr.stroke ();
        }

        private Mat4 parent_matrix (Layer l, double t) {
            var p = l.parent_layer ();
            return p != null && p != l ? p.world_matrix (t) : new Mat4 ();
        }

        private void draw_overlays (Cairo.Context cr) {
            double t = doc.time;
            foreach (var l in doc.selection) {
                if (l.comp != doc.comp) continue;
                var c = LayerGeometry.corners (doc.service.renderer, l, t);
                cr.set_source_rgba (0.36, 0.6, 1, 1);
                cr.set_line_width (1.2);
                for (int i = 0; i < 4; i++) {
                    var v = to_view (c[i].x, c[i].y);
                    if (i == 0) cr.move_to (v.x, v.y);
                    else cr.line_to (v.x, v.y);
                }
                cr.close_path ();
                cr.stroke ();
                for (int i = 0; i < 4; i++) {
                    var v = to_view (c[i].x, c[i].y);
                    cr.rectangle (v.x - 3.5, v.y - 3.5, 7, 7);
                    cr.fill ();
                }
                if (l.kind != LayerKind.CAMERA && l.kind != LayerKind.LIGHT && !l.is_three_d ()) {
                    var a = l.transform.vec ("anchor", l.layer_time (t));
                    var ap = l.world_matrix (t).transform_point (Vec3 (a[0], a[1], 0));
                    var av = to_view (ap.x, ap.y);
                    cr.set_source_rgba (1, 1, 1, 0.95);
                    cr.arc (av.x, av.y, 5, 0, Math.PI * 2);
                    cr.move_to (av.x - 8, av.y);
                    cr.line_to (av.x + 8, av.y);
                    cr.move_to (av.x, av.y - 8);
                    cr.line_to (av.x, av.y + 8);
                    cr.stroke ();
                }
                if (show_paths) draw_motion_path (cr, l);
                draw_masks (cr, l);
            }
            if (pen_path != null) {
                cr.set_source_rgba (1, 0.85, 0.2, 1);
                draw_bez (cr, pen_path, pen_layer != null ? pen_layer.world_matrix (t) : new Mat4 ());
            }
        }

        private void draw_bez (Cairo.Context cr, BezPath p, Mat4 m) {
            var c = p.copy ();
            c.transform (m);
            cr.save ();
            cr.translate (offset_x, offset_y);
            cr.scale (zoom, zoom);
            c.to_cairo (cr);
            cr.restore ();
            cr.set_line_width (1.5);
            cr.stroke ();
            foreach (var v in c.v) {
                var pv = to_view (v.x, v.y);
                cr.rectangle (pv.x - 3, pv.y - 3, 6, 6);
                cr.fill ();
            }
        }

        private void draw_motion_path (Cairo.Context cr, Layer l) {
            var pos = l.transform.prop ("position");
            if (pos == null || pos.keys.size < 2) return;
            var pm = parent_matrix (l, doc.time);
            double t0 = l.comp_time (pos.keys[0].time), t1 = l.comp_time (pos.keys[pos.keys.size - 1].time);
            cr.set_source_rgba (0.36, 0.6, 1, 0.9);
            cr.set_line_width (1);
            int steps = int.max (2, (int) ((t1 - t0) * (doc.comp != null ? doc.comp.fps : 30)));
            for (int i = 0; i <= steps; i++) {
                double tt = t0 + (t1 - t0) * i / steps;
                var v = pos.value_at (l.layer_time (tt));
                var w = pm.transform_point (Vec3 (v[0], v[1], 0));
                var p = to_view (w.x, w.y);
                if (i == 0) cr.move_to (p.x, p.y);
                else cr.line_to (p.x, p.y);
            }
            cr.stroke ();
            for (int i = 0; i <= steps; i++) {
                double tt = t0 + (t1 - t0) * i / steps;
                var v = pos.value_at (l.layer_time (tt));
                var w = pm.transform_point (Vec3 (v[0], v[1], 0));
                var p = to_view (w.x, w.y);
                cr.arc (p.x, p.y, 1.4, 0, Math.PI * 2);
                cr.fill ();
            }
            for (int k = 0; k < pos.keys.size; k++) {
                var kv = pos.keys[k].value;
                var w = pm.transform_point (Vec3 (kv[0], kv[1], 0));
                var p = to_view (w.x, w.y);
                bool sel = doc.selected_keys.contains (pos.keys[k]);
                cr.set_source_rgba (sel ? 1 : 0.36, sel ? 0.85 : 0.6, sel ? 0.2 : 1, 1);
                cr.rectangle (p.x - 4, p.y - 4, 8, 8);
                cr.fill ();
                double[] tin, tout;
                pos.auto_tangents (k, out tin, out tout);
                cr.set_source_rgba (0.36, 0.6, 1, 0.8);
                for (int side = 0; side < 2; side++) {
                    var tan = side == 0 ? tin : tout;
                    if (tan[0] == 0 && tan[1] == 0) continue;
                    var hw = pm.transform_point (Vec3 (kv[0] + tan[0], kv[1] + tan[1], 0));
                    var hp = to_view (hw.x, hw.y);
                    cr.move_to (p.x, p.y);
                    cr.line_to (hp.x, hp.y);
                    cr.stroke ();
                    cr.arc (hp.x, hp.y, 3, 0, Math.PI * 2);
                    cr.fill ();
                }
            }
        }

        private void draw_masks (Cairo.Context cr, Layer l) {
            var masks = l.masks;
            if (masks == null) return;
            var m = l.world_matrix (doc.time);
            foreach (var c in masks.children) {
                var g = c as PropGroup;
                if (g == null) continue;
                var p = g.prop ("path");
                if (p == null) continue;
                cr.set_source_rgba (1, 0.85, 0.2, 0.95);
                draw_bez (cr, p.path_at (l.layer_time (doc.time)), m);
            }
        }

        private void on_scroll_zoom (double dy, double x, double y) {
            set_zoom (zoom * (dy < 0 ? 1.15 : 1 / 1.15), x, y);
        }

        private bool on_scroll (double dx, double dy) {
            var state = scroll_ctl.get_current_event_state ();
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 || tool == ViewerTool.HAND) {
                on_scroll_zoom (dy, press_x, press_y);
                return true;
            }
            offset_x -= dx * 30;
            offset_y -= dy * 30;
            fit_mode = false;
            queue_draw ();
            return true;
        }

        private Layer? hit_layer (double cx, double cy) {
            if (doc.comp == null) return null;
            foreach (var l in doc.comp.layers) {
                if (!l.video || !l.active_at (doc.time) || l.locked) continue;
                if (l.kind == LayerKind.AUDIO) continue;
                var c = LayerGeometry.corners (doc.service.renderer, l, doc.time);
                if (LayerGeometry.contains (c, cx, cy)) return l;
            }
            return null;
        }

        private void on_press (Gesture g, int n, double x, double y) {
            grab_focus ();
            press_x = x;
            press_y = y;
            var gc = g as GestureClick;
            uint button = gc != null ? gc.get_current_button () : 1;
            var c = to_comp (x, y);
            if (doc.comp == null) return;
            if (button == 2 || tool == ViewerTool.HAND) {
                drag_kind = "pan";
                drag_x = offset_x;
                drag_y = offset_y;
                return;
            }
            var state = gc != null ? gc.get_current_event_state () : 0;
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            switch (tool) {
                case ViewerTool.ROI:
                    drag_kind = "roi";
                    rubber_x0 = rubber_x1 = x;
                    rubber_y0 = rubber_y1 = y;
                    return;
                case ViewerTool.RECT:
                case ViewerTool.ELLIPSE:
                case ViewerTool.STAR:
                    drag_kind = "shape";
                    rubber_x0 = rubber_x1 = x;
                    rubber_y0 = rubber_y1 = y;
                    return;
                case ViewerTool.PEN:
                    pen_click (c, n);
                    return;
                case ViewerTool.TEXT:
                    request_text (c.x, c.y);
                    return;
                case ViewerTool.TRACK:
                    request_track_point (c.x, c.y);
                    return;
                case ViewerTool.PUPPET:
                    request_puppet_pin (c.x, c.y);
                    return;
                default:
                    break;
            }
            if (try_grab_handle (x, y)) return;
            var hit = hit_layer (c.x, c.y);
            if (hit == null) {
                if (!shift) doc.select_layer (null);
                drag_kind = "rubber";
                rubber_x0 = rubber_x1 = x;
                rubber_y0 = rubber_y1 = y;
                return;
            }
            if (!doc.selection.contains (hit)) doc.select_layer (hit, shift);
            drag_kind = "move";
            drag_start_values.clear ();
            foreach (var l in doc.selection) {
                var p = l.transform.prop ("position");
                drag_start_values.add (new Vals (p != null ? p.value_at (l.layer_time (doc.time)) : new double[] { 0, 0, 0 }));
            }
            doc.begin_edit (_("Move"));
        }

        private bool try_grab_handle (double x, double y) {
            var l = doc.primary ();
            if (l == null) return false;
            double t = doc.time;
            double lt = l.layer_time (t);
            var masks = l.masks;
            if (masks != null) {
                var m = l.world_matrix (t);
                foreach (var c in masks.children) {
                    var g = c as PropGroup;
                    if (g == null || g.prop ("path") == null) continue;
                    var path = g.prop ("path").path_at (lt);
                    for (int i = 0; i < path.count; i++) {
                        var w = m.transform_point (Vec3 (path.v[i].x, path.v[i].y, 0));
                        var p = to_view (w.x, w.y);
                        if (Math.hypot (p.x - x, p.y - y) <= 6) {
                            drag_kind = "mask-vertex";
                            drag_mask = g;
                            drag_index = i;
                            doc.begin_edit (_("Edit Mask"));
                            return true;
                        }
                    }
                }
            }
            var pos = l.transform.prop ("position");
            if (pos != null && pos.keys.size > 1 && show_paths) {
                var pm = parent_matrix (l, t);
                for (int k = 0; k < pos.keys.size; k++) {
                    var kv = pos.keys[k].value;
                    double[] tin, tout;
                    pos.auto_tangents (k, out tin, out tout);
                    for (int side = 0; side < 2; side++) {
                        var tan = side == 0 ? tin : tout;
                        if (tan[0] == 0 && tan[1] == 0) continue;
                        var hw = pm.transform_point (Vec3 (kv[0] + tan[0], kv[1] + tan[1], 0));
                        var hp = to_view (hw.x, hw.y);
                        if (Math.hypot (hp.x - x, hp.y - y) <= 6) {
                            drag_kind = side == 0 ? "tangent-in" : "tangent-out";
                            drag_prop = pos;
                            drag_index = k;
                            doc.begin_edit (_("Edit Motion Path"));
                            return true;
                        }
                    }
                    var w = pm.transform_point (Vec3 (kv[0], kv[1], 0));
                    var p = to_view (w.x, w.y);
                    if (Math.hypot (p.x - x, p.y - y) <= 6) {
                        drag_kind = "path-key";
                        drag_prop = pos;
                        drag_index = k;
                        doc.select_key (pos, pos.keys[k], false);
                        doc.begin_edit (_("Edit Motion Path"));
                        return true;
                    }
                }
            }
            if (!l.is_three_d ()) {
                var a = l.transform.vec ("anchor", lt);
                var ap = l.world_matrix (t).transform_point (Vec3 (a[0], a[1], 0));
                var av = to_view (ap.x, ap.y);
                if (Math.hypot (av.x - x, av.y - y) <= 7) {
                    drag_kind = "anchor";
                    doc.begin_edit (_("Move Anchor Point"));
                    drag_start_values.clear ();
                    drag_start_values.add (new Vals (a));
                    drag_start_values.add (new Vals (l.transform.vec ("position", lt)));
                    return true;
                }
                var c = LayerGeometry.corners (doc.service.renderer, l, t);
                for (int i = 0; i < 4; i++) {
                    var v = to_view (c[i].x, c[i].y);
                    double d = Math.hypot (v.x - x, v.y - y);
                    if (d <= 7) {
                        drag_kind = "scale";
                        drag_start_values.clear ();
                        drag_start_values.add (new Vals (l.transform.vec ("scale", lt)));
                        drag_start_values.add (new Vals ({ ap.x, ap.y, Math.hypot (c[i].x - ap.x, c[i].y - ap.y) }));
                        doc.begin_edit (_("Scale"));
                        return true;
                    }
                    if (d <= 22) {
                        drag_kind = "rotate";
                        drag_start_values.clear ();
                        drag_start_values.add (new Vals ({ l.transform.num ("rotation", lt) }));
                        var cp = to_comp (x, y);
                        drag_start_values.add (new Vals ({ ap.x, ap.y, Math.atan2 (cp.y - ap.y, cp.x - ap.x) }));
                        doc.begin_edit (_("Rotate"));
                        return true;
                    }
                }
            }
            return false;
        }

        private void set_prop (Layer l, string key, double[] v) {
            var p = l.transform.prop (key);
            if (p == null) return;
            p.set_value_at (l.layer_time (doc.time), v);
        }

        private void on_drag (double dx, double dy) {
            if (doc.comp == null) return;
            double x = press_x + dx, y = press_y + dy;
            var c = to_comp (x, y);
            double cdx = dx / zoom, cdy = dy / zoom;
            switch (drag_kind) {
                case "pan":
                    offset_x = drag_x + dx;
                    offset_y = drag_y + dy;
                    fit_mode = false;
                    queue_draw ();
                    return;
                case "rubber":
                case "roi":
                case "shape":
                    rubber_x1 = x;
                    rubber_y1 = y;
                    queue_draw ();
                    return;
                case "move":
                    for (int i = 0; i < doc.selection.size && i < drag_start_values.size; i++) {
                        var l = doc.selection[i];
                        var s = drag_start_values[i].v;
                        var parent = l.parent_layer ();
                        double ddx = cdx, ddy = cdy;
                        if (parent != null) {
                            var inv = parent.world_matrix (doc.time).inverted ();
                            if (inv != null) {
                                var d = inv.transform_vector (Vec3 (cdx, cdy, 0));
                                ddx = d.x;
                                ddy = d.y;
                            }
                        }
                        var nv = s.length > 2 ? new double[] { s[0] + ddx, s[1] + ddy, s[2] } : new double[] { s[0] + ddx, s[1] + ddy };
                        set_prop (l, "position", nv);
                    }
                    break;
                case "anchor":
                    var l = doc.primary ();
                    var inv = l.world_matrix (doc.time).inverted ();
                    var a0 = drag_start_values[0].v;
                    var p0 = drag_start_values[1].v;
                    if (inv != null) {
                        var d = inv.transform_vector (Vec3 (cdx, cdy, 0));
                        set_prop (l, "anchor", { a0[0] + d.x, a0[1] + d.y, a0.length > 2 ? a0[2] : 0 });
                        set_prop (l, "position", { p0[0] + cdx, p0[1] + cdy, p0.length > 2 ? p0[2] : 0 });
                    }
                    break;
                case "scale":
                    var l = doc.primary ();
                    var s0 = drag_start_values[0].v;
                    var info = drag_start_values[1].v;
                    double nd = Math.hypot (c.x - info[0], c.y - info[1]);
                    double f = info[2] > 1e-6 ? nd / info[2] : 1;
                    set_prop (l, "scale", { s0[0] * f, s0[1] * f, s0.length > 2 ? s0[2] : 100 });
                    break;
                case "rotate":
                    var l = doc.primary ();
                    var r0 = drag_start_values[0].v[0];
                    var info = drag_start_values[1].v;
                    double ang = Math.atan2 (c.y - info[1], c.x - info[0]);
                    set_prop (l, "rotation", { r0 + (ang - info[2]) * 180 / Math.PI });
                    break;
                case "path-key":
                case "tangent-in":
                case "tangent-out":
                    var l = doc.primary ();
                    var k = drag_prop.keys[drag_index];
                    var pinv = parent_matrix (l, doc.time).inverted () ?? new Mat4 ();
                    var lc = pinv.transform_point (Vec3 (c.x, c.y, 0));
                    if (drag_kind == "path-key") {
                        var nv = k.value;
                        nv[0] = lc.x;
                        nv[1] = lc.y;
                        k.value = nv;
                    } else {
                        double[] tin, tout;
                        drag_prop.auto_tangents (drag_index, out tin, out tout);
                        k.spatial_auto = false;
                        double hx = lc.x - k.value[0], hy = lc.y - k.value[1];
                        if (drag_kind == "tangent-in") {
                            tin = { hx, hy, 0 };
                            tout = { -hx * (Math.hypot (tout[0], tout[1]) / double.max (1e-6, Math.hypot (hx, hy))), -hy * (Math.hypot (tout[0], tout[1]) / double.max (1e-6, Math.hypot (hx, hy))), 0 };
                        } else {
                            tout = { hx, hy, 0 };
                            tin = { -hx * (Math.hypot (tin[0], tin[1]) / double.max (1e-6, Math.hypot (hx, hy))), -hy * (Math.hypot (tin[0], tin[1]) / double.max (1e-6, Math.hypot (hx, hy))), 0 };
                        }
                        k.tangent_in = tin;
                        k.tangent_out = tout;
                    }
                    drag_prop.touch ();
                    break;
                case "mask-vertex":
                    var l = doc.primary ();
                    var inv = l.world_matrix (doc.time).inverted ();
                    if (inv == null) break;
                    var lp = inv.transform_point (Vec3 (c.x, c.y, 0));
                    var mp = drag_mask.prop ("path");
                    double lt = l.layer_time (doc.time);
                    var path = mp.path_at (lt).copy ();
                    path.v[drag_index].x = lp.x;
                    path.v[drag_index].y = lp.y;
                    if (mp.keys.size > 0) mp.set_path_key (lt, path);
                    else {
                        mp.path = path;
                        mp.touch ();
                    }
                    break;
            }
            refresh ();
        }

        private void on_release (Gesture g, int n, double x, double y) {
        }

        private void end_drag () {
            switch (drag_kind) {
                case "rubber":
                    select_in_rect ();
                    break;
                case "roi":
                    var a = to_comp (double.min (rubber_x0, rubber_x1), double.min (rubber_y0, rubber_y1));
                    var b = to_comp (double.max (rubber_x0, rubber_x1), double.max (rubber_y0, rubber_y1));
                    if (doc.comp != null && b.x - a.x > 4 && b.y - a.y > 4) {
                        doc.roi_x = a.x.clamp (0, doc.comp.width);
                        doc.roi_y = a.y.clamp (0, doc.comp.height);
                        doc.roi_w = (b.x - a.x).clamp (1, doc.comp.width - doc.roi_x);
                        doc.roi_h = (b.y - a.y).clamp (1, doc.comp.height - doc.roi_y);
                        doc.roi_enabled = true;
                        refresh ();
                    }
                    tool_finished ();
                    break;
                case "shape":
                    finish_shape ();
                    break;
                case "move":
                case "anchor":
                case "scale":
                case "rotate":
                case "path-key":
                case "tangent-in":
                case "tangent-out":
                case "mask-vertex":
                    doc.end_edit ();
                    doc.content_changed ();
                    break;
            }
            drag_kind = "";
            drag_mask = null;
            drag_prop = null;
            queue_draw ();
        }

        private void select_in_rect () {
            if (doc.comp == null) return;
            var a = to_comp (double.min (rubber_x0, rubber_x1), double.min (rubber_y0, rubber_y1));
            var b = to_comp (double.max (rubber_x0, rubber_x1), double.max (rubber_y0, rubber_y1));
            if (b.x - a.x < 3 && b.y - a.y < 3) return;
            foreach (var l in doc.comp.layers) {
                if (!l.active_at (doc.time) || l.locked) continue;
                var c = LayerGeometry.corners (doc.service.renderer, l, doc.time);
                bool any = false;
                foreach (var p in c) if (p.x >= a.x && p.x <= b.x && p.y >= a.y && p.y <= b.y) any = true;
                if (any && !doc.selection.contains (l)) doc.selection.add (l);
            }
            doc.selection_changed ();
        }

        private void finish_shape () {
            if (doc.comp == null) return;
            var a = to_comp (double.min (rubber_x0, rubber_x1), double.min (rubber_y0, rubber_y1));
            var b = to_comp (double.max (rubber_x0, rubber_x1), double.max (rubber_y0, rubber_y1));
            double w = b.x - a.x, h = b.y - a.y;
            if (w < 2 || h < 2) return;
            var target = doc.primary ();
            doc.begin_edit (_("New Shape"));
            if (target != null && target.kind != LayerKind.SHAPE && target.masks != null) {
                var inv = target.world_matrix (doc.time).inverted () ?? new Mat4 ();
                var p0 = inv.transform_point (Vec3 (a.x, a.y, 0));
                var p1 = inv.transform_point (Vec3 (b.x, b.y, 0));
                double mx = double.min (p0.x, p1.x), my = double.min (p0.y, p1.y), mw = (p1.x - p0.x).abs (), mh = (p1.y - p0.y).abs ();
                BezPath mp = tool == ViewerTool.ELLIPSE ? BezPath.ellipse (mx + mw / 2, my + mh / 2, mw / 2, mh / 2) : BezPath.rect (mx, my, mw, mh);
                var mg = Factory.mask (mp);
                mg.key = target.masks.unique_key ("mask");
                mg.name = _("Mask %d").printf (target.masks.children.size + 1);
                target.masks.add<PropGroup> (mg);
                target.mark_changed ();
            } else {
                Layer layer;
                if (target != null && target.kind == LayerKind.SHAPE) layer = target;
                else {
                    layer = Factory.shape_layer (doc.comp);
                    layer.transform.prop ("position").value = { a.x + w / 2, a.y + h / 2, 0 };
                    doc.comp.add_layer (layer, 0);
                }
                var inv = layer.world_matrix (doc.time).inverted () ?? new Mat4 ();
                var center = inv.transform_point (Vec3 (a.x + w / 2, a.y + h / 2, 0));
                string name = tool == ViewerTool.RECT ? _("Rectangle") : (tool == ViewerTool.ELLIPSE ? _("Ellipse") : _("Polystar"));
                var grp = Factory.shape_group (name);
                grp.key = layer.contents.unique_key ("group");
                PropGroup gen;
                if (tool == ViewerTool.RECT) gen = Factory.rect (w, h);
                else if (tool == ViewerTool.ELLIPSE) gen = Factory.ellipse (w, h);
                else gen = Factory.star (false, 5, double.min (w, h) / 2, double.min (w, h) / 4);
                gen.prop ("position").value = { center.x, center.y };
                grp.group ("contents").add<PropGroup> (gen);
                grp.group ("contents").add<PropGroup> (Factory.stroke ({ 1, 1, 1, 1 }, 2));
                grp.group ("contents").add<PropGroup> (Factory.fill ({ 0.95, 0.45, 0.15, 1 }));
                layer.contents.insert (0, grp);
                layer.mark_changed ();
                doc.select_layer (layer);
            }
            doc.end_edit ();
            doc.content_changed ();
            tool_finished ();
        }

        private void pen_click (Point c, int n) {
            var target = doc.primary ();
            if (pen_path == null) {
                pen_path = new BezPath ();
                pen_path.closed = false;
                pen_layer = target;
            }
            var m = pen_layer != null ? pen_layer.world_matrix (doc.time).inverted () ?? new Mat4 () : new Mat4 ();
            var lp = m.transform_point (Vec3 (c.x, c.y, 0));
            if (pen_path.count > 2) {
                var first = pen_path.v[0];
                var fw = (pen_layer != null ? pen_layer.world_matrix (doc.time) : new Mat4 ()).transform_point (Vec3 (first.x, first.y, 0));
                var fv = to_view (fw.x, fw.y);
                var cv = to_view (c.x, c.y);
                if (Math.hypot (fv.x - cv.x, fv.y - cv.y) < 8 || n >= 2) {
                    finish_pen (true);
                    return;
                }
            }
            pen_path.add (lp.x, lp.y);
            queue_draw ();
        }

        public void finish_pen (bool closed) {
            if (pen_path == null || doc.comp == null) return;
            var path = pen_path;
            path.closed = closed;
            var target = pen_layer;
            pen_path = null;
            pen_layer = null;
            if (path.count < 2) {
                queue_draw ();
                return;
            }
            doc.begin_edit (_("Pen"));
            if (target != null && target.kind != LayerKind.SHAPE && target.masks != null) {
                var mg = Factory.mask (path);
                mg.key = target.masks.unique_key ("mask");
                mg.name = _("Mask %d").printf (target.masks.children.size + 1);
                target.masks.add<PropGroup> (mg);
                target.mark_changed ();
            } else {
                Layer layer = target;
                if (layer == null || layer.kind != LayerKind.SHAPE) {
                    layer = Factory.shape_layer (doc.comp);
                    layer.transform.prop ("position").value = { 0, 0, 0 };
                    doc.comp.add_layer (layer, 0);
                }
                var grp = Factory.shape_group (_("Path"));
                grp.key = layer.contents.unique_key ("group");
                grp.group ("contents").add<PropGroup> (Factory.path_shape (path));
                grp.group ("contents").add<PropGroup> (Factory.stroke ({ 1, 1, 1, 1 }, 3));
                if (closed) grp.group ("contents").add<PropGroup> (Factory.fill ({ 0.2, 0.6, 1, 1 }));
                layer.contents.insert (0, grp);
                layer.mark_changed ();
                doc.select_layer (layer);
            }
            doc.end_edit ();
            doc.content_changed ();
            queue_draw ();
        }

        public void cancel_pen () {
            pen_path = null;
            pen_layer = null;
            queue_draw ();
        }
    }
}
