using Singularity.Vector;

namespace Singularity.Apps.Keyframe {

    public struct Vertex {
        public double x;
        public double y;
        public double in_x;
        public double in_y;
        public double out_x;
        public double out_y;
        public double feather;

        public Vertex (double x, double y, double in_x = 0, double in_y = 0, double out_x = 0, double out_y = 0) {
            this.x = x;
            this.y = y;
            this.in_x = in_x;
            this.in_y = in_y;
            this.out_x = out_x;
            this.out_y = out_y;
            this.feather = 1;
        }
    }

    public class BezPath {
        public Vertex[] v = {};
        public bool closed = true;

        public BezPath () {
        }

        public BezPath copy () {
            var r = new BezPath ();
            r.v = v;
            r.closed = closed;
            return r;
        }

        public int count { get { return v.length; } }

        public void push (Vertex x) {
            var n = new Vertex[v.length + 1];
            for (int i = 0; i < v.length; i++) n[i] = v[i];
            n[v.length] = x;
            v = n;
        }

        public void add (double x, double y, double in_x = 0, double in_y = 0, double out_x = 0, double out_y = 0) {
            push (Vertex (x, y, in_x, in_y, out_x, out_y));
        }

        public static BezPath rect (double x, double y, double w, double h) {
            var p = new BezPath ();
            p.add (x, y);
            p.add (x + w, y);
            p.add (x + w, y + h);
            p.add (x, y + h);
            return p;
        }

        public static BezPath ellipse (double cx, double cy, double rx, double ry) {
            var p = new BezPath ();
            double k = PathData.KAPPA;
            p.add (cx, cy - ry, -rx * k, 0, rx * k, 0);
            p.add (cx + rx, cy, 0, -ry * k, 0, ry * k);
            p.add (cx, cy + ry, rx * k, 0, -rx * k, 0);
            p.add (cx - rx, cy, 0, ry * k, 0, -ry * k);
            return p;
        }

        public static BezPath polystar (double cx, double cy, int points, double outer, double inner, double outer_round, double inner_round, double rotation_deg, bool star) {
            var p = new BezPath ();
            int n = int.max (3, points);
            int total = star ? n * 2 : n;
            double angle = (rotation_deg - 90) * Math.PI / 180.0;
            double step = Math.PI * 2 / total;
            for (int i = 0; i < total; i++) {
                bool is_outer = !star || i % 2 == 0;
                double r = is_outer ? outer : inner;
                double rnd = (is_outer ? outer_round : inner_round) / 100.0;
                double a = angle + i * step;
                double x = cx + Math.cos (a) * r, y = cy + Math.sin (a) * r;
                double tl = r * rnd * (star ? 0.47829 / 2.0 : 0.25) * (2 * Math.PI / total) * 1.5;
                double tx = -Math.sin (a) * tl, ty = Math.cos (a) * tl;
                p.add (x, y, -tx, -ty, tx, ty);
            }
            return p;
        }

        public void segment (int i, out Bezier b) {
            int n = v.length;
            var a = v[i];
            var c = v[(i + 1) % n];
            b = Bezier (Point (a.x, a.y), Point (a.x + a.out_x, a.y + a.out_y), Point (c.x + c.in_x, c.y + c.in_y), Point (c.x, c.y));
        }

        public int segment_count () {
            if (v.length < 2) return 0;
            return closed ? v.length : v.length - 1;
        }

        public double length () {
            double total = 0;
            for (int i = 0; i < segment_count (); i++) {
                Bezier b;
                segment (i, out b);
                total += b.length ();
            }
            return total;
        }

        public PathData to_path_data () {
            var pd = new PathData ();
            append_to (pd);
            return pd;
        }

        public void append_to (PathData pd) {
            if (v.length == 0) return;
            pd.move_to (v[0].x, v[0].y);
            for (int i = 0; i < segment_count (); i++) {
                Bezier b;
                segment (i, out b);
                if (is_line (b)) pd.line_to (b.p3.x, b.p3.y);
                else pd.curve_to (b.p1.x, b.p1.y, b.p2.x, b.p2.y, b.p3.x, b.p3.y);
            }
            if (closed) pd.close ();
        }

        private static bool is_line (Bezier b) {
            return b.p1.x == b.p0.x && b.p1.y == b.p0.y && b.p2.x == b.p3.x && b.p2.y == b.p3.y;
        }

        public void to_cairo (Cairo.Context cr) {
            if (v.length == 0) return;
            cr.move_to (v[0].x, v[0].y);
            for (int i = 0; i < segment_count (); i++) {
                Bezier b;
                segment (i, out b);
                cr.curve_to (b.p1.x, b.p1.y, b.p2.x, b.p2.y, b.p3.x, b.p3.y);
            }
            if (closed) cr.close_path ();
        }

        public static Gee.ArrayList<BezPath> from_path_data (PathData pd) {
            var result = new Gee.ArrayList<BezPath> ();
            BezPath? cur = null;
            foreach (var s in pd.segs) {
                switch (s.kind) {
                    case SegKind.MOVE:
                        if (cur != null && cur.v.length > 0) result.add (cur);
                        cur = new BezPath ();
                        cur.closed = false;
                        cur.add (s.x, s.y);
                        break;
                    case SegKind.LINE:
                        if (cur == null) { cur = new BezPath (); cur.closed = false; cur.add (s.x, s.y); break; }
                        cur.add (s.x, s.y);
                        break;
                    case SegKind.CURVE:
                        if (cur == null) { cur = new BezPath (); cur.closed = false; cur.add (s.x, s.y); break; }
                        int last = cur.v.length - 1;
                        cur.v[last].out_x = s.x1 - cur.v[last].x;
                        cur.v[last].out_y = s.y1 - cur.v[last].y;
                        cur.add (s.x, s.y, s.x2 - s.x, s.y2 - s.y);
                        break;
                    case SegKind.CLOSE:
                        if (cur != null) {
                            cur.closed = true;
                            int n = cur.v.length;
                            if (n > 1 && (cur.v[n - 1].x - cur.v[0].x).abs () < 1e-9 && (cur.v[n - 1].y - cur.v[0].y).abs () < 1e-9) {
                                cur.v[0].in_x = cur.v[n - 1].in_x;
                                cur.v[0].in_y = cur.v[n - 1].in_y;
                                cur.v.resize (n - 1);
                            }
                            result.add (cur);
                            cur = null;
                        }
                        break;
                    default:
                        break;
                }
            }
            if (cur != null && cur.v.length > 0) result.add (cur);
            return result;
        }

        [CCode (cname = "keyframe_cairo_path", cheader_filename = "cairo_path.h", array_length_pos = 1.1)]
        private static extern double[] cairo_path_numbers (Cairo.Context context);

        public static Gee.ArrayList<BezPath> from_cairo (Cairo.Context cr) {
            var nums = cairo_path_numbers (cr);
            var pd = new PathData ();
            for (int i = 0; i + 6 < nums.length; i += 7) {
                switch ((int) nums[i]) {
                    case 0:
                        pd.move_to (nums[i + 1], nums[i + 2]);
                        break;
                    case 1:
                        pd.line_to (nums[i + 1], nums[i + 2]);
                        break;
                    case 2:
                        pd.curve_to (nums[i + 1], nums[i + 2], nums[i + 3], nums[i + 4], nums[i + 5], nums[i + 6]);
                        break;
                    default:
                        pd.close ();
                        break;
                }
            }
            return from_path_data (pd);
        }

        public void transform (Mat4 m) {
            for (int i = 0; i < v.length; i++) {
                var p = m.transform_point (Vec3 (v[i].x, v[i].y, 0));
                var pi = m.transform_point (Vec3 (v[i].x + v[i].in_x, v[i].y + v[i].in_y, 0));
                var po = m.transform_point (Vec3 (v[i].x + v[i].out_x, v[i].y + v[i].out_y, 0));
                v[i].x = p.x;
                v[i].y = p.y;
                v[i].in_x = pi.x - p.x;
                v[i].in_y = pi.y - p.y;
                v[i].out_x = po.x - p.x;
                v[i].out_y = po.y - p.y;
            }
        }

        public void bounds (ref Rect r) {
            for (int i = 0; i < v.length; i++) {
                r = r.include (v[i].x, v[i].y);
                r = r.include (v[i].x + v[i].in_x, v[i].y + v[i].in_y);
                r = r.include (v[i].x + v[i].out_x, v[i].y + v[i].out_y);
            }
        }

        public BezPath resampled (int count) {
            if (v.length == count || v.length == 0) return copy ();
            var r = copy ();
            while (r.v.length < count) {
                int best = 0;
                double best_len = -1;
                for (int i = 0; i < r.segment_count (); i++) {
                    Bezier b;
                    r.segment (i, out b);
                    double l = b.length ();
                    if (l > best_len) { best_len = l; best = i; }
                }
                if (r.segment_count () == 0) {
                    r.push (r.v[r.v.length - 1]);
                    continue;
                }
                r.split_segment (best, 0.5);
            }
            if (r.v.length > count) r.v.resize (count);
            return r;
        }

        public void split_segment (int i, double t) {
            Bezier b, left, right;
            segment (i, out b);
            b.split (t, out left, out right);
            int n = v.length;
            int next = (i + 1) % n;
            v[i].out_x = left.p1.x - left.p0.x;
            v[i].out_y = left.p1.y - left.p0.y;
            var mid = Vertex (left.p3.x, left.p3.y, left.p2.x - left.p3.x, left.p2.y - left.p3.y, right.p1.x - right.p0.x, right.p1.y - right.p0.y);
            v[next].in_x = right.p2.x - right.p3.x;
            v[next].in_y = right.p2.y - right.p3.y;
            Vertex[] nv = {};
            for (int k = 0; k <= i; k++) nv += v[k];
            nv += mid;
            for (int k = i + 1; k < n; k++) nv += v[k];
            v = nv;
        }

        public static BezPath lerp (BezPath a, BezPath b, double t) {
            int n = int.max (a.v.length, b.v.length);
            var pa = a.v.length == n ? a : a.resampled (n);
            var pb = b.v.length == n ? b : b.resampled (n);
            var r = new BezPath ();
            r.closed = t < 1 ? a.closed : b.closed;
            for (int i = 0; i < n; i++) {
                var va = pa.v[i];
                var vb = pb.v[i];
                var vr = Vertex (va.x + (vb.x - va.x) * t, va.y + (vb.y - va.y) * t,
                                 va.in_x + (vb.in_x - va.in_x) * t, va.in_y + (vb.in_y - va.in_y) * t,
                                 va.out_x + (vb.out_x - va.out_x) * t, va.out_y + (vb.out_y - va.out_y) * t);
                vr.feather = va.feather + (vb.feather - va.feather) * t;
                r.push (vr);
            }
            return r;
        }

        public Point point_at_length (double target, out double angle) {
            double acc = 0;
            angle = 0;
            for (int i = 0; i < segment_count (); i++) {
                Bezier b;
                segment (i, out b);
                double l = b.length ();
                if (acc + l >= target || i == segment_count () - 1) {
                    double t = l > 0 ? b.t_at_length ((target - acc).clamp (0, l)) : 0;
                    angle = b.angle_at (t);
                    return b.at (t);
                }
                acc += l;
            }
            return v.length > 0 ? Point (v[0].x, v[0].y) : Point (0, 0);
        }

        public BezPath reversed () {
            var r = new BezPath ();
            r.closed = closed;
            for (int i = v.length - 1; i >= 0; i--) {
                var o = v[i];
                var nv = Vertex (o.x, o.y, o.out_x, o.out_y, o.in_x, o.in_y);
                nv.feather = o.feather;
                r.push (nv);
            }
            return r;
        }

        public string serialize () {
            var sb = new StringBuilder ();
            sb.append (closed ? "c" : "o");
            foreach (var p in v) {
                sb.append_printf (" %s,%s,%s,%s,%s,%s,%s", fmt (p.x), fmt (p.y), fmt (p.in_x), fmt (p.in_y), fmt (p.out_x), fmt (p.out_y), fmt (p.feather));
            }
            return sb.str;
        }

        public static BezPath parse (string s) {
            var r = new BezPath ();
            var parts = s.strip ().split (" ");
            if (parts.length == 0) return r;
            r.closed = parts[0] == "c";
            for (int i = 1; i < parts.length; i++) {
                var n = parts[i].split (",");
                if (n.length < 6) continue;
                var vx = Vertex (double.parse (n[0]), double.parse (n[1]), double.parse (n[2]), double.parse (n[3]), double.parse (n[4]), double.parse (n[5]));
                if (n.length > 6) vx.feather = double.parse (n[6]);
                r.push (vx);
            }
            return r;
        }

        public static string fmt (double d) {
            if (d == Math.floor (d) && d.abs () < 1e15) return "%.0f".printf (d);
            char[] buf = new char[double.DTOSTR_BUF_SIZE];
            return d.format (buf, "%.6g");
        }
    }
}
