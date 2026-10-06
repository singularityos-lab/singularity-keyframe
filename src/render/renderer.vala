using Singularity.Imaging;
using Singularity.Vector;

namespace Singularity.Apps.Keyframe {

    public class RenderSettings {
        public int downsample = 1;
        public bool roi = false;
        public double roi_x = 0;
        public double roi_y = 0;
        public double roi_w = 0;
        public double roi_h = 0;
        public bool motion_blur = true;
        public bool use_cache = true;
        public bool include_guides = false;
        public bool lights = true;

        public RenderSettings copy () {
            var r = new RenderSettings ();
            r.downsample = downsample;
            r.roi = roi;
            r.roi_x = roi_x;
            r.roi_y = roi_y;
            r.roi_w = roi_w;
            r.roi_h = roi_h;
            r.motion_blur = motion_blur;
            r.use_cache = use_cache;
            r.include_guides = include_guides;
            r.lights = lights;
            return r;
        }

        public string key () {
            if (!roi) return "%d|%d|%d".printf (downsample, motion_blur ? 1 : 0, include_guides ? 1 : 0);
            return "%d|%d|%d|%.1f,%.1f,%.1f,%.1f".printf (downsample, motion_blur ? 1 : 0, include_guides ? 1 : 0, roi_x, roi_y, roi_w, roi_h);
        }
    }

    public class CameraInfo {
        public Mat4 view;
        public double zoom;
        public Vec3 position;
        public bool dof = false;
        public double focus = 0;
        public double aperture = 0;
        public double blur_level = 1;
    }

    public class LightInfo {
        public LightType type;
        public Vec3 position;
        public Vec3 direction;
        public double r;
        public double g;
        public double b;
        public double cone;
        public double feather;
        public int falloff;
        public double radius;
        public double falloff_distance;
    }

    public class Renderer : Object {
        public Project project;
        public MediaPool media;
        public FrameCache cache;
        public int depth_limit = 12;
        private Mutex lock_mutex = Mutex ();

        public Renderer (Project project) {
            this.project = project;
            media = new MediaPool (project);
            cache = new FrameCache (512);
            project.changed.connect ((c, l) => {
                if (c != null) cache.invalidate (project, c, l);
            });
            project.structure_changed.connect (() => cache.clear ());
            EffectRegistry.ensure ();
            Expressions.install ();
        }

        public int canvas_width (Composition comp, RenderSettings s) {
            double w = s.roi ? s.roi_w : comp.width;
            return int.max (1, (int) Math.ceil (w / int.max (1, s.downsample)));
        }

        public int canvas_height (Composition comp, RenderSettings s) {
            double h = s.roi ? s.roi_h : comp.height;
            return int.max (1, (int) Math.ceil (h / int.max (1, s.downsample)));
        }

        public Mat4 canvas_matrix (RenderSettings s) {
            double ds = int.max (1, s.downsample);
            var m = Mat4.scaling (1.0 / ds, 1.0 / ds, 1);
            if (s.roi) m = m.multiply (Mat4.translation (-s.roi_x, -s.roi_y, 0));
            return m;
        }

        public FloatImage render (Composition comp, double t, RenderSettings s) {
            lock_mutex.lock ();
            var r = render_comp (comp, t, s, 0);
            lock_mutex.unlock ();
            return r;
        }

        public FloatImage render_comp (Composition comp, double t, RenderSettings s, int depth) {
            int w = canvas_width (comp, s), h = canvas_height (comp, s);
            if (depth > depth_limit) return new FloatImage (w, h);
            bool on_frame = (t * comp.fps - Math.round (t * comp.fps)).abs () < 1e-4;
            if (s.use_cache && on_frame) {
                var hit = cache.lookup (comp.id, (int) Math.round (t * comp.fps), s.key ());
                if (hit != null) return hit;
            }
            var canvas = new FloatImage (w, h);
            var cam = camera_info (comp, t, s);
            var lights = s.lights ? light_infos (comp, t) : new Gee.ArrayList<LightInfo> ();
            var order = new Gee.ArrayList<Layer> ();
            for (int i = comp.layers.size - 1; i >= 0; i--) {
                var l = comp.layers[i];
                if (!renders_in_comp (comp, l, t, s)) continue;
                order.add (l);
            }
            int idx = 0;
            while (idx < order.size) {
                var l = order[idx];
                if (l.is_three_d () && !l.adjustment) {
                    var run = new Gee.ArrayList<Layer> ();
                    while (idx < order.size && order[idx].is_three_d () && !order[idx].adjustment) {
                        run.add (order[idx]);
                        idx++;
                    }
                    var depths = new Gee.HashMap<Layer, double?> ();
                    foreach (var rl in run) depths[rl] = camera_depth (rl, t, cam);
                    run.sort ((a, b) => {
                        double da = depths[a], db = depths[b];
                        return da > db ? -1 : (da < db ? 1 : 0);
                    });
                    foreach (var rl in run) composite_layer (canvas, rl, t, s, depth, cam, lights);
                } else {
                    composite_layer (canvas, l, t, s, depth, cam, lights);
                    idx++;
                }
            }
            if (project.bit_depth < 32) Pixels.quantize (canvas, project.bit_depth);
            if (s.use_cache && on_frame) cache.store (comp.id, (int) Math.round (t * comp.fps), s.key (), canvas, t);
            return canvas;
        }

        private bool renders_in_comp (Composition comp, Layer l, double t, RenderSettings s) {
            if (l.kind == LayerKind.CAMERA || l.kind == LayerKind.LIGHT || l.kind == LayerKind.AUDIO || l.kind == LayerKind.NULL) return false;
            if (!l.video || !l.active_at (t)) return false;
            if (l.guide && !s.include_guides) return false;
            if (comp.any_solo () && !l.solo) return false;
            int i = comp.layers.index_of (l);
            if (i >= 0 && i + 1 < comp.layers.size) {
                var below = comp.layers[i + 1];
                if (below != l && below.matte_mode != MatteMode.NONE && below.matte_id == "" ) return false;
            }
            return true;
        }

        public Layer? matte_source (Layer l) {
            if (l.matte_mode == MatteMode.NONE || l.comp == null) return null;
            if (l.matte_id != "") return l.comp.layer_by_id (l.matte_id);
            int i = l.comp.layers.index_of (l);
            return i > 0 ? l.comp.layers[i - 1] : null;
        }

        private void composite_layer (FloatImage canvas, Layer l, double t, RenderSettings s, int depth, CameraInfo cam, Gee.List<LightInfo> lights) {
            if (l.adjustment) {
                apply_adjustment (canvas, l, t, s, depth);
                return;
            }
            var ci = layer_comp_image (l, t, s, depth, false, cam, lights);
            if (ci == null) return;
            var matte = matte_source (l);
            if (matte != null && matte != l) {
                var mi = layer_comp_image (matte, t, s, depth + 1, false, cam, lights);
                apply_matte (ci, mi, l.matte_mode);
            }
            Pixels.blend (canvas, ci, l.blend, project.linear_blending, l.preserve_transparency);
        }

        private void apply_matte (CompImage ci, CompImage? mi, MatteMode mode) {
            bool inv = mode == MatteMode.ALPHA_INVERTED || mode == MatteMode.LUMA_INVERTED;
            bool luma = mode == MatteMode.LUMA || mode == MatteMode.LUMA_INVERTED;
            var img = ci.img;
            for (int y = 0; y < img.height; y++)
                for (int x = 0; x < img.width; x++) {
                    float r = 0, g = 0, b = 0, a = 0;
                    if (mi != null) mi.get_pixel_at (x + ci.x, y + ci.y, out r, out g, out b, out a);
                    float v = luma ? (a > 0 ? Pixels.luma (r, g, b).clamp (0, 1) : 0) : a;
                    if (luma) v = Transfer.linear_to_srgb (v);
                    if (inv) v = 1 - v;
                    size_t o = img.offset (x, y);
                    img.data[o] *= v;
                    img.data[o + 1] *= v;
                    img.data[o + 2] *= v;
                    img.data[o + 3] *= v;
                }
        }

        private void apply_adjustment (FloatImage canvas, Layer l, double t, RenderSettings s, int depth) {
            var fx = l.effects;
            if (fx == null || fx.children.size == 0) return;
            double ds = int.max (1, s.downsample);
            var buf = new LayerBuffer (canvas.copy (), s.roi ? s.roi_x : 0, s.roi ? s.roi_y : 0, 1.0 / ds);
            apply_effects (l, t, s, depth, ref buf, int.MAX, true);
            var cover_layer = new Layer (LayerKind.SOLID, "");
            cover_layer.copy_from (l);
            cover_layer.comp = l.comp;
            cover_layer.adjustment = false;
            cover_layer.solid_color = { 1, 1, 1, 1 };
            var cover_fx = cover_layer.effects;
            if (cover_fx != null) cover_fx.children.clear ();
            var cover = layer_comp_image (cover_layer, t, s, depth + 1, false, camera_info (l.comp, t, s), new Gee.ArrayList<LightInfo> ());
            if (cover == null) return;
            int w = canvas.width, h = canvas.height;
            var adjusted = buf.img;
            if (adjusted.width != w || adjusted.height != h || buf.x0 != (s.roi ? s.roi_x : 0)) {
                var aligned = new FloatImage (w, h);
                for (int y = 0; y < h; y++)
                    for (int x = 0; x < w; x++) {
                        double lx = (s.roi ? s.roi_x : 0) + (x + 0.5) * ds, ly = (s.roi ? s.roi_y : 0) + (y + 0.5) * ds;
                        double px, py;
                        buf.to_pixel (lx, ly, out px, out py);
                        float r, g, b, a;
                        Pixels.sample_premul (adjusted, px, py, out r, out g, out b, out a);
                        size_t o = aligned.offset (x, y);
                        aligned.data[o] = r;
                        aligned.data[o + 1] = g;
                        aligned.data[o + 2] = b;
                        aligned.data[o + 3] = a;
                    }
                adjusted = aligned;
            }
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++) {
                    float cr, cg, cb, ca;
                    cover.get_pixel_at (x, y, out cr, out cg, out cb, out ca);
                    if (ca <= 0) continue;
                    size_t o = canvas.offset (x, y);
                    for (int c = 0; c < 4; c++) canvas.data[o + c] += (adjusted.data[o + c] - canvas.data[o + c]) * ca;
                }
        }

        public bool layer_animates (Layer l) {
            if (l.kind == LayerKind.PRECOMP || l.kind == LayerKind.FOOTAGE) return true;
            foreach (var p in l.all_props ()) if (p.varies ()) return true;
            var parent = l.parent_layer ();
            if (parent != null && parent != l) return layer_animates (parent);
            return false;
        }

        public CompImage? layer_comp_image (Layer l, double t, RenderSettings s, int depth, bool raw = false, CameraInfo? cam = null, Gee.List<LightInfo>? lights = null) {
            if (depth > depth_limit) return null;
            var comp = l.comp;
            if (comp == null) return null;
            CameraInfo c;
            if (cam != null) c = cam;
            else c = camera_info (comp, t, s);
            Gee.List<LightInfo> li;
            if (lights != null) li = lights;
            else if (s.lights) li = light_infos (comp, t);
            else li = new Gee.ArrayList<LightInfo> ();
            bool mb = !raw && s.motion_blur && comp.motion_blur_enabled && l.motion_blur && comp.shutter_angle > 0 && layer_animates (l);
            if (!mb) return layer_comp_image_at (l, t, s, depth, raw, c, li);
            int n = comp.motion_blur_samples.clamp (2, 64);
            double open = t + comp.shutter_phase / 360.0 / comp.fps;
            double span = comp.shutter_angle / 360.0 / comp.fps;
            int w = canvas_width (comp, s), h = canvas_height (comp, s);
            var acc = new FloatImage (w, h);
            float wgt = 1.0f / n;
            for (int k = 0; k < n; k++) {
                double tk = open + span * (k + 0.5) / n;
                var ck = camera_info (comp, tk, s);
                var ci = layer_comp_image_at (l, tk, s, depth, raw, ck, li);
                if (ci == null) continue;
                for (int y = 0; y < ci.img.height; y++) {
                    int cy = y + ci.y;
                    if (cy < 0 || cy >= h) continue;
                    for (int x = 0; x < ci.img.width; x++) {
                        int cx = x + ci.x;
                        if (cx < 0 || cx >= w) continue;
                        size_t so = ci.img.offset (x, y), d = acc.offset (cx, cy);
                        for (int ch = 0; ch < 4; ch++) acc.data[d + ch] += ci.img.data[so + ch] * wgt;
                    }
                }
            }
            return crop_to_content (acc);
        }

        private CompImage crop_to_content (FloatImage img) {
            int x0 = img.width, y0 = img.height, x1 = -1, y1 = -1;
            for (int y = 0; y < img.height; y++)
                for (int x = 0; x < img.width; x++)
                    if (img.data[img.offset (x, y) + 3] > 0) {
                        if (x < x0) x0 = x;
                        if (y < y0) y0 = y;
                        if (x > x1) x1 = x;
                        if (y > y1) y1 = y;
                    }
            if (x1 < 0) return new CompImage (new FloatImage (1, 1), 0, 0);
            return new CompImage (img.cropped (x0, y0, x1 - x0 + 1, y1 - y0 + 1), x0, y0);
        }

        public double desired_scale (Layer l, double t, RenderSettings s, CameraInfo cam) {
            double ds = int.max (1, s.downsample);
            var world = l.world_matrix (t);
            double sc;
            if (l.is_three_d ()) {
                var center = world.transform_point (Vec3 (0, 0, 0));
                var ex = world.transform_vector (Vec3 (1, 0, 0));
                var ey = world.transform_vector (Vec3 (0, 1, 0));
                var cc = cam.view.transform_point (center);
                double z = double.max (1, cc.z);
                sc = double.max (ex.length (), ey.length ()) * cam.zoom / z;
            } else {
                sc = world.max_scale_2d ();
            }
            return (sc / ds).clamp (0.01, 8);
        }

        public CompImage? layer_comp_image_at (Layer l, double t, RenderSettings s, int depth, bool raw, CameraInfo cam, Gee.List<LightInfo> lights) {
            if (!l.kind.is_visual () && l.kind != LayerKind.SOLID) return null;
            if (l.kind == LayerKind.MODEL) return ModelRender.render (this, l, t, s, cam, lights);
            double scale = desired_scale (l, t, s, cam);
            var buf = layer_buffer_until (l, t, s, depth, raw ? 0 : int.MAX, scale, raw);
            if (buf == null) return null;
            double opacity = l.opacity_at (t);
            if (opacity <= 0) return null;
            CompImage? ci;
            if (l.is_three_d ()) ci = project_3d (l, buf, t, s, cam, lights);
            else ci = transform_2d (l, buf, t, s);
            if (ci == null) return null;
            if (opacity < 0.9999) Pixels.scale_alpha (ci.img, (float) opacity);
            return ci;
        }

        public LayerBuffer? layer_buffer_until (Layer l, double t, RenderSettings s, int depth, int effect_limit, double scale, bool raw = false) {
            var buf = source_buffer (l, t, s, depth, scale);
            if (buf == null) return null;
            if (!raw && Masks.active (l)) {
                var m = Masks.combined (l, l.layer_time (t), buf);
                if (m != null) Pixels.multiply_mask (buf.img, m);
            }
            if (!raw) apply_effects (l, t, s, depth, ref buf, effect_limit, false);
            return buf;
        }

        public void apply_effects (Layer l, double t, RenderSettings s, int depth, ref LayerBuffer buf, int limit, bool adjustment) {
            var fx = l.effects;
            if (fx == null || fx.children.size == 0 || limit <= 0) return;
            double lt = l.layer_time (t);
            double margin = 0;
            int count = 0;
            foreach (var c in fx.children) {
                if (count++ >= limit) break;
                var g = c as PropGroup;
                if (g == null || !g.enabled) continue;
                var def = EffectRegistry.get (EffectRegistry.id_of (g));
                if (def != null && def.margin != null) margin += def.margin (g, lt);
            }
            if (margin > 0 && !adjustment) buf = buf.padded (margin);
            var ctx = new EffectContext ();
            ctx.renderer = this;
            ctx.comp = l.comp;
            ctx.layer = l;
            ctx.comp_time = t;
            ctx.buf = buf;
            ctx.settings = s;
            ctx.depth = depth;
            ctx.adjustment = adjustment;
            int index = 0;
            foreach (var c in fx.children) {
                if (index >= limit) break;
                var g = c as PropGroup;
                index++;
                if (g == null || !g.enabled) continue;
                var def = EffectRegistry.get (EffectRegistry.id_of (g));
                if (def == null || def.apply == null) continue;
                ctx.effect_index = index - 1;
                def.apply (ctx, g, lt);
            }
            buf = ctx.buf;
        }

        public LayerBuffer? source_buffer (Layer l, double t, RenderSettings s, int depth, double scale) {
            double lt = l.layer_time (t);
            switch (l.kind) {
                case LayerKind.SOLID:
                    double sc = scale.clamp (0.02, 4);
                    int w = int.min (8192, int.max (1, (int) Math.ceil (l.solid_width * sc)));
                    int h = int.min (8192, int.max (1, (int) Math.ceil (l.solid_height * sc)));
                    var c = l.solid_color;
                    float a = (float) (c.length > 3 ? c[3] : 1);
                    var img = new FloatImage.filled (w, h, (float) c[0] * a, (float) c[1] * a, (float) c[2] * a, a);
                    return new LayerBuffer (img, 0, 0, w / (double) l.solid_width);
                case LayerKind.SHAPE:
                    var contents = l.contents;
                    if (contents == null) return null;
                    var sr = new ShapeRenderer (lt);
                    var scene = sr.build (contents, new Mat4 ());
                    var b = scene.bounds ();
                    if (b.is_empty ()) return null;
                    return draw_vector_buffer (b, scale, (buf) => sr.draw (scene, buf));
                case LayerKind.TEXT:
                    return text_buffer (l, lt, scale);
                case LayerKind.FOOTAGE:
                    var f = project.footage_by_id (l.source_id);
                    if (f == null) return null;
                    double st = l.source_time (t);
                    FloatImage? frame;
                    if (l.frame_blend && f.kind == FootageKind.VIDEO) frame = media.blended_frame (f, st, l.comp.fps);
                    else frame = media.frame (f, st);
                    if (frame == null) return null;
                    double fsc = 1;
                    int factor = scale < 0.5 ? (int) Math.floor (1.0 / scale) : 1;
                    if (factor > 1) {
                        frame = Pixels.box_downsample (frame, factor);
                        fsc = 1.0 / factor;
                    }
                    return new LayerBuffer (factor > 1 ? frame : frame.copy (), 0, 0, fsc);
                case LayerKind.PRECOMP:
                    var nested = project.comp_by_id (l.source_id);
                    if (nested == null || nested == l.comp) return null;
                    int nds = int.max (1, (int) Math.floor (1.0 / double.min (1, scale)));
                    var ns = new RenderSettings ();
                    ns.downsample = nds;
                    ns.motion_blur = s.motion_blur;
                    ns.use_cache = s.use_cache;
                    ns.include_guides = false;
                    ns.lights = s.lights;
                    double nt = l.source_time (t);
                    if (nt < 0 || nt > nested.duration + 1e-9) return null;
                    var img = render_comp (nested, nt, ns, depth + 1);
                    return new LayerBuffer (img.copy (), 0, 0, 1.0 / nds);
                default:
                    return null;
            }
        }

        public delegate void VectorDraw (LayerBuffer buf);

        public LayerBuffer draw_vector_buffer (Rect b, double scale, VectorDraw draw) {
            double sc = scale.clamp (0.02, 8);
            double max_side = double.max (b.w, b.h) * sc;
            if (max_side > 8192) sc = 8192 / double.max (b.w, b.h);
            double x0 = Math.floor (b.x * sc) / sc, y0 = Math.floor (b.y * sc) / sc;
            int w = int.max (1, (int) Math.ceil ((b.x2 () - x0) * sc) + 1);
            int h = int.max (1, (int) Math.ceil ((b.y2 () - y0) * sc) + 1);
            var buf = new LayerBuffer (new FloatImage (w, h), x0, y0, sc);
            draw (buf);
            return buf;
        }

        public LayerBuffer? text_buffer (Layer l, double lt, double scale) {
            var tg = l.text_group;
            if (tg == null) return null;
            var sp = tg.prop ("source-text");
            if (sp == null) return null;
            var doc = sp.text_at (lt);
            doc = TextOffsets.apply (tg, doc, lt);
            var tl = TextRenderer.layout_glyphs (doc);
            TextRenderer.apply_animators (tg, tl, lt, l, doc);
            BezPath? path = null;
            var po = tg.group ("path-options");
            if (po != null && po.attr ("mask", "") != "" && l.masks != null) {
                var mg = l.masks.child (po.attr ("mask")) as PropGroup;
                if (mg != null && mg.prop ("path") != null) path = mg.prop ("path").path_at (lt);
            }
            var b = TextRenderer.bounds (tl, tg, path, lt, doc);
            if (b.is_empty ()) return null;
            return draw_vector_buffer (b, scale, (buf) => TextRenderer.draw (tl, tg, path, lt, doc, buf));
        }

        public CompImage? transform_2d (Layer l, LayerBuffer buf, double t, RenderSettings s) {
            var comp = l.comp;
            int cw = canvas_width (comp, s), ch = canvas_height (comp, s);
            var m = canvas_matrix (s).multiply (l.world_matrix (t)).multiply (buf.pixel_to_layer ());
            var src = buf.img;
            double msc = m.max_scale_2d ();
            if (msc < 0.5 && msc > 0) {
                int factor = (int) Math.floor (1.0 / msc);
                if (factor > 1) {
                    src = Pixels.box_downsample (src, factor);
                    m = m.multiply (Mat4.scaling ((double) buf.img.width / src.width, (double) buf.img.height / src.height, 1));
                }
            }
            var inv = m.inverted ();
            if (inv == null) return null;
            double minx = double.MAX, miny = double.MAX, maxx = -double.MAX, maxy = -double.MAX;
            double[] cx = { 0, src.width, 0, src.width };
            double[] cy = { 0, 0, src.height, src.height };
            for (int i = 0; i < 4; i++) {
                var p = m.transform_point (Vec3 (cx[i], cy[i], 0));
                minx = double.min (minx, p.x);
                miny = double.min (miny, p.y);
                maxx = double.max (maxx, p.x);
                maxy = double.max (maxy, p.y);
            }
            int x0 = int.max (0, (int) Math.floor (minx)), y0 = int.max (0, (int) Math.floor (miny));
            int x1 = int.min (cw, (int) Math.ceil (maxx)), y1 = int.min (ch, (int) Math.ceil (maxy));
            if (x1 <= x0 || y1 <= y0) return null;
            var out_img = new FloatImage (x1 - x0, y1 - y0);
            bool integer_shift = (m.m[0] - 1).abs () < 1e-9 && (m.m[5] - 1).abs () < 1e-9 && m.m[1].abs () < 1e-9 && m.m[4].abs () < 1e-9
                                 && (m.m[3] - Math.round (m.m[3])).abs () < 1e-6 && (m.m[7] - Math.round (m.m[7])).abs () < 1e-6;
            int sx_off = (int) Math.round (m.m[3]), sy_off = (int) Math.round (m.m[7]);
            Parallel.range (out_img.height, (st, en) => {
                for (int y = st; y < en; y++)
                    for (int x = 0; x < out_img.width; x++) {
                        size_t o = out_img.offset (x, y);
                        if (integer_shift) {
                            int sx = x + x0 - sx_off, sy = y + y0 - sy_off;
                            if (sx < 0 || sy < 0 || sx >= src.width || sy >= src.height) continue;
                            size_t so = src.offset (sx, sy);
                            out_img.data[o] = src.data[so];
                            out_img.data[o + 1] = src.data[so + 1];
                            out_img.data[o + 2] = src.data[so + 2];
                            out_img.data[o + 3] = src.data[so + 3];
                            continue;
                        }
                        var p = inv.transform_point (Vec3 (x + x0 + 0.5, y + y0 + 0.5, 0));
                        float r, g, b, a;
                        Pixels.sample_premul (src, p.x, p.y, out r, out g, out b, out a);
                        out_img.data[o] = r;
                        out_img.data[o + 1] = g;
                        out_img.data[o + 2] = b;
                        out_img.data[o + 3] = a;
                    }
            });
            return new CompImage (out_img, x0, y0);
        }

        public Mat4 projection (Composition comp, CameraInfo cam) {
            var p = new Mat4 ();
            p.m[0] = cam.zoom;
            p.m[1] = 0;
            p.m[2] = comp.width / 2.0;
            p.m[3] = 0;
            p.m[4] = 0;
            p.m[5] = cam.zoom;
            p.m[6] = comp.height / 2.0;
            p.m[7] = 0;
            p.m[8] = 0;
            p.m[9] = 0;
            p.m[10] = 1;
            p.m[11] = 0;
            p.m[12] = 0;
            p.m[13] = 0;
            p.m[14] = 1;
            p.m[15] = 0;
            return p;
        }

        public Mat4 canvas_projective (RenderSettings s) {
            double ds = int.max (1, s.downsample);
            var m = new Mat4 ();
            m.m[0] = 1.0 / ds;
            m.m[5] = 1.0 / ds;
            if (s.roi) {
                m.m[3] = -s.roi_x / ds;
                m.m[7] = -s.roi_y / ds;
            }
            return m;
        }

        public double camera_depth (Layer l, double t, CameraInfo cam) {
            var w = l.world_matrix (t);
            double cx = 0, cy = 0;
            if (l.kind == LayerKind.SOLID || l.kind == LayerKind.PRECOMP || l.kind == LayerKind.FOOTAGE) {
                cx = l.solid_width / 2.0;
                cy = l.solid_height / 2.0;
            }
            var p = cam.view.transform_point (w.transform_point (Vec3 (cx, cy, 0)));
            return p.z;
        }

        public Mat4 model_view_projection (Layer l, double t, RenderSettings s, CameraInfo cam) {
            return canvas_projective (s).multiply (projection (l.comp, cam)).multiply (cam.view).multiply (l.world_matrix (t));
        }

        public CompImage? project_3d (Layer l, LayerBuffer buf, double t, RenderSettings s, CameraInfo cam, Gee.List<LightInfo> lights) {
            var comp = l.comp;
            int cw = canvas_width (comp, s), ch = canvas_height (comp, s);
            var world = l.world_matrix (t);
            var mvp = canvas_projective (s).multiply (projection (comp, cam)).multiply (cam.view).multiply (world).multiply (buf.pixel_to_layer ());
            var hm = Homography.from_mat4_plane (mvp);
            var inv = hm.inverted ();
            if (inv == null) return null;
            double minx = double.MAX, miny = double.MAX, maxx = -double.MAX, maxy = -double.MAX;
            bool behind = false;
            double[] cxs = { 0, buf.img.width, 0, buf.img.width };
            double[] cys = { 0, 0, buf.img.height, buf.img.height };
            for (int i = 0; i < 4; i++) {
                double wv = hm.h[6] * cxs[i] + hm.h[7] * cys[i] + hm.h[8];
                if (wv <= 1e-6) {
                    behind = true;
                    continue;
                }
                double px, py;
                hm.apply (cxs[i], cys[i], out px, out py);
                minx = double.min (minx, px);
                miny = double.min (miny, py);
                maxx = double.max (maxx, px);
                maxy = double.max (maxy, py);
            }
            if (behind) {
                minx = 0;
                miny = 0;
                maxx = cw;
                maxy = ch;
            }
            int x0 = int.max (0, (int) Math.floor (minx)), y0 = int.max (0, (int) Math.floor (miny));
            int x1 = int.min (cw, (int) Math.ceil (maxx)), y1 = int.min (ch, (int) Math.ceil (maxy));
            if (x1 <= x0 || y1 <= y0) return null;
            var mat = l.root.group ("material");
            bool lit = lights.size > 0 && (mat == null || mat.toggle ("accepts-lights", l.layer_time (t)));
            double lt = l.layer_time (t);
            double amb_k = mat != null ? mat.num ("ambient", lt) / 100.0 : 1;
            double dif_k = mat != null ? mat.num ("diffuse", lt) / 100.0 : 0.5;
            double spec_k = mat != null ? mat.num ("specular", lt) / 100.0 : 0.5;
            double shin = mat != null ? 1 + mat.num ("shininess", lt) * 2 : 11;
            var normal = world.transform_vector (Vec3 (0, 0, -1)).normalized ();
            var b2l = buf.pixel_to_layer ();
            var src = buf.img;
            var out_img = new FloatImage (x1 - x0, y1 - y0);
            Parallel.range (out_img.height, (st, en) => {
                for (int y = st; y < en; y++)
                    for (int x = 0; x < out_img.width; x++) {
                        double u, v;
                        inv.apply (x + x0 + 0.5, y + y0 + 0.5, out u, out v);
                        double wv = hm.h[6] * u + hm.h[7] * v + hm.h[8];
                        if (wv <= 1e-6) continue;
                        if (u < -1 || v < -1 || u > src.width + 1 || v > src.height + 1) continue;
                        float r, g, b, a;
                        Pixels.sample_premul (src, u, v, out r, out g, out b, out a);
                        if (a <= 0) continue;
                        if (lit) {
                            var lp = b2l.transform_point (Vec3 (u, v, 0));
                            var wp = world.transform_point (lp);
                            double sr, sg, sb, spr, spg, spb;
                            shade (wp, normal, cam.position, lights, amb_k, dif_k, spec_k, shin, out sr, out sg, out sb, out spr, out spg, out spb);
                            r = (float) (r * sr + spr * a);
                            g = (float) (g * sg + spg * a);
                            b = (float) (b * sb + spb * a);
                        }
                        size_t o = out_img.offset (x, y);
                        out_img.data[o] = r;
                        out_img.data[o + 1] = g;
                        out_img.data[o + 2] = b;
                        out_img.data[o + 3] = a;
                    }
            });
            var ci = new CompImage (out_img, x0, y0);
            if (cam.dof) {
                double z = double.max (1, camera_depth (l, t, cam));
                double coc = cam.aperture * cam.blur_level * (z - cam.focus).abs () / z / int.max (1, s.downsample);
                if (coc > 0.5) {
                    int pad = (int) Math.ceil (coc * 1.5);
                    var big = new FloatImage (out_img.width + pad * 2, out_img.height + pad * 2);
                    big.paste (out_img, pad, pad);
                    Blur.gaussian (big, coc / 2, coc / 2);
                    ci = new CompImage (big, x0 - pad, y0 - pad);
                }
            }
            return ci;
        }

        public void shade (Vec3 wp, Vec3 normal_in, Vec3 cam_pos, Gee.List<LightInfo> lights, double amb_k, double dif_k, double spec_k, double shin,
                           out double sr, out double sg, out double sb, out double spr, out double spg, out double spb) {
            var n = normal_in;
            var to_cam = cam_pos.sub (wp).normalized ();
            if (n.dot (to_cam) < 0) n = n.scale (-1);
            double ar = 0, ag = 0, ab = 0, dr = 0, dg = 0, db = 0;
            spr = spg = spb = 0;
            foreach (var li in lights) {
                if (li.type == LightType.AMBIENT) {
                    ar += li.r;
                    ag += li.g;
                    ab += li.b;
                    continue;
                }
                Vec3 ldir;
                double atten = 1;
                if (li.type == LightType.PARALLEL) {
                    ldir = li.direction.scale (-1).normalized ();
                } else {
                    var d = li.position.sub (wp);
                    double dist = d.length ();
                    ldir = d.normalized ();
                    if (li.falloff == 1) atten = (1 - ((dist - li.radius) / double.max (1, li.falloff_distance)).clamp (0, 1));
                    else if (li.falloff == 2) atten = double.min (1, Math.pow (li.radius / double.max (1, dist), 2));
                    if (li.type == LightType.SPOT) {
                        double cosang = ldir.scale (-1).dot (li.direction.normalized ());
                        double ang = Math.acos (cosang.clamp (-1, 1)) * 180.0 / Math.PI;
                        double half = li.cone / 2;
                        double inner = half * (1 - li.feather);
                        if (ang > half) atten = 0;
                        else if (ang > inner) atten *= 1 - (ang - inner) / double.max (1e-6, half - inner);
                    }
                }
                double ndl = double.max (0, n.dot (ldir));
                dr += li.r * ndl * atten;
                dg += li.g * ndl * atten;
                db += li.b * ndl * atten;
                if (spec_k > 0 && ndl > 0) {
                    var refl = n.scale (2 * n.dot (ldir)).sub (ldir);
                    double sp = Math.pow (double.max (0, refl.dot (to_cam)), shin) * spec_k * atten;
                    spr += li.r * sp;
                    spg += li.g * sp;
                    spb += li.b * sp;
                }
            }
            sr = ar * amb_k + dr * dif_k;
            sg = ag * amb_k + dg * dif_k;
            sb = ab * amb_k + db * dif_k;
        }

        public static Mat4 look_at_rotation (Vec3 eye, Vec3 target) {
            var f = target.sub (eye).normalized ();
            if (f.length () < 1e-9) f = Vec3 (0, 0, 1);
            var down = Vec3 (0, 1, 0);
            var r = down.cross (f).normalized ();
            if (r.length () < 1e-9) r = Vec3 (1, 0, 0);
            var d = f.cross (r).normalized ();
            var m = new Mat4 ();
            m.m[0] = r.x;
            m.m[4] = r.y;
            m.m[8] = r.z;
            m.m[1] = d.x;
            m.m[5] = d.y;
            m.m[9] = d.z;
            m.m[2] = f.x;
            m.m[6] = f.y;
            m.m[10] = f.z;
            return m;
        }

        public Mat4 camera_world (Layer cam, double t) {
            double lt = cam.layer_time (t);
            var tr = cam.transform;
            var p = tr.vec ("position", lt);
            var pos = Vec3 (p[0], p[1], p.length > 2 ? p[2] : 0);
            Mat4 rot;
            var cg = cam.root.group ("camera") ?? cam.root.group ("light");
            bool one_node = cg != null && cg.attr ("one-node", "false") == "true";
            var poi_prop = tr.prop ("point-of-interest");
            if (!one_node && poi_prop != null) {
                var q = poi_prop.value_at (lt);
                rot = look_at_rotation (pos, Vec3 (q[0], q[1], q.length > 2 ? q[2] : 0));
            } else {
                rot = new Mat4 ();
            }
            var o = tr.vec ("orientation", lt);
            rot = rot.multiply (Mat4.rotation_x (o[0])).multiply (Mat4.rotation_y (o[1])).multiply (Mat4.rotation_z (o[2]));
            rot = rot.multiply (Mat4.rotation_x (tr.num ("rotation-x", lt))).multiply (Mat4.rotation_y (tr.num ("rotation-y", lt))).multiply (Mat4.rotation_z (tr.num ("rotation", lt)));
            var m = Mat4.translation (pos.x, pos.y, pos.z).multiply (rot);
            var parent = cam.parent_layer ();
            if (parent != null && parent != cam) m = parent.world_matrix (t).multiply (m);
            return m;
        }

        public CameraInfo camera_info (Composition comp, double t, RenderSettings s) {
            var info = new CameraInfo ();
            var cam = comp.active_camera (t);
            if (cam == null) {
                info.zoom = comp.width * 50.0 / 36.0;
                info.position = Vec3 (comp.width / 2.0, comp.height / 2.0, -info.zoom);
                info.view = Mat4.translation (-info.position.x, -info.position.y, -info.position.z);
                return info;
            }
            double lt = cam.layer_time (t);
            var cg = cam.root.group ("camera");
            info.zoom = cg != null ? cg.num ("zoom", lt) : comp.width * 50.0 / 36.0;
            var world = camera_world (cam, t);
            info.position = world.transform_point (Vec3 (0, 0, 0));
            info.view = world.inverted () ?? new Mat4 ();
            if (cg != null && cg.toggle ("dof", lt)) {
                info.dof = true;
                info.focus = cg.num ("focus-distance", lt);
                info.aperture = cg.num ("aperture", lt) / 100.0;
                info.blur_level = cg.num ("blur-level", lt) / 100.0 * 10;
            }
            return info;
        }

        public Gee.ArrayList<LightInfo> light_infos (Composition comp, double t) {
            var r = new Gee.ArrayList<LightInfo> ();
            foreach (var l in comp.layers) {
                if (l.kind != LayerKind.LIGHT || !l.video || !l.active_at (t)) continue;
                var g = l.root.group ("light");
                if (g == null) continue;
                double lt = l.layer_time (t);
                var li = new LightInfo ();
                li.type = (LightType) int.parse (g.attr ("type", "2"));
                var world = camera_world (l, t);
                li.position = world.transform_point (Vec3 (0, 0, 0));
                li.direction = world.transform_vector (Vec3 (0, 0, 1)).normalized ();
                double inten = g.num ("intensity", lt) / 100.0;
                var col = g.vec ("color", lt);
                li.r = col[0] * inten;
                li.g = col[1] * inten;
                li.b = col[2] * inten;
                li.cone = g.num ("cone-angle", lt);
                li.feather = g.num ("cone-feather", lt) / 100.0;
                li.falloff = g.choice ("falloff", lt);
                li.radius = g.num ("radius", lt);
                li.falloff_distance = g.num ("falloff-distance", lt);
                r.add (li);
            }
            return r;
        }
    }
}
