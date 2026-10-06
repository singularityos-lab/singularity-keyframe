namespace Singularity.Apps.Keyframe {

    public class TokenCurve {
        public string name;
        public double x1;
        public double y1;
        public double x2;
        public double y2;
        public uint duration_ms;
        public string curve_token = "";
        public string duration_token = "";

        public TokenCurve (string name, double x1, double y1, double x2, double y2, uint duration_ms = 0) {
            this.name = name;
            this.x1 = x1;
            this.y1 = y1;
            this.x2 = x2;
            this.y2 = y2;
            this.duration_ms = duration_ms;
        }

        public bool is_linear () {
            return (x1 - y1).abs () < 1e-6 && (x2 - y2).abs () < 1e-6;
        }

        public string css () {
            if (is_linear ()) return "linear";
            return "cubic-bezier(%s, %s, %s, %s)".printf (MotionTokens.fmt (x1), MotionTokens.fmt (y1), MotionTokens.fmt (x2), MotionTokens.fmt (y2));
        }
    }

    namespace MotionTokens {
        public string fmt (double d) {
            var s = "%.3f".printf (d);
            while (s.contains (".") && (s.has_suffix ("0") || s.has_suffix ("."))) s = s.substring (0, s.length - 1);
            return s == "-0" ? "0" : s;
        }

        public string match_curve (double x1, double y1, double x2, double y2, double tolerance = 0.02) {
            foreach (var c in Singularity.Motion.Curve.all ()) {
                double a, b, cc, d;
                c.get_points (out a, out b, out cc, out d);
                if ((a - x1).abs () <= tolerance && (b - y1).abs () <= tolerance && (cc - x2).abs () <= tolerance && (d - y2).abs () <= tolerance) return c.css_name ();
            }
            return "";
        }

        public string match_duration (uint ms) {
            foreach (var d in Singularity.Motion.Duration.all ()) {
                uint v = d.ms ();
                if (v == 0) {
                    if (ms == 0) return d.css_name ();
                    continue;
                }
                if ((double) (ms > v ? ms - v : v - ms) <= v * 0.1) return d.css_name ();
            }
            return "";
        }

        public Gee.ArrayList<TokenCurve> export_property (Property p, string base_name) {
            var r = new Gee.ArrayList<TokenCurve> ();
            if (p.keys.size < 2) return r;
            var times = p.effective_times ();
            for (int s = 0; s < p.keys.size - 1; s++) {
                double x1, y1, x2, y2;
                if (p.keys[s].out_interp == Interp.HOLD) continue;
                p.segment_ease (s, times, out x1, out y1, out x2, out y2);
                uint ms = (uint) Math.round ((times[s + 1] - times[s]) * 1000);
                var tc = new TokenCurve (p.keys.size > 2 ? "%s-%d".printf (base_name, s + 1) : base_name, x1, y1, x2, y2, ms);
                tc.curve_token = match_curve (x1, y1, x2, y2);
                tc.duration_token = match_duration (ms);
                r.add (tc);
            }
            return r;
        }

        public string to_json (Gee.List<TokenCurve> list) {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("format").add_string_value ("singularity-motion-tokens");
            b.set_member_name ("version").add_int_value (1);
            b.set_member_name ("tokens");
            b.begin_array ();
            foreach (var t in list) {
                b.begin_object ();
                b.set_member_name ("name").add_string_value (t.name);
                b.set_member_name ("bezier");
                JsonUtil.add_array (b, { t.x1, t.y1, t.x2, t.y2 });
                b.set_member_name ("durationMs").add_int_value (t.duration_ms);
                if (t.curve_token != "") b.set_member_name ("curve").add_string_value (t.curve_token);
                if (t.duration_token != "") b.set_member_name ("duration").add_string_value (t.duration_token);
                b.set_member_name ("css").add_string_value (t.css ());
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
            return JsonUtil.to_string (b.get_root ());
        }

        public string to_css (Gee.List<TokenCurve> list) {
            var sb = new StringBuilder (":root {\n");
            foreach (var t in list) {
                string easing = t.curve_token != "" ? "var(--motion-curve-%s, %s)".printf (t.curve_token, t.css ()) : t.css ();
                string dur = t.duration_token != "" ? "var(--motion-duration-%s, %ums)".printf (t.duration_token, t.duration_ms) : "%ums".printf (t.duration_ms);
                sb.append_printf ("  --keyframe-%s-easing: %s;\n", t.name, easing);
                sb.append_printf ("  --keyframe-%s-duration: %s;\n", t.name, dur);
            }
            sb.append ("}\n");
            return sb.str;
        }

        private string enum_name (string css_name) {
            return css_name.up ().replace ("-", "_");
        }

        public string to_vala (Gee.List<TokenCurve> list) {
            var sb = new StringBuilder ();
            foreach (var t in list) {
                string var_name = t.name.replace ("-", "_");
                string dur = t.duration_token != "" ? "Singularity.Motion.Duration.%s.ms ()".printf (enum_name (t.duration_token)) : "%u".printf (t.duration_ms);
                if (t.curve_token != "") {
                    sb.append_printf ("var %s = new Singularity.Animation.TimedAnimation.with_curve (widget, from, to, %s, Singularity.Motion.Curve.%s);\n", var_name, dur, enum_name (t.curve_token));
                } else {
                    sb.append_printf ("var %s = new Singularity.Animation.TimedAnimation (widget, from, to, %s);\n", var_name, dur);
                    sb.append_printf ("%s.set_bezier (%s, %s, %s, %s);\n", var_name, fmt (t.x1), fmt (t.y1), fmt (t.x2), fmt (t.y2));
                }
            }
            return sb.str;
        }

        public Gee.ArrayList<TokenCurve> presets () {
            var r = new Gee.ArrayList<TokenCurve> ();
            foreach (var c in Singularity.Motion.Curve.all ()) {
                double a, b, cc, d;
                c.get_points (out a, out b, out cc, out d);
                var t = new TokenCurve (c.css_name (), a, b, cc, d, Singularity.Motion.Duration.MEDIUM.ms ());
                t.curve_token = c.css_name ();
                t.duration_token = "medium";
                r.add (t);
            }
            return r;
        }

        public void apply_preset (Keyframe from, Keyframe to, TokenCurve c) {
            if (c.is_linear ()) {
                from.out_interp = Interp.LINEAR;
                to.in_interp = Interp.LINEAR;
                return;
            }
            from.out_interp = Interp.BEZIER;
            from.ease_out_x = c.x1;
            from.ease_out_y = c.y1;
            from.auto_bezier = false;
            to.in_interp = Interp.BEZIER;
            to.ease_in_x = c.x2;
            to.ease_in_y = c.y2;
            to.auto_bezier = false;
        }

        public Gee.ArrayList<TokenCurve> parse_json (string text) throws Error {
            var r = new Gee.ArrayList<TokenCurve> ();
            var root = JsonUtil.parse (text).get_object ();
            if (JsonUtil.str (root, "format") != "singularity-motion-tokens") throw new ProjectError.FORMAT (_("Not a motion tokens file"));
            foreach (var e in root.get_array_member ("tokens").get_elements ()) {
                var o = e.get_object ();
                var bz = JsonUtil.array (o, "bezier", { 0, 0, 1, 1 });
                if (bz.length < 4) continue;
                var t = new TokenCurve (JsonUtil.str (o, "name", "token"), bz[0], bz[1], bz[2], bz[3], (uint) JsonUtil.num (o, "durationMs", 0));
                t.curve_token = JsonUtil.str (o, "curve");
                t.duration_token = JsonUtil.str (o, "duration");
                r.add (t);
            }
            return r;
        }
    }
}
