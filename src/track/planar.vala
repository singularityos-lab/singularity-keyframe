using Singularity.Imaging;
using Singularity.Imaging.Tracking;

namespace Singularity.Apps.Keyframe {

    public class PlanarResult {
        public int first_frame;
        public int direction = 1;
        public double fps;
        public Gee.ArrayList<double?> corners = new Gee.ArrayList<double?> ();
        public double[] confidence = {};

        public int frames {
            get { return corners.size / 8; }
        }

        public double comp_time (int i) {
            return (first_frame + i * direction) / fps;
        }

        public double corner (int frame, int index) {
            return corners[frame * 8 + index];
        }
    }

    namespace PlanarTracker {
        public bool inside (double[] quad, double x, double y) {
            bool c = false;
            for (int i = 0, j = 3; i < 4; j = i++) {
                double xi = quad[i * 2], yi = quad[i * 2 + 1], xj = quad[j * 2], yj = quad[j * 2 + 1];
                if (((yi > y) != (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)) c = !c;
            }
            return c;
        }

        private double[] seed (Plane plane, double[] quad, int max) {
            double minx = double.MAX, miny = double.MAX, maxx = -double.MAX, maxy = -double.MAX;
            for (int i = 0; i < 4; i++) {
                minx = double.min (minx, quad[i * 2]);
                maxx = double.max (maxx, quad[i * 2]);
                miny = double.min (miny, quad[i * 2 + 1]);
                maxy = double.max (maxy, quad[i * 2 + 1]);
            }
            var all = good_features (plane, max * 3, 6, 0.01, { minx, miny, maxx - minx, maxy - miny });
            double[] r = {};
            for (int i = 0; i < all.length; i += 2) {
                if (!inside (quad, all[i], all[i + 1])) continue;
                r += all[i];
                r += all[i + 1];
                if (r.length / 2 >= max) break;
            }
            return r;
        }

        public PlanarResult track (Renderer renderer, Layer source, double start, double end, double[] corners, int max_features = 200, TrackProgress? progress = null) {
            var src = new TrackSource (renderer, source);
            var res = new PlanarResult ();
            res.fps = src.fps;
            int f0 = src.frame_of (start), f1 = src.frame_of (end);
            int step = f1 >= f0 ? 1 : -1;
            res.first_frame = f0;
            res.direction = step;
            foreach (var c in corners) res.corners.add (c);
            res.confidence = { 1 };
            var pyr0 = src.pyramid (f0);
            if (pyr0 == null) return res;
            double[] origin = seed (pyr0.levels[0], corners, max_features);
            double[] current = origin;
            var prev = pyr0;
            double[] hcur = identity ();
            int total = (f1 - f0).abs (), done = 0;
            for (int f = f0 + step; step > 0 ? f <= f1 : f >= f1; f += step) {
                var pyr = src.pyramid (f);
                if (pyr == null) break;
                bool[] ok;
                var moved = track_features (prev, pyr, current, 21, 0.25, out ok);
                double[] so = {}, dc = {};
                for (int i = 0; i < ok.length; i++) {
                    if (!ok[i]) continue;
                    so += origin[i * 2];
                    so += origin[i * 2 + 1];
                    dc += moved[i * 2];
                    dc += moved[i * 2 + 1];
                }
                bool[] inl = {};
                double[]? hm = null;
                if (so.length >= 8) hm = ransac (MotionModel.HOMOGRAPHY, so, dc, 1.5, 400, out inl);
                double conf = 0;
                if (hm != null) {
                    hcur = hm;
                    int good = 0;
                    double[] no = {}, nc = {};
                    for (int i = 0; i < inl.length; i++) {
                        if (!inl[i]) continue;
                        good++;
                        no += so[i * 2];
                        no += so[i * 2 + 1];
                        nc += dc[i * 2];
                        nc += dc[i * 2 + 1];
                    }
                    conf = (double) good / double.max (1, origin.length / 2);
                    origin = no;
                    current = nc;
                } else {
                    origin = {};
                    current = {};
                }
                var quad = new double[8];
                for (int k = 0; k < 4; k++) apply (hcur, corners[k * 2], corners[k * 2 + 1], out quad[k * 2], out quad[k * 2 + 1]);
                foreach (var q in quad) res.corners.add (q);
                res.confidence = track_append (res.confidence, conf);
                if (origin.length / 2 < max_features / 3) {
                    var hinv = invert (hcur);
                    var fresh = seed (pyr.levels[0], quad, max_features);
                    if (hinv != null) {
                        for (int i = 0; i < fresh.length; i += 2) {
                            double ox, oy;
                            apply (hinv, fresh[i], fresh[i + 1], out ox, out oy);
                            origin += ox;
                            origin += oy;
                            current += fresh[i];
                            current += fresh[i + 1];
                        }
                    }
                }
                prev = pyr;
                done++;
                if (progress != null && !progress (total > 0 ? (double) done / total : 1)) break;
            }
            return res;
        }

        public PropGroup? apply_corner_pin (PlanarResult res, Layer source, Layer target) {
            if (res.frames == 0) return null;
            var fx = EffectRegistry.add_to_layer (target, "corner-pin");
            if (fx == null) return null;
            string[] keys = { "upper-left", "upper-right", "lower-right", "lower-left" };
            for (int i = 0; i < res.frames; i++) {
                double t = res.comp_time (i);
                double lt = target.layer_time (t);
                var sw = source.world_matrix (t);
                var tinv = target.world_matrix (t).inverted ();
                if (tinv == null) continue;
                for (int k = 0; k < 4; k++) {
                    var c = sw.transform_point (Vec3 (res.corner (i, k * 2), res.corner (i, k * 2 + 1), 0));
                    var l = tinv.transform_point (c);
                    fx.prop (keys[k]).set_key (lt, { l.x, l.y });
                }
            }
            target.mark_changed ();
            return fx;
        }
    }
}
