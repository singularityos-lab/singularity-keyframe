using Singularity.Imaging;
using Singularity.Imaging.Tracking;

namespace Singularity.Apps.Keyframe {

    public delegate bool TrackProgress (double fraction);

    public class TrackSource {
        public Renderer renderer;
        public Layer layer;
        public RenderSettings settings;
        private Gee.HashMap<int, Pyramid> cache = new Gee.HashMap<int, Pyramid> ();
        private Gee.HashMap<int, FloatImage> images = new Gee.HashMap<int, FloatImage> ();

        public TrackSource (Renderer renderer, Layer layer) {
            this.renderer = renderer;
            this.layer = layer;
            settings = new RenderSettings ();
            settings.motion_blur = false;
            settings.use_cache = true;
        }

        public double fps {
            get { return layer.comp != null ? layer.comp.fps : 30; }
        }

        public int frame_of (double comp_t) {
            return (int) Math.round (comp_t * fps);
        }

        public double time_of (int frame) {
            return frame / fps;
        }

        public FloatImage? image (int frame) {
            if (images.has_key (frame)) return images[frame];
            var buf = renderer.layer_buffer_until (layer, time_of (frame), settings, 0, 0, 1.0, true);
            if (buf == null) return null;
            if (images.size > 6) images.clear ();
            images[frame] = buf.img;
            return buf.img;
        }

        public Pyramid? pyramid (int frame) {
            if (cache.has_key (frame)) return cache[frame];
            var img = image (frame);
            if (img == null) return null;
            if (cache.size > 6) cache.clear ();
            var p = Pyramid.from_image (img, 4);
            cache[frame] = p;
            return p;
        }
    }

    public class TrackPoint {
        public string name = "";
        public double x;
        public double y;
        public int feature = 12;
        public int search = 24;
        public double[] xs = {};
        public double[] ys = {};
        public double[] confidence = {};

        public TrackPoint (double x, double y, int feature = 12, int search = 24) {
            this.x = x;
            this.y = y;
            this.feature = feature;
            this.search = search;
        }
    }

    public class TrackResult {
        public int first_frame;
        public int direction = 1;
        public double fps;
        public Gee.ArrayList<TrackPoint> points = new Gee.ArrayList<TrackPoint> ();

        public int frames {
            get { return points.size > 0 ? points[0].xs.length : 0; }
        }

        public double comp_time (int i) {
            return (first_frame + i * direction) / fps;
        }
    }

    public double[] track_append (double[] a, double v) {
        var r = new double[a.length + 1];
        for (int i = 0; i < a.length; i++) r[i] = a[i];
        r[a.length] = v;
        return r;
    }

    public class TrackRegion {
        public double ax;
        public double ay;
        public double[] origin = {};
        public double[] current = {};
    }

    namespace PointTracker {
        public double min_confidence = 0.6;

        public TrackResult track (Renderer renderer, Layer source, double start, double end, TrackPoint[] points, bool adapt = true, TrackProgress? progress = null) {
            var src = new TrackSource (renderer, source);
            var result = new TrackResult ();
            result.fps = src.fps;
            int f0 = src.frame_of (start), f1 = src.frame_of (end);
            int step = f1 >= f0 ? 1 : -1;
            result.first_frame = f0;
            result.direction = step;
            foreach (var p in points) {
                p.xs = { p.x };
                p.ys = { p.y };
                p.confidence = { 1 };
                result.points.add (p);
            }
            var first = src.image (f0);
            if (first == null) return result;
            var ref_planes = new Plane[points.length];
            var ref_pyrs = new Pyramid[points.length];
            var ref_x = new double[points.length];
            var ref_y = new double[points.length];
            var base_plane = Plane.from_image (first);
            for (int i = 0; i < points.length; i++) {
                ref_planes[i] = base_plane;
                ref_x[i] = points[i].x;
                ref_y[i] = points[i].y;
            }
            var prev_pyr = src.pyramid (f0);
            var regions = new TrackRegion[points.length];
            for (int i = 0; i < points.length; i++) {
                ref_pyrs[i] = prev_pyr;
                int rad = int.max (points[i].feature * 2, points[i].search);
                regions[i] = new TrackRegion ();
                regions[i].ax = points[i].x;
                regions[i].ay = points[i].y;
                regions[i].origin = good_features (base_plane, 40, 4, 0.02, { points[i].x - rad, points[i].y - rad, rad * 2, rad * 2 });
                regions[i].current = regions[i].origin;
            }
            int total = (f1 - f0).abs ();
            int done = 0;
            for (int f = f0 + step; step > 0 ? f <= f1 : f >= f1; f += step) {
                var pyr = src.pyramid (f);
                if (pyr == null) break;
                var plane = pyr.levels[0];
                for (int i = 0; i < points.length; i++) {
                    var p = points[i];
                    int n = p.xs.length;
                    double px = p.xs[n - 1], py = p.ys[n - 1];
                    double vx = n > 1 ? px - p.xs[n - 2] : 0, vy = n > 1 ? py - p.ys[n - 2] : 0;
                    double gx = px + vx, gy = py + vy;
                    double lx = gx, ly = gy, err;
                    double mx = gx, my = gy, score;
                    bool lk = false;
                    var reg = regions[i];
                    double[]? sim = null;
                    if (reg.origin.length >= 8) {
                        bool[] ok;
                        var moved = track_features (prev_pyr, pyr, reg.current, 15, 0.25, out ok);
                        double[] no = {}, nc = {};
                        for (int k = 0; k < ok.length; k++) {
                            if (!ok[k]) continue;
                            no += reg.origin[k * 2];
                            no += reg.origin[k * 2 + 1];
                            nc += moved[k * 2];
                            nc += moved[k * 2 + 1];
                        }
                        reg.origin = no;
                        reg.current = nc;
                        bool[] inl = {};
                        if (no.length >= 8) sim = ransac (MotionModel.SIMILARITY, no, nc, 1.0, 200, out inl);
                    }
                    if (sim != null) {
                        lk = true;
                        Tracking.apply (sim, reg.ax, reg.ay, out mx, out my);
                        double sx, sy;
                        score = ncc_match (ref_planes[i], ref_x[i], ref_y[i], p.feature, plane, mx, my, 0, out sx, out sy);
                        if (score < min_confidence) score = min_confidence;
                    } else {
                        lk = lucas_kanade (prev_pyr, pyr, px, py, gx, gy, p.feature * 2 + 1, out lx, out ly, out err);
                        score = -1;
                    }
                    if (sim == null && lk) {
                        mx = lx;
                        my = ly;
                        double rx = mx, ry = my, rerr;
                        if (ref_pyrs[i] != prev_pyr && lucas_kanade (ref_pyrs[i], pyr, ref_x[i], ref_y[i], mx, my, p.feature * 2 + 1, out rx, out ry, out rerr) && Math.hypot (rx - mx, ry - my) < 3) {
                            mx = rx;
                            my = ry;
                        }
                        double sx, sy;
                        score = ncc_match (ref_planes[i], ref_x[i], ref_y[i], p.feature, plane, mx, my, 0, out sx, out sy);
                    }
                    if (score < min_confidence) {
                        double wx, wy;
                        double wide = ncc_match (ref_planes[i], ref_x[i], ref_y[i], p.feature, plane, px + vx, py + vy, p.search, out wx, out wy);
                        if (wide > score) {
                            score = wide;
                            mx = wx;
                            my = wy;
                        }
                    }
                    p.xs = track_append (p.xs, mx);
                    p.ys = track_append (p.ys, my);
                    p.confidence = track_append (p.confidence, score);
                    if (adapt && score < 0.9 && score > min_confidence) {
                        ref_planes[i] = plane;
                        ref_pyrs[i] = pyr;
                        ref_x[i] = mx;
                        ref_y[i] = my;
                    }
                }
                prev_pyr = pyr;
                done++;
                if (progress != null && !progress (total > 0 ? (double) done / total : 1)) break;
            }
            return result;
        }

        public Vec3 to_comp (Layer source, double t, double lx, double ly) {
            return source.world_matrix (t).transform_point (Vec3 (lx, ly, 0));
        }

        public void apply (TrackResult res, Layer source, Layer target, bool position = true, bool scale = false, bool rotation = false) {
            if (res.points.size == 0 || res.frames == 0) return;
            var tr = target.transform;
            var pos = tr.prop ("position");
            var sc = tr.prop ("scale");
            var rot = tr.prop ("rotation");
            double base_scale = sc.value_at (target.layer_time (res.comp_time (0)))[0];
            double base_scale_y = sc.value_at (target.layer_time (res.comp_time (0)))[1];
            double base_rot = rot.scalar_at (target.layer_time (res.comp_time (0)));
            var p1 = res.points[0];
            TrackPoint? p2 = res.points.size > 1 ? res.points[1] : null;
            double d0 = 0, a0 = 0;
            if (p2 != null) {
                var c1 = to_comp (source, res.comp_time (0), p1.xs[0], p1.ys[0]);
                var c2 = to_comp (source, res.comp_time (0), p2.xs[0], p2.ys[0]);
                d0 = Math.hypot (c2.x - c1.x, c2.y - c1.y);
                a0 = Math.atan2 (c2.y - c1.y, c2.x - c1.x);
            }
            var parent = target.parent_layer ();
            for (int i = 0; i < res.frames; i++) {
                double t = res.comp_time (i);
                double lt = target.layer_time (t);
                var c = to_comp (source, t, p1.xs[i], p1.ys[i]);
                if (position) {
                    var pc = c;
                    if (parent != null) {
                        var inv = parent.world_matrix (t).inverted ();
                        if (inv != null) pc = inv.transform_point (c);
                    }
                    var cur = pos.value_at (lt);
                    var v = new double[cur.length];
                    v[0] = pc.x;
                    v[1] = pc.y;
                    for (int k = 2; k < cur.length; k++) v[k] = cur[k];
                    var key = pos.set_key (lt, v);
                    key.spatial_auto = false;
                    key.tangent_in = new double[cur.length];
                    key.tangent_out = new double[cur.length];
                }
                if (p2 != null && d0 > 1e-6) {
                    var c2 = to_comp (source, t, p2.xs[i], p2.ys[i]);
                    double d = Math.hypot (c2.x - c.x, c2.y - c.y);
                    double a = Math.atan2 (c2.y - c.y, c2.x - c.x);
                    if (scale) {
                        var cur = sc.value_at (lt);
                        var v = cur;
                        v[0] = base_scale * d / d0;
                        v[1] = base_scale_y * d / d0;
                        sc.set_key (lt, v);
                    }
                    if (rotation) {
                        double da = (a - a0) * 180.0 / Math.PI;
                        while (da > 180) da -= 360;
                        while (da < -180) da += 360;
                        rot.set_key (lt, { base_rot + da });
                    }
                }
            }
            target.mark_changed ();
        }

        public Layer apply_to_new_null (TrackResult res, Layer source, bool scale = false, bool rotation = false) {
            var comp = source.comp;
            var n = Factory.null_layer (comp);
            n.name = comp.unique_layer_name (_("Track Null"));
            comp.add_layer (n, int.max (0, comp.layers.index_of (source)));
            apply (res, source, n, true, scale, rotation);
            return n;
        }
    }
}
