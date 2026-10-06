using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    public class StrokeStyle {
        public double width = 1;
        public Cairo.LineCap cap = Cairo.LineCap.BUTT;
        public Cairo.LineJoin join = Cairo.LineJoin.MITER;
        public double miter = 4;
        public double[] dashes = {};
        public double dash_offset = 0;

        public static Cairo.LineCap cap_from (string s) {
            switch (s) {
                case "round": return Cairo.LineCap.ROUND;
                case "square": return Cairo.LineCap.SQUARE;
                default: return Cairo.LineCap.BUTT;
            }
        }

        public static Cairo.LineJoin join_from (string s) {
            switch (s) {
                case "round": return Cairo.LineJoin.ROUND;
                case "bevel": return Cairo.LineJoin.BEVEL;
                default: return Cairo.LineJoin.MITER;
            }
        }
    }

    public class GradientSpec {
        public bool radial = false;
        public double sx;
        public double sy;
        public double ex;
        public double ey;
        public double highlight = 0;
        public double highlight_angle = 0;
        public double[] stops = {};

        public void color_at (double t, out float r, out float g, out float b, out float a) {
            int n = stops.length / 5;
            r = g = b = 0;
            a = 1;
            if (n == 0) return;
            t = t.clamp (0, 1);
            if (t <= stops[0] || n == 1) {
                r = (float) stops[1];
                g = (float) stops[2];
                b = (float) stops[3];
                a = (float) stops[4];
                return;
            }
            for (int i = 0; i < n - 1; i++) {
                double p0 = stops[i * 5], p1 = stops[(i + 1) * 5];
                if (t <= p1 || i == n - 2) {
                    double u = p1 > p0 ? ((t - p0) / (p1 - p0)).clamp (0, 1) : 1;
                    r = (float) (stops[i * 5 + 1] + (stops[(i + 1) * 5 + 1] - stops[i * 5 + 1]) * u);
                    g = (float) (stops[i * 5 + 2] + (stops[(i + 1) * 5 + 2] - stops[i * 5 + 2]) * u);
                    b = (float) (stops[i * 5 + 3] + (stops[(i + 1) * 5 + 3] - stops[i * 5 + 3]) * u);
                    a = (float) (stops[i * 5 + 4] + (stops[(i + 1) * 5 + 4] - stops[i * 5 + 4]) * u);
                    return;
                }
            }
        }

        public double param_at (double x, double y) {
            double dx = ex - sx, dy = ey - sy;
            if (!radial) {
                double len2 = dx * dx + dy * dy;
                if (len2 < 1e-12) return 0;
                return ((x - sx) * dx + (y - sy) * dy) / len2;
            }
            double radius = Math.hypot (dx, dy);
            if (radius < 1e-12) return 0;
            double hl = highlight.clamp (-0.99, 0.99);
            double ang = Math.atan2 (dy, dx) + highlight_angle * Math.PI / 180.0;
            double fx = sx + Math.cos (ang) * radius * hl, fy = sy + Math.sin (ang) * radius * hl;
            double px = x - fx, py = y - fy;
            double cx = sx - fx, cy = sy - fy;
            double a = px * px + py * py;
            if (a < 1e-12) return 0;
            double b = -2 * (px * cx + py * cy);
            double c = cx * cx + cy * cy - radius * radius;
            double disc = b * b - 4 * a * c;
            if (disc < 0) return 1;
            double s = (-b + Math.sqrt (disc)) / (2 * a);
            return s > 1e-12 ? 1.0 / s : 1;
        }
    }

    namespace Raster {
        public float[] coverage (Gee.List<BezPath> paths, Mat4 to_px, int w, int h, bool even_odd = false) {
            var surface = new Cairo.ImageSurface (Cairo.Format.A8, w, h);
            var cr = new Cairo.Context (surface);
            cr.set_matrix (to_px.to_cairo ());
            cr.set_fill_rule (even_odd ? Cairo.FillRule.EVEN_ODD : Cairo.FillRule.WINDING);
            foreach (var p in paths) {
                if (p.count < 2) continue;
                var c = p.copy ();
                c.closed = true;
                c.to_cairo (cr);
            }
            cr.fill ();
            return read_a8 (surface);
        }

        public float[] stroke_coverage (Gee.List<BezPath> paths, Mat4 to_px, int w, int h, StrokeStyle st) {
            var surface = new Cairo.ImageSurface (Cairo.Format.A8, w, h);
            var cr = new Cairo.Context (surface);
            cr.set_matrix (to_px.to_cairo ());
            cr.set_line_width (st.width);
            cr.set_line_cap (st.cap);
            cr.set_line_join (st.join);
            cr.set_miter_limit (st.miter);
            if (st.dashes.length > 0) cr.set_dash (st.dashes, st.dash_offset);
            foreach (var p in paths) {
                if (p.count < 2) continue;
                p.to_cairo (cr);
            }
            cr.stroke ();
            return read_a8 (surface);
        }

        public float[] polygon_coverage (Singularity.Vector.Point[] pts, Mat4 to_px, int w, int h) {
            var surface = new Cairo.ImageSurface (Cairo.Format.A8, w, h);
            var cr = new Cairo.Context (surface);
            cr.set_matrix (to_px.to_cairo ());
            if (pts.length > 2) {
                cr.move_to (pts[0].x, pts[0].y);
                for (int i = 1; i < pts.length; i++) cr.line_to (pts[i].x, pts[i].y);
                cr.close_path ();
                cr.fill ();
            }
            return read_a8 (surface);
        }

        public float[] read_a8 (Cairo.ImageSurface surface) {
            surface.flush ();
            int w = surface.get_width (), h = surface.get_height (), stride = surface.get_stride ();
            unowned uint8[] data = surface.get_data ();
            var out_cov = new float[(size_t) w * h];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++) out_cov[(size_t) y * w + x] = data[y * stride + x] / 255.0f;
            return out_cov;
        }

        public void shade_solid (FloatImage dst, float[] cov, double[] color, double opacity, BlendMode mode = BlendMode.NORMAL) {
            float a = (float) (color.length > 3 ? color[3] * opacity : opacity);
            float r = (float) color[0], g = (float) color[1], b = (float) color[2];
            if (mode != BlendMode.NORMAL) {
                var tmp = new FloatImage (dst.width, dst.height);
                size_t n = tmp.pixel_count ();
                for (size_t i = 0; i < n; i++) {
                    float k = cov[i] * a;
                    tmp.data[i * 4] = r * k;
                    tmp.data[i * 4 + 1] = g * k;
                    tmp.data[i * 4 + 2] = b * k;
                    tmp.data[i * 4 + 3] = k;
                }
                Pixels.blend (dst, new CompImage (tmp, 0, 0), mode, true, false);
                return;
            }
            Parallel.range (dst.height, (s, e) => {
                for (size_t i = (size_t) s * dst.width; i < (size_t) e * dst.width; i++) {
                    float k = cov[i] * a;
                    if (k <= 0) continue;
                    float inv = 1 - k;
                    dst.data[i * 4] = r * k + dst.data[i * 4] * inv;
                    dst.data[i * 4 + 1] = g * k + dst.data[i * 4 + 1] * inv;
                    dst.data[i * 4 + 2] = b * k + dst.data[i * 4 + 2] * inv;
                    dst.data[i * 4 + 3] = k + dst.data[i * 4 + 3] * inv;
                }
            });
        }

        public void shade_gradient (FloatImage dst, float[] cov, GradientSpec grad, Mat4 px_to_space, double opacity, BlendMode mode = BlendMode.NORMAL) {
            var tmp = new FloatImage (dst.width, dst.height);
            Parallel.range (dst.height, (s, e) => {
                for (int y = s; y < e; y++)
                    for (int x = 0; x < dst.width; x++) {
                        size_t i = (size_t) y * dst.width + x;
                        float c = cov[i];
                        if (c <= 0) continue;
                        var sp = px_to_space.transform_point (Vec3 (x + 0.5, y + 0.5, 0));
                        float r, g, b, a;
                        grad.color_at (grad.param_at (sp.x, sp.y), out r, out g, out b, out a);
                        float k = c * a * (float) opacity;
                        tmp.data[i * 4] = r * k;
                        tmp.data[i * 4 + 1] = g * k;
                        tmp.data[i * 4 + 2] = b * k;
                        tmp.data[i * 4 + 3] = k;
                    }
            });
            Pixels.blend (dst, new CompImage (tmp, 0, 0), mode, true, false);
        }
    }
}
