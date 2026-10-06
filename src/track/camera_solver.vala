using Singularity.Imaging;
using Singularity.Imaging.Tracking;

namespace Singularity.Apps.Keyframe {

    public class FeatureTrack {
        public double[] xs;
        public double[] ys;
        public bool[] valid;

        public FeatureTrack (int frames) {
            xs = new double[frames];
            ys = new double[frames];
            valid = new bool[frames];
        }

        public int count () {
            int c = 0;
            foreach (var v in valid) if (v) c++;
            return c;
        }
    }

    public class CameraSolve {
        public int frames;
        public double zoom;
        public double cx;
        public double cy;
        public double[] poses;
        public double[] points;
        public bool[] point_ok;
        public double error_px = 0;
        public int first_frame = 0;
        public double fps = 30;

        public Vec3 position (int k) {
            return Vec3 (poses[k * 6], poses[k * 6 + 1], poses[k * 6 + 2]);
        }

        public Mat4 rotation (int k) {
            return CameraSolver.rodrigues (poses[k * 6 + 3], poses[k * 6 + 4], poses[k * 6 + 5]);
        }
    }

    namespace CameraSolver {
        public Mat4 rodrigues (double rx, double ry, double rz) {
            double th = Math.sqrt (rx * rx + ry * ry + rz * rz);
            var m = new Mat4 ();
            if (th < 1e-12) return m;
            double kx = rx / th, ky = ry / th, kz = rz / th;
            double c = Math.cos (th), s = Math.sin (th), v = 1 - c;
            m.m[0] = kx * kx * v + c;
            m.m[1] = kx * ky * v - kz * s;
            m.m[2] = kx * kz * v + ky * s;
            m.m[4] = ky * kx * v + kz * s;
            m.m[5] = ky * ky * v + c;
            m.m[6] = ky * kz * v - kx * s;
            m.m[8] = kz * kx * v - ky * s;
            m.m[9] = kz * ky * v + kx * s;
            m.m[10] = kz * kz * v + c;
            return m;
        }

        public void project (double[] pose, int po, double[] pts, int pi, double zoom, double cx, double cy, out double u, out double v, out double depth) {
            var r = rodrigues (pose[po + 3], pose[po + 4], pose[po + 5]);
            double dx = pts[pi] - pose[po], dy = pts[pi + 1] - pose[po + 1], dz = pts[pi + 2] - pose[po + 2];
            double xc = r.m[0] * dx + r.m[4] * dy + r.m[8] * dz;
            double yc = r.m[1] * dx + r.m[5] * dy + r.m[9] * dz;
            double zc = r.m[2] * dx + r.m[6] * dy + r.m[10] * dz;
            depth = zc;
            if (zc < 1e-6) zc = 1e-6;
            u = cx + zoom * xc / zc;
            v = cy + zoom * yc / zc;
        }

        private struct Obs {
            public int frame;
            public int point;
            public double u;
            public double v;
        }

        private bool cholesky_solve (double[] a, double[] b, int n, double[] x) {
            var l = new double[(size_t) n * n];
            for (int i = 0; i < n; i++) {
                for (int j = 0; j <= i; j++) {
                    double s = a[(size_t) i * n + j];
                    for (int k = 0; k < j; k++) s -= l[(size_t) i * n + k] * l[(size_t) j * n + k];
                    if (i == j) {
                        if (s <= 1e-12) return false;
                        l[(size_t) i * n + i] = Math.sqrt (s);
                    } else {
                        l[(size_t) i * n + j] = s / l[(size_t) j * n + j];
                    }
                }
            }
            var y = new double[n];
            for (int i = 0; i < n; i++) {
                double s = b[i];
                for (int k = 0; k < i; k++) s -= l[(size_t) i * n + k] * y[k];
                y[i] = s / l[(size_t) i * n + i];
            }
            for (int i = n - 1; i >= 0; i--) {
                double s = y[i];
                for (int k = i + 1; k < n; k++) s -= l[(size_t) k * n + i] * x[k];
                x[i] = s / l[(size_t) i * n + i];
            }
            return true;
        }

        private double total_error (Obs[] obs, double[] poses, double[] pts, double zoom, double cx, double cy, double prior_w, double target_depth, int[] point_cols) {
            double e = 0;
            foreach (var o in obs) {
                if (point_cols[o.point] < -1) continue;
                double u, v, d;
                project (poses, o.frame * 6, pts, o.point * 3, zoom, cx, cy, out u, out v, out d);
                e += (u - o.u) * (u - o.u) + (v - o.v) * (v - o.v);
                if (d < 1) e += 1e6;
            }
            if (prior_w > 0) {
                double r = mean_depth (poses, pts, point_cols) - target_depth;
                e += prior_w * prior_w * r * r;
            }
            return e;
        }

        private double mean_depth (double[] poses, double[] pts, int[] point_cols) {
            double s = 0;
            int c = 0;
            for (int p = 0; p < pts.length / 3; p++) {
                if (point_cols[p] < -1) continue;
                double u, v, d;
                project (poses, 0, pts, p * 3, 1, 0, 0, out u, out v, out d);
                s += d;
                c++;
            }
            return c > 0 ? s / c : 0;
        }

        private void bundle (Obs[] obs, double[] poses, double[] pts, int frames, double zoom, double cx, double cy, bool optimize_points, int fixed_until, int iterations, double target_depth, int[] point_cols, int only_frame = -1, bool[]? active = null) {
            int npose = 0;
            var pose_col = new int[frames];
            Obs[] all = obs;
            Obs[] used = {};
            foreach (var o in all) if (active == null || active[o.frame]) used += o;
            obs = used;
            var seen = new bool[pts.length / 3];
            foreach (var o in obs) seen[o.point] = true;
            for (int k = 0; k < frames; k++) {
                bool free = k > fixed_until && (active == null || active[k]) && (only_frame < 0 || k == only_frame);
                pose_col[k] = free ? npose * 6 : -1;
                if (free) npose++;
            }
            int npts = 0;
            var pcol = new int[pts.length / 3];
            for (int p = 0; p < pcol.length; p++) {
                if (point_cols[p] < -1 || !optimize_points || !seen[p]) pcol[p] = -1;
                else pcol[p] = npose * 6 + (npts++) * 3;
            }
            int n = npose * 6 + npts * 3;
            if (n == 0) return;
            double prior_w = optimize_points ? 4.0 : 0;
            double lambda = 1e-3;
            double err = total_error (obs, poses, pts, zoom, cx, cy, prior_w, target_depth, point_cols);
            for (int it = 0; it < iterations; it++) {
                var jtj = new double[(size_t) n * n];
                var jtr = new double[n];
                foreach (var o in obs) {
                    if (point_cols[o.point] < -1) continue;
                    int pc = pose_col[o.frame], qc = pcol[o.point];
                    if (pc < 0 && qc < 0) continue;
                    double u0, v0, d0;
                    project (poses, o.frame * 6, pts, o.point * 3, zoom, cx, cy, out u0, out v0, out d0);
                    double ru = u0 - o.u, rv = v0 - o.v;
                    var ju = new double[9];
                    var jv = new double[9];
                    var cols = new int[9];
                    for (int c = 0; c < 9; c++) cols[c] = -1;
                    for (int c = 0; c < 6; c++) {
                        if (pc < 0) break;
                        int idx = o.frame * 6 + c;
                        double old = poses[idx], h = c < 3 ? 1e-3 * double.max (1, old.abs ()) : 1e-6;
                        poses[idx] = old + h;
                        double u1, v1, d1;
                        project (poses, o.frame * 6, pts, o.point * 3, zoom, cx, cy, out u1, out v1, out d1);
                        poses[idx] = old;
                        ju[c] = (u1 - u0) / h;
                        jv[c] = (v1 - v0) / h;
                        cols[c] = pc + c;
                    }
                    for (int c = 0; c < 3; c++) {
                        if (qc < 0) break;
                        int idx = o.point * 3 + c;
                        double old = pts[idx], h = 1e-3 * double.max (1, old.abs ());
                        pts[idx] = old + h;
                        double u1, v1, d1;
                        project (poses, o.frame * 6, pts, o.point * 3, zoom, cx, cy, out u1, out v1, out d1);
                        pts[idx] = old;
                        ju[6 + c] = (u1 - u0) / h;
                        jv[6 + c] = (v1 - v0) / h;
                        cols[6 + c] = qc + c;
                    }
                    for (int a = 0; a < 9; a++) {
                        if (cols[a] < 0) continue;
                        jtr[cols[a]] += ju[a] * ru + jv[a] * rv;
                        for (int b = 0; b < 9; b++) {
                            if (cols[b] < 0) continue;
                            jtj[(size_t) cols[a] * n + cols[b]] += ju[a] * ju[b] + jv[a] * jv[b];
                        }
                    }
                }
                if (prior_w > 0 && npts > 0) {
                    double r0 = mean_depth (poses, pts, point_cols) - target_depth;
                    var jp = new double[n];
                    for (int p = 0; p < pcol.length; p++) {
                        if (pcol[p] < 0) continue;
                        for (int c = 0; c < 3; c++) {
                            int idx = p * 3 + c;
                            double old = pts[idx], h = 1e-3 * double.max (1, old.abs ());
                            pts[idx] = old + h;
                            double r1 = mean_depth (poses, pts, point_cols) - target_depth;
                            pts[idx] = old;
                            jp[pcol[p] + c] = prior_w * (r1 - r0) / h;
                        }
                    }
                    for (int a = 0; a < n; a++) {
                        if (jp[a] == 0) continue;
                        jtr[a] += jp[a] * prior_w * r0;
                        for (int b = 0; b < n; b++) if (jp[b] != 0) jtj[(size_t) a * n + b] += jp[a] * jp[b];
                    }
                }
                bool improved = false;
                for (int tries = 0; tries < 8; tries++) {
                    var a2 = new double[(size_t) n * n];
                    for (size_t i = 0; i < a2.length; i++) a2[i] = jtj[i];
                    for (int i = 0; i < n; i++) a2[(size_t) i * n + i] += lambda * (jtj[(size_t) i * n + i] + 1e-6);
                    var delta = new double[n];
                    var rhs = new double[n];
                    for (int i = 0; i < n; i++) rhs[i] = -jtr[i];
                    if (!cholesky_solve (a2, rhs, n, delta)) {
                        lambda *= 10;
                        continue;
                    }
                    var np = poses.copy ();
                    var nq = pts.copy ();
                    for (int k = 0; k < frames; k++) if (pose_col[k] >= 0) for (int c = 0; c < 6; c++) np[k * 6 + c] += delta[pose_col[k] + c];
                    for (int p = 0; p < pcol.length; p++) if (pcol[p] >= 0) for (int c = 0; c < 3; c++) nq[p * 3 + c] += delta[pcol[p] + c];
                    double ne = total_error (obs, np, nq, zoom, cx, cy, prior_w, target_depth, point_cols);
                    if (ne < err) {
                        for (int i = 0; i < poses.length; i++) poses[i] = np[i];
                        for (int i = 0; i < pts.length; i++) pts[i] = nq[i];
                        bool converged = (err - ne) < 1e-9 * err;
                        err = ne;
                        lambda = double.max (1e-9, lambda / 5);
                        improved = true;
                        if (converged) it = iterations;
                        break;
                    }
                    lambda *= 10;
                }
                if (!improved) break;
            }
        }

        public CameraSolve? solve (Gee.List<FeatureTrack> tracks, int frames, int width, int height, double zoom, int iterations = 40) {
            var res = new CameraSolve ();
            res.frames = frames;
            res.zoom = zoom;
            res.cx = width / 2.0;
            res.cy = height / 2.0;
            Obs[] obs = {};
            var usable = new Gee.ArrayList<FeatureTrack> ();
            foreach (var tr in tracks) if (tr.count () >= 3) usable.add (tr);
            if (usable.size < 6 || frames < 2) return null;
            int npt = usable.size;
            var poses = new double[frames * 6];
            for (int k = 0; k < frames; k++) {
                poses[k * 6] = res.cx;
                poses[k * 6 + 1] = res.cy;
                poses[k * 6 + 2] = -zoom;
            }
            var pts = new double[npt * 3];
            var point_cols = new int[npt];
            for (int p = 0; p < npt; p++) {
                var tr = usable[p];
                int f = 0;
                while (!tr.valid[f]) f++;
                pts[p * 3] = res.cx + (tr.xs[f] - res.cx);
                pts[p * 3 + 1] = res.cy + (tr.ys[f] - res.cy);
                pts[p * 3 + 2] = 0;
                for (int k = 0; k < frames; k++) {
                    if (!tr.valid[k]) continue;
                    Obs o = { k, p, tr.xs[k], tr.ys[k] };
                    obs += o;
                }
            }
            int last = frames - 1;
            double mu = 0, mv = 0;
            int shared = 0;
            foreach (var tr in usable) {
                if (!tr.valid[0] || !tr.valid[last]) continue;
                mu += tr.xs[last] - tr.xs[0];
                mv += tr.ys[last] - tr.ys[0];
                shared++;
            }
            if (shared > 0) {
                poses[last * 6] -= mu / shared;
                poses[last * 6 + 1] -= mv / shared;
            }
            var pair = new bool[frames];
            pair[0] = true;
            pair[last] = true;
            bundle (obs, poses, pts, frames, zoom, res.cx, res.cy, true, 0, 80, zoom, point_cols, -1, pair);
            for (int k = 1; k < last; k++) {
                double f = (double) k / last;
                for (int c = 0; c < 6; c++) poses[k * 6 + c] = poses[c] + (poses[last * 6 + c] - poses[c]) * f;
                bundle (obs, poses, pts, frames, zoom, res.cx, res.cy, false, 0, 30, zoom, point_cols, k);
            }
            bundle (obs, poses, pts, frames, zoom, res.cx, res.cy, true, 0, iterations, zoom, point_cols);
            for (int round = 0; round < 2; round++) {
                var perr = new double[npt];
                var pcnt = new int[npt];
                foreach (var o in obs) {
                    double u, v, d;
                    project (poses, o.frame * 6, pts, o.point * 3, zoom, res.cx, res.cy, out u, out v, out d);
                    perr[o.point] += Math.hypot (u - o.u, v - o.v);
                    pcnt[o.point]++;
                }
                bool dropped = false;
                for (int p = 0; p < npt; p++) {
                    if (point_cols[p] < -1 || pcnt[p] == 0) continue;
                    if (perr[p] / pcnt[p] > 3.0) {
                        point_cols[p] = -2;
                        dropped = true;
                    }
                }
                if (!dropped) break;
                bundle (obs, poses, pts, frames, zoom, res.cx, res.cy, true, 0, iterations, zoom, point_cols);
            }
            double total = 0;
            int count = 0;
            foreach (var o in obs) {
                if (point_cols[o.point] < -1) continue;
                double u, v, d;
                project (poses, o.frame * 6, pts, o.point * 3, zoom, res.cx, res.cy, out u, out v, out d);
                total += Math.hypot (u - o.u, v - o.v);
                count++;
            }
            res.error_px = count > 0 ? total / count : 0;
            res.poses = poses;
            res.points = pts;
            res.point_ok = new bool[npt];
            for (int p = 0; p < npt; p++) res.point_ok[p] = point_cols[p] >= -1;
            return res;
        }

        public Gee.ArrayList<FeatureTrack> track_scene (Renderer renderer, Layer source, double start, double end, int max_features = 150, TrackProgress? progress = null) {
            var src = new TrackSource (renderer, source);
            int f0 = src.frame_of (start), f1 = src.frame_of (end);
            int frames = int.max (1, f1 - f0 + 1);
            var tracks = new Gee.ArrayList<FeatureTrack> ();
            var pyr = src.pyramid (f0);
            if (pyr == null) return tracks;
            var active = new Gee.ArrayList<FeatureTrack> ();
            double[] cur = good_features (pyr.levels[0], max_features, 10, 0.01);
            for (int i = 0; i < cur.length; i += 2) {
                var t = new FeatureTrack (frames);
                t.xs[0] = cur[i];
                t.ys[0] = cur[i + 1];
                t.valid[0] = true;
                tracks.add (t);
                active.add (t);
            }
            var prev = pyr;
            for (int k = 1; k < frames; k++) {
                var next = src.pyramid (f0 + k);
                if (next == null) break;
                bool[] ok;
                var moved = track_features (prev, next, cur, 21, 0.25, out ok);
                double[] nc = {};
                var na = new Gee.ArrayList<FeatureTrack> ();
                for (int i = 0; i < ok.length; i++) {
                    if (!ok[i]) continue;
                    var t = active[i];
                    t.xs[k] = moved[i * 2];
                    t.ys[k] = moved[i * 2 + 1];
                    t.valid[k] = true;
                    na.add (t);
                    nc += moved[i * 2];
                    nc += moved[i * 2 + 1];
                }
                if (na.size < max_features / 2) {
                    var fresh = good_features (next.levels[0], max_features, 10, 0.01);
                    for (int i = 0; i < fresh.length && na.size < max_features; i += 2) {
                        bool near_existing = false;
                        for (int j = 0; j < nc.length; j += 2) if (Math.hypot (nc[j] - fresh[i], nc[j + 1] - fresh[i + 1]) < 10) near_existing = true;
                        if (near_existing) continue;
                        var t = new FeatureTrack (frames);
                        t.xs[k] = fresh[i];
                        t.ys[k] = fresh[i + 1];
                        t.valid[k] = true;
                        tracks.add (t);
                        na.add (t);
                        nc += fresh[i];
                        nc += fresh[i + 1];
                    }
                }
                active = na;
                cur = nc;
                prev = next;
                if (progress != null && !progress ((double) k / (frames - 1))) break;
            }
            return tracks;
        }

        public void euler_xyz (Mat4 r, out double a, out double b, out double c) {
            b = Math.asin (r.m[2].clamp (-1, 1));
            if (Math.cos (b).abs () > 1e-6) {
                c = Math.atan2 (-r.m[1], r.m[0]);
                a = Math.atan2 (-r.m[6], r.m[10]);
            } else {
                c = 0;
                a = Math.atan2 (r.m[9], r.m[5]);
            }
            a *= 180.0 / Math.PI;
            b *= 180.0 / Math.PI;
            c *= 180.0 / Math.PI;
        }

        public Layer create_layers (CameraSolve s, Composition comp, double start, bool nulls = true, bool ground = true) {
            var cam = Factory.camera (comp);
            cam.name = comp.unique_layer_name (_("Solved Camera"));
            var cg = cam.root.group ("camera");
            cg.attrs["one-node"] = "true";
            cg.prop ("zoom").value = { s.zoom };
            var pos = cam.transform.prop ("position");
            var ori = cam.transform.prop ("orientation");
            for (int k = 0; k < s.frames; k++) {
                double t = cam.layer_time (start + k / comp.fps);
                var p = s.position (k);
                var key = pos.set_key (t, { p.x, p.y, p.z });
                key.spatial_auto = false;
                key.tangent_in = { 0, 0, 0 };
                key.tangent_out = { 0, 0, 0 };
                double a, b, c;
                euler_xyz (s.rotation (k), out a, out b, out c);
                ori.set_key (t, { a, b, c });
            }
            comp.add_layer (cam);
            if (nulls) {
                int idx = 0;
                for (int p = 0; p < s.points.length / 3; p++) {
                    if (!s.point_ok[p]) continue;
                    var n = Factory.null_layer (comp);
                    n.three_d = true;
                    n.name = comp.unique_layer_name (_("Track Point %d").printf (++idx));
                    n.transform.prop ("anchor").value = { 50, 50, 0 };
                    n.transform.prop ("scale").value = { 10, 10, 10 };
                    n.transform.prop ("position").value = { s.points[p * 3], s.points[p * 3 + 1], s.points[p * 3 + 2] };
                    comp.add_layer (n, comp.layers.size);
                }
            }
            if (ground) {
                var g = ground_plane (s, comp);
                if (g != null) comp.add_layer (g, comp.layers.size);
            }
            return cam;
        }

        public Layer? ground_plane (CameraSolve s, Composition comp) {
            double cx = 0, cy = 0, cz = 0;
            int n = 0;
            for (int p = 0; p < s.points.length / 3; p++) {
                if (!s.point_ok[p]) continue;
                cx += s.points[p * 3];
                cy += s.points[p * 3 + 1];
                cz += s.points[p * 3 + 2];
                n++;
            }
            if (n < 3) return null;
            cx /= n;
            cy /= n;
            cz /= n;
            var cov = new double[9];
            for (int p = 0; p < s.points.length / 3; p++) {
                if (!s.point_ok[p]) continue;
                double[] d = { s.points[p * 3] - cx, s.points[p * 3 + 1] - cy, s.points[p * 3 + 2] - cz };
                for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++) cov[i * 3 + j] += d[i] * d[j];
            }
            var normal = smallest_eigenvector (cov);
            var z = Vec3 (normal[0], normal[1], normal[2]).normalized ();
            var up = z.x.abs () < 0.9 ? Vec3 (1, 0, 0) : Vec3 (0, 1, 0);
            var x = up.sub (z.scale (up.dot (z))).normalized ();
            var y = z.cross (x).normalized ();
            var r = new Mat4 ();
            r.m[0] = x.x;
            r.m[4] = x.y;
            r.m[8] = x.z;
            r.m[1] = y.x;
            r.m[5] = y.y;
            r.m[9] = y.z;
            r.m[2] = z.x;
            r.m[6] = z.y;
            r.m[10] = z.z;
            double a, b, c;
            euler_xyz (r, out a, out b, out c);
            var l = Factory.null_layer (comp);
            l.three_d = true;
            l.name = comp.unique_layer_name (_("Ground Plane"));
            l.transform.prop ("position").value = { cx, cy, cz };
            l.transform.prop ("orientation").value = { a, b, c };
            return l;
        }

        private double[] smallest_eigenvector (double[] m) {
            var a = new double[9];
            for (int i = 0; i < 9; i++) a[i] = m[i];
            var v = new double[] { 1, 0, 0, 0, 1, 0, 0, 0, 1 };
            for (int sweep = 0; sweep < 50; sweep++) {
                for (int p = 0; p < 2; p++)
                    for (int q = p + 1; q < 3; q++) {
                        double apq = a[p * 3 + q];
                        if (apq.abs () < 1e-14) continue;
                        double theta = (a[q * 3 + q] - a[p * 3 + p]) / (2 * apq);
                        double t = (theta >= 0 ? 1 : -1) / (theta.abs () + Math.sqrt (theta * theta + 1));
                        double c = 1 / Math.sqrt (t * t + 1), s = t * c;
                        for (int k = 0; k < 3; k++) {
                            double akp = a[k * 3 + p], akq = a[k * 3 + q];
                            a[k * 3 + p] = c * akp - s * akq;
                            a[k * 3 + q] = s * akp + c * akq;
                        }
                        for (int k = 0; k < 3; k++) {
                            double apk = a[p * 3 + k], aqk = a[q * 3 + k];
                            a[p * 3 + k] = c * apk - s * aqk;
                            a[q * 3 + k] = s * apk + c * aqk;
                        }
                        for (int k = 0; k < 3; k++) {
                            double vkp = v[k * 3 + p], vkq = v[k * 3 + q];
                            v[k * 3 + p] = c * vkp - s * vkq;
                            v[k * 3 + q] = s * vkp + c * vkq;
                        }
                    }
            }
            int best = 0;
            for (int i = 1; i < 3; i++) if (a[i * 3 + i] < a[best * 3 + best]) best = i;
            return { v[best], v[3 + best], v[6 + best] };
        }
    }
}
