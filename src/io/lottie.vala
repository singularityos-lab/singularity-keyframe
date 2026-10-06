using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    public class LottieExport {
        public Gee.ArrayList<string> warnings = new Gee.ArrayList<string> ();
        private Project project;
        private Renderer? renderer;
        private Gee.HashMap<string, string> asset_ids = new Gee.HashMap<string, string> ();
        private Json.Builder assets = new Json.Builder ();
        private int asset_count = 0;
        private double fps;
        private Gee.HashSet<string> fonts = new Gee.HashSet<string> ();

        public LottieExport (Project project) {
            this.project = project;
        }

        private void warn (string w) {
            if (!warnings.contains (w)) warnings.add (w);
        }

        public static int blend_code (BlendMode b) {
            switch (b) {
                case BlendMode.NORMAL: return 0;
                case BlendMode.MULTIPLY: return 1;
                case BlendMode.SCREEN: return 2;
                case BlendMode.OVERLAY: return 3;
                case BlendMode.DARKEN: return 4;
                case BlendMode.LIGHTEN: return 5;
                case BlendMode.COLOR_DODGE: return 6;
                case BlendMode.COLOR_BURN: return 7;
                case BlendMode.HARD_LIGHT: return 8;
                case BlendMode.SOFT_LIGHT: return 9;
                case BlendMode.DIFFERENCE: return 10;
                case BlendMode.EXCLUSION: return 11;
                case BlendMode.HUE: return 12;
                case BlendMode.SATURATION: return 13;
                case BlendMode.COLOR: return 14;
                case BlendMode.LUMINOSITY: return 15;
                case BlendMode.LINEAR_DODGE: return 16;
                case BlendMode.HARD_MIX: return 17;
                default: return -1;
            }
        }

        public static BlendMode blend_from_code (int c) {
            BlendMode[] m = { BlendMode.NORMAL, BlendMode.MULTIPLY, BlendMode.SCREEN, BlendMode.OVERLAY, BlendMode.DARKEN, BlendMode.LIGHTEN,
                              BlendMode.COLOR_DODGE, BlendMode.COLOR_BURN, BlendMode.HARD_LIGHT, BlendMode.SOFT_LIGHT, BlendMode.DIFFERENCE,
                              BlendMode.EXCLUSION, BlendMode.HUE, BlendMode.SATURATION, BlendMode.COLOR, BlendMode.LUMINOSITY, BlendMode.LINEAR_DODGE, BlendMode.HARD_MIX };
            return c >= 0 && c < m.length ? m[c] : BlendMode.NORMAL;
        }

        public string export (Composition comp) {
            fps = comp.fps;
            assets.begin_array ();
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("v").add_string_value ("5.7.4");
            b.set_member_name ("fr").add_double_value (comp.fps);
            b.set_member_name ("ip").add_double_value (0);
            b.set_member_name ("op").add_double_value (Math.round (comp.duration * comp.fps));
            b.set_member_name ("w").add_int_value (comp.width);
            b.set_member_name ("h").add_int_value (comp.height);
            b.set_member_name ("nm").add_string_value (comp.name);
            b.set_member_name ("ddd").add_int_value (0);
            b.set_member_name ("layers");
            layers (b, comp, 0);
            assets.end_array ();
            b.set_member_name ("assets").add_value (assets.get_root ());
            if (fonts.size > 0) {
                b.set_member_name ("fonts");
                b.begin_object ();
                b.set_member_name ("list");
                b.begin_array ();
                foreach (var f in fonts) {
                    b.begin_object ();
                    b.set_member_name ("fName").add_string_value (f);
                    var parts = f.split ("-", 2);
                    b.set_member_name ("fFamily").add_string_value (parts[0]);
                    b.set_member_name ("fStyle").add_string_value (parts.length > 1 ? parts[1] : "Regular");
                    b.set_member_name ("ascent").add_double_value (75);
                    b.end_object ();
                }
                b.end_array ();
                b.end_object ();
            }
            b.set_member_name ("markers");
            b.begin_array ();
            foreach (var m in comp.markers) {
                b.begin_object ();
                b.set_member_name ("tm").add_double_value (m.time * fps);
                b.set_member_name ("cm").add_string_value (m.comment);
                b.set_member_name ("dr").add_double_value (m.duration * fps);
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
            return JsonUtil.to_string (b.get_root (), false);
        }

        private int layer_index (Composition comp, Layer l) {
            return comp.layers.index_of (l) + 1;
        }

        private void layers (Json.Builder b, Composition comp, int depth) {
            b.begin_array ();
            foreach (var l in comp.layers) layer (b, comp, l, depth);
            b.end_array ();
        }

        private void layer (Json.Builder b, Composition comp, Layer l, int depth) {
            int ty;
            switch (l.kind) {
                case LayerKind.PRECOMP: ty = 0; break;
                case LayerKind.SOLID: ty = 1; break;
                case LayerKind.NULL: ty = 3; break;
                case LayerKind.SHAPE: ty = 4; break;
                case LayerKind.TEXT: ty = 5; break;
                case LayerKind.FOOTAGE:
                    var f = project.footage_by_id (l.source_id);
                    if (f != null && f.kind == FootageKind.IMAGE) ty = 2;
                    else {
                        warn (_("Video and sequence footage cannot be exported to Lottie: “%s” was skipped").printf (l.name));
                        return;
                    }
                    break;
                case LayerKind.CAMERA:
                case LayerKind.LIGHT:
                    warn (_("Cameras and lights are not supported by Lottie players: “%s” was skipped").printf (l.name));
                    return;
                default:
                    warn (_("Layer “%s” has no Lottie equivalent and was skipped").printf (l.name));
                    return;
            }
            if (l.adjustment) {
                warn (_("Adjustment layers are not supported by Lottie: “%s” was skipped").printf (l.name));
                return;
            }
            b.begin_object ();
            b.set_member_name ("ddd").add_int_value (l.three_d ? 1 : 0);
            if (l.three_d) warn (_("3D layers are exported flat; Lottie players ignore most 3D settings"));
            b.set_member_name ("ind").add_int_value (layer_index (comp, l));
            b.set_member_name ("ty").add_int_value (ty);
            b.set_member_name ("nm").add_string_value (l.name);
            b.set_member_name ("sr").add_double_value (l.stretch);
            if (l.stretch != 1) warn (_("Time stretch may play differently in some Lottie players"));
            var parent = l.parent_layer ();
            if (parent != null) b.set_member_name ("parent").add_int_value (layer_index (comp, parent));
            if (!l.video) b.set_member_name ("hd").add_boolean_value (true);
            b.set_member_name ("ip").add_double_value (l.in_point * fps);
            b.set_member_name ("op").add_double_value (l.out_point * fps);
            b.set_member_name ("st").add_double_value (l.start_time * fps);
            int bm = blend_code (l.blend);
            if (bm < 0) {
                warn (_("Blend mode “%s” is not available in Lottie and was exported as Normal").printf (l.blend.label ()));
                bm = 0;
            }
            b.set_member_name ("bm").add_int_value (bm);
            b.set_member_name ("ao").add_int_value (l.auto_orient == AutoOrient.ALONG_PATH ? 1 : 0);
            if (l.matte_mode != MatteMode.NONE) {
                int tt = l.matte_mode == MatteMode.ALPHA ? 1 : (l.matte_mode == MatteMode.ALPHA_INVERTED ? 2 : (l.matte_mode == MatteMode.LUMA ? 3 : 4));
                b.set_member_name ("tt").add_int_value (tt);
                int idx = comp.layers.index_of (l);
                if (l.matte_id != "" && (idx == 0 || comp.layers[idx - 1].id != l.matte_id)) {
                    var src = comp.layer_by_id (l.matte_id);
                    if (src != null) b.set_member_name ("tp").add_int_value (layer_index (comp, src));
                    warn (_("Track matte from a layer that is not directly above needs a recent Lottie player"));
                }
            }
            int pos = comp.layers.index_of (l);
            if (pos + 1 < comp.layers.size) {
                var below = comp.layers[pos + 1];
                if (below.matte_mode != MatteMode.NONE && (below.matte_id == "" || below.matte_id == l.id)) b.set_member_name ("td").add_int_value (1);
            }
            b.set_member_name ("ks");
            transform (b, l.transform, l);
            masks (b, l);
            effects (l);
            switch (ty) {
                case 0:
                    var nested = project.comp_by_id (l.source_id);
                    b.set_member_name ("refId").add_string_value (nested != null ? precomp_asset (nested, depth) : "");
                    b.set_member_name ("w").add_int_value (l.solid_width);
                    b.set_member_name ("h").add_int_value (l.solid_height);
                    if (l.time_remap) {
                        var tm = l.root.prop ("time-remap");
                        if (tm != null) {
                            b.set_member_name ("tm");
                            prop (b, tm, l, 1, 0);
                        }
                    }
                    break;
                case 1:
                    b.set_member_name ("sc").add_string_value ("#%02x%02x%02x".printf (to8 (l.solid_color[0]), to8 (l.solid_color[1]), to8 (l.solid_color[2])));
                    b.set_member_name ("sw").add_int_value (l.solid_width);
                    b.set_member_name ("sh").add_int_value (l.solid_height);
                    break;
                case 2:
                    b.set_member_name ("refId").add_string_value (image_asset (l));
                    break;
                case 4:
                    b.set_member_name ("shapes");
                    shapes (b, l.contents, l);
                    break;
                case 5:
                    text (b, l);
                    break;
            }
            b.end_object ();
        }

        private static int to8 (double v) {
            return ((int) Math.round (Transfer.linear_to_srgb ((float) v.clamp (0, 1)) * 255)).clamp (0, 255);
        }

        private void effects (Layer l) {
            var fx = l.effects;
            if (fx == null) return;
            foreach (var c in fx.children) {
                var g = c as PropGroup;
                if (g == null || !g.enabled) continue;
                var def = EffectRegistry.get (EffectRegistry.id_of (g));
                if (def != null && def.control) continue;
                warn (_("Effect “%s” on “%s” is not supported by Lottie and was skipped").printf (g.name, l.name));
            }
        }

        private string precomp_asset (Composition nested, int depth) {
            if (asset_ids.has_key (nested.id)) return asset_ids[nested.id];
            string id = "comp_%d".printf (asset_count++);
            asset_ids[nested.id] = id;
            if (depth > 12) return id;
            assets.begin_object ();
            assets.set_member_name ("id").add_string_value (id);
            assets.set_member_name ("nm").add_string_value (nested.name);
            assets.set_member_name ("fr").add_double_value (nested.fps);
            assets.set_member_name ("layers");
            if ((nested.fps - fps).abs () > 1e-6) warn (_("Precomposition “%s” has a different frame rate; Lottie uses the main rate").printf (nested.name));
            layers (assets, nested, depth + 1);
            assets.end_object ();
            return id;
        }

        private string image_asset (Layer l) {
            var f = project.footage_by_id (l.source_id);
            if (f == null) return "";
            if (asset_ids.has_key (f.id)) return asset_ids[f.id];
            string id = "image_%d".printf (asset_count++);
            asset_ids[f.id] = id;
            string data = "";
            try {
                var img = ImageIO.load (f.effective_path ());
                Pixels.premultiply (img);
                data = "data:image/png;base64," + Base64.encode (ImageIO.encode_png (img, 8, true));
                f.width = img.width;
                f.height = img.height;
            } catch (Error e) {
                warn (_("Image “%s” could not be embedded").printf (f.name));
            }
            assets.begin_object ();
            assets.set_member_name ("id").add_string_value (id);
            assets.set_member_name ("w").add_int_value (f.width);
            assets.set_member_name ("h").add_int_value (f.height);
            assets.set_member_name ("u").add_string_value ("");
            assets.set_member_name ("p").add_string_value (data);
            assets.set_member_name ("e").add_int_value (1);
            assets.end_object ();
            return id;
        }

        private double[] convert (Property p, double[] v, double scale, int dims) {
            int n = dims > 0 ? dims : v.length;
            var r = new double[n];
            for (int i = 0; i < n; i++) r[i] = i < v.length ? v[i] * scale : 0;
            if (p.kind == PropKind.COLOR) for (int i = 0; i < n && i < 3; i++) r[i] = Transfer.linear_to_srgb ((float) v[i].clamp (0, 1));
            return r;
        }

        private void value (Json.Builder b, double[] v, bool scalar) {
            if (scalar) {
                b.add_double_value (v.length > 0 ? v[0] : 0);
                return;
            }
            JsonUtil.add_array (b, v);
        }

        public void prop (Json.Builder b, Property? p, Layer? l, double scale = 1, int dims = 0, bool force_array = false) {
            b.begin_object ();
            if (p == null) {
                b.set_member_name ("a").add_int_value (0);
                b.set_member_name ("k").add_int_value (0);
                b.end_object ();
                return;
            }
            bool scalar = !force_array && (dims == 1 || (dims == 0 && p.dims == 1));
            if (p.expression.strip () != "") {
                b.set_member_name ("x").add_string_value (p.expression);
                warn (_("Expressions are passed through; many Lottie players ignore them"));
            }
            if (p.keys.size == 0) {
                b.set_member_name ("a").add_int_value (0);
                b.set_member_name ("k");
                value (b, convert (p, p.value, scale, dims), scalar);
                b.end_object ();
                return;
            }
            b.set_member_name ("a").add_int_value (1);
            b.set_member_name ("k");
            b.begin_array ();
            var times = p.effective_times ();
            for (int i = 0; i < p.keys.size; i++) {
                var k = p.keys[i];
                double ct = l != null ? l.comp_time (times[i]) : times[i];
                b.begin_object ();
                b.set_member_name ("t").add_double_value (ct * fps);
                b.set_member_name ("s");
                value (b, convert (p, k.value, scale, dims), false);
                if (i < p.keys.size - 1) {
                    if (k.out_interp == Interp.HOLD) b.set_member_name ("h").add_int_value (1);
                    else {
                        double x1, y1, x2, y2;
                        p.segment_ease (i, times, out x1, out y1, out x2, out y2);
                        b.set_member_name ("o");
                        ease (b, x1, y1);
                        b.set_member_name ("i");
                        ease (b, x2, y2);
                        if (p.spatial) {
                            double[] tin0, tout0, tin1, tout1;
                            p.auto_tangents (i, out tin0, out tout0);
                            p.auto_tangents (i + 1, out tin1, out tout1);
                            b.set_member_name ("to");
                            JsonUtil.add_array (b, convert (p, tout0, 1, dims));
                            b.set_member_name ("ti");
                            JsonUtil.add_array (b, convert (p, tin1, 1, dims));
                        }
                    }
                }
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
        }

        private void ease (Json.Builder b, double x, double y) {
            b.begin_object ();
            b.set_member_name ("x").add_double_value (x);
            b.set_member_name ("y").add_double_value (y);
            b.end_object ();
        }

        private void path_value (Json.Builder b, BezPath p) {
            b.begin_object ();
            b.set_member_name ("c").add_boolean_value (p.closed);
            b.set_member_name ("v");
            b.begin_array ();
            foreach (var v in p.v) JsonUtil.add_array (b, { v.x, v.y });
            b.end_array ();
            b.set_member_name ("i");
            b.begin_array ();
            foreach (var v in p.v) JsonUtil.add_array (b, { v.in_x, v.in_y });
            b.end_array ();
            b.set_member_name ("o");
            b.begin_array ();
            foreach (var v in p.v) JsonUtil.add_array (b, { v.out_x, v.out_y });
            b.end_array ();
            b.end_object ();
        }

        public void path_prop (Json.Builder b, Property p, Layer? l) {
            b.begin_object ();
            if (p.keys.size == 0) {
                b.set_member_name ("a").add_int_value (0);
                b.set_member_name ("k");
                path_value (b, p.path ?? new BezPath ());
                b.end_object ();
                return;
            }
            b.set_member_name ("a").add_int_value (1);
            b.set_member_name ("k");
            b.begin_array ();
            var times = p.effective_times ();
            int n = 0;
            foreach (var k in p.keys) n = int.max (n, k.path != null ? k.path.count : 0);
            for (int i = 0; i < p.keys.size; i++) {
                var k = p.keys[i];
                double ct = l != null ? l.comp_time (times[i]) : times[i];
                b.begin_object ();
                b.set_member_name ("t").add_double_value (ct * fps);
                b.set_member_name ("s");
                b.begin_array ();
                path_value (b, k.path != null && k.path.count != n ? k.path.resampled (n) : (k.path ?? new BezPath ()));
                b.end_array ();
                if (i < p.keys.size - 1) {
                    if (k.out_interp == Interp.HOLD) b.set_member_name ("h").add_int_value (1);
                    else {
                        double x1, y1, x2, y2;
                        p.segment_ease (i, times, out x1, out y1, out x2, out y2);
                        b.set_member_name ("o");
                        ease (b, x1, y1);
                        b.set_member_name ("i");
                        ease (b, x2, y2);
                    }
                }
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
        }

        private void transform (Json.Builder b, PropGroup t, Layer l) {
            b.begin_object ();
            b.set_member_name ("o");
            prop (b, t.prop ("opacity"), l);
            b.set_member_name ("r");
            prop (b, t.prop ("rotation"), l);
            b.set_member_name ("p");
            prop (b, t.prop ("position"), l, 1, l.three_d ? 3 : 2);
            b.set_member_name ("a");
            prop (b, t.prop ("anchor"), l, 1, l.three_d ? 3 : 2);
            b.set_member_name ("s");
            prop (b, t.prop ("scale"), l, 1, l.three_d ? 3 : 2);
            if (t.prop ("skew") != null) {
                b.set_member_name ("sk");
                prop (b, t.prop ("skew"), l);
                b.set_member_name ("sa");
                prop (b, t.prop ("skew-axis"), l);
            }
            if (l.three_d) {
                b.set_member_name ("rx");
                prop (b, t.prop ("rotation-x"), l);
                b.set_member_name ("ry");
                prop (b, t.prop ("rotation-y"), l);
                b.set_member_name ("or");
                prop (b, t.prop ("orientation"), l, 1, 3);
            }
            b.end_object ();
        }

        private void masks (Json.Builder b, Layer l) {
            var m = l.masks;
            if (m == null || m.children.size == 0) return;
            b.set_member_name ("hasMask").add_boolean_value (true);
            b.set_member_name ("masksProperties");
            b.begin_array ();
            foreach (var c in m.children) {
                var g = c as PropGroup;
                if (g == null) continue;
                b.begin_object ();
                b.set_member_name ("inv").add_boolean_value (g.attr ("inverted", "false") == "true");
                string mode;
                switch (g.attr ("mode", "add")) {
                    case "subtract": mode = "s"; break;
                    case "intersect": mode = "i"; break;
                    case "lighten": mode = "l"; break;
                    case "darken": mode = "d"; break;
                    case "difference": mode = "f"; break;
                    case "none": mode = "n"; break;
                    default: mode = "a"; break;
                }
                b.set_member_name ("mode").add_string_value (mode);
                b.set_member_name ("nm").add_string_value (g.name);
                b.set_member_name ("pt");
                path_prop (b, g.prop ("path"), l);
                b.set_member_name ("o");
                prop (b, g.prop ("opacity"), l);
                b.set_member_name ("x");
                prop (b, g.prop ("expansion"), l);
                var f = g.prop ("feather");
                if (f != null && (f.is_animated () || f.value[0] > 0)) {
                    b.set_member_name ("f");
                    prop (b, f, l, 1, 2);
                    warn (_("Mask feather is only supported by some Lottie players"));
                }
                b.end_object ();
            }
            b.end_array ();
        }

        private void shapes (Json.Builder b, PropGroup? contents, Layer l) {
            b.begin_array ();
            if (contents != null) foreach (var c in contents.children) {
                var g = c as PropGroup;
                if (g == null) continue;
                shape (b, g, l);
            }
            b.end_array ();
        }

        private void stops (Json.Builder b, PropGroup g) {
            var p = g.prop ("stops");
            var v = p != null ? p.value : new double[] { 0, 1, 1, 1, 1, 1, 0, 0, 0, 1 };
            int n = v.length / 5;
            b.begin_object ();
            b.set_member_name ("p").add_int_value (n);
            b.set_member_name ("k");
            b.begin_object ();
            b.set_member_name ("a").add_int_value (0);
            b.set_member_name ("k");
            b.begin_array ();
            for (int i = 0; i < n; i++) {
                b.add_double_value (v[i * 5]);
                for (int c = 1; c < 4; c++) b.add_double_value (Transfer.linear_to_srgb ((float) v[i * 5 + c].clamp (0, 1)));
            }
            for (int i = 0; i < n; i++) {
                b.add_double_value (v[i * 5]);
                b.add_double_value (v[i * 5 + 4]);
            }
            b.end_array ();
            b.end_object ();
            b.end_object ();
            if (p != null && p.is_animated ()) warn (_("Animated gradient colours are exported as their first value"));
        }

        private void stroke_common (Json.Builder b, PropGroup g, Layer l) {
            b.set_member_name ("w");
            prop (b, g.prop ("width"), l);
            string cap = g.attr ("cap", "butt"), join = g.attr ("join", "miter");
            b.set_member_name ("lc").add_int_value (cap == "round" ? 2 : (cap == "square" ? 3 : 1));
            b.set_member_name ("lj").add_int_value (join == "round" ? 2 : (join == "bevel" ? 3 : 1));
            b.set_member_name ("ml").add_double_value (g.num ("miter-limit", 0));
            double dash = g.num ("dash", 0);
            if (dash > 0 || (g.prop ("dash") != null && g.prop ("dash").is_animated ())) {
                b.set_member_name ("d");
                b.begin_array ();
                b.begin_object ();
                b.set_member_name ("n").add_string_value ("d");
                b.set_member_name ("nm").add_string_value ("dash");
                b.set_member_name ("v");
                prop (b, g.prop ("dash"), l);
                b.end_object ();
                b.begin_object ();
                b.set_member_name ("n").add_string_value ("g");
                b.set_member_name ("nm").add_string_value ("gap");
                b.set_member_name ("v");
                prop (b, g.num ("gap", 0) > 0 ? g.prop ("gap") : g.prop ("dash"), l);
                b.end_object ();
                b.begin_object ();
                b.set_member_name ("n").add_string_value ("o");
                b.set_member_name ("nm").add_string_value ("offset");
                b.set_member_name ("v");
                prop (b, g.prop ("dash-offset"), l);
                b.end_object ();
                b.end_array ();
            }
            if (g.num ("taper-start", 0) > 0 || g.num ("taper-end", 0) > 0) warn (_("Tapered strokes are exported with constant width"));
        }

        private void gradient_common (Json.Builder b, PropGroup g, Layer l) {
            b.set_member_name ("t").add_int_value (g.attr ("gradient", "linear") == "radial" ? 2 : 1);
            b.set_member_name ("s");
            prop (b, g.prop ("start"), l, 1, 2);
            b.set_member_name ("e");
            prop (b, g.prop ("end"), l, 1, 2);
            b.set_member_name ("h");
            prop (b, g.prop ("highlight-length"), l);
            b.set_member_name ("a");
            prop (b, g.prop ("highlight-angle"), l);
            b.set_member_name ("g");
            stops (b, g);
        }

        private void shape (Json.Builder b, PropGroup g, Layer l) {
            string ty;
            switch (g.type) {
                case "shape.group": ty = "gr"; break;
                case "shape.rect": ty = "rc"; break;
                case "shape.ellipse": ty = "el"; break;
                case "shape.star": ty = "sr"; break;
                case "shape.path": ty = "sh"; break;
                case "shape.fill": ty = "fl"; break;
                case "shape.stroke": ty = "st"; break;
                case "shape.gradient-fill": ty = "gf"; break;
                case "shape.gradient-stroke": ty = "gs"; break;
                case "shape.trim": ty = "tm"; break;
                case "shape.repeater": ty = "rp"; break;
                case "shape.round": ty = "rd"; break;
                case "shape.merge": ty = "mm"; break;
                case "shape.offset": ty = "op"; break;
                case "shape.pucker": ty = "pb"; break;
                case "shape.twist": ty = "tw"; break;
                case "shape.zigzag": ty = "zz"; break;
                default:
                    warn (_("Shape operator “%s” is not supported by Lottie and was skipped").printf (g.name));
                    return;
            }
            b.begin_object ();
            b.set_member_name ("ty").add_string_value (ty);
            b.set_member_name ("nm").add_string_value (g.name);
            if (!g.enabled) b.set_member_name ("hd").add_boolean_value (true);
            if (g.attrs.has_key ("direction")) b.set_member_name ("d").add_int_value (int.parse (g.attr ("direction", "1")));
            switch (ty) {
                case "gr":
                    b.set_member_name ("it");
                    b.begin_array ();
                    var contents = g.group ("contents");
                    if (contents != null) foreach (var c in contents.children) {
                        var cg = c as PropGroup;
                        if (cg != null) shape (b, cg, l);
                    }
                    var tr = g.group ("transform");
                    b.begin_object ();
                    b.set_member_name ("ty").add_string_value ("tr");
                    if (tr != null) {
                        b.set_member_name ("p");
                        prop (b, tr.prop ("position"), l, 1, 2);
                        b.set_member_name ("a");
                        prop (b, tr.prop ("anchor"), l, 1, 2);
                        b.set_member_name ("s");
                        prop (b, tr.prop ("scale"), l, 1, 2);
                        b.set_member_name ("r");
                        prop (b, tr.prop ("rotation"), l);
                        b.set_member_name ("o");
                        prop (b, tr.prop ("opacity"), l);
                        b.set_member_name ("sk");
                        prop (b, tr.prop ("skew"), l);
                        b.set_member_name ("sa");
                        prop (b, tr.prop ("skew-axis"), l);
                    }
                    b.end_object ();
                    b.end_array ();
                    break;
                case "rc":
                    b.set_member_name ("p");
                    prop (b, g.prop ("position"), l, 1, 2);
                    b.set_member_name ("s");
                    prop (b, g.prop ("size"), l, 1, 2);
                    b.set_member_name ("r");
                    prop (b, g.prop ("roundness"), l);
                    break;
                case "el":
                    b.set_member_name ("p");
                    prop (b, g.prop ("position"), l, 1, 2);
                    b.set_member_name ("s");
                    prop (b, g.prop ("size"), l, 1, 2);
                    break;
                case "sr":
                    b.set_member_name ("sy").add_int_value (g.attr ("star", "true") == "true" ? 1 : 2);
                    b.set_member_name ("p");
                    prop (b, g.prop ("position"), l, 1, 2);
                    b.set_member_name ("pt");
                    prop (b, g.prop ("points"), l);
                    b.set_member_name ("r");
                    prop (b, g.prop ("rotation"), l);
                    b.set_member_name ("or");
                    prop (b, g.prop ("outer-radius"), l);
                    b.set_member_name ("os");
                    prop (b, g.prop ("outer-roundness"), l);
                    b.set_member_name ("ir");
                    prop (b, g.prop ("inner-radius"), l);
                    b.set_member_name ("is");
                    prop (b, g.prop ("inner-roundness"), l);
                    break;
                case "sh":
                    b.set_member_name ("ks");
                    path_prop (b, g.prop ("path"), l);
                    break;
                case "fl":
                    b.set_member_name ("c");
                    prop (b, g.prop ("color"), l, 1, 4);
                    b.set_member_name ("o");
                    prop (b, g.prop ("opacity"), l);
                    b.set_member_name ("r").add_int_value (g.attr ("rule", "nonzero") == "evenodd" ? 2 : 1);
                    break;
                case "st":
                    b.set_member_name ("c");
                    prop (b, g.prop ("color"), l, 1, 4);
                    b.set_member_name ("o");
                    prop (b, g.prop ("opacity"), l);
                    stroke_common (b, g, l);
                    break;
                case "gf":
                    gradient_common (b, g, l);
                    b.set_member_name ("o");
                    prop (b, g.prop ("opacity"), l);
                    b.set_member_name ("r").add_int_value (g.attr ("rule", "nonzero") == "evenodd" ? 2 : 1);
                    break;
                case "gs":
                    gradient_common (b, g, l);
                    b.set_member_name ("o");
                    prop (b, g.prop ("opacity"), l);
                    stroke_common (b, g, l);
                    break;
                case "tm":
                    b.set_member_name ("s");
                    prop (b, g.prop ("start"), l);
                    b.set_member_name ("e");
                    prop (b, g.prop ("end"), l);
                    b.set_member_name ("o");
                    prop (b, g.prop ("offset"), l);
                    b.set_member_name ("m").add_int_value (g.attr ("mode", "simultaneous") == "individually" ? 2 : 1);
                    break;
                case "rp":
                    b.set_member_name ("c");
                    prop (b, g.prop ("copies"), l);
                    b.set_member_name ("o");
                    prop (b, g.prop ("offset"), l);
                    b.set_member_name ("m").add_int_value (g.attr ("composite", "below") == "above" ? 1 : 2);
                    var rt = g.group ("transform");
                    b.set_member_name ("tr");
                    b.begin_object ();
                    b.set_member_name ("ty").add_string_value ("tr");
                    if (rt != null) {
                        b.set_member_name ("p");
                        prop (b, rt.prop ("position"), l, 1, 2);
                        b.set_member_name ("a");
                        prop (b, rt.prop ("anchor"), l, 1, 2);
                        b.set_member_name ("s");
                        prop (b, rt.prop ("scale"), l, 1, 2);
                        b.set_member_name ("r");
                        prop (b, rt.prop ("rotation"), l);
                        b.set_member_name ("so");
                        prop (b, rt.prop ("start-opacity"), l);
                        b.set_member_name ("eo");
                        prop (b, rt.prop ("end-opacity"), l);
                    }
                    b.end_object ();
                    break;
                case "rd":
                    b.set_member_name ("r");
                    prop (b, g.prop ("radius"), l);
                    break;
                case "mm":
                    int mode;
                    switch (g.attr ("mode", "add")) {
                        case "merge": mode = 1; break;
                        case "subtract": mode = 3; break;
                        case "intersect": mode = 4; break;
                        case "exclude": mode = 5; break;
                        default: mode = 2; break;
                    }
                    b.set_member_name ("mm").add_int_value (mode);
                    break;
                case "op":
                    b.set_member_name ("a");
                    prop (b, g.prop ("amount"), l);
                    string join = g.attr ("join", "miter");
                    b.set_member_name ("lj").add_int_value (join == "round" ? 2 : (join == "bevel" ? 3 : 1));
                    b.set_member_name ("ml");
                    prop (b, g.prop ("miter-limit"), l);
                    break;
                case "pb":
                    b.set_member_name ("a");
                    prop (b, g.prop ("amount"), l);
                    break;
                case "tw":
                    b.set_member_name ("a");
                    prop (b, g.prop ("angle"), l);
                    b.set_member_name ("c");
                    prop (b, g.prop ("center"), l, 1, 2);
                    break;
                case "zz":
                    b.set_member_name ("s");
                    prop (b, g.prop ("size"), l);
                    b.set_member_name ("r");
                    prop (b, g.prop ("ridges"), l);
                    b.set_member_name ("pt");
                    b.begin_object ();
                    b.set_member_name ("a").add_int_value (0);
                    b.set_member_name ("k").add_int_value (g.num ("points", 0) > 0.5 ? 2 : 1);
                    b.end_object ();
                    break;
            }
            b.end_object ();
        }

        private string font_name (TextDocument d) {
            string style = d.weight >= 700 ? (d.italic ? "BoldItalic" : "Bold") : (d.italic ? "Italic" : "Regular");
            return d.font.replace (" ", "") + "-" + style;
        }

        private void doc (Json.Builder b, TextDocument d) {
            b.begin_object ();
            var fn = font_name (d);
            fonts.add (fn);
            b.set_member_name ("s").add_double_value (d.size);
            b.set_member_name ("f").add_string_value (fn);
            b.set_member_name ("t").add_string_value (d.all_caps ? d.text.up () : d.text);
            b.set_member_name ("j").add_int_value (d.justify == 1 ? 2 : (d.justify == 2 ? 1 : (d.justify == 3 ? 3 : 0)));
            b.set_member_name ("tr").add_double_value (d.tracking);
            b.set_member_name ("lh").add_double_value (d.leading > 0 ? d.leading : d.size * 1.2);
            b.set_member_name ("ls").add_double_value (d.baseline_shift);
            b.set_member_name ("fc");
            JsonUtil.add_array (b, { Transfer.linear_to_srgb ((float) d.fill[0]), Transfer.linear_to_srgb ((float) d.fill[1]), Transfer.linear_to_srgb ((float) d.fill[2]) });
            if (d.apply_stroke && d.stroke_width > 0) {
                b.set_member_name ("sc");
                JsonUtil.add_array (b, { Transfer.linear_to_srgb ((float) d.stroke[0]), Transfer.linear_to_srgb ((float) d.stroke[1]), Transfer.linear_to_srgb ((float) d.stroke[2]) });
                b.set_member_name ("sw").add_double_value (d.stroke_width);
                b.set_member_name ("of").add_boolean_value (d.fill_over_stroke);
            }
            if (d.is_box ()) {
                b.set_member_name ("sz");
                JsonUtil.add_array (b, { d.box_width, d.box_height });
                b.set_member_name ("ps");
                JsonUtil.add_array (b, { 0, 0 });
            }
            b.end_object ();
        }

        private void text (Json.Builder b, Layer l) {
            var tg = l.text_group;
            b.set_member_name ("t");
            b.begin_object ();
            var src = tg != null ? tg.prop ("source-text") : null;
            b.set_member_name ("d");
            b.begin_object ();
            b.set_member_name ("k");
            b.begin_array ();
            if (src != null && src.keys.size > 0) {
                foreach (var k in src.keys) {
                    b.begin_object ();
                    b.set_member_name ("s");
                    doc (b, k.text ?? new TextDocument ());
                    b.set_member_name ("t").add_double_value (l.comp_time (k.time) * fps);
                    b.end_object ();
                }
            } else {
                b.begin_object ();
                b.set_member_name ("s");
                doc (b, src != null && src.text != null ? src.text : new TextDocument ());
                b.set_member_name ("t").add_double_value (0);
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
            b.set_member_name ("p");
            b.begin_object ();
            var po = tg != null ? tg.group ("path-options") : null;
            if (po != null && po.attr ("mask", "") != "" && l.masks != null) {
                int mi = 0;
                foreach (var c in l.masks.children) {
                    if (c.key == po.attr ("mask")) break;
                    mi++;
                }
                b.set_member_name ("m").add_int_value (mi);
                b.set_member_name ("f");
                prop (b, po.prop ("first-margin"), l);
                b.set_member_name ("l");
                prop (b, po.prop ("last-margin"), l);
                b.set_member_name ("r");
                prop (b, po.prop ("reverse"), l);
                b.set_member_name ("p");
                prop (b, po.prop ("perpendicular"), l);
                b.set_member_name ("a");
                prop (b, po.prop ("force-alignment"), l);
            }
            b.end_object ();
            b.set_member_name ("m");
            b.begin_object ();
            var more = tg != null ? tg.group ("more-options") : null;
            b.set_member_name ("g").add_int_value (more != null ? more.choice ("grouping", 0) + 1 : 1);
            b.set_member_name ("a");
            prop (b, more != null ? more.prop ("grouping-alignment") : null, l, 1, 2);
            b.end_object ();
            b.set_member_name ("a");
            b.begin_array ();
            var animators = tg != null ? tg.group ("animators") : null;
            if (animators != null) foreach (var an in animators.groups_of_type ("text.animator")) animator (b, an, l);
            b.end_array ();
            b.end_object ();
        }

        private void animator (Json.Builder b, PropGroup an, Layer l) {
            b.begin_object ();
            b.set_member_name ("nm").add_string_value (an.name);
            var sels = an.group ("selectors");
            PropGroup? sel = null;
            if (sels != null) foreach (var c in sels.children) {
                var g = c as PropGroup;
                if (g == null) continue;
                if (g.type == "text.selector.range" && sel == null) sel = g;
                else warn (_("Only the first range selector of each text animator is exported to Lottie"));
            }
            b.set_member_name ("s");
            b.begin_object ();
            if (sel != null) {
                b.set_member_name ("t").add_int_value (0);
                string based = sel.attr ("based-on", "characters");
                b.set_member_name ("b").add_int_value (based == "characters-excluding-spaces" ? 2 : (based == "words" ? 3 : (based == "lines" ? 4 : 1)));
                string shape = sel.attr ("shape", "square");
                int sh = shape == "ramp-up" ? 2 : (shape == "ramp-down" ? 3 : (shape == "triangle" ? 4 : (shape == "round" ? 5 : (shape == "smooth" ? 6 : 1))));
                b.set_member_name ("sh").add_int_value (sh);
                b.set_member_name ("r").add_int_value (sel.attr ("units", "percent") == "index" ? 2 : 1);
                b.set_member_name ("rn").add_int_value (sel.attr ("randomize", "false") == "true" ? 1 : 0);
                string mode = sel.attr ("mode", "add");
                b.set_member_name ("m").add_int_value (mode == "subtract" ? 2 : (mode == "intersect" ? 3 : (mode == "min" ? 4 : (mode == "max" ? 5 : (mode == "difference" ? 6 : 1)))));
                b.set_member_name ("s");
                prop (b, sel.prop ("start"), l);
                b.set_member_name ("e");
                prop (b, sel.prop ("end"), l);
                b.set_member_name ("o");
                prop (b, sel.prop ("offset"), l);
                b.set_member_name ("a");
                prop (b, sel.prop ("amount"), l);
                b.set_member_name ("xe");
                prop (b, sel.prop ("ease-high"), l);
                b.set_member_name ("ne");
                prop (b, sel.prop ("ease-low"), l);
            }
            b.end_object ();
            b.set_member_name ("a");
            b.begin_object ();
            var props = an.group ("properties");
            if (props != null) foreach (var c in props.children) {
                var p = c as Property;
                if (p == null) continue;
                switch (p.key) {
                    case "position": b.set_member_name ("p"); prop (b, p, l, 1, 2); break;
                    case "anchor": b.set_member_name ("a"); prop (b, p, l, 1, 2); break;
                    case "scale": b.set_member_name ("s"); prop (b, p, l, 1, 2); break;
                    case "rotation": b.set_member_name ("r"); prop (b, p, l); break;
                    case "skew": b.set_member_name ("sk"); prop (b, p, l); break;
                    case "opacity": b.set_member_name ("o"); prop (b, p, l); break;
                    case "fill-color": b.set_member_name ("fc"); prop (b, p, l, 1, 4); break;
                    case "stroke-color": b.set_member_name ("sc"); prop (b, p, l, 1, 4); break;
                    case "stroke-width": b.set_member_name ("sw"); prop (b, p, l); break;
                    case "tracking": b.set_member_name ("t"); prop (b, p, l); break;
                    default:
                        warn (_("Text animator property “%s” is not supported by Lottie").printf (p.name));
                        break;
                }
            }
            b.end_object ();
            b.end_object ();
        }
    }

    public class LottieImport {
        public Gee.ArrayList<string> warnings = new Gee.ArrayList<string> ();
        private Project project;
        private double fps = 30;
        private Gee.HashMap<string, Json.Object> assets = new Gee.HashMap<string, Json.Object> ();
        private Gee.HashMap<string, Item> made = new Gee.HashMap<string, Item> ();
        private string base_dir = "";

        public LottieImport (Project project) {
            this.project = project;
        }

        public Composition import_text (string text, string base_dir = "") throws Error {
            this.base_dir = base_dir;
            var root = JsonUtil.parse (text).get_object ();
            if (!root.has_member ("layers")) throw new ProjectError.FORMAT (_("This is not a Lottie animation"));
            fps = JsonUtil.num (root, "fr", 30);
            if (root.has_member ("assets"))
                foreach (var e in root.get_array_member ("assets").get_elements ()) {
                    var a = e.get_object ();
                    assets[JsonUtil.str (a, "id")] = a;
                }
            var comp = new Composition (JsonUtil.str (root, "nm", _("Lottie Animation")), (int) JsonUtil.num (root, "w", 512), (int) JsonUtil.num (root, "h", 512), fps,
                                        (JsonUtil.num (root, "op", 60) - JsonUtil.num (root, "ip", 0)) / fps);
            project.add_item (comp);
            build_layers (comp, root.get_array_member ("layers"), 0);
            if (root.has_member ("markers"))
                foreach (var e in root.get_array_member ("markers").get_elements ()) {
                    var m = e.get_object ();
                    comp.markers.add (new Marker (JsonUtil.num (m, "tm") / fps, JsonUtil.str (m, "cm"), JsonUtil.num (m, "dr") / fps));
                }
            return comp;
        }

        public Composition import_file (string path) throws Error {
            string text;
            FileUtils.get_contents (path, out text);
            return import_text (text, Path.get_dirname (path));
        }

        private void warn (string w) {
            if (!warnings.contains (w)) warnings.add (w);
        }

        private void build_layers (Composition comp, Json.Array arr, int depth) {
            var by_ind = new Gee.HashMap<int, Layer> ();
            var parents = new Gee.HashMap<Layer, int> ();
            var order = new Gee.ArrayList<Layer> ();
            var matte_types = new Gee.HashMap<Layer, int> ();
            foreach (var e in arr.get_elements ()) {
                var o = e.get_object ();
                var l = make_layer (comp, o, depth);
                if (l == null) continue;
                int ind = (int) JsonUtil.num (o, "ind", order.size + 1);
                by_ind[ind] = l;
                if (o.has_member ("parent")) parents[l] = (int) JsonUtil.num (o, "parent");
                if (o.has_member ("tt")) matte_types[l] = (int) JsonUtil.num (o, "tt");
                order.add (l);
            }
            foreach (var l in order) {
                l.comp = comp;
                comp.layers.add (l);
            }
            foreach (var kv in parents.entries) {
                var p = by_ind[kv.value];
                if (p != null) kv.key.parent_id = p.id;
            }
            foreach (var kv in matte_types.entries) {
                switch (kv.value) {
                    case 1: kv.key.matte_mode = MatteMode.ALPHA; break;
                    case 2: kv.key.matte_mode = MatteMode.ALPHA_INVERTED; break;
                    case 3: kv.key.matte_mode = MatteMode.LUMA; break;
                    case 4: kv.key.matte_mode = MatteMode.LUMA_INVERTED; break;
                }
            }
        }

        private Layer? make_layer (Composition comp, Json.Object o, int depth) {
            int ty = (int) JsonUtil.num (o, "ty", -1);
            string name = JsonUtil.str (o, "nm", _("Layer"));
            Layer l;
            switch (ty) {
                case 0:
                    var ref_id = JsonUtil.str (o, "refId");
                    var nested = precomp (ref_id, (int) JsonUtil.num (o, "w", comp.width), (int) JsonUtil.num (o, "h", comp.height), depth);
                    if (nested == null) return null;
                    l = Factory.precomp_layer (comp, nested);
                    break;
                case 1:
                    l = Factory.solid (comp, name, hex (JsonUtil.str (o, "sc", "#000000")), (int) JsonUtil.num (o, "sw", 100), (int) JsonUtil.num (o, "sh", 100));
                    break;
                case 2:
                    var f = image (JsonUtil.str (o, "refId"));
                    if (f == null) return null;
                    l = Factory.footage_layer (comp, f);
                    break;
                case 3:
                    l = Factory.null_layer (comp);
                    break;
                case 4:
                    l = Factory.shape_layer (comp, name);
                    if (o.has_member ("shapes")) shapes (l.contents, o.get_array_member ("shapes"), l);
                    break;
                case 5:
                    l = Factory.text_layer (comp, "");
                    text (l, o);
                    break;
                default:
                    warn (_("Lottie layer type %d is not supported").printf (ty));
                    return null;
            }
            l.name = name;
            l.root.name = name;
            l.stretch = JsonUtil.num (o, "sr", 1);
            l.start_time = JsonUtil.num (o, "st", 0) / fps;
            l.in_point = JsonUtil.num (o, "ip", 0) / fps;
            l.out_point = JsonUtil.num (o, "op", comp.duration * fps) / fps;
            l.video = !JsonUtil.bool_of (o, "hd", false);
            l.three_d = JsonUtil.num (o, "ddd", 0) == 1;
            l.blend = LottieExport.blend_from_code ((int) JsonUtil.num (o, "bm", 0));
            if (JsonUtil.num (o, "ao", 0) == 1) l.auto_orient = AutoOrient.ALONG_PATH;
            if (o.has_member ("ks")) transform (l, o.get_object_member ("ks"));
            if (o.has_member ("masksProperties")) masks (l, o.get_array_member ("masksProperties"));
            if (o.has_member ("ef")) warn (_("Lottie effects were not imported"));
            if (ty == 0 && o.has_member ("tm")) {
                l.time_remap = true;
                read_prop (l.root.prop ("time-remap"), o.get_object_member ("tm"), l, 1);
            }
            return l;
        }

        private Composition? precomp (string id, int w, int h, int depth) {
            if (made.has_key (id)) return made[id] as Composition;
            var a = assets[id];
            if (a == null || !a.has_member ("layers") || depth > 12) return null;
            var c = new Composition (JsonUtil.str (a, "nm", id), w, h, fps, 1);
            double maxop = 0;
            foreach (var e in a.get_array_member ("layers").get_elements ()) maxop = double.max (maxop, JsonUtil.num (e.get_object (), "op", 0));
            c.duration = double.max (1.0 / fps, maxop / fps);
            project.add_item (c);
            made[id] = c;
            build_layers (c, a.get_array_member ("layers"), depth + 1);
            return c;
        }

        private Footage? image (string id) {
            if (made.has_key (id)) return made[id] as Footage;
            var a = assets[id];
            if (a == null) return null;
            string p = JsonUtil.str (a, "p");
            string path;
            if (p.has_prefix ("data:")) {
                int comma = p.index_of (",");
                var data = Base64.decode (p.substring (comma + 1));
                var dir = Path.build_filename (Environment.get_user_cache_dir (), "keyframe", "lottie");
                DirUtils.create_with_parents (dir, 0700);
                path = Path.build_filename (dir, "%s.png".printf (Checksum.compute_for_data (ChecksumType.SHA1, data)));
                try {
                    FileUtils.set_data (path, data);
                } catch (Error e) {
                    return null;
                }
            } else {
                path = Path.build_filename (base_dir, JsonUtil.str (a, "u"), p);
            }
            var f = new Footage (path, FootageKind.IMAGE);
            f.width = (int) JsonUtil.num (a, "w");
            f.height = (int) JsonUtil.num (a, "h");
            f.name = JsonUtil.str (a, "nm", id);
            project.add_item (f);
            made[id] = f;
            return f;
        }

        private static double[] hex (string s) {
            var h = s.has_prefix ("#") ? s.substring (1) : s;
            if (h.length < 6) return { 0, 0, 0, 1 };
            double[] r = { 0, 0, 0, 1 };
            for (int i = 0; i < 3; i++) {
                uint64 v;
                uint64.try_parse (h.substring (i * 2, 2), out v, null, 16);
                r[i] = Transfer.srgb_to_linear ((float) (v / 255.0));
            }
            return r;
        }

        private double[] lot_value (Json.Node n) {
            if (n.get_node_type () == Json.NodeType.ARRAY) return JsonUtil.node_array (n);
            return { n.get_value_type () == typeof (int64) ? (double) n.get_int () : n.get_double () };
        }

        private double first_of (Json.Object o, string key, double fallback) {
            if (!o.has_member (key)) return fallback;
            var n = o.get_member (key);
            if (n.get_node_type () == Json.NodeType.ARRAY) {
                var a = JsonUtil.node_array (n);
                return a.length > 0 ? a[0] : fallback;
            }
            return JsonUtil.num (o, key, fallback);
        }

        private double[] adapt (Property p, double[] v) {
            var r = new double[p.dims];
            for (int i = 0; i < p.dims; i++) r[i] = i < v.length ? v[i] : (p.kind == PropKind.COLOR && i == 3 ? 1 : (i < p.value.length ? p.value[i] : 0));
            if (p.kind == PropKind.COLOR) for (int i = 0; i < 3 && i < v.length; i++) r[i] = Transfer.srgb_to_linear ((float) v[i].clamp (0, 1));
            return r;
        }

        public void read_prop (Property? p, Json.Object o, Layer? l, double scale = 1) {
            if (p == null) return;
            if (o.has_member ("x")) p.expression = JsonUtil.str (o, "x");
            var k = o.get_member ("k");
            bool animated = JsonUtil.num (o, "a", 0) == 1;
            if (!animated && k.get_node_type () == Json.NodeType.ARRAY) {
                var arr = k.get_array ();
                if (arr.get_length () > 0 && arr.get_element (0).get_node_type () == Json.NodeType.OBJECT && arr.get_element (0).get_object ().has_member ("t")) animated = true;
            }
            if (!animated) {
                var v = lot_value (k);
                for (int i = 0; i < v.length; i++) v[i] *= scale;
                p.value = adapt (p, v);
                return;
            }
            var arr = k.get_array ();
            double[]? prev_end = null;
            Keyframe? prev = null;
            for (uint i = 0; i < arr.get_length (); i++) {
                var ko = arr.get_element (i).get_object ();
                double t = JsonUtil.num (ko, "t") / fps;
                double lt = l != null ? l.layer_time (t) : t;
                double[] v;
                if (ko.has_member ("s")) v = lot_value (ko.get_member ("s"));
                else if (prev_end != null) v = prev_end;
                else continue;
                for (int c = 0; c < v.length; c++) v[c] *= scale;
                var key = new Keyframe (lt);
                key.value = adapt (p, v);
                key.spatial_auto = false;
                key.tangent_in = new double[p.dims];
                key.tangent_out = new double[p.dims];
                if (prev != null && prev.out_interp != Interp.HOLD) {
                    key.in_interp = prev_in_interp;
                    key.ease_in_x = prev_in_x;
                    key.ease_in_y = prev_in_y;
                    if (p.spatial && prev_ti != null) key.tangent_in = adapt_raw (p, prev_ti);
                }
                p.keys.add (key);
                apply_ease (ko, key, p);
                prev_end = ko.has_member ("e") ? lot_value (ko.get_member ("e")) : null;
                if (prev_end != null) for (int c = 0; c < prev_end.length; c++) prev_end[c] *= scale;
                prev = key;
            }
            p.sort_keys ();
        }

        private Interp prev_in_interp = Interp.LINEAR;
        private double prev_in_x = 1;
        private double prev_in_y = 1;
        private double[]? prev_ti = null;

        private double[] adapt_raw (Property p, double[] v) {
            var r = new double[p.dims];
            for (int i = 0; i < p.dims && i < v.length; i++) r[i] = v[i];
            return r;
        }

        private void apply_ease (Json.Object ko, Keyframe key, Property p) {
            if (JsonUtil.num (ko, "h", 0) == 1) {
                key.out_interp = Interp.HOLD;
                prev_in_interp = Interp.LINEAR;
                prev_ti = null;
                return;
            }
            double ox = 0, oy = 0, ix = 1, iy = 1;
            if (ko.has_member ("o")) {
                var o = ko.get_object_member ("o");
                ox = first_of (o, "x", 0);
                oy = first_of (o, "y", 0);
            }
            if (ko.has_member ("i")) {
                var i = ko.get_object_member ("i");
                ix = first_of (i, "x", 1);
                iy = first_of (i, "y", 1);
            }
            bool linear = (ox - oy).abs () < 1e-6 && (ix - iy).abs () < 1e-6;
            key.out_interp = linear ? Interp.LINEAR : Interp.BEZIER;
            key.ease_out_x = ox;
            key.ease_out_y = oy;
            prev_in_interp = linear ? Interp.LINEAR : Interp.BEZIER;
            prev_in_x = ix;
            prev_in_y = iy;
            if (ko.has_member ("to")) key.tangent_out = adapt_raw (p, JsonUtil.node_array (ko.get_member ("to")));
            prev_ti = ko.has_member ("ti") ? JsonUtil.node_array (ko.get_member ("ti")) : null;
        }

        private BezPath read_path (Json.Object o) {
            var p = new BezPath ();
            p.closed = JsonUtil.bool_of (o, "c", false);
            if (!o.has_member ("v")) return p;
            var vs = o.get_array_member ("v");
            var ins = o.has_member ("i") ? o.get_array_member ("i") : null;
            var outs = o.has_member ("o") ? o.get_array_member ("o") : null;
            for (uint i = 0; i < vs.get_length (); i++) {
                var v = JsonUtil.node_array (vs.get_element (i));
                var iv = ins != null && i < ins.get_length () ? JsonUtil.node_array (ins.get_element (i)) : new double[] { 0, 0 };
                var ov = outs != null && i < outs.get_length () ? JsonUtil.node_array (outs.get_element (i)) : new double[] { 0, 0 };
                p.add (v[0], v[1], iv[0], iv[1], ov[0], ov[1]);
            }
            return p;
        }

        public void read_path_prop (Property? p, Json.Object o, Layer? l) {
            if (p == null) return;
            var k = o.get_member ("k");
            if (k.get_node_type () == Json.NodeType.OBJECT) {
                p.path = read_path (k.get_object ());
                return;
            }
            var arr = k.get_array ();
            Json.Object? prev_e = null;
            Keyframe? prev = null;
            for (uint i = 0; i < arr.get_length (); i++) {
                var ko = arr.get_element (i).get_object ();
                double t = JsonUtil.num (ko, "t") / fps;
                Json.Object? sv = null;
                if (ko.has_member ("s")) {
                    var sn = ko.get_member ("s");
                    sv = sn.get_node_type () == Json.NodeType.ARRAY ? sn.get_array ().get_element (0).get_object () : sn.get_object ();
                } else if (prev_e != null) {
                    sv = prev_e;
                }
                if (sv == null) continue;
                var key = new Keyframe (l != null ? l.layer_time (t) : t);
                key.path = read_path (sv);
                if (prev != null && prev.out_interp != Interp.HOLD) {
                    key.in_interp = prev_in_interp;
                    key.ease_in_x = prev_in_x;
                    key.ease_in_y = prev_in_y;
                }
                apply_ease (ko, key, p);
                p.keys.add (key);
                if (ko.has_member ("e")) {
                    var en = ko.get_member ("e");
                    prev_e = en.get_node_type () == Json.NodeType.ARRAY ? en.get_array ().get_element (0).get_object () : en.get_object ();
                } else {
                    prev_e = null;
                }
                prev = key;
            }
            p.sort_keys ();
        }

        private void transform (Layer l, Json.Object ks) {
            var t = l.transform;
            if (ks.has_member ("o")) read_prop (t.prop ("opacity"), ks.get_object_member ("o"), l);
            if (ks.has_member ("r")) read_prop (t.prop ("rotation"), ks.get_object_member ("r"), l);
            if (ks.has_member ("rz")) read_prop (t.prop ("rotation"), ks.get_object_member ("rz"), l);
            if (ks.has_member ("p")) {
                var po = ks.get_object_member ("p");
                if (JsonUtil.bool_of (po, "s", false)) {
                    var px = new Property ("x", "x", PropKind.SCALAR, { 0 });
                    var py = new Property ("y", "y", PropKind.SCALAR, { 0 });
                    if (po.has_member ("x")) read_prop (px, po.get_object_member ("x"), l);
                    if (po.has_member ("y")) read_prop (py, po.get_object_member ("y"), l);
                    var pp = t.prop ("position");
                    if (px.keys.size == 0 && py.keys.size == 0) pp.value = { px.value[0], py.value[0], 0 };
                    else {
                        var times = new Gee.TreeSet<double?> ((a, b) => a < b ? -1 : (a > b ? 1 : 0));
                        foreach (var k in px.keys) times.add (k.time);
                        foreach (var k in py.keys) times.add (k.time);
                        foreach (var tt in times) {
                            var k = pp.set_key (tt, { px.raw_value_at (tt)[0], py.raw_value_at (tt)[0], 0 });
                            k.spatial_auto = false;
                        }
                    }
                    warn (_("Separated position dimensions were merged"));
                } else {
                    read_prop (t.prop ("position"), po, l);
                }
            }
            if (ks.has_member ("a")) read_prop (t.prop ("anchor"), ks.get_object_member ("a"), l);
            if (ks.has_member ("s")) read_prop (t.prop ("scale"), ks.get_object_member ("s"), l);
            if (ks.has_member ("sk")) read_prop (t.prop ("skew"), ks.get_object_member ("sk"), l);
            if (ks.has_member ("sa")) read_prop (t.prop ("skew-axis"), ks.get_object_member ("sa"), l);
            if (ks.has_member ("rx")) read_prop (t.prop ("rotation-x"), ks.get_object_member ("rx"), l);
            if (ks.has_member ("ry")) read_prop (t.prop ("rotation-y"), ks.get_object_member ("ry"), l);
            if (ks.has_member ("or")) read_prop (t.prop ("orientation"), ks.get_object_member ("or"), l);
        }

        private void masks (Layer l, Json.Array arr) {
            foreach (var e in arr.get_elements ()) {
                var o = e.get_object ();
                string mode;
                switch (JsonUtil.str (o, "mode", "a")) {
                    case "s": mode = "subtract"; break;
                    case "i": mode = "intersect"; break;
                    case "l": mode = "lighten"; break;
                    case "d": mode = "darken"; break;
                    case "f": mode = "difference"; break;
                    case "n": mode = "none"; break;
                    default: mode = "add"; break;
                }
                var g = Factory.mask (new BezPath (), mode);
                g.name = JsonUtil.str (o, "nm", g.name);
                g.key = l.masks.unique_key ("mask");
                g.attrs["inverted"] = JsonUtil.bool_of (o, "inv", false) ? "true" : "false";
                if (o.has_member ("pt")) read_path_prop (g.prop ("path"), o.get_object_member ("pt"), l);
                if (o.has_member ("o")) read_prop (g.prop ("opacity"), o.get_object_member ("o"), l);
                if (o.has_member ("x")) read_prop (g.prop ("expansion"), o.get_object_member ("x"), l);
                if (o.has_member ("f")) read_prop (g.prop ("feather"), o.get_object_member ("f"), l);
                l.masks.add<PropGroup> (g);
            }
        }

        private void shapes (PropGroup into, Json.Array arr, Layer l) {
            foreach (var e in arr.get_elements ()) {
                var o = e.get_object ();
                var g = shape (o, l);
                if (g == null) continue;
                g.key = into.unique_key (g.key);
                into.add<PropGroup> (g);
            }
        }

        private void stops (PropGroup g, Json.Object go) {
            int n = (int) JsonUtil.num (go, "p", 2);
            var k = go.get_object_member ("k");
            if (JsonUtil.num (k, "a", 0) == 1) {
                warn (_("Animated gradient colours were imported as their first value"));
                var first = k.get_array_member ("k").get_element (0).get_object ();
                k = new Json.Object ();
                k.set_member ("k", first.get_member ("s"));
            }
            var v = JsonUtil.node_array (k.get_member ("k"));
            var r = new double[n * 5];
            for (int i = 0; i < n && i * 4 + 3 < v.length; i++) {
                r[i * 5] = v[i * 4];
                for (int c = 1; c < 4; c++) r[i * 5 + c] = Transfer.srgb_to_linear ((float) v[i * 4 + c]);
                r[i * 5 + 4] = 1;
                if (v.length >= n * 4 + n * 2) r[i * 5 + 4] = v[n * 4 + i * 2 + 1];
            }
            g.prop ("stops").value = r;
        }

        private PropGroup? shape (Json.Object o, Layer l) {
            string ty = JsonUtil.str (o, "ty");
            PropGroup? g = null;
            switch (ty) {
                case "gr":
                    g = Factory.shape_group (JsonUtil.str (o, "nm", _("Group")));
                    if (o.has_member ("it")) {
                        var contents = g.group ("contents");
                        foreach (var e in o.get_array_member ("it").get_elements ()) {
                            var io = e.get_object ();
                            if (JsonUtil.str (io, "ty") == "tr") {
                                var tr = g.group ("transform");
                                if (io.has_member ("p")) read_prop (tr.prop ("position"), io.get_object_member ("p"), l);
                                if (io.has_member ("a")) read_prop (tr.prop ("anchor"), io.get_object_member ("a"), l);
                                if (io.has_member ("s")) read_prop (tr.prop ("scale"), io.get_object_member ("s"), l);
                                if (io.has_member ("r")) read_prop (tr.prop ("rotation"), io.get_object_member ("r"), l);
                                if (io.has_member ("o")) read_prop (tr.prop ("opacity"), io.get_object_member ("o"), l);
                                if (io.has_member ("sk")) read_prop (tr.prop ("skew"), io.get_object_member ("sk"), l);
                                if (io.has_member ("sa")) read_prop (tr.prop ("skew-axis"), io.get_object_member ("sa"), l);
                                continue;
                            }
                            var child = shape (io, l);
                            if (child == null) continue;
                            child.key = contents.unique_key (child.key);
                            contents.add<PropGroup> (child);
                        }
                    }
                    break;
                case "rc":
                    g = Factory.rect (100, 100);
                    rd (g, o, "p", "position", l);
                    rd (g, o, "s", "size", l);
                    rd (g, o, "r", "roundness", l);
                    break;
                case "el":
                    g = Factory.ellipse (100, 100);
                    rd (g, o, "p", "position", l);
                    rd (g, o, "s", "size", l);
                    break;
                case "sr":
                    g = Factory.star (JsonUtil.num (o, "sy", 1) == 2, 5, 100, 50);
                    rd (g, o, "p", "position", l);
                    rd (g, o, "pt", "points", l);
                    rd (g, o, "r", "rotation", l);
                    rd (g, o, "or", "outer-radius", l);
                    rd (g, o, "os", "outer-roundness", l);
                    rd (g, o, "ir", "inner-radius", l);
                    rd (g, o, "is", "inner-roundness", l);
                    break;
                case "sh":
                    g = Factory.path_shape (new BezPath ());
                    if (o.has_member ("ks")) read_path_prop (g.prop ("path"), o.get_object_member ("ks"), l);
                    break;
                case "fl":
                    g = Factory.fill ({ 1, 1, 1, 1 });
                    rd (g, o, "c", "color", l);
                    rd (g, o, "o", "opacity", l);
                    if (JsonUtil.num (o, "r", 1) == 2) g.attrs["rule"] = "evenodd";
                    break;
                case "st":
                case "gs":
                    g = ty == "st" ? Factory.stroke ({ 1, 1, 1, 1 }, 1) : Factory.gradient_stroke (1);
                    if (ty == "st") rd (g, o, "c", "color", l);
                    rd (g, o, "o", "opacity", l);
                    rd (g, o, "w", "width", l);
                    int lc = (int) JsonUtil.num (o, "lc", 1), lj = (int) JsonUtil.num (o, "lj", 1);
                    g.attrs["cap"] = lc == 2 ? "round" : (lc == 3 ? "square" : "butt");
                    g.attrs["join"] = lj == 2 ? "round" : (lj == 3 ? "bevel" : "miter");
                    if (o.has_member ("ml")) g.prop ("miter-limit").value = { JsonUtil.num (o, "ml", 4) };
                    if (o.has_member ("d")) foreach (var de in o.get_array_member ("d").get_elements ()) {
                        var d = de.get_object ();
                        string n = JsonUtil.str (d, "n");
                        string key = n == "d" ? "dash" : (n == "g" ? "gap" : "dash-offset");
                        if (d.has_member ("v")) read_prop (g.prop (key), d.get_object_member ("v"), l);
                    }
                    if (ty == "gs") gradient (g, o, l);
                    break;
                case "gf":
                    g = Factory.gradient_fill ();
                    rd (g, o, "o", "opacity", l);
                    gradient (g, o, l);
                    if (JsonUtil.num (o, "r", 1) == 2) g.attrs["rule"] = "evenodd";
                    break;
                case "tm":
                    g = Factory.trim ();
                    rd (g, o, "s", "start", l);
                    rd (g, o, "e", "end", l);
                    rd (g, o, "o", "offset", l);
                    if (JsonUtil.num (o, "m", 1) == 2) g.attrs["mode"] = "individually";
                    break;
                case "rp":
                    g = Factory.repeater (3);
                    rd (g, o, "c", "copies", l);
                    rd (g, o, "o", "offset", l);
                    g.attrs["composite"] = JsonUtil.num (o, "m", 1) == 1 ? "above" : "below";
                    if (o.has_member ("tr")) {
                        var tro = o.get_object_member ("tr");
                        var rt = g.group ("transform");
                        rd (rt, tro, "p", "position", l);
                        rd (rt, tro, "a", "anchor", l);
                        rd (rt, tro, "s", "scale", l);
                        rd (rt, tro, "r", "rotation", l);
                        rd (rt, tro, "so", "start-opacity", l);
                        rd (rt, tro, "eo", "end-opacity", l);
                    }
                    break;
                case "rd":
                    g = Factory.round_corners (0);
                    rd (g, o, "r", "radius", l);
                    break;
                case "mm":
                    g = Factory.merge ();
                    string[] modes = { "add", "merge", "add", "subtract", "intersect", "exclude" };
                    int mm = (int) JsonUtil.num (o, "mm", 2);
                    g.attrs["mode"] = mm >= 0 && mm < modes.length ? modes[mm] : "add";
                    break;
                case "op":
                    g = Factory.offset_paths ();
                    rd (g, o, "a", "amount", l);
                    rd (g, o, "ml", "miter-limit", l);
                    int oj = (int) JsonUtil.num (o, "lj", 1);
                    g.attrs["join"] = oj == 2 ? "round" : (oj == 3 ? "bevel" : "miter");
                    break;
                case "pb":
                    g = Factory.pucker_bloat ();
                    rd (g, o, "a", "amount", l);
                    break;
                case "tw":
                    g = Factory.twist ();
                    rd (g, o, "a", "angle", l);
                    rd (g, o, "c", "center", l);
                    break;
                case "zz":
                    g = Factory.zigzag ();
                    rd (g, o, "s", "size", l);
                    rd (g, o, "r", "ridges", l);
                    break;
                default:
                    warn (_("Lottie shape item “%s” is not supported").printf (ty));
                    return null;
            }
            g.name = JsonUtil.str (o, "nm", g.name);
            g.enabled = !JsonUtil.bool_of (o, "hd", false);
            if (o.has_member ("d") && ty != "st" && ty != "gs") g.attrs["direction"] = ((int) JsonUtil.num (o, "d", 1)).to_string ();
            return g;
        }

        private void gradient (PropGroup g, Json.Object o, Layer l) {
            g.attrs["gradient"] = JsonUtil.num (o, "t", 1) == 2 ? "radial" : "linear";
            rd (g, o, "s", "start", l);
            rd (g, o, "e", "end", l);
            rd (g, o, "h", "highlight-length", l);
            rd (g, o, "a", "highlight-angle", l);
            if (o.has_member ("g")) stops (g, o.get_object_member ("g"));
        }

        private void rd (PropGroup g, Json.Object o, string member, string key, Layer l) {
            if (!o.has_member (member)) return;
            var n = o.get_member (member);
            if (n.get_node_type () != Json.NodeType.OBJECT) return;
            read_prop (g.prop (key), n.get_object (), l);
        }

        private TextDocument read_doc (Json.Object s) {
            var d = new TextDocument ();
            d.text = JsonUtil.str (s, "t", "").replace ("\r", "\n");
            d.size = JsonUtil.num (s, "s", 36);
            var f = JsonUtil.str (s, "f", "Sans");
            var fparts = f.split ("-", 2);
            d.font = fparts[0];
            d.weight = f.contains ("Bold") ? 700 : 400;
            d.italic = f.contains ("Italic");
            int j = (int) JsonUtil.num (s, "j", 0);
            d.justify = j == 2 ? 1 : (j == 1 ? 2 : (j == 3 ? 3 : 0));
            d.tracking = JsonUtil.num (s, "tr", 0);
            d.leading = JsonUtil.num (s, "lh", 0);
            if (s.has_member ("fc")) {
                var c = JsonUtil.node_array (s.get_member ("fc"));
                d.fill = { Transfer.srgb_to_linear ((float) c[0]), Transfer.srgb_to_linear ((float) c[1]), Transfer.srgb_to_linear ((float) c[2]), 1 };
            }
            if (s.has_member ("sc")) {
                var c = JsonUtil.node_array (s.get_member ("sc"));
                d.stroke = { Transfer.srgb_to_linear ((float) c[0]), Transfer.srgb_to_linear ((float) c[1]), Transfer.srgb_to_linear ((float) c[2]), 1 };
                d.stroke_width = JsonUtil.num (s, "sw", 0);
                d.apply_stroke = d.stroke_width > 0;
                d.fill_over_stroke = JsonUtil.bool_of (s, "of", true);
            }
            if (s.has_member ("sz")) {
                var sz = JsonUtil.node_array (s.get_member ("sz"));
                d.box_width = sz[0];
                d.box_height = sz.length > 1 ? sz[1] : 0;
            }
            return d;
        }

        private void text (Layer l, Json.Object o) {
            if (!o.has_member ("t")) return;
            var t = o.get_object_member ("t");
            var tg = l.text_group;
            var src = tg.prop ("source-text");
            if (t.has_member ("d")) {
                var ks = t.get_object_member ("d").get_array_member ("k");
                var docs = ks.get_elements ();
                if (docs.length () == 1) {
                    src.text = read_doc (docs.data.get_object ().get_object_member ("s"));
                } else {
                    foreach (var e in docs) {
                        var ko = e.get_object ();
                        src.set_text_key (l.layer_time (JsonUtil.num (ko, "t") / fps), read_doc (ko.get_object_member ("s")));
                    }
                }
                l.name = src.text_at (0).text.length > 24 ? src.text_at (0).text.substring (0, 24) : src.text_at (0).text;
            }
            if (t.has_member ("a")) {
                var animators = tg.group ("animators");
                foreach (var e in t.get_array_member ("a").get_elements ()) {
                    var ao = e.get_object ();
                    var an = Factory.text_animator (JsonUtil.str (ao, "nm", _("Animator")));
                    an.key = animators.unique_key ("animator");
                    if (ao.has_member ("s")) {
                        var so = ao.get_object_member ("s");
                        var sel = Factory.range_selector ();
                        int bsel = (int) JsonUtil.num (so, "b", 1);
                        sel.attrs["based-on"] = bsel == 2 ? "characters-excluding-spaces" : (bsel == 3 ? "words" : (bsel == 4 ? "lines" : "characters"));
                        string[] shapes_ids = { "square", "square", "ramp-up", "ramp-down", "triangle", "round", "smooth" };
                        int sh = (int) JsonUtil.num (so, "sh", 1);
                        sel.attrs["shape"] = sh >= 0 && sh < shapes_ids.length ? shapes_ids[sh] : "square";
                        sel.attrs["units"] = JsonUtil.num (so, "r", 1) == 2 ? "index" : "percent";
                        sel.attrs["randomize"] = JsonUtil.num (so, "rn", 0) == 1 ? "true" : "false";
                        string[] modes = { "add", "add", "subtract", "intersect", "min", "max", "difference" };
                        int m = (int) JsonUtil.num (so, "m", 1);
                        sel.attrs["mode"] = m >= 0 && m < modes.length ? modes[m] : "add";
                        rd (sel, so, "s", "start", l);
                        rd (sel, so, "e", "end", l);
                        rd (sel, so, "o", "offset", l);
                        rd (sel, so, "a", "amount", l);
                        rd (sel, so, "xe", "ease-high", l);
                        rd (sel, so, "ne", "ease-low", l);
                        an.group ("selectors").add<PropGroup> (sel);
                    }
                    if (ao.has_member ("a")) {
                        var po = ao.get_object_member ("a");
                        string[,] map = { { "p", "position" }, { "a", "anchor" }, { "s", "scale" }, { "r", "rotation" }, { "sk", "skew" }, { "o", "opacity" },
                                          { "fc", "fill-color" }, { "sc", "stroke-color" }, { "sw", "stroke-width" }, { "t", "tracking" } };
                        for (int i = 0; i < map.length[0]; i++) {
                            if (!po.has_member (map[i, 0])) continue;
                            var p = Factory.animator_property (map[i, 1]);
                            read_prop (p, po.get_object_member (map[i, 0]), l);
                            an.group ("properties").add<Property> (p);
                        }
                    }
                    animators.add<PropGroup> (an);
                }
            }
        }
    }
}
