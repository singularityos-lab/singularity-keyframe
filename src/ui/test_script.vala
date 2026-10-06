using Gtk;

namespace Singularity.Apps.Keyframe {

    public class TestScript : Object {
        private static bool started = false;
        private KeyframeWindow win;
        private string[] lines;
        private int index = 0;

        public static void maybe_run (KeyframeWindow win) {
            string? path = Environment.get_variable ("SINGULARITY_KEYFRAME_TEST_SCRIPT");
            if (path == null || path == "" || started) return;
            started = true;
            string text;
            try {
                FileUtils.get_contents (path, out text);
            } catch (Error e) {
                printerr ("script: %s\n", e.message);
                return;
            }
            var s = new TestScript ();
            s.win = win;
            s.lines = text.split ("\n");
            s.ref ();
            Timeout.add (900, () => {
                s.step ();
                return Source.REMOVE;
            });
        }

        private void step () {
            while (index < lines.length) {
                string line = lines[index++].strip ();
                if (line == "" || line.has_prefix ("#")) continue;
                uint wait = 400;
                try {
                    wait = run (line);
                } catch (Error e) {
                    printerr ("script: %s failed: %s\n", line, e.message);
                }
                printerr ("script: ok %s\n", line);
                Timeout.add (wait, () => {
                    step ();
                    return Source.REMOVE;
                });
                return;
            }
            printerr ("script: finished\n");
            unref ();
        }

        private static Widget? find_button (Widget w, string label) {
            if (w is Button && ((Button) w).label == label && w.is_visible ()) return w;
            if (w is MenuButton && ((MenuButton) w).label == label && w.is_visible ()) return w;
            for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) {
                var r = find_button (c, label);
                if (r != null) return r;
            }
            return null;
        }

        private uint run (string line) throws Error {
            string[] a = line.split (" ");
            string rest = line.length > a[0].length ? line.substring (a[0].length + 1) : "";
            switch (a[0]) {
                case "sleep":
                    return (uint) int.parse (a[1]);
                case "maximize":
                    win.maximize ();
                    return 900;
                case "dark":
                    Singularity.Style.StyleManager.get_default ().apply_color_scheme (a.length < 2 || a[1] != "off");
                    return 600;
                case "new":
                    win.new_project ();
                    return 900;
                case "open":
                    win.open_project (File.new_for_path (rest));
                    return 1200;
                case "demo":
                    win.load_into_workspace (DemoProject.build (rest));
                    return 1500;
                case "action":
                    win.activate_action (a[1], a.length > 2 ? new Variant.string (a[2]) : null);
                    return 900;
                case "action-int":
                    win.activate_action (a[1], new Variant.int32 (int.parse (a[2])));
                    return 900;
                case "time":
                    win.doc.seek (double.parse (a[1]));
                    return 900;
                case "select":
                    var c = win.doc.comp;
                    int n = int.parse (a[1]) - 1;
                    if (c != null && n >= 0 && n < c.layers.size) win.doc.select_layer (c.layers[n]);
                    return 700;
                case "expand":
                    var cc = win.doc.comp;
                    int m = int.parse (a[1]) - 1;
                    if (cc != null && m >= 0 && m < cc.layers.size) win.timeline.reveal_animated (cc.layers[m]);
                    return 700;
                case "property":
                    var l = win.doc.primary ();
                    if (l != null) {
                        var p = l.root.find (a[1]) as Property;
                        if (p != null) {
                            win.doc.active_property = p;
                            if (p.keys.size > 0) win.doc.select_key (p, p.keys[0], false);
                            else win.doc.selection_changed ();
                        }
                    }
                    return 700;
                case "lower":
                    win.activate_action ("graph-editor", null);
                    return 900;
                case "tab":
                    var stack = find_stack (win.inspector);
                    if (stack != null) stack.visible_child_name = a[1];
                    return 700;
                case "comp":
                    foreach (var comp in win.doc.project.compositions ()) if (comp.name == rest) win.doc.open_comp (comp);
                    return 900;
                case "zoom":
                    win.viewer.set_zoom (double.parse (a[1]));
                    return 700;
                case "click":
                    Widget? b = null;
                    foreach (var top in Gtk.Window.list_toplevels ()) {
                        if (!top.visible) continue;
                        b = find_button (top, rest);
                        if (b != null) break;
                    }
                    if (b == null) throw new FileError.NOENT ("no button %s".printf (rest));
                    if (b is MenuButton) ((MenuButton) b).popup ();
                    else ((Button) b).clicked ();
                    return 900;
                case "play":
                    win.doc.play ();
                    return (uint) (a.length > 1 ? int.parse (a[1]) : 2000);
                case "stop":
                    win.doc.stop ();
                    return 500;
                case "save":
                    NativeFormat.save (win.doc.project, rest);
                    return 600;
                case "queue-output":
                    var q = win.doc.project.render_queue;
                    if (q.size > 0) {
                        q[q.size - 1].outputs[0].format = a[1];
                        q[q.size - 1].outputs[0].path = a[2];
                        q[q.size - 1].start = 0;
                        q[q.size - 1].end = double.parse (a.length > 3 ? a[3] : "1");
                    }
                    return 300;
                case "viewer-drag":
                    Graphene.Point src = { 0, 0 }, dst = { 0, 0 };
                    var p1 = win.viewer.to_view (double.parse (a[1]), double.parse (a[2]));
                    var p2 = win.viewer.to_view (double.parse (a[3]), double.parse (a[4]));
                    win.viewer.compute_point (win, { (float) p1.x, (float) p1.y }, out src);
                    win.viewer.compute_point (win, { (float) p2.x, (float) p2.y }, out dst);
                    printerr ("script: drag %d,%d to %d,%d\n", (int) src.x, (int) src.y, (int) dst.x, (int) dst.y);
                    pointer ("move %d %d press left drag %d %d 20 15 wait 150 release left".printf ((int) src.x, (int) src.y, (int) dst.x, (int) dst.y));
                    return 1500;
                case "viewer-click":
                    Graphene.Point at = { 0, 0 };
                    var pv = win.viewer.to_view (double.parse (a[1]), double.parse (a[2]));
                    win.viewer.compute_point (win, { (float) pv.x, (float) pv.y }, out at);
                    pointer ("move %d %d click left".printf ((int) at.x, (int) at.y));
                    return 900;
                case "import":
                    win.import_path (rest);
                    foreach (var it in win.doc.project.items) {
                        var f = it as Footage;
                        if (f != null && f.path == rest && win.doc.comp != null) win.add_footage_layer (f);
                    }
                    return 1500;
                case "dump":
                    printerr ("script: dump layers=%d selection=%d queue=%d\n", win.doc.comp != null ? win.doc.comp.layers.size : -1, win.doc.selection.size, win.doc.project.render_queue.size);
                    foreach (var rq in win.doc.project.render_queue) printerr ("script: queue %s %s %s\n", rq.status.to_id (), rq.outputs.size > 0 ? rq.outputs[0].path : "", rq.error);
                    return 100;
                case "measure":
                    measure_tree (win.inspector, 0, int.parse (a[1]));
                    return 300;
                case "choice":
                    var parts = rest.split ("|");
                    var cr = find_choice (win.inspector, parts[0]);
                    if (cr == null) throw new FileError.NOENT ("no choice %s".printf (parts[0]));
                    cr.expanded = true;
                    ((Singularity.Widgets.SelectionRow) cr).selected (parts[1]);
                    var pl = win.doc.primary ();
                    printerr ("script: choice %s=%u blend=%s\n", parts[0], cr.selected, pl != null ? pl.blend.label () : "");
                    return 900;
                case "expand-choice":
                    var er = find_choice (win.inspector, rest);
                    if (er != null) er.expanded = true;
                    return 900;
                case "expression":
                    if (win.doc.active_property != null) Dialogs.expression (win, win.doc.active_property);
                    return 1200;
                case "focus-viewer":
                    win.viewer.grab_focus ();
                    printerr ("script: viewer focus %s\n", win.viewer.has_focus.to_string ());
                    return 600;
                case "add-effect":
                    var el = win.doc.primary ();
                    if (el != null) win.doc.edit ("fx", () => {
                        EffectRegistry.add_to_layer (el, rest);
                        el.mark_changed ();
                    });
                    return 900;
                case "timeline-drag":
                    Graphene.Point tp = { 0, 0 };
                    win.timeline.compute_point (win, { (float) win.timeline.left_width, (float) Timeline.HEADER + 40 }, out tp);
                    int tdx = int.parse (a[1]);
                    pointer ("move %d %d press left drag %d %d 20 15 wait 150 release left".printf ((int) tp.x, (int) tp.y, (int) tp.x + tdx, (int) tp.y));
                    return 1500;
                case "inspector-end":
                    var ist = find_stack (win.inspector);
                    var isw = ist != null ? ist.visible_child as ScrolledWindow : null;
                    if (isw != null) isw.vadjustment.value = isw.vadjustment.upper - isw.vadjustment.page_size - (a.length > 1 ? double.parse (a[1]) : 0);
                    return 800;
                case "inspector-at":
                    var ast = find_stack (win.inspector);
                    var asw = ast != null ? ast.visible_child as ScrolledWindow : null;
                    if (asw != null) asw.vadjustment.value = double.parse (a[1]);
                    if (asw != null) printerr ("script: inspector upper %.0f\n", asw.vadjustment.upper);
                    return 800;
                case "timeline-width":
                    printerr ("script: timeline left %d\n", win.timeline.left_width);
                    return 100;
                case "close-dialogs":
                    foreach (var top in Gtk.Window.list_toplevels ()) {
                        var dlg = top as Singularity.Widgets.AppDialog;
                        if (dlg != null && dlg.visible) dlg.close_dialog ();
                    }
                    return 900;
                case "deselect":
                    win.doc.select_layer (null);
                    return 500;
                case "shot":
                    string dir = Environment.get_variable ("KEYFRAME_SHOTS") ?? Environment.get_tmp_dir ();
                    Process.spawn_command_line_async ("grim %s".printf (GLib.Shell.quote (Path.build_filename (dir, a[1] + ".png"))));
                    return 1000;
                default:
                    throw new FileError.INVAL ("unknown command %s".printf (a[0]));
            }
        }

        private static void pointer (string args) {
            string vptr = Environment.get_variable ("KEYFRAME_VPTR") ?? "vptr";
            try {
                Process.spawn_command_line_async ("%s %s".printf (GLib.Shell.quote (vptr), args));
            } catch (Error e) {
                printerr ("script: pointer %s\n", e.message);
            }
        }

        private static void measure_tree (Widget w, int depth, int limit) {
            int min, nat, mb, nb;
            w.measure (Orientation.HORIZONTAL, -1, out min, out nat, out mb, out nb);
            if (min >= limit) {
                string extra = "";
                if (w is Label) extra = ((Label) w).label;
                printerr ("script: measure %s%s min=%d %s\n", string.nfill (depth, ' '), w.get_type ().name (), min, extra);
            }
            for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) measure_tree (c, depth + 1, limit);
        }

        private static ChoiceRow? find_choice (Widget w, string title) {
            if (w is ChoiceRow && ((ChoiceRow) w).title == title && w.is_drawable ()) return (ChoiceRow) w;
            for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) {
                var r = find_choice (c, title);
                if (r != null) return r;
            }
            return null;
        }

        private static Stack? find_stack (Widget w) {
            if (w is Stack) return (Stack) w;
            for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) {
                var r = find_stack (c);
                if (r != null) return r;
            }
            return null;
        }
    }

    namespace DemoProject {
        public Project build (string kind) {
            var p = new Project ();
            var comp = new Composition ("Title", 1280, 720, 30, 4);
            comp.background = { 0.04, 0.04, 0.07, 1 };
            p.add_item (comp);
            var bg = Factory.solid (comp, "Background", { 0.1, 0.1, 0.2, 1 });
            var ramp = EffectRegistry.add_to_layer (bg, "gradient-ramp");
            ramp.prop ("end").value = { 1280, 720, 0 };
            ramp.prop ("start-color").value = { 0.03, 0.04, 0.12, 1 };
            ramp.prop ("end-color").value = { 0.32, 0.06, 0.24, 1 };
            comp.add_layer (bg, 0);
            var shape = Factory.shape_layer (comp, "Orbit");
            var grp = Factory.shape_group ("Star");
            grp.group ("contents").add<PropGroup> (Factory.star (false, 5, 46, 20));
            grp.group ("contents").add<PropGroup> (Factory.stroke ({ 1, 1, 1, 1 }, 3));
            grp.group ("contents").add<PropGroup> (Factory.fill ({ 1, 0.55, 0.12, 1 }));
            shape.contents.add<PropGroup> (grp);
            var rep = Factory.repeater (6);
            rep.group ("transform").prop ("position").value = { 0, 0 };
            rep.group ("transform").prop ("anchor").value = { 0, 160 };
            rep.group ("transform").prop ("rotation").value = { 60 };
            rep.group ("transform").prop ("end-opacity").value = { 35 };
            shape.contents.add<PropGroup> (rep);
            var pos = shape.transform.prop ("position");
            pos.set_key (0, { 260, 520, 0 });
            pos.set_key (1.5, { 640, 300, 0 });
            pos.set_key (3, { 1020, 480, 0 });
            foreach (var k in pos.keys) k.set_easy_ease ();
            var rot = shape.transform.prop ("rotation");
            rot.set_key (0, { 0 });
            rot.set_key (4, { 240 });
            shape.transform.prop ("scale").value = { 70, 70, 100 };
            shape.motion_blur = true;
            comp.add_layer (shape, 0);
            var line = Factory.shape_layer (comp, "Wave");
            var lg = Factory.shape_group ("Wave");
            var path = new BezPath ();
            path.closed = false;
            path.add (-420, 0, 0, 0, 140, -120);
            path.add (0, 0, -140, 120, 140, -120);
            path.add (420, 0, -140, 120, 0, 0);
            lg.group ("contents").add<PropGroup> (Factory.path_shape (path));
            var ls = Factory.gradient_stroke (8);
            ls.attrs["cap"] = "round";
            ls.prop ("stops").value = { 0, 0.2, 0.8, 1, 1, 1, 0.9, 0.3, 0.9, 1 };
            ls.prop ("start").value = { -420, 0 };
            ls.prop ("end").value = { 420, 0 };
            lg.group ("contents").add<PropGroup> (ls);
            var trim = Factory.trim ();
            trim.prop ("end").set_key (0, { 0 });
            trim.prop ("end").set_key (2.5, { 100 });
            trim.prop ("end").keys[0].set_easy_ease ();
            trim.prop ("end").keys[1].set_easy_ease ();
            lg.group ("contents").add<PropGroup> (trim);
            line.contents.add<PropGroup> (lg);
            line.transform.prop ("position").value = { 640, 600, 0 };
            comp.add_layer (line, 0);
            var text = Factory.text_layer (comp, "Keyframe");
            var doc = text.text_group.prop ("source-text").text;
            doc.size = 110;
            doc.weight = 800;
            text.transform.prop ("position").value = { 640, 230, 0 };
            var an = Factory.text_animator ("Reveal");
            var sel = Factory.range_selector ();
            sel.prop ("start").set_key (0.2, { 0 });
            sel.prop ("start").set_key (1.8, { 100 });
            sel.attrs["shape"] = "ramp-up";
            an.group ("selectors").add<PropGroup> (sel);
            var op = Factory.animator_property ("opacity");
            op.value = { 0 };
            an.group ("properties").add<Property> (op);
            var ap = Factory.animator_property ("position");
            ap.value = { 0, 60 };
            an.group ("properties").add<Property> (ap);
            text.text_group.group ("animators").add<PropGroup> (an);
            var shadow = EffectRegistry.add_to_layer (text, "drop-shadow");
            shadow.prop ("distance").value = { 6 };
            shadow.prop ("softness").value = { 12 };
            comp.add_layer (text, 0);
            var sub = Factory.text_layer (comp, "Motion graphics, made here");
            sub.text_group.prop ("source-text").text.size = 36;
            sub.transform.prop ("position").value = { 640, 330, 0 };
            sub.transform.prop ("opacity").set_key (1.2, { 0 });
            sub.transform.prop ("opacity").set_key (2.0, { 85 });
            comp.add_layer (sub, 0);
            var glow = Factory.adjustment (comp);
            var g = EffectRegistry.add_to_layer (glow, "glow");
            g.prop ("threshold").value = { 70 };
            g.prop ("radius").value = { 30 };
            g.prop ("intensity").value = { 0.6 };
            comp.add_layer (glow, 0);
            p.modified = false;
            return p;
        }
    }
}
