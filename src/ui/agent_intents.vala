namespace Singularity.Apps.Keyframe {

    internal class KeyframeIntents : Object {
        private const string[] LAYERS = { "solid", "text", "shape", "null", "adjustment", "camera", "footage" };

        private static string text (Json.Object args, string key) {
            return args.has_member (key) ? args.get_string_member (key) : "";
        }

        private static double num (Json.Object args, string key, double fallback) {
            return args.has_member (key) ? args.get_double_member (key) : fallback;
        }

        private static Json.Node obj (Json.Object o) {
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (o);
            return node;
        }

        private static string list (string[] values) {
            var b = new StringBuilder ("[");
            for (int i = 0; i < values.length; i++) {
                if (i > 0) b.append (",");
                b.append ("\"").append (values[i]).append ("\"");
            }
            return b.append ("]").str;
        }

        private static double round (double v) {
            return Math.round (v * 1000) / 1000.0;
        }

        private static Json.Array numbers (double[] v) {
            var a = new Json.Array ();
            foreach (var d in v) a.add_double_element (round (d));
            return a;
        }

        private static double[] read_numbers (Json.Object args, string key) throws Error {
            var node = args.get_member (key);
            if (node.get_node_type () == Json.NodeType.VALUE) return { node.get_double () };
            if (node.get_node_type () != Json.NodeType.ARRAY) throw new IOError.INVALID_ARGUMENT ("%s must be a number or an array of numbers", key);
            double[] r = {};
            foreach (var e in node.get_array ().get_elements ()) r += e.get_double ();
            return r;
        }

        private static Composition need_comp (KeyframeWindow w) throws Error {
            if (w.doc.comp == null) throw new IOError.FAILED ("no composition is open; create one with keyframe_new");
            return w.doc.comp;
        }

        private static Layer need_layer (KeyframeWindow w, Json.Object args) throws Error {
            var comp = need_comp (w);
            if (!args.has_member ("layer")) {
                var p = w.doc.primary ();
                if (p == null) throw new IOError.INVALID_ARGUMENT ("name a layer by its 1-based index or its name");
                return p;
            }
            var node = args.get_member ("layer");
            if (node.get_value_type () == typeof (string)) {
                var l = comp.layer_by_name (node.get_string ());
                if (l == null) throw new IOError.NOT_FOUND ("no layer named %s", node.get_string ());
                return l;
            }
            int n = (int) node.get_int () - 1;
            if (n < 0 || n >= comp.layers.size) throw new IOError.NOT_FOUND ("layer %d does not exist; the composition has %d", n + 1, comp.layers.size);
            return comp.layers[n];
        }

        private static Json.Object layer_info (Composition comp, Layer l) {
            var o = new Json.Object ();
            o.set_int_member ("index", comp.index_of (l) + 1);
            o.set_string_member ("name", l.name);
            o.set_string_member ("kind", l.kind.to_id ());
            o.set_double_member ("in", round (l.in_point));
            o.set_double_member ("out", round (l.out_point));
            o.set_boolean_member ("visible", l.video);
            var fx = new Json.Array ();
            var g = l.effects;
            if (g != null) foreach (var c in g.children) fx.add_string_element (EffectRegistry.id_of ((PropGroup) c));
            o.set_array_member ("effects", fx);
            int animated = 0;
            foreach (var p in l.all_props ()) if (p.is_animated ()) animated++;
            o.set_int_member ("animated_properties", animated);
            return o;
        }

        private static Json.Node outline (KeyframeWindow w) {
            var o = new Json.Object ();
            var p = w.doc.project;
            o.set_string_member ("path", p.path);
            o.set_boolean_member ("modified", p.modified);
            o.set_boolean_member ("can_undo", w.doc.can_undo ());
            o.set_boolean_member ("can_redo", w.doc.can_redo ());
            var comps = new Json.Array ();
            foreach (var c in p.compositions ()) {
                var co = new Json.Object ();
                co.set_string_member ("name", c.name);
                co.set_int_member ("width", c.width);
                co.set_int_member ("height", c.height);
                co.set_double_member ("fps", c.fps);
                co.set_double_member ("duration", c.duration);
                co.set_int_member ("layers", c.layers.size);
                comps.add_object_element (co);
            }
            o.set_array_member ("compositions", comps);
            var footage = new Json.Array ();
            foreach (var it in p.items) {
                var f = it as Footage;
                if (f != null) footage.add_string_element (f.path);
            }
            o.set_array_member ("footage", footage);
            var c = w.doc.comp;
            if (c != null) {
                var co = new Json.Object ();
                co.set_string_member ("name", c.name);
                co.set_double_member ("time", round (w.doc.time));
                var layers = new Json.Array ();
                foreach (var l in c.layers) layers.add_object_element (layer_info (c, l));
                co.set_array_member ("layers", layers);
                var marks = new Json.Array ();
                foreach (var m in c.markers) {
                    var mo = new Json.Object ();
                    mo.set_double_member ("time", round (m.time));
                    mo.set_string_member ("comment", m.comment);
                    marks.add_object_element (mo);
                }
                co.set_array_member ("markers", marks);
                var sel = w.doc.primary ();
                if (sel != null) co.set_int_member ("selected", c.index_of (sel) + 1);
                o.set_object_member ("active", co);
            }
            var queue = new Json.Array ();
            foreach (var item in p.render_queue) {
                var qo = new Json.Object ();
                var qc = p.comp_by_id (item.comp_id);
                qo.set_string_member ("composition", qc != null ? qc.name : "");
                qo.set_string_member ("status", item.status.to_id ());
                if (item.outputs.size > 0) {
                    qo.set_string_member ("format", item.outputs[0].format);
                    qo.set_string_member ("path", item.outputs[0].path);
                }
                if (item.error != "") qo.set_string_member ("error", item.error);
                queue.add_object_element (qo);
            }
            o.set_array_member ("render_queue", queue);
            return obj (o);
        }

        private static Json.Node property_info (Layer l, Property p, double comp_t) {
            var o = new Json.Object ();
            o.set_string_member ("path", p.path_string ());
            o.set_string_member ("kind", p.kind.to_id ());
            double lt = l.layer_time (comp_t);
            if (p.kind == PropKind.TEXT) o.set_string_member ("text", p.text_at (lt).text);
            else if (p.kind != PropKind.PATH) o.set_array_member ("value", numbers (p.value_at (lt)));
            var keys = new Json.Array ();
            foreach (var k in p.keys) {
                var ko = new Json.Object ();
                ko.set_double_member ("time", round (l.comp_time (k.time)));
                if (p.kind != PropKind.TEXT && p.kind != PropKind.PATH) ko.set_array_member ("value", numbers (k.value));
                keys.add_object_element (ko);
            }
            o.set_array_member ("keys", keys);
            if (p.expression != "") o.set_string_member ("expression", p.expression);
            return obj (o);
        }

        private static void collect_paths (PropGroup g, Json.Array into) {
            foreach (var c in g.children) {
                var p = c as Property;
                if (p != null) into.add_string_element (p.path_string ());
                var sub = c as PropGroup;
                if (sub != null) collect_paths (sub, into);
            }
        }

        private static Json.Array property_paths (PropGroup g) {
            var r = new Json.Array ();
            collect_paths (g, r);
            return r;
        }

        private static Json.Node new_thing (KeyframeWindow w, Json.Object args) throws Error {
            string what = text (args, "what");
            int width = (int) num (args, "width", 1920), height = (int) num (args, "height", 1080);
            double fps = num (args, "fps", 30), duration = num (args, "duration", 10);
            if (width < 16 || height < 16 || width > 16384 || height > 16384) throw new IOError.INVALID_ARGUMENT ("width and height must be between 16 and 16384");
            if (fps <= 0 || fps > 240 || duration <= 0) throw new IOError.INVALID_ARGUMENT ("fps must be in (0, 240] and duration positive");
            if (what == "project") {
                if (w.doc.project.modified && !(args.has_member ("discard") && args.get_boolean_member ("discard")))
                    throw new IOError.FAILED ("the open project has unsaved changes; save it first or pass discard");
                w.new_project ();
                var c = need_comp (w);
                c.width = width;
                c.height = height;
                c.fps = fps;
                c.duration = duration;
                if (args.has_member ("name")) c.name = text (args, "name");
                w.doc.project.modified = false;
                w.doc.open_comp (c);
            } else if (what == "composition") {
                string name = text (args, "name");
                if (name == "") name = "Composition %d".printf (w.doc.project.compositions ().size + 1);
                var c = new Composition (name, width, height, fps, duration);
                w.doc.edit ("New Composition", () => w.doc.project.add_item (c));
                w.doc.open_comp (c);
            } else {
                throw new IOError.INVALID_ARGUMENT ("what must be project or composition");
            }
            return outline (w);
        }

        private static Json.Node open (KeyframeWindow w, Json.Object args) throws Error {
            string path = text (args, "path");
            if (args.has_member ("composition")) {
                var c = w.doc.project.comp_by_name (text (args, "composition"));
                if (c == null) throw new IOError.NOT_FOUND ("no composition named %s", text (args, "composition"));
                w.doc.open_comp (c);
                return outline (w);
            }
            if (path == "" || !FileUtils.test (path, FileTest.IS_REGULAR)) throw new IOError.NOT_FOUND ("no project file at %s", path);
            if (w.doc.project.modified && !(args.has_member ("discard") && args.get_boolean_member ("discard")))
                throw new IOError.FAILED ("the open project has unsaved changes; save it first or pass discard");
            w.open_project (File.new_for_path (path));
            if (w.doc.project.path != path) throw new IOError.FAILED ("could not open %s", path);
            return outline (w);
        }

        private static Json.Node layer (KeyframeWindow w, Json.Object args) throws Error {
            var comp = need_comp (w);
            string action = text (args, "action");
            switch (action) {
                case "add":
                    string kind = text (args, "kind");
                    string name = text (args, "name");
                    if (kind == "footage") {
                        string path = text (args, "path");
                        if (!FileUtils.test (path, FileTest.IS_REGULAR)) throw new IOError.NOT_FOUND ("no file at %s", path);
                        Footage? f = null;
                        foreach (var it in w.doc.project.items) {
                            var ff = it as Footage;
                            if (ff != null && ff.path == path) f = ff;
                        }
                        if (f == null) {
                            f = MediaPool.probe (path);
                            var nf = f;
                            w.doc.edit ("Import", () => w.doc.project.add_item (nf));
                        }
                        int before = comp.layers.size;
                        w.add_footage_layer (f);
                        if (comp.layers.size == before) throw new IOError.FAILED ("could not place %s", path);
                        if (name != "") comp.layers[0].name = name;
                        return obj (layer_info (comp, comp.layers[0]));
                    }
                    Layer l;
                    switch (kind) {
                        case "solid":
                            double[] color = args.has_member ("color") ? read_numbers (args, "color") : new double[] { 0.5, 0.5, 0.5, 1 };
                            if (color.length == 3) color += 1;
                            if (color.length != 4) throw new IOError.INVALID_ARGUMENT ("color is [r, g, b] or [r, g, b, a] in 0..1");
                            l = Factory.solid (comp, name != "" ? name : "Solid", color);
                            break;
                        case "text":
                            l = Factory.text_layer (comp, args.has_member ("text") ? text (args, "text") : (name != "" ? name : "Text"));
                            if (args.has_member ("size")) l.text_group.prop ("source-text").text.size = num (args, "size", 72);
                            break;
                        case "shape":
                            l = Factory.shape_layer (comp, name);
                            var grp = Factory.shape_group ("Shape");
                            string shape = text (args, "shape");
                            double sw = num (args, "shape_width", 200), sh = num (args, "shape_height", 200);
                            if (shape == "" || shape == "rect") grp.group ("contents").add<PropGroup> (Factory.rect (sw, sh, num (args, "roundness", 0)));
                            else if (shape == "ellipse") grp.group ("contents").add<PropGroup> (Factory.ellipse (sw, sh));
                            else if (shape == "star") grp.group ("contents").add<PropGroup> (Factory.star (false, (int) num (args, "points", 5), sw / 2, sw / 4));
                            else throw new IOError.INVALID_ARGUMENT ("shape must be rect, ellipse or star");
                            double[] fill = args.has_member ("color") ? read_numbers (args, "color") : new double[] { 1, 1, 1, 1 };
                            if (fill.length == 3) fill += 1;
                            grp.group ("contents").add<PropGroup> (Factory.fill (fill));
                            l.contents.add<PropGroup> (grp);
                            break;
                        case "null":
                            l = Factory.null_layer (comp);
                            break;
                        case "adjustment":
                            l = Factory.adjustment (comp);
                            break;
                        case "camera":
                            l = Factory.camera (comp, num (args, "focal_mm", 50));
                            break;
                        default:
                            throw new IOError.INVALID_ARGUMENT ("kind must be one of %s", string.joinv (", ", LAYERS));
                    }
                    if (name != "" && kind != "solid" && kind != "shape") l.name = name;
                    l.name = comp.unique_layer_name (l.name);
                    l.in_point = num (args, "in", 0);
                    l.out_point = num (args, "out", comp.duration);
                    var added = l;
                    w.doc.edit ("Add Layer", () => {
                        comp.add_layer (added, 0);
                        w.doc.select_layer (added);
                    });
                    return obj (layer_info (comp, l));
                case "delete":
                    var d = need_layer (w, args);
                    w.doc.edit ("Delete Layer", () => comp.remove_layer (d));
                    return outline (w);
                case "select":
                    var s = need_layer (w, args);
                    w.doc.select_layer (s);
                    return obj (layer_info (comp, s));
                case "update":
                    var u = need_layer (w, args);
                    double new_in = num (args, "in", u.in_point), new_out = num (args, "out", u.out_point);
                    if (new_out <= new_in) throw new IOError.INVALID_ARGUMENT ("out must come after in");
                    string rename = text (args, "name");
                    int move = args.has_member ("index") ? (int) args.get_int_member ("index") - 1 : -1;
                    if (move >= comp.layers.size) throw new IOError.INVALID_ARGUMENT ("index must be between 1 and %d", comp.layers.size);
                    w.doc.edit ("Change Layer", () => {
                        u.in_point = new_in;
                        u.out_point = new_out;
                        if (rename != "") u.name = rename;
                        if (args.has_member ("visible")) u.video = args.get_boolean_member ("visible");
                        if (move >= 0) comp.move_layer (u, move);
                        u.mark_changed ();
                    });
                    return obj (layer_info (comp, u));
                default:
                    throw new IOError.INVALID_ARGUMENT ("action must be add, delete, select or update");
            }
        }

        private static Json.Node property (KeyframeWindow w, Json.Object args) throws Error {
            var l = need_layer (w, args);
            string path = text (args, "path");
            if (path == "") {
                var o = new Json.Object ();
                o.set_array_member ("properties", property_paths (l.root));
                return obj (o);
            }
            var p = l.root.find (path) as Property;
            if (p == null) throw new IOError.NOT_FOUND ("layer %s has no property %s; omit path to list them", l.name, path);
            double t = num (args, "time", w.doc.time);
            double lt = l.layer_time (t);
            bool key = args.has_member ("key") && args.get_boolean_member ("key");
            if (args.has_member ("clear_keys") && args.get_boolean_member ("clear_keys")) {
                w.doc.edit ("Clear Keyframes", () => p.clear_keys ());
            }
            if (args.has_member ("expression")) {
                string ex = text (args, "expression");
                w.doc.edit ("Expression", () => {
                    p.expression = ex;
                    p.touch ();
                });
            }
            if (args.has_member ("text")) {
                if (p.kind != PropKind.TEXT) throw new IOError.INVALID_ARGUMENT ("%s is not a text property", path);
                string s = text (args, "text");
                w.doc.edit ("Change Text", () => {
                    var d = p.raw_text_at (lt).copy ();
                    d.text = s;
                    if (key || p.keys.size > 0) p.set_text_key (lt, d);
                    else {
                        p.text = d;
                        p.touch ();
                    }
                });
            } else if (args.has_member ("value")) {
                if (p.kind == PropKind.TEXT || p.kind == PropKind.PATH) throw new IOError.INVALID_ARGUMENT ("%s takes text or a path, not numbers", path);
                var v = read_numbers (args, "value");
                int need = p.value.length;
                if (v.length != need) throw new IOError.INVALID_ARGUMENT ("%s takes %d numbers, got %d", path, need, v.length);
                w.doc.edit ("Change Value", () => {
                    if (key) p.set_key (lt, v);
                    else p.set_value_at (lt, v);
                });
            }
            return property_info (l, p, t);
        }

        private static Json.Node effect (KeyframeWindow w, Json.Object args) throws Error {
            string id = text (args, "effect");
            if (id == "") {
                var o = new Json.Object ();
                var a = new Json.Array ();
                foreach (var d in EffectRegistry.all ()) {
                    var eo = new Json.Object ();
                    eo.set_string_member ("id", d.id);
                    eo.set_string_member ("label", d.label);
                    eo.set_string_member ("category", d.category);
                    a.add_object_element (eo);
                }
                o.set_array_member ("effects", a);
                return obj (o);
            }
            var l = need_layer (w, args);
            if (EffectRegistry.get (id) == null) throw new IOError.NOT_FOUND ("no effect %s; omit effect to list them", id);
            if (args.has_member ("remove") && args.get_boolean_member ("remove")) {
                var fx = l.effects;
                PropGroup? hit = null;
                if (fx != null) foreach (var c in fx.children) if (EffectRegistry.id_of ((PropGroup) c) == id) hit = (PropGroup) c;
                if (hit == null) throw new IOError.NOT_FOUND ("layer %s has no %s effect", l.name, id);
                w.doc.edit ("Remove Effect", () => {
                    fx.children.remove (hit);
                    l.mark_changed ();
                });
                return obj (layer_info (need_comp (w), l));
            }
            PropGroup? made = null;
            w.doc.edit ("Add Effect", () => {
                made = EffectRegistry.add_to_layer (l, id);
                l.mark_changed ();
            });
            var o = layer_info (need_comp (w), l);
            if (made != null) o.set_array_member ("properties", property_paths (made));
            return obj (o);
        }

        private static Json.Node marker (KeyframeWindow w, Json.Object args) throws Error {
            var comp = need_comp (w);
            string action = text (args, "action");
            double t = num (args, "time", w.doc.time);
            if (action == "add") {
                if (t < 0 || t > comp.duration) throw new IOError.INVALID_ARGUMENT ("time must be within the composition");
                var m = new Marker (t, text (args, "comment"));
                w.doc.edit ("Add Marker", () => comp.markers.add (m));
            } else if (action == "delete") {
                Marker? hit = null;
                foreach (var m in comp.markers) if (Math.fabs (m.time - t) < 1e-3) hit = m;
                if (hit == null) throw new IOError.NOT_FOUND ("no marker at %.3f", t);
                w.doc.edit ("Delete Marker", () => comp.markers.remove (hit));
            } else {
                throw new IOError.INVALID_ARGUMENT ("action must be add or delete");
            }
            w.doc.content_changed ();
            return outline (w);
        }

        private static Json.Node seek (KeyframeWindow w, Json.Object args) throws Error {
            var comp = need_comp (w);
            double t = num (args, "time", 0);
            if (t < 0 || t > comp.duration) throw new IOError.INVALID_ARGUMENT ("time must be between 0 and %.3f", comp.duration);
            w.doc.seek (t);
            var o = new Json.Object ();
            o.set_double_member ("time", round (w.doc.time));
            return obj (o);
        }

        private static Json.Node history (KeyframeWindow w, Json.Object args) throws Error {
            string action = text (args, "action");
            if (action == "undo") {
                if (!w.doc.can_undo ()) throw new IOError.FAILED ("nothing to undo");
                w.doc.undo ();
            } else if (action == "redo") {
                if (!w.doc.can_redo ()) throw new IOError.FAILED ("nothing to redo");
                w.doc.redo ();
            } else {
                throw new IOError.INVALID_ARGUMENT ("action must be undo or redo");
            }
            return outline (w);
        }

        private static Json.Node save (KeyframeWindow w, Json.Object args) throws Error {
            string path = text (args, "path");
            if (path == "") path = w.doc.project.path;
            if (path == "") throw new IOError.INVALID_ARGUMENT ("the project has never been saved; pass a path");
            if (!path.has_suffix (".keyframe")) path += ".keyframe";
            NativeFormat.save (w.doc.project, path);
            var o = new Json.Object ();
            o.set_string_member ("path", path);
            return obj (o);
        }

        private static Json.Node formats () {
            var o = new Json.Object ();
            var a = new Json.Array ();
            foreach (var f in Encoders.formats ()) {
                var fo = new Json.Object ();
                fo.set_string_member ("id", f.id);
                fo.set_string_member ("label", f.label);
                fo.set_string_member ("extension", f.extension);
                fo.set_boolean_member ("available", f.available);
                if (!f.available) fo.set_string_member ("reason", f.reason);
                a.add_object_element (fo);
            }
            o.set_array_member ("formats", a);
            return obj (o);
        }

        private static async Json.Node render (KeyframeWindow w, Json.Object args) throws Error {
            var comp = need_comp (w);
            string format = text (args, "format");
            string path = text (args, "path");
            OutputFormat? fmt = null;
            foreach (var f in Encoders.formats ()) if (f.id == format) fmt = f;
            if (fmt == null) throw new IOError.INVALID_ARGUMENT ("unknown format %s; keyframe_formats lists them", format);
            if (!fmt.available) throw new IOError.NOT_SUPPORTED ("%s is not available: %s", format, fmt.reason);
            if (path == "" || !Path.is_absolute (path)) throw new IOError.INVALID_ARGUMENT ("path must be absolute");
            if (FileUtils.test (path, FileTest.EXISTS) && !(args.has_member ("overwrite") && args.get_boolean_member ("overwrite")))
                throw new IOError.EXISTS ("%s already exists; pass overwrite to replace it", path);
            double start = num (args, "start", 0), end = num (args, "end", comp.duration);
            if (start < 0 || end > comp.duration + 1e-6 || end <= start) throw new IOError.INVALID_ARGUMENT ("start and end must lie within the composition, start before end");
            var item = new RenderItem (comp.id);
            item.start = start;
            item.end = end;
            var om = new OutputModule ();
            om.format = format;
            om.path = path;
            om.alpha = args.has_member ("alpha") && args.get_boolean_member ("alpha") && fmt.alpha;
            item.outputs.add (om);
            w.doc.project.render_queue.add (item);
            var dir = Path.build_filename (Environment.get_user_cache_dir (), "keyframe", "render");
            DirUtils.create_with_parents (dir, 0700);
            var copy = Path.build_filename (dir, "agent-%s.keyframe".printf (Layer.new_id ()));
            var p = w.doc.project;
            string old = p.base_dir;
            p.base_dir = "";
            try {
                FileUtils.set_data (copy, NativeFormat.save_bytes (p));
            } finally {
                p.base_dir = old;
            }
            item.status = RenderStatus.RENDERING;
            string last_error = "";
            int code = -1;
            try {
                var proc = new Subprocess.newv (RenderJobs.helper_argv (copy, item.id), SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
                var input = new DataInputStream (proc.get_stdout_pipe ());
                string? line;
                while ((line = yield input.read_line_async (Priority.DEFAULT, null)) != null) {
                    string kind, value;
                    RenderJobs.parse_line (line, out kind, out value);
                    if (kind == "progress") item.progress = double.parse (value);
                    else if (kind == "error") last_error = value;
                }
                yield proc.wait_async (null);
                code = proc.get_if_exited () ? proc.get_exit_status () : -1;
            } finally {
                FileUtils.unlink (copy);
            }
            p.modified = true;
            if (code != 0) {
                item.status = RenderStatus.FAILED;
                item.error = last_error != "" ? last_error : "the renderer stopped unexpectedly";
                throw new IOError.FAILED ("render failed: %s", item.error);
            }
            item.status = RenderStatus.DONE;
            item.progress = 1;
            var o = new Json.Object ();
            o.set_string_member ("path", path);
            o.set_string_member ("format", format);
            o.set_double_member ("start", round (start));
            o.set_double_member ("end", round (end));
            if (!fmt.sequence) {
                var info = File.new_for_path (path).query_info (FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
                o.set_int_member ("bytes", info.get_size ());
            }
            return obj (o);
        }

        private static async Json.Node handle (KeyframeApp app, string name, Json.Object args) throws Error {
            var w = app.shown_window ();
            switch (name) {
                case "keyframe_outline": return outline (w);
                case "keyframe_new": return new_thing (w, args);
                case "keyframe_open": return open (w, args);
                case "keyframe_layer": return layer (w, args);
                case "keyframe_property": return property (w, args);
                case "keyframe_effect": return effect (w, args);
                case "keyframe_marker": return marker (w, args);
                case "keyframe_seek": return seek (w, args);
                case "keyframe_history": return history (w, args);
                case "keyframe_save": return save (w, args);
                case "keyframe_formats": return formats ();
                case "keyframe_render": return yield render (w, args);
                default: throw new IOError.NOT_SUPPORTED ("unknown intent %s", name);
            }
        }

        private static void add (KeyframeApp app, string name, string description, string schema, Singularity.AppIntentRisk risk) {
            app.agent.add_async_intent (name, description, schema, risk, (args, reply) => {
                handle.begin (app, name, args, (o, res) => {
                    try {
                        reply (handle.end (res), null);
                    } catch (Error e) {
                        reply (null, e);
                    }
                });
            });
        }

        internal static void install (KeyframeApp app) {
            string layer_ref = """"layer":{"type":["integer","string"],"description":"1-based layer index (1 is the top layer) or layer name; defaults to the selected layer"}""";
            add (app, "keyframe_outline", "Describe the open project: compositions, footage, the active composition's layers, markers, current time and render queue.",
                """{"type":"object","properties":{}}""", Singularity.AppIntentRisk.READ);
            add (app, "keyframe_new", "Create a new project or add a composition to the open project and make it active.",
                """{"type":"object","properties":{"what":{"type":"string","enum":["project","composition"]},"name":{"type":"string"},"width":{"type":"integer"},"height":{"type":"integer"},"fps":{"type":"number"},"duration":{"type":"number","description":"seconds"},"discard":{"type":"boolean","description":"discard unsaved changes when creating a project"}},"required":["what"]}""",
                Singularity.AppIntentRisk.UNDOABLE);
            add (app, "keyframe_open", "Open a .keyframe project file, or switch to another composition of the open project.",
                """{"type":"object","properties":{"path":{"type":"string"},"composition":{"type":"string"},"discard":{"type":"boolean"}}}""",
                Singularity.AppIntentRisk.UNDOABLE);
            add (app, "keyframe_layer", "Add, delete, select or update a layer of the active composition. Footage layers import the file at path.",
                """{"type":"object","properties":{"action":{"type":"string","enum":["add","delete","select","update"]},""" + layer_ref + ""","kind":{"type":"string","enum":""" + list (LAYERS) + """},"name":{"type":"string"},"text":{"type":"string"},"size":{"type":"number"},"path":{"type":"string"},"color":{"type":"array","items":{"type":"number"},"description":"[r,g,b] or [r,g,b,a] in 0..1"},"shape":{"type":"string","enum":["rect","ellipse","star"]},"shape_width":{"type":"number"},"shape_height":{"type":"number"},"roundness":{"type":"number"},"points":{"type":"integer"},"focal_mm":{"type":"number"},"in":{"type":"number"},"out":{"type":"number"},"index":{"type":"integer"},"visible":{"type":"boolean"}},"required":["action"]}""",
                Singularity.AppIntentRisk.UNDOABLE);
            add (app, "keyframe_property", "Read or change a layer property by path such as transform/position. Omit path to list a layer's properties. A value at a time on an animated property, or with key true, sets a keyframe.",
                """{"type":"object","properties":{""" + layer_ref + ""","path":{"type":"string"},"time":{"type":"number","description":"composition seconds; defaults to the current time"},"value":{"type":["number","array"],"items":{"type":"number"}},"text":{"type":"string"},"key":{"type":"boolean"},"clear_keys":{"type":"boolean"},"expression":{"type":"string"}}}""",
                Singularity.AppIntentRisk.UNDOABLE);
            add (app, "keyframe_effect", "Add or remove an effect on a layer. Omit effect to list the available effects.",
                """{"type":"object","properties":{""" + layer_ref + ""","effect":{"type":"string"},"remove":{"type":"boolean"}}}""",
                Singularity.AppIntentRisk.UNDOABLE);
            add (app, "keyframe_marker", "Add or delete a marker in the active composition.",
                """{"type":"object","properties":{"action":{"type":"string","enum":["add","delete"]},"time":{"type":"number"},"comment":{"type":"string"}},"required":["action"]}""",
                Singularity.AppIntentRisk.UNDOABLE);
            add (app, "keyframe_seek", "Move the current time of the active composition.",
                """{"type":"object","properties":{"time":{"type":"number"}},"required":["time"]}""", Singularity.AppIntentRisk.READ);
            add (app, "keyframe_history", "Undo or redo the last change.",
                """{"type":"object","properties":{"action":{"type":"string","enum":["undo","redo"]}},"required":["action"]}""",
                Singularity.AppIntentRisk.UNDOABLE);
            add (app, "keyframe_save", "Save the project, to its current file or to path.",
                """{"type":"object","properties":{"path":{"type":"string"}}}""", Singularity.AppIntentRisk.IRREVERSIBLE);
            add (app, "keyframe_formats", "List the render output formats and whether each is available.",
                """{"type":"object","properties":{}}""", Singularity.AppIntentRisk.READ);
            add (app, "keyframe_render", "Render the active composition to a file and wait until it is written.",
                """{"type":"object","properties":{"format":{"type":"string"},"path":{"type":"string","description":"absolute output path"},"start":{"type":"number"},"end":{"type":"number"},"alpha":{"type":"boolean"},"overwrite":{"type":"boolean"}},"required":["format","path"]}""",
                Singularity.AppIntentRisk.IRREVERSIBLE);
        }
    }
}
