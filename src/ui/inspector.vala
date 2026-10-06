using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Keyframe {

    public class Inspector : Box {
        private Document doc;
        private Stack stack;
        private SidebarTabs switcher;
        private Box props_box;
        private Box text_box;
        private Box essential_box;
        private Box tracker_box;
        private Gee.ArrayList<PropRow> editors = new Gee.ArrayList<PropRow> ();
        private uint rebuild_source = 0;
        public Gtk.Window? host = null;

        public signal void request_expression (Property p);
        public signal void request_add_effect (Layer l, Widget anchor);
        public signal void request_tracker (string kind);

        public Inspector (Document doc) {
            Object (orientation: Orientation.VERTICAL, spacing: 6);
            this.doc = doc;
            margin_top = 8;
            margin_start = 10;
            margin_end = 10;
            margin_bottom = 8;
            stack = new Stack ();
            stack.vexpand = true;
            switcher = new SidebarTabs (stack);
            props_box = scroll_page ("properties", _("Layer"));
            text_box = scroll_page ("character", _("Text"));
            essential_box = scroll_page ("essential", _("Essential"));
            tracker_box = scroll_page ("tracker", _("Tracker"));
            switcher.set_active ("properties");
            append (switcher);
            append (stack);
            doc.selection_changed.connect (schedule_rebuild);
            doc.structure_changed.connect (schedule_rebuild);
            doc.comp_switched.connect (schedule_rebuild);
            doc.time_changed.connect (refresh_values);
            doc.content_changed.connect (refresh_values);
            doc.history_changed.connect (schedule_rebuild);
            rebuild ();
        }

        public void add_page (string name, string title, Widget w) {
            var box = scroll_page (name, title);
            box.append (w);
        }

        private Box scroll_page (string name, string title) {
            var sw = new ScrolledWindow ();
            sw.hscrollbar_policy = PolicyType.NEVER;
            sw.vexpand = true;
            var box = new Box (Orientation.VERTICAL, 12);
            box.margin_top = 6;
            box.margin_bottom = 12;
            sw.child = box;
            stack.add_named (sw, name);
            switcher.add_option (name, title);
            return box;
        }

        private void clear (Box b) {
            Widget? c;
            while ((c = b.get_first_child ()) != null) b.remove (c);
        }

        private void schedule_rebuild () {
            if (rebuild_source != 0) return;
            rebuild_source = Idle.add (() => {
                rebuild_source = 0;
                rebuild ();
                return false;
            });
        }

        private void refresh_values () {
            foreach (var e in editors) e.refresh ();
        }

        private PropRow editor (Layer l, Property p) {
            var e = PropRow.create (doc, l, p);
            e.request_expression.connect ((pp) => request_expression (pp));
            editors.add (e);
            return e;
        }

        private void empty_state (Box b, string text) {
            var sp = new StatusPage ();
            sp.icon_name = "dev.sinty.keyframe";
            sp.title = text;
            sp.compact = true;
            b.append (sp);
        }

        private void text_empty () {
            var wp = new WelcomePage ();
            wp.is_section = true;
            wp.compact = true;
            wp.embedded = true;
            wp.title = _("Text");
            wp.subtitle = _("Select a text layer in the timeline to edit its characters, paragraph and animators.");
            wp.add_action ("font-x-generic", _("New Text Layer"), _("Type a title in the middle of the composition"), () => {
                if (host != null) host.activate_action ("win.new-text", null);
            });
            text_box.append (wp);
        }

        public void rebuild () {
            editors.clear ();
            clear (props_box);
            clear (text_box);
            clear (essential_box);
            clear (tracker_box);
            build_essential ();
            build_tracker ();
            var l = doc.primary ();
            if (l == null) {
                if (doc.comp != null) build_comp_info ();
                else empty_state (props_box, _("No composition open"));
                text_empty ();
                return;
            }
            build_layer (l);
            if (l.kind == LayerKind.TEXT) build_text (l);
            else text_empty ();
        }

        private void build_comp_info () {
            var c = doc.comp;
            var g = new PreferencesGroup (c.name);
            g.add_row (new ActionRow (_("Size"), "%d × %d".printf (c.width, c.height)));
            g.add_row (new ActionRow (_("Frame Rate"), "%.3g fps".printf (c.fps)));
            g.add_row (new ActionRow (_("Duration"), Timecode.format (c.duration, c.fps)));
            g.add_row (new ActionRow (_("Layers"), c.layers.size.to_string ()));
            props_box.append (g);
        }

        private void build_layer (Layer l) {
            var info = new PreferencesGroup (l.name);
            var blend = new ChoiceRow (_("Blending Mode"), blend_labels ());
            blend.selected = (uint) l.blend;
            blend.valign = Align.CENTER;
            blend.notify["selected"].connect (() => doc.edit (_("Blending Mode"), () => {
                l.blend = (Singularity.Imaging.BlendMode) blend.selected;
                l.mark_changed ();
            }));
            info.add_row (blend);
            if (l.kind == LayerKind.SOLID && !l.adjustment) {
                var cb = new ColorPickerButton ();
                var c = Gdk.RGBA ();
                c.red = (float) l.solid_color[0];
                c.green = (float) l.solid_color[1];
                c.blue = (float) l.solid_color[2];
                c.alpha = 1;
                cb.color = c;
                cb.valign = Align.CENTER;
                cb.color_changed.connect ((nc) => doc.edit (_("Solid Color"), () => {
                    l.solid_color = { nc.red, nc.green, nc.blue, 1 };
                    l.mark_changed ();
                }));
                var crow = new ActionRow (_("Solid Color"));
                crow.add_suffix (cb);
                info.add_row (crow);
            }
            var orient = new ChoiceRow (_("Auto-Orient"), { _("Off"), _("Orient Along Path"), _("Orient Towards Camera") });
            orient.selected = (uint) l.auto_orient;
            orient.valign = Align.CENTER;
            orient.notify["selected"].connect (() => doc.edit (_("Auto-Orient"), () => {
                l.auto_orient = (AutoOrient) orient.selected;
                l.mark_changed ();
            }));
            info.add_row (orient);
            info.add_row (switch_row (_("Motion Blur"), l.motion_blur, (v) => l.motion_blur = v));
            info.add_row (switch_row (_("3D Layer"), l.three_d, (v) => l.three_d = v));
            info.add_row (switch_row (_("Adjustment Layer"), l.adjustment, (v) => l.adjustment = v));
            if (l.kind == LayerKind.FOOTAGE || l.kind == LayerKind.PRECOMP) {
                info.add_row (switch_row (_("Time Remapping"), l.time_remap, (v) => {
                    l.time_remap = v;
                    var tr = l.root.prop ("time-remap");
                    if (v && tr != null && tr.keys.size == 0) {
                        tr.set_key (0, { 0 });
                        tr.set_key (l.out_point - l.start_time, { l.out_point - l.start_time });
                    }
                }));
                info.add_row (switch_row (_("Frame Blending"), l.frame_blend, (v) => l.frame_blend = v));
            }
            info.add_row (switch_row (_("Guide Layer"), l.guide, (v) => l.guide = v));
            var stretch = new SpinRow (_("Time Stretch"), _("In percent"), -1000, 1000, 1, l.stretch * 100);
            stretch.notify["value"].connect (() => doc.edit_merged ("stretch" + l.id, _("Time Stretch"), () => {
                if (stretch.value.abs () < 1) return;
                double s = stretch.value / 100.0;
                double dur = (l.out_point - l.start_time) / l.stretch;
                l.stretch = s;
                l.out_point = l.start_time + dur * s;
                l.mark_changed ();
            }));
            info.add_row (stretch);
            props_box.append (info);

            var tr = l.transform;
            if (tr != null) {
                var tg = new PreferencesGroup (_("Transform"));
                foreach (var c in tr.children) {
                    var p = c as Property;
                    if (p == null) continue;
                    if (!l.three_d && (p.key == "orientation" || p.key == "rotation-x" || p.key == "rotation-y")) continue;
                    tg.add_row (editor (l, p));
                }
                props_box.append (tg);
            }
            foreach (var gkey in new string[] { "camera", "light", "material", "model", "audio" }) {
                var g = l.root.group (gkey);
                if (g == null) continue;
                if (gkey == "material" && !l.three_d) continue;
                if (gkey == "audio" && l.kind != LayerKind.AUDIO && l.kind != LayerKind.FOOTAGE) continue;
                var pg = new PreferencesGroup (g.name);
                if (gkey == "light") {
                    var types = new ChoiceRow (_("Light Type"), { _("Parallel"), _("Spot"), _("Point"), _("Ambient") });
                    types.selected = (uint) int.parse (g.attr ("type", "2"));
                    types.valign = Align.CENTER;
                    types.notify["selected"].connect (() => doc.edit (_("Light Type"), () => g.set_attr ("type", types.selected.to_string ())));
                    pg.add_row (types);
                }
                foreach (var c in g.children) if (c is Property) pg.add_row (editor (l, (Property) c));
                props_box.append (pg);
            }
            if (l.kind == LayerKind.SHAPE && l.contents != null) build_contents (l);
            build_masks (l);
            build_effects (l);
        }

        public delegate void BoolSetter (bool v);

        private SwitchRow switch_row (string title, bool value, owned BoolSetter set) {
            var row = new SwitchRow (title, null, value);
            row.notify["active"].connect (() => doc.edit (title, () => {
                set (row.active);
                var l = doc.primary ();
                if (l != null) l.mark_changed ();
            }));
            return row;
        }

        public static string[] blend_labels () {
            string[] r = {};
            for (int i = 0; i < Singularity.Imaging.BlendMode.COUNT; i++) r += ((Singularity.Imaging.BlendMode) i).label ();
            return r;
        }

        private void attr_dropdown (PreferencesGroup g, PropGroup target, string key, string title, string[] ids, string[] labels) {
            var dd = new ChoiceRow (title, labels);
            int cur = 0;
            for (int i = 0; i < ids.length; i++) if (ids[i] == target.attr (key, ids[0])) cur = i;
            dd.selected = cur;
            dd.valign = Align.CENTER;
            dd.notify["selected"].connect (() => doc.edit (title, () => target.set_attr (key, ids[dd.selected])));
            g.add_row (dd);
        }

        private void group_header (PreferencesGroup pg, PropGroup g, PropGroup parent) {
            var box = new Box (Orientation.HORIZONTAL, 2);
            var en = new Switch ();
            en.active = g.enabled;
            en.valign = Align.CENTER;
            en.tooltip_text = _("Enabled");
            en.notify["active"].connect (() => doc.edit (_("Toggle"), () => {
                g.enabled = en.active;
                g.touch ();
            }));
            box.append (en);
            var up = new Button.from_icon_name ("go-up-symbolic");
            up.add_css_class ("flat");
            up.tooltip_text = _("Move Up");
            up.clicked.connect (() => doc.edit (_("Reorder"), () => {
                int i = parent.children.index_of (g);
                if (i > 0) {
                    parent.children.remove (g);
                    parent.children.insert (i - 1, g);
                    g.touch ();
                }
                schedule_rebuild ();
            }));
            box.append (up);
            var del = new Button.from_icon_name ("user-trash-symbolic");
            del.add_css_class ("flat");
            del.tooltip_text = _("Remove");
            del.clicked.connect (() => doc.edit (_("Remove"), () => {
                var l = g.owner_layer ();
                parent.remove (g);
                if (l != null) l.mark_changed ();
                schedule_rebuild ();
            }));
            box.append (del);
            pg.add_header_suffix (box);
        }

        private void build_contents (Layer l) {
            var add_group = new PreferencesGroup (_("Contents"));
            var add_btn = new MenuButton ();
            add_btn.label = _("Add");
            add_btn.valign = Align.CENTER;
            var menu = new GLib.Menu ();
            string[,] items = {
                { _("Group"), "shape.group" }, { _("Rectangle"), "shape.rect" }, { _("Ellipse"), "shape.ellipse" }, { _("Polystar"), "shape.star" },
                { _("Path"), "shape.path" }, { _("Fill"), "shape.fill" }, { _("Stroke"), "shape.stroke" }, { _("Gradient Fill"), "shape.gradient-fill" },
                { _("Gradient Stroke"), "shape.gradient-stroke" }, { _("Merge Paths"), "shape.merge" }, { _("Offset Paths"), "shape.offset" },
                { _("Pucker & Bloat"), "shape.pucker" }, { _("Repeater"), "shape.repeater" }, { _("Round Corners"), "shape.round" },
                { _("Trim Paths"), "shape.trim" }, { _("Twist"), "shape.twist" }, { _("Wiggle Paths"), "shape.wiggle" }, { _("Zig Zag"), "shape.zigzag" }
            };
            for (int i = 0; i < items.length[0]; i++) menu.append (items[i, 0], "win.add-shape-item::" + items[i, 1]);
            add_btn.menu_model = menu;
            add_group.add_header_suffix (add_btn);
            props_box.append (add_group);
            add_items (l, l.contents, "");
        }

        private void add_items (Layer l, PropGroup container, string prefix) {
            foreach (var c in container.children) {
                var g = c as PropGroup;
                if (g == null) continue;
                string title = prefix == "" ? g.name : prefix + " / " + g.name;
                if (g.type == "shape.group") {
                    var gg = new PreferencesGroup (title);
                    group_header (gg, g, container);
                    var gt = g.group ("transform");
                    attr_dropdown (gg, g, "blend", _("Blending Mode"), blend_keys (), blend_labels ());
                    if (gt != null) foreach (var tc in gt.children) if (tc is Property) gg.add_row (editor (l, (Property) tc));
                    props_box.append (gg);
                    var inner = g.group ("contents");
                    if (inner != null) add_items (l, inner, title);
                    continue;
                }
                var pg = new PreferencesGroup (title);
                group_header (pg, g, container);
                switch (g.type) {
                    case "shape.fill":
                    case "shape.gradient-fill":
                        attr_dropdown (pg, g, "rule", _("Fill Rule"), { "nonzero", "evenodd" }, { _("Non-Zero Winding"), _("Even-Odd") });
                        break;
                    case "shape.merge":
                        attr_dropdown (pg, g, "mode", _("Mode"), { "merge", "add", "subtract", "intersect", "exclude" }, { _("Merge"), _("Add"), _("Subtract"), _("Intersect"), _("Exclude Intersections") });
                        break;
                    case "shape.trim":
                        attr_dropdown (pg, g, "mode", _("Trim Multiple Shapes"), { "simultaneous", "individually" }, { _("Simultaneously"), _("Individually") });
                        break;
                    case "shape.repeater":
                        attr_dropdown (pg, g, "composite", _("Composite"), { "below", "above" }, { _("Below"), _("Above") });
                        break;
                    case "shape.offset":
                        attr_dropdown (pg, g, "join", _("Line Join"), { "miter", "round", "bevel" }, { _("Miter Join"), _("Round Join"), _("Bevel Join") });
                        break;
                    case "shape.star":
                        attr_dropdown (pg, g, "star", _("Type"), { "true", "false" }, { _("Star"), _("Polygon") });
                        break;
                }
                if (g.type == "shape.stroke" || g.type == "shape.gradient-stroke") {
                    attr_dropdown (pg, g, "cap", _("Line Cap"), { "butt", "round", "square" }, { _("Butt Cap"), _("Round Cap"), _("Projecting Cap") });
                    attr_dropdown (pg, g, "join", _("Line Join"), { "miter", "round", "bevel" }, { _("Miter Join"), _("Round Join"), _("Bevel Join") });
                }
                if (g.type == "shape.gradient-fill" || g.type == "shape.gradient-stroke") {
                    attr_dropdown (pg, g, "gradient", _("Type"), { "linear", "radial" }, { _("Linear"), _("Radial") });
                }
                if (g.type == "shape.fill" || g.type == "shape.stroke" || g.type == "shape.gradient-fill" || g.type == "shape.gradient-stroke") {
                    attr_dropdown (pg, g, "blend", _("Blending Mode"), blend_keys (), blend_labels ());
                }
                foreach (var pc in g.children) {
                    if (pc is Property) pg.add_row (editor (l, (Property) pc));
                    else if (pc is PropGroup) foreach (var sc in ((PropGroup) pc).children) if (sc is Property) pg.add_row (editor (l, (Property) sc));
                }
                props_box.append (pg);
            }
        }

        public static string[] blend_keys () {
            string[] r = {};
            for (int i = 0; i < Singularity.Imaging.BlendMode.COUNT; i++) r += ((Singularity.Imaging.BlendMode) i).key ();
            return r;
        }

        private void build_masks (Layer l) {
            var masks = l.masks;
            if (masks == null || masks.children.size == 0) return;
            foreach (var c in masks.children) {
                var g = c as PropGroup;
                if (g == null) continue;
                var pg = new PreferencesGroup (g.name);
                group_header (pg, g, masks);
                attr_dropdown (pg, g, "mode", _("Mode"), { "add", "subtract", "intersect", "lighten", "darken", "difference", "none" },
                               { _("Add"), _("Subtract"), _("Intersect"), _("Lighten"), _("Darken"), _("Difference"), _("None") });
                attr_dropdown (pg, g, "inverted", _("Inverted"), { "false", "true" }, { _("No"), _("Yes") });
                foreach (var pc in g.children) if (pc is Property) pg.add_row (editor (l, (Property) pc));
                props_box.append (pg);
            }
        }

        private void build_effects (Layer l) {
            var fx = l.effects;
            var head = new PreferencesGroup (_("Effects"));
            var add = new Button.with_label (_("Add Effect"));
            add.valign = Align.CENTER;
            add.clicked.connect (() => request_add_effect (l, add));
            head.add_header_suffix (add);
            props_box.append (head);
            if (fx == null) return;
            foreach (var c in fx.children) {
                var g = c as PropGroup;
                if (g == null) continue;
                var pg = new PreferencesGroup (g.name);
                group_header (pg, g, fx);
                var id = EffectRegistry.id_of (g);
                if (id == "curves") {
                    var ch = new ChoiceRow (_("Channel"), { _("RGB"), _("Red"), _("Green"), _("Blue") });
                    pg.add_row (ch);
                    pg.add_row (new CurvesRow (doc, g, ch));
                }
                if (id == "color-lut") {
                    var row = new ActionRow (_("LUT File"), g.attr ("file", "") == "" ? _("None") : Path.get_basename (g.attr ("file")));
                    var pick = new Button.with_label (_("Choose"));
                    pick.valign = Align.CENTER;
                    pick.clicked.connect (() => choose_lut (g));
                    row.add_suffix (pick);
                    pg.add_row (row);
                }
                if (id == "color-convert") {
                    var spaces = ColorManagement.builtin_spaces ();
                    string[] labels = {};
                    foreach (var s in spaces) labels += ColorManagement.label (s);
                    attr_dropdown (pg, g, "from", _("From"), spaces, labels);
                    attr_dropdown (pg, g, "to", _("To"), spaces, labels);
                }
                foreach (var pc in g.children) {
                    if (pc is Property) pg.add_row (editor (l, (Property) pc));
                    else if (pc is PropGroup) {
                        foreach (var sc in ((PropGroup) pc).children) {
                            if (sc is Property) pg.add_row (editor (l, (Property) sc));
                            else if (sc is PropGroup) foreach (var ssc in ((PropGroup) sc).children) if (ssc is Property) pg.add_row (editor (l, (Property) ssc));
                        }
                    }
                }
                props_box.append (pg);
            }
        }

        private void choose_lut (PropGroup g) {
            var dlg = new FileDialog ();
            dlg.title = _("Choose a Cube LUT");
            var filter = new FileFilter ();
            filter.name = _("Cube LUT");
            filter.add_pattern ("*.cube");
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (filter);
            dlg.filters = filters;
            dlg.open.begin (get_root () as Gtk.Window, null, (o, res) => {
                try {
                    var f = dlg.open.end (res);
                    if (f != null) doc.edit (_("LUT File"), () => g.set_attr ("file", f.get_path ()));
                    schedule_rebuild ();
                } catch (Error e) {
                }
            });
        }

        private void build_text (Layer l) {
            var tg = l.text_group;
            if (tg == null) return;
            var sp = tg.prop ("source-text");
            double lt = l.layer_time (doc.time);
            var d = sp.text_at (lt);
            var g = new PreferencesGroup (_("Character"));
            var source = new PreferencesGroup (_("Source Text"));
            var view = new TextView ();
            view.wrap_mode = WrapMode.WORD_CHAR;
            view.buffer.text = d.text;
            view.height_request = 60;
            view.top_margin = 10;
            view.bottom_margin = 10;
            view.left_margin = 12;
            view.right_margin = 12;
            view.add_css_class ("keyframe-source-text");
            var apply = new Button.with_label (_("Apply"));
            apply.valign = Align.CENTER;
            apply.tooltip_text = _("Apply the text to the layer");
            apply.clicked.connect (() => update_doc (l, (nd) => nd.text = view.buffer.text));
            source.add_header_suffix (apply);
            var trow = new PreferencesRow ();
            trow.child = view;
            trow.activatable = false;
            source.add_row (trow);
            text_box.append (source);
            var font_btn = new FontDialogButton (new FontDialog ());
            font_btn.font_desc = TextRenderer.font_description (d);
            font_btn.level = FontLevel.FAMILY;
            font_btn.valign = Align.CENTER;
            font_btn.notify["font-desc"].connect (() => update_doc (l, (nd) => nd.font = font_btn.font_desc.get_family ()));
            var frow = new ActionRow (_("Font"));
            frow.add_suffix (font_btn);
            g.add_row (frow);
            var weights = new ChoiceRow (_("Weight"), { _("Thin"), _("Light"), _("Regular"), _("Medium"), _("Semibold"), _("Bold"), _("Black") });
            int[] wv = { 100, 300, 400, 500, 600, 700, 900 };
            for (int i = 0; i < wv.length; i++) if (wv[i] == d.weight) weights.selected = i;
            weights.valign = Align.CENTER;
            weights.notify["selected"].connect (() => update_doc (l, (nd) => nd.weight = wv[weights.selected]));
            g.add_row (weights);
            g.add_row (num_row (l, _("Size"), d.size, 1, 2000, (nd, v) => nd.size = v));
            g.add_row (num_row (l, _("Tracking"), d.tracking, -1000, 5000, (nd, v) => nd.tracking = v));
            g.add_row (num_row (l, _("Leading"), d.leading, 0, 5000, (nd, v) => nd.leading = v));
            g.add_row (num_row (l, _("Baseline Shift"), d.baseline_shift, -1000, 1000, (nd, v) => nd.baseline_shift = v));
            g.add_row (num_row (l, _("Stroke Width"), d.stroke_width, 0, 500, (nd, v) => {
                nd.stroke_width = v;
                nd.apply_stroke = v > 0;
            }));
            g.add_row (color_row (l, _("Fill Color"), d.fill, (nd, c) => nd.fill = c));
            g.add_row (color_row (l, _("Stroke Color"), d.stroke, (nd, c) => nd.stroke = c));
            g.add_row (text_switch (l, _("Italic"), d.italic, (nd, v) => nd.italic = v));
            g.add_row (text_switch (l, _("All Caps"), d.all_caps, (nd, v) => nd.all_caps = v));
            g.add_row (text_switch (l, _("Small Caps"), d.small_caps, (nd, v) => nd.small_caps = v));
            g.add_row (text_switch (l, _("Stroke Over Fill"), !d.fill_over_stroke, (nd, v) => nd.fill_over_stroke = !v));
            var vars = new EntryRow (_("Variable Font Axes"));
            vars.text = d.variations;
            vars.entry_activated.connect (() => update_doc (l, (nd) => nd.variations = vars.text));
            g.add_row (vars);
            var feats = new EntryRow (_("OpenType Features"));
            feats.text = d.features;
            feats.entry_activated.connect (() => update_doc (l, (nd) => nd.features = feats.text));
            g.add_row (feats);
            text_box.append (g);
            var para = new PreferencesGroup (_("Paragraph"));
            var just = new ChoiceRow (_("Alignment"), { _("Left"), _("Center"), _("Right"), _("Justify") });
            just.selected = d.justify.clamp (0, 3);
            just.valign = Align.CENTER;
            just.notify["selected"].connect (() => update_doc (l, (nd) => nd.justify = (int) just.selected));
            para.add_row (just);
            para.add_row (num_row (l, _("Box Width"), d.box_width, 0, 10000, (nd, v) => nd.box_width = v));
            para.add_row (num_row (l, _("Box Height"), d.box_height, 0, 10000, (nd, v) => nd.box_height = v));
            para.add_row (num_row (l, _("First Line Indent"), d.first_indent, -2000, 2000, (nd, v) => nd.first_indent = v));
            text_box.append (para);
            var po = tg.group ("path-options");
            if (po != null) {
                var pg = new PreferencesGroup (_("Path Options"));
                string[] ids = { "" };
                string[] labels = { _("None") };
                if (l.masks != null) foreach (var mc in l.masks.children) {
                    ids += mc.key;
                    labels += mc.name;
                }
                attr_dropdown (pg, po, "mask", _("Path"), ids, labels);
                foreach (var pc in po.children) if (pc is Property) pg.add_row (editor (l, (Property) pc));
                text_box.append (pg);
            }
            var anims = tg.group ("animators");
            var ah = new PreferencesGroup (_("Animators"));
            var add = new MenuButton ();
            add.label = _("Animate");
            add.valign = Align.CENTER;
            var menu = new GLib.Menu ();
            string[] keys = Factory.animator_property_keys ();
            foreach (var k in keys) {
                var prop = Factory.animator_property (k);
                menu.append (prop.name, "win.add-text-animator::" + k);
            }
            add.menu_model = menu;
            ah.add_header_suffix (add);
            text_box.append (ah);
            if (anims == null) return;
            foreach (var ac in anims.children) {
                var an = ac as PropGroup;
                if (an == null) continue;
                var ag = new PreferencesGroup (an.name);
                group_header (ag, an, anims);
                var sels = an.group ("selectors");
                var props = an.group ("properties");
                var add_sel = new MenuButton ();
                add_sel.icon_name = "list-add-symbolic";
                add_sel.tooltip_text = _("Add Selector");
                add_sel.add_css_class ("flat");
                var smenu = new GLib.Menu ();
                smenu.append (_("Range Selector"), "win.add-text-selector::range|" + an.key);
                smenu.append (_("Wiggly Selector"), "win.add-text-selector::wiggly|" + an.key);
                smenu.append (_("Expression Selector"), "win.add-text-selector::expression|" + an.key);
                foreach (var k in keys) smenu.append (Factory.animator_property (k).name, "win.add-animator-property::" + k + "|" + an.key);
                add_sel.menu_model = smenu;
                ag.add_header_suffix (add_sel);
                if (props != null) foreach (var pc in props.children) if (pc is Property) ag.add_row (editor (l, (Property) pc));
                text_box.append (ag);
                if (sels == null) continue;
                foreach (var sc in sels.children) {
                    var sel = sc as PropGroup;
                    if (sel == null) continue;
                    var sg = new PreferencesGroup ("%s / %s".printf (an.name, sel.name));
                    group_header (sg, sel, sels);
                    if (sel.type == "text.selector.range") {
                        attr_dropdown (sg, sel, "units", _("Units"), { "percent", "index" }, { _("Percentage"), _("Index") });
                        attr_dropdown (sg, sel, "shape", _("Shape"), { "square", "ramp-up", "ramp-down", "triangle", "round", "smooth" },
                                       { _("Square"), _("Ramp Up"), _("Ramp Down"), _("Triangle"), _("Round"), _("Smooth") });
                        attr_dropdown (sg, sel, "randomize", _("Randomize Order"), { "false", "true" }, { _("Off"), _("On") });
                    }
                    attr_dropdown (sg, sel, "based-on", _("Based On"), { "characters", "characters-excluding-spaces", "words", "lines" },
                                   { _("Characters"), _("Characters Excluding Spaces"), _("Words"), _("Lines") });
                    if (sel.type != "text.selector.expression")
                        attr_dropdown (sg, sel, "mode", _("Mode"), { "add", "subtract", "intersect", "min", "max", "difference" },
                                       { _("Add"), _("Subtract"), _("Intersect"), _("Min"), _("Max"), _("Difference") });
                    foreach (var pc in sel.children) if (pc is Property) sg.add_row (editor (l, (Property) pc));
                    text_box.append (sg);
                }
            }
        }

        public delegate void DocEdit (TextDocument d);
        public delegate void DocNum (TextDocument d, double v);
        public delegate void DocColor (TextDocument d, double[] c);
        public delegate void DocBool (TextDocument d, bool v);

        private void update_doc (Layer l, DocEdit f) {
            var sp = l.text_group.prop ("source-text");
            double lt = l.layer_time (doc.time);
            var nd = sp.text_at (lt).copy ();
            f (nd);
            doc.edit_merged ("text" + l.id, _("Edit Text"), () => {
                if (sp.keys.size > 0) sp.set_text_key (lt, nd);
                else {
                    sp.text = nd;
                    sp.touch ();
                }
            });
        }

        private SpinRow num_row (Layer l, string title, double value, double lo, double hi, owned DocNum f) {
            var row = new SpinRow (title, null, lo, hi, 1, value);
            row.notify["value"].connect (() => update_doc (l, (nd) => f (nd, row.value)));
            return row;
        }

        private ActionRow color_row (Layer l, string title, double[] value, owned DocColor f) {
            var cb = new ColorPickerButton ();
            var c = Gdk.RGBA ();
            c.red = (float) value[0];
            c.green = (float) value[1];
            c.blue = (float) value[2];
            c.alpha = (float) (value.length > 3 ? value[3] : 1);
            cb.color = c;
            cb.valign = Align.CENTER;
            cb.color_changed.connect ((nc) => update_doc (l, (nd) => f (nd, { nc.red, nc.green, nc.blue, nc.alpha })));
            var row = new ActionRow (title);
            row.add_suffix (cb);
            return row;
        }

        private SwitchRow text_switch (Layer l, string title, bool value, owned DocBool f) {
            var row = new SwitchRow (title, null, value);
            row.notify["active"].connect (() => update_doc (l, (nd) => f (nd, row.active)));
            return row;
        }

        private void build_essential () {
            if (doc.comp == null) {
                empty_state (essential_box, _("No composition open"));
                return;
            }
            var c = doc.comp;
            var g = new PreferencesGroup (_("Exposed Properties"), _("Properties that Montage and templates can change without opening the composition"));
            var add = new Button.with_label (_("Add Property"));
            add.valign = Align.CENTER;
            add.sensitive = doc.active_property != null;
            add.tooltip_text = _("Expose the property selected in the timeline");
            add.clicked.connect (() => {
                var p = doc.active_property;
                var l = p != null ? p.owner_layer () : null;
                if (p == null || l == null) return;
                doc.edit (_("Expose Property"), () => {
                    c.essential.add (new EssentialProperty (l.id, p.path_string (), "%s %s".printf (l.name, p.name)));
                    c.layer_changed (null);
                });
                schedule_rebuild ();
            });
            g.add_header_suffix (add);
            if (c.essential.size == 0) {
                var none = new ActionRow (_("No Exposed Properties"), _("Select a property in the timeline, then press Add Property."));
                none.activatable = false;
                g.add_row (none);
            }
            foreach (var e in c.essential) {
                var l = c.layer_by_id (e.layer_id);
                var row = new EntryRow (l != null ? "%s: %s".printf (l.name, e.path) : e.path);
                row.text = e.label;
                var entry = e;
                row.entry_changed.connect (() => entry.label = row.text);
                var del = new Button.from_icon_name ("user-trash-symbolic");
                del.add_css_class ("flat");
                del.valign = Align.CENTER;
                del.clicked.connect (() => {
                    doc.edit (_("Remove Exposed Property"), () => {
                        c.essential.remove (entry);
                        c.layer_changed (null);
                    });
                    schedule_rebuild ();
                });
                row.add_suffix (del);
                g.add_row (row);
                if (l != null) {
                    var p = l.root.find (e.path) as Property;
                    if (p != null) g.add_row (editor (l, p));
                }
            }
            essential_box.append (g);
            var tg = new PreferencesGroup (_("Template"));
            var save = new ActionRow (_("Save as Motion Template"), _("A .keyframe file whose exposed properties Montage can edit"));
            var sb = new Button.with_label (_("Save"));
            sb.valign = Align.CENTER;
            sb.action_name = "win.save-template";
            save.add_suffix (sb);
            tg.add_row (save);
            essential_box.append (tg);
        }

        private void build_tracker () {
            var g = new PreferencesGroup (_("Motion Tracking"), _("Track the selected footage or precomposition layer"));
            string[,] rows = {
                { _("Track One Point"), _("Position, applied to a new null"), "point" },
                { _("Track Two Points"), _("Position, scale and rotation"), "two-points" },
                { _("Track Plane"), _("Corner pin a layer onto a flat surface"), "planar" },
                { _("Stabilize"), _("Smooth or lock camera motion"), "stabilize" },
                { _("Track Camera"), _("Solve a 3D camera and ground nulls"), "camera" },
                { _("Propagate Mask"), _("Carry the selected mask through the shot"), "roto" }
            };
            for (int i = 0; i < rows.length[0]; i++) {
                var row = new ActionRow (rows[i, 0], rows[i, 1]);
                var b = new Button.with_label (_("Run"));
                b.valign = Align.CENTER;
                string kind = rows[i, 2];
                b.clicked.connect (() => request_tracker (kind));
                row.add_suffix (b);
                g.add_row (row);
            }
            tracker_box.append (g);
        }
    }

    public class CurvesRow : PreferencesRow {
        private Document doc;
        private PropGroup fx;
        private DrawingArea area;
        private ChoiceRow channel;
        private string[] channels = { "rgb", "red", "green", "blue" };
        private int drag_index = -1;

        public CurvesRow (Document doc, PropGroup fx, ChoiceRow channel) {
            this.doc = doc;
            this.fx = fx;
            var box = new Box (Orientation.VERTICAL, 6);
            box.margin_top = 8;
            box.margin_bottom = 8;
            box.margin_start = 8;
            box.margin_end = 8;
            this.channel = channel;
            channel.notify["selected"].connect (() => area.queue_draw ());
            area = new DrawingArea ();
            area.content_height = 220;
            area.set_draw_func (draw);
            var click = new GestureClick ();
            click.pressed.connect (pressed);
            area.add_controller (click);
            var drag = new GestureDrag ();
            drag.drag_update.connect ((dx, dy) => {
                double sx, sy;
                drag.get_start_point (out sx, out sy);
                move (sx + dx, sy + dy);
            });
            drag.drag_end.connect ((x, y) => {
                if (drag_index >= 0) doc.end_edit ();
                drag_index = -1;
                doc.content_changed ();
            });
            area.add_controller (drag);
            box.append (area);
            child = box;
            activatable = false;
        }

        private string key () {
            return channels[channel.selected];
        }

        private EffectsColor.CurvePoints points () {
            return EffectsColor.CurvePoints.parse (fx.attr (key (), "0,0 1,1"));
        }

        private void store (double[] xs, double[] ys) {
            var sb = new StringBuilder ();
            for (int i = 0; i < xs.length; i++) {
                if (i > 0) sb.append (" ");
                sb.append ("%s,%s".printf (BezPath.fmt (xs[i]), BezPath.fmt (ys[i])));
            }
            fx.set_attr (key (), sb.str);
        }

        private void draw (DrawingArea a, Cairo.Context cr, int w, int h) {
            cr.set_source_rgba (0.5, 0.5, 0.5, 0.15);
            cr.rectangle (0, 0, w, h);
            cr.fill ();
            cr.set_source_rgba (0.5, 0.5, 0.5, 0.3);
            for (int i = 1; i < 4; i++) {
                cr.move_to (w * i / 4.0, 0);
                cr.line_to (w * i / 4.0, h);
                cr.move_to (0, h * i / 4.0);
                cr.line_to (w, h * i / 4.0);
            }
            cr.stroke ();
            var p = points ();
            double[] col = { 0.9, 0.9, 0.9 };
            if (channel.selected == 1) col = { 0.95, 0.35, 0.35 };
            if (channel.selected == 2) col = { 0.35, 0.85, 0.4 };
            if (channel.selected == 3) col = { 0.35, 0.6, 1 };
            cr.set_source_rgb (col[0], col[1], col[2]);
            cr.set_line_width (2);
            for (int i = 0; i <= w; i++) {
                double y = p.eval ((float) (i / (double) w));
                if (i == 0) cr.move_to (i, h - y * h);
                else cr.line_to (i, h - y * h);
            }
            cr.stroke ();
            for (int i = 0; i < p.xs.length; i++) {
                cr.arc (p.xs[i] * w, h - p.ys[i] * h, 4, 0, Math.PI * 2);
                cr.fill ();
            }
        }

        private void pressed (int n, double x, double y) {
            var p = points ();
            int w = area.get_width (), h = area.get_height ();
            for (int i = 0; i < p.xs.length; i++) {
                if (Math.hypot (p.xs[i] * w - x, (1 - p.ys[i]) * h - y) < 8) {
                    if (n == 2 && i > 0 && i < p.xs.length - 1) {
                        double[] xs = {}, ys = {};
                        for (int k = 0; k < p.xs.length; k++) if (k != i) {
                            xs += p.xs[k];
                            ys += p.ys[k];
                        }
                        doc.edit (_("Curves"), () => store (xs, ys));
                        area.queue_draw ();
                        return;
                    }
                    drag_index = i;
                    doc.begin_edit (_("Curves"));
                    return;
                }
            }
            double nx = (x / w).clamp (0, 1), ny = (1 - y / h).clamp (0, 1);
            double[] xs = {}, ys = {};
            bool added = false;
            for (int k = 0; k < p.xs.length; k++) {
                if (!added && nx < p.xs[k]) {
                    xs += nx;
                    ys += ny;
                    drag_index = xs.length - 1;
                    added = true;
                }
                xs += p.xs[k];
                ys += p.ys[k];
            }
            if (!added) {
                xs += nx;
                ys += ny;
                drag_index = xs.length - 1;
            }
            doc.begin_edit (_("Curves"));
            store (xs, ys);
            area.queue_draw ();
        }

        private void move (double x, double y) {
            if (drag_index < 0) return;
            var p = points ();
            int w = area.get_width (), h = area.get_height ();
            var xs = p.xs;
            var ys = p.ys;
            if (drag_index >= xs.length) return;
            double lo = drag_index > 0 ? xs[drag_index - 1] + 0.01 : 0;
            double hi = drag_index < xs.length - 1 ? xs[drag_index + 1] - 0.01 : 1;
            xs[drag_index] = (x / w).clamp (lo, hi);
            ys[drag_index] = (1 - y / h).clamp (0, 1);
            store (xs, ys);
            area.queue_draw ();
        }
    }
}
