using Gtk;
using Singularity.Widgets;
using Singularity.Assets;

namespace Singularity.Apps.Keyframe {

    public class LibraryPanel : Box {
        private KeyframeWindow win;
        private string kind = "color";

        public LibraryPanel (KeyframeWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 12);
            this.win = win;
            AssetLibrary.get_default ().changed.connect (fill);
            fill ();
        }

        private void fill () {
            Widget? c;
            while ((c = get_first_child ()) != null) remove (c);
            string[,] kinds = {
                { "color", _("Colors"), _("No Saved Colors"), _("Select a color property or a solid, then press Add.") },
                { "shape", _("Shapes"), _("No Saved Shapes"), _("Select a shape layer, then press Add.") },
                { "text", _("Texts"), _("No Saved Texts"), _("Select a text layer, then press Add.") },
                { "footage", _("Footage"), _("No Saved Footage"), _("Select footage in the project, then press Add.") }
            };
            for (int k = 0; k < kinds.length[0]; k++) append (kind_group (kinds[k, 0], kinds[k, 1], kinds[k, 2], kinds[k, 3]));
        }

        private PreferencesGroup kind_group (string kind_id, string title, string empty_title, string empty_hint) {
            var g = new PreferencesGroup (title);
            var add = new Button.with_label (_("Add"));
            add.valign = Align.CENTER;
            add.tooltip_text = _("Add the selection to the shared library");
            add.clicked.connect (() => {
                kind = kind_id;
                add_selection ();
            });
            g.add_header_suffix (add);
            var items = AssetLibrary.get_default ().list (kind_id, null);
            if (items.size == 0) {
                var row = new ActionRow (empty_title, empty_hint);
                row.activatable = false;
                g.add_row (row);
                return g;
            }
            foreach (var a in items) {
                var row = new ActionRow (a.name != "" ? a.name : _("Untitled"), subtitle_for (a));
                if (a.kind == "color") {
                    var sw = new DrawingArea ();
                    sw.set_size_request (22, 22);
                    sw.valign = Align.CENTER;
                    sw.margin_end = 10;
                    var hex = a.get_field ("color");
                    sw.set_draw_func ((d, cr, w, h) => {
                        var rgba = Gdk.RGBA ();
                        if (!rgba.parse (hex)) return;
                        cr.arc (w / 2.0, h / 2.0, 10, 0, Math.PI * 2);
                        cr.set_source_rgba (rgba.red, rgba.green, rgba.blue, rgba.alpha);
                        cr.fill ();
                    });
                    row.add_prefix (sw);
                }
                var use = new Button.with_label (_("Use"));
                use.valign = Align.CENTER;
                var asset = a;
                use.clicked.connect (() => use_asset (asset));
                row.add_suffix (use);
                g.add_row (row);
            }
            return g;
        }

        private string subtitle_for (Asset a) {
            switch (a.kind) {
                case "color": return a.get_field ("color");
                case "text": return a.get_field ("text");
                case "footage": return Path.get_basename (a.get_field ("path"));
                default: return a.app;
            }
        }

        private double[]? rgba_of (string hex) {
            var c = Gdk.RGBA ();
            if (!c.parse (hex)) return null;
            return { c.red, c.green, c.blue, c.alpha };
        }

        private string hex_of (double[] v) {
            return "#%02x%02x%02x".printf ((int) (v[0].clamp (0, 1) * 255), (int) (v[1].clamp (0, 1) * 255), (int) (v[2].clamp (0, 1) * 255));
        }

        private void use_asset (Asset a) {
            var doc = win.doc;
            if (doc.comp == null) return;
            switch (a.kind) {
                case "color": {
                    var col = rgba_of (a.get_field ("color"));
                    if (col == null) return;
                    var p = doc.active_property;
                    var l = doc.primary ();
                    if (p != null && p.kind == PropKind.COLOR && p.owner_layer () != null) {
                        var owner = p.owner_layer ();
                        doc.edit (_("Apply Color"), () => p.set_value_at (owner.layer_time (doc.time), col));
                    } else if (l != null && l.kind == LayerKind.SOLID) {
                        doc.edit (_("Apply Color"), () => {
                            l.solid_color = col;
                            l.mark_changed ();
                        });
                    } else {
                        doc.edit (_("New Solid"), () => {
                            var s = Factory.solid (doc.comp, a.name != "" ? a.name : _("Solid"), col);
                            doc.comp.add_layer (s, 0);
                            doc.select_layer (s);
                        });
                    }
                    break;
                }
                case "text":
                    doc.edit (_("New Text Layer"), () => {
                        var t = Factory.text_layer (doc.comp, a.get_field ("text", a.name));
                        var d = t.text_group.prop ("source-text").text;
                        d.font = a.get_field ("font", d.font);
                        d.size = a.get_number ("size", d.size);
                        var col = rgba_of (a.get_field ("color", "#ffffff"));
                        if (col != null) d.fill = col;
                        doc.comp.add_layer (t, 0);
                        doc.select_layer (t);
                    });
                    break;
                case "shape":
                    doc.edit (_("New Shape Layer"), () => {
                        var l = Factory.shape_layer (doc.comp, a.name);
                        var g = Factory.shape_group (a.name != "" ? a.name : _("Shape"));
                        g.group ("contents").add<PropGroup> (Factory.path_shape (BezPath.parse (a.get_field ("path", "c"))));
                        var col = rgba_of (a.get_field ("fill", "#ff8a33"));
                        if (col != null) g.group ("contents").add<PropGroup> (Factory.fill (col));
                        l.contents.add<PropGroup> (g);
                        doc.comp.add_layer (l, 0);
                        doc.select_layer (l);
                    });
                    break;
                case "footage":
                    win.import_path (a.get_field ("path"));
                    break;
            }
        }

        private void add_selection () {
            var doc = win.doc;
            var lib = AssetLibrary.get_default ();
            var a = new Asset ();
            a.kind = kind;
            a.app = "dev.sinty.keyframe";
            var l = doc.primary ();
            double lt = l != null ? l.layer_time (doc.time) : 0;
            switch (kind) {
                case "color":
                    var p = doc.active_property;
                    if (p != null && p.kind == PropKind.COLOR) {
                        a.set_field ("color", hex_of (p.value_at (lt)));
                        a.name = p.name;
                    } else if (l != null && l.kind == LayerKind.SOLID) {
                        a.set_field ("color", hex_of (l.solid_color));
                        a.name = l.name;
                    } else {
                        win.toast (_("Select a color property or a solid first"));
                        return;
                    }
                    break;
                case "text":
                    if (l == null || l.text_group == null) {
                        win.toast (_("Select a text layer first"));
                        return;
                    }
                    var d = l.text_group.prop ("source-text").text_at (lt);
                    a.name = l.name;
                    a.set_field ("text", d.text);
                    a.set_field ("font", d.font);
                    a.set_field ("size", "%g".printf (d.size));
                    a.set_field ("color", hex_of (d.fill));
                    break;
                case "shape":
                    if (l == null || l.contents == null) {
                        win.toast (_("Select a shape layer first"));
                        return;
                    }
                    var scene = new ShapeRenderer (lt).build (l.contents, new Mat4 ());
                    BezPath? first = null;
                    foreach (var n in scene.nodes) if (n.paths.size > 0 && first == null) first = n.paths[0];
                    if (first == null) return;
                    a.name = l.name;
                    a.set_field ("path", first.serialize ());
                    foreach (var op in scene.ops) if (op.style.type == "shape.fill") a.set_field ("fill", hex_of (op.style.vec ("color", lt)));
                    break;
                case "footage":
                    var f = win.project_panel.selected_item as Footage;
                    if (f == null) {
                        win.toast (_("Select footage in the project first"));
                        return;
                    }
                    a.name = f.name;
                    a.set_field ("path", f.path);
                    break;
            }
            try {
                lib.add (a);
                win.toast (_("Added to the library"));
            } catch (Error e) {
                win.toast (e.message);
            }
        }
    }
}
