using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Keyframe {

    namespace EasingPresets {
        public string[] extra_names () {
            return { "ease-in-quad", "ease-out-quad", "ease-in-out-cubic", "ease-in-out-expo", "overshoot", "anticipate" };
        }

        public string label (string name) {
            switch (name) {
                case "linear": return _("Linear");
                case "standard": return _("Desktop Standard");
                case "enter": return _("Desktop Enter");
                case "exit": return _("Desktop Exit");
                case "emphasized": return _("Desktop Emphasized");
                case "ease-in-quad": return _("Ease In Quad");
                case "ease-out-quad": return _("Ease Out Quad");
                case "ease-in-out-cubic": return _("Ease In Out Cubic");
                case "ease-in-out-expo": return _("Ease In Out Expo");
                case "overshoot": return _("Overshoot");
                case "anticipate": return _("Anticipate");
                default: return name;
            }
        }

        public bool points (string name, out double x1, out double y1, out double x2, out double y2) {
            foreach (var c in Singularity.Motion.Curve.all ()) {
                if (c.css_name () == name) {
                    c.get_points (out x1, out y1, out x2, out y2);
                    return true;
                }
            }
            switch (name) {
                case "ease-in-quad": x1 = 0.11; y1 = 0; x2 = 0.5; y2 = 0; return true;
                case "ease-out-quad": x1 = 0.5; y1 = 1; x2 = 0.89; y2 = 1; return true;
                case "ease-in-out-cubic": x1 = 0.65; y1 = 0; x2 = 0.35; y2 = 1; return true;
                case "ease-in-out-expo": x1 = 0.87; y1 = 0; x2 = 0.13; y2 = 1; return true;
                case "overshoot": x1 = 0.34; y1 = 1.56; x2 = 0.64; y2 = 1; return true;
                case "anticipate": x1 = 0.36; y1 = 0; x2 = 0.66; y2 = -0.56; return true;
                default:
                    x1 = 0;
                    y1 = 0;
                    x2 = 1;
                    y2 = 1;
                    return false;
            }
        }

        public void apply (string name, Property? p, Keyframe k) {
            if (p == null) return;
            int i = p.keys.index_of (k);
            if (i < 0 || i >= p.keys.size - 1) return;
            double x1, y1, x2, y2;
            points (name, out x1, out y1, out x2, out y2);
            var next = p.keys[i + 1];
            if (name == "linear") {
                k.out_interp = Interp.LINEAR;
                next.in_interp = Interp.LINEAR;
                return;
            }
            k.out_interp = Interp.BEZIER;
            k.ease_out_x = x1;
            k.ease_out_y = y1;
            k.auto_bezier = false;
            next.in_interp = Interp.BEZIER;
            next.ease_in_x = x2;
            next.ease_in_y = y2;
            next.auto_bezier = false;
        }
    }

    namespace Dialogs {
        public delegate void TextResult (string text);

        private ConfirmDialog make (KeyframeWindow w, string title, string primary, ConfirmDialog.ActionStyle style = ConfirmDialog.ActionStyle.SUGGESTED) {
            var d = new ConfirmDialog (w.app, title, null, null, primary, style);
            d.set_default_size (460, 0);
            d.transient_for = w;
            d.modal = true;
            return d;
        }

        public void text_prompt (KeyframeWindow w, string title, string initial, owned TextResult done, string? field = null) {
            var d = make (w, title, _("OK"));
            var g = new PreferencesGroup ();
            var row = new EntryRow (field ?? _("Text"));
            row.text = initial;
            g.add_row (row);
            d.custom_area.append (g);
            row.entry_activated.connect (() => {
                d.response (ConfirmDialog.Response.PRIMARY);
                d.close_dialog ();
            });
            d.response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY && row.text.strip () != "") done (row.text);
            });
            d.present ();
            row.grab_focus ();
        }

        public void rename_layer (KeyframeWindow w, Layer l) {
            text_prompt (w, _("Rename Layer"), l.name, (t) => w.doc.edit (_("Rename Layer"), () => {
                l.name = t;
                l.root.name = t;
                l.mark_changed ();
            }), _("Name"));
        }

        public void rename_item (KeyframeWindow w, Item it) {
            text_prompt (w, _("Rename"), it.name, (t) => w.doc.edit (_("Rename"), () => {
                it.name = t;
                w.doc.project.structure_changed ();
            }), _("Name"));
        }

        private ActionRow color_row (string title, double[] value, out ColorPickerButton btn) {
            btn = new ColorPickerButton ();
            var c = Gdk.RGBA ();
            c.red = (float) value[0];
            c.green = (float) value[1];
            c.blue = (float) value[2];
            c.alpha = 1;
            btn.color = c;
            btn.valign = Align.CENTER;
            var row = new ActionRow (title);
            row.add_suffix (btn);
            return row;
        }

        public void comp_settings (KeyframeWindow w, Composition c, bool is_new = false) {
            var d = make (w, is_new ? _("New Composition") : _("Composition Settings"), is_new ? _("Create") : _("Apply"));
            var basic = new PreferencesGroup (_("Composition"));
            var name = new EntryRow (_("Name"));
            name.text = c.name;
            basic.add_row (name);
            var presets = new ChoiceRow (_("Preset"), { _("Custom"), "HD 1920 x 1080", "4K UHD 3840 x 2160", "HD 1280 x 720", _("Square 1080"), _("Vertical 1080 x 1920"), _("Icon 512") });
            presets.valign = Align.CENTER;
            basic.add_row (presets);
            var width = new SpinRow (_("Width"), _("Pixels"), 4, 16384, 1, c.width);
            var height = new SpinRow (_("Height"), _("Pixels"), 4, 16384, 1, c.height);
            basic.add_row (width);
            basic.add_row (height);
            presets.notify["selected"].connect (() => {
                int[,] sizes = { { 0, 0 }, { 1920, 1080 }, { 3840, 2160 }, { 1280, 720 }, { 1080, 1080 }, { 1080, 1920 }, { 512, 512 } };
                int i = (int) presets.selected;
                if (i > 0) {
                    width.value = sizes[i, 0];
                    height.value = sizes[i, 1];
                }
            });
            var fps = new SpinRow (_("Frame Rate"), _("Frames per second"), 1, 240, 0.001, c.fps);
            fps.spin_btn.digits = 3;
            basic.add_row (fps);
            var duration = new SpinRow (_("Duration"), _("Seconds"), 0.04, 36000, 0.1, c.duration);
            duration.spin_btn.digits = 2;
            basic.add_row (duration);
            ColorPickerButton bg;
            basic.add_row (color_row (_("Background Color"), c.background, out bg));
            var form = new Box (Orientation.VERTICAL, 12);
            form.append (basic);
            var adv = new PreferencesGroup (_("Motion Blur"));
            var angle = new SpinRow (_("Shutter Angle"), _("Degrees"), 0, 720, 1, c.shutter_angle);
            var phase = new SpinRow (_("Shutter Phase"), _("Degrees"), -360, 360, 1, c.shutter_phase);
            var samples = new SpinRow (_("Samples per Frame"), null, 2, 64, 1, c.motion_blur_samples);
            adv.add_row (angle);
            adv.add_row (phase);
            adv.add_row (samples);
            form.append (adv);
            var form_scroll = new ScrolledWindow ();
            form_scroll.hscrollbar_policy = PolicyType.NEVER;
            form_scroll.propagate_natural_height = true;
            form_scroll.max_content_height = 480;
            form_scroll.child = form;
            d.custom_area.append (form_scroll);
            d.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                w.doc.edit (is_new ? _("New Composition") : _("Composition Settings"), () => {
                    c.name = name.text.strip () != "" ? name.text : c.name;
                    c.width = (int) width.value;
                    c.height = (int) height.value;
                    c.fps = fps.value;
                    double old = c.duration;
                    c.duration = duration.value;
                    foreach (var l in c.layers) if ((l.out_point - old).abs () < 1e-6) l.out_point = c.duration;
                    var bc = bg.color;
                    c.background = { bc.red, bc.green, bc.blue, 1 };
                    c.shutter_angle = angle.value;
                    c.shutter_phase = phase.value;
                    c.motion_blur_samples = (int) samples.value;
                    if (is_new) w.doc.project.add_item (c);
                    else c.layer_changed (null);
                });
                if (is_new) w.doc.open_comp (c);
                else w.doc.structure_changed ();
            });
            d.present ();
        }

        public void new_solid (KeyframeWindow w) {
            var c = w.doc.comp;
            var d = make (w, _("New Solid"), _("Create"));
            var g = new PreferencesGroup (_("Solid"));
            var name = new EntryRow (_("Name"));
            name.text = c.unique_layer_name (_("Solid"));
            g.add_row (name);
            var width = new SpinRow (_("Width"), null, 1, 30000, 1, c.width);
            var height = new SpinRow (_("Height"), null, 1, 30000, 1, c.height);
            g.add_row (width);
            g.add_row (height);
            ColorPickerButton col;
            g.add_row (color_row (_("Color"), { 0.9, 0.3, 0.2, 1 }, out col));
            d.custom_area.append (g);
            d.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                w.doc.edit (_("New Solid"), () => {
                    var cc = col.color;
                    var l = Factory.solid (c, name.text, { cc.red, cc.green, cc.blue, 1 }, (int) width.value, (int) height.value);
                    c.add_layer (l, 0);
                    w.doc.select_layer (l);
                });
            });
            d.present ();
        }

        public void solid (KeyframeWindow w, Layer l) {
            var d = make (w, _("Solid Settings"), _("Apply"));
            var g = new PreferencesGroup (_("Solid"));
            var width = new SpinRow (_("Width"), null, 1, 30000, 1, l.solid_width);
            var height = new SpinRow (_("Height"), null, 1, 30000, 1, l.solid_height);
            g.add_row (width);
            g.add_row (height);
            ColorPickerButton col;
            g.add_row (color_row (_("Color"), l.solid_color, out col));
            d.custom_area.append (g);
            d.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                w.doc.edit (_("Solid Settings"), () => {
                    var cc = col.color;
                    l.solid_color = { cc.red, cc.green, cc.blue, 1 };
                    l.solid_width = (int) width.value;
                    l.solid_height = (int) height.value;
                    l.mark_changed ();
                });
            });
            d.present ();
        }

        public void project_settings (KeyframeWindow w) {
            var p = w.doc.project;
            var d = make (w, _("Project Settings"), _("Apply"));
            var g = new PreferencesGroup (_("Color"));
            var depth = new ChoiceRow (_("Depth"), { _("8 bits per channel"), _("16 bits per channel"), _("32 bits per channel, floating point") });
            depth.selected = p.bit_depth <= 8 ? 0 : (p.bit_depth <= 16 ? 1 : 2);
            depth.valign = Align.CENTER;
            g.add_row (depth);
            string[] spaces = { "linear-srgb", "acescg", "linear-rec2020" };
            var ws = new ChoiceRow (_("Working Space"), { ColorManagement.label ("linear-srgb"), ColorManagement.label ("acescg"), ColorManagement.label ("linear-rec2020") });
            for (int i = 0; i < spaces.length; i++) if (spaces[i] == p.working_space) ws.selected = i;
            ws.valign = Align.CENTER;
            g.add_row (ws);
            string[] displays = { "srgb", "rec709", "display-p3", "aces-sdr" };
            var disp = new ChoiceRow (_("Display Transform"), { ColorManagement.label ("srgb"), ColorManagement.label ("rec709"), ColorManagement.label ("display-p3"), ColorManagement.label ("aces-sdr") });
            for (int i = 0; i < displays.length; i++) if (displays[i] == p.display_space) disp.selected = i;
            disp.valign = Align.CENTER;
            g.add_row (disp);
            var blend = new SwitchRow (_("Blend in Linear Light"), _("Off blends in gamma space like most design tools"), p.linear_blending);
            g.add_row (blend);
            var ocio = new ActionRow (_("OpenColorIO Configuration"), p.ocio_config != "" ? Path.get_basename (p.ocio_config) : _("Built-in color spaces"));
            var pick = new Button.with_label (_("Choose"));
            pick.valign = Align.CENTER;
            string chosen = p.ocio_config;
            pick.clicked.connect (() => {
                var fd = new FileDialog ();
                fd.title = _("Choose an OpenColorIO Configuration");
                fd.open.begin (w, null, (o, res) => {
                    try {
                        var f = fd.open.end (res);
                        if (f != null) {
                            chosen = f.get_path ();
                            ocio.subtitle = Path.get_basename (chosen);
                        }
                    } catch (Error e) {
                    }
                });
            });
            ocio.add_suffix (pick);
            g.add_row (ocio);
            d.custom_area.append (g);
            d.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                w.doc.edit (_("Project Settings"), () => {
                    p.bit_depth = depth.selected == 0 ? 8 : (depth.selected == 1 ? 16 : 32);
                    p.working_space = spaces[ws.selected];
                    p.display_space = displays[disp.selected];
                    p.linear_blending = blend.active;
                    p.ocio_config = chosen;
                    if (chosen != "") {
                        try {
                            ColorManagement.active_config = OcioConfig.load (chosen);
                        } catch (Error e) {
                            w.toast (_("Could not read the configuration: %s").printf (e.message));
                        }
                    }
                    p.structure_changed ();
                });
            });
            d.present ();
        }

        public void interpret_footage (KeyframeWindow w, Footage f) {
            var d = make (w, _("Interpret Footage"), _("Apply"));
            var g = new PreferencesGroup (f.name);
            var fps = new SpinRow (_("Assume Frame Rate"), _("0 uses the file's rate"), 0, 240, 0.001, f.fps_override);
            fps.spin_btn.digits = 3;
            g.add_row (fps);
            var loop = new SpinRow (_("Loop"), _("Times"), 1, 1000, 1, f.loop);
            g.add_row (loop);
            var premul = new SwitchRow (_("Premultiplied Alpha"), null, f.premultiplied);
            g.add_row (premul);
            string[] spaces = ColorManagement.builtin_spaces ();
            string[] labels = {};
            foreach (var s in spaces) labels += ColorManagement.label (s);
            var cs = new ChoiceRow (_("Input Color Space"), labels);
            for (int i = 0; i < spaces.length; i++) if (spaces[i] == f.color_space) cs.selected = i;
            cs.valign = Align.CENTER;
            g.add_row (cs);
            var proxy = new ActionRow (_("Proxy"), f.proxy_path != "" ? Path.get_basename (f.proxy_path) : _("None"));
            var use_proxy = new Switch ();
            use_proxy.active = f.use_proxy;
            use_proxy.valign = Align.CENTER;
            var pick = new Button.with_label (_("Choose"));
            pick.valign = Align.CENTER;
            string proxy_path = f.proxy_path;
            pick.clicked.connect (() => {
                var fd = new FileDialog ();
                fd.open.begin (w, null, (o, res) => {
                    try {
                        var file = fd.open.end (res);
                        if (file != null) {
                            proxy_path = file.get_path ();
                            proxy.subtitle = Path.get_basename (proxy_path);
                        }
                    } catch (Error e) {
                    }
                });
            });
            proxy.add_suffix (pick);
            proxy.add_suffix (use_proxy);
            g.add_row (proxy);
            d.custom_area.append (g);
            d.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                w.doc.edit (_("Interpret Footage"), () => {
                    f.fps_override = fps.value;
                    f.loop = (int) loop.value;
                    f.premultiplied = premul.active;
                    f.color_space = spaces[cs.selected];
                    f.proxy_path = proxy_path;
                    f.use_proxy = use_proxy.active && proxy_path != "";
                    w.doc.service.renderer.media.forget (f.path);
                    foreach (var c in w.doc.project.comps_using (f.id)) c.layer_changed (null);
                    w.doc.project.structure_changed ();
                });
            });
            d.present ();
        }

        public void precompose (KeyframeWindow w) {
            var doc = w.doc;
            if (doc.comp == null || doc.selection.size == 0) return;
            text_prompt (w, _("Pre-compose"), _("Pre-comp %d").printf (doc.project.compositions ().size), (name) => {
                doc.edit (_("Pre-compose"), () => {
                    var parent = doc.comp;
                    var nested = new Composition (name, parent.width, parent.height, parent.fps, parent.duration);
                    doc.project.add_item (nested);
                    int index = parent.layers.size;
                    var moved = new Gee.ArrayList<Layer> ();
                    foreach (var l in parent.layers) if (doc.selection.contains (l)) moved.add (l);
                    foreach (var l in moved) index = int.min (index, parent.index_of (l));
                    foreach (var l in moved) {
                        parent.layers.remove (l);
                        l.comp = nested;
                        nested.layers.add (l);
                    }
                    foreach (var l in moved) {
                        if (l.parent_id != "" && nested.layer_by_id (l.parent_id) == null) l.parent_id = "";
                        if (l.matte_id != "" && nested.layer_by_id (l.matte_id) == null) {
                            l.matte_id = "";
                            l.matte_mode = MatteMode.NONE;
                        }
                    }
                    var pl = Factory.precomp_layer (parent, nested);
                    parent.add_layer (pl, index);
                    doc.selection.clear ();
                    doc.selection.add (pl);
                    nested.layer_changed (null);
                });
                doc.structure_changed ();
                doc.selection_changed ();
            }, _("Name"));
        }

        public void expression (KeyframeWindow w, Property p) {
            var d = make (w, _("Expression: %s").printf (p.name), _("Apply"));
            d.set_default_size (560, 0);
            var view = new TextView ();
            view.monospace = true;
            view.wrap_mode = WrapMode.WORD_CHAR;
            view.buffer.text = p.expression;
            view.height_request = 180;
            view.add_css_class ("keyframe-source-text");
            view.top_margin = 10;
            view.left_margin = 12;
            view.right_margin = 12;
            view.bottom_margin = 10;
            var sw = new ScrolledWindow ();
            sw.child = view;
            sw.min_content_height = 180;
            var code = new PreferencesGroup (_("Expression"), _("Use time, value, wiggle(freq, amp), loopOut(), ease(), linear(), valueAtTime(t), thisComp.layer(\"Name\") and effect(\"Slider Control\")(\"Slider\")."));
            var code_row = new PreferencesRow ();
            code_row.child = sw;
            code_row.activatable = false;
            code.add_row (code_row);
            d.custom_area.append (code);
            var enabled = new SwitchRow (_("Enabled"), null, p.expression_enabled);
            var g = new PreferencesGroup (_("Options"));
            g.add_row (enabled);
            var links = new ChoiceRow (_("Link to Property"), link_labels (w, p), _("Choose a property to reference with a pick whip"));
            links.valign = Align.CENTER;
            links.notify["selected"].connect (() => {
                var refs = link_targets (w, p);
                if (links.selected == 0 || links.selected > refs.size) return;
                var target = refs[(int) links.selected - 1];
                var from = p.owner_layer ();
                if (from != null) view.buffer.text = Expressions.reference_for (from, target);
            });
            g.add_row (links);
            d.custom_area.append (g);
            if (p.expression_error != "") {
                var err = new Label (p.expression_error);
                err.wrap = true;
                err.xalign = 0;
                err.add_css_class ("error");
                d.custom_area.append (err);
            }
            d.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                w.doc.edit (_("Expression"), () => {
                    p.expression = view.buffer.text;
                    p.expression_enabled = enabled.active;
                    p.expression_error = "";
                    p.touch ();
                });
                w.timeline.rebuild ();
            });
            d.present ();
        }

        private Gee.ArrayList<Property> link_targets (KeyframeWindow w, Property self) {
            var r = new Gee.ArrayList<Property> ();
            if (w.doc.comp == null) return r;
            foreach (var l in w.doc.comp.layers) {
                foreach (var p in l.all_props ()) {
                    if (p == self || p.kind == PropKind.TEXT) continue;
                    if (p.path_string ().has_prefix ("material") || p.path_string ().has_prefix ("audio")) continue;
                    r.add (p);
                }
            }
            return r;
        }

        private string[] link_labels (KeyframeWindow w, Property self) {
            string[] r = { _("Choose") };
            foreach (var p in link_targets (w, self)) {
                var l = p.owner_layer ();
                r += "%s: %s".printf (l != null ? l.name : "", p.name);
            }
            return r;
        }

        public void keyframe_velocity (KeyframeWindow w, Property? p, Keyframe k) {
            if (p == null) return;
            int i = p.keys.index_of (k);
            var times = p.effective_times ();
            var d = make (w, _("Keyframe Velocity"), _("Apply"));
            var g = new PreferencesGroup (_("Incoming"));
            double in_speed = 0, in_infl = 33.33, out_speed = 0, out_infl = 33.33;
            if (i > 0) {
                double dt = times[i] - times[i - 1];
                double dv = p.dims == 1 ? p.keys[i].value[0] - p.keys[i - 1].value[0] : 1;
                in_infl = (1 - k.ease_in_x) * 100;
                double x = 1 - k.ease_in_x;
                in_speed = x > 1e-6 ? (1 - k.ease_in_y) / x * dv / dt : 0;
            }
            if (i < p.keys.size - 1) {
                double dt = times[i + 1] - times[i];
                double dv = p.dims == 1 ? p.keys[i + 1].value[0] - p.keys[i].value[0] : 1;
                out_infl = k.ease_out_x * 100;
                out_speed = k.ease_out_x > 1e-6 ? k.ease_out_y / k.ease_out_x * dv / dt : 0;
            }
            var ins = new SpinRow (_("Speed"), _("Units per second"), -1e6, 1e6, 0.1, in_speed);
            var inf = new SpinRow (_("Influence"), _("Percent"), 0.1, 100, 1, in_infl);
            g.add_row (ins);
            g.add_row (inf);
            d.custom_area.append (g);
            var g2 = new PreferencesGroup (_("Outgoing"));
            var outs = new SpinRow (_("Speed"), _("Units per second"), -1e6, 1e6, 0.1, out_speed);
            var outf = new SpinRow (_("Influence"), _("Percent"), 0.1, 100, 1, out_infl);
            g2.add_row (outs);
            g2.add_row (outf);
            d.custom_area.append (g2);
            ins.sensitive = inf.sensitive = i > 0;
            outs.sensitive = outf.sensitive = i < p.keys.size - 1;
            d.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                w.doc.edit (_("Keyframe Velocity"), () => {
                    if (i > 0) {
                        double dt = times[i] - times[i - 1];
                        double dv = p.dims == 1 ? p.keys[i].value[0] - p.keys[i - 1].value[0] : 1;
                        double x = inf.value / 100.0;
                        k.in_interp = Interp.BEZIER;
                        k.ease_in_x = 1 - x;
                        k.ease_in_y = dv.abs () > 1e-12 ? 1 - ins.value * x * dt / dv : 1;
                        k.auto_bezier = false;
                    }
                    if (i < p.keys.size - 1) {
                        double dt = times[i + 1] - times[i];
                        double dv = p.dims == 1 ? p.keys[i + 1].value[0] - p.keys[i].value[0] : 1;
                        double x = outf.value / 100.0;
                        k.out_interp = Interp.BEZIER;
                        k.ease_out_x = x;
                        k.ease_out_y = dv.abs () > 1e-12 ? outs.value * x * dt / dv : 0;
                        k.auto_bezier = false;
                    }
                    p.touch ();
                });
            });
            d.present ();
        }

        public void value_popover (KeyframeWindow w, Widget anchor, Property p, double x, double y) {
            var l = p.owner_layer ();
            if (l == null) return;
            var pop = new Popover ();
            pop.set_parent (anchor);
            pop.pointing_to = { (int) x, (int) y, 1, 1 };
            var g = new PreferencesGroup ();
            var ed = PropRow.create (w.doc, l, p);
            ed.request_expression.connect ((pp) => expression (w, pp));
            g.add_row (ed);
            g.width_request = 360;
            pop.child = g;
            pop.closed.connect (() => {
                pop.unparent ();
            });
            pop.popup ();
        }
    }
}
