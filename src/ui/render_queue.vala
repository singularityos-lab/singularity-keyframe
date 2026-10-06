using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Keyframe {

    public class RenderQueueDialog : ConfirmDialog {
        private KeyframeWindow win;
        private Box list;
        private Gee.HashMap<string, ProgressBar> bars = new Gee.HashMap<string, ProgressBar> ();
        private Gee.HashMap<string, ActionRow> status_rows = new Gee.HashMap<string, ActionRow> ();
        private Subprocess? running = null;
        private Cancellable? cancel = null;
        private bool rendering = false;

        public RenderQueueDialog (KeyframeWindow win) {
            base (win.app, _("Render Queue"), null, null, _("Render"), ConfirmDialog.ActionStyle.SUGGESTED);
            this.win = win;
            transient_for = win;
            set_default_size (620, 640);
            var sw = new ScrolledWindow ();
            sw.hscrollbar_policy = PolicyType.NEVER;
            sw.min_content_height = 460;
            list = new Box (Orientation.VERTICAL, 12);
            sw.child = list;
            custom_area.append (sw);
            response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY) render_all.begin ();
                else if (cancel != null) {
                    cancel.cancel ();
                    if (running != null) running.force_exit ();
                }
            });
            rebuild ();
        }

        public override void close_dialog () {
            if (rendering) return;
            base.close_dialog ();
        }

        private void rebuild () {
            Widget? c;
            while ((c = list.get_first_child ()) != null) list.remove (c);
            bars.clear ();
            status_rows.clear ();
            var q = win.doc.project.render_queue;
            if (q.size == 0) {
                var sp = new WelcomePage ();
                sp.is_section = true;
                sp.compact = true;
                sp.embedded = true;
                sp.title = _("Nothing to Render");
                sp.subtitle = _("Queue a composition to export it as video, an image sequence or animation.");
                if (win.doc.comp != null) {
                    var comp = win.doc.comp;
                    sp.add_action ("video-x-generic", _("Add Current Composition"), comp.name, () => {
                        win.doc.edit (_("Add to Render Queue"), () => {
                            var ri = new RenderItem (comp.id);
                            ri.start = comp.work_start;
                            ri.end = comp.work_area_end ();
                            var om = new OutputModule ();
                            om.format = "h264-mp4";
                            bool known = false;
                            foreach (var f in Encoders.formats ()) if (f.id == om.format && f.available) known = true;
                            if (!known) om.format = "png-sequence";
                            ri.outputs.add (om);
                            win.doc.project.render_queue.add (ri);
                        });
                        rebuild ();
                    });
                }
                list.append (sp);
                primary_sensitive = false;
                return;
            }
            primary_sensitive = true;
            foreach (var item in q) list.append (item_group (item));
        }

        private string label_for (OutputFormat f) {
            return f.available ? f.label : _("%s (not available)").printf (f.label);
        }

        private Widget item_group (RenderItem item) {
            var comp = win.doc.project.comp_by_id (item.comp_id);
            var g = new PreferencesGroup (comp != null ? comp.name : _("Missing composition"));
            var del = new Button.from_icon_name ("user-trash-symbolic");
            del.add_css_class ("flat");
            del.tooltip_text = _("Remove From Queue");
            del.clicked.connect (() => {
                win.doc.edit (_("Remove From Render Queue"), () => win.doc.project.render_queue.remove (item));
                rebuild ();
            });
            g.add_header_suffix (del);
            var status = new ActionRow (_("Status"), status_text (item));
            var bar = new ProgressBar ();
            bar.fraction = item.progress;
            bar.valign = Align.CENTER;
            bar.width_request = 140;
            status.add_suffix (bar);
            bars[item.id] = bar;
            status_rows[item.id] = status;
            g.add_row (status);
            var om = item.outputs.size > 0 ? item.outputs[0] : new OutputModule ();
            if (item.outputs.size == 0) item.outputs.add (om);
            var formats = Encoders.formats ();
            string[] labels = {};
            int current = 0;
            for (int i = 0; i < formats.size; i++) {
                labels += label_for (formats[i]);
                if (formats[i].id == om.format) current = i;
            }
            var fmt = new ChoiceRow (_("Format"), labels, formats[current].available ? "" : formats[current].reason);
            fmt.selected = current;
            fmt.valign = Align.CENTER;
            g.add_row (fmt);
            var alpha = new SwitchRow (_("Alpha Channel"), null, om.alpha);
            alpha.sensitive = formats[current].alpha;
            g.add_row (alpha);
            var depth = new ChoiceRow (_("Depth"), { _("8 bits per channel"), _("16 bits per channel"), _("32 bits per channel, floating point") });
            depth.selected = om.bit_depth >= 32 ? 2 : (om.bit_depth >= 16 ? 1 : 0);
            depth.valign = Align.CENTER;
            g.add_row (depth);
            var out_row = new ActionRow (_("Output To"), om.path != "" ? om.path : _("Not chosen"));
            var choose = new Button.with_label (_("Choose"));
            choose.valign = Align.CENTER;
            choose.clicked.connect (() => choose_output (item, om, formats[(int) fmt.selected], out_row));
            out_row.add_suffix (choose);
            g.add_row (out_row);
            var range = new ChoiceRow (_("Frames"), { _("Work Area"), _("Whole Composition") });
            range.selected = item.end < 0 && item.start == 0 ? 1 : 0;
            range.valign = Align.CENTER;
            g.add_row (range);
            var res = new ChoiceRow (_("Resolution"), { _("Full"), _("Half"), _("Third"), _("Quarter") });
            res.selected = (item.resolution - 1).clamp (0, 3);
            res.valign = Align.CENTER;
            g.add_row (res);
            var mb = new SwitchRow (_("Motion Blur"), null, item.motion_blur);
            g.add_row (mb);
            var audio = new SwitchRow (_("Include Audio"), null, om.include_audio);
            audio.sensitive = formats[current].audio;
            g.add_row (audio);
            fmt.notify["selected"].connect (() => {
                var f = formats[(int) fmt.selected];
                om.format = f.id;
                fmt.subtitle = f.available ? "" : f.reason;
                alpha.sensitive = f.alpha;
                audio.sensitive = f.audio;
                if (om.path != "") {
                    om.path = with_extension (om.path, f);
                    out_row.subtitle = om.path;
                }
            });
            alpha.notify["active"].connect (() => om.alpha = alpha.active);
            depth.notify["selected"].connect (() => om.bit_depth = depth.selected == 0 ? 8 : (depth.selected == 1 ? 16 : 32));
            audio.notify["active"].connect (() => om.include_audio = audio.active);
            mb.notify["active"].connect (() => item.motion_blur = mb.active);
            res.notify["selected"].connect (() => item.resolution = (int) res.selected + 1);
            range.notify["selected"].connect (() => {
                if (comp == null) return;
                if (range.selected == 1) {
                    item.start = 0;
                    item.end = -1;
                } else {
                    item.start = comp.work_start;
                    item.end = comp.work_area_end ();
                }
            });
            return g;
        }

        private string with_extension (string path, OutputFormat f) {
            var base_path = path;
            int dot = base_path.last_index_of (".");
            int slash = base_path.last_index_of ("/");
            if (dot > slash) base_path = base_path.substring (0, dot);
            if (f.sequence && !base_path.contains ("#")) base_path += "_####";
            if (!f.sequence) base_path = base_path.replace ("_####", "");
            return base_path + "." + f.extension;
        }

        private void choose_output (RenderItem item, OutputModule om, OutputFormat f, ActionRow row) {
            var comp = win.doc.project.comp_by_id (item.comp_id);
            var dlg = new FileDialog ();
            dlg.title = _("Render To");
            dlg.initial_name = with_extension (comp != null ? comp.name : "render", f);
            dlg.save.begin (win, null, (o, res) => {
                try {
                    var file = dlg.save.end (res);
                    if (file == null) return;
                    om.path = with_extension (file.get_path (), f);
                    row.subtitle = om.path;
                    win.doc.project.modified = true;
                } catch (Error e) {
                }
            });
        }

        private string status_text (RenderItem item) {
            switch (item.status) {
                case RenderStatus.DONE: return _("Done");
                case RenderStatus.FAILED: return _("Failed: %s").printf (item.error);
                case RenderStatus.RENDERING: return _("Rendering");
                case RenderStatus.STOPPED: return _("Stopped");
                case RenderStatus.UNQUEUED: return _("Not queued");
                default: return _("Queued");
            }
        }

        private string project_copy () throws Error {
            var dir = Path.build_filename (Environment.get_user_cache_dir (), "keyframe", "render");
            DirUtils.create_with_parents (dir, 0700);
            var path = Path.build_filename (dir, "queue-%s.keyframe".printf (Layer.new_id ()));
            var p = win.doc.project;
            string old = p.base_dir;
            p.base_dir = "";
            try {
                FileUtils.set_data (path, NativeFormat.save_bytes (p));
            } finally {
                p.base_dir = old;
            }
            return path;
        }

        private async void render_all () {
            if (rendering) return;
            rendering = true;
            primary_sensitive = false;
            cancel = new Cancellable ();
            foreach (var item in win.doc.project.render_queue) {
                if (cancel.is_cancelled ()) break;
                if (item.status == RenderStatus.DONE || item.status == RenderStatus.UNQUEUED) continue;
                if (item.outputs.size == 0 || item.outputs[0].path == "") {
                    item.status = RenderStatus.FAILED;
                    item.error = _("Choose where to render first");
                    update (item);
                    continue;
                }
                yield render_item (item);
            }
            rendering = false;
            primary_sensitive = true;
            cancel = null;
            win.doc.project.modified = true;
        }

        private async void render_item (RenderItem item) {
            string project_path;
            try {
                project_path = project_copy ();
            } catch (Error e) {
                item.status = RenderStatus.FAILED;
                item.error = e.message;
                update (item);
                return;
            }
            item.status = RenderStatus.RENDERING;
            item.progress = 0;
            update (item);
            var argv = RenderJobs.helper_argv (project_path, item.id);
            try {
                running = new Subprocess.newv (argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
                var input = new DataInputStream (running.get_stdout_pipe ());
                string? line;
                string last_error = "";
                while ((line = yield input.read_line_async (Priority.DEFAULT, null)) != null) {
                    string kind, value;
                    RenderJobs.parse_line (line, out kind, out value);
                    if (kind == "progress") {
                        item.progress = double.parse (value);
                        update (item);
                    } else if (kind == "error") {
                        last_error = value;
                    }
                }
                yield running.wait_async (null);
                int code = running.get_if_exited () ? running.get_exit_status () : -1;
                if (code == 0) {
                    item.status = RenderStatus.DONE;
                    item.progress = 1;
                } else if (code == 4 || cancel.is_cancelled ()) {
                    item.status = RenderStatus.STOPPED;
                } else {
                    item.status = RenderStatus.FAILED;
                    item.error = last_error != "" ? last_error : _("The renderer stopped unexpectedly");
                }
            } catch (Error e) {
                item.status = RenderStatus.FAILED;
                item.error = e.message;
            }
            running = null;
            FileUtils.unlink (project_path);
            update (item);
        }

        private void update (RenderItem item) {
            var bar = bars[item.id];
            if (bar != null) bar.fraction = item.progress.clamp (0, 1);
            var row = status_rows[item.id];
            if (row != null) row.subtitle = status_text (item);
        }
    }
}
