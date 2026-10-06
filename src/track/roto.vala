using Singularity.Imaging;
using Singularity.Imaging.Tracking;

namespace Singularity.Apps.Keyframe {

    namespace RotoBrush {
        public bool uses_local_model = false;

        private double ssd (Plane a, Plane b, double[] samples, double dx, double dy, double div) {
            double e = 0;
            int n = samples.length / 2;
            for (int i = 0; i < n; i++) {
                double x = samples[i * 2] / div, y = samples[i * 2 + 1] / div;
                double d = a.sample (x, y) - b.sample (x + dx, y + dy);
                e += d * d;
            }
            return n > 0 ? e / n : double.MAX;
        }

        private void flat_minimum (double[] grid, int side, double best, out double mx, out double my) {
            double tol = best * 0.02 + 1e-7;
            double sx = 0, sy = 0;
            int n = 0;
            for (int j = 0; j < side; j++)
                for (int i = 0; i < side; i++)
                    if (grid[j * side + i] <= best + tol) {
                        sx += i;
                        sy += j;
                        n++;
                    }
            mx = n > 0 ? sx / n : side / 2;
            my = n > 0 ? sy / n : side / 2;
        }

        public double[] inside_samples (BezPath path, LayerBuffer reference, int max_samples = 3000) {
            if (path.count < 3) return {};
            var to_px = Mat4.scaling (reference.scale, reference.scale, 1).multiply (Mat4.translation (-reference.x0, -reference.y0, 0));
            var closed = path.copy ();
            closed.closed = true;
            var list = new Gee.ArrayList<BezPath> ();
            list.add (closed);
            int w = reference.img.width, h = reference.img.height;
            var cov = Raster.coverage (list, to_px, w, h);
            int count = 0;
            for (size_t i = 0; i < cov.length; i++) if (cov[i] > 0.95f) count++;
            int stride = 1;
            while (count / (stride * stride) > max_samples) stride++;
            double[] r = {};
            for (int y = 0; y < h; y += stride)
                for (int x = 0; x < w; x += stride)
                    if (cov[(size_t) y * w + x] > 0.95f) {
                        r += x + 0.5;
                        r += y + 0.5;
                    }
            return r;
        }

        public BezPath step (Pyramid prev, Pyramid next, BezPath path, LayerBuffer reference, double snap_radius, double snap_strength, ref double vx, ref double vy) {
            var r = path.copy ();
            int n = path.count;
            if (n == 0) return r;
            var samples = inside_samples (path, reference);
            double interior = -1;
            if (samples.length >= 2) {
                interior = 0;
                for (int i = 0; i < samples.length; i += 2) interior += prev.levels[0].sample (samples[i], samples[i + 1]);
                interior /= samples.length / 2;
            }
            double dx = vx * reference.scale, dy = vy * reference.scale;
            if (samples.length >= 16 && prev.levels.length > 1 && next.levels.length > 1) {
                var a1 = prev.levels[1];
                var b1 = next.levels[1];
                int range = (int) Math.ceil (Math.hypot (dx, dy) / 2) + 8;
                double cx = Math.round (dx / 2), cy = Math.round (dy / 2);
                int side = range * 2 + 1;
                var grid = new double[side * side];
                double best = double.MAX;
                for (int j = -range; j <= range; j++)
                    for (int i = -range; i <= range; i++) {
                        double e = ssd (a1, b1, samples, cx + i, cy + j, 2);
                        grid[(j + range) * side + i + range] = e;
                        best = double.min (best, e);
                    }
                double bx, by;
                flat_minimum (grid, side, best, out bx, out by);
                bx += cx - range;
                by += cy - range;
                var a0 = prev.levels[0];
                var b0 = next.levels[0];
                double fx = bx * 2, fy = by * 2;
                for (int pass = 0; pass < 2; pass++) {
                    double step_size = pass == 0 ? 1 : 0.25;
                    var g0 = new double[49];
                    double best0 = double.MAX;
                    for (int j = -3; j <= 3; j++)
                        for (int i = -3; i <= 3; i++) {
                            double e = ssd (a0, b0, samples, fx + i * step_size, fy + j * step_size, 1);
                            g0[(j + 3) * 7 + i + 3] = e;
                            best0 = double.min (best0, e);
                        }
                    double ox, oy;
                    flat_minimum (g0, 7, best0, out ox, out oy);
                    fx += (ox - 3) * step_size;
                    fy += (oy - 3) * step_size;
                }
                dx = fx;
                dy = fy;
            } else {
                double sx = 0, sy = 0;
                int good = 0;
                for (int i = 0; i < n; i++) {
                    double px, py, nx, ny, err;
                    reference.to_pixel (path.v[i].x, path.v[i].y, out px, out py);
                    if (lucas_kanade (prev, next, px, py, px + dx, py + dy, 21, out nx, out ny, out err) && err < 0.3) {
                        sx += nx - px;
                        sy += ny - py;
                        good++;
                    }
                }
                if (good > 0) {
                    dx = sx / good;
                    dy = sy / good;
                }
            }
            vx = dx / reference.scale;
            vy = dy / reference.scale;
            for (int i = 0; i < n; i++) {
                r.v[i].x += vx;
                r.v[i].y += vy;
            }
            if (snap_radius > 0 && snap_strength > 0) {
                var snapped = r.copy ();
                snap (snapped, next.levels[0], reference, snap_radius, 1.0, interior);
                double[] sp = {}, dp = {};
                for (int i = 0; i < n; i++) {
                    sp += r.v[i].x;
                    sp += r.v[i].y;
                    dp += snapped.v[i].x;
                    dp += snapped.v[i].y;
                }
                bool[] inl = {};
                var sim = n >= 3 ? ransac (MotionModel.SIMILARITY, sp, dp, 3.0, 100, out inl) : null;
                if (sim != null) {
                    for (int i = 0; i < n; i++) {
                        var v = r.v[i];
                        double nx, ny, ix, iy, ox, oy;
                        Tracking.apply (sim, v.x, v.y, out nx, out ny);
                        Tracking.apply (sim, v.x + v.in_x, v.y + v.in_y, out ix, out iy);
                        Tracking.apply (sim, v.x + v.out_x, v.y + v.out_y, out ox, out oy);
                        r.v[i].x = nx;
                        r.v[i].y = ny;
                        r.v[i].in_x = ix - nx;
                        r.v[i].in_y = iy - ny;
                        r.v[i].out_x = ox - nx;
                        r.v[i].out_y = oy - ny;
                    }
                }
                snap (r, next.levels[0], reference, snap_radius * 0.5, snap_strength, interior);
                double ax = 0, ay = 0, bx = 0, by = 0;
                for (int i = 0; i < n; i++) {
                    ax += path.v[i].x / n;
                    ay += path.v[i].y / n;
                    bx += r.v[i].x / n;
                    by += r.v[i].y / n;
                }
                vx = bx - ax;
                vy = by - ay;
            }
            return r;
        }

        public void snap (BezPath p, Plane plane, LayerBuffer reference, double radius, double strength, double interior = -1) {
            int n = p.count;
            var moved = new double[n * 2];
            for (int i = 0; i < n; i++) {
                var a = p.v[(i - 1 + n) % n];
                var b = p.v[(i + 1) % n];
                double tx = b.x - a.x, ty = b.y - a.y;
                double tl = Math.hypot (tx, ty);
                moved[i * 2] = p.v[i].x;
                moved[i * 2 + 1] = p.v[i].y;
                if (tl < 1e-9) continue;
                double nx = -ty / tl, ny = tx / tl;
                double best = 0, best_off = 0;
                double base_g = 0;
                int steps = (int) Math.ceil (radius * reference.scale * 8);
                for (int s = 0; s <= steps; s++) {
                    double off = -radius + 2 * radius * s / double.max (1, steps);
                    double px, py;
                    reference.to_pixel (p.v[i].x + nx * off, p.v[i].y + ny * off, out px, out py);
                    double gxs = (plane.sample (px + nx, py + ny) - plane.sample (px - nx, py - ny)) * 0.5;
                    float g = (float) gxs.abs ();
                    if (off.abs () < radius / double.max (1, steps) + 1e-9) base_g = double.max (base_g, g);
                    double weighted = g * (1 - 0.05 * off.abs () / radius);
                    if (interior >= 0) {
                        double s1 = plane.sample (px - nx * 2 * reference.scale, py - ny * 2 * reference.scale);
                        double s2 = plane.sample (px + nx * 2 * reference.scale, py + ny * 2 * reference.scale);
                        double match = (1 - double.min ((s1 - interior).abs (), (s2 - interior).abs ()) * 5).clamp (0, 1);
                        weighted *= match;
                    }
                    if (weighted > best) {
                        best = weighted;
                        best_off = off;
                    }
                }
                if (best > 0.04 && best > base_g * 1.1) {
                    moved[i * 2] = p.v[i].x + nx * best_off * strength;
                    moved[i * 2 + 1] = p.v[i].y + ny * best_off * strength;
                }
            }
            for (int i = 0; i < n; i++) {
                p.v[i].x = moved[i * 2];
                p.v[i].y = moved[i * 2 + 1];
            }
        }

        public BezPath refine (BezPath p, Plane plane, LayerBuffer reference, double radius) {
            var r = p.copy ();
            snap (r, plane, reference, radius, 1.0);
            int n = r.count;
            var dx = new double[n];
            var dy = new double[n];
            for (int i = 0; i < n; i++) {
                dx[i] = r.v[i].x - p.v[i].x;
                dy[i] = r.v[i].y - p.v[i].y;
            }
            for (int i = 0; i < n; i++) {
                int a = (i - 1 + n) % n, b = (i + 1) % n;
                r.v[i].x = p.v[i].x + (dx[a] + 2 * dx[i] + dx[b]) / 4;
                r.v[i].y = p.v[i].y + (dy[a] + 2 * dy[i] + dy[b]) / 4;
            }
            return r;
        }

        public int propagate (Renderer renderer, Layer layer, PropGroup mask, double from_t, double to_t, double snap_radius = 4, double snap_strength = 0.5, TrackProgress? progress = null) {
            var pp = mask.prop ("path");
            if (pp == null) return 0;
            var src = new TrackSource (renderer, layer);
            int f0 = src.frame_of (from_t), f1 = src.frame_of (to_t);
            if (f0 == f1) return 0;
            int dir = f1 > f0 ? 1 : -1;
            var path = pp.path_at (layer.layer_time (from_t));
            if (pp.keys.size == 0) pp.set_path_key (layer.layer_time (from_t), path);
            var prev = src.pyramid (f0);
            var settings = new RenderSettings ();
            settings.motion_blur = false;
            var reference = renderer.layer_buffer_until (layer, from_t, settings, 0, 0, 1.0, true);
            if (prev == null || reference == null) return 0;
            int written = 0;
            double vx = 0, vy = 0;
            int total = (f1 - f0).abs ();
            for (int f = f0 + dir; dir > 0 ? f <= f1 : f >= f1; f += dir) {
                var next = src.pyramid (f);
                if (next == null) break;
                path = step (prev, next, path, reference, snap_radius, snap_strength, ref vx, ref vy);
                pp.set_path_key (layer.layer_time (src.time_of (f)), path);
                written++;
                prev = next;
                if (progress != null && !progress ((double) written / total)) break;
            }
            layer.mark_changed ();
            return written;
        }
    }
}
