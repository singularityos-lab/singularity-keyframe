using Singularity.Vector;

namespace Singularity.Apps.Keyframe {

    namespace Masks {
        public bool active (Layer l) {
            var m = l.masks;
            if (m == null) return false;
            foreach (var c in m.children) {
                var g = c as PropGroup;
                if (g != null && g.enabled && g.attr ("mode", "add") != "none") return true;
            }
            return false;
        }

        public float[]? combined (Layer l, double t, LayerBuffer buf) {
            var group = l.masks;
            if (group == null) return null;
            float[]? acc = null;
            int w = buf.img.width, h = buf.img.height;
            var to_px = Mat4.scaling (buf.scale, buf.scale, 1).multiply (Mat4.translation (-buf.x0, -buf.y0, 0));
            foreach (var c in group.children) {
                var g = c as PropGroup;
                if (g == null || !g.enabled) continue;
                string mode = g.attr ("mode", "add");
                if (mode == "none") continue;
                var m = single (g, t, to_px, w, h, buf.scale);
                if (acc == null) {
                    acc = new float[(size_t) w * h];
                    float init = (mode == "subtract" || mode == "intersect" || mode == "darken") ? 1 : 0;
                    for (size_t i = 0; i < acc.length; i++) acc[i] = init;
                }
                combine (acc, m, mode);
            }
            return acc;
        }

        public void combine (float[] acc, float[] m, string mode) {
            for (size_t i = 0; i < acc.length; i++) {
                float a = acc[i], b = m[i];
                switch (mode) {
                    case "subtract": a = a * (1 - b); break;
                    case "intersect": a = a * b; break;
                    case "lighten": a = float.max (a, b); break;
                    case "darken": a = float.min (a, b); break;
                    case "difference": a = (a - b).abs (); break;
                    default: a = a + b - a * b; break;
                }
                acc[i] = a;
            }
        }

        public float[] single (PropGroup g, double t, Mat4 to_px, int w, int h, double scale) {
            var pp = g.prop ("path");
            var path = pp != null ? pp.path_at (t) : new BezPath ();
            double expansion = g.num ("expansion", t);
            var feather = g.vec ("feather", t);
            double opacity = g.num ("opacity", t) / 100.0;
            bool inverted = g.attr ("inverted", "false") == "true";
            bool variable = g.toggle ("variable-feather", t);
            var list = new Gee.ArrayList<BezPath> ();
            if (expansion.abs () > 1e-6 && !variable) list.add (PathOps.offset (path, -expansion, "round"));
            else list.add (path);
            float[] cov;
            if (variable && feather[0] > 0) {
                cov = variable_feather (path, to_px, w, h, feather[0] * scale, expansion * scale);
            } else {
                cov = Raster.coverage (list, to_px, w, h);
                double fx = feather[0] * scale, fy = (feather.length > 1 ? feather[1] : feather[0]) * scale;
                if (fx > 0.01 || fy > 0.01) Blur.gaussian_plane (cov, w, h, fx / 2.5, fy / 2.5);
            }
            for (size_t i = 0; i < cov.length; i++) {
                float v = cov[i].clamp (0, 1);
                if (inverted) v = 1 - v;
                cov[i] = v * (float) opacity;
            }
            return cov;
        }

        public float[] variable_feather (BezPath path, Mat4 to_px, int w, int h, double base_feather, double expansion_px) {
            var list = new Gee.ArrayList<BezPath> ();
            list.add (path);
            var hard = Raster.coverage (list, to_px, w, h);
            var sd = DistanceField.signed_distance (hard, w, h);
            var px_path = path.copy ();
            px_path.transform (to_px);
            Point[] samples = {};
            double[] widths = {};
            for (int i = 0; i < px_path.segment_count (); i++) {
                Bezier b;
                px_path.segment (i, out b);
                var fa = px_path.v[i].feather, fb = px_path.v[(i + 1) % px_path.count].feather;
                int k = int.max (2, (int) (b.length () / 4));
                for (int s = 0; s < k; s++) {
                    double u = (double) s / k;
                    samples += b.at (u);
                    widths += (fa + (fb - fa) * u) * base_feather;
                }
            }
            var cell = 32;
            int gw = w / cell + 1, gh = h / cell + 1;
            var grid = new Gee.ArrayList<Gee.ArrayList<int>> ();
            for (int i = 0; i < gw * gh; i++) grid.add (new Gee.ArrayList<int> ());
            for (int i = 0; i < samples.length; i++) {
                int gx = ((int) (samples[i].x / cell)).clamp (0, gw - 1), gy = ((int) (samples[i].y / cell)).clamp (0, gh - 1);
                grid[gy * gw + gx].add (i);
            }
            var r = new float[(size_t) w * h];
            Singularity.Imaging.Parallel.range (h, (s, e) => {
                for (int y = s; y < e; y++)
                    for (int x = 0; x < w; x++) {
                        size_t i = (size_t) y * w + x;
                        double d = sd[i] + expansion_px;
                        double fw = base_feather;
                        if (samples.length > 0) {
                            int gx = (x / cell).clamp (0, gw - 1), gy = (y / cell).clamp (0, gh - 1);
                            double best = double.MAX;
                            for (int ring = 0; ring < int.max (gw, gh) && best == double.MAX; ring++) {
                                for (int yy = gy - ring; yy <= gy + ring; yy++)
                                    for (int xx = gx - ring; xx <= gx + ring; xx++) {
                                        if (xx < 0 || yy < 0 || xx >= gw || yy >= gh) continue;
                                        if ((xx - gx).abs () != ring && (yy - gy).abs () != ring) continue;
                                        foreach (var idx in grid[yy * gw + xx]) {
                                            double dd = Math.hypot (samples[idx].x - x, samples[idx].y - y);
                                            if (dd < best) {
                                                best = dd;
                                                fw = widths[idx];
                                            }
                                        }
                                    }
                            }
                        }
                        if (fw < 0.5) r[i] = d >= 0 ? 1 : 0;
                        else r[i] = (float) (0.5 + 0.5 * (d / fw).clamp (-1, 1));
                        if (fw >= 0.5) {
                            double u = (d / fw + 1) / 2;
                            u = u.clamp (0, 1);
                            r[i] = (float) (u * u * (3 - 2 * u));
                        }
                    }
            });
            return r;
        }
    }
}
