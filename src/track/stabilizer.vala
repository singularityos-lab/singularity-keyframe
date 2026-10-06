using Singularity.Imaging;
using Singularity.Imaging.Tracking;

namespace Singularity.Apps.Keyframe {

    public class StabilizerSeries {
        public double[] v;

        public StabilizerSeries (double[] v) {
            this.v = v;
        }
    }

    namespace Stabilizer {
        private Gee.HashMap<string, StabilizerSeries>? warp_cache = null;

        public string encode (double[] values) {
            var sb = new StringBuilder ();
            foreach (var v in values) {
                if (sb.len > 0) sb.append_c (' ');
                sb.append (BezPath.fmt (v));
            }
            return sb.str;
        }

        public double[] decode (string s) {
            double[] r = {};
            foreach (var p in s.strip ().split (" ")) if (p != "") r += double.parse (p);
            return r;
        }

        public void register () {
            var def = new EffectDef ("warp-stabilizer", _("Warp Stabilizer"), _("Distort"), (g) => {
                g.attrs["start"] = "0";
                g.attrs["fps"] = "30";
                g.attrs["width"] = "0";
                g.attrs["height"] = "0";
                g.attrs["motion-translation"] = "";
                g.attrs["motion-similarity"] = "";
                g.attrs["motion-perspective"] = "";
                g.add<Property> (Factory.choice ("result", _("Result"), { _("Smooth Motion"), _("No Motion") }, 0));
                g.add<Property> (Factory.percent ("smoothness", _("Smoothness"), 50).range (0, 1000));
                g.add<Property> (Factory.choice ("method", _("Method"), { _("Position"), _("Position, Scale, Rotation"), _("Perspective") }, 1));
                g.add<Property> (Factory.choice ("framing", _("Framing"), { _("Stabilize Only"), _("Stabilize, Crop"), _("Stabilize, Crop, Auto-scale") }, 2));
                g.add<Property> (Factory.percent ("max-scale", _("Maximum Scale"), 150).range (100, 1000));
            }, (ctx, fx, t) => apply_effect (ctx, fx, t));
            EffectRegistry.add (def);
        }

        private string motion_key (int method) {
            return method == 0 ? "motion-translation" : (method == 1 ? "motion-similarity" : "motion-perspective");
        }

        public double[] warps (PropGroup fx, double t) {
            int method = fx.choice ("method", t);
            bool locked = fx.choice ("result", t) == 1;
            double smooth_pct = fx.num ("smoothness", t);
            double fps = double.parse (fx.attr ("fps", "30"));
            string raw = fx.attr (motion_key (method), "");
            string key = "%s|%d|%d|%.3f|%u".printf (fx.attr ("start", "0"), method, locked ? 1 : 0, smooth_pct, raw.hash ());
            if (warp_cache == null) warp_cache = new Gee.HashMap<string, StabilizerSeries> ();
            if (warp_cache.has_key (key)) return warp_cache[key].v;
            var m = decode (raw);
            int n = m.length / 9;
            var result = new double[n * 9];
            if (n == 0) return result;
            double sigma = smooth_pct / 100.0 * fps;
            if (method == 2) {
                var comps = new double[8 * n];
                for (int c = 0; c < 8; c++) {
                    var series = new double[n];
                    for (int k = 0; k < n; k++) series[k] = m[k * 9 + c] / m[k * 9 + 8];
                    var sm = locked ? constant (series) : smooth (series, sigma);
                    for (int k = 0; k < n; k++) comps[c * n + k] = sm[k];
                }
                for (int k = 0; k < n; k++) {
                    double[] s = { comps[k], comps[n + k], comps[2 * n + k], comps[3 * n + k], comps[4 * n + k], comps[5 * n + k], comps[6 * n + k], comps[7 * n + k], 1 };
                    var inv = invert (m[k * 9:k * 9 + 9]) ?? identity ();
                    var w = multiply (s, inv);
                    for (int c = 0; c < 9; c++) result[k * 9 + c] = w[c];
                }
            } else {
                var tx = new double[n];
                var ty = new double[n];
                var ls = new double[n];
                var an = new double[n];
                double prev = 0;
                for (int k = 0; k < n; k++) {
                    double sc, a;
                    decompose_similarity (m[k * 9:k * 9 + 9], out tx[k], out ty[k], out sc, out a);
                    while (a - prev > Math.PI) a -= 2 * Math.PI;
                    while (a - prev < -Math.PI) a += 2 * Math.PI;
                    prev = a;
                    ls[k] = Math.log (double.max (1e-6, sc));
                    an[k] = a;
                }
                var stx = locked ? constant (tx) : smooth (tx, sigma);
                var sty = locked ? constant (ty) : smooth (ty, sigma);
                var sls = locked ? constant (ls) : smooth (ls, sigma);
                var san = locked ? constant (an) : smooth (an, sigma);
                for (int k = 0; k < n; k++) {
                    var s = compose_similarity (stx[k], sty[k], Math.exp (sls[k]), san[k]);
                    var inv = invert (m[k * 9:k * 9 + 9]) ?? identity ();
                    var w = multiply (s, inv);
                    for (int c = 0; c < 9; c++) result[k * 9 + c] = w[c];
                }
            }
            warp_cache[key] = new StabilizerSeries (result);
            return result;
        }

        private double[] constant (double[] series) {
            var r = new double[series.length];
            for (int i = 0; i < r.length; i++) r[i] = series.length > 0 ? series[0] : 0;
            return r;
        }

        public double auto_scale (double[] w, double width, double height, double max_scale) {
            int n = w.length / 9;
            double cx = width / 2, cy = height / 2;
            double best = 1;
            for (int k = 0; k < n; k++) {
                var inv = invert (w[k * 9:k * 9 + 9]);
                if (inv == null) continue;
                double lo = 1, hi = max_scale;
                if (!covers (inv, 1, cx, cy, width, height)) {
                    for (int it = 0; it < 30; it++) {
                        double mid = (lo + hi) / 2;
                        if (covers (inv, mid, cx, cy, width, height)) hi = mid;
                        else lo = mid;
                    }
                    best = double.max (best, hi);
                }
            }
            return double.min (best, max_scale);
        }

        private bool covers (double[] inv, double s, double cx, double cy, double w, double h) {
            double[] xs = { 0, w, w, 0, w / 2, w, w / 2, 0 };
            double[] ys = { 0, 0, h, h, 0, h / 2, h, h / 2 };
            for (int i = 0; i < xs.length; i++) {
                double qx = cx + (xs[i] - cx) / s, qy = cy + (ys[i] - cy) / s;
                double sx, sy;
                Tracking.apply (inv, qx, qy, out sx, out sy);
                if (sx < -0.01 || sy < -0.01 || sx > w + 0.01 || sy > h + 0.01) return false;
            }
            return true;
        }

        private void apply_effect (EffectContext ctx, PropGroup fx, double t) {
            var w = warps (fx, t);
            int n = w.length / 9;
            if (n == 0) return;
            double fps = double.parse (fx.attr ("fps", "30"));
            double start = double.parse (fx.attr ("start", "0"));
            int k = ((int) Math.round ((t - start) * fps)).clamp (0, n - 1);
            var inv = invert (w[k * 9:k * 9 + 9]);
            if (inv == null) return;
            double width = double.parse (fx.attr ("width", "0")), height = double.parse (fx.attr ("height", "0"));
            if (width <= 0) width = ctx.buf.width_units ();
            if (height <= 0) height = ctx.buf.height_units ();
            int framing = fx.choice ("framing", t);
            double max_scale = fx.num ("max-scale", t) / 100.0;
            double s = framing > 0 ? auto_scale (w, width, height, max_scale) : 1;
            double cx = width / 2, cy = height / 2;
            var src = ctx.buf.img;
            var buf = ctx.buf;
            var dst = new FloatImage (src.width, src.height);
            Parallel.range (dst.height, (st, en) => {
                for (int y = st; y < en; y++)
                    for (int x = 0; x < dst.width; x++) {
                        double lx, ly;
                        buf.to_layer (x + 0.5, y + 0.5, out lx, out ly);
                        if (framing == 1) {
                            double hw = width / s / 2, hh = height / s / 2;
                            if ((lx - cx).abs () > hw || (ly - cy).abs () > hh) continue;
                        } else if (framing == 2) {
                            lx = cx + (lx - cx) / s;
                            ly = cy + (ly - cy) / s;
                        }
                        double sx, sy;
                        Tracking.apply (inv, lx, ly, out sx, out sy);
                        double px, py;
                        buf.to_pixel (sx, sy, out px, out py);
                        float r, g, b, a;
                        Pixels.sample_premul (src, px, py, out r, out g, out b, out a);
                        size_t o = dst.offset (x, y);
                        dst.data[o] = r;
                        dst.data[o + 1] = g;
                        dst.data[o + 2] = b;
                        dst.data[o + 3] = a;
                    }
            });
            ctx.buf.img = dst;
        }

        public PropGroup? analyze (Renderer renderer, Layer layer, double start, double end, TrackProgress? progress = null) {
            var src = new TrackSource (renderer, layer);
            int f0 = src.frame_of (start), f1 = src.frame_of (end);
            if (f1 <= f0) return null;
            MotionModel[] kinds = { MotionModel.TRANSLATION, MotionModel.SIMILARITY, MotionModel.HOMOGRAPHY };
            var cumul = new StabilizerSeries[3];
            var acc = new StabilizerSeries[3];
            for (int m = 0; m < 3; m++) {
                acc[m] = new StabilizerSeries (identity ());
                cumul[m] = new StabilizerSeries (identity ());
            }
            var prev = src.pyramid (f0);
            if (prev == null) return null;
            int width = prev.levels[0].width, height = prev.levels[0].height;
            for (int f = f0 + 1; f <= f1; f++) {
                var pyr = src.pyramid (f);
                if (pyr == null) break;
                var feats = good_features (prev.levels[0], 300, 8, 0.01);
                bool[] ok;
                var moved = track_features (prev, pyr, feats, 21, 0.25, out ok);
                double[] s = {}, d = {};
                for (int i = 0; i < ok.length; i++) {
                    if (!ok[i]) continue;
                    s += feats[i * 2];
                    s += feats[i * 2 + 1];
                    d += moved[i * 2];
                    d += moved[i * 2 + 1];
                }
                for (int m = 0; m < 3; m++) {
                    bool[] inl;
                    var step = ransac (kinds[m], s, d, 1.5, 300, out inl) ?? identity ();
                    acc[m].v = multiply (step, acc[m].v);
                    double[] grown = {};
                    foreach (var v in cumul[m].v) grown += v;
                    foreach (var v in acc[m].v) grown += v;
                    cumul[m].v = grown;
                }
                prev = pyr;
                if (progress != null && !progress ((double) (f - f0) / (f1 - f0))) break;
            }
            var fx = EffectRegistry.add_to_layer (layer, "warp-stabilizer");
            if (fx == null) return null;
            fx.attrs["start"] = BezPath.fmt (layer.layer_time (f0 / src.fps));
            fx.attrs["fps"] = BezPath.fmt (src.fps / layer.stretch.abs ());
            fx.attrs["width"] = width.to_string ();
            fx.attrs["height"] = height.to_string ();
            fx.attrs["motion-translation"] = encode (cumul[0].v);
            fx.attrs["motion-similarity"] = encode (cumul[1].v);
            fx.attrs["motion-perspective"] = encode (cumul[2].v);
            layer.mark_changed ();
            return fx;
        }
    }
}
