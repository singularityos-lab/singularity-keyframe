namespace Singularity.Apps.Keyframe {

    public class ExprContext {
        public Property? prop;
        public Layer? layer;
        public Composition? comp;
        public Project? project;
        public double comp_time;
        public double[] pre = {};
        public BezPath? pre_path;
        public uint seed = 0;
        public bool timeless = false;
        public int random_counter = 0;
        public bool mutable = false;
        public StringBuilder output = new StringBuilder ();
    }

    namespace Expressions {
        private Interpreter? shared = null;
        private Gee.ArrayList<ExprContext>? stack = null;
        private RecMutex mutex;

        public void install () {
            Property.expression_hook = evaluate_value;
            Property.path_expression_hook = evaluate_path;
            Property.text_expression_hook = evaluate_text;
        }

        public Interpreter interpreter () {
            if (shared == null) {
                shared = new Interpreter ();
                stack = new Gee.ArrayList<ExprContext> ();
                define_globals (shared);
                shared.fallback = (name) => {
                    var ctx = current ();
                    if (ctx != null && name == "time") return JsValue.number (ctx.comp_time);
                    if (ctx != null && name == "value" && ctx.prop != null && ctx.prop.kind != PropKind.PATH && ctx.prop.kind != PropKind.TEXT) return JsValue.from_value (ctx.pre);
                    if (ctx != null && ctx.prop != null && ctx.prop.dims > 0) {
                        if (name == "velocity") return ExprHost.prop_velocity (ctx.prop, ctx.comp_time);
                        if (name == "speed") return JsValue.number (ExprHost.prop_speed (ctx.prop, ctx.comp_time));
                    }
                    if (ctx == null || ctx.layer == null) return null;
                    var lo = ExprHost.layer_object (ctx.layer, ctx);
                    var v = lo.obj.getter (name);
                    if (v != null && v.kind != JsKind.UNDEFINED) return v;
                    return null;
                };
            }
            return shared;
        }

        public ExprContext? current () {
            if (stack == null || stack.size == 0) return null;
            return stack[stack.size - 1];
        }

        public void push (ExprContext c) {
            interpreter ();
            stack.add (c);
        }

        public void pop () {
            if (stack != null && stack.size > 0) stack.remove_at (stack.size - 1);
        }

        private uint hash_string (string s) {
            uint h = 2166136261u;
            for (int i = 0; i < s.length; i++) {
                h ^= (uint8) s[i];
                h *= 16777619u;
            }
            return h;
        }

        public ExprContext context_for (Property prop, double layer_time) {
            var c = new ExprContext ();
            c.prop = prop;
            c.layer = prop.owner_layer ();
            c.comp = c.layer != null ? c.layer.comp : null;
            c.project = c.comp != null ? c.comp.project : null;
            c.comp_time = c.layer != null ? c.layer.comp_time (layer_time) : layer_time;
            c.seed = hash_string ((c.layer != null ? c.layer.id : "") + "/" + prop.path_string ());
            return c;
        }

        public Env scope_for (Interpreter it, ExprContext c) {
            var env = new Env (it.globals);
            if (c.prop != null) {
                env.define ("thisProperty", ExprHost.prop_object (c.prop, c));
                if (c.prop.kind == PropKind.PATH) env.define ("value", ExprHost.path_value (c.pre_path ?? c.prop.raw_path_at (layer_time_of (c))));
                else if (c.prop.kind == PropKind.TEXT) env.define ("value", JsValue.string_value (c.prop.text_at (layer_time_of (c)).text));
                env.define ("numKeys", JsValue.number (c.prop.keys.size));
            }
            if (c.layer != null) {
                env.define ("thisLayer", ExprHost.layer_object (c.layer, c));
                env.define ("index", JsValue.number (c.comp != null ? c.comp.layers.index_of (c.layer) + 1 : 1));
                env.define ("inPoint", JsValue.number (c.layer.in_point));
                env.define ("outPoint", JsValue.number (c.layer.out_point));
                env.define ("startTime", JsValue.number (c.layer.start_time));
            }
            if (c.comp != null) env.define ("thisComp", ExprHost.comp_object (c.comp, c));
            if (TextExpressionVars.active) {
                env.define ("textIndex", JsValue.number (TextExpressionVars.index));
                env.define ("textTotal", JsValue.number (TextExpressionVars.total));
                env.define ("selectorValue", JsValue.number (TextExpressionVars.selector_value));
            }
            return env;
        }

        public double layer_time_of (ExprContext c) {
            return c.layer != null ? c.layer.layer_time (c.comp_time) : c.comp_time;
        }

        private JsValue? run_expression (Property prop, double time, ExprContext c) {
            var it = interpreter ();
            mutex.lock ();
            push (c);
            JsValue? result = null;
            int saved_steps = it.steps;
            try {
                var env = scope_for (it, c);
                var prog = it.compile (prop.expression);
                result = it.run_node (prog, env);
                prop.expression_error = "";
            } catch (ExprError e) {
                prop.expression_error = e.message;
                result = null;
            }
            it.steps = saved_steps;
            pop ();
            mutex.unlock ();
            return result;
        }

        public double[]? evaluate_value (Property prop, double time, double[] pre) {
            var c = context_for (prop, time);
            c.pre = pre;
            var r = run_expression (prop, time, c);
            if (r == null) return null;
            try {
                var d = interpreter ().to_doubles (r);
                if (d == null) {
                    prop.expression_error = _("The expression result is not a number or an array");
                    return null;
                }
                foreach (var x in d) {
                    if (x.is_nan () || x.is_infinity () != 0) {
                        prop.expression_error = _("The expression result is not a finite number");
                        return null;
                    }
                }
                if (prop.dims > 0 && d.length > prop.dims && prop.kind != PropKind.COLOR) d = d[0:prop.dims];
                return d;
            } catch (ExprError e) {
                prop.expression_error = e.message;
                return null;
            }
        }

        public BezPath? evaluate_path (Property prop, double time, BezPath pre) {
            var c = context_for (prop, time);
            c.pre_path = pre;
            var r = run_expression (prop, time, c);
            if (r == null) return null;
            var p = ExprHost.to_path (r);
            if (p == null) prop.expression_error = _("The expression result is not a path");
            return p;
        }

        public string? evaluate_text (Property prop, double time) {
            if (!prop.has_expression () || prop.in_expression) return null;
            var c = context_for (prop, time);
            prop.in_expression = true;
            var r = run_expression (prop, time, c);
            prop.in_expression = false;
            if (r == null) return null;
            return interpreter ().to_string (r);
        }

        public string reference_for (Layer from, Property target) {
            var tl = target.owner_layer ();
            var parts = new Gee.ArrayList<string> ();
            PropNode? n = target;
            while (n != null && n.parent != null) {
                parts.insert (0, segment_for (n));
                n = n.parent;
            }
            string chain = string.joinv ("", parts.to_array ());
            if (chain.has_prefix (".")) chain = chain.substring (1);
            if (tl == null || tl == from) return chain;
            string layer_ref = "layer(\"%s\")".printf (escape (tl.name));
            string comp_ref = (tl.comp != null && tl.comp != from.comp) ? "comp(\"%s\").".printf (escape (tl.comp.name)) : "thisComp.";
            return comp_ref + layer_ref + "." + chain;
        }

        private string escape (string s) {
            return s.replace ("\\", "\\\\").replace ("\"", "\\\"");
        }

        private string segment_for (PropNode n) {
            var parent = n.parent;
            string ptype = parent != null ? parent.type : "";
            if (n is Property) {
                if (ptype.has_prefix ("effect.")) return "(\"%s\")".printf (escape (n.name));
                return "." + ExprHost.ae_name (n.key);
            }
            var g = (PropGroup) n;
            switch (g.type) {
                case "effects":
                case "masks":
                case "contents":
                case "shape.contents":
                case "text.animators":
                case "text.selectors":
                case "text.properties":
                    return "";
                case "transform":
                case "shape.transform":
                    return ".transform";
                case "text":
                    return ".text";
                case "material":
                    return ".materialOption";
                case "camera":
                    return ".cameraOption";
                case "light":
                    return ".lightOption";
                case "audio":
                    return ".audio";
            }
            if (g.type.has_prefix ("effect.")) return ".effect(\"%s\")".printf (escape (g.name));
            if (g.type == "mask") return ".mask(\"%s\")".printf (escape (g.name));
            if (g.type == "text.animator") return ".animator(\"%s\")".printf (escape (g.name));
            if (ptype == "text.selectors") return ".selector(\"%s\")".printf (escape (g.name));
            if (g.type.has_prefix ("shape.") || ptype == "contents") return ".content(\"%s\")".printf (escape (g.name));
            return "." + ExprHost.ae_name (g.key);
        }

        private double[] vec_of (Interpreter it, JsValue v) throws ExprError {
            var d = it.to_doubles (v);
            if (d == null) throw new ExprError.RUNTIME ("Expected a number or an array");
            return d;
        }

        private JsValue from_vec (double[] v, bool force_array) {
            if (v.length == 1 && !force_array) return JsValue.number (v[0]);
            return JsValue.from_doubles (v);
        }

        private bool is_array_arg (Interpreter it, JsValue v) throws ExprError {
            return it.prim (v).kind == JsKind.ARRAY;
        }

        private double num_arg (Interpreter it, JsValue[] args, int i, double fallback) throws ExprError {
            if (i >= args.length || args[i].kind == JsKind.UNDEFINED) return fallback;
            return it.to_number (it.prim (args[i]));
        }

        public JsValue interpolate (Interpreter it, JsValue[] args, double k1x, double k1y, double k2x, double k2y, bool linear) throws ExprError {
            double t, t0 = 0, t1 = 1;
            JsValue va, vb;
            if (args.length >= 5) {
                t = num_arg (it, args, 0, 0);
                t0 = num_arg (it, args, 1, 0);
                t1 = num_arg (it, args, 2, 1);
                va = args[3];
                vb = args[4];
            } else if (args.length >= 3) {
                t = num_arg (it, args, 0, 0);
                va = args[1];
                vb = args[2];
            } else {
                throw new ExprError.RUNTIME ("Interpolation needs 3 or 5 arguments");
            }
            bool reversed = t1 < t0;
            if (reversed) {
                double tmp = t0;
                t0 = t1;
                t1 = tmp;
                var tv = va;
                va = vb;
                vb = tv;
            }
            double u = t1 > t0 ? ((t - t0) / (t1 - t0)).clamp (0, 1) : (t >= t1 ? 1 : 0);
            double k = linear ? u : Singularity.Animation.Bezier.solve (k1x, k1y, k2x, k2y, u);
            var a = vec_of (it, va);
            var b = vec_of (it, vb);
            int n = int.max (a.length, b.length);
            var r = new double[n];
            for (int i = 0; i < n; i++) {
                double x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
                r[i] = x + (y - x) * k;
            }
            return from_vec (r, is_array_arg (it, va) || is_array_arg (it, vb));
        }

        private void define_globals (Interpreter it) {
            var g = it.globals;
            g.define ("linear", JsValue.native ("linear", (it2, self, args) => interpolate (it2, args, 0, 0, 1, 1, true)));
            g.define ("ease", JsValue.native ("ease", (it2, self, args) => interpolate (it2, args, 0.33, 0, 0.67, 1, false)));
            g.define ("easeIn", JsValue.native ("easeIn", (it2, self, args) => interpolate (it2, args, 0.33, 0, 1, 1, false)));
            g.define ("easeOut", JsValue.native ("easeOut", (it2, self, args) => interpolate (it2, args, 0, 0, 0.67, 1, false)));
            g.define ("add", JsValue.native ("add", (it2, self, args) => it2.binary ("+", args.length > 0 ? args[0] : JsValue.number (0), args.length > 1 ? args[1] : JsValue.number (0))));
            g.define ("sub", JsValue.native ("sub", (it2, self, args) => it2.binary ("-", args.length > 0 ? args[0] : JsValue.number (0), args.length > 1 ? args[1] : JsValue.number (0))));
            g.define ("mul", JsValue.native ("mul", (it2, self, args) => it2.binary ("*", args.length > 0 ? args[0] : JsValue.number (0), args.length > 1 ? args[1] : JsValue.number (1))));
            g.define ("div", JsValue.native ("div", (it2, self, args) => it2.binary ("/", args.length > 0 ? args[0] : JsValue.number (0), args.length > 1 ? args[1] : JsValue.number (1))));
            g.define ("clamp", JsValue.native ("clamp", (it2, self, args) => {
                if (args.length < 3) throw new ExprError.RUNTIME ("clamp needs 3 arguments");
                var v = vec_of (it2, args[0]);
                var lo = vec_of (it2, args[1]);
                var hi = vec_of (it2, args[2]);
                var r = new double[v.length];
                for (int i = 0; i < v.length; i++) r[i] = v[i].clamp (lo[int.min (i, lo.length - 1)], hi[int.min (i, hi.length - 1)]);
                return from_vec (r, is_array_arg (it2, args[0]));
            }));
            g.define ("dot", JsValue.native ("dot", (it2, self, args) => {
                var a = vec_of (it2, args[0]);
                var b = vec_of (it2, args[1]);
                double s = 0;
                for (int i = 0; i < int.min (a.length, b.length); i++) s += a[i] * b[i];
                return JsValue.number (s);
            }));
            g.define ("cross", JsValue.native ("cross", (it2, self, args) => {
                var a = vec_of (it2, args[0]);
                var b = vec_of (it2, args[1]);
                double[] a3 = { a[0], a.length > 1 ? a[1] : 0, a.length > 2 ? a[2] : 0 };
                double[] b3 = { b[0], b.length > 1 ? b[1] : 0, b.length > 2 ? b[2] : 0 };
                return JsValue.from_doubles ({ a3[1] * b3[2] - a3[2] * b3[1], a3[2] * b3[0] - a3[0] * b3[2], a3[0] * b3[1] - a3[1] * b3[0] });
            }));
            g.define ("length", JsValue.native ("length", (it2, self, args) => {
                var a = vec_of (it2, args[0]);
                double s = 0;
                if (args.length > 1) {
                    var b = vec_of (it2, args[1]);
                    for (int i = 0; i < int.max (a.length, b.length); i++) s += Math.pow ((i < a.length ? a[i] : 0) - (i < b.length ? b[i] : 0), 2);
                } else {
                    foreach (var x in a) s += x * x;
                }
                return JsValue.number (Math.sqrt (s));
            }));
            g.define ("normalize", JsValue.native ("normalize", (it2, self, args) => {
                var a = vec_of (it2, args[0]);
                double s = 0;
                foreach (var x in a) s += x * x;
                s = Math.sqrt (s);
                var r = new double[a.length];
                for (int i = 0; i < a.length; i++) r[i] = s > 0 ? a[i] / s : 0;
                return JsValue.from_doubles (r);
            }));
            g.define ("lookAt", JsValue.native ("lookAt", (it2, self, args) => {
                var f = vec_of (it2, args[0]);
                var t = vec_of (it2, args[1]);
                double dx = t[0] - f[0], dy = (t.length > 1 ? t[1] : 0) - (f.length > 1 ? f[1] : 0), dz = (t.length > 2 ? t[2] : 0) - (f.length > 2 ? f[2] : 0);
                double pitch = -Math.atan2 (dy, Math.sqrt (dx * dx + dz * dz)) * 180 / Math.PI;
                double yaw = Math.atan2 (dx, dz) * 180 / Math.PI;
                return JsValue.from_doubles ({ pitch, yaw, 0 });
            }));
            g.define ("degreesToRadians", JsValue.native ("degreesToRadians", (it2, self, args) => JsValue.number (num_arg (it2, args, 0, 0) * Math.PI / 180)));
            g.define ("radiansToDegrees", JsValue.native ("radiansToDegrees", (it2, self, args) => JsValue.number (num_arg (it2, args, 0, 0) * 180 / Math.PI)));
            g.define ("seedRandom", JsValue.native ("seedRandom", (it2, self, args) => {
                var c = current ();
                if (c != null) {
                    c.seed = (uint) (int) num_arg (it2, args, 0, 0) * 2654435761u + (c.layer != null ? hash_string (c.layer.id) : 0);
                    c.timeless = args.length > 1 && it2.truthy (args[1]);
                    c.random_counter = 0;
                }
                return JsValue.undefined ();
            }));
            g.define ("random", JsValue.native ("random", (it2, self, args) => random_value (it2, args, false)));
            g.define ("gaussRandom", JsValue.native ("gaussRandom", (it2, self, args) => random_value (it2, args, true)));
            g.define ("noise", JsValue.native ("noise", (it2, self, args) => {
                var v = vec_of (it2, args.length > 0 ? args[0] : JsValue.number (0));
                double r;
                if (v.length >= 3) r = Noise.perlin3 (v[0], v[1], v[2]);
                else if (v.length == 2) r = Noise.perlin2 (v[0], v[1]);
                else r = Noise.perlin1 (v[0]);
                return JsValue.number (r.clamp (-1, 1));
            }));
            g.define ("timeToFrames", JsValue.native ("timeToFrames", (it2, self, args) => {
                var c = current ();
                double fps = num_arg (it2, args, 1, c != null && c.comp != null ? c.comp.fps : 30);
                double t = num_arg (it2, args, 0, c != null ? c.comp_time + (c.comp != null ? c.comp.start_timecode : 0) : 0);
                return JsValue.number (Math.floor (t * fps + 1e-6));
            }));
            g.define ("framesToTime", JsValue.native ("framesToTime", (it2, self, args) => {
                var c = current ();
                double fps = num_arg (it2, args, 1, c != null && c.comp != null ? c.comp.fps : 30);
                return JsValue.number (num_arg (it2, args, 0, 0) / fps);
            }));
            g.define ("timeToTimecode", JsValue.native ("timeToTimecode", (it2, self, args) => {
                var c = current ();
                double t = num_arg (it2, args, 0, c != null ? c.comp_time + (c.comp != null ? c.comp.start_timecode : 0) : 0);
                int base_fps = (int) num_arg (it2, args, 1, 30);
                bool neg = t < 0;
                int64 frames = (int64) Math.floor (t.abs () * base_fps + 1e-6);
                int ff = (int) (frames % base_fps);
                int64 secs = frames / base_fps;
                return JsValue.string_value ("%s%d:%02d:%02d:%02d".printf (neg ? "-" : "", (int) (secs / 3600), (int) ((secs / 60) % 60), (int) (secs % 60), ff));
            }));
            g.define ("timeToCurrentFormat", g.vars["timeToTimecode"]);
            g.define ("posterizeTime", JsValue.native ("posterizeTime", (it2, self, args) => {
                var c = current ();
                double fps = num_arg (it2, args, 0, 0);
                if (c == null) return JsValue.undefined ();
                double t = fps > 0 ? Math.floor (c.comp_time * fps + 1e-6) / fps : c.comp_time;
                c.comp_time = t;
                if (c.prop != null && c.prop.dims > 0) c.pre = c.prop.raw_value_at (layer_time_of (c));
                return JsValue.number (t);
            }));
            g.define ("comp", JsValue.native ("comp", (it2, self, args) => {
                var c = current ();
                if (c == null || c.project == null || args.length == 0) throw new ExprError.RUNTIME ("No project available");
                var name = it2.to_string (args[0]);
                var cc = c.project.comp_by_name (name);
                if (cc == null) throw new ExprError.RUNTIME ("Composition \"%s\" does not exist", name);
                return ExprHost.comp_object (cc, c);
            }));
            g.define ("footage", JsValue.native ("footage", (it2, self, args) => {
                var c = current ();
                if (c == null || c.project == null || args.length == 0) throw new ExprError.RUNTIME ("No project available");
                var name = it2.to_string (args[0]);
                foreach (var item in c.project.items) {
                    var f = item as Footage;
                    if (f != null && f.name == name) {
                        var o = new JsObject ();
                        o.put ("name", JsValue.string_value (f.name));
                        o.put ("width", JsValue.number (f.width));
                        o.put ("height", JsValue.number (f.height));
                        o.put ("duration", JsValue.number (f.duration));
                        o.put ("frameDuration", JsValue.number (1.0 / f.frame_rate ()));
                        return JsValue.object (o);
                    }
                }
                throw new ExprError.RUNTIME ("Footage \"%s\" does not exist", name);
            }));
            g.define ("createPath", JsValue.native ("createPath", (it2, self, args) => {
                var p = new BezPath ();
                p.closed = args.length < 4 || it2.truthy (args[3]);
                var pts = args.length > 0 ? it2.prim (args[0]) : JsValue.new_array ();
                if (pts.kind != JsKind.ARRAY) throw new ExprError.RUNTIME ("createPath needs an array of points");
                for (int i = 0; i < pts.arr.size; i++) {
                    var pt = vec_of (it2, pts.arr[i]);
                    double ix = 0, iy = 0, ox = 0, oy = 0;
                    if (args.length > 1) {
                        var ins = it2.prim (args[1]);
                        if (ins.kind == JsKind.ARRAY && i < ins.arr.size) {
                            var v = vec_of (it2, ins.arr[i]);
                            ix = v[0];
                            iy = v.length > 1 ? v[1] : 0;
                        }
                    }
                    if (args.length > 2) {
                        var outs = it2.prim (args[2]);
                        if (outs.kind == JsKind.ARRAY && i < outs.arr.size) {
                            var v = vec_of (it2, outs.arr[i]);
                            ox = v[0];
                            oy = v.length > 1 ? v[1] : 0;
                        }
                    }
                    p.add (pt[0], pt.length > 1 ? pt[1] : 0, ix, iy, ox, oy);
                }
                return ExprHost.path_value (p);
            }));
            g.define ("valueAtTime", JsValue.native ("valueAtTime", (it2, self, args) => {
                var c = current ();
                if (c == null || c.prop == null) throw new ExprError.RUNTIME ("valueAtTime needs a property");
                return ExprHost.prop_value_at (c.prop, num_arg (it2, args, 0, c.comp_time));
            }));
            g.define ("velocityAtTime", JsValue.native ("velocityAtTime", (it2, self, args) => {
                var c = current ();
                if (c == null || c.prop == null) throw new ExprError.RUNTIME ("velocityAtTime needs a property");
                return ExprHost.prop_velocity (c.prop, num_arg (it2, args, 0, c.comp_time));
            }));
            g.define ("speedAtTime", JsValue.native ("speedAtTime", (it2, self, args) => {
                var c = current ();
                if (c == null || c.prop == null) throw new ExprError.RUNTIME ("speedAtTime needs a property");
                return JsValue.number (ExprHost.prop_speed (c.prop, num_arg (it2, args, 0, c.comp_time)));
            }));
            string[] prop_fns = { "wiggle", "loopOut", "loopIn", "loopOutDuration", "loopInDuration", "key", "nearestKey", "smooth", "temporalWiggle", "points", "inTangents", "outTangents", "isClosed", "pointOnPath", "tangentOnPath", "normalOnPath" };
            foreach (var name in prop_fns) {
                string fname = name;
                g.define (fname, JsValue.native (fname, (it2, self, args) => {
                    var c = current ();
                    if (c == null || c.prop == null) throw new ExprError.RUNTIME ("%s needs a property", fname);
                    var po = ExprHost.prop_object (c.prop, c);
                    var f = po.obj.getter (fname);
                    return it2.call (f, po, args);
                }));
            }
            var kit = new JsObject ();
            kit.put ("LINEAR", JsValue.number (6612));
            kit.put ("BEZIER", JsValue.number (6613));
            kit.put ("HOLD", JsValue.number (6614));
            g.define ("KeyframeInterpolationType", JsValue.object (kit));
            var lt = new JsObject ();
            lt.put ("PARALLEL", JsValue.number (4412));
            lt.put ("SPOT", JsValue.number (4413));
            lt.put ("POINT", JsValue.number (4414));
            lt.put ("AMBIENT", JsValue.number (4415));
            g.define ("LightType", JsValue.object (lt));
        }

        private double random_next (uint seed, int frame, ref int counter) {
            double u = Noise.hash01 ((int) (seed & 0x7fffffff), frame * 7919 + counter * 104729, counter);
            counter += 977;
            return u;
        }

        private double random_sample (uint seed, int frame, ref int counter, bool gauss) {
            if (!gauss) return random_next (seed, frame, ref counter);
            double u1 = double.max (1e-9, random_next (seed, frame, ref counter));
            double u2 = random_next (seed, frame, ref counter);
            double z = Math.sqrt (-2 * Math.log (u1)) * Math.cos (2 * Math.PI * u2);
            return (z / 6 + 0.5).clamp (0, 1);
        }

        private JsValue random_value (Interpreter it, JsValue[] args, bool gauss) throws ExprError {
            var c = current ();
            uint seed = c != null ? c.seed : 0;
            int frame = c != null && !c.timeless && c.comp != null ? (int) Math.floor (c.comp_time * c.comp.fps + 1e-6) : 0;
            int counter = 0;
            if (c != null) {
                counter = c.random_counter;
                c.random_counter += 31;
            }
            if (args.length == 0) return JsValue.number (random_sample (seed, frame, ref counter, gauss));
            var a = it.prim (args[0]);
            if (args.length == 1) {
                if (a.kind == JsKind.ARRAY) {
                    var m = vec_of (it, a);
                    var r = new double[m.length];
                    for (int i = 0; i < m.length; i++) r[i] = random_sample (seed, frame, ref counter, gauss) * m[i];
                    return JsValue.from_doubles (r);
                }
                return JsValue.number (random_sample (seed, frame, ref counter, gauss) * it.to_number (a));
            }
            var lo = vec_of (it, args[0]);
            var hi = vec_of (it, args[1]);
            int n = int.max (lo.length, hi.length);
            var r = new double[n];
            for (int i = 0; i < n; i++) {
                double l = lo[int.min (i, lo.length - 1)], h = hi[int.min (i, hi.length - 1)];
                r[i] = l + random_sample (seed, frame, ref counter, gauss) * (h - l);
            }
            return from_vec (r, a.kind == JsKind.ARRAY || it.prim (args[1]).kind == JsKind.ARRAY);
        }
    }

    namespace ExprHost {
        public string ae_name (string key) {
            switch (key) {
                case "anchor": return "anchorPoint";
                case "rotation-x": return "xRotation";
                case "rotation-y": return "yRotation";
                case "point-of-interest": return "pointOfInterest";
                case "source-text": return "sourceText";
                case "path": return "path";
            }
            var sb = new StringBuilder ();
            bool up = false;
            for (int i = 0; i < key.length; i++) {
                char ch = key[i];
                if (ch == '-' || ch == '_' || ch == ' ') {
                    up = true;
                    continue;
                }
                sb.append_c (up ? ch.toupper () : ch);
                up = false;
            }
            return sb.str;
        }

        public string kebab (string name) {
            var sb = new StringBuilder ();
            for (int i = 0; i < name.length; i++) {
                char ch = name[i];
                if (ch.isupper () && i > 0) {
                    sb.append_c ('-');
                    sb.append_c (ch.tolower ());
                } else {
                    sb.append_c (ch.tolower ());
                }
            }
            return sb.str;
        }

        public PropNode? resolve_child (PropGroup g, string name) {
            foreach (var c in g.children) if (c.key == name) return c;
            string alias = "";
            switch (name) {
                case "anchorPoint": alias = "anchor"; break;
                case "xRotation": alias = "rotation-x"; break;
                case "yRotation": alias = "rotation-y"; break;
                case "zRotation": alias = "rotation"; break;
                case "pointOfInterest": alias = "point-of-interest"; break;
                case "maskPath": alias = "path"; break;
                case "maskFeather": alias = "feather"; break;
                case "maskOpacity": alias = "opacity"; break;
                case "maskExpansion": alias = "expansion"; break;
                case "sourceText": alias = "source-text"; break;
                case "materialOption": alias = "material"; break;
                case "cameraOption": alias = "camera"; break;
                case "lightOption": alias = "light"; break;
                case "audioLevels": alias = "levels"; break;
                case "timeRemap": alias = "time-remap"; break;
                case "pathOption": alias = "path-options"; break;
                case "moreOption": alias = "more-options"; break;
            }
            if (alias != "") foreach (var c in g.children) if (c.key == alias) return c;
            var k = kebab (name);
            foreach (var c in g.children) if (c.key == k) return c;
            var lower = name.down ();
            foreach (var c in g.children) if (c.name.down () == lower) return c;
            return null;
        }

        public PropNode? child_by_arg (Interpreter it, PropGroup g, JsValue arg) throws ExprError {
            var a = it.prim (arg);
            if (a.kind == JsKind.NUMBER) {
                int i = (int) a.num - 1;
                return i >= 0 && i < g.children.size ? g.children[i] : null;
            }
            return resolve_child (g, it.to_string (a));
        }

        public double layer_time (Property p, double comp_t) {
            var l = p.owner_layer ();
            return l != null ? l.layer_time (comp_t) : comp_t;
        }

        public double comp_time_of (Property p, double lt) {
            var l = p.owner_layer ();
            return l != null ? l.comp_time (lt) : lt;
        }

        public JsValue path_value (BezPath p) {
            var o = new JsObject ();
            o.class_name = "Path";
            o.host = new PathBox (p);
            o.getter = (name) => path_member (p, name);
            return JsValue.object (o);
        }

        public class PathBox : Object {
            public BezPath path;

            public PathBox (BezPath p) {
                path = p;
            }
        }

        private JsValue? path_member (BezPath p, string name) {
            switch (name) {
                case "points":
                    return JsValue.native (name, (it, self, args) => {
                        var l = new Gee.ArrayList<JsValue> ();
                        foreach (var v in p.v) l.add (JsValue.from_doubles ({ v.x, v.y }));
                        return JsValue.array (l);
                    });
                case "inTangents":
                    return JsValue.native (name, (it, self, args) => {
                        var l = new Gee.ArrayList<JsValue> ();
                        foreach (var v in p.v) l.add (JsValue.from_doubles ({ v.in_x, v.in_y }));
                        return JsValue.array (l);
                    });
                case "outTangents":
                    return JsValue.native (name, (it, self, args) => {
                        var l = new Gee.ArrayList<JsValue> ();
                        foreach (var v in p.v) l.add (JsValue.from_doubles ({ v.out_x, v.out_y }));
                        return JsValue.array (l);
                    });
                case "isClosed":
                    return JsValue.native (name, (it, self, args) => JsValue.boolean (p.closed));
                case "pointOnPath":
                case "tangentOnPath":
                case "normalOnPath":
                    string which = name;
                    return JsValue.native (name, (it, self, args) => {
                        double pct = args.length > 0 ? it.to_number (it.prim (args[0])) : 0.5;
                        double len = p.length ();
                        double ang;
                        var pt = p.point_at_length (pct.clamp (0, 1) * len, out ang);
                        if (which == "pointOnPath") return JsValue.from_doubles ({ pt.x, pt.y });
                        if (which == "tangentOnPath") return JsValue.from_doubles ({ Math.cos (ang), Math.sin (ang) });
                        return JsValue.from_doubles ({ -Math.sin (ang), Math.cos (ang) });
                    });
            }
            return null;
        }

        public BezPath? to_path (JsValue v) {
            if (v.kind != JsKind.OBJECT) return null;
            var box = v.obj.host as PathBox;
            if (box != null) return box.path.copy ();
            var pb = v.obj.host as Property;
            if (pb != null && pb.kind == PropKind.PATH) {
                try {
                    var pv = v.obj.value_of ();
                    return to_path (pv);
                } catch (ExprError e) {
                    return null;
                }
            }
            return null;
        }

        public JsValue convert_value (Property p, double lt) {
            switch (p.kind) {
                case PropKind.PATH:
                    return path_value (p.path_at (lt));
                case PropKind.TEXT:
                    string? t = Expressions.evaluate_text (p, lt);
                    return JsValue.string_value (t ?? p.text_at (lt).text);
                default:
                    return JsValue.from_value (p.value_at (lt));
            }
        }

        public JsValue prop_value_at (Property p, double comp_t) {
            return convert_value (p, layer_time (p, comp_t));
        }

        public JsValue prop_velocity (Property p, double comp_t) {
            double lt = layer_time (p, comp_t);
            var l = p.owner_layer ();
            double stretch = l != null && l.stretch.abs () > 1e-9 ? l.stretch : 1;
            var v = p.velocity_at (lt);
            for (int i = 0; i < v.length; i++) v[i] /= stretch;
            return JsValue.from_value (v);
        }

        public double prop_speed (Property p, double comp_t) {
            var l = p.owner_layer ();
            double stretch = l != null && l.stretch.abs () > 1e-9 ? l.stretch : 1;
            return p.speed_at (layer_time (p, comp_t)) / stretch.abs ();
        }

        private JsValue key_object (Property p, int index) {
            var k = p.keys[index];
            var o = new JsObject ();
            o.class_name = "Key";
            o.put ("time", JsValue.number (comp_time_of (p, k.time)));
            o.put ("index", JsValue.number (index + 1));
            if (p.kind == PropKind.PATH) o.put ("value", path_value (k.path ?? new BezPath ()));
            else if (p.kind == PropKind.TEXT) o.put ("value", JsValue.string_value ((k.text ?? new TextDocument ()).text));
            else o.put ("value", JsValue.from_value (k.value));
            var vv = o.own ("value");
            o.value_of = () => vv;
            return JsValue.object (o);
        }

        private double[] raw_at (Property p, double lt) {
            return p.raw_value_at (lt);
        }

        private JsValue loop (Interpreter it, Property p, ExprContext? c, JsValue[] args, bool out_dir, bool by_duration) throws ExprError {
            double ct = c != null ? c.comp_time : 0;
            double lt = layer_time (p, ct);
            int n = p.keys.size;
            var cur_v = convert_value (p, lt);
            if (n < 2 || p.kind == PropKind.TEXT) return c != null && c.prop == p ? JsValue.from_value (c.pre) : cur_v;
            string type = args.length > 0 && args[0].kind != JsKind.UNDEFINED ? it.to_string (args[0]) : "cycle";
            double param = args.length > 1 ? it.to_number (it.prim (args[1])) : 0;
            var times = p.effective_times ();
            double first = times[0], last = times[n - 1];
            double a, b;
            if (out_dir) {
                b = last;
                if (by_duration) a = param > 0 ? double.max (first, last - param) : first;
                else a = param > 0 ? times[int.max (0, n - 1 - (int) param)] : first;
                if (lt <= b) return c != null && c.prop == p ? JsValue.from_value (c.pre) : cur_v;
            } else {
                a = first;
                if (by_duration) b = param > 0 ? double.min (last, first + param) : last;
                else b = param > 0 ? times[int.min (n - 1, (int) param)] : last;
                if (lt >= a) return c != null && c.prop == p ? JsValue.from_value (c.pre) : cur_v;
            }
            double span = b - a;
            if (span <= 1e-9) return cur_v;
            if (p.kind == PropKind.PATH) {
                double tt = a + Math.fmod (Math.fmod (lt - a, span) + span, span);
                return path_value (p.raw_path_at (tt));
            }
            var va = raw_at (p, a);
            var vb = raw_at (p, b);
            double[] result;
            switch (type) {
                case "pingpong":
                    double d = out_dir ? lt - b : a - lt;
                    int cycles = (int) Math.floor (d / span);
                    double frac = Math.fmod (d, span);
                    double tt;
                    if (out_dir) tt = cycles % 2 == 0 ? b - frac : a + frac;
                    else tt = cycles % 2 == 0 ? a + frac : b - frac;
                    result = raw_at (p, tt);
                    break;
                case "offset":
                    double rel = lt - a;
                    double cyc = Math.floor (rel / span);
                    double tt2 = a + (rel - cyc * span);
                    var base_v = raw_at (p, tt2);
                    result = new double[base_v.length];
                    for (int i = 0; i < base_v.length; i++) result[i] = base_v[i] + (vb[i] - va[i]) * cyc;
                    break;
                case "continue":
                    double edge = out_dir ? b : a;
                    var ev = raw_at (p, edge);
                    double dt = 1e-3;
                    var e2 = raw_at (p, out_dir ? edge - dt : edge + dt);
                    result = new double[ev.length];
                    for (int i = 0; i < ev.length; i++) {
                        double vel = out_dir ? (ev[i] - e2[i]) / dt : (e2[i] - ev[i]) / dt;
                        result[i] = ev[i] + vel * (lt - edge);
                    }
                    break;
                default:
                    double tt3 = a + Math.fmod (Math.fmod (lt - a, span) + span, span);
                    result = raw_at (p, tt3);
                    break;
            }
            return JsValue.from_value (result);
        }

        private JsValue wiggle (Interpreter it, Property p, ExprContext? c, JsValue[] args) throws ExprError {
            double freq = args.length > 0 ? it.to_number (it.prim (args[0])) : 1;
            var ampv = args.length > 1 ? it.prim (args[1]) : JsValue.number (0);
            int octaves = args.length > 2 && args[2].kind != JsKind.UNDEFINED ? (int) it.to_number (it.prim (args[2])) : 1;
            double mult = args.length > 3 && args[3].kind != JsKind.UNDEFINED ? it.to_number (it.prim (args[3])) : 0.5;
            double ct = args.length > 4 && args[4].kind != JsKind.UNDEFINED ? it.to_number (it.prim (args[4])) : (c != null ? c.comp_time : 0);
            double[] base_v;
            if (c != null && c.prop == p && args.length <= 4) base_v = c.pre;
            else base_v = p.raw_value_at (layer_time (p, ct));
            double[] amp = ampv.kind == JsKind.ARRAY ? it.to_doubles (ampv) : new double[] { it.to_number (ampv) };
            uint seed = 0;
            string path = (p.owner_layer () != null ? p.owner_layer ().id : "") + "/" + p.path_string ();
            for (int i = 0; i < path.length; i++) seed = seed * 31 + (uint8) path[i];
            var r = new double[base_v.length];
            int dims = p.kind == PropKind.COLOR ? int.min (3, base_v.length) : base_v.length;
            for (int i = 0; i < base_v.length; i++) {
                if (i >= dims) {
                    r[i] = base_v[i];
                    continue;
                }
                double a = amp[int.min (i, amp.length - 1)];
                r[i] = base_v[i] + Noise.fractal1 (ct * freq, octaves, mult, (int) (seed & 0xffff) + i * 1013) * a;
            }
            return JsValue.from_value (r);
        }

        public JsValue prop_object (Property p, ExprContext? ctx) {
            var o = new JsObject ();
            o.class_name = "Property";
            o.host = p;
            o.value_of = () => {
                var c = Expressions.current () ?? ctx;
                if (c != null && c.prop == p) {
                    if (p.kind == PropKind.PATH) return path_value (c.pre_path ?? p.raw_path_at (layer_time (p, c.comp_time)));
                    if (p.kind != PropKind.TEXT) return JsValue.from_value (c.pre);
                }
                return prop_value_at (p, c != null ? c.comp_time : 0);
            };
            o.getter = (name) => {
                var c = Expressions.current () ?? ctx;
                double ct = c != null ? c.comp_time : 0;
                switch (name) {
                    case "value": return o.value_of ();
                    case "name": return JsValue.string_value (p.name);
                    case "matchName": return JsValue.string_value (p.key);
                    case "numKeys": return JsValue.number (p.keys.size);
                    case "velocity": return prop_velocity (p, ct);
                    case "speed": return JsValue.number (prop_speed (p, ct));
                    case "propertyIndex": return JsValue.number (p.parent != null ? p.parent.children.index_of (p) + 1 : 1);
                    case "expression": return JsValue.string_value (p.expression);
                    case "expressionEnabled": return JsValue.boolean (p.expression_enabled);
                    case "expressionError": return JsValue.string_value (p.expression_error);
                    case "isTimeVarying": return JsValue.boolean (p.varies ());
                    case "canVaryOverTime": return JsValue.boolean (p.animatable);
                    case "valueAtTime":
                        return JsValue.native (name, (it, self, args) => prop_value_at (p, args.length > 0 ? it.to_number (it.prim (args[0])) : ct));
                    case "velocityAtTime":
                        return JsValue.native (name, (it, self, args) => prop_velocity (p, args.length > 0 ? it.to_number (it.prim (args[0])) : ct));
                    case "speedAtTime":
                        return JsValue.native (name, (it, self, args) => JsValue.number (prop_speed (p, args.length > 0 ? it.to_number (it.prim (args[0])) : ct)));
                    case "key":
                        return JsValue.native (name, (it, self, args) => {
                            int i = args.length > 0 ? (int) it.to_number (it.prim (args[0])) - 1 : -1;
                            if (i < 0 || i >= p.keys.size) throw new ExprError.RUNTIME ("Key index %d out of range", i + 1);
                            return key_object (p, i);
                        });
                    case "nearestKey":
                        return JsValue.native (name, (it, self, args) => {
                            if (p.keys.size == 0) throw new ExprError.RUNTIME ("The property has no keyframes");
                            double t = args.length > 0 ? it.to_number (it.prim (args[0])) : ct;
                            double lt = layer_time (p, t);
                            int best = 0;
                            for (int i = 1; i < p.keys.size; i++) if ((p.keys[i].time - lt).abs () < (p.keys[best].time - lt).abs ()) best = i;
                            return key_object (p, best);
                        });
                    case "wiggle":
                        return JsValue.native (name, (it, self, args) => wiggle (it, p, Expressions.current () ?? ctx, args));
                    case "temporalWiggle":
                        return JsValue.native (name, (it, self, args) => {
                            double freq = args.length > 0 ? it.to_number (it.prim (args[0])) : 1;
                            double amp = args.length > 1 ? it.to_number (it.prim (args[1])) : 0;
                            double t = args.length > 4 ? it.to_number (it.prim (args[4])) : ct;
                            double off = Noise.fractal1 (t * freq, 1, 0.5, 77) * amp;
                            return prop_value_at (p, t + off);
                        });
                    case "smooth":
                        return JsValue.native (name, (it, self, args) => {
                            double width = args.length > 0 ? it.to_number (it.prim (args[0])) : 0.2;
                            int samples = args.length > 1 ? (int) it.to_number (it.prim (args[1])) : 5;
                            double t = args.length > 2 ? it.to_number (it.prim (args[2])) : ct;
                            samples = samples.clamp (1, 100);
                            double[]? acc = null;
                            for (int i = 0; i < samples; i++) {
                                double tt = samples == 1 ? t : t - width / 2 + width * i / (samples - 1);
                                var v = p.raw_value_at (layer_time (p, tt));
                                if (acc == null) acc = new double[v.length];
                                for (int k = 0; k < v.length; k++) acc[k] += v[k] / samples;
                            }
                            return JsValue.from_value (acc);
                        });
                    case "loopOut":
                        return JsValue.native (name, (it, self, args) => loop (it, p, Expressions.current () ?? ctx, args, true, false));
                    case "loopIn":
                        return JsValue.native (name, (it, self, args) => loop (it, p, Expressions.current () ?? ctx, args, false, false));
                    case "loopOutDuration":
                        return JsValue.native (name, (it, self, args) => loop (it, p, Expressions.current () ?? ctx, args, true, true));
                    case "loopInDuration":
                        return JsValue.native (name, (it, self, args) => loop (it, p, Expressions.current () ?? ctx, args, false, true));
                    case "points":
                    case "inTangents":
                    case "outTangents":
                    case "isClosed":
                    case "pointOnPath":
                    case "tangentOnPath":
                    case "normalOnPath":
                        string which = name;
                        return JsValue.native (name, (it, self, args) => {
                            double t = ct;
                            JsValue[] rest = args;
                            if ((which == "points" || which == "inTangents" || which == "outTangents") && args.length > 0) t = it.to_number (it.prim (args[0]));
                            if ((which == "pointOnPath" || which == "tangentOnPath" || which == "normalOnPath") && args.length > 1) t = it.to_number (it.prim (args[1]));
                            BezPath path;
                            if (p.kind != PropKind.PATH) throw new ExprError.RUNTIME ("%s needs a path property", which);
                            var c2 = Expressions.current ();
                            if (c2 != null && c2.prop == p && (t - c2.comp_time).abs () < 1e-9) path = c2.pre_path ?? p.raw_path_at (layer_time (p, t));
                            else path = p.path_at (layer_time (p, t));
                            var fv = path_member (path, which);
                            return it.call (fv, JsValue.undefined (), rest);
                        });
                    case "createPath":
                        return Expressions.interpreter ().globals.vars["createPath"];
                }
                if (c != null && c.mutable) return ScriptHost.prop_member (p, name, c);
                return null;
            };
            o.setter = (name, v) => {
                var c = Expressions.current () ?? ctx;
                if (c == null || !c.mutable) return false;
                return ScriptHost.prop_set (p, name, v);
            };
            return JsValue.object (o);
        }

        public JsValue group_object (PropGroup g, ExprContext? ctx) {
            var o = new JsObject ();
            o.class_name = "PropertyGroup";
            o.host = g;
            o.call = (it, self, args) => {
                if (args.length == 0) throw new ExprError.RUNTIME ("Missing property name");
                var ch = child_by_arg (it, g, args[0]);
                if (ch == null) throw new ExprError.RUNTIME ("Property %s does not exist in %s", it.to_string (args[0]), g.name);
                return node_object (ch, ctx);
            };
            o.getter = (name) => {
                switch (name) {
                    case "name": return JsValue.string_value (g.name);
                    case "matchName": return JsValue.string_value (g.type);
                    case "numProperties": return JsValue.number (g.children.size);
                    case "enabled":
                    case "active": return JsValue.boolean (g.enabled);
                    case "propertyIndex": return JsValue.number (g.parent != null ? g.parent.children.index_of (g) + 1 : 1);
                    case "property":
                        return JsValue.native (name, (it, self, args) => {
                            var ch = args.length > 0 ? child_by_arg (it, g, args[0]) : null;
                            if (ch == null) throw new ExprError.RUNTIME ("Property does not exist");
                            return node_object (ch, ctx);
                        });
                    case "content":
                        var contents = g.group ("contents") ?? (g.type == "contents" || g.type == "shape.contents" ? g : null);
                        if (contents != null) return group_object (contents, ctx);
                        break;
                    case "animator":
                        var an = g.group ("animators") ?? (g.type == "text.animators" ? g : null);
                        if (an != null) return group_object (an, ctx);
                        break;
                    case "selector":
                        var sel = g.group ("selectors");
                        if (sel != null) return group_object (sel, ctx);
                        break;
                }
                var ch = resolve_child (g, name);
                if (ch != null) return node_object (ch, ctx);
                if (g.type == "shape.group" || g.type == "text.animator") {
                    var inner = g.group ("contents") ?? g.group ("properties");
                    if (inner != null) {
                        var ich = resolve_child (inner, name);
                        if (ich != null) return node_object (ich, ctx);
                    }
                }
                var c = Expressions.current () ?? ctx;
                if (c != null && c.mutable) return ScriptHost.group_member (g, name, c);
                return null;
            };
            o.setter = (name, v) => {
                var c = Expressions.current () ?? ctx;
                if (c == null || !c.mutable) return false;
                return ScriptHost.group_set (g, name, v);
            };
            return JsValue.object (o);
        }

        public JsValue node_object (PropNode n, ExprContext? ctx) {
            if (n is Property) return prop_object ((Property) n, ctx);
            return group_object ((PropGroup) n, ctx);
        }

        private double[] point_arg (Interpreter it, JsValue[] args) throws ExprError {
            if (args.length == 0) throw new ExprError.RUNTIME ("Missing point");
            var d = it.to_doubles (args[0]);
            if (d == null) throw new ExprError.RUNTIME ("Expected a point");
            return d;
        }

        public JsValue source_rect (Layer l, double ct) {
            double lt = l.layer_time (ct);
            double x = 0, y = 0, w = l.solid_width, h = l.solid_height;
            if (l.kind == LayerKind.SHAPE && l.contents != null) {
                var sr = new ShapeRenderer (lt);
                var scene = sr.build (l.contents, new Mat4 ());
                var b = scene.bounds ();
                if (!b.is_empty ()) {
                    x = b.x;
                    y = b.y;
                    w = b.w;
                    h = b.h;
                } else {
                    w = h = 0;
                }
            } else if (l.kind == LayerKind.TEXT && l.text_group != null) {
                var sp = l.text_group.prop ("source-text");
                if (sp != null) {
                    var doc = sp.text_at (lt);
                    var tl = TextRenderer.layout_glyphs (doc);
                    var r = Singularity.Vector.Rect.empty ();
                    bool any = false;
                    foreach (var gl in tl.glyphs) {
                        foreach (var p in gl.paths) {
                            var cp = p.copy ();
                            cp.transform (Mat4.translation (gl.x, gl.y, 0));
                            var pr = Singularity.Vector.Rect.empty ();
                            cp.bounds (ref pr);
                            if (pr.is_empty ()) continue;
                            r = any ? r.union (pr) : pr;
                            any = true;
                        }
                    }
                    if (any) {
                        x = r.x;
                        y = r.y;
                        w = r.w;
                        h = r.h;
                    } else {
                        w = h = 0;
                    }
                }
            } else if (l.kind == LayerKind.PRECOMP && l.comp != null && l.comp.project != null) {
                var nc = l.comp.project.comp_by_id (l.source_id);
                if (nc != null) {
                    w = nc.width;
                    h = nc.height;
                }
            }
            var o = new JsObject ();
            o.put ("top", JsValue.number (y));
            o.put ("left", JsValue.number (x));
            o.put ("width", JsValue.number (w));
            o.put ("height", JsValue.number (h));
            return JsValue.object (o);
        }

        public JsValue layer_object (Layer l, ExprContext? ctx) {
            var o = new JsObject ();
            o.class_name = "Layer";
            o.host = l;
            o.getter = (name) => {
                var c = Expressions.current () ?? ctx;
                double ct = c != null ? c.comp_time : 0;
                switch (name) {
                    case "name": return JsValue.string_value (l.name);
                    case "index": return JsValue.number (l.comp != null ? l.comp.layers.index_of (l) + 1 : 1);
                    case "inPoint": return JsValue.number (l.in_point);
                    case "outPoint": return JsValue.number (l.out_point);
                    case "startTime": return JsValue.number (l.start_time);
                    case "stretch": return JsValue.number (l.stretch * 100);
                    case "enabled": return JsValue.boolean (l.video);
                    case "active": return JsValue.boolean (l.video && l.active_at (ct));
                    case "hasVideo": return JsValue.boolean (l.kind.is_visual () || l.kind == LayerKind.SOLID);
                    case "hasAudio": return JsValue.boolean (l.kind == LayerKind.AUDIO || l.kind == LayerKind.FOOTAGE);
                    case "threeDLayer": return JsValue.boolean (l.three_d);
                    case "width":
                        if (l.kind == LayerKind.PRECOMP && l.comp != null && l.comp.project != null) {
                            var nc = l.comp.project.comp_by_id (l.source_id);
                            if (nc != null) return JsValue.number (nc.width);
                        }
                        return JsValue.number (l.solid_width);
                    case "height":
                        if (l.kind == LayerKind.PRECOMP && l.comp != null && l.comp.project != null) {
                            var nc = l.comp.project.comp_by_id (l.source_id);
                            if (nc != null) return JsValue.number (nc.height);
                        }
                        return JsValue.number (l.solid_height);
                    case "hasParent": return JsValue.boolean (l.parent_layer () != null);
                    case "parent":
                        var p = l.parent_layer ();
                        return p != null ? layer_object (p, ctx) : JsValue.null_value ();
                    case "comment": return JsValue.string_value (l.comment);
                    case "label": return JsValue.number (l.label);
                    case "transform": return group_object (l.transform, ctx);
                    case "source":
                        if (l.kind == LayerKind.PRECOMP && l.comp != null && l.comp.project != null) {
                            var nc = l.comp.project.comp_by_id (l.source_id);
                            if (nc != null) return comp_object (nc, ctx);
                        }
                        return JsValue.null_value ();
                    case "text":
                        var tg = l.text_group;
                        return tg != null ? group_object (tg, ctx) : JsValue.null_value ();
                    case "effect":
                        var fx = l.effects ?? new PropGroup ("effects", "effects", "Effects");
                        var fo = group_object (fx, ctx);
                        return fo;
                    case "mask":
                        var mg = l.masks ?? new PropGroup ("masks", "masks", "Masks");
                        return group_object (mg, ctx);
                    case "content":
                        var cg = l.contents ?? new PropGroup ("contents", "contents", "Contents");
                        return group_object (cg, ctx);
                    case "toComp":
                    case "toWorld":
                    case "fromComp":
                    case "fromWorld":
                    case "toCompVec":
                    case "fromCompVec":
                        string which = name;
                        return JsValue.native (name, (it, self, args) => {
                            var pt = point_arg (it, args);
                            double t = args.length > 1 ? it.to_number (it.prim (args[1])) : ct;
                            var m = l.world_matrix (t);
                            Vec3 r;
                            var v = Vec3 (pt[0], pt.length > 1 ? pt[1] : 0, pt.length > 2 ? pt[2] : 0);
                            if (which == "toComp" || which == "toWorld") r = m.transform_point (v);
                            else if (which == "toCompVec") r = m.transform_vector (v);
                            else {
                                var inv = m.inverted ();
                                if (inv == null) throw new ExprError.RUNTIME ("The layer transform cannot be inverted");
                                r = which == "fromCompVec" ? inv.transform_vector (v) : inv.transform_point (v);
                            }
                            if (pt.length >= 3 || which == "toWorld") return JsValue.from_doubles ({ r.x, r.y, r.z });
                            return JsValue.from_doubles ({ r.x, r.y });
                        });
                    case "sourceRectAtTime":
                        return JsValue.native (name, (it, self, args) => source_rect (l, args.length > 0 && args[0].kind != JsKind.UNDEFINED ? it.to_number (it.prim (args[0])) : ct));
                    case "sourceTime":
                        return JsValue.native (name, (it, self, args) => JsValue.number (l.source_time (args.length > 0 ? it.to_number (it.prim (args[0])) : ct)));
                }
                var ch = ExprHost.resolve_child (l.root, name);
                if (ch != null) return node_object (ch, ctx);
                if (c != null && c.mutable) return ScriptHost.layer_member (l, name, c);
                return null;
            };
            o.setter = (name, v) => {
                var c = Expressions.current () ?? ctx;
                if (c == null || !c.mutable) return false;
                return ScriptHost.layer_set (l, name, v);
            };
            return JsValue.object (o);
        }

        public JsValue comp_object (Composition comp, ExprContext? ctx) {
            var o = new JsObject ();
            o.class_name = "Comp";
            o.host = comp;
            o.getter = (name) => {
                switch (name) {
                    case "name": return JsValue.string_value (comp.name);
                    case "width": return JsValue.number (comp.width);
                    case "height": return JsValue.number (comp.height);
                    case "duration": return JsValue.number (comp.duration);
                    case "frameDuration": return JsValue.number (1.0 / comp.fps);
                    case "frameRate": return JsValue.number (comp.fps);
                    case "numLayers": return JsValue.number (comp.layers.size);
                    case "pixelAspect": return JsValue.number (comp.pixel_aspect);
                    case "displayStartTime": return JsValue.number (comp.start_timecode);
                    case "bgColor": return JsValue.from_doubles (comp.background);
                    case "shutterAngle": return JsValue.number (comp.shutter_angle);
                    case "shutterPhase": return JsValue.number (comp.shutter_phase);
                    case "activeCamera":
                        var c = Expressions.current () ?? ctx;
                        var cam = comp.active_camera (c != null ? c.comp_time : 0);
                        return cam != null ? layer_object (cam, ctx) : JsValue.null_value ();
                    case "layer":
                        return JsValue.native (name, (it, self, args) => {
                            if (args.length == 0) throw new ExprError.RUNTIME ("layer needs a name or index");
                            var a = it.prim (args[0]);
                            Layer? l = null;
                            if (a.kind == JsKind.NUMBER) {
                                int i = (int) a.num - 1;
                                if (i >= 0 && i < comp.layers.size) l = comp.layers[i];
                            } else if (a.kind == JsKind.OBJECT && a.obj.host is Layer) {
                                var base_l = (Layer) a.obj.host;
                                int rel = args.length > 1 ? (int) it.to_number (it.prim (args[1])) : 0;
                                int i = comp.layers.index_of (base_l) + rel;
                                if (i >= 0 && i < comp.layers.size) l = comp.layers[i];
                            } else {
                                l = comp.layer_by_name (it.to_string (a));
                            }
                            if (l == null) throw new ExprError.RUNTIME ("Layer %s does not exist", it.to_string (a));
                            return layer_object (l, ctx);
                        });
                    case "marker":
                        var mo = new JsObject ();
                        mo.put ("numKeys", JsValue.number (comp.markers.size));
                        mo.put ("key", JsValue.native ("key", (it, self, args) => {
                            var a = args.length > 0 ? it.prim (args[0]) : JsValue.number (1);
                            Marker? m = null;
                            if (a.kind == JsKind.NUMBER) {
                                int i = (int) a.num - 1;
                                if (i >= 0 && i < comp.markers.size) m = comp.markers[i];
                            } else {
                                foreach (var mk in comp.markers) if (mk.comment == it.to_string (a)) m = mk;
                            }
                            if (m == null) throw new ExprError.RUNTIME ("Marker does not exist");
                            var k = new JsObject ();
                            k.put ("time", JsValue.number (m.time));
                            k.put ("duration", JsValue.number (m.duration));
                            k.put ("comment", JsValue.string_value (m.comment));
                            return JsValue.object (k);
                        }));
                        return JsValue.object (mo);
                }
                var c = Expressions.current () ?? ctx;
                if (c != null && c.mutable) return ScriptHost.comp_member (comp, name, c);
                return null;
            };
            o.setter = (name, v) => {
                var c = Expressions.current () ?? ctx;
                if (c == null || !c.mutable) return false;
                return ScriptHost.comp_set (comp, name, v);
            };
            return JsValue.object (o);
        }
    }
}
