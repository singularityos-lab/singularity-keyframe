using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    namespace Blur {
        private int[] box_sizes (double sigma, int n) {
            double ideal = Math.sqrt ((12 * sigma * sigma / n) + 1);
            int wl = (int) Math.floor (ideal);
            if (wl % 2 == 0) wl--;
            int wu = wl + 2;
            double m_ideal = (12 * sigma * sigma - n * wl * wl - 4 * n * wl - 3 * n) / (-4 * wl - 4);
            int m = (int) Math.round (m_ideal);
            var sizes = new int[n];
            for (int i = 0; i < n; i++) sizes[i] = i < m ? wl : wu;
            return sizes;
        }

        private void box_h (float[] src, float[] dst, int w, int h, int r, int stride, int channels) {
            if (r <= 0) {
                Memory.copy (dst, src, src.length * sizeof (float));
                return;
            }
            float inv = 1.0f / (r + r + 1);
            Parallel.range (h, (s, e) => {
                for (int y = s; y < e; y++) {
                    for (int c = 0; c < channels; c++) {
                        size_t row = (size_t) y * w * stride + c;
                        float acc = 0;
                        for (int x = 0; x <= r && x < w; x++) acc += src[row + (size_t) x * stride];
                        for (int x = 0; x < w; x++) {
                            dst[row + (size_t) x * stride] = acc * inv;
                            int add = x + r + 1, sub = x - r;
                            if (add < w) acc += src[row + (size_t) add * stride];
                            if (sub >= 0) acc -= src[row + (size_t) sub * stride];
                        }
                    }
                }
            });
        }

        private void box_v (float[] src, float[] dst, int w, int h, int r, int stride, int channels) {
            if (r <= 0) {
                Memory.copy (dst, src, src.length * sizeof (float));
                return;
            }
            float inv = 1.0f / (r + r + 1);
            Parallel.range (w, (s, e) => {
                for (int x = s; x < e; x++) {
                    for (int c = 0; c < channels; c++) {
                        size_t col = (size_t) x * stride + c;
                        size_t row_stride = (size_t) w * stride;
                        float acc = 0;
                        for (int y = 0; y <= r && y < h; y++) acc += src[col + (size_t) y * row_stride];
                        for (int y = 0; y < h; y++) {
                            dst[col + (size_t) y * row_stride] = acc * inv;
                            int add = y + r + 1, sub = y - r;
                            if (add < h) acc += src[col + (size_t) add * row_stride];
                            if (sub >= 0) acc -= src[col + (size_t) sub * row_stride];
                        }
                    }
                }
            });
        }

        public void gaussian_buffer (float[] data, int w, int h, int stride, double sx, double sy) {
            var tmp = new float[data.length];
            if (sx > 0.3) {
                foreach (var bs in box_sizes (sx, 3)) {
                    box_h (data, tmp, w, h, (bs - 1) / 2, stride, stride);
                    Memory.copy (data, tmp, data.length * sizeof (float));
                }
            }
            if (sy > 0.3) {
                foreach (var bs in box_sizes (sy, 3)) {
                    box_v (data, tmp, w, h, (bs - 1) / 2, stride, stride);
                    Memory.copy (data, tmp, data.length * sizeof (float));
                }
            }
        }

        public void gaussian (FloatImage img, double sx, double sy) {
            gaussian_buffer (img.data, img.width, img.height, 4, sx, sy);
        }

        public void gaussian_plane (float[] plane, int w, int h, double sx, double sy) {
            gaussian_buffer (plane, w, h, 1, sx, sy);
        }

        public void directional (FloatImage img, double angle_deg, double length) {
            if (length < 0.5) return;
            var src = img.copy ();
            double a = angle_deg * Math.PI / 180.0;
            double dx = Math.sin (a), dy = -Math.cos (a);
            int steps = int.max (2, (int) Math.ceil (length));
            Parallel.range (img.height, (s, e) => {
                for (int y = s; y < e; y++)
                    for (int x = 0; x < img.width; x++) {
                        float r = 0, g = 0, b = 0, al = 0;
                        for (int k = 0; k < steps; k++) {
                            double f = ((double) k / (steps - 1) - 0.5) * length;
                            float pr, pg, pb, pa;
                            Pixels.sample_premul (src, x + 0.5 + dx * f, y + 0.5 + dy * f, out pr, out pg, out pb, out pa);
                            r += pr;
                            g += pg;
                            b += pb;
                            al += pa;
                        }
                        size_t o = img.offset (x, y);
                        img.data[o] = r / steps;
                        img.data[o + 1] = g / steps;
                        img.data[o + 2] = b / steps;
                        img.data[o + 3] = al / steps;
                    }
            });
        }

        public void radial (FloatImage img, double cx, double cy, double amount, bool zoom) {
            if (amount <= 0) return;
            var src = img.copy ();
            int steps = int.max (4, (int) (amount * 0.6));
            Parallel.range (img.height, (s, e) => {
                for (int y = s; y < e; y++)
                    for (int x = 0; x < img.width; x++) {
                        float r = 0, g = 0, b = 0, al = 0;
                        double px = x + 0.5 - cx, py = y + 0.5 - cy;
                        for (int k = 0; k < steps; k++) {
                            double f = ((double) k / (steps - 1) - 0.5);
                            double sx, sy;
                            if (zoom) {
                                double sc = 1 + f * amount / 100.0;
                                sx = cx + px * sc;
                                sy = cy + py * sc;
                            } else {
                                double ang = f * amount * Math.PI / 180.0;
                                sx = cx + px * Math.cos (ang) - py * Math.sin (ang);
                                sy = cy + px * Math.sin (ang) + py * Math.cos (ang);
                            }
                            float pr, pg, pb, pa;
                            Pixels.sample_premul (src, sx, sy, out pr, out pg, out pb, out pa);
                            r += pr;
                            g += pg;
                            b += pb;
                            al += pa;
                        }
                        size_t o = img.offset (x, y);
                        img.data[o] = r / steps;
                        img.data[o + 1] = g / steps;
                        img.data[o + 2] = b / steps;
                        img.data[o + 3] = al / steps;
                    }
            });
        }
    }

    namespace DistanceField {
        public float[] signed_distance (float[] mask, int w, int h) {
            var inside = edt (mask, w, h, true);
            var outside = edt (mask, w, h, false);
            var r = new float[(size_t) w * h];
            for (size_t i = 0; i < r.length; i++) r[i] = mask[i] >= 0.5f ? Math.sqrtf (inside[i]) - 0.5f : -(Math.sqrtf (outside[i]) - 0.5f);
            return r;
        }

        private float[] edt (float[] mask, int w, int h, bool inside) {
            float inf = 1e20f;
            var f = new float[(size_t) w * h];
            for (size_t i = 0; i < f.length; i++) {
                bool in_set = mask[i] >= 0.5f;
                f[i] = (in_set == inside) ? inf : 0;
            }
            var tmp = new float[int.max (w, h)];
            var d = new float[int.max (w, h)];
            var v = new int[int.max (w, h)];
            var z = new float[int.max (w, h) + 1];
            for (int x = 0; x < w; x++) {
                for (int y = 0; y < h; y++) tmp[y] = f[(size_t) y * w + x];
                edt1 (tmp, h, d, v, z);
                for (int y = 0; y < h; y++) f[(size_t) y * w + x] = d[y];
            }
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) tmp[x] = f[(size_t) y * w + x];
                edt1 (tmp, w, d, v, z);
                for (int x = 0; x < w; x++) f[(size_t) y * w + x] = d[x];
            }
            return f;
        }

        private void edt1 (float[] f, int n, float[] d, int[] v, float[] z) {
            int k = 0;
            v[0] = 0;
            z[0] = -1e20f;
            z[1] = 1e20f;
            for (int q = 1; q < n; q++) {
                float s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
                while (s <= z[k]) {
                    k--;
                    s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
                }
                k++;
                v[k] = q;
                z[k] = s;
                z[k + 1] = 1e20f;
            }
            k = 0;
            for (int q = 0; q < n; q++) {
                while (z[k + 1] < q) k++;
                d[q] = (q - v[k]) * (q - v[k]) + f[v[k]];
            }
        }
    }
}
