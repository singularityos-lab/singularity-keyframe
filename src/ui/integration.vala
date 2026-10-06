using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Keyframe {

    namespace Tracking {
        public Gee.ArrayList<TrackPoint> pending_points = null;

        private bool pump (double fraction) {
            while (MainContext.default ().pending ()) MainContext.default ().iteration (false);
            return true;
        }

        private Layer? source_layer (KeyframeWindow w) {
            var l = w.doc.primary ();
            if (l == null || (l.kind != LayerKind.FOOTAGE && l.kind != LayerKind.PRECOMP && l.kind != LayerKind.SOLID)) {
                w.toast (_("Select a footage or precomposition layer to track"));
                return null;
            }
            return l;
        }

        private void layer_point (KeyframeWindow w, Layer l, double x, double y, out double lx, out double ly) {
            var inv = l.world_matrix (w.doc.time).inverted () ?? new Mat4 ();
            var p = inv.transform_point (Vec3 (x, y, 0));
            lx = p.x;
            ly = p.y;
        }

        public void place_point (KeyframeWindow w, double x, double y) {
            var l = source_layer (w);
            if (l == null) return;
            if (pending_points == null) pending_points = new Gee.ArrayList<TrackPoint> ();
            if (pending_points.size >= 2) pending_points.clear ();
            double lx, ly;
            layer_point (w, l, x, y, out lx, out ly);
            pending_points.add (new TrackPoint (lx, ly));
            w.toast (pending_points.size == 1 ? _("Track point placed") : _("Second track point placed"));
        }

        public void add_puppet_pin (KeyframeWindow w, double x, double y) {
            var l = w.doc.primary ();
            if (l == null || l.kind == LayerKind.CAMERA || l.kind == LayerKind.LIGHT || l.kind == LayerKind.NULL) {
                w.toast (_("Select a layer to add puppet pins"));
                return;
            }
            double lx, ly;
            layer_point (w, l, x, y, out lx, out ly);
            w.doc.edit (_("Puppet Pin"), () => {
                PropGroup? fx = null;
                if (l.effects != null) foreach (var c in l.effects.children) if (((PropGroup) c).type == "effect.puppet") fx = (PropGroup) c;
                if (fx == null) fx = EffectRegistry.add_to_layer (l, "puppet");
                if (fx != null) Puppet.add_pin (fx, lx, ly);
                l.mark_changed ();
            });
            w.inspector.rebuild ();
            w.timeline.rebuild ();
        }

        public void run (KeyframeWindow w, string kind) {
            var comp = w.doc.comp;
            if (comp == null) return;
            var r = new Renderer (w.doc.project);
            switch (kind) {
                case "point":
                case "two-points": {
                    var l = source_layer (w);
                    if (l == null) return;
                    bool two = kind == "two-points";
                    TrackPoint[] pts = {};
                    if (pending_points != null) foreach (var tp in pending_points) pts += tp;
                    if (pts.length == 0) pts += new TrackPoint (l.solid_width / 2.0, l.solid_height / 2.0);
                    if (two && pts.length < 2) pts += new TrackPoint (pts[0].x + l.solid_width / 4.0, pts[0].y);
                    if (!two && pts.length > 1) pts = { pts[0] };
                    var res = PointTracker.track (r, l, w.doc.time, l.out_point - 1 / comp.fps, pts, true, pump);
                    w.doc.edit (_("Track Motion"), () => PointTracker.apply_to_new_null (res, l, two, two));
                    pending_points = null;
                    w.toast (_("Tracked onto a new null"));
                    break;
                }
                case "planar": {
                    var l = source_layer (w);
                    if (l == null) return;
                    double[] corners = { l.solid_width * 0.25, l.solid_height * 0.25, l.solid_width * 0.75, l.solid_height * 0.25, l.solid_width * 0.75, l.solid_height * 0.75, l.solid_width * 0.25, l.solid_height * 0.75 };
                    if (l.masks != null && l.masks.children.size > 0) {
                        var mp = ((PropGroup) l.masks.children[0]).prop ("path");
                        var path = mp != null ? mp.path_at (l.layer_time (w.doc.time)) : null;
                        if (path != null && path.count >= 4) corners = { path.v[0].x, path.v[0].y, path.v[1].x, path.v[1].y, path.v[2].x, path.v[2].y, path.v[3].x, path.v[3].y };
                    }
                    var res = PlanarTracker.track (r, l, w.doc.time, l.out_point - 1 / comp.fps, corners, 200, pump);
                    w.doc.edit (_("Track Plane"), () => {
                        var target = Factory.solid (comp, _("Screen Replacement"), { 0.2, 0.5, 1, 1 }, l.solid_width, l.solid_height);
                        comp.add_layer (target, comp.index_of (l));
                        PlanarTracker.apply_corner_pin (res, l, target);
                        w.doc.select_layer (target);
                    });
                    w.toast (_("Plane tracked, corner pin applied"));
                    break;
                }
                case "stabilize": {
                    var l = source_layer (w);
                    if (l == null) return;
                    w.doc.edit (_("Stabilize"), () => Stabilizer.analyze (r, l, l.in_point, l.out_point - 1 / comp.fps, pump));
                    w.inspector.rebuild ();
                    w.toast (_("Stabilization analysed"));
                    break;
                }
                case "camera": {
                    var l = source_layer (w);
                    if (l == null) return;
                    var tracks = CameraSolver.track_scene (r, l, l.in_point, l.out_point - 1 / comp.fps, 150, pump);
                    int frames = int.max (2, (int) Math.round ((l.out_point - l.in_point) * comp.fps));
                    var solve = CameraSolver.solve (tracks, frames, l.solid_width, l.solid_height, comp.width * 50.0 / 36.0);
                    if (solve == null) {
                        w.toast (_("Not enough detail to solve the camera"));
                        return;
                    }
                    w.doc.edit (_("Track Camera"), () => CameraSolver.create_layers (solve, comp, l.in_point, true, true));
                    w.toast (_("Camera solved, reprojection error %.2f px").printf (solve.error_px));
                    break;
                }
                case "roto": {
                    var l = w.doc.primary ();
                    if (l == null || l.masks == null || l.masks.children.size == 0) {
                        w.toast (_("Draw a mask on the layer first"));
                        return;
                    }
                    var mask = (PropGroup) l.masks.children[l.masks.children.size - 1];
                    int n = 0;
                    w.doc.edit (_("Propagate Mask"), () => n = RotoBrush.propagate (r, l, mask, w.doc.time, l.out_point - 1 / comp.fps, 4, 0.5, pump));
                    w.toast (ngettext ("%d mask key written", "%d mask keys written", n).printf (n));
                    break;
                }
            }
            r.media.close ();
            w.timeline.rebuild ();
            w.viewer.refresh ();
        }
    }

    namespace VectorImport {
        public void import_into (KeyframeWindow w, Footage f) {
            try {
                var layers = VectorShapes.layers_from_file (w.doc.comp, f.path);
                w.doc.edit (_("Import Vector Artwork"), () => {
                    foreach (var l in layers) w.doc.comp.add_layer (l, 0);
                    if (layers.size > 0) w.doc.select_layer (layers[0]);
                });
            } catch (Error e) {
                w.toast (_("Could not import the artwork: %s").printf (e.message));
            }
        }
    }

    namespace Interchange {
        public bool is_lottie (string path) {
            try {
                string text;
                FileUtils.get_contents (path, out text);
                var root = JsonUtil.parse (text);
                return root.get_node_type () == Json.NodeType.OBJECT && root.get_object ().has_member ("layers") && root.get_object ().has_member ("fr");
            } catch (Error e) {
                return false;
            }
        }

        public void show_warnings_public (KeyframeWindow w, string done, Gee.List<string> warnings) {
            show_warnings (w, done, warnings);
        }

        private void show_warnings (KeyframeWindow w, string done, Gee.List<string> warnings) {
            if (warnings.size == 0) {
                w.toast (done);
                return;
            }
            var d = new ConfirmDialog.message (w.app, done, null, string.joinv ("\n", warnings.to_array ()));
            d.transient_for = w;
            d.present ();
        }

        public void import_lottie (KeyframeWindow w, string path) {
            var imp = new LottieImport (w.doc.project);
            Composition? c = null;
            w.doc.edit (_("Import Lottie"), () => {
                try {
                    c = imp.import_file (path);
                } catch (Error e) {
                    w.toast (_("Could not import the animation: %s").printf (e.message));
                }
            });
            if (c != null) {
                w.doc.open_comp (c);
                show_warnings (w, _("Lottie animation imported"), imp.warnings);
            }
        }

        public void import_otio (KeyframeWindow w, string path) {
            var warnings = new Gee.ArrayList<string> ();
            Composition? c = null;
            w.doc.edit (_("Import OpenTimelineIO"), () => {
                try {
                    string text;
                    FileUtils.get_contents (path, out text);
                    c = Otio.import_text (w.doc.project, text, warnings);
                } catch (Error e) {
                    w.toast (_("Could not import the timeline: %s").printf (e.message));
                }
            });
            if (c != null) {
                w.doc.open_comp (c);
                show_warnings (w, _("Timeline imported"), warnings);
            }
        }

        public void export_text (KeyframeWindow w, string title, string name, owned ExportFunc f) {
            var dlg = new FileDialog ();
            dlg.title = title;
            dlg.initial_name = name;
            dlg.save.begin (w, null, (o, res) => {
                try {
                    var file = dlg.save.end (res);
                    if (file != null) f (file.get_path ());
                } catch (Error e) {
                    if (!(e is IOError.CANCELLED) && !(e is Gtk.DialogError.DISMISSED)) w.toast (e.message);
                }
            });
        }

        public delegate void ExportFunc (string path) throws Error;
    }

    namespace RenderQueueUi {
        public void add_comp (KeyframeWindow w, Composition c) {
            w.doc.edit (_("Add to Render Queue"), () => {
                var ri = new RenderItem (c.id);
                ri.start = c.work_start;
                ri.end = c.work_area_end ();
                var om = new OutputModule ();
                om.format = "h264-mp4";
                bool known = false;
                foreach (var f in Encoders.formats ()) if (f.id == om.format && f.available) known = true;
                if (!known) om.format = "png-sequence";
                ri.outputs.add (om);
                w.doc.project.render_queue.add (ri);
            });
            new RenderQueueDialog (w).present ();
        }
    }

    namespace ExtraActions {
        public void install (KeyframeWindow w) {
            w.action ("run-script", () => run_script (w));
            w.action ("export-tokens", () => export_tokens (w));
            w.action ("render-queue", () => new RenderQueueDialog (w).present ());
            w.action ("add-render-queue", () => {
                if (w.doc.comp != null) RenderQueueUi.add_comp (w, w.doc.comp);
            });
            w.action ("export-lottie", () => {
                if (w.doc.comp == null) return;
                Interchange.export_text (w, _("Export Lottie"), w.doc.comp.name + ".json", (path) => {
                    var ex = new LottieExport (w.doc.project);
                    FileUtils.set_contents (path, ex.export (w.doc.comp));
                    Interchange.show_warnings_public (w, _("Lottie animation exported"), ex.warnings);
                });
            });
            w.action ("export-otio", () => {
                if (w.doc.comp == null) return;
                Interchange.export_text (w, _("Export OpenTimelineIO"), w.doc.comp.name + ".otio", (path) => {
                    var warnings = new Gee.ArrayList<string> ();
                    FileUtils.set_contents (path, Otio.export (w.doc.project, w.doc.comp, warnings));
                    Interchange.show_warnings_public (w, _("Timeline exported"), warnings);
                });
            });
            w.action ("save-template", () => {
                if (w.doc.comp == null) return;
                if (w.doc.comp.essential.size == 0) {
                    w.toast (_("Expose at least one property in the Essential panel first"));
                    return;
                }
                Interchange.export_text (w, _("Save as Motion Template"), w.doc.comp.name + ".keyframe", (path) => {
                    MotionTemplates.save_template (w.doc.project, w.doc.comp, path.has_suffix (".keyframe") ? path : path + ".keyframe");
                    w.toast (_("Motion template saved"));
                });
            });
        }

        public void run_script (KeyframeWindow w) {
            var d = new ConfirmDialog (w.app, _("Run Script"), null, _("Scripts create and change compositions, layers, keyframes and render queue items."), _("Run"), ConfirmDialog.ActionStyle.SUGGESTED);
            d.transient_for = w;
            d.modal = true;
            d.set_default_size (560, 0);
            var view = new TextView ();
            view.monospace = true;
            view.wrap_mode = WrapMode.WORD_CHAR;
            view.buffer.text = "var comp = app.project.activeItem;\n";
            view.top_margin = 8;
            view.left_margin = 8;
            view.add_css_class ("card");
            var sw = new ScrolledWindow ();
            sw.child = view;
            sw.min_content_height = 220;
            d.custom_area.append (sw);
            var open = new Button.with_label (_("Load Script File"));
            open.halign = Align.START;
            open.clicked.connect (() => {
                var fd = new FileDialog ();
                fd.open.begin (w, null, (o, res) => {
                    try {
                        var f = fd.open.end (res);
                        if (f == null) return;
                        uint8[] data;
                        f.load_contents (null, out data, null);
                        view.buffer.text = (string) data;
                    } catch (Error e) {
                    }
                });
            });
            d.custom_area.append (open);
            d.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                string output = "";
                bool ok = false;
                w.doc.edit (_("Run Script"), () => {
                    ok = Scripting.run (w.doc.project, view.buffer.text, out output);
                });
                w.doc.structure_changed ();
                if (w.doc.comp == null && w.doc.project.compositions ().size > 0) w.doc.open_comp (w.doc.project.compositions ()[0]);
                w.toast (ok ? (output.strip () != "" ? output.strip () : _("Script finished")) : output);
            });
            d.present ();
        }

        public void export_tokens (KeyframeWindow w) {
            var p = w.doc.active_property;
            if (p == null || p.keys.size < 2) {
                w.toast (_("Select an animated property in the timeline"));
                return;
            }
            var list = MotionTokens.export_property (p, ExpressionHelpers.token_name (p));
            var fd = new FileDialog ();
            fd.initial_name = "motion-tokens.json";
            fd.save.begin (w, null, (o, res) => {
                try {
                    var f = fd.save.end (res);
                    if (f == null) return;
                    var path = f.get_path ();
                    string text = path.has_suffix (".css") ? MotionTokens.to_css (list) : (path.has_suffix (".vala") ? MotionTokens.to_vala (list) : MotionTokens.to_json (list));
                    FileUtils.set_contents (path, text);
                    w.toast (_("Animation tokens exported"));
                } catch (Error e) {
                    w.toast (e.message);
                }
            });
        }
    }

    namespace ExpressionHelpers {
        public string token_name (Property p) {
            var l = p.owner_layer ();
            var raw = (l != null ? l.name + "-" : "") + p.key;
            var sb = new StringBuilder ();
            foreach (var c in raw.down ().to_utf8 ()) sb.append_c (c.isalnum () ? c : '-');
            return sb.str;
        }
    }
}
