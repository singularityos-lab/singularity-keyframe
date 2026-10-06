namespace Singularity.Apps.Keyframe {

    namespace Factory {

        public Property scalar (string key, string name, double v) {
            return new Property (key, name, PropKind.SCALAR, { v });
        }

        public Property percent (string key, string name, double v) {
            return new Property (key, name, PropKind.PERCENT, { v });
        }

        public Property angle (string key, string name, double v) {
            return new Property (key, name, PropKind.ANGLE, { v });
        }

        public Property vec (string key, string name, double[] v) {
            return new Property (key, name, PropKind.VECTOR, v);
        }

        public Property point (string key, string name, double[] v) {
            return new Property (key, name, PropKind.POINT, v);
        }

        public Property color (string key, string name, double[] v) {
            return new Property (key, name, PropKind.COLOR, v);
        }

        public Property choice (string key, string name, string[] choices, int v = 0) {
            return new Property (key, name, PropKind.CHOICE, { v }).with_choices (choices);
        }

        public Property toggle (string key, string name, bool v) {
            return new Property (key, name, PropKind.TOGGLE, { v ? 1 : 0 }).range (0, 1);
        }

        public Property layer_ref (string key, string name) {
            return new Property (key, name, PropKind.LAYER, { -1 });
        }

        public PropGroup transform_group (double[] anchor, double[] position) {
            var g = new PropGroup ("transform", "transform", _("Transform"));
            g.add<Property> (point ("anchor", _("Anchor Point"), anchor));
            g.add<Property> (point ("position", _("Position"), position));
            g.add<Property> (vec ("scale", _("Scale"), { 100, 100, 100 }));
            g.add<Property> (vec ("orientation", _("Orientation"), { 0, 0, 0 }));
            g.add<Property> (angle ("rotation-x", _("X Rotation"), 0));
            g.add<Property> (angle ("rotation-y", _("Y Rotation"), 0));
            g.add<Property> (angle ("rotation", _("Rotation"), 0));
            g.add<Property> (scalar ("skew", _("Skew"), 0).range (-85, 85));
            g.add<Property> (angle ("skew-axis", _("Skew Axis"), 0));
            g.add<Property> (percent ("opacity", _("Opacity"), 100).range (0, 100));
            return g;
        }

        public PropGroup material_group () {
            var g = new PropGroup ("material", "material", _("Material Options"));
            g.add<Property> (toggle ("accepts-lights", _("Accepts Lights"), true));
            g.add<Property> (toggle ("accepts-shadows", _("Accepts Shadows"), true));
            g.add<Property> (choice ("casts-shadows", _("Casts Shadows"), { _("Off"), _("On"), _("Only") }, 0));
            g.add<Property> (percent ("ambient", _("Ambient"), 100).range (0, 100));
            g.add<Property> (percent ("diffuse", _("Diffuse"), 50).range (0, 100));
            g.add<Property> (percent ("specular", _("Specular Intensity"), 50).range (0, 100));
            g.add<Property> (percent ("shininess", _("Specular Shininess"), 5).range (0, 100));
            g.add<Property> (percent ("metal", _("Metal"), 100).range (0, 100));
            return g;
        }

        private Layer base_layer (Composition comp, LayerKind kind, string name, double[] anchor, double[] position) {
            var l = new Layer (kind, comp.unique_layer_name (name));
            l.in_point = 0;
            l.out_point = comp.duration;
            l.comp = comp;
            l.root.add<PropGroup> (new PropGroup ("masks", "masks", _("Masks")));
            l.root.add<PropGroup> (transform_group (anchor, position));
            l.root.add<PropGroup> (new PropGroup ("effects", "effects", _("Effects")));
            l.root.add<PropGroup> (material_group ());
            var remap = scalar ("time-remap", _("Time Remap"), 0);
            remap.unit = "s";
            l.root.add<Property> (remap);
            var audio = new PropGroup ("audio", "audio", _("Audio"));
            audio.add<Property> (vec ("levels", _("Audio Levels"), { 0, 0 }).ui_range (-48, 12));
            l.root.add<PropGroup> (audio);
            return l;
        }

        public Layer solid (Composition comp, string name, double[] rgba, int w = 0, int h = 0) {
            int sw = w > 0 ? w : comp.width, sh = h > 0 ? h : comp.height;
            var l = base_layer (comp, LayerKind.SOLID, name, { sw / 2.0, sh / 2.0, 0 }, { comp.width / 2.0, comp.height / 2.0, 0 });
            l.solid_color = rgba;
            l.solid_width = sw;
            l.solid_height = sh;
            return l;
        }

        public Layer adjustment (Composition comp) {
            var l = solid (comp, _("Adjustment Layer"), { 1, 1, 1, 1 });
            l.adjustment = true;
            return l;
        }

        public Layer null_layer (Composition comp) {
            var l = base_layer (comp, LayerKind.NULL, _("Null"), { 50, 50, 0 }, { comp.width / 2.0, comp.height / 2.0, 0 });
            l.solid_width = 100;
            l.solid_height = 100;
            return l;
        }

        public Layer shape_layer (Composition comp, string name = "") {
            var l = base_layer (comp, LayerKind.SHAPE, name == "" ? _("Shape Layer") : name, { 0, 0, 0 }, { comp.width / 2.0, comp.height / 2.0, 0 });
            l.root.insert (1, new PropGroup ("contents", "contents", _("Contents")));
            return l;
        }

        public Layer text_layer (Composition comp, string text) {
            string label = text.length > 24 ? text.substring (0, 24) : text;
            if (label.strip () == "") label = _("Text");
            var l = base_layer (comp, LayerKind.TEXT, label, { 0, 0, 0 }, { comp.width / 2.0, comp.height / 2.0, 0 });
            var doc = new TextDocument ();
            doc.text = text;
            doc.size = double.max (12, comp.height / 12.0);
            doc.justify = 1;
            var tg = new PropGroup ("text", "text", _("Text"));
            tg.add<Property> (new Property.with_text ("source-text", _("Source Text"), doc));
            var po = new PropGroup ("text.path", "path-options", _("Path Options"));
            po.attrs["mask"] = "";
            po.add<Property> (toggle ("reverse", _("Reverse Path"), false));
            po.add<Property> (toggle ("perpendicular", _("Perpendicular To Path"), true));
            po.add<Property> (toggle ("force-alignment", _("Force Alignment"), false));
            po.add<Property> (scalar ("first-margin", _("First Margin"), 0));
            po.add<Property> (scalar ("last-margin", _("Last Margin"), 0));
            tg.add<PropGroup> (po);
            var more = new PropGroup ("text.more", "more-options", _("More Options"));
            more.add<Property> (choice ("grouping", _("Anchor Point Grouping"), { _("Character"), _("Word"), _("Line"), _("All") }, 0));
            more.add<Property> (vec ("grouping-alignment", _("Grouping Alignment"), { 0, 0 }));
            tg.add<PropGroup> (more);
            tg.add<PropGroup> (new PropGroup ("text.animators", "animators", _("Animators")));
            l.root.insert (1, tg);
            return l;
        }

        public Layer footage_layer (Composition comp, Footage f) {
            int w = f.width > 0 ? f.width : comp.width, h = f.height > 0 ? f.height : comp.height;
            var kind = f.kind == FootageKind.AUDIO ? LayerKind.AUDIO : (f.kind == FootageKind.MODEL ? LayerKind.MODEL : LayerKind.FOOTAGE);
            var l = base_layer (comp, kind, f.name, { w / 2.0, h / 2.0, 0 }, { comp.width / 2.0, comp.height / 2.0, 0 });
            l.source_id = f.id;
            l.solid_width = w;
            l.solid_height = h;
            if (f.kind == FootageKind.VIDEO || f.kind == FootageKind.AUDIO || f.kind == FootageKind.SEQUENCE) {
                if (f.duration > 0) l.out_point = double.min (comp.duration, f.duration);
            }
            if (f.kind == FootageKind.MODEL) {
                l.three_d = true;
                var mg = new PropGroup ("model", "model", _("Model"));
                mg.add<Property> (vec ("model-scale", _("Model Scale"), { 100 }));
                mg.add<Property> (color ("tint", _("Tint"), { 1, 1, 1, 1 }));
                mg.add<Property> (choice ("shading", _("Shading"), { _("Lit"), _("Flat") }, 0));
                l.root.insert (1, mg);
                l.transform.prop ("anchor").value = { 0, 0, 0 };
            }
            return l;
        }

        public Layer precomp_layer (Composition comp, Composition nested) {
            var l = base_layer (comp, LayerKind.PRECOMP, nested.name, { nested.width / 2.0, nested.height / 2.0, 0 }, { comp.width / 2.0, comp.height / 2.0, 0 });
            l.source_id = nested.id;
            l.solid_width = nested.width;
            l.solid_height = nested.height;
            l.out_point = double.min (comp.duration, nested.duration);
            return l;
        }

        public Layer camera (Composition comp, double focal_mm = 50) {
            double film = 36;
            double zoom = comp.width * focal_mm / film;
            var l = new Layer (LayerKind.CAMERA, comp.unique_layer_name (_("Camera")));
            l.in_point = 0;
            l.out_point = comp.duration;
            l.comp = comp;
            l.three_d = true;
            var t = new PropGroup ("transform", "transform", _("Transform"));
            t.add<Property> (point ("point-of-interest", _("Point of Interest"), { comp.width / 2.0, comp.height / 2.0, 0 }));
            t.add<Property> (point ("position", _("Position"), { comp.width / 2.0, comp.height / 2.0, -zoom }));
            t.add<Property> (vec ("orientation", _("Orientation"), { 0, 0, 0 }));
            t.add<Property> (angle ("rotation-x", _("X Rotation"), 0));
            t.add<Property> (angle ("rotation-y", _("Y Rotation"), 0));
            t.add<Property> (angle ("rotation", _("Z Rotation"), 0));
            t.add<Property> (point ("anchor", _("Anchor Point"), { 0, 0, 0 }));
            t.add<Property> (vec ("scale", _("Scale"), { 100, 100, 100 }));
            t.add<Property> (percent ("opacity", _("Opacity"), 100));
            l.root.add<PropGroup> (t);
            var c = new PropGroup ("camera", "camera", _("Camera Options"));
            c.add<Property> (scalar ("zoom", _("Zoom"), zoom).range (1, 100000));
            c.add<Property> (toggle ("dof", _("Depth of Field"), false));
            c.add<Property> (scalar ("focus-distance", _("Focus Distance"), zoom).range (1, 100000));
            c.add<Property> (scalar ("aperture", _("Aperture"), 25).range (0, 2000));
            c.add<Property> (percent ("blur-level", _("Blur Level"), 100).range (0, 1000));
            c.attrs["one-node"] = "false";
            l.root.add<PropGroup> (c);
            l.root.add<PropGroup> (new PropGroup ("effects", "effects", _("Effects")));
            return l;
        }

        public Layer light (Composition comp, LightType type) {
            string[] names = { _("Parallel Light"), _("Spot Light"), _("Point Light"), _("Ambient Light") };
            var l = new Layer (LayerKind.LIGHT, comp.unique_layer_name (names[type]));
            l.in_point = 0;
            l.out_point = comp.duration;
            l.comp = comp;
            l.three_d = true;
            var t = new PropGroup ("transform", "transform", _("Transform"));
            t.add<Property> (point ("point-of-interest", _("Point of Interest"), { comp.width / 2.0, comp.height / 2.0, 0 }));
            t.add<Property> (point ("position", _("Position"), { comp.width / 2.0 - 200, comp.height / 2.0 - 200, -400 }));
            t.add<Property> (vec ("orientation", _("Orientation"), { 0, 0, 0 }));
            t.add<Property> (angle ("rotation-x", _("X Rotation"), 0));
            t.add<Property> (angle ("rotation-y", _("Y Rotation"), 0));
            t.add<Property> (angle ("rotation", _("Z Rotation"), 0));
            t.add<Property> (point ("anchor", _("Anchor Point"), { 0, 0, 0 }));
            t.add<Property> (vec ("scale", _("Scale"), { 100, 100, 100 }));
            t.add<Property> (percent ("opacity", _("Opacity"), 100));
            l.root.add<PropGroup> (t);
            var g = new PropGroup ("light", "light", _("Light Options"));
            g.attrs["type"] = ((int) type).to_string ();
            g.add<Property> (percent ("intensity", _("Intensity"), 100).range (-1000, 1000));
            g.add<Property> (color ("color", _("Color"), { 1, 1, 1, 1 }));
            g.add<Property> (angle ("cone-angle", _("Cone Angle"), 90).range (0, 180));
            g.add<Property> (percent ("cone-feather", _("Cone Feather"), 50).range (0, 100));
            g.add<Property> (choice ("falloff", _("Falloff"), { _("None"), _("Smooth"), _("Inverse Square Clamped") }, 0));
            g.add<Property> (scalar ("radius", _("Radius"), 500).range (0, 100000));
            g.add<Property> (scalar ("falloff-distance", _("Falloff Distance"), 500).range (0, 100000));
            g.add<Property> (toggle ("casts-shadows", _("Casts Shadows"), false));
            g.add<Property> (percent ("shadow-darkness", _("Shadow Darkness"), 100).range (0, 100));
            g.add<Property> (scalar ("shadow-diffusion", _("Shadow Diffusion"), 0).range (0, 1000));
            l.root.add<PropGroup> (g);
            return l;
        }

        public PropGroup shape_transform () {
            var g = new PropGroup ("shape.transform", "transform", _("Transform"));
            g.add<Property> (point ("anchor", _("Anchor Point"), { 0, 0 }));
            g.add<Property> (point ("position", _("Position"), { 0, 0 }));
            g.add<Property> (vec ("scale", _("Scale"), { 100, 100 }));
            g.add<Property> (scalar ("skew", _("Skew"), 0).range (-85, 85));
            g.add<Property> (angle ("skew-axis", _("Skew Axis"), 0));
            g.add<Property> (angle ("rotation", _("Rotation"), 0));
            g.add<Property> (percent ("opacity", _("Opacity"), 100).range (0, 100));
            return g;
        }

        public PropGroup shape_group (string name) {
            var g = new PropGroup ("shape.group", "group", name);
            g.add<PropGroup> (new PropGroup ("shape.contents", "contents", _("Contents")));
            g.add<PropGroup> (shape_transform ());
            g.attrs["blend"] = "normal";
            return g;
        }

        public PropGroup rect (double w, double h, double roundness = 0) {
            var g = new PropGroup ("shape.rect", "rectangle", _("Rectangle Path"));
            g.add<Property> (vec ("size", _("Size"), { w, h }));
            g.add<Property> (point ("position", _("Position"), { 0, 0 }));
            g.add<Property> (scalar ("roundness", _("Roundness"), roundness).range (0, 100000).ui_range (0, 500));
            g.attrs["direction"] = "1";
            return g;
        }

        public PropGroup ellipse (double w, double h) {
            var g = new PropGroup ("shape.ellipse", "ellipse", _("Ellipse Path"));
            g.add<Property> (vec ("size", _("Size"), { w, h }));
            g.add<Property> (point ("position", _("Position"), { 0, 0 }));
            g.attrs["direction"] = "1";
            return g;
        }

        public PropGroup star (bool polygon, int points, double outer, double inner) {
            var g = new PropGroup ("shape.star", polygon ? "polygon" : "star", polygon ? _("Polygon Path") : _("Polystar Path"));
            g.attrs["star"] = polygon ? "false" : "true";
            g.attrs["direction"] = "1";
            g.add<Property> (scalar ("points", _("Points"), points).range (3, 100));
            g.add<Property> (point ("position", _("Position"), { 0, 0 }));
            g.add<Property> (angle ("rotation", _("Rotation"), 0));
            g.add<Property> (scalar ("inner-radius", _("Inner Radius"), inner).range (0, 100000).ui_range (0, 1000));
            g.add<Property> (scalar ("outer-radius", _("Outer Radius"), outer).range (0, 100000).ui_range (0, 1000));
            g.add<Property> (percent ("inner-roundness", _("Inner Roundness"), 0).range (-1000, 1000).ui_range (-100, 100));
            g.add<Property> (percent ("outer-roundness", _("Outer Roundness"), 0).range (-1000, 1000).ui_range (-100, 100));
            return g;
        }

        public PropGroup path_shape (BezPath p) {
            var g = new PropGroup ("shape.path", "path", _("Path"));
            g.add<Property> (new Property.with_path ("path", _("Path"), p));
            g.attrs["direction"] = "1";
            return g;
        }

        public PropGroup fill (double[] rgba) {
            var g = new PropGroup ("shape.fill", "fill", _("Fill"));
            g.attrs["rule"] = "nonzero";
            g.attrs["composite"] = "below";
            g.attrs["blend"] = "normal";
            g.add<Property> (color ("color", _("Color"), rgba));
            g.add<Property> (percent ("opacity", _("Opacity"), 100).range (0, 100));
            return g;
        }

        private void add_stroke_props (PropGroup g, double width) {
            g.attrs["cap"] = "butt";
            g.attrs["join"] = "miter";
            g.attrs["composite"] = "below";
            g.attrs["blend"] = "normal";
            g.add<Property> (percent ("opacity", _("Opacity"), 100).range (0, 100));
            g.add<Property> (scalar ("width", _("Stroke Width"), width).range (0, 100000).ui_range (0, 200));
            g.add<Property> (scalar ("miter-limit", _("Miter Limit"), 4).range (1, 100));
            g.add<Property> (scalar ("dash", _("Dash"), 0).range (0, 100000).ui_range (0, 200));
            g.add<Property> (scalar ("gap", _("Gap"), 0).range (0, 100000).ui_range (0, 200));
            g.add<Property> (scalar ("dash-offset", _("Offset"), 0));
            g.add<Property> (scalar ("taper-start", _("Start Length"), 0).range (0, 100));
            g.add<Property> (scalar ("taper-end", _("End Length"), 0).range (0, 100));
            g.add<Property> (percent ("taper-start-width", _("Start Width"), 0).range (0, 100));
            g.add<Property> (percent ("taper-end-width", _("End Width"), 0).range (0, 100));
        }

        public PropGroup stroke (double[] rgba, double width) {
            var g = new PropGroup ("shape.stroke", "stroke", _("Stroke"));
            g.add<Property> (color ("color", _("Color"), rgba));
            add_stroke_props (g, width);
            return g;
        }

        private void add_gradient_props (PropGroup g) {
            g.attrs["gradient"] = "linear";
            g.add<Property> (vec ("stops", _("Colors"), { 0, 1, 1, 1, 1, 1, 0, 0, 0, 1 }));
            g.add<Property> (point ("start", _("Start Point"), { -100, 0 }));
            g.add<Property> (point ("end", _("End Point"), { 100, 0 }));
            g.add<Property> (percent ("highlight-length", _("Highlight Length"), 0).range (-100, 100));
            g.add<Property> (angle ("highlight-angle", _("Highlight Angle"), 0));
        }

        public PropGroup gradient_fill () {
            var g = new PropGroup ("shape.gradient-fill", "gradient-fill", _("Gradient Fill"));
            g.attrs["rule"] = "nonzero";
            g.attrs["composite"] = "below";
            g.attrs["blend"] = "normal";
            add_gradient_props (g);
            g.add<Property> (percent ("opacity", _("Opacity"), 100).range (0, 100));
            return g;
        }

        public PropGroup gradient_stroke (double width) {
            var g = new PropGroup ("shape.gradient-stroke", "gradient-stroke", _("Gradient Stroke"));
            add_gradient_props (g);
            add_stroke_props (g, width);
            return g;
        }

        public PropGroup merge () {
            var g = new PropGroup ("shape.merge", "merge", _("Merge Paths"));
            g.attrs["mode"] = "add";
            return g;
        }

        public PropGroup repeater (int copies) {
            var g = new PropGroup ("shape.repeater", "repeater", _("Repeater"));
            g.attrs["composite"] = "below";
            g.add<Property> (scalar ("copies", _("Copies"), copies).range (0, 1000).ui_range (0, 50));
            g.add<Property> (scalar ("offset", _("Offset"), 0).ui_range (-20, 20));
            var t = new PropGroup ("shape.repeater-transform", "transform", _("Transform"));
            t.add<Property> (point ("anchor", _("Anchor Point"), { 0, 0 }));
            t.add<Property> (point ("position", _("Position"), { 100, 0 }));
            t.add<Property> (vec ("scale", _("Scale"), { 100, 100 }));
            t.add<Property> (angle ("rotation", _("Rotation"), 0));
            t.add<Property> (percent ("start-opacity", _("Start Opacity"), 100).range (0, 100));
            t.add<Property> (percent ("end-opacity", _("End Opacity"), 100).range (0, 100));
            g.add<PropGroup> (t);
            return g;
        }

        public PropGroup trim () {
            var g = new PropGroup ("shape.trim", "trim", _("Trim Paths"));
            g.attrs["mode"] = "simultaneous";
            g.add<Property> (percent ("start", _("Start"), 0).range (0, 100));
            g.add<Property> (percent ("end", _("End"), 100).range (0, 100));
            g.add<Property> (angle ("offset", _("Offset"), 0));
            return g;
        }

        public PropGroup round_corners (double radius) {
            var g = new PropGroup ("shape.round", "round-corners", _("Round Corners"));
            g.add<Property> (scalar ("radius", _("Radius"), radius).range (0, 100000).ui_range (0, 200));
            return g;
        }

        public PropGroup wiggle_paths () {
            var g = new PropGroup ("shape.wiggle", "wiggle-paths", _("Wiggle Paths"));
            g.add<Property> (scalar ("size", _("Size"), 10).range (0, 100000).ui_range (0, 200));
            g.add<Property> (scalar ("detail", _("Detail"), 10).range (0, 100000).ui_range (0, 200));
            g.add<Property> (choice ("points", _("Points"), { _("Corner"), _("Smooth") }, 1));
            g.add<Property> (scalar ("wiggles", _("Wiggles/Second"), 2).range (0, 1000).ui_range (0, 20));
            g.add<Property> (percent ("correlation", _("Correlation"), 50).range (0, 100));
            g.add<Property> (angle ("temporal-phase", _("Temporal Phase"), 0));
            g.add<Property> (angle ("spatial-phase", _("Spatial Phase"), 0));
            g.add<Property> (scalar ("seed", _("Random Seed"), 0).range (0, 100000));
            return g;
        }

        public PropGroup zigzag () {
            var g = new PropGroup ("shape.zigzag", "zig-zag", _("Zig Zag"));
            g.add<Property> (scalar ("size", _("Size"), 10).range (0, 100000).ui_range (0, 100));
            g.add<Property> (scalar ("ridges", _("Ridges per segment"), 5).range (0, 1000).ui_range (0, 50));
            g.add<Property> (choice ("points", _("Points"), { _("Corner"), _("Smooth") }, 0));
            return g;
        }

        public PropGroup offset_paths () {
            var g = new PropGroup ("shape.offset", "offset-paths", _("Offset Paths"));
            g.attrs["join"] = "miter";
            g.add<Property> (scalar ("amount", _("Amount"), 10).ui_range (-100, 100));
            g.add<Property> (scalar ("miter-limit", _("Miter Limit"), 4).range (1, 100));
            return g;
        }

        public PropGroup pucker_bloat () {
            var g = new PropGroup ("shape.pucker", "pucker-bloat", _("Pucker & Bloat"));
            g.add<Property> (percent ("amount", _("Amount"), 0).range (-100, 100));
            return g;
        }

        public PropGroup twist () {
            var g = new PropGroup ("shape.twist", "twist", _("Twist"));
            g.add<Property> (angle ("angle", _("Angle"), 0));
            g.add<Property> (point ("center", _("Center"), { 0, 0 }));
            return g;
        }

        public PropGroup? shape_item (string type) {
            switch (type) {
                case "shape.group": return shape_group (_("Group"));
                case "shape.rect": return rect (200, 200);
                case "shape.ellipse": return ellipse (200, 200);
                case "shape.star": return star (false, 5, 100, 50);
                case "shape.path": return path_shape (BezPath.rect (-50, -50, 100, 100));
                case "shape.fill": return fill ({ 1, 0.4, 0.2, 1 });
                case "shape.stroke": return stroke ({ 1, 1, 1, 1 }, 4);
                case "shape.gradient-fill": return gradient_fill ();
                case "shape.gradient-stroke": return gradient_stroke (4);
                case "shape.merge": return merge ();
                case "shape.repeater": return repeater (3);
                case "shape.trim": return trim ();
                case "shape.round": return round_corners (10);
                case "shape.wiggle": return wiggle_paths ();
                case "shape.zigzag": return zigzag ();
                case "shape.offset": return offset_paths ();
                case "shape.pucker": return pucker_bloat ();
                case "shape.twist": return twist ();
                case "shape.transform": return shape_transform ();
                default: return null;
            }
        }

        public PropGroup mask (BezPath path, string mode = "add") {
            var g = new PropGroup ("mask", "mask", _("Mask"));
            g.attrs["mode"] = mode;
            g.attrs["inverted"] = "false";
            g.attrs["color"] = "4";
            g.add<Property> (new Property.with_path ("path", _("Mask Path"), path));
            g.add<Property> (vec ("feather", _("Mask Feather"), { 0, 0 }).range (0, 10000).ui_range (0, 200));
            g.add<Property> (percent ("opacity", _("Mask Opacity"), 100).range (0, 100));
            g.add<Property> (scalar ("expansion", _("Mask Expansion"), 0).ui_range (-200, 200));
            g.add<Property> (toggle ("variable-feather", _("Variable Feather"), false));
            return g;
        }

        public PropGroup text_animator (string name) {
            var g = new PropGroup ("text.animator", "animator", name);
            g.add<PropGroup> (new PropGroup ("text.selectors", "selectors", _("Selectors")));
            g.add<PropGroup> (new PropGroup ("text.properties", "properties", _("Properties")));
            return g;
        }

        public PropGroup range_selector () {
            var g = new PropGroup ("text.selector.range", "range-selector", _("Range Selector"));
            g.attrs["units"] = "percent";
            g.attrs["based-on"] = "characters";
            g.attrs["mode"] = "add";
            g.attrs["shape"] = "square";
            g.attrs["randomize"] = "false";
            g.add<Property> (percent ("start", _("Start"), 0).range (-10000, 10000).ui_range (0, 100));
            g.add<Property> (percent ("end", _("End"), 100).range (-10000, 10000).ui_range (0, 100));
            g.add<Property> (percent ("offset", _("Offset"), 0).ui_range (-100, 100));
            g.add<Property> (percent ("amount", _("Amount"), 100).range (-100, 100));
            g.add<Property> (percent ("smoothness", _("Smoothness"), 100).range (0, 100));
            g.add<Property> (percent ("ease-high", _("Ease High"), 0).range (-100, 100));
            g.add<Property> (percent ("ease-low", _("Ease Low"), 0).range (-100, 100));
            g.add<Property> (scalar ("seed", _("Random Seed"), 0).range (0, 100000));
            return g;
        }

        public PropGroup wiggly_selector () {
            var g = new PropGroup ("text.selector.wiggly", "wiggly-selector", _("Wiggly Selector"));
            g.attrs["mode"] = "intersect";
            g.attrs["based-on"] = "characters";
            g.add<Property> (percent ("max", _("Max Amount"), 100).range (-100, 100));
            g.add<Property> (percent ("min", _("Min Amount"), -100).range (-100, 100));
            g.add<Property> (scalar ("wiggles", _("Wiggles/Second"), 2).range (0, 1000).ui_range (0, 20));
            g.add<Property> (percent ("correlation", _("Correlation"), 50).range (0, 100));
            g.add<Property> (angle ("temporal-phase", _("Temporal Phase"), 0));
            g.add<Property> (angle ("spatial-phase", _("Spatial Phase"), 0));
            g.add<Property> (toggle ("lock-dimensions", _("Lock Dimensions"), false));
            g.add<Property> (scalar ("seed", _("Random Seed"), 0).range (0, 100000));
            return g;
        }

        public PropGroup expression_selector () {
            var g = new PropGroup ("text.selector.expression", "expression-selector", _("Expression Selector"));
            g.attrs["based-on"] = "characters";
            var amount = percent ("amount", _("Amount"), 100).range (-100, 100);
            amount.expression = "selectorValue * textIndex / textTotal";
            g.add<Property> (amount);
            return g;
        }

        public Property? animator_property (string key) {
            switch (key) {
                case "anchor": return point ("anchor", _("Anchor Point"), { 0, 0 });
                case "position": return point ("position", _("Position"), { 0, 0 });
                case "scale": return vec ("scale", _("Scale"), { 100, 100 });
                case "skew": return scalar ("skew", _("Skew"), 0).range (-85, 85);
                case "rotation": return angle ("rotation", _("Rotation"), 0);
                case "opacity": return percent ("opacity", _("Opacity"), 0).range (0, 100);
                case "fill-color": return color ("fill-color", _("Fill Color"), { 1, 0, 0, 1 });
                case "stroke-color": return color ("stroke-color", _("Stroke Color"), { 0, 0, 1, 1 });
                case "stroke-width": return scalar ("stroke-width", _("Stroke Width"), 2).range (0, 1000);
                case "tracking": return scalar ("tracking", _("Tracking Amount"), 0).ui_range (-200, 1000);
                case "line-spacing": return vec ("line-spacing", _("Line Spacing"), { 0, 0 });
                case "character-offset": return scalar ("character-offset", _("Character Offset"), 0).ui_range (-50, 50);
                case "blur": return vec ("blur", _("Blur"), { 0, 0 }).range (0, 10000).ui_range (0, 100);
                default: return null;
            }
        }

        public string[] animator_property_keys () {
            return { "anchor", "position", "scale", "skew", "rotation", "opacity", "fill-color", "stroke-color", "stroke-width", "tracking", "line-spacing", "character-offset", "blur" };
        }
    }
}
