using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Keyframe {

    public class KeyframeWindow : Singularity.Widgets.Window {
        public KeyframeApp app;
        public Document doc;
        private Stack content_stack;
        private Box workspace_host;
        public Viewer viewer;
        public Timeline timeline;
        public GraphEditor graph;
        public Inspector inspector;
        public ProjectPanel project_panel;
        private Stack lower_stack;
        private BubbleSwitcher lower_switch;
        private Box graph_tools;
        private Label status;
        private Label time_label;
        private DropDown resolution;
        private ToggleButton roi_toggle;
        private Gee.HashMap<ViewerTool, ToggleButton> tool_buttons = new Gee.HashMap<ViewerTool, ToggleButton> ();
        private Gee.ArrayList<Widget> doc_bubbles = new Gee.ArrayList<Widget> ();
        private Button play_bubble;
        private Button undo_bubble;
        private Button redo_bubble;
        private bool close_confirmed = false;
        private uint autosave_source = 0;

        public KeyframeWindow (KeyframeApp app) {
            Object (application: app);
            this.app = app;
            set_default_size (1440, 900);
            set_title (_("Keyframe"));
            doc = new Document (new Project ());
            content_stack = new Stack ();
            content_stack.transition_type = StackTransitionType.CROSSFADE;
            content_stack.add_named (build_welcome (), "welcome");
            workspace_host = new Box (Orientation.VERTICAL, 0);
            content_stack.add_named (workspace_host, "workspace");
            set_content (content_stack);
            build_bubbles ();
            install_actions ();
            close_request.connect (on_close_request);
            show_welcome ();
            TestScript.maybe_run (this);
            var drop = new DropTarget (typeof (Gdk.FileList), Gdk.DragAction.COPY);
            drop.drop.connect ((val, x, y) => {
                var fl = (Gdk.FileList) val;
                var files = fl.get_files ();
                if (files.length () == 0) return false;
                if (content_stack.visible_child_name == "welcome") {
                    var first = files.data;
                    if (first.get_path () != null && first.get_path ().has_suffix (".keyframe")) {
                        open_project (first);
                        return true;
                    }
                    new_project ();
                }
                foreach (var f in files) import_path (f.get_path ());
                return true;
            });
            ((Widget) this).add_controller (drop);
            int minutes = app.settings_int ("autosave-minutes", 5);
            if (minutes > 0) autosave_source = Timeout.add_seconds (minutes * 60, () => {
                autosave ();
                return true;
            });
        }

        private Widget build_welcome () {
            var welcome = new WelcomePage ();
            welcome.app_icon_name = "dev.sinty.keyframe";
            welcome.title = _("Keyframe");
            welcome.subtitle = _("Animate titles, graphics and effects, and composite video");
            welcome.add_action ("document-new", _("New Project"), _("Start with an empty composition"), new_project);
            welcome.add_action ("folder-open", _("Open"), _("Open a Keyframe project or a Lottie animation"), choose_open);
            return welcome;
        }

        private void build_bubbles () {
            track (add_bubble_icon ("go-previous-symbolic", _("Close Project (Ctrl+W)"), () => close_project.begin ()));
            track (add_bubble_icon ("sidebar-show-symbolic", _("Project (F9)"), () => set_sidebar_visible (!get_sidebar_visible ())));
            track (add_bubble_icon ("document-save-symbolic", _("Save (Ctrl+S)"), () => save.begin (false)));
            undo_bubble = add_bubble_icon ("edit-undo-symbolic", _("Undo (Ctrl+Z)"), () => doc.undo ());
            track (undo_bubble);
            redo_bubble = add_bubble_icon ("edit-redo-symbolic", _("Redo (Ctrl+Shift+Z)"), () => doc.redo ());
            track (redo_bubble);
            play_bubble = add_bubble_icon ("media-playback-start-symbolic", _("Preview (Space)"), () => doc.toggle_play ());
            track (play_bubble);
            track (add_bubble_icon ("keyframe-render-symbolic", _("Render Queue (Ctrl+Alt+M)"), () => activate_action ("render-queue", null)));
        }

        private void track (Widget w) {
            doc_bubbles.add (w);
        }

        private void show_welcome () {
            content_stack.visible_child_name = "welcome";
            foreach (var w in doc_bubbles) w.visible = false;
            set_sidebar_visible (false);
            set_title (_("Keyframe"));
        }

        public void new_project () {
            var p = new Project ();
            int w = app.settings_int ("default-width", 1920), h = app.settings_int ("default-height", 1080);
            double fps = app.settings_double ("default-fps", 30);
            var comp = new Composition (_("Composition 1"), w, h, fps, app.settings_int ("default-duration", 10));
            p.add_item (comp);
            p.bit_depth = app.settings_int ("bit-depth", 32);
            p.modified = false;
            load_into_workspace (p);
        }

        public void load_into_workspace (Project p) {
            if (content_stack.visible_child_name == "workspace") {
                doc.replace_project (p);
            } else {
                doc.close ();
                doc = new Document (p);
                build_workspace ();
                doc.open_comp (p.compositions ().size > 0 ? p.compositions ()[0] : null);
            }
            content_stack.visible_child_name = "workspace";
            foreach (var w in doc_bubbles) w.visible = true;
            set_sidebar_visible (true);
            update_title ();
            update_history ();
            doc.service.renderer.cache.set_budget_mb (app.settings_int ("preview-cache-mb", 1024));
        }

        private void build_workspace () {
            Widget? c;
            while ((c = workspace_host.get_first_child ()) != null) workspace_host.remove (c);
            viewer = new Viewer (doc);
            timeline = new Timeline (doc);
            graph = new GraphEditor (doc);
            inspector = new Inspector (doc);
            inspector.host = this;
            inspector.add_page ("library", _("Library"), new LibraryPanel (this));
            project_panel = new ProjectPanel (doc);
            set_sidebar (project_panel);
            project_panel.item_activated.connect (activate_item);
            project_panel.request_import.connect (() => activate_action ("import", null));
            project_panel.request_new_comp.connect (() => activate_action ("new-comp", null));
            project_panel.request_item_menu.connect (item_menu);
            inspector.request_expression.connect ((p) => Dialogs.expression (this, p));
            inspector.request_add_effect.connect (add_effect_menu);
            inspector.request_tracker.connect ((k) => Tracking.run (this, k));
            timeline.request_expression.connect ((p) => Dialogs.expression (this, p));
            timeline.request_layer_menu.connect (layer_menu);
            timeline.request_key_menu.connect (key_menu);
            timeline.request_value_edit.connect ((p, x, y) => Dialogs.value_popover (this, timeline, p, x, y));
            timeline.request_parent_menu.connect (parent_menu);
            timeline.request_blend_menu.connect (blend_menu);
            timeline.request_mask_menu.connect (mask_menu);
            timeline.request_rename.connect ((l) => Dialogs.rename_layer (this, l));
            timeline.request_key_dialog.connect ((p, k) => Dialogs.keyframe_velocity (this, p, k));
            viewer.request_text.connect (new_text_at);
            viewer.request_track_point.connect ((x, y) => Tracking.place_point (this, x, y));
            viewer.request_puppet_pin.connect ((x, y) => Tracking.add_puppet_pin (this, x, y));
            viewer.tool_finished.connect (() => set_tool (ViewerTool.SELECT));

            var upper = new Paned (Orientation.HORIZONTAL);
            upper.vexpand = true;
            var view_col = new Box (Orientation.VERTICAL, 0);
            var overlay = new Overlay ();
            overlay.child = viewer;
            overlay.add_overlay (build_tools ());
            overlay.vexpand = true;
            view_col.append (overlay);
            view_col.append (build_view_bar ());
            upper.start_child = view_col;
            upper.resize_start_child = true;
            upper.shrink_start_child = false;
            var insp_frame = new Box (Orientation.VERTICAL, 0);
            insp_frame.add_css_class ("window-sidebar");
            insp_frame.add_css_class ("sx-inspector");
            insp_frame.append (inspector);
            apply_bubble_inset (inspector, 56, 0);
            upper.end_child = new FixedWidth (insp_frame, 420);
            upper.resize_end_child = false;
            upper.shrink_end_child = false;

            var lower = new Box (Orientation.VERTICAL, 0);
            lower.append (build_lower_bar ());
            lower_stack = new Stack ();
            var timeline_overlay = new Overlay ();
            timeline_overlay.child = timeline;
            var timeline_empty = new WelcomePage ();
            timeline_empty.is_section = true;
            timeline_empty.compact = true;
            timeline_empty.embedded = true;
            timeline_empty.title = _("No Layers");
            timeline_empty.subtitle = _("Draw with the tools on the viewer, or start with a title or your footage.");
            timeline_empty.add_action ("font-x-generic", _("New Text Layer"), _("Type a title in the middle of the composition"), () => activate_action ("new-text", null));
            timeline_empty.add_action ("video-x-generic", _("Import Footage"), _("Video, audio, pictures and SVG files"), () => activate_action ("import", null));
            timeline_empty.width_request = 440;
            timeline_empty.halign = Align.CENTER;
            timeline_empty.valign = Align.CENTER;
            timeline_empty.vexpand = false;
            timeline_empty.margin_top = 12;
            timeline_empty.margin_bottom = 12;
            var timeline_empty_scroll = new ScrolledWindow ();
            timeline_empty_scroll.hscrollbar_policy = PolicyType.NEVER;
            timeline_empty_scroll.margin_top = Timeline.HEADER;
            timeline_empty_scroll.child = timeline_empty;
            timeline_overlay.add_overlay (timeline_empty_scroll);
            timeline_empty_scroll.visible = doc.comp != null && doc.comp.layers.size == 0;
            doc.structure_changed.connect (() => timeline_empty_scroll.visible = doc.comp != null && doc.comp.layers.size == 0);
            doc.comp_switched.connect (() => timeline_empty_scroll.visible = doc.comp != null && doc.comp.layers.size == 0);
            doc.history_changed.connect (() => timeline_empty_scroll.visible = doc.comp != null && doc.comp.layers.size == 0);
            lower_stack.add_named (timeline_overlay, "timeline");
            var graph_overlay = new Overlay ();
            graph_overlay.child = graph;
            var graph_empty = new StatusPage ();
            graph_empty.icon_name = "dev.sinty.keyframe";
            graph_empty.title = _("No Curve Selected");
            graph_empty.description = _("Select an animated property in the timeline to edit its curve.");
            graph_empty.compact = true;
            graph_empty.valign = Align.CENTER;
            graph_empty.can_target = false;
            graph_overlay.add_overlay (graph_empty);
            graph_empty.visible = !graph.has_curve ();
            doc.selection_changed.connect (() => graph_empty.visible = !graph.has_curve ());
            doc.structure_changed.connect (() => graph_empty.visible = !graph.has_curve ());
            lower_stack.add_named (graph_overlay, "graph");
            lower_stack.vexpand = true;
            lower_switch.set_stack (lower_stack);
            lower.append (lower_stack);

            var vpaned = new Paned (Orientation.VERTICAL);
            vpaned.start_child = upper;
            vpaned.end_child = lower;
            vpaned.resize_end_child = true;
            vpaned.shrink_end_child = false;
            vpaned.position = 500;
            workspace_host.append (vpaned);
            doc.history_changed.connect (update_history);
            doc.playback_changed.connect (() => play_bubble.icon_name = doc.playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic");
            doc.time_changed.connect (update_status);
            doc.selection_changed.connect (update_status);
            doc.content_changed.connect (update_title);
            doc.comp_switched.connect (() => {
                update_title ();
                timeline.rebuild ();
            });
        }

        private Widget build_tools () {
            var tools = new Singularity.Widgets.ToolPalette ();
            tools.margin_start = 10;
            tools.margin_top = tools.margin_bottom = 6;
            add_tool (tools, ViewerTool.SELECT, "keyframe-select-symbolic", _("Selection (V)"));
            add_tool (tools, ViewerTool.HAND, "keyframe-hand-symbolic", _("Hand (H)"));
            tools.add_separator ();
            add_tool (tools, ViewerTool.RECT, "keyframe-rect-symbolic", _("Rectangle (Q)"));
            add_tool (tools, ViewerTool.ELLIPSE, "keyframe-ellipse-symbolic", _("Ellipse"));
            add_tool (tools, ViewerTool.STAR, "keyframe-star-symbolic", _("Polystar"));
            add_tool (tools, ViewerTool.PEN, "keyframe-pen-symbolic", _("Pen (G)"));
            add_tool (tools, ViewerTool.TEXT, "keyframe-text-symbolic", _("Text (Ctrl+T)"));
            tools.add_separator ();
            add_tool (tools, ViewerTool.PUPPET, "keyframe-puppet-symbolic", _("Puppet Pin (Ctrl+P)"));
            add_tool (tools, ViewerTool.TRACK, "keyframe-track-symbolic", _("Track Point"));
            add_tool (tools, ViewerTool.ROI, "keyframe-roi-symbolic", _("Region of Interest"));
            tool_buttons[ViewerTool.SELECT].active = true;
            return tools;
        }

        private void add_tool (Singularity.Widgets.ToolPalette tools, ViewerTool tool, string icon, string tip) {
            var b = tools.add_tool (icon, tip);
            b.toggled.connect (() => {
                if (b.active && viewer.tool != tool) set_tool (tool);
                else if (!b.active && viewer.tool == tool) b.active = true;
            });
            tool_buttons[tool] = b;
        }

        public void set_tool (ViewerTool t) {
            if (viewer.tool == ViewerTool.PEN && t != ViewerTool.PEN) viewer.finish_pen (false);
            viewer.tool = t;
            foreach (var e in tool_buttons.entries) e.value.active = e.key == t;
        }

        private Widget build_view_bar () {
            var bar = new Singularity.Widgets.ControlStrip (4, 4);
            resolution = new DropDown.from_strings ({ _("Auto"), _("Full"), _("Half"), _("Third"), _("Quarter") });
            resolution.tooltip_text = _("Preview Resolution");
            int pref = app.settings_resolution ();
            resolution.selected = pref;
            doc.preview_downsample = pref;
            resolution.notify["selected"].connect (() => {
                doc.preview_downsample = (int) resolution.selected;
                viewer.refresh ();
                timeline.queue_draw ();
            });
            bar.append (resolution);
            roi_toggle = bar.add_icon_toggle ("keyframe-roi-symbolic", _("Render Only the Region of Interest"));
            roi_toggle.toggled.connect (() => {
                doc.roi_enabled = roi_toggle.active;
                if (roi_toggle.active && doc.roi_w <= 0) set_tool (ViewerTool.ROI);
                viewer.refresh ();
            });
            var checker = bar.add_text_toggle (_("Transparency"));
            checker.active = true;
            checker.toggled.connect (() => {
                viewer.checker = checker.active;
                viewer.queue_draw ();
            });
            var safe = bar.add_text_toggle (_("Guides"));
            safe.toggled.connect (() => {
                viewer.show_safe = safe.active;
                viewer.show_grid = safe.active;
                viewer.queue_draw ();
            });
            var fit = bar.add_text_button (_("Fit"));
            fit.clicked.connect (() => {
                viewer.fit ();
                viewer.refresh ();
            });
            var z100 = bar.add_text_button ("100%");
            z100.clicked.connect (() => viewer.set_zoom (1));
            status = new Label ("");
            status.add_css_class ("dim-label");
            status.hexpand = true;
            status.xalign = 1;
            status.ellipsize = Pango.EllipsizeMode.START;
            bar.append (status);
            return bar;
        }

        private Widget build_lower_bar () {
            var bar = new Singularity.Widgets.ControlStrip (6, 4);
            lower_switch = new BubbleSwitcher ();
            lower_switch.add_option ("timeline", _("Timeline"));
            lower_switch.add_option ("graph", _("Graph Editor"));
            lower_switch.selected.connect ((n) => {
                graph_tools.visible = n == "graph";
                if (n == "graph") graph.fit ();
            });
            bar.append (lower_switch);
            var nav = new Box (Orientation.HORIZONTAL, 0);
            nav.add_css_class ("linked");
            foreach (var spec in new string[] { "media-skip-backward-symbolic|go-start|" + _("First Frame (Home)"), "media-seek-backward-symbolic|prev-frame|" + _("Previous Frame (Page Up)"),
                                                "media-seek-forward-symbolic|next-frame|" + _("Next Frame (Page Down)"), "media-skip-forward-symbolic|go-end|" + _("Last Frame (End)") }) {
                var parts = spec.split ("|");
                var b = new Button.from_icon_name (parts[0]);
                b.tooltip_text = parts[2];
                b.action_name = "win." + parts[1];
                b.add_css_class ("flat");
                nav.append (b);
            }
            bar.append (nav);
            time_label = bar.add_numeric_label ();
            var only_anim = bar.add_text_toggle (_("Animated Only"), _("Show only properties with keyframes or expressions (U)"));
            only_anim.toggled.connect (() => {
                timeline.only_animated = only_anim.active;
                timeline.rebuild ();
            });
            graph_tools = new Box (Orientation.HORIZONTAL, 6);
            graph_tools.visible = false;
            var speed = new ToggleButton.with_label (_("Speed"));
            speed.add_css_class ("flat");
            speed.tooltip_text = _("Show the speed graph instead of the value graph");
            speed.toggled.connect (() => {
                graph.speed_mode = speed.active;
                graph.fit ();
            });
            graph_tools.append (speed);
            var gfit = new Button.from_icon_name ("zoom-fit-best-symbolic");
            gfit.add_css_class ("flat");
            gfit.tooltip_text = _("Fit Curve");
            gfit.clicked.connect (() => graph.fit ());
            graph_tools.append (gfit);
            var interp = new Button.with_label (_("Interpolation"));
            interp.add_css_class ("flat");
            interp.tooltip_text = _("Change the interpolation of the selected keyframes");
            interp.clicked.connect (() => interpolation_menu (interp));
            graph_tools.append (interp);
            bar.append (graph_tools);
            bar.add_spacer ();
            var zout = bar.add_icon_button ("zoom-out-symbolic", _("Zoom Out Time"));
            zout.clicked.connect (() => {
                timeline.px_per_sec = double.max (5, timeline.px_per_sec / 1.4);
                timeline.queue_draw ();
            });
            var zin = bar.add_icon_button ("zoom-in-symbolic", _("Zoom In Time"));
            zin.clicked.connect (() => {
                timeline.px_per_sec = double.min (4000, timeline.px_per_sec * 1.4);
                timeline.queue_draw ();
            });
            return bar;
        }

        private void interpolation_menu (Widget anchor) {
            var menu = new ContextMenu (anchor);
            foreach (var spec in new string[] { "easy-ease|" + _("Easy Ease"), "easy-ease-in|" + _("Easy Ease In"), "easy-ease-out|" + _("Easy Ease Out"),
                                                "key-linear|" + _("Linear"), "key-auto|" + _("Auto Bezier"), "key-hold|" + _("Hold") }) {
                var parts = spec.split ("|");
                var name = parts[0];
                menu.add_item (parts[1], null, () => activate_action (name, null));
            }
            var presets = menu.add_submenu (_("Presets"), null);
            foreach (var c in Singularity.Motion.Curve.all ()) {
                var id = c.css_name ();
                presets.add_item (EasingPresets.label (id), null, () => activate_action ("ease-preset", new Variant.string (id)));
            }
            foreach (var n in EasingPresets.extra_names ()) {
                var id = n;
                presets.add_item (EasingPresets.label (id), null, () => activate_action ("ease-preset", new Variant.string (id)));
            }
            menu.popup ();
        }

        private void update_status () {
            if (doc.comp == null || time_label == null) return;
            time_label.label = "%s  /  %s".printf (Timecode.format (doc.time, doc.comp.fps), Timecode.format (doc.comp.duration, doc.comp.fps));
            var l = doc.primary ();
            string sel = l != null ? l.name : doc.comp.name;
            status.label = "%s  %s  %.0f ms".printf (sel, viewer.status, doc.service.last_ms);
        }

        private void update_history () {
            if (undo_bubble == null) return;
            undo_bubble.sensitive = doc.can_undo ();
            redo_bubble.sensitive = doc.can_redo ();
            update_title ();
        }

        private void update_title () {
            string name = doc.project.path != "" ? Path.get_basename (doc.project.path) : _("Untitled Project");
            if (doc.project.modified) name = "%s *".printf (name);
            if (doc.comp != null) name = "%s, %s".printf (name, doc.comp.name);
            set_title (name);
        }

        private void activate_item (Item it) {
            var c = it as Composition;
            if (c != null) {
                doc.open_comp (c);
                return;
            }
            var f = it as Footage;
            if (f != null && doc.comp != null) add_footage_layer (f);
        }

        public void add_footage_layer (Footage f) {
            if (doc.comp == null) return;
            if (f.kind == FootageKind.VECTOR) {
                VectorImport.import_into (this, f);
                return;
            }
            doc.edit (_("Add Layer"), () => {
                var l = Factory.footage_layer (doc.comp, f);
                l.in_point = doc.time;
                l.start_time = doc.time;
                l.out_point = double.min (doc.comp.duration, doc.time + (f.duration > 0 ? f.duration : doc.comp.duration));
                doc.comp.add_layer (l, 0);
                doc.select_layer (l);
            });
        }

        public void import_path (string? path) {
            if (path == null) return;
            if (path.has_suffix (".json") && Interchange.is_lottie (path)) {
                Interchange.import_lottie (this, path);
                return;
            }
            if (path.has_suffix (".otio")) {
                Interchange.import_otio (this, path);
                return;
            }
            try {
                var f = MediaPool.probe (path);
                if (project_panel != null && project_panel.selected_item is Folder) f.folder_id = project_panel.selected_item.id;
                doc.edit (_("Import"), () => doc.project.add_item (f));
                if (doc.comp != null && doc.project.items.size <= 2 && doc.comp.layers.size == 0) add_footage_layer (f);
            } catch (Error e) {
                toast (_("Could not import %s: %s").printf (Path.get_basename (path), e.message));
            }
        }

        public void toast (string text) {
            add_toast (new Toast (text));
        }

        public void choose_open () {
            var dlg = new FileDialog ();
            dlg.title = _("Open");
            var filters = new GLib.ListStore (typeof (FileFilter));
            var f = new FileFilter ();
            f.name = _("Keyframe Projects and Animations");
            f.add_pattern ("*.keyframe");
            f.add_pattern ("*.json");
            f.add_pattern ("*.otio");
            f.add_mime_type ("application/x-keyframe");
            filters.append (f);
            dlg.filters = filters;
            dlg.open.begin (this, null, (o, res) => {
                try {
                    var file = dlg.open.end (res);
                    if (file != null) open_project (file);
                } catch (Error e) {
                }
            });
        }

        public void open_project (File file) {
            var path = file.get_path ();
            if (path == null) return;
            if (path.has_suffix (".json") || path.has_suffix (".otio")) {
                if (content_stack.visible_child_name == "welcome") new_project ();
                import_path (path);
                return;
            }
            try {
                var p = NativeFormat.load (path);
                load_into_workspace (p);
                app.note_recent (path);
            } catch (Error e) {
                toast (_("Could not open the project: %s").printf (e.message));
            }
        }

        public async bool save (bool save_as) {
            string path = doc.project.path;
            if (save_as || path == "") {
                var dlg = new FileDialog ();
                dlg.title = _("Save Project");
                dlg.initial_name = (doc.comp != null ? doc.comp.name : _("Project")) + ".keyframe";
                try {
                    var f = yield dlg.save (this, null);
                    if (f == null) return false;
                    path = f.get_path ();
                    if (!path.has_suffix (".keyframe")) path += ".keyframe";
                } catch (Error e) {
                    return false;
                }
            }
            try {
                NativeFormat.save (doc.project, path);
                app.note_recent (path);
                update_title ();
                return true;
            } catch (Error e) {
                toast (_("Could not save: %s").printf (e.message));
                return false;
            }
        }

        private void autosave () {
            if (content_stack.visible_child_name != "workspace" || !doc.project.modified) return;
            try {
                var dir = Path.build_filename (Environment.get_user_cache_dir (), "keyframe", "autosave");
                DirUtils.create_with_parents (dir, 0700);
                var name = doc.project.path != "" ? Path.get_basename (doc.project.path) : "untitled.keyframe";
                var bytes = NativeFormat.save_bytes (doc.project);
                FileUtils.set_data (Path.build_filename (dir, name), bytes);
            } catch (Error e) {
            }
        }

        private async bool confirm_discard () {
            if (!doc.project.modified) return true;
            var dialog = new ConfirmDialog (app, _("Save Changes?"), "dev.sinty.keyframe", _("The project has unsaved changes."), _("Save"), ConfirmDialog.ActionStyle.SUGGESTED);
            dialog.set_secondary (_("Discard"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dialog.transient_for = this;
            dialog.modal = true;
            ConfirmDialog.Response result = ConfirmDialog.Response.CANCEL;
            dialog.response.connect ((r) => {
                result = r;
                confirm_discard.callback ();
            });
            dialog.present ();
            yield;
            if (result == ConfirmDialog.Response.PRIMARY) return yield save (false);
            return result == ConfirmDialog.Response.SECONDARY;
        }

        public async void close_project () {
            if (content_stack.visible_child_name != "workspace") return;
            if (!yield confirm_discard ()) return;
            doc.stop ();
            doc.close ();
            doc = new Document (new Project ());
            show_welcome ();
        }

        private bool on_close_request () {
            if (close_confirmed || content_stack.visible_child_name != "workspace" || !doc.project.modified) {
                if (autosave_source != 0) Source.remove (autosave_source);
                autosave_source = 0;
                doc.close ();
                return false;
            }
            confirm_discard.begin ((o, r) => {
                if (confirm_discard.end (r)) {
                    close_confirmed = true;
                    close ();
                }
            });
            return true;
        }

        private void new_text_at (double x, double y) {
            if (doc.comp == null) return;
            Dialogs.text_prompt (this, _("New Text"), _("Text"), (text) => {
                doc.edit (_("New Text Layer"), () => {
                    var l = Factory.text_layer (doc.comp, text);
                    l.transform.prop ("position").value = { x, y, 0 };
                    doc.comp.add_layer (l, 0);
                    doc.select_layer (l);
                });
                set_tool (ViewerTool.SELECT);
            });
        }

        private void add_layer (Layer l) {
            doc.edit (_("New Layer"), () => {
                doc.comp.add_layer (l, 0);
                doc.select_layer (l);
            });
        }

        private void add_effect_menu (Layer l, Widget anchor) {
            var menu = new ContextMenu (anchor);
            foreach (var cat in EffectRegistry.categories ()) {
                var sub = menu.add_submenu (cat, null);
                foreach (var def in EffectRegistry.all ()) {
                    if (def.category != cat) continue;
                    var id = def.id;
                    sub.add_item (def.label, null, () => doc.edit (_("Add Effect"), () => {
                        EffectRegistry.add_to_layer (l, id);
                        doc.select_layer (l);
                    }));
                }
            }
            menu.popup ();
        }

        private void item_menu (Item it, Widget anchor, double x, double y) {
            var menu = new ContextMenu (anchor);
            menu.add_item (_("Rename"), null, () => Dialogs.rename_item (this, it));
            var c = it as Composition;
            if (c != null) {
                menu.add_item (_("Open Composition"), null, () => doc.open_comp (c));
                menu.add_item (_("Composition Settings"), null, () => Dialogs.comp_settings (this, c));
                menu.add_item (_("Duplicate"), null, () => doc.edit (_("Duplicate"), () => {
                    try {
                        var snap = NativeFormat.snapshot (doc.project);
                        var copy = NativeFormat.restore (snap, doc.project.base_dir).comp_by_id (c.id);
                        copy.id = Layer.new_id ();
                        copy.name = c.name + " " + _("Copy");
                        doc.project.add_item (copy);
                    } catch (Error e) {
                    }
                }));
                if (doc.comp != null && doc.comp != c && !doc.project.precomp_cycle (doc.comp, c)) {
                    menu.add_item (_("Add to Current Composition"), null, () => add_layer (Factory.precomp_layer (doc.comp, c)));
                }
                menu.add_item (_("Add to Render Queue"), null, () => RenderQueueUi.add_comp (this, c));
            }
            var f = it as Footage;
            if (f != null) {
                if (doc.comp != null) menu.add_item (_("Add to Composition"), null, () => add_footage_layer (f));
                menu.add_item (_("Interpret Footage"), null, () => Dialogs.interpret_footage (this, f));
                menu.add_item (_("New Composition from Footage"), null, () => doc.edit (_("New Composition"), () => {
                    var nc = new Composition (f.name, f.width > 0 ? f.width : 1920, f.height > 0 ? f.height : 1080, f.fps > 0 ? f.fps : 30, f.duration > 0 ? f.duration : 10);
                    doc.project.add_item (nc);
                    nc.add_layer (Factory.footage_layer (nc, f));
                    doc.open_comp (nc);
                }));
            }
            menu.add_separator ();
            menu.add_item (_("Delete"), null, () => doc.edit (_("Delete"), () => {
                foreach (var comp in doc.project.compositions ()) {
                    var dead = new Gee.ArrayList<Layer> ();
                    foreach (var l in comp.layers) if (l.source_id == it.id) dead.add (l);
                    foreach (var l in dead) comp.remove_layer (l);
                }
                doc.project.remove_item (it);
                if (doc.comp == it) doc.open_comp (doc.project.compositions ().size > 0 ? doc.project.compositions ()[0] : null);
            }));
            menu.popup ();
        }

        private void layer_menu (Layer l, double x, double y) {
            var menu = new ContextMenu (timeline);
            menu.pointing_to = { (int) x, (int) y, 1, 1 };
            menu.add_item (_("Rename"), null, () => Dialogs.rename_layer (this, l));
            menu.add_item (_("Duplicate"), null, () => activate_action ("duplicate", null));
            menu.add_item (_("Split Layer"), null, () => activate_action ("split-layer", null));
            menu.add_item (_("Pre-compose"), null, () => activate_action ("precompose", null));
            menu.add_item (_("Add Effect"), null, () => add_effect_menu (l, timeline));
            if (l.kind == LayerKind.SOLID) menu.add_item (_("Solid Settings"), null, () => Dialogs.solid (this, l));
            if (l.kind == LayerKind.PRECOMP) menu.add_item (_("Open Composition"), null, () => {
                var c = doc.project.comp_by_id (l.source_id);
                if (c != null) doc.open_comp (c);
            });
            var reveal = menu.add_submenu (_("Reveal"), null);
            reveal.add_item (_("Animated Properties"), null, () => timeline.reveal_animated (l));
            menu.add_separator ();
            menu.add_item (_("Delete"), null, () => activate_action ("delete", null));
            menu.popup ();
        }

        private void key_menu (double x, double y) {
            var menu = new ContextMenu (timeline);
            menu.pointing_to = { (int) x, (int) y, 1, 1 };
            menu.add_item (_("Easy Ease"), null, () => activate_action ("easy-ease", null));
            menu.add_item (_("Easy Ease In"), null, () => activate_action ("easy-ease-in", null));
            menu.add_item (_("Easy Ease Out"), null, () => activate_action ("easy-ease-out", null));
            menu.add_item (_("Linear"), null, () => activate_action ("key-linear", null));
            menu.add_item (_("Auto Bezier"), null, () => activate_action ("key-auto", null));
            menu.add_item (_("Hold"), null, () => activate_action ("key-hold", null));
            menu.add_item (_("Rove Across Time"), null, () => activate_action ("key-rove", null));
            menu.add_item (_("Keyframe Velocity"), null, () => {
                if (doc.selected_keys.size > 0) Dialogs.keyframe_velocity (this, doc.key_owner[doc.selected_keys[0]], doc.selected_keys[0]);
            });
            menu.add_separator ();
            menu.add_item (_("Delete"), null, () => activate_action ("delete-keys", null));
            menu.popup ();
        }

        private void parent_menu (Layer l, double x, double y) {
            var menu = new ContextMenu (timeline);
            menu.pointing_to = { (int) x, (int) y, 1, 1 };
            var parent = menu.add_submenu (_("Parent"), null);
            parent.add_item (_("None"), null, () => doc.edit (_("Parent"), () => {
                set_parent (l, null);
            }));
            foreach (var o in doc.comp.layers) {
                if (o == l || doc.comp.would_cycle (l, o)) continue;
                var target = o;
                parent.add_item ("%d. %s".printf (doc.comp.index_of (o) + 1, o.name), null, () => doc.edit (_("Parent"), () => set_parent (l, target)));
            }
            var matte = menu.add_submenu (_("Track Matte"), null);
            string[] labels = { _("No Track Matte"), _("Alpha Matte"), _("Alpha Inverted Matte"), _("Luma Matte"), _("Luma Inverted Matte") };
            for (int i = 0; i < labels.length; i++) {
                int mode = i;
                matte.add_item (labels[i], null, () => doc.edit (_("Track Matte"), () => {
                    l.matte_mode = (MatteMode) mode;
                    l.mark_changed ();
                }));
            }
            var src = menu.add_submenu (_("Matte Layer"), null);
            src.add_item (_("Layer Above"), null, () => doc.edit (_("Track Matte"), () => {
                l.matte_id = "";
                l.mark_changed ();
            }));
            foreach (var o in doc.comp.layers) {
                if (o == l) continue;
                var target = o;
                src.add_item ("%d. %s".printf (doc.comp.index_of (o) + 1, o.name), null, () => doc.edit (_("Track Matte"), () => {
                    l.matte_id = target.id;
                    if (l.matte_mode == MatteMode.NONE) l.matte_mode = MatteMode.ALPHA;
                    l.mark_changed ();
                }));
            }
            menu.popup ();
        }

        public void set_parent (Layer l, Layer? parent) {
            double t = doc.time;
            var world = l.world_matrix (t);
            l.parent_id = parent != null ? parent.id : "";
            var pw = parent != null ? parent.world_matrix (t) : new Mat4 ();
            var inv = pw.inverted () ?? new Mat4 ();
            var local = inv.multiply (world);
            var a = l.transform.vec ("anchor", l.layer_time (t));
            var np = local.transform_point (Vec3 (a[0], a[1], a.length > 2 ? a[2] : 0));
            var pp = l.transform.prop ("position");
            if (pp != null && pp.keys.size == 0) pp.value = { np.x, np.y, np.z };
            double sx = Math.sqrt (local.m[0] * local.m[0] + local.m[4] * local.m[4]);
            double sy = Math.sqrt (local.m[1] * local.m[1] + local.m[5] * local.m[5]);
            var sp = l.transform.prop ("scale");
            if (sp != null && sp.keys.size == 0) sp.value = { sx * 100, sy * 100, sp.value.length > 2 ? sp.value[2] : 100 };
            var rp = l.transform.prop ("rotation");
            if (rp != null && rp.keys.size == 0) rp.value = { Math.atan2 (local.m[4], local.m[0]) * 180 / Math.PI };
            l.mark_changed ();
        }

        private void blend_menu (Layer l, double x, double y) {
            var menu = new ContextMenu (timeline);
            menu.pointing_to = { (int) x, (int) y, 1, 1 };
            for (int i = 0; i < Singularity.Imaging.BlendMode.COUNT; i++) {
                var mode = (Singularity.Imaging.BlendMode) i;
                menu.add_item (mode.label (), null, () => doc.edit (_("Blending Mode"), () => {
                    l.blend = mode;
                    l.mark_changed ();
                }));
            }
            menu.popup ();
        }

        private void mask_menu (PropGroup mask, double x, double y) {
            var menu = new ContextMenu (timeline);
            menu.pointing_to = { (int) x, (int) y, 1, 1 };
            foreach (var m in new string[] { "add", "subtract", "intersect", "lighten", "darken", "difference", "none" }) {
                var mode = m;
                menu.add_item (Timeline.mask_mode_label (m), null, () => doc.edit (_("Mask Mode"), () => mask.set_attr ("mode", mode)));
            }
            menu.add_separator ();
            menu.add_item (_("Inverted"), null, () => doc.edit (_("Invert Mask"), () => mask.set_attr ("inverted", mask.attr ("inverted", "false") == "true" ? "false" : "true")));
            menu.popup ();
        }

        private void foreach_selected_key (Doc.KeyFunc f) {
            doc.edit (_("Keyframe Interpolation"), () => {
                foreach (var k in doc.selected_keys) {
                    var p = doc.key_owner[k];
                    f (p, k);
                    if (p != null) p.touch ();
                }
            });
            timeline.queue_draw ();
            graph.queue_draw ();
        }

        private void install_actions () {
            action ("save", () => save.begin (false));
            action ("save-as", () => save.begin (true));
            action ("close-project", () => close_project.begin ());
            action ("undo", () => doc.undo ());
            action ("redo", () => doc.redo ());
            action ("toggle-sidebar", () => set_sidebar_visible (!get_sidebar_visible ()));
            action ("import", () => {
                var dlg = new FileDialog ();
                dlg.title = _("Import");
                dlg.open_multiple.begin (this, null, (o, res) => {
                    try {
                        var files = dlg.open_multiple.end (res);
                        for (uint i = 0; i < files.get_n_items (); i++) import_path (((File) files.get_item (i)).get_path ());
                    } catch (Error e) {
                    }
                });
            });
            action ("new-comp", () => {
                var c = new Composition (_("Composition %d").printf (doc.project.compositions ().size + 1), app.settings_int ("default-width", 1920), app.settings_int ("default-height", 1080), app.settings_double ("default-fps", 30), app.settings_int ("default-duration", 10));
                Dialogs.comp_settings (this, c, true);
            });
            action ("comp-settings", () => {
                if (doc.comp != null) Dialogs.comp_settings (this, doc.comp);
            });
            action ("project-settings", () => Dialogs.project_settings (this));
            action ("new-solid", () => {
                if (doc.comp != null) Dialogs.new_solid (this);
            });
            action ("new-null", () => {
                if (doc.comp != null) add_layer (Factory.null_layer (doc.comp));
            });
            action ("new-shape", () => {
                if (doc.comp != null) add_layer (Factory.shape_layer (doc.comp));
            });
            action ("new-text", () => {
                if (doc.comp != null) new_text_at (doc.comp.width / 2.0, doc.comp.height / 2.0);
            });
            action ("new-adjustment", () => {
                if (doc.comp != null) add_layer (Factory.adjustment (doc.comp));
            });
            action ("new-camera", () => {
                if (doc.comp != null) add_layer (Factory.camera (doc.comp, 50));
            });
            action ("new-light", () => {
                if (doc.comp != null) add_layer (Factory.light (doc.comp, LightType.SPOT));
            });
            action ("delete", () => {
                if (doc.selected_keys.size > 0) {
                    activate_action ("delete-keys", null);
                    return;
                }
                if (doc.comp == null || doc.selection.size == 0) return;
                doc.edit (_("Delete Layers"), () => {
                    foreach (var l in doc.selection) doc.comp.remove_layer (l);
                    doc.selection.clear ();
                });
                doc.selection_changed ();
            });
            action ("delete-keys", () => {
                doc.edit (_("Delete Keyframes"), () => {
                    foreach (var k in doc.selected_keys) {
                        var p = doc.key_owner[k];
                        if (p != null) p.remove_key (k);
                    }
                });
                doc.clear_keys ();
            });
            action ("duplicate", () => {
                if (doc.comp == null) return;
                doc.edit (_("Duplicate"), () => {
                    var copies = new Gee.ArrayList<Layer> ();
                    foreach (var l in doc.selection) {
                        var d = l.duplicate ();
                        d.name = doc.comp.unique_layer_name (l.name);
                        doc.comp.add_layer (d, doc.comp.index_of (l));
                        copies.add (d);
                    }
                    doc.selection.clear ();
                    doc.selection.add_all (copies);
                });
                doc.selection_changed ();
            });
            action ("split-layer", () => {
                if (doc.comp == null) return;
                doc.edit (_("Split Layer"), () => {
                    foreach (var l in doc.selection) {
                        if (doc.time <= l.in_point || doc.time >= l.out_point) continue;
                        var d = l.duplicate ();
                        d.name = doc.comp.unique_layer_name (l.name);
                        d.in_point = doc.time;
                        l.out_point = doc.time;
                        doc.comp.add_layer (d, doc.comp.index_of (l));
                    }
                });
            });
            action ("precompose", () => Dialogs.precompose (this));
            action ("select-all", () => {
                if (doc.comp == null) return;
                doc.selection.clear ();
                doc.selection.add_all (doc.comp.layers);
                doc.selection_changed ();
            });
            action ("play", () => doc.toggle_play ());
            action ("next-frame", () => doc.step_frames (1));
            action ("prev-frame", () => doc.step_frames (-1));
            action ("next-frame-10", () => doc.step_frames (10));
            action ("prev-frame-10", () => doc.step_frames (-10));
            action ("go-start", () => doc.seek (0));
            action ("go-end", () => {
                if (doc.comp != null) doc.seek (doc.comp.duration);
            });
            action ("set-in", () => doc.edit (_("Set In Point"), () => {
                foreach (var l in doc.selection) {
                    l.in_point = doc.time;
                    l.mark_changed ();
                }
            }));
            action ("set-out", () => doc.edit (_("Set Out Point"), () => {
                foreach (var l in doc.selection) {
                    l.out_point = doc.time + 1 / doc.comp.fps;
                    l.mark_changed ();
                }
            }));
            action ("work-start", () => {
                if (doc.comp != null) doc.edit (_("Work Area"), () => doc.comp.work_start = doc.time);
            });
            action ("work-end", () => {
                if (doc.comp != null) doc.edit (_("Work Area"), () => doc.comp.work_end = doc.time + 1 / doc.comp.fps);
            });
            action ("add-marker", () => {
                if (doc.comp != null) doc.edit (_("Add Marker"), () => {
                    doc.comp.markers.add (new Marker (doc.time));
                    doc.comp.layer_changed (null);
                });
            });
            action ("easy-ease", () => foreach_selected_key ((p, k) => k.set_easy_ease ()));
            action ("easy-ease-in", () => foreach_selected_key ((p, k) => {
                k.in_interp = Interp.BEZIER;
                k.ease_in_x = 1 - 0.3333;
                k.ease_in_y = 1;
                k.auto_bezier = false;
            }));
            action ("easy-ease-out", () => foreach_selected_key ((p, k) => {
                k.out_interp = Interp.BEZIER;
                k.ease_out_x = 0.3333;
                k.ease_out_y = 0;
                k.auto_bezier = false;
            }));
            action ("key-linear", () => foreach_selected_key ((p, k) => {
                k.in_interp = Interp.LINEAR;
                k.out_interp = Interp.LINEAR;
                k.auto_bezier = false;
            }));
            action ("key-hold", () => foreach_selected_key ((p, k) => k.out_interp = Interp.HOLD));
            action ("key-auto", () => foreach_selected_key ((p, k) => {
                k.in_interp = Interp.BEZIER;
                k.out_interp = Interp.BEZIER;
                k.auto_bezier = true;
            }));
            action ("key-rove", () => foreach_selected_key ((p, k) => k.roving = !k.roving));
            var preset = new SimpleAction ("ease-preset", VariantType.STRING);
            preset.activate.connect ((v) => {
                var name = v.get_string ();
                foreach_selected_key ((p, k) => EasingPresets.apply (name, p, k));
            });
            add_action (preset);
            action ("reveal-animated", () => {
                var l = doc.primary ();
                if (l != null) timeline.reveal_animated (l);
            });
            action ("graph-editor", () => {
                lower_switch.set_active (lower_stack.visible_child_name == "graph" ? "timeline" : "graph");
                lower_stack.visible_child_name = lower_switch.active_option;
                graph_tools.visible = lower_stack.visible_child_name == "graph";
                graph.fit ();
            });
            action ("toggle-roi", () => roi_toggle.active = !roi_toggle.active);
            var tool = new SimpleAction ("tool", VariantType.STRING);
            tool.activate.connect ((v) => {
                switch (v.get_string ()) {
                    case "select": set_tool (ViewerTool.SELECT); break;
                    case "hand": set_tool (ViewerTool.HAND); break;
                    case "rect": set_tool (ViewerTool.RECT); break;
                    case "ellipse": set_tool (ViewerTool.ELLIPSE); break;
                    case "star": set_tool (ViewerTool.STAR); break;
                    case "pen": set_tool (ViewerTool.PEN); break;
                    case "text": set_tool (ViewerTool.TEXT); break;
                    case "puppet": set_tool (ViewerTool.PUPPET); break;
                }
            });
            add_action (tool);
            var res = new SimpleAction ("resolution", VariantType.INT32);
            res.activate.connect ((v) => resolution.selected = (uint) v.get_int32 ().clamp (0, 4));
            add_action (res);
            var shape_item = new SimpleAction ("add-shape-item", VariantType.STRING);
            shape_item.activate.connect ((v) => {
                var l = doc.primary ();
                if (l == null || l.contents == null) return;
                var type = v.get_string ();
                doc.edit (_("Add Shape Item"), () => {
                    var g = Factory.shape_item (type);
                    if (g == null) return;
                    g.key = l.contents.unique_key (g.key);
                    if (type == "shape.fill" || type == "shape.stroke" || type == "shape.gradient-fill" || type == "shape.gradient-stroke" || type == "shape.repeater" || type == "shape.merge"
                        || type == "shape.trim" || type == "shape.round" || type == "shape.wiggle" || type == "shape.zigzag" || type == "shape.offset" || type == "shape.pucker" || type == "shape.twist") l.contents.add<PropGroup> (g);
                    else l.contents.insert (0, g);
                    l.mark_changed ();
                });
                inspector.rebuild ();
                timeline.rebuild ();
            });
            add_action (shape_item);
            var animator = new SimpleAction ("add-text-animator", VariantType.STRING);
            animator.activate.connect ((v) => {
                var l = doc.primary ();
                if (l == null || l.text_group == null) return;
                var key = v.get_string ();
                doc.edit (_("Add Text Animator"), () => {
                    var anims = l.text_group.group ("animators");
                    var an = Factory.text_animator (_("Animator %d").printf (anims.children.size + 1));
                    an.key = anims.unique_key ("animator");
                    an.group ("selectors").add<PropGroup> (Factory.range_selector ());
                    var p = Factory.animator_property (key);
                    if (p != null) an.group ("properties").add<Property> (p);
                    anims.add<PropGroup> (an);
                    l.mark_changed ();
                });
                inspector.rebuild ();
                timeline.rebuild ();
            });
            add_action (animator);
            var selector = new SimpleAction ("add-text-selector", VariantType.STRING);
            selector.activate.connect ((v) => {
                var parts = v.get_string ().split ("|");
                var l = doc.primary ();
                if (l == null || l.text_group == null || parts.length < 2) return;
                var an = l.text_group.group ("animators").group (parts[1]);
                if (an == null) return;
                doc.edit (_("Add Selector"), () => {
                    PropGroup sel = parts[0] == "wiggly" ? Factory.wiggly_selector () : (parts[0] == "expression" ? Factory.expression_selector () : Factory.range_selector ());
                    sel.key = an.group ("selectors").unique_key (sel.key);
                    an.group ("selectors").add<PropGroup> (sel);
                    l.mark_changed ();
                });
                inspector.rebuild ();
            });
            add_action (selector);
            var aprop = new SimpleAction ("add-animator-property", VariantType.STRING);
            aprop.activate.connect ((v) => {
                var parts = v.get_string ().split ("|");
                var l = doc.primary ();
                if (l == null || l.text_group == null || parts.length < 2) return;
                var an = l.text_group.group ("animators").group (parts[1]);
                if (an == null || an.group ("properties").prop (parts[0]) != null) return;
                doc.edit (_("Add Animator Property"), () => {
                    an.group ("properties").add<Property> (Factory.animator_property (parts[0]));
                    l.mark_changed ();
                });
                inspector.rebuild ();
            });
            add_action (aprop);
            action ("export-frame", () => Exports.export_frame (this));
            action ("print", () => Exports.print_frame (this));
            ExtraActions.install (this);
        }

        public delegate void Act ();

        public void action (string name, owned Act f) {
            var a = new SimpleAction (name, null);
            a.activate.connect (() => {
                if (content_stack.visible_child_name != "workspace" && name != "import") return;
                f ();
            });
            add_action (a);
        }
    }

    namespace Doc {
        public delegate void KeyFunc (Property? p, Keyframe k);
    }
}
