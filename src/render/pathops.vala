using Singularity.Vector;

namespace Singularity.Apps.Keyframe {

    namespace PathOps {
        public Point[] flatten (BezPath p, double tolerance = 0.25) {
            Point[] pts = {};
            if (p.count == 0) return pts;
            pts += Point (p.v[0].x, p.v[0].y);
            for (int i = 0; i < p.segment_count (); i++) {
                Bezier b;
                p.segment (i, out b);
                var f = b.flatten (double.max (tolerance, 0.01));
                for (int k = 1; k < f.length; k++) pts += f[k];
            }
            return pts;
        }

        public BezPath sub_path (BezPath p, double a, double b) {
            var r = new BezPath ();
            r.closed = false;
            int n = p.segment_count ();
            if (n == 0) return r;
            var lens = new double[n];
            double total = 0;
            for (int i = 0; i < n; i++) {
                Bezier bz;
                p.segment (i, out bz);
                lens[i] = bz.length ();
                total += lens[i];
            }
            if (total <= 0) return r;
            double ta = a.clamp (0, 1) * total, tb = b.clamp (0, 1) * total;
            if (tb <= ta) return r;
            double c0 = 0;
            for (int i = 0; i < n; i++) {
                double c1 = c0 + lens[i];
                if (c1 < ta - 1e-9 || c0 > tb + 1e-9 || lens[i] <= 0) {
                    c0 = c1;
                    continue;
                }
                Bezier bz;
                p.segment (i, out bz);
                double l0 = double.max (0, ta - c0), l1 = double.min (lens[i], tb - c0);
                double t0 = l0 <= 0 ? 0 : bz.t_at_length (l0);
                double t1 = l1 >= lens[i] ? 1 : bz.t_at_length (l1);
                if (t1 <= t0) {
                    c0 = c1;
                    continue;
                }
                var piece = bz.sub (t0, t1);
                if (r.count == 0) {
                    r.add (piece.p0.x, piece.p0.y, 0, 0, piece.p1.x - piece.p0.x, piece.p1.y - piece.p0.y);
                } else {
                    int last = r.count - 1;
                    r.v[last].out_x = piece.p1.x - piece.p0.x;
                    r.v[last].out_y = piece.p1.y - piece.p0.y;
                }
                r.add (piece.p3.x, piece.p3.y, piece.p2.x - piece.p3.x, piece.p2.y - piece.p3.y, 0, 0);
                c0 = c1;
            }
            return r;
        }

        private void window (double start, double end, double off, out double s1, out double e1, out double s2, out double e2) {
            double s = double.min (start, end) + off, e = double.max (start, end) + off;
            s2 = e2 = -1;
            if (e - s >= 1 - 1e-9) {
                s1 = 0;
                e1 = 1;
                return;
            }
            double fs = s - Math.floor (s);
            double fe = fs + (e - s);
            if (fe <= 1 + 1e-12) {
                s1 = fs;
                e1 = double.min (fe, 1);
            } else {
                s1 = fs;
                e1 = 1;
                s2 = 0;
                e2 = fe - 1;
            }
        }

        public Gee.ArrayList<BezPath> trim (BezPath p, double start, double end, double off) {
            var r = new Gee.ArrayList<BezPath> ();
            if ((end - start).abs () < 1e-9) return r;
            double s1, e1, s2, e2;
            window (start, end, off, out s1, out e1, out s2, out e2);
            if (s1 <= 0 && e1 >= 1 && s2 < 0) {
                r.add (p.copy ());
                return r;
            }
            var first = sub_path (p, s1, e1);
            if (s2 >= 0) {
                var second = sub_path (p, s2, e2);
                if (p.closed && first.count > 0 && second.count > 0) {
                    int last = first.count - 1;
                    first.v[last].out_x = second.v[0].out_x;
                    first.v[last].out_y = second.v[0].out_y;
                    for (int i = 1; i < second.count; i++) first.push (second.v[i]);
                } else if (second.count > 0) {
                    r.add (second);
                }
            }
            if (first.count > 0) r.add (first);
            return r;
        }

        public Gee.ArrayList<BezPath> trim_window (BezPath p, double s0, double s1, double gs, double ge) {
            var r = new Gee.ArrayList<BezPath> ();
            double a1, b1, a2, b2;
            window (gs, ge, 0, out a1, out b1, out a2, out b2);
            double span = s1 - s0;
            if (span <= 0) return r;
            double[] wins = { a1, b1, a2, b2 };
            for (int k = 0; k < 2; k++) {
                double wa = wins[k * 2], wb = wins[k * 2 + 1];
                if (wa < 0) continue;
                double ia = double.max (wa, s0), ib = double.min (wb, s1);
                if (ib <= ia) continue;
                if (ia <= s0 + 1e-12 && ib >= s1 - 1e-12) {
                    r.add (p.copy ());
                    continue;
                }
                var piece = sub_path (p, (ia - s0) / span, (ib - s0) / span);
                if (piece.count > 0) r.add (piece);
            }
            return r;
        }

        private bool is_corner (Vertex v) {
            return v.in_x == 0 && v.in_y == 0 && v.out_x == 0 && v.out_y == 0;
        }

        public BezPath round_corners (BezPath p, double radius) {
            if (radius <= 0 || p.count < 3) return p;
            var r = new BezPath ();
            r.closed = p.closed;
            int n = p.count;
            for (int i = 0; i < n; i++) {
                var v = p.v[i];
                bool endpoint = !p.closed && (i == 0 || i == n - 1);
                if (endpoint || !is_corner (v)) {
                    r.push (v);
                    continue;
                }
                var prev = p.v[(i - 1 + n) % n];
                var next = p.v[(i + 1) % n];
                double px = prev.x + prev.out_x - v.x, py = prev.y + prev.out_y - v.y;
                if (prev.out_x == 0 && prev.out_y == 0) {
                    px = prev.x - v.x;
                    py = prev.y - v.y;
                }
                double nx = next.x + next.in_x - v.x, ny = next.y + next.in_y - v.y;
                if (next.in_x == 0 && next.in_y == 0) {
                    nx = next.x - v.x;
                    ny = next.y - v.y;
                }
                double lp = Math.hypot (prev.x - v.x, prev.y - v.y), ln = Math.hypot (next.x - v.x, next.y - v.y);
                double dp = Math.hypot (px, py), dn = Math.hypot (nx, ny);
                if (dp < 1e-9 || dn < 1e-9) {
                    r.push (v);
                    continue;
                }
                double d = double.min (radius, double.min (lp, ln) / 2);
                double ax = v.x + px / dp * d, ay = v.y + py / dp * d;
                double bx = v.x + nx / dn * d, by = v.y + ny / dn * d;
                double k = 1 - PathData.KAPPA;
                var va = Vertex (ax, ay, 0, 0, (v.x - ax) * (1 - k), (v.y - ay) * (1 - k));
                var vb = Vertex (bx, by, (v.x - bx) * (1 - k), (v.y - by) * (1 - k), 0, 0);
                r.push (va);
                r.push (vb);
            }
            return r;
        }

        public BezPath wiggle (BezPath p, double size, double detail, bool smooth, double wiggles, double correlation, double tphase, double sphase, int seed, double time) {
            if (size <= 0 || p.count < 2) return p;
            var r = new BezPath ();
            r.closed = p.closed;
            var pts = new Gee.ArrayList<Point?> ();
            for (int i = 0; i < p.segment_count (); i++) {
                Bezier b;
                p.segment (i, out b);
                int k = int.max (1, (int) Math.round (b.length () * detail / 100.0));
                for (int s = 0; s < k; s++) pts.add (b.at ((double) s / k));
            }
            if (!p.closed) pts.add (Point (p.v[p.count - 1].x, p.v[p.count - 1].y));
            double tt = time * wiggles + tphase / 360.0;
            double spatial = 1.0 - correlation.clamp (0, 0.99);
            int n = pts.size;
            for (int i = 0; i < n; i++) {
                double sp = i * spatial + sphase / 360.0;
                double dx = Noise.perlin2 (tt, sp, seed) * size;
                double dy = Noise.perlin2 (tt + 57.3, sp + 11.1, seed + 7) * size;
                r.add (pts[i].x + dx, pts[i].y + dy);
            }
            if (smooth) {
                int m = r.count;
                for (int i = 0; i < m; i++) {
                    if (!r.closed && (i == 0 || i == m - 1)) continue;
                    var a = r.v[(i - 1 + m) % m];
                    var c = r.v[(i + 1) % m];
                    double tx = (c.x - a.x) / 6, ty = (c.y - a.y) / 6;
                    r.v[i].in_x = -tx;
                    r.v[i].in_y = -ty;
                    r.v[i].out_x = tx;
                    r.v[i].out_y = ty;
                }
            }
            return r;
        }

        public BezPath zigzag (BezPath p, double size, int ridges, bool smooth) {
            if (ridges <= 0 || size == 0 || p.count < 2) return p;
            var r = new BezPath ();
            r.closed = p.closed;
            int sign = 1;
            for (int i = 0; i < p.segment_count (); i++) {
                Bezier b;
                p.segment (i, out b);
                int k = ridges * 2;
                for (int s = 0; s < k; s++) {
                    double t = (double) s / k;
                    var pt = b.at (t);
                    double off = s == 0 ? 0 : size * sign;
                    if (s > 0) sign = -sign;
                    double ang = b.angle_at (t);
                    double nx = -Math.sin (ang), ny = Math.cos (ang);
                    double hx = smooth ? Math.cos (ang) * b.length () / k / 2.5 : 0;
                    double hy = smooth ? Math.sin (ang) * b.length () / k / 2.5 : 0;
                    r.add (pt.x + nx * off, pt.y + ny * off, -hx, -hy, hx, hy);
                }
            }
            if (!p.closed) r.add (p.v[p.count - 1].x, p.v[p.count - 1].y);
            return r;
        }

        public BezPath offset (BezPath p, double amount, string join) {
            if (amount.abs () < 1e-9 || p.count < 2) return p;
            var pts = flatten (p, 0.3);
            if (pts.length < 2) return p;
            Point[] result;
            if (p.closed) {
                if (pts.length > 2 && pts[0].distance (pts[pts.length - 1]) < 1e-6) pts.resize (pts.length - 1);
                var edges = new Gee.ArrayList<OffsetEdge> ();
                var style = join == "round" ? CornerStyle.ROUND : (join == "bevel" ? CornerStyle.BEVEL : CornerStyle.INTERSECT);
                for (int i = 0; i < pts.length; i++) {
                    var e = new OffsetEdge ({ pts[i], pts[(i + 1) % pts.length] }, -amount);
                    e.end_corner = style;
                    edges.add (e);
                }
                result = Offset.closed (edges);
            } else {
                result = Offset.polyline (pts, amount);
            }
            var r = new BezPath ();
            r.closed = p.closed;
            foreach (var q in result) r.add (q.x, q.y);
            return r;
        }

        public BezPath pucker_bloat (BezPath p, double amount) {
            if (amount == 0 || p.count == 0) return p;
            double cx = 0, cy = 0;
            foreach (var v in p.v) {
                cx += v.x;
                cy += v.y;
            }
            cx /= p.count;
            cy /= p.count;
            var r = p.copy ();
            for (int i = 0; i < r.count; i++) {
                var v = p.v[i];
                double nx = v.x + (cx - v.x) * amount, ny = v.y + (cy - v.y) * amount;
                double ix = v.x + v.in_x, iy = v.y + v.in_y, ox = v.x + v.out_x, oy = v.y + v.out_y;
                ix += (cx - ix) * -amount;
                iy += (cy - iy) * -amount;
                ox += (cx - ox) * -amount;
                oy += (cy - oy) * -amount;
                r.v[i].x = nx;
                r.v[i].y = ny;
                r.v[i].in_x = ix - nx;
                r.v[i].in_y = iy - ny;
                r.v[i].out_x = ox - nx;
                r.v[i].out_y = oy - ny;
            }
            return r;
        }

        public BezPath twist (BezPath p, double angle, double cx, double cy) {
            if (angle == 0 || p.count == 0) return p;
            double maxd = 1e-9;
            foreach (var v in p.v) maxd = double.max (maxd, Math.hypot (v.x - cx, v.y - cy));
            var r = p.copy ();
            for (int i = 0; i < r.count; i++) {
                var v = p.v[i];
                double vx, vy, ix, iy, ox, oy;
                rot (v.x, v.y, cx, cy, angle, maxd, out vx, out vy);
                rot (v.x + v.in_x, v.y + v.in_y, cx, cy, angle, maxd, out ix, out iy);
                rot (v.x + v.out_x, v.y + v.out_y, cx, cy, angle, maxd, out ox, out oy);
                r.v[i].x = vx;
                r.v[i].y = vy;
                r.v[i].in_x = ix - vx;
                r.v[i].in_y = iy - vy;
                r.v[i].out_x = ox - vx;
                r.v[i].out_y = oy - vy;
            }
            return r;
        }

        private void rot (double x, double y, double cx, double cy, double angle, double maxd, out double ox, out double oy) {
            double d = Math.hypot (x - cx, y - cy);
            double a = angle * (d / maxd) * Math.PI / 180.0;
            double c = Math.cos (a), s = Math.sin (a);
            ox = cx + (x - cx) * c - (y - cy) * s;
            oy = cy + (x - cx) * s + (y - cy) * c;
        }
    }
}
