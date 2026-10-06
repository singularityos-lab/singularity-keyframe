using Singularity.Imaging;
using Singularity.Vector;

namespace Singularity.Apps.Keyframe {

    public class ShapeNode {
        public Gee.ArrayList<BezPath> paths = new Gee.ArrayList<BezPath> ();
    }

    public class DrawOp {
        public PropGroup style;
        public Gee.ArrayList<ShapeNode> targets = new Gee.ArrayList<ShapeNode> ();
        public Mat4 space;
        public double opacity;

        public DrawOp (PropGroup style, Mat4 space, double opacity) {
            this.style = style;
            this.space = space;
            this.opacity = opacity;
        }

        public Gee.ArrayList<BezPath> all_paths () {
            var r = new Gee.ArrayList<BezPath> ();
            foreach (var n in targets) r.add_all (n.paths);
            return r;
        }
    }

    public class ShapeScene {
        public Gee.ArrayList<ShapeNode> nodes = new Gee.ArrayList<ShapeNode> ();
        public Gee.ArrayList<DrawOp> ops = new Gee.ArrayList<DrawOp> ();

        public Rect bounds () {
            var r = Rect.empty ();
            bool any = false;
            foreach (var op in ops) {
                double grow = 0;
                if (op.style.type == "shape.stroke" || op.style.type == "shape.gradient-stroke") {
                    double w = op.style.num ("width", 0) * op.space.max_scale_2d ();
                    grow = w / 2 * (op.style.attr ("join", "miter") == "miter" ? double.max (1, op.style.num ("miter-limit", 0) * 0.5) : 1) + 1;
                }
                foreach (var p in op.all_paths ()) {
                    var pr = Rect.empty ();
                    p.bounds (ref pr);
                    if (pr.is_empty ()) continue;
                    pr = pr.inflate (grow);
                    r = any ? r.union (pr) : pr;
                    any = true;
                }
            }
            return r;
        }
    }

    public class ShapeRenderer {
        private double time;
        private int depth = 0;

        public ShapeRenderer (double time) {
            this.time = time;
        }

        public static Mat4 group_matrix (PropGroup tr, double t) {
            var a = tr.vec ("anchor", t);
            var p = tr.vec ("position", t);
            var s = tr.vec ("scale", t);
            double rot = tr.num ("rotation", t);
            var m = Mat4.translation (p[0], p[1], 0);
            m = m.multiply (Mat4.rotation_z (rot));
            m = m.multiply (Mat4.skew (tr.num ("skew", t), tr.num ("skew-axis", t)));
            m = m.multiply (Mat4.scaling (s[0] / 100.0, s[1] / 100.0, 1));
            m = m.multiply (Mat4.translation (-a[0], -a[1], 0));
            return m;
        }

        public ShapeScene build (PropGroup contents, Mat4 base_matrix) {
            var scene = new ShapeScene ();
            process (contents.children, 0, contents.children.size, base_matrix, 1.0, scene);
            return scene;
        }

        private void process (Gee.List<PropNode> items, int from, int to, Mat4 m, double opacity, ShapeScene scene) {
            if (depth > 64) return;
            depth++;
            for (int idx = from; idx < to; idx++) {
                var g = items[idx] as PropGroup;
                if (g == null || !g.enabled) continue;
                switch (g.type) {
                    case "shape.repeater":
                        apply_repeater (items, from, idx, g, m, opacity, scene);
                        break;
                    case "shape.group":
                        var tr = g.group ("transform");
                        var gm = tr != null ? m.multiply (group_matrix (tr, time)) : m;
                        double go = tr != null ? tr.num ("opacity", time) / 100.0 : 1;
                        var sub = new ShapeScene ();
                        var c = g.group ("contents");
                        if (c != null) process (c.children, 0, c.children.size, gm, opacity * go, sub);
                        scene.nodes.add_all (sub.nodes);
                        scene.ops.add_all (sub.ops);
                        break;
                    case "shape.rect":
                    case "shape.ellipse":
                    case "shape.star":
                    case "shape.path":
                        var node = new ShapeNode ();
                        var p = generate (g);
                        if (p != null) {
                            if (g.attr ("direction", "1") == "3") p = p.reversed ();
                            p.transform (m);
                            node.paths.add (p);
                        }
                        scene.nodes.add (node);
                        break;
                    case "shape.fill":
                    case "shape.stroke":
                    case "shape.gradient-fill":
                    case "shape.gradient-stroke":
                        var op = new DrawOp (g, m, opacity);
                        op.targets.add_all (scene.nodes);
                        scene.ops.add (op);
                        break;
                    case "shape.merge":
                        merge (scene, g.attr ("mode", "add"));
                        break;
                    default:
                        if (g.type.has_prefix ("shape.")) modify (scene, g, m);
                        break;
                }
            }
            depth--;
        }

        private void apply_repeater (Gee.List<PropNode> items, int from, int idx, PropGroup rep, Mat4 m, double opacity, ShapeScene scene) {
            double copies = rep.num ("copies", time);
            double offset = rep.num ("offset", time);
            var tr = rep.group ("transform");
            int n = (int) Math.ceil (copies);
            scene.nodes.clear ();
            scene.ops.clear ();
            if (n <= 0 || tr == null) return;
            var a = tr.vec ("anchor", time);
            var p = tr.vec ("position", time);
            var s = tr.vec ("scale", time);
            double rot = tr.num ("rotation", time);
            double so = tr.num ("start-opacity", time) / 100.0;
            double eo = tr.num ("end-opacity", time) / 100.0;
            var copies_scenes = new Gee.ArrayList<ShapeScene> ();
            for (int k = 0; k < n; k++) {
                double step = k + offset;
                var cm = Mat4.translation (a[0], a[1], 0);
                cm = cm.multiply (Mat4.translation (p[0] * step, p[1] * step, 0));
                cm = cm.multiply (Mat4.rotation_z (rot * step));
                cm = cm.multiply (Mat4.scaling (Math.pow (s[0] / 100.0, step), Math.pow (s[1] / 100.0, step), 1));
                cm = cm.multiply (Mat4.translation (-a[0], -a[1], 0));
                double frac = n > 1 ? (double) k / (n - 1) : 0;
                double o = so + (eo - so) * frac;
                double partial = (k == n - 1 && copies < n) ? copies - (n - 1) : 1;
                var sub = new ShapeScene ();
                process (items, from, idx, m.multiply (cm), opacity * o * partial, sub);
                copies_scenes.add (sub);
            }
            bool above = rep.attr ("composite", "below") == "above";
            for (int k = 0; k < copies_scenes.size; k++) {
                var sub = copies_scenes[above ? copies_scenes.size - 1 - k : k];
                scene.nodes.add_all (sub.nodes);
            }
            for (int k = 0; k < copies_scenes.size; k++) {
                var sub = copies_scenes[above ? k : copies_scenes.size - 1 - k];
                scene.ops.add_all (sub.ops);
            }
        }

        public BezPath? generate (PropGroup g) {
            double t = time;
            switch (g.type) {
                case "shape.rect":
                    var size = g.vec ("size", t);
                    var pos = g.vec ("position", t);
                    double r = g.num ("roundness", t);
                    return round_rect (pos[0] - size[0] / 2, pos[1] - size[1] / 2, size[0], size[1], r);
                case "shape.ellipse":
                    var size = g.vec ("size", t);
                    var pos = g.vec ("position", t);
                    return BezPath.ellipse (pos[0], pos[1], size[0] / 2, size[1] / 2);
                case "shape.star":
                    var pos = g.vec ("position", t);
                    bool star = g.attr ("star", "true") == "true";
                    return BezPath.polystar (pos[0], pos[1], (int) Math.round (g.num ("points", t)), g.num ("outer-radius", t), g.num ("inner-radius", t),
                                             g.num ("outer-roundness", t), g.num ("inner-roundness", t), g.num ("rotation", t), star);
                case "shape.path":
                    var p = g.prop ("path");
                    return p != null ? p.path_at (t).copy () : null;
                default:
                    return null;
            }
        }

        public static BezPath round_rect (double x, double y, double w, double h, double r) {
            r = double.min (r, double.min (w.abs (), h.abs ()) / 2);
            if (r <= 0.0001) return BezPath.rect (x, y, w, h);
            double k = PathData.KAPPA * r;
            var p = new BezPath ();
            p.add (x + r, y, -k, 0, 0, 0);
            p.add (x + w - r, y, 0, 0, k, 0);
            p.add (x + w, y + r, 0, -k, 0, 0);
            p.add (x + w, y + h - r, 0, 0, 0, k);
            p.add (x + w - r, y + h, k, 0, 0, 0);
            p.add (x + r, y + h, 0, 0, -k, 0);
            p.add (x, y + h - r, 0, k, 0, 0);
            p.add (x, y + r, 0, 0, 0, -k);
            return p;
        }

        private void merge (ShapeScene scene, string mode) {
            if (scene.nodes.size == 0) return;
            var all = new Gee.ArrayList<BezPath> ();
            foreach (var n in scene.nodes) all.add_all (n.paths);
            var merged = new ShapeNode ();
            if (mode == "merge" || all.size < 2) {
                merged.paths.add_all (all);
            } else {
                var acc = all[0].to_path_data ();
                BoolOp op;
                switch (mode) {
                    case "subtract": op = BoolOp.SUBTRACT; break;
                    case "intersect": op = BoolOp.INTERSECT; break;
                    case "exclude": op = BoolOp.EXCLUDE; break;
                    default: op = BoolOp.UNION; break;
                }
                for (int i = 1; i < all.size; i++) acc = PathBoolean.apply (acc, all[i].to_path_data (), op);
                merged.paths.add_all (BezPath.from_path_data (acc));
            }
            foreach (var n in scene.nodes) n.paths.clear ();
            scene.nodes.clear ();
            scene.nodes.add (merged);
        }

        private void modify (ShapeScene scene, PropGroup g, Mat4 m) {
            double t = time;
            double sc = m.max_scale_2d ();
            switch (g.type) {
                case "shape.trim":
                    double start = g.num ("start", t) / 100.0, end = g.num ("end", t) / 100.0, off = g.num ("offset", t) / 360.0;
                    if (g.attr ("mode", "simultaneous") == "individually") {
                        var all = new Gee.ArrayList<BezPath> ();
                        foreach (var n in scene.nodes) all.add_all (n.paths);
                        double total = 0;
                        foreach (var p in all) total += p.length ();
                        double acc = 0;
                        foreach (var n in scene.nodes) {
                            var res = new Gee.ArrayList<BezPath> ();
                            foreach (var p in n.paths) {
                                double len = p.length ();
                                double s0 = total > 0 ? acc / total : 0, s1 = total > 0 ? (acc + len) / total : 1;
                                acc += len;
                                double gs = start + off, ge = end + off;
                                foreach (var piece in PathOps.trim_window (p, s0, s1, gs, ge)) res.add (piece);
                            }
                            n.paths = res;
                        }
                    } else {
                        foreach (var n in scene.nodes) {
                            var res = new Gee.ArrayList<BezPath> ();
                            foreach (var p in n.paths) res.add_all (PathOps.trim (p, start, end, off));
                            n.paths = res;
                        }
                    }
                    break;
                case "shape.round":
                    double radius = g.num ("radius", t) * sc;
                    foreach (var n in scene.nodes)
                        for (int i = 0; i < n.paths.size; i++) n.paths[i] = PathOps.round_corners (n.paths[i], radius);
                    break;
                case "shape.wiggle":
                    int pi = 0;
                    foreach (var n in scene.nodes)
                        for (int i = 0; i < n.paths.size; i++) n.paths[i] = PathOps.wiggle (n.paths[i], g.num ("size", t) * sc, g.num ("detail", t), g.choice ("points", t) == 1,
                            g.num ("wiggles", t), g.num ("correlation", t) / 100.0, g.num ("temporal-phase", t), g.num ("spatial-phase", t), (int) g.num ("seed", t) + (pi++) * 31, t);
                    break;
                case "shape.zigzag":
                    foreach (var n in scene.nodes)
                        for (int i = 0; i < n.paths.size; i++) n.paths[i] = PathOps.zigzag (n.paths[i], g.num ("size", t) * sc, (int) Math.round (g.num ("ridges", t)), g.choice ("points", t) == 1);
                    break;
                case "shape.offset":
                    foreach (var n in scene.nodes)
                        for (int i = 0; i < n.paths.size; i++) n.paths[i] = PathOps.offset (n.paths[i], g.num ("amount", t) * sc, g.attr ("join", "miter"));
                    break;
                case "shape.pucker":
                    foreach (var n in scene.nodes)
                        for (int i = 0; i < n.paths.size; i++) n.paths[i] = PathOps.pucker_bloat (n.paths[i], g.num ("amount", t) / 100.0);
                    break;
                case "shape.twist":
                    var c = g.vec ("center", t);
                    var cc = m.transform_point (Vec3 (c[0], c[1], 0));
                    foreach (var n in scene.nodes)
                        for (int i = 0; i < n.paths.size; i++) n.paths[i] = PathOps.twist (n.paths[i], g.num ("angle", t), cc.x, cc.y);
                    break;
            }
        }

        public void draw (ShapeScene scene, LayerBuffer buf, double layer_opacity = 1) {
            var to_px = Mat4.scaling (buf.scale, buf.scale, 1).multiply (Mat4.translation (-buf.x0, -buf.y0, 0));
            var px_to_layer = buf.pixel_to_layer ();
            for (int i = scene.ops.size - 1; i >= 0; i--) {
                var op = scene.ops[i];
                var paths = op.all_paths ();
                if (paths.size == 0) continue;
                var st = op.style;
                double opacity = st.num ("opacity", time) / 100.0 * op.opacity * layer_opacity;
                if (opacity <= 0) continue;
                var mode = BlendMode.from_key (st.attr ("blend", "normal"));
                bool stroke = st.type == "shape.stroke" || st.type == "shape.gradient-stroke";
                float[] cov;
                if (stroke) {
                    double sc = op.space.max_scale_2d ();
                    var ss = new StrokeStyle ();
                    ss.width = st.num ("width", time) * sc;
                    if (ss.width <= 0) continue;
                    ss.cap = StrokeStyle.cap_from (st.attr ("cap", "butt"));
                    ss.join = StrokeStyle.join_from (st.attr ("join", "miter"));
                    ss.miter = st.num ("miter-limit", time);
                    double dash = st.num ("dash", time) * sc, gap = st.num ("gap", time) * sc;
                    if (dash > 0) {
                        ss.dashes = { dash, gap > 0 ? gap : dash };
                        ss.dash_offset = st.num ("dash-offset", time) * sc;
                    }
                    double taper_s = st.num ("taper-start", time), taper_e = st.num ("taper-end", time);
                    if (taper_s > 0 || taper_e > 0) cov = tapered (paths, to_px, buf, ss.width, taper_s / 100.0, taper_e / 100.0,
                                                                   st.num ("taper-start-width", time) / 100.0, st.num ("taper-end-width", time) / 100.0);
                    else cov = Raster.stroke_coverage (paths, to_px, buf.img.width, buf.img.height, ss);
                } else {
                    cov = Raster.coverage (paths, to_px, buf.img.width, buf.img.height, st.attr ("rule", "nonzero") == "evenodd");
                }
                if (st.type == "shape.fill" || st.type == "shape.stroke") {
                    Raster.shade_solid (buf.img, cov, st.vec ("color", time), opacity, mode);
                } else {
                    var gs = new GradientSpec ();
                    gs.radial = st.attr ("gradient", "linear") == "radial";
                    var sp = op.space.transform_point (Vec3 (st.vec ("start", time)[0], st.vec ("start", time)[1], 0));
                    var ep = op.space.transform_point (Vec3 (st.vec ("end", time)[0], st.vec ("end", time)[1], 0));
                    gs.sx = sp.x;
                    gs.sy = sp.y;
                    gs.ex = ep.x;
                    gs.ey = ep.y;
                    gs.highlight = st.num ("highlight-length", time) / 100.0;
                    gs.highlight_angle = st.num ("highlight-angle", time);
                    gs.stops = st.vec ("stops", time);
                    Raster.shade_gradient (buf.img, cov, gs, px_to_layer, opacity, mode);
                }
            }
        }

        private float[] tapered (Gee.List<BezPath> paths, Mat4 to_px, LayerBuffer buf, double width, double ts, double te, double ws, double we) {
            var total = new float[buf.img.pixel_count ()];
            foreach (var p in paths) {
                var pts = PathOps.flatten (p, 0.5 / buf.scale);
                if (pts.length < 2) continue;
                double len = Polyline.length (pts, false);
                var widths = new double[pts.length];
                double acc = 0;
                for (int i = 0; i < pts.length; i++) {
                    if (i > 0) acc += pts[i].distance (pts[i - 1]);
                    double f = len > 0 ? acc / len : 0;
                    double w = width;
                    if (ts > 0 && f < ts) w = width * (ws + (1 - ws) * (f / ts));
                    if (te > 0 && f > 1 - te) w = double.min (w, width * (we + (1 - we) * ((1 - f) / te)));
                    widths[i] = w;
                }
                var outline = StrokeOutline.build (pts, widths, false);
                var cov = Raster.polygon_coverage (outline, to_px, buf.img.width, buf.img.height);
                for (size_t i = 0; i < total.length; i++) total[i] = float.min (1, total[i] + cov[i] - total[i] * cov[i]);
            }
            return total;
        }
    }
}
