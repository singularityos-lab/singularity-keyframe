namespace Singularity.Apps.Keyframe {

    public enum Interp {
        LINEAR,
        BEZIER,
        HOLD;

        public string to_id () {
            switch (this) {
                case BEZIER: return "bezier";
                case HOLD: return "hold";
                default: return "linear";
            }
        }

        public static Interp from_id (string? s) {
            switch (s) {
                case "bezier": return BEZIER;
                case "hold": return HOLD;
                default: return LINEAR;
            }
        }
    }

    public enum PropKind {
        SCALAR,
        ANGLE,
        PERCENT,
        VECTOR,
        POINT,
        COLOR,
        PATH,
        TEXT,
        CHOICE,
        TOGGLE,
        LAYER;

        public string to_id () {
            switch (this) {
                case ANGLE: return "angle";
                case PERCENT: return "percent";
                case VECTOR: return "vector";
                case POINT: return "point";
                case COLOR: return "color";
                case PATH: return "path";
                case TEXT: return "text";
                case CHOICE: return "choice";
                case TOGGLE: return "toggle";
                case LAYER: return "layer";
                default: return "scalar";
            }
        }

        public static PropKind from_id (string? s) {
            switch (s) {
                case "angle": return ANGLE;
                case "percent": return PERCENT;
                case "vector": return VECTOR;
                case "point": return POINT;
                case "color": return COLOR;
                case "path": return PATH;
                case "text": return TEXT;
                case "choice": return CHOICE;
                case "toggle": return TOGGLE;
                case "layer": return LAYER;
                default: return SCALAR;
            }
        }

        public bool holds_only () {
            return this == TEXT || this == CHOICE || this == TOGGLE || this == LAYER;
        }
    }

    public class Keyframe {
        public double time;
        public double[] value = {};
        public BezPath? path;
        public TextDocument? text;
        public Interp in_interp = Interp.LINEAR;
        public Interp out_interp = Interp.LINEAR;
        public double ease_in_x = 2.0 / 3.0;
        public double ease_in_y = 1;
        public double ease_out_x = 1.0 / 3.0;
        public double ease_out_y = 0;
        public bool auto_bezier = false;
        public bool continuous = false;
        public bool roving = false;
        public double[] tangent_in = {};
        public double[] tangent_out = {};
        public bool spatial_auto = true;
        public bool selected = false;

        public Keyframe (double time) {
            this.time = time;
        }

        public Keyframe copy () {
            var k = new Keyframe (time);
            k.value = value;
            k.path = path != null ? path.copy () : null;
            k.text = text != null ? text.copy () : null;
            k.in_interp = in_interp;
            k.out_interp = out_interp;
            k.ease_in_x = ease_in_x;
            k.ease_in_y = ease_in_y;
            k.ease_out_x = ease_out_x;
            k.ease_out_y = ease_out_y;
            k.auto_bezier = auto_bezier;
            k.continuous = continuous;
            k.roving = roving;
            k.tangent_in = tangent_in;
            k.tangent_out = tangent_out;
            k.spatial_auto = spatial_auto;
            return k;
        }

        public void set_easy_ease () {
            in_interp = Interp.BEZIER;
            out_interp = Interp.BEZIER;
            ease_in_x = 1 - 0.3333;
            ease_in_y = 1;
            ease_out_x = 0.3333;
            ease_out_y = 0;
            auto_bezier = false;
        }
    }

    public delegate double[]? ExpressionHook (Property prop, double time, double[] pre);
    public delegate BezPath? PathExpressionHook (Property prop, double time, BezPath pre);
    public delegate string? TextExpressionHook (Property prop, double time);

    public abstract class PropNode : Object {
        public string key = "";
        public string name = "";
        public unowned PropGroup? parent = null;

        public Layer? owner_layer () {
            PropNode? n = this;
            while (n != null) {
                var g = n as PropGroup;
                if (g != null && g.layer != null) return g.layer;
                n = n.parent;
            }
            return null;
        }

        public void touch () {
            var l = owner_layer ();
            if (l != null) l.mark_changed ();
        }

        public string path_string () {
            var parts = new Gee.ArrayList<string> ();
            PropNode? n = this;
            while (n != null && n.parent != null) {
                parts.insert (0, n.key);
                n = n.parent;
            }
            return string.joinv ("/", parts.to_array ());
        }

        public abstract PropNode clone ();
    }

    public class Property : PropNode {
        public static ExpressionHook? expression_hook = null;
        public static PathExpressionHook? path_expression_hook = null;
        public static TextExpressionHook? text_expression_hook = null;

        public PropKind kind = PropKind.SCALAR;
        public int dims = 1;
        public double[] value = {0};
        public BezPath? path;
        public TextDocument? text;
        public Gee.ArrayList<Keyframe> keys = new Gee.ArrayList<Keyframe> ();
        public string expression = "";
        public bool expression_enabled = true;
        public string expression_error = "";
        public double min = -double.MAX;
        public double max = double.MAX;
        public double ui_min = -1000;
        public double ui_max = 1000;
        public string[] choices = {};
        public bool animatable = true;
        public bool spatial = false;
        public string unit = "";
        public bool in_expression = false;

        public Property (string key, string name, PropKind kind, double[] value) {
            this.key = key;
            this.name = name;
            this.kind = kind;
            this.value = value;
            this.dims = value.length;
            this.spatial = kind == PropKind.POINT;
            if (kind == PropKind.PERCENT) unit = "%";
            if (kind == PropKind.ANGLE) unit = "°";
        }

        public Property.with_path (string key, string name, BezPath path) {
            this.key = key;
            this.name = name;
            this.kind = PropKind.PATH;
            this.path = path;
            this.dims = 0;
            this.value = {};
        }

        public Property.with_text (string key, string name, TextDocument text) {
            this.key = key;
            this.name = name;
            this.kind = PropKind.TEXT;
            this.text = text;
            this.dims = 0;
            this.value = {};
        }

        public Property range (double mn, double mx) {
            min = mn;
            max = mx;
            ui_min = mn;
            ui_max = mx;
            return this;
        }

        public Property ui_range (double mn, double mx) {
            ui_min = mn;
            ui_max = mx;
            return this;
        }

        public Property with_choices (string[] c) {
            choices = c;
            min = 0;
            max = c.length - 1;
            return this;
        }

        public Property static_only () {
            animatable = false;
            return this;
        }

        public override PropNode clone () {
            var p = new Property (key, name, kind, value);
            p.dims = dims;
            p.path = path != null ? path.copy () : null;
            p.text = text != null ? text.copy () : null;
            foreach (var k in keys) p.keys.add (k.copy ());
            p.expression = expression;
            p.expression_enabled = expression_enabled;
            p.min = min;
            p.max = max;
            p.ui_min = ui_min;
            p.ui_max = ui_max;
            p.choices = choices;
            p.animatable = animatable;
            p.spatial = spatial;
            p.unit = unit;
            return p;
        }

        public bool is_animated () {
            return keys.size > 0;
        }

        public bool has_expression () {
            return expression.strip () != "" && expression_enabled;
        }

        public bool varies () {
            return keys.size > 1 || has_expression ();
        }

        public void sort_keys () {
            keys.sort ((a, b) => a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
        }

        public Keyframe? key_at (double t, double tolerance = 1e-6) {
            foreach (var k in keys) if ((k.time - t).abs () <= tolerance) return k;
            return null;
        }

        public int index_of_key (Keyframe k) {
            return keys.index_of (k);
        }

        public Keyframe set_key (double t, double[] v) {
            var k = key_at (t);
            if (k == null) {
                k = new Keyframe (t);
                if (spatial) k.spatial_auto = true;
                if (kind.holds_only ()) {
                    k.in_interp = Interp.HOLD;
                    k.out_interp = Interp.HOLD;
                }
                keys.add (k);
                sort_keys ();
            }
            k.value = clamp_value (v);
            touch ();
            return k;
        }

        public Keyframe set_path_key (double t, BezPath p) {
            var k = key_at (t);
            if (k == null) {
                k = new Keyframe (t);
                keys.add (k);
                sort_keys ();
            }
            k.path = p.copy ();
            touch ();
            return k;
        }

        public Keyframe set_text_key (double t, TextDocument d) {
            var k = key_at (t);
            if (k == null) {
                k = new Keyframe (t);
                k.in_interp = Interp.HOLD;
                k.out_interp = Interp.HOLD;
                keys.add (k);
                sort_keys ();
            }
            k.text = d.copy ();
            touch ();
            return k;
        }

        public void remove_key (Keyframe k) {
            keys.remove (k);
            touch ();
        }

        public void clear_keys () {
            if (keys.size > 0) {
                if (kind == PropKind.PATH) path = keys[0].path.copy ();
                else if (kind == PropKind.TEXT) text = keys[0].text.copy ();
                else value = keys[0].value;
            }
            keys.clear ();
            touch ();
        }

        public double[] clamp_value (double[] v) {
            var r = new double[v.length];
            for (int i = 0; i < v.length; i++) {
                r[i] = v[i];
                if (kind == PropKind.COLOR) continue;
                if (dims == 1) r[i] = v[i].clamp (min, max);
            }
            return r;
        }

        public void set_value (double[] v) {
            value = clamp_value (v);
            touch ();
        }

        public void set_value_at (double t, double[] v) {
            if (keys.size > 0) set_key (t, v);
            else set_value (v);
        }

        public double scalar_at (double t) {
            var v = value_at (t);
            return v.length > 0 ? v[0] : 0;
        }

        public double[] value_at (double t) {
            var pre = raw_value_at (t);
            if (has_expression () && expression_hook != null && !in_expression) {
                in_expression = true;
                var r = expression_hook (this, t, pre);
                in_expression = false;
                if (r != null) {
                    if (r.length < dims) {
                        var full = pre;
                        for (int i = 0; i < r.length; i++) full[i] = r[i];
                        return full;
                    }
                    return r;
                }
            }
            return pre;
        }

        public BezPath path_at (double t) {
            var pre = raw_path_at (t);
            if (has_expression () && path_expression_hook != null && !in_expression) {
                in_expression = true;
                var r = path_expression_hook (this, t, pre);
                in_expression = false;
                if (r != null) return r;
            }
            return pre;
        }

        public TextDocument text_at (double t) {
            var base_doc = raw_text_at (t);
            if (has_expression () && text_expression_hook != null && !in_expression) {
                var r = text_expression_hook (this, t);
                if (r != null) {
                    var d = base_doc.copy ();
                    d.text = r;
                    return d;
                }
            }
            return base_doc;
        }

        public TextDocument raw_text_at (double t) {
            if (keys.size == 0) return text ?? new TextDocument ();
            Keyframe cur = keys[0];
            foreach (var k in keys) {
                if (k.time <= t + 1e-9) cur = k;
                else break;
            }
            return cur.text ?? text ?? new TextDocument ();
        }

        private int segment_index (double t, Gee.List<double?> times) {
            int lo = 0, hi = keys.size - 1;
            while (hi - lo > 1) {
                int mid = (lo + hi) / 2;
                if (times[mid] <= t) lo = mid;
                else hi = mid;
            }
            return lo;
        }

        public Gee.ArrayList<double?> effective_times () {
            var times = new Gee.ArrayList<double?> ();
            foreach (var k in keys) times.add (k.time);
            if (!spatial || keys.size < 3) return times;
            int i = 0;
            while (i < keys.size - 1) {
                if (keys[i].roving) { i++; continue; }
                int j = i + 1;
                while (j < keys.size - 1 && keys[j].roving) j++;
                if (j > i + 1) {
                    var lens = new double[j - i];
                    double total = 0;
                    for (int s = i; s < j; s++) {
                        lens[s - i] = spatial_segment_length (s);
                        total += lens[s - i];
                    }
                    double acc = 0;
                    for (int s = i + 1; s < j; s++) {
                        acc += lens[s - i - 1];
                        times[s] = keys[i].time + (keys[j].time - keys[i].time) * (total > 0 ? acc / total : (double) (s - i) / (j - i));
                    }
                }
                i = j;
            }
            return times;
        }

        private double spatial_segment_length (int s) {
            Singularity.Vector.Bezier b;
            if (!spatial_bezier (s, out b)) {
                double d = 0;
                for (int c = 0; c < dims; c++) d += Math.pow (keys[s + 1].value[c] - keys[s].value[c], 2);
                return Math.sqrt (d);
            }
            return b.length ();
        }

        public void auto_tangents (int i, out double[] tin, out double[] tout) {
            tin = new double[dims];
            tout = new double[dims];
            var k = keys[i];
            if (!k.spatial_auto) {
                for (int c = 0; c < dims; c++) {
                    tin[c] = c < k.tangent_in.length ? k.tangent_in[c] : 0;
                    tout[c] = c < k.tangent_out.length ? k.tangent_out[c] : 0;
                }
                return;
            }
            if (i == 0 || i == keys.size - 1) return;
            var prev = keys[i - 1].value;
            var next = keys[i + 1].value;
            double dprev = 0, dnext = 0;
            for (int c = 0; c < dims; c++) {
                dprev += Math.pow (k.value[c] - prev[c], 2);
                dnext += Math.pow (next[c] - k.value[c], 2);
            }
            dprev = Math.sqrt (dprev);
            dnext = Math.sqrt (dnext);
            double total = dprev + dnext;
            if (total < 1e-9) return;
            for (int c = 0; c < dims; c++) {
                double dir = (next[c] - prev[c]) / total;
                tout[c] = dir * dnext / 3.0;
                tin[c] = -dir * dprev / 3.0;
            }
        }

        public bool spatial_bezier (int s, out Singularity.Vector.Bezier b) {
            b = Singularity.Vector.Bezier.line (Singularity.Vector.Point (0, 0), Singularity.Vector.Point (0, 0));
            if (!spatial || dims < 2) return false;
            double[] in0, out0, in1, out1;
            auto_tangents (s, out in0, out out0);
            auto_tangents (s + 1, out in1, out out1);
            bool zero = true;
            for (int c = 0; c < 2; c++) if (out0[c] != 0 || in1[c] != 0) zero = false;
            if (zero) return false;
            var a = keys[s].value;
            var d = keys[s + 1].value;
            b = Singularity.Vector.Bezier (Singularity.Vector.Point (a[0], a[1]),
                Singularity.Vector.Point (a[0] + out0[0], a[1] + out0[1]),
                Singularity.Vector.Point (d[0] + in1[0], d[1] + in1[1]),
                Singularity.Vector.Point (d[0], d[1]));
            return true;
        }

        public void segment_ease (int s, Gee.List<double?> times, out double x1, out double y1, out double x2, out double y2) {
            var a = keys[s];
            var b = keys[s + 1];
            x1 = 0;
            y1 = 0;
            x2 = 1;
            y2 = 1;
            if (a.out_interp == Interp.BEZIER) {
                x1 = a.ease_out_x;
                y1 = a.ease_out_y;
                if (a.auto_bezier) auto_ease (s, times, true, out x1, out y1);
            }
            if (b.in_interp == Interp.BEZIER) {
                x2 = b.ease_in_x;
                y2 = b.ease_in_y;
                if (b.auto_bezier) auto_ease (s + 1, times, false, out x2, out y2);
            }
        }

        private double scalar_delta (int s) {
            if (dims == 0) return 1;
            if (dims == 1) return keys[s + 1].value[0] - keys[s].value[0];
            if (spatial) return spatial_segment_length (s);
            double d = 0;
            for (int c = 0; c < dims; c++) d += Math.pow (keys[s + 1].value[c] - keys[s].value[c], 2);
            return Math.sqrt (d);
        }

        private void auto_ease (int i, Gee.List<double?> times, bool outgoing, out double x, out double y) {
            x = outgoing ? 1.0 / 3.0 : 2.0 / 3.0;
            y = outgoing ? 0 : 1;
            if (i <= 0 || i >= keys.size - 1 || dims != 1) return;
            double speed = (keys[i + 1].value[0] - keys[i - 1].value[0]) / (times[i + 1] - times[i - 1]);
            int s = outgoing ? i : i - 1;
            double dt = times[s + 1] - times[s];
            double dv = keys[s + 1].value[0] - keys[s].value[0];
            if (dv.abs () < 1e-12) return;
            double norm = speed * dt / dv / 3.0;
            y = outgoing ? norm : 1 - norm;
        }

        public double progress_in_segment (int s, double t, Gee.List<double?> times) {
            double t0 = times[s], t1 = times[s + 1];
            double u = t1 > t0 ? ((t - t0) / (t1 - t0)).clamp (0, 1) : 1;
            var a = keys[s];
            var b = keys[s + 1];
            if (a.out_interp == Interp.LINEAR && b.in_interp == Interp.LINEAR) return u;
            double x1, y1, x2, y2;
            segment_ease (s, times, out x1, out y1, out x2, out y2);
            return Singularity.Animation.Bezier.solve (x1.clamp (0, 1), y1, x2.clamp (0, 1), y2, u);
        }

        public double[] raw_value_at (double t) {
            if (keys.size == 0 || dims == 0) return value;
            if (keys.size == 1) return keys[0].value;
            var times = effective_times ();
            if (t <= times[0]) return keys[0].value;
            if (t >= times[keys.size - 1]) return keys[keys.size - 1].value;
            int s = segment_index (t, times);
            var a = keys[s];
            var b = keys[s + 1];
            if (a.out_interp == Interp.HOLD || kind.holds_only ()) return a.value;
            double p = progress_in_segment (s, t, times);
            Singularity.Vector.Bezier sb;
            if (spatial_bezier (s, out sb)) {
                double len = sb.length ();
                double target = (p * len);
                Singularity.Vector.Point pt;
                if (target < 0) {
                    var dir = sb.derivative (0);
                    double dl = Math.hypot (dir.x, dir.y);
                    pt = dl > 0 ? Singularity.Vector.Point (sb.p0.x + dir.x / dl * target, sb.p0.y + dir.y / dl * target) : sb.p0;
                } else if (target > len) {
                    var dir = sb.derivative (1);
                    double dl = Math.hypot (dir.x, dir.y);
                    pt = dl > 0 ? Singularity.Vector.Point (sb.p3.x + dir.x / dl * (target - len), sb.p3.y + dir.y / dl * (target - len)) : sb.p3;
                } else {
                    pt = sb.at (sb.t_at_length (target));
                }
                var r = new double[dims];
                r[0] = pt.x;
                r[1] = pt.y;
                for (int c = 2; c < dims; c++) r[c] = a.value[c] + (b.value[c] - a.value[c]) * p;
                return r;
            }
            var r = new double[dims];
            for (int c = 0; c < dims; c++) r[c] = a.value[c] + (b.value[c] - a.value[c]) * p;
            return r;
        }

        public BezPath raw_path_at (double t) {
            if (keys.size == 0) return path ?? new BezPath ();
            if (keys.size == 1) return keys[0].path;
            var times = effective_times ();
            if (t <= times[0]) return keys[0].path;
            if (t >= times[keys.size - 1]) return keys[keys.size - 1].path;
            int s = segment_index (t, times);
            if (keys[s].out_interp == Interp.HOLD) return keys[s].path;
            double p = progress_in_segment (s, t, times);
            return BezPath.lerp (keys[s].path, keys[s + 1].path, p);
        }

        public double[] velocity_at (double t, double dt = 1e-3) {
            var a = value_at (t - dt);
            var b = value_at (t + dt);
            var r = new double[dims];
            for (int c = 0; c < dims && c < a.length && c < b.length; c++) r[c] = (b[c] - a[c]) / (2 * dt);
            return r;
        }

        public double speed_at (double t) {
            var v = velocity_at (t);
            double s = 0;
            foreach (var c in v) s += c * c;
            return Math.sqrt (s);
        }

        public double static_value_at_key (int index) {
            return keys[index].value.length > 0 ? keys[index].value[0] : 0;
        }

        public string choice_label (int index) {
            return index >= 0 && index < choices.length ? choices[index] : "";
        }
    }

    public class PropGroup : PropNode {
        public string type = "group";
        public bool enabled = true;
        public Gee.ArrayList<PropNode> children = new Gee.ArrayList<PropNode> ();
        public Gee.HashMap<string, string> attrs = new Gee.HashMap<string, string> ();
        public unowned Layer? layer = null;
        public bool expanded = false;

        public PropGroup (string type, string key, string name) {
            this.type = type;
            this.key = key;
            this.name = name;
        }

        public T add<T> (PropNode node) {
            node.parent = this;
            children.add (node);
            return (T) node;
        }

        public void insert (int index, PropNode node) {
            node.parent = this;
            children.insert (index.clamp (0, children.size), node);
        }

        public void remove (PropNode node) {
            children.remove (node);
            node.parent = null;
        }

        public Property? prop (string key) {
            foreach (var c in children) if (c is Property && c.key == key) return (Property) c;
            return null;
        }

        public PropGroup? group (string key) {
            foreach (var c in children) if (c is PropGroup && c.key == key) return (PropGroup) c;
            return null;
        }

        public PropNode? child (string key) {
            foreach (var c in children) if (c.key == key) return c;
            foreach (var c in children) if (c.name == key) return c;
            return null;
        }

        public PropNode? find (string path) {
            PropNode? n = this;
            foreach (var part in path.split ("/")) {
                if (part == "") continue;
                var g = n as PropGroup;
                if (g == null) return null;
                n = g.child (part);
                if (n == null) return null;
            }
            return n;
        }

        public Gee.ArrayList<PropGroup> groups_of_type (string prefix) {
            var r = new Gee.ArrayList<PropGroup> ();
            foreach (var c in children) {
                var g = c as PropGroup;
                if (g != null && g.type.has_prefix (prefix)) r.add (g);
            }
            return r;
        }

        public string attr (string key, string fallback = "") {
            return attrs.has_key (key) ? attrs[key] : fallback;
        }

        public void set_attr (string key, string value) {
            attrs[key] = value;
            touch ();
        }

        public double num (string key, double t) {
            var p = prop (key);
            return p != null ? p.scalar_at (t) : 0;
        }

        public double[] vec (string key, double t) {
            var p = prop (key);
            return p != null ? p.value_at (t) : new double[] { 0, 0, 0, 0 };
        }

        public int choice (string key, double t) {
            return (int) Math.round (num (key, t));
        }

        public bool toggle (string key, double t) {
            return num (key, t) > 0.5;
        }

        public override PropNode clone () {
            var g = new PropGroup (type, key, name);
            g.enabled = enabled;
            foreach (var e in attrs.entries) g.attrs[e.key] = e.value;
            foreach (var c in children) g.add<PropNode> (c.clone ());
            return g;
        }

        public void visit_props (Gee.List<Property> into) {
            foreach (var c in children) {
                if (c is Property) into.add ((Property) c);
                else ((PropGroup) c).visit_props (into);
            }
        }

        public string unique_key (string base_key) {
            if (child (base_key) == null) return base_key;
            int n = 2;
            while (child ("%s-%d".printf (base_key, n)) != null) n++;
            return "%s-%d".printf (base_key, n);
        }
    }

    public class TextDocument {
        public string text = "Text";
        public string font = "Sans";
        public int weight = 400;
        public bool italic = false;
        public double size = 72;
        public double[] fill = { 1, 1, 1, 1 };
        public double[] stroke = { 0, 0, 0, 1 };
        public double stroke_width = 0;
        public bool fill_over_stroke = true;
        public bool apply_fill = true;
        public bool apply_stroke = false;
        public double tracking = 0;
        public double leading = 0;
        public int justify = 0;
        public bool all_caps = false;
        public bool small_caps = false;
        public double baseline_shift = 0;
        public double box_width = 0;
        public double box_height = 0;
        public string variations = "";
        public string features = "";
        public double first_indent = 0;
        public double space_before = 0;
        public double space_after = 0;
        public string direction = "auto";

        public TextDocument copy () {
            var d = new TextDocument ();
            d.text = text;
            d.font = font;
            d.weight = weight;
            d.italic = italic;
            d.size = size;
            d.fill = fill;
            d.stroke = stroke;
            d.stroke_width = stroke_width;
            d.fill_over_stroke = fill_over_stroke;
            d.apply_fill = apply_fill;
            d.apply_stroke = apply_stroke;
            d.tracking = tracking;
            d.leading = leading;
            d.justify = justify;
            d.all_caps = all_caps;
            d.small_caps = small_caps;
            d.baseline_shift = baseline_shift;
            d.box_width = box_width;
            d.box_height = box_height;
            d.variations = variations;
            d.features = features;
            d.first_indent = first_indent;
            d.space_before = space_before;
            d.space_after = space_after;
            d.direction = direction;
            return d;
        }

        public bool is_box () {
            return box_width > 0;
        }

        public Json.Node to_json () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("text").add_string_value (text);
            b.set_member_name ("font").add_string_value (font);
            b.set_member_name ("weight").add_int_value (weight);
            b.set_member_name ("italic").add_boolean_value (italic);
            b.set_member_name ("size").add_double_value (size);
            b.set_member_name ("fill");
            JsonUtil.add_array (b, fill);
            b.set_member_name ("stroke");
            JsonUtil.add_array (b, stroke);
            b.set_member_name ("strokeWidth").add_double_value (stroke_width);
            b.set_member_name ("fillOverStroke").add_boolean_value (fill_over_stroke);
            b.set_member_name ("applyFill").add_boolean_value (apply_fill);
            b.set_member_name ("applyStroke").add_boolean_value (apply_stroke);
            b.set_member_name ("tracking").add_double_value (tracking);
            b.set_member_name ("leading").add_double_value (leading);
            b.set_member_name ("justify").add_int_value (justify);
            b.set_member_name ("allCaps").add_boolean_value (all_caps);
            b.set_member_name ("smallCaps").add_boolean_value (small_caps);
            b.set_member_name ("baselineShift").add_double_value (baseline_shift);
            b.set_member_name ("boxWidth").add_double_value (box_width);
            b.set_member_name ("boxHeight").add_double_value (box_height);
            b.set_member_name ("variations").add_string_value (variations);
            b.set_member_name ("features").add_string_value (features);
            b.set_member_name ("firstIndent").add_double_value (first_indent);
            b.set_member_name ("spaceBefore").add_double_value (space_before);
            b.set_member_name ("spaceAfter").add_double_value (space_after);
            b.set_member_name ("direction").add_string_value (direction);
            b.end_object ();
            return b.get_root ();
        }

        public static TextDocument from_json (Json.Object o) {
            var d = new TextDocument ();
            d.text = JsonUtil.str (o, "text", d.text);
            d.font = JsonUtil.str (o, "font", d.font);
            d.weight = (int) JsonUtil.num (o, "weight", d.weight);
            d.italic = JsonUtil.bool_of (o, "italic", false);
            d.size = JsonUtil.num (o, "size", d.size);
            d.fill = JsonUtil.array (o, "fill", d.fill);
            d.stroke = JsonUtil.array (o, "stroke", d.stroke);
            d.stroke_width = JsonUtil.num (o, "strokeWidth", 0);
            d.fill_over_stroke = JsonUtil.bool_of (o, "fillOverStroke", true);
            d.apply_fill = JsonUtil.bool_of (o, "applyFill", true);
            d.apply_stroke = JsonUtil.bool_of (o, "applyStroke", false);
            d.tracking = JsonUtil.num (o, "tracking", 0);
            d.leading = JsonUtil.num (o, "leading", 0);
            d.justify = (int) JsonUtil.num (o, "justify", 0);
            d.all_caps = JsonUtil.bool_of (o, "allCaps", false);
            d.small_caps = JsonUtil.bool_of (o, "smallCaps", false);
            d.baseline_shift = JsonUtil.num (o, "baselineShift", 0);
            d.box_width = JsonUtil.num (o, "boxWidth", 0);
            d.box_height = JsonUtil.num (o, "boxHeight", 0);
            d.variations = JsonUtil.str (o, "variations", "");
            d.features = JsonUtil.str (o, "features", "");
            d.first_indent = JsonUtil.num (o, "firstIndent", 0);
            d.space_before = JsonUtil.num (o, "spaceBefore", 0);
            d.space_after = JsonUtil.num (o, "spaceAfter", 0);
            d.direction = JsonUtil.str (o, "direction", "auto");
            return d;
        }
    }

    namespace JsonUtil {
        public void add_array (Json.Builder b, double[] v) {
            b.begin_array ();
            foreach (var d in v) b.add_double_value (d);
            b.end_array ();
        }

        public string str (Json.Object o, string key, string fallback = "") {
            return o.has_member (key) && o.get_member (key).get_value_type () == typeof (string) ? o.get_string_member (key) : fallback;
        }

        public double num (Json.Object o, string key, double fallback = 0) {
            if (!o.has_member (key)) return fallback;
            var n = o.get_member (key);
            if (n.get_node_type () != Json.NodeType.VALUE) return fallback;
            var t = n.get_value_type ();
            if (t == typeof (double)) return n.get_double ();
            if (t == typeof (int64)) return (double) n.get_int ();
            if (t == typeof (bool)) return n.get_boolean () ? 1 : 0;
            return fallback;
        }

        public bool bool_of (Json.Object o, string key, bool fallback = false) {
            if (!o.has_member (key)) return fallback;
            var n = o.get_member (key);
            if (n.get_node_type () != Json.NodeType.VALUE) return fallback;
            if (n.get_value_type () == typeof (bool)) return n.get_boolean ();
            return num (o, key, fallback ? 1 : 0) != 0;
        }

        public double[] array (Json.Object o, string key, double[] fallback) {
            if (!o.has_member (key) || o.get_member (key).get_node_type () != Json.NodeType.ARRAY) return fallback;
            return node_array (o.get_member (key));
        }

        public double[] node_array (Json.Node node) {
            var arr = node.get_array ();
            var r = new double[arr.get_length ()];
            for (uint i = 0; i < arr.get_length (); i++) {
                var e = arr.get_element (i);
                r[i] = e.get_value_type () == typeof (int64) ? (double) e.get_int () : e.get_double ();
            }
            return r;
        }

        public string to_string (Json.Node node, bool pretty = true) {
            var g = new Json.Generator ();
            g.pretty = pretty;
            g.indent = 1;
            g.set_root (node);
            return g.to_data (null);
        }

        public Json.Node parse (string text) throws Error {
            var p = new Json.Parser ();
            p.load_from_data (text);
            return p.get_root ();
        }
    }
}
