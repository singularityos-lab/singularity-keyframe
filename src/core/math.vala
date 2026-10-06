namespace Singularity.Apps.Keyframe {

    public struct Vec3 {
        public double x;
        public double y;
        public double z;

        public Vec3 (double x, double y, double z) {
            this.x = x;
            this.y = y;
            this.z = z;
        }

        public Vec3 add (Vec3 o) {
            return Vec3 (x + o.x, y + o.y, z + o.z);
        }

        public Vec3 sub (Vec3 o) {
            return Vec3 (x - o.x, y - o.y, z - o.z);
        }

        public Vec3 scale (double s) {
            return Vec3 (x * s, y * s, z * s);
        }

        public double dot (Vec3 o) {
            return x * o.x + y * o.y + z * o.z;
        }

        public Vec3 cross (Vec3 o) {
            return Vec3 (y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
        }

        public double length () {
            return Math.sqrt (x * x + y * y + z * z);
        }

        public Vec3 normalized () {
            double l = length ();
            return l < 1e-12 ? Vec3 (0, 0, 0) : scale (1.0 / l);
        }
    }

    public class Mat4 {
        public double m[16];

        public Mat4 () {
            set_identity ();
        }

        public Mat4.copy_of (Mat4 o) {
            for (int i = 0; i < 16; i++) m[i] = o.m[i];
        }

        public void set_identity () {
            for (int i = 0; i < 16; i++) m[i] = (i % 5 == 0) ? 1 : 0;
        }

        public double get (int row, int col) {
            return m[row * 4 + col];
        }

        public void set (int row, int col, double v) {
            m[row * 4 + col] = v;
        }

        public Mat4 multiply (Mat4 b) {
            var r = new Mat4 ();
            for (int i = 0; i < 4; i++) {
                for (int j = 0; j < 4; j++) {
                    double s = 0;
                    for (int k = 0; k < 4; k++) s += m[i * 4 + k] * b.m[k * 4 + j];
                    r.m[i * 4 + j] = s;
                }
            }
            return r;
        }

        public static Mat4 translation (double x, double y, double z) {
            var r = new Mat4 ();
            r.m[3] = x;
            r.m[7] = y;
            r.m[11] = z;
            return r;
        }

        public static Mat4 scaling (double x, double y, double z) {
            var r = new Mat4 ();
            r.m[0] = x;
            r.m[5] = y;
            r.m[10] = z;
            return r;
        }

        public static Mat4 rotation_x (double deg) {
            double a = deg * Math.PI / 180.0, c = Math.cos (a), s = Math.sin (a);
            var r = new Mat4 ();
            r.m[5] = c;
            r.m[6] = -s;
            r.m[9] = s;
            r.m[10] = c;
            return r;
        }

        public static Mat4 rotation_y (double deg) {
            double a = deg * Math.PI / 180.0, c = Math.cos (a), s = Math.sin (a);
            var r = new Mat4 ();
            r.m[0] = c;
            r.m[2] = s;
            r.m[8] = -s;
            r.m[10] = c;
            return r;
        }

        public static Mat4 rotation_z (double deg) {
            double a = deg * Math.PI / 180.0, c = Math.cos (a), s = Math.sin (a);
            var r = new Mat4 ();
            r.m[0] = c;
            r.m[1] = -s;
            r.m[4] = s;
            r.m[5] = c;
            return r;
        }

        public static Mat4 skew (double amount_deg, double axis_deg) {
            if (amount_deg.abs () < 1e-9) return new Mat4 ();
            var to = rotation_z (axis_deg);
            var back = rotation_z (-axis_deg);
            var sk = new Mat4 ();
            sk.m[1] = Math.tan (-amount_deg * Math.PI / 180.0);
            return to.multiply (sk).multiply (back);
        }

        public Vec3 transform_point (Vec3 p) {
            double x = m[0] * p.x + m[1] * p.y + m[2] * p.z + m[3];
            double y = m[4] * p.x + m[5] * p.y + m[6] * p.z + m[7];
            double z = m[8] * p.x + m[9] * p.y + m[10] * p.z + m[11];
            double w = m[12] * p.x + m[13] * p.y + m[14] * p.z + m[15];
            if (w.abs () > 1e-12 && (w - 1).abs () > 1e-12) return Vec3 (x / w, y / w, z / w);
            return Vec3 (x, y, z);
        }

        public Vec3 transform_vector (Vec3 p) {
            return Vec3 (m[0] * p.x + m[1] * p.y + m[2] * p.z,
                         m[4] * p.x + m[5] * p.y + m[6] * p.z,
                         m[8] * p.x + m[9] * p.y + m[10] * p.z);
        }

        public Mat4? inverted () {
            double inv[16];
            unowned double[] a = m;
            inv[0] = a[5] * a[10] * a[15] - a[5] * a[11] * a[14] - a[9] * a[6] * a[15] + a[9] * a[7] * a[14] + a[13] * a[6] * a[11] - a[13] * a[7] * a[10];
            inv[4] = -a[4] * a[10] * a[15] + a[4] * a[11] * a[14] + a[8] * a[6] * a[15] - a[8] * a[7] * a[14] - a[12] * a[6] * a[11] + a[12] * a[7] * a[10];
            inv[8] = a[4] * a[9] * a[15] - a[4] * a[11] * a[13] - a[8] * a[5] * a[15] + a[8] * a[7] * a[13] + a[12] * a[5] * a[11] - a[12] * a[7] * a[9];
            inv[12] = -a[4] * a[9] * a[14] + a[4] * a[10] * a[13] + a[8] * a[5] * a[14] - a[8] * a[6] * a[13] - a[12] * a[5] * a[10] + a[12] * a[6] * a[9];
            inv[1] = -a[1] * a[10] * a[15] + a[1] * a[11] * a[14] + a[9] * a[2] * a[15] - a[9] * a[3] * a[14] - a[13] * a[2] * a[11] + a[13] * a[3] * a[10];
            inv[5] = a[0] * a[10] * a[15] - a[0] * a[11] * a[14] - a[8] * a[2] * a[15] + a[8] * a[3] * a[14] + a[12] * a[2] * a[11] - a[12] * a[3] * a[10];
            inv[9] = -a[0] * a[9] * a[15] + a[0] * a[11] * a[13] + a[8] * a[1] * a[15] - a[8] * a[3] * a[13] - a[12] * a[1] * a[11] + a[12] * a[3] * a[9];
            inv[13] = a[0] * a[9] * a[14] - a[0] * a[10] * a[13] - a[8] * a[1] * a[14] + a[8] * a[2] * a[13] + a[12] * a[1] * a[10] - a[12] * a[2] * a[9];
            inv[2] = a[1] * a[6] * a[15] - a[1] * a[7] * a[14] - a[5] * a[2] * a[15] + a[5] * a[3] * a[14] + a[13] * a[2] * a[7] - a[13] * a[3] * a[6];
            inv[6] = -a[0] * a[6] * a[15] + a[0] * a[7] * a[14] + a[4] * a[2] * a[15] - a[4] * a[3] * a[14] - a[12] * a[2] * a[7] + a[12] * a[3] * a[6];
            inv[10] = a[0] * a[5] * a[15] - a[0] * a[7] * a[13] - a[4] * a[1] * a[15] + a[4] * a[3] * a[13] + a[12] * a[1] * a[7] - a[12] * a[3] * a[5];
            inv[14] = -a[0] * a[5] * a[14] + a[0] * a[6] * a[13] + a[4] * a[1] * a[14] - a[4] * a[2] * a[13] - a[12] * a[1] * a[6] + a[12] * a[2] * a[5];
            inv[3] = -a[1] * a[6] * a[11] + a[1] * a[7] * a[10] + a[5] * a[2] * a[11] - a[5] * a[3] * a[10] - a[9] * a[2] * a[7] + a[9] * a[3] * a[6];
            inv[7] = a[0] * a[6] * a[11] - a[0] * a[7] * a[10] - a[4] * a[2] * a[11] + a[4] * a[3] * a[10] + a[8] * a[2] * a[7] - a[8] * a[3] * a[6];
            inv[11] = -a[0] * a[5] * a[11] + a[0] * a[7] * a[9] + a[4] * a[1] * a[11] - a[4] * a[3] * a[9] - a[8] * a[1] * a[7] + a[8] * a[3] * a[5];
            inv[15] = a[0] * a[5] * a[10] - a[0] * a[6] * a[9] - a[4] * a[1] * a[10] + a[4] * a[2] * a[9] + a[8] * a[1] * a[6] - a[8] * a[2] * a[5];
            double det = a[0] * inv[0] + a[1] * inv[4] + a[2] * inv[8] + a[3] * inv[12];
            if (det.abs () < 1e-14) return null;
            var r = new Mat4 ();
            for (int i = 0; i < 16; i++) r.m[i] = inv[i] / det;
            return r;
        }

        public Cairo.Matrix to_cairo () {
            return Cairo.Matrix (m[0], m[4], m[1], m[5], m[3], m[7]);
        }

        public double max_scale_2d () {
            double sx = Math.sqrt (m[0] * m[0] + m[4] * m[4]);
            double sy = Math.sqrt (m[1] * m[1] + m[5] * m[5]);
            return double.max (sx, sy);
        }

        public bool is_affine_2d () {
            return m[2].abs () < 1e-12 && m[6].abs () < 1e-12 && m[8].abs () < 1e-12 && m[9].abs () < 1e-12
                && m[12].abs () < 1e-12 && m[13].abs () < 1e-12 && (m[15] - 1).abs () < 1e-12;
        }
    }

    public class Homography {
        public double h[9];

        public Homography () {
            for (int i = 0; i < 9; i++) h[i] = (i % 4 == 0) ? 1 : 0;
        }

        public void apply (double x, double y, out double ox, out double oy) {
            double w = h[6] * x + h[7] * y + h[8];
            if (w.abs () < 1e-12) w = 1e-12;
            ox = (h[0] * x + h[1] * y + h[2]) / w;
            oy = (h[3] * x + h[4] * y + h[5]) / w;
        }

        public Homography? inverted () {
            double a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7], i = h[8];
            double det = a * (e * i - f * hh) - b * (d * i - f * g) + c * (d * hh - e * g);
            if (det.abs () < 1e-14) return null;
            var r = new Homography ();
            r.h[0] = (e * i - f * hh) / det;
            r.h[1] = (c * hh - b * i) / det;
            r.h[2] = (b * f - c * e) / det;
            r.h[3] = (f * g - d * i) / det;
            r.h[4] = (a * i - c * g) / det;
            r.h[5] = (c * d - a * f) / det;
            r.h[6] = (d * hh - e * g) / det;
            r.h[7] = (b * g - a * hh) / det;
            r.h[8] = (a * e - b * d) / det;
            return r;
        }

        public Homography multiply (Homography o) {
            var r = new Homography ();
            for (int row = 0; row < 3; row++)
                for (int col = 0; col < 3; col++) {
                    double s = 0;
                    for (int k = 0; k < 3; k++) s += h[row * 3 + k] * o.h[k * 3 + col];
                    r.h[row * 3 + col] = s;
                }
            return r;
        }

        public static Homography from_mat4_plane (Mat4 mvp) {
            var r = new Homography ();
            r.h[0] = mvp.m[0];
            r.h[1] = mvp.m[1];
            r.h[2] = mvp.m[3];
            r.h[3] = mvp.m[4];
            r.h[4] = mvp.m[5];
            r.h[5] = mvp.m[7];
            r.h[6] = mvp.m[12];
            r.h[7] = mvp.m[13];
            r.h[8] = mvp.m[15];
            return r;
        }

        public static Homography? from_quads (double[] src, double[] dst) {
            double a[72];
            double rhs[8];
            for (int i = 0; i < 4; i++) {
                double x = src[i * 2], y = src[i * 2 + 1], u = dst[i * 2], v = dst[i * 2 + 1];
                int r0 = i * 2, r1 = i * 2 + 1;
                double row0[8] = { x, y, 1, 0, 0, 0, -u * x, -u * y };
                double row1[8] = { 0, 0, 0, x, y, 1, -v * x, -v * y };
                for (int k = 0; k < 8; k++) {
                    a[r0 * 9 + k] = row0[k];
                    a[r1 * 9 + k] = row1[k];
                }
                rhs[r0] = u;
                rhs[r1] = v;
            }
            double sol[8];
            if (!LinearSolve.solve (a, rhs, 8, sol)) return null;
            var r = new Homography ();
            for (int k = 0; k < 8; k++) r.h[k] = sol[k];
            r.h[8] = 1;
            return r;
        }
    }

    namespace LinearSolve {
        public bool solve (double[] a_rows9, double[] rhs, int n, double[] result) {
            var a = new double[n * (n + 1)];
            for (int r = 0; r < n; r++) {
                for (int c = 0; c < n; c++) a[r * (n + 1) + c] = a_rows9[r * 9 + c];
                a[r * (n + 1) + n] = rhs[r];
            }
            return gauss (a, n, result);
        }

        public bool gauss (double[] aug, int n, double[] result) {
            int w = n + 1;
            for (int col = 0; col < n; col++) {
                int pivot = col;
                for (int r = col + 1; r < n; r++)
                    if (aug[r * w + col].abs () > aug[pivot * w + col].abs ()) pivot = r;
                if (aug[pivot * w + col].abs () < 1e-14) return false;
                if (pivot != col) {
                    for (int c = 0; c < w; c++) {
                        double t = aug[col * w + c];
                        aug[col * w + c] = aug[pivot * w + c];
                        aug[pivot * w + c] = t;
                    }
                }
                for (int r = 0; r < n; r++) {
                    if (r == col) continue;
                    double f = aug[r * w + col] / aug[col * w + col];
                    if (f == 0) continue;
                    for (int c = col; c < w; c++) aug[r * w + c] -= f * aug[col * w + c];
                }
            }
            for (int r = 0; r < n; r++) result[r] = aug[r * w + n] / aug[r * w + r];
            return true;
        }
    }

    namespace Noise {
        private int hash_int (int x) {
            uint h = (uint) x;
            h ^= h >> 16;
            h *= 0x7feb352du;
            h ^= h >> 15;
            h *= 0x846ca68bu;
            h ^= h >> 16;
            return (int) (h & 0x7fffffff);
        }

        public double hash01 (int a, int b = 0, int c = 0) {
            int h = hash_int (a * 73856093 ^ hash_int (b * 19349663 ^ hash_int (c * 83492791)));
            return (h % 1000003) / 1000003.0;
        }

        private double grad1 (int i, int seed) {
            return hash01 (i, seed, 17) * 2 - 1;
        }

        public double perlin1 (double x, int seed = 0) {
            int i0 = (int) Math.floor (x);
            double f = x - i0;
            double g0 = grad1 (i0, seed) * f;
            double g1 = grad1 (i0 + 1, seed) * (f - 1);
            double u = f * f * f * (f * (f * 6 - 15) + 10);
            return (g0 + (g1 - g0) * u) * 2;
        }

        private double grad2 (int ix, int iy, int seed, double dx, double dy) {
            double a = hash01 (ix, iy, seed) * Math.PI * 2;
            return Math.cos (a) * dx + Math.sin (a) * dy;
        }

        public double perlin2 (double x, double y, int seed = 0) {
            int x0 = (int) Math.floor (x), y0 = (int) Math.floor (y);
            double fx = x - x0, fy = y - y0;
            double u = fx * fx * fx * (fx * (fx * 6 - 15) + 10);
            double v = fy * fy * fy * (fy * (fy * 6 - 15) + 10);
            double n00 = grad2 (x0, y0, seed, fx, fy);
            double n10 = grad2 (x0 + 1, y0, seed, fx - 1, fy);
            double n01 = grad2 (x0, y0 + 1, seed, fx, fy - 1);
            double n11 = grad2 (x0 + 1, y0 + 1, seed, fx - 1, fy - 1);
            double nx0 = n00 + (n10 - n00) * u;
            double nx1 = n01 + (n11 - n01) * u;
            return (nx0 + (nx1 - nx0) * v) * 1.414;
        }

        public double perlin3 (double x, double y, double z, int seed = 0) {
            int zi = (int) Math.floor (z);
            double fz = z - zi;
            double w = fz * fz * fz * (fz * (fz * 6 - 15) + 10);
            double a = perlin2 (x + zi * 31.7, y - zi * 17.3, seed);
            double b = perlin2 (x + (zi + 1) * 31.7, y - (zi + 1) * 17.3, seed);
            return a + (b - a) * w;
        }

        public double fractal1 (double x, int octaves, double amp_mult, int seed) {
            double sum = 0, amp = 1, freq = 1, norm = 0;
            for (int o = 0; o < int.max (1, octaves); o++) {
                sum += perlin1 (x * freq, seed + o * 101) * amp;
                norm += amp;
                amp *= amp_mult;
                freq *= 2;
            }
            return norm > 0 ? sum / norm * 1.0 : 0;
        }
    }
}
