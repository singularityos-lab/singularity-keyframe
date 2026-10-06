using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    public class Lut3D {
        public int size;
        public float[] data;
        public double[] domain_min = { 0, 0, 0 };
        public double[] domain_max = { 1, 1, 1 };

        public static Lut3D parse_cube (string text) throws Error {
            var lut = new Lut3D ();
            var values = new Gee.ArrayList<float?> ();
            foreach (var raw in text.split ("\n")) {
                var line = raw.strip ();
                if (line == "" || line.has_prefix ("#") || line.has_prefix ("TITLE")) continue;
                if (line.has_prefix ("LUT_3D_SIZE")) {
                    lut.size = int.parse (line.substring (11).strip ());
                    continue;
                }
                if (line.has_prefix ("DOMAIN_MIN")) {
                    var p = line.substring (10).strip ().split (" ");
                    if (p.length >= 3) lut.domain_min = { double.parse (p[0]), double.parse (p[1]), double.parse (p[2]) };
                    continue;
                }
                if (line.has_prefix ("DOMAIN_MAX")) {
                    var p = line.substring (10).strip ().split (" ");
                    if (p.length >= 3) lut.domain_max = { double.parse (p[0]), double.parse (p[1]), double.parse (p[2]) };
                    continue;
                }
                if (line.has_prefix ("LUT_1D_SIZE")) throw new ImageError.UNSUPPORTED ("1D cube LUTs are not supported");
                var parts = line.split_set (" \t");
                int added = 0;
                foreach (var p in parts) {
                    if (p == "") continue;
                    values.add ((float) double.parse (p));
                    added++;
                }
            }
            if (lut.size < 2 || values.size < lut.size * lut.size * lut.size * 3) throw new ImageError.FORMAT ("Bad cube LUT");
            lut.data = new float[values.size];
            for (int i = 0; i < values.size; i++) lut.data[i] = values[i];
            return lut;
        }

        public void apply (ref float r, ref float g, ref float b) {
            double[] c = { r, g, b };
            double[] f = new double[3];
            int[] i0 = new int[3];
            for (int k = 0; k < 3; k++) {
                double u = ((c[k] - domain_min[k]) / (domain_max[k] - domain_min[k])).clamp (0, 1) * (size - 1);
                i0[k] = int.min ((int) u, size - 2);
                f[k] = u - i0[k];
            }
            float[] res = { 0, 0, 0 };
            for (int dz = 0; dz < 2; dz++)
                for (int dy = 0; dy < 2; dy++)
                    for (int dx = 0; dx < 2; dx++) {
                        double w = (dx == 1 ? f[0] : 1 - f[0]) * (dy == 1 ? f[1] : 1 - f[1]) * (dz == 1 ? f[2] : 1 - f[2]);
                        int idx = ((i0[2] + dz) * size * size + (i0[1] + dy) * size + (i0[0] + dx)) * 3;
                        for (int k = 0; k < 3; k++) res[k] += (float) (data[idx + k] * w);
                    }
            r = res[0];
            g = res[1];
            b = res[2];
        }
    }

    public class OcioStep {
        public string kind;
        public double[] matrix = {};
        public double[] exponent = {};
        public Lut3D? lut;
        public bool inverse = false;
    }

    public class OcioSpace {
        public string name;
        public string family = "";
        public Gee.ArrayList<OcioStep> to_reference = new Gee.ArrayList<OcioStep> ();
        public Gee.ArrayList<OcioStep> from_reference = new Gee.ArrayList<OcioStep> ();
    }

    public class OcioConfig {
        public Gee.ArrayList<OcioSpace> spaces = new Gee.ArrayList<OcioSpace> ();
        public string path = "";

        public OcioSpace? space (string name) {
            foreach (var s in spaces) if (s.name == name) return s;
            return null;
        }

        public static OcioConfig load (string path) throws Error {
            string text;
            FileUtils.get_contents (path, out text);
            var cfg = new OcioConfig ();
            cfg.path = path;
            string dir = Path.get_dirname (path);
            string search = "";
            OcioSpace? cur = null;
            Gee.ArrayList<OcioStep>? target = null;
            foreach (var raw in text.split ("\n")) {
                var line = raw.strip ();
                if (line.has_prefix ("search_path:")) search = unquote (line.substring (12).strip ());
                if (line.has_prefix ("- !<ColorSpace>")) {
                    cur = new OcioSpace ();
                    cfg.spaces.add (cur);
                    target = null;
                    continue;
                }
                if (cur == null) continue;
                if (line.has_prefix ("name:")) {
                    cur.name = unquote (line.substring (5).strip ());
                } else if (line.has_prefix ("family:")) {
                    cur.family = unquote (line.substring (7).strip ());
                } else if (line.has_prefix ("to_reference:") || line.has_prefix ("to_scene_reference:")) {
                    target = cur.to_reference;
                    parse_transforms (line.substring (line.index_of (":") + 1), target, dir, search);
                } else if (line.has_prefix ("from_reference:") || line.has_prefix ("from_scene_reference:")) {
                    target = cur.from_reference;
                    parse_transforms (line.substring (line.index_of (":") + 1), target, dir, search);
                } else if (target != null && line.has_prefix ("- !<")) {
                    parse_transforms (line.substring (2), target, dir, search);
                } else if (target != null && line.has_prefix ("!<")) {
                    parse_transforms (line, target, dir, search);
                }
            }
            return cfg;
        }

        private static string unquote (string s) {
            var t = s.strip ();
            if (t.length >= 2 && (t[0] == '"' || t[0] == '\'')) return t.substring (1, t.length - 2);
            return t;
        }

        private static void parse_transforms (string text, Gee.ArrayList<OcioStep> into, string dir, string search) {
            int pos = 0;
            while (true) {
                int start = text.index_of ("!<", pos);
                if (start < 0) break;
                int end = text.index_of (">", start);
                if (end < 0) break;
                string kind = text.substring (start + 2, end - start - 2);
                int brace = text.index_of ("{", end);
                int close = brace >= 0 ? text.index_of ("}", brace) : -1;
                string body = brace >= 0 && close > brace ? text.substring (brace + 1, close - brace - 1) : "";
                pos = close > 0 ? close : end + 1;
                if (kind == "GroupTransform") continue;
                var step = new OcioStep ();
                step.kind = kind;
                step.inverse = body.contains ("direction: inverse");
                var m = field (body, "matrix");
                if (m != null) step.matrix = numbers (m);
                var off = field (body, "offset");
                var e = field (body, "value");
                if (e != null) step.exponent = numbers (e);
                var src = field (body, "src");
                if (kind == "FileTransform" && src != null) {
                    string file = unquote (src);
                    string[] candidates = { Path.build_filename (dir, file), Path.build_filename (dir, search, file) };
                    foreach (var cpath in candidates) {
                        if (!FileUtils.test (cpath, FileTest.EXISTS)) continue;
                        try {
                            string lt;
                            FileUtils.get_contents (cpath, out lt);
                            step.lut = Lut3D.parse_cube (lt);
                        } catch (Error err) {
                        }
                        break;
                    }
                }
                if (off != null && step.matrix.length == 16) {
                    var o = numbers (off);
                    for (int i = 0; i < 3 && i < o.length; i++) step.matrix[i * 4 + 3] = o[i];
                }
                into.add (step);
            }
        }

        private static string? field (string body, string name) {
            int i = body.index_of (name + ":");
            if (i < 0) return null;
            var rest = body.substring (i + name.length + 1).strip ();
            if (rest.has_prefix ("[")) {
                int e = rest.index_of ("]");
                return e > 0 ? rest.substring (1, e - 1) : null;
            }
            int comma = rest.index_of (",");
            return comma >= 0 ? rest.substring (0, comma) : rest;
        }

        private static double[] numbers (string s) {
            double[] r = {};
            foreach (var p in s.split (",")) {
                var t = p.strip ();
                if (t != "") r += double.parse (t);
            }
            return r;
        }
    }

    namespace ColorManagement {
        public OcioConfig? active_config = null;

        public string[] builtin_spaces () {
            return { "linear-srgb", "srgb", "rec709", "linear-rec2020", "rec2020", "display-p3", "acescg", "aces2065-1", "acescct", "linear" };
        }

        public string label (string id) {
            switch (id) {
                case "linear-srgb": return _("Linear sRGB / Rec.709");
                case "srgb": return _("sRGB");
                case "rec709": return _("Rec.709 (BT.1886)");
                case "linear-rec2020": return _("Linear Rec.2020");
                case "rec2020": return _("Rec.2020");
                case "display-p3": return _("Display P3");
                case "acescg": return _("ACEScg");
                case "aces2065-1": return _("ACES2065-1");
                case "acescct": return _("ACEScct");
                case "aces-sdr": return _("ACES 1.0 SDR Video");
                case "linear": return _("Linear (no conversion)");
                default: return id;
            }
        }

        private Primaries ap0 () {
            return Primaries (0.7347, 0.2653, 0.0, 1.0, 0.0001, -0.077, 0.32168, 0.33767);
        }

        private Primaries ap1 () {
            return Primaries (0.713, 0.293, 0.165, 0.830, 0.128, 0.044, 0.32168, 0.33767);
        }

        private bool primaries_of (string id, out Primaries p) {
            switch (id) {
                case "linear-rec2020":
                case "rec2020":
                    p = Primaries.rec2020 ();
                    return true;
                case "display-p3":
                    p = Primaries.display_p3 ();
                    return true;
                case "acescg":
                case "acescct":
                    p = ap1 ();
                    return true;
                case "aces2065-1":
                    p = ap0 ();
                    return true;
                default:
                    p = Primaries.rec709 ();
                    return true;
            }
        }

        private double[] matrix_between (Primaries a, Primaries b) {
            var m = Primaries.conversion (a, b);
            if ((a.wx - b.wx).abs () > 1e-4 || (a.wy - b.wy).abs () > 1e-4) {
                var to_xyz = a.to_xyz ();
                var adapt = Matrix3.bradford (a.wx, a.wy, b.wx, b.wy);
                var from_xyz = Matrix3.invert (b.to_xyz ());
                m = Matrix3.multiply (from_xyz, Matrix3.multiply (adapt, to_xyz));
            }
            return m;
        }

        public float decode (string id, float v) {
            switch (id) {
                case "srgb":
                case "display-p3":
                    return Transfer.srgb_to_linear (v);
                case "rec709":
                case "rec2020":
                    return v <= 0 ? 0 : Math.powf (v, 2.4f);
                case "acescct":
                    if (v <= 0.155251141552511f) return (v - 0.0729055341958355f) / 10.5402377416545f;
                    return Math.powf (2, v * 17.52f - 9.72f);
                default:
                    return v;
            }
        }

        public float encode (string id, float v) {
            switch (id) {
                case "srgb":
                case "display-p3":
                    return Transfer.linear_to_srgb (v);
                case "rec709":
                case "rec2020":
                    return v <= 0 ? 0 : Math.powf (v, 1.0f / 2.4f);
                case "acescct":
                    if (v <= 0.0078125f) return 10.5402377416545f * v + 0.0729055341958355f;
                    return (Math.log2f (v) + 9.72f) / 17.52f;
                default:
                    return v;
            }
        }

        public float aces_tonemap (float x) {
            float a = 2.51f, b = 0.03f, c = 2.43f, d = 0.59f, e = 0.14f;
            x *= 0.6f;
            return ((x * (a * x + b)) / (x * (c * x + d) + e)).clamp (0, 1);
        }

        private void apply_ocio_steps (Gee.List<OcioStep> steps, ref float r, ref float g, ref float b, bool reverse) {
            for (int si = 0; si < steps.size; si++) {
                var s = steps[reverse ? steps.size - 1 - si : si];
                bool inv = s.inverse != reverse;
                if (s.kind == "MatrixTransform" && s.matrix.length >= 12) {
                    double[] m = s.matrix;
                    if (inv) {
                        var m3 = Matrix3.invert ({ m[0], m[1], m[2], m[4], m[5], m[6], m[8], m[9], m[10] });
                        float rr = r - (float) m[3], gg = g - (float) m[7], bb = b - (float) m[11];
                        Matrix3.apply (m3, ref rr, ref gg, ref bb);
                        r = rr;
                        g = gg;
                        b = bb;
                    } else {
                        float rr = (float) (m[0] * r + m[1] * g + m[2] * b + m[3]);
                        float gg = (float) (m[4] * r + m[5] * g + m[6] * b + m[7]);
                        float bb = (float) (m[8] * r + m[9] * g + m[10] * b + m[11]);
                        r = rr;
                        g = gg;
                        b = bb;
                    }
                } else if (s.kind == "ExponentTransform" && s.exponent.length >= 3) {
                    float er = (float) (inv ? 1.0 / s.exponent[0] : s.exponent[0]);
                    float eg = (float) (inv ? 1.0 / s.exponent[1] : s.exponent[1]);
                    float eb = (float) (inv ? 1.0 / s.exponent[2] : s.exponent[2]);
                    r = r > 0 ? Math.powf (r, er) : 0;
                    g = g > 0 ? Math.powf (g, eg) : 0;
                    b = b > 0 ? Math.powf (b, eb) : 0;
                } else if (s.kind == "FileTransform" && s.lut != null && !inv) {
                    s.lut.apply (ref r, ref g, ref b);
                }
            }
        }

        public void convert (FloatImage img, string from, string to) {
            if (from == to) return;
            OcioSpace? ofrom = active_config != null ? active_config.space (from) : null;
            OcioSpace? oto = active_config != null ? active_config.space (to) : null;
            Primaries pf, pt;
            primaries_of (from, out pf);
            primaries_of (to, out pt);
            var m = matrix_between (pf, pt);
            bool same_primaries = true;
            for (int i = 0; i < 9; i++) if ((m[i] - (i % 4 == 0 ? 1 : 0)).abs () > 1e-6) same_primaries = false;
            bool tonemap = to == "aces-sdr";
            Parallel.range (img.height, (s, e) => {
                for (size_t i = (size_t) s * img.width; i < (size_t) e * img.width; i++) {
                    float r = img.data[i * 4], g = img.data[i * 4 + 1], b = img.data[i * 4 + 2];
                    if (ofrom != null) {
                        if (ofrom.to_reference.size > 0) apply_ocio_steps (ofrom.to_reference, ref r, ref g, ref b, false);
                        else apply_ocio_steps (ofrom.from_reference, ref r, ref g, ref b, true);
                    } else {
                        r = decode (from, r);
                        g = decode (from, g);
                        b = decode (from, b);
                        if (!same_primaries && oto == null) Matrix3.apply (m, ref r, ref g, ref b);
                    }
                    if (oto != null) {
                        if (oto.from_reference.size > 0) apply_ocio_steps (oto.from_reference, ref r, ref g, ref b, false);
                        else apply_ocio_steps (oto.to_reference, ref r, ref g, ref b, true);
                    } else if (tonemap) {
                        r = Transfer.linear_to_srgb (aces_tonemap (r));
                        g = Transfer.linear_to_srgb (aces_tonemap (g));
                        b = Transfer.linear_to_srgb (aces_tonemap (b));
                    } else {
                        r = encode (to, r);
                        g = encode (to, g);
                        b = encode (to, b);
                    }
                    img.data[i * 4] = r;
                    img.data[i * 4 + 1] = g;
                    img.data[i * 4 + 2] = b;
                }
            });
        }

        public void to_working (FloatImage img, string input, string working) {
            convert (img, input, working);
        }

        public void working_to_linear_srgb (FloatImage img, string working) {
            convert (img, working, "linear-srgb");
        }
    }
}
