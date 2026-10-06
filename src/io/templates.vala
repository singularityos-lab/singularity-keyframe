namespace Singularity.Apps.Keyframe {

    public class TemplateParam {
        public string label;
        public Layer layer;
        public Property prop;
        public EssentialProperty entry;

        public TemplateParam (string label, Layer layer, Property prop, EssentialProperty entry) {
            this.label = label;
            this.layer = layer;
            this.prop = prop;
            this.entry = entry;
        }
    }

    namespace MotionTemplates {
        public EssentialProperty expose (Composition comp, Layer layer, Property prop, string label) {
            var path = prop.path_string ();
            foreach (var e in comp.essential) {
                if (e.layer_id == layer.id && e.path == path) {
                    e.label = label;
                    return e;
                }
            }
            var e = new EssentialProperty (layer.id, path, label);
            comp.essential.add (e);
            comp.layer_changed (null);
            return e;
        }

        public void remove (Composition comp, EssentialProperty entry) {
            comp.essential.remove (entry);
            comp.layer_changed (null);
        }

        public Gee.ArrayList<TemplateParam> params (Composition comp) {
            var r = new Gee.ArrayList<TemplateParam> ();
            foreach (var e in comp.essential) {
                var l = comp.layer_by_id (e.layer_id);
                if (l == null) continue;
                var p = l.root.find (e.path) as Property;
                if (p == null) continue;
                r.add (new TemplateParam (e.label, l, p, e));
            }
            return r;
        }

        public Composition? main_composition (Project p) {
            foreach (var c in p.compositions ()) if (c.essential.size > 0) return c;
            var used = new Gee.HashSet<string> ();
            foreach (var c in p.compositions ())
                foreach (var l in c.layers) if (l.kind == LayerKind.PRECOMP) used.add (l.source_id);
            Composition? last = null;
            foreach (var c in p.compositions ()) if (!used.contains (c.id)) last = c;
            if (last != null) return last;
            var all = p.compositions ();
            return all.size > 0 ? all[0] : null;
        }

        public bool set_value (TemplateParam tp, Json.Node v) {
            var p = tp.prop;
            if (p.kind == PropKind.TEXT) {
                string text;
                if (v.get_value_type () == typeof (string)) text = v.get_string ();
                else return false;
                if (p.keys.size > 0) {
                    foreach (var k in p.keys) if (k.text != null) k.text.text = text;
                } else {
                    var d = (p.text ?? new TextDocument ()).copy ();
                    d.text = text;
                    p.text = d;
                }
                p.touch ();
                return true;
            }
            double[] vals;
            if (v.get_node_type () == Json.NodeType.ARRAY) vals = JsonUtil.node_array (v);
            else if (v.get_value_type () == typeof (bool)) vals = { v.get_boolean () ? 1 : 0 };
            else if (v.get_value_type () == typeof (int64)) vals = { (double) v.get_int () };
            else if (v.get_value_type () == typeof (double)) vals = { v.get_double () };
            else if (v.get_value_type () == typeof (string) && p.kind == PropKind.COLOR) vals = parse_hex (v.get_string ());
            else return false;
            var full = new double[p.dims];
            for (int i = 0; i < p.dims; i++) full[i] = i < vals.length ? vals[i] : (i < p.value.length ? p.value[i] : 0);
            if (p.keys.size > 0) {
                var base_v = p.keys[0].value;
                foreach (var k in p.keys) {
                    for (int i = 0; i < p.dims && i < k.value.length; i++) k.value[i] = k.value[i] - base_v[i] + full[i];
                }
            } else {
                p.value = p.clamp_value (full);
            }
            p.touch ();
            return true;
        }

        public double[] parse_hex (string s) {
            var h = s.has_prefix ("#") ? s.substring (1) : s;
            double[] r = { 0, 0, 0, 1 };
            for (int i = 0; i < 4 && i * 2 + 2 <= h.length; i++) {
                uint64 v;
                uint64.try_parse (h.substring (i * 2, 2), out v, null, 16);
                r[i] = i < 3 ? Singularity.Imaging.Transfer.srgb_to_linear ((float) (v / 255.0)) : v / 255.0;
            }
            return r;
        }

        public int apply_overrides (Composition comp, string json) throws Error {
            if (json.strip () == "") return 0;
            var root = JsonUtil.parse (json);
            if (root.get_node_type () != Json.NodeType.OBJECT) throw new ProjectError.FORMAT (_("Template values must be a JSON object"));
            var o = root.get_object ();
            int applied = 0;
            foreach (var tp in params (comp)) {
                if (!o.has_member (tp.label)) continue;
                if (set_value (tp, o.get_member (tp.label))) applied++;
            }
            return applied;
        }

        public string values_json (Composition comp, double t = 0) {
            var b = new Json.Builder ();
            b.begin_object ();
            foreach (var tp in params (comp)) {
                b.set_member_name (tp.label);
                if (tp.prop.kind == PropKind.TEXT) b.add_string_value (tp.prop.text_at (tp.layer.layer_time (t)).text);
                else if (tp.prop.dims == 1) b.add_double_value (tp.prop.value_at (tp.layer.layer_time (t))[0]);
                else JsonUtil.add_array (b, tp.prop.value_at (tp.layer.layer_time (t)));
            }
            b.end_object ();
            return JsonUtil.to_string (b.get_root (), false);
        }

        private void collect (Project p, Composition c, Gee.HashSet<string> ids, int depth) {
            if (depth > 16 || ids.contains (c.id)) return;
            ids.add (c.id);
            foreach (var l in c.layers) {
                if (l.source_id == "") continue;
                ids.add (l.source_id);
                var nested = p.comp_by_id (l.source_id);
                if (nested != null) collect (p, nested, ids, depth + 1);
            }
        }

        public void save_template (Project p, Composition comp, string path) throws Error {
            var copy = NativeFormat.restore (NativeFormat.snapshot (p), p.base_dir);
            var ids = new Gee.HashSet<string> ();
            collect (copy, copy.comp_by_id (comp.id), ids, 0);
            var drop = new Gee.ArrayList<Item> ();
            foreach (var i in copy.items) if (!ids.contains (i.id) && !(i is Folder)) drop.add (i);
            foreach (var i in drop) copy.items.remove (i);
            copy.render_queue.clear ();
            var main = copy.comp_by_id (comp.id);
            if (main != null) {
                copy.items.remove (main);
                copy.items.insert (0, main);
            }
            NativeFormat.save (copy, path);
        }

        public Project instantiate (string template_path, string overrides) throws Error {
            var p = NativeFormat.load (template_path);
            var main = main_composition (p);
            if (main != null) apply_overrides (main, overrides);
            return p;
        }
    }
}
