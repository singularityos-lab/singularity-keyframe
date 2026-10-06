using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Keyframe {

    public interface PropRow : Widget {
        public signal void request_expression (Property p);
        public abstract void refresh ();

        public static PropRow create (Document doc, Layer layer, Property prop) {
            if (prop.kind == PropKind.CHOICE || prop.kind == PropKind.LAYER) return new ChoicePropEditor (doc, layer, prop);
            return new PropEditor (doc, layer, prop);
        }
    }

    public class PropActions : Object {
        private Document doc;
        private Layer layer;
        private Property prop;
        public ToggleButton? stopwatch = null;
        private Button expr_button;
        private ActionRow host;
        public bool updating = false;

        public signal void request_expression (Property p);

        public PropActions (Document doc, Layer layer, Property prop, ActionRow host, Box suffix, Box? prefix = null) {
            this.doc = doc;
            this.layer = layer;
            this.prop = prop;
            this.host = host;
            if (prop.animatable) {
                stopwatch = new ToggleButton ();
                stopwatch.icon_name = "keyframe-stopwatch-symbolic";
                stopwatch.tooltip_text = _("Animate This Property");
                stopwatch.add_css_class ("flat");
                stopwatch.valign = Align.CENTER;
                stopwatch.active = prop.keys.size > 0;
                stopwatch.toggled.connect (() => {
                    if (updating) return;
                    doc.edit (_("Toggle Animation"), () => {
                        if (stopwatch.active) add_key ();
                        else prop.clear_keys ();
                    });
                });
                if (prefix != null) prefix.append (stopwatch);
                else host.add_prefix (stopwatch);
                var key_btn = new Button.from_icon_name ("keyframe-add-symbolic");
                key_btn.tooltip_text = _("Add or Remove Keyframe at Current Time");
                key_btn.add_css_class ("flat");
                key_btn.valign = Align.CENTER;
                key_btn.clicked.connect (() => {
                    doc.edit (_("Keyframe"), () => {
                        double lt = layer.layer_time (doc.time);
                        var k = prop.key_at (lt, 0.5 / (layer.comp != null ? layer.comp.fps : 30));
                        if (k != null) prop.remove_key (k);
                        else add_key ();
                    });
                });
                suffix.append (key_btn);
            }
            expr_button = new Button.with_label ("=");
            expr_button.tooltip_text = _("Expression");
            expr_button.add_css_class ("flat");
            expr_button.valign = Align.CENTER;
            expr_button.clicked.connect (() => request_expression (prop));
            suffix.append (expr_button);
        }

        public void add_key () {
            double lt = layer.layer_time (doc.time);
            if (prop.kind == PropKind.PATH) prop.set_path_key (lt, prop.path_at (lt));
            else if (prop.kind == PropKind.TEXT) prop.set_text_key (lt, prop.text_at (lt));
            else prop.set_key (lt, prop.value_at (lt));
        }

        public void set_value (double[] v) {
            double lt = layer.layer_time (doc.time);
            doc.edit_merged ("value:" + layer.id + ":" + prop.path_string (), _("Change Value"), () => prop.set_value_at (lt, v));
        }

        public void refresh () {
            updating = true;
            if (stopwatch != null) stopwatch.active = prop.keys.size > 0;
            if (prop.has_expression ()) expr_button.add_css_class ("accent");
            else expr_button.remove_css_class ("accent");
            host.subtitle = prop.has_expression () && prop.expression_error != "" ? prop.expression_error : "";
            updating = false;
        }
    }

    public class ChoicePropEditor : ChoiceRow, PropRow {
        public Property prop;
        public Layer layer;
        private Document doc;
        private PropActions actions;
        private bool updating = false;

        private static string[] labels_for (Layer layer, Property prop) {
            if (prop.kind == PropKind.CHOICE) return prop.choices;
            string[] names = { _("None") };
            if (layer.comp != null) foreach (var l in layer.comp.layers) names += "%d. %s".printf (layer.comp.index_of (l) + 1, l.name);
            return names;
        }

        public ChoicePropEditor (Document doc, Layer layer, Property prop) {
            base (prop.name, labels_for (layer, prop));
            this.doc = doc;
            this.layer = layer;
            this.prop = prop;
            var box = new Box (Orientation.HORIZONTAL, 4);
            box.valign = Align.CENTER;
            actions = new PropActions (doc, layer, prop, this, box);
            actions.request_expression.connect ((p) => request_expression (p));
            add_suffix (box);
            notify["selected"].connect (() => {
                if (updating) return;
                actions.set_value ({ prop.kind == PropKind.LAYER ? (double) selected - 1 : (double) selected });
            });
            refresh ();
        }

        public void refresh () {
            updating = true;
            double lt = layer.layer_time (doc.time);
            if (prop.kind == PropKind.CHOICE) selected = (uint) ((int) Math.round (prop.scalar_at (lt))).clamp (0, prop.choices.length - 1);
            else selected = (uint) ((int) Math.round (prop.scalar_at (lt)) + 1).clamp (0, 1000);
            actions.refresh ();
            updating = false;
        }
    }

    public class PropEditor : ActionRow, PropRow {
        public Property prop;
        public Layer layer;
        private Document doc;
        private PropActions actions;
        private SpinButton[] spins = {};
        private ColorPickerButton? color_btn = null;
        private Switch? toggle_switch = null;
        private Entry? text_entry = null;
        private bool updating = false;

        public const int ROW_AVAILABLE = 340;
        private Label error_label;

        public PropEditor (Document doc, Layer layer, Property prop) {
            base (prop.name);
            this.doc = doc;
            this.layer = layer;
            this.prop = prop;
            var box = new Box (Orientation.HORIZONTAL, 4);
            box.valign = Align.CENTER;
            build_editor (box);
            var head = new Box (Orientation.HORIZONTAL, 6);
            actions = new PropActions (doc, layer, prop, this, box, head);
            actions.request_expression.connect ((p) => request_expression (p));
            var title_label = new Label (prop.name);
            title_label.add_css_class ("title");
            title_label.xalign = 0;
            title_label.hexpand = true;
            title_label.valign = Align.CENTER;
            title_label.ellipsize = Pango.EllipsizeMode.END;
            title_label.tooltip_text = prop.name;
            head.append (title_label);
            error_label = new Label ("");
            error_label.add_css_class ("subtitle");
            error_label.add_css_class ("error");
            error_label.xalign = 0;
            error_label.wrap = true;
            error_label.visible = false;
            var layout = new Box (Orientation.VERTICAL, 6);
            layout.margin_top = 8;
            layout.margin_bottom = 8;
            layout.margin_start = 12;
            layout.margin_end = 12;
            layout.append (head);
            int tmin, tnat, bmin, bnat, sw = 0;
            title_label.measure (Orientation.HORIZONTAL, -1, out tmin, out tnat, null, null);
            box.measure (Orientation.HORIZONTAL, -1, out bmin, out bnat, null, null);
            if (actions.stopwatch != null) sw = 40;
            if (sw + tnat + 12 + bnat > ROW_AVAILABLE) {
                box.halign = Align.END;
                layout.append (box);
            } else {
                head.append (box);
            }
            layout.append (error_label);
            child = layout;
            refresh ();
        }

        private int digits () {
            switch (prop.kind) {
                case PropKind.PERCENT:
                case PropKind.ANGLE:
                    return 1;
                case PropKind.CHOICE:
                case PropKind.TOGGLE:
                    return 0;
                default:
                    return prop.ui_max - prop.ui_min <= 10 ? 3 : 1;
            }
        }

        private void build_editor (Box box) {
            switch (prop.kind) {
                case PropKind.COLOR:
                    color_btn = new ColorPickerButton ();
                    color_btn.valign = Align.CENTER;
                    color_btn.color_changed.connect ((c) => {
                        if (updating) return;
                        actions.set_value ({ c.red, c.green, c.blue, c.alpha });
                    });
                    box.append (color_btn);
                    break;
                case PropKind.TOGGLE:
                    toggle_switch = new Switch ();
                    toggle_switch.valign = Align.CENTER;
                    toggle_switch.notify["active"].connect (() => {
                        if (updating) return;
                        actions.set_value ({ toggle_switch.active ? 1 : 0 });
                    });
                    box.append (toggle_switch);
                    break;
                case PropKind.TEXT:
                    text_entry = new Entry ();
                    text_entry.width_chars = 14;
                    text_entry.valign = Align.CENTER;
                    text_entry.activate.connect (() => {
                        double lt = layer.layer_time (doc.time);
                        var d = prop.text_at (lt).copy ();
                        d.text = text_entry.text;
                        doc.edit (_("Edit Text"), () => {
                            if (prop.keys.size > 0) prop.set_text_key (lt, d);
                            else {
                                prop.text = d;
                                prop.touch ();
                            }
                        });
                    });
                    box.append (text_entry);
                    break;
                case PropKind.PATH:
                    var l = new Label (_("Edit in the viewer"));
                    l.add_css_class ("dim-label");
                    box.append (l);
                    break;
                default:
                    int n = prop.dims;
                    if (prop.key == "position" || prop.key == "anchor" || prop.key == "scale" || prop.key == "orientation") {
                        if (!layer.three_d && n > 2) n = 2;
                    }
                    var spin_box = new Box (n > 1 ? Orientation.VERTICAL : Orientation.HORIZONTAL, 2);
                    spin_box.valign = Align.CENTER;
                    box.append (spin_box);
                    for (int i = 0; i < n; i++) {
                        double lo = prop.min > -1e300 ? prop.min : -1e6, hi = prop.max < 1e300 ? prop.max : 1e6;
                        var sb = new SpinButton.with_range (lo, hi, prop.ui_max - prop.ui_min <= 10 ? 0.01 : 1);
                        sb.digits = digits ();
                        sb.width_chars = 7;
                        sb.valign = Align.CENTER;
                        int idx = i;
                        sb.value_changed.connect (() => {
                            if (updating) return;
                            var v = prop.value_at (layer.layer_time (doc.time));
                            v[idx] = sb.value;
                            actions.set_value (v);
                        });
                        spins += sb;
                        spin_box.append (sb);
                    }
                    break;
            }
        }

        public void refresh () {
            updating = true;
            double lt = layer.layer_time (doc.time);
            switch (prop.kind) {
                case PropKind.COLOR:
                    var v = prop.value_at (lt);
                    var c = Gdk.RGBA ();
                    c.red = (float) v[0].clamp (0, 1);
                    c.green = (float) v[1].clamp (0, 1);
                    c.blue = (float) v[2].clamp (0, 1);
                    c.alpha = (float) (v.length > 3 ? v[3] : 1);
                    color_btn.color = c;
                    break;
                case PropKind.TOGGLE:
                    toggle_switch.active = prop.scalar_at (lt) > 0.5;
                    break;
                case PropKind.TEXT:
                    if (!text_entry.has_focus) text_entry.text = prop.text_at (lt).text;
                    break;
                case PropKind.PATH:
                    break;
                default:
                    var v = prop.value_at (lt);
                    for (int i = 0; i < spins.length && i < v.length; i++) if (!spins[i].has_focus) spins[i].value = v[i];
                    break;
            }
            actions.refresh ();
            if (error_label != null) {
                error_label.label = prop.has_expression () && prop.expression_error != "" ? prop.expression_error : "";
                error_label.visible = error_label.label != "";
            }
            updating = false;
        }
    }

    public class ChoiceRow : SelectionRow {
        private static bool compact_value (Widget w) {
            var l = w as Label;
            if (l != null && l.has_css_class ("dim-label")) {
                l.ellipsize = Pango.EllipsizeMode.END;
                l.max_width_chars = 12;
                l.notify["label"].connect (() => l.tooltip_text = l.label);
                l.tooltip_text = l.label;
                return true;
            }
            for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) if (compact_value (c)) return true;
            return false;
        }

        private string[] labels;
        private uint _selected = 0;

        public uint selected {
            get { return _selected; }
            set {
                if (value >= labels.length || value == _selected) return;
                _selected = value;
                current_value = labels[value];
            }
        }

        public ChoiceRow (string title, string[] labels, string? subtitle = null) {
            base (title, labels, labels.length > 0 ? labels[0] : "");
            this.labels = labels;
            compact_value (this);
            if (subtitle != null && subtitle != "") this.subtitle = subtitle;
            ((SelectionRow) this).selected.connect ((item) => {
                for (uint i = 0; i < this.labels.length; i++) {
                    if (this.labels[i] == item) {
                        if (i != _selected) {
                            _selected = i;
                            notify_property ("selected");
                        }
                        return;
                    }
                }
            });
        }
    }
}
