using Gtk;

namespace Singularity.Apps.Keyframe {

    public class KeyframeApp : Singularity.Application {
        private const string CSS = """
.keyframe-source-text,
.keyframe-source-text text {
    background-color: transparent;
}

.keyframe-viewer:focus-visible,
.keyframe-viewer:focus,
.keyframe-timeline:focus-visible,
.keyframe-timeline:focus,
.keyframe-graph:focus-visible,
.keyframe-graph:focus {
    outline: none;
    box-shadow: none;
}
""";
        public GLib.Settings? settings = null;

        public KeyframeApp () {
            Object (application_id: "dev.sinty.keyframe", flags: ApplicationFlags.HANDLES_OPEN);
        }

        protected override void startup () {
            base.startup ();
            about_version = "0.1.0";
            about_license = _("GNU General Public License, version 3 only");
            var schema = SettingsSchemaSource.get_default ()?.lookup ("dev.sinty.keyframe", true);
            if (schema != null) settings = new GLib.Settings ("dev.sinty.keyframe");
            Gtk.IconTheme.get_for_display (Gdk.Display.get_default ()).add_resource_path ("/dev/sinty/keyframe/icons");
            Singularity.Application.add_app_css (CSS);
            EffectRegistry.ensure ();
            EffectPlugins.load_all ();
            Expressions.install ();
            install_actions ();
            build_menu ();
            install_accels ();
        }

        public int settings_int (string key, int fallback) {
            if (settings == null || settings.settings_schema.has_key (key) == false) return fallback;
            var v = settings.get_value (key);
            if (v.is_of_type (VariantType.STRING)) return int.parse (v.get_string ());
            return settings.get_int (key);
        }

        public double settings_double (string key, double fallback) {
            if (settings == null || settings.settings_schema.has_key (key) == false) return fallback;
            return settings.get_double (key);
        }

        public int settings_resolution () {
            if (settings == null) return 0;
            switch (settings.get_string ("preview-resolution")) {
                case "full": return 1;
                case "half": return 2;
                case "third": return 3;
                case "quarter": return 4;
                default: return 0;
            }
        }

        public void note_recent (string path) {
            try {
                Gtk.RecentManager.get_default ().add_full (File.new_for_path (path).get_uri (), Gtk.RecentData () {
                    display_name = Path.get_basename (path),
                    mime_type = "application/x-keyframe",
                    app_name = "Keyframe",
                    app_exec = "singularity-keyframe %u"
                });
            } catch (Error e) {
            }
        }

        public override void activate () {
            window ().present ();
        }

        public override void open (File[] files, string hint) {
            foreach (var file in files) {
                var w = get_active_window () as KeyframeWindow;
                if (w == null || w.doc.project.items.size > 0) w = new KeyframeWindow (this);
                w.open_project (file);
                w.present ();
            }
        }

        private KeyframeWindow window () {
            var current = get_active_window () as KeyframeWindow;
            if (current == null) current = new KeyframeWindow (this);
            return current;
        }

        private void install_actions () {
            var new_action = new SimpleAction ("new", null);
            new_action.activate.connect (() => window ().new_project ());
            add_action (new_action);
            var open_action = new SimpleAction ("open", null);
            open_action.activate.connect (() => window ().choose_open ());
            add_action (open_action);
            var quit = new SimpleAction ("quit", null);
            quit.activate.connect (() => {
                var windows = new Gee.ArrayList<Gtk.Window> ();
                foreach (var item in get_windows ()) windows.add (item);
                foreach (var item in windows) item.close ();
            });
            add_action (quit);
        }

        private void install_accels () {
            string[,] accels = {
                { "app.new", "<Control><Alt>n" }, { "app.open", "<Control>o" }, { "app.quit", "<Control>q" },
                { "win.save", "<Control>s" }, { "win.save-as", "<Control><Shift>s" }, { "win.close-project", "<Control>w" },
                { "win.undo", "<Control>z" }, { "win.import", "<Control>i" }, { "win.new-comp", "<Control>n" },
                { "win.comp-settings", "<Control>k" }, { "win.new-solid", "<Control>y" }, { "win.new-null", "<Control><Alt><Shift>y" },
                { "win.new-adjustment", "<Control><Alt>y" }, { "win.new-text", "<Control><Alt><Shift>t" }, { "win.new-camera", "<Control><Alt><Shift>c" },
                { "win.new-light", "<Control><Alt><Shift>l" }, { "win.precompose", "<Control><Shift>c" }, { "win.duplicate", "<Control>d" },
                { "win.split-layer", "<Control><Shift>d" }, { "win.delete", "Delete" }, { "win.select-all", "<Control>a" },
                { "win.play", "space" }, { "win.next-frame", "Page_Down" }, { "win.prev-frame", "Page_Up" },
                { "win.next-frame-10", "<Shift>Page_Down" }, { "win.prev-frame-10", "<Shift>Page_Up" }, { "win.go-start", "Home" }, { "win.go-end", "End" },
                { "win.set-in", "bracketleft" }, { "win.set-out", "bracketright" }, { "win.work-start", "b" }, { "win.work-end", "n" },
                { "win.easy-ease", "<Control>F9" }, { "win.easy-ease-in", "<Shift>F9" }, { "win.easy-ease-out", "<Control><Shift>F9" },
                { "win.key-hold", "<Control><Alt>h" }, { "win.reveal-animated", "u" }, { "win.graph-editor", "<Shift>F3" },
                { "win.toggle-sidebar", "F9" }, { "win.add-marker", "asterisk" }, { "win.print", "<Control>p" },
                { "win.export-frame", "<Control><Alt>s" }, { "win.project-settings", "<Control><Alt><Shift>k" }
            };
            for (int i = 0; i < accels.length[0]; i++) set_accels_for_action (accels[i, 0], { accels[i, 1] });
            set_accels_for_action ("win.redo", { "<Control><Shift>z", "<Control>y" });
            set_accels_for_action ("win.tool::select", { "v" });
            set_accels_for_action ("win.tool::hand", { "h" });
            set_accels_for_action ("win.tool::rect", { "q" });
            set_accels_for_action ("win.tool::pen", { "g" });
            set_accels_for_action ("win.tool::text", { "<Control>t" });
        }

        private static GLib.Menu section (string[,] items) {
            var result = new GLib.Menu ();
            for (int i = 0; i < items.length[0]; i++) result.append (items[i, 0], items[i, 1]);
            return result;
        }

        private void build_menu () {
            var menu = new GLib.Menu ();
            var file = new GLib.Menu ();
            file.append_section (null, section ({ { _("New Project"), "app.new" }, { _("Open…"), "app.open" }, { _("Import…"), "win.import" } }));
            file.append_section (null, section ({ { _("Save"), "win.save" }, { _("Save As…"), "win.save-as" }, { _("Save as Motion Template…"), "win.save-template" } }));
            file.append_section (null, section ({ { _("Add to Render Queue"), "win.add-render-queue" }, { _("Render Queue"), "win.render-queue" },
                                                  { _("Export Lottie…"), "win.export-lottie" }, { _("Export OpenTimelineIO…"), "win.export-otio" },
                                                  { _("Save Frame As…"), "win.export-frame" }, { _("Export Animation Tokens…"), "win.export-tokens" } }));
            file.append_section (null, section ({ { _("Print Frame…"), "win.print" } }));
            file.append_section (null, section ({ { _("Run Script…"), "win.run-script" } }));
            file.append_section (null, section ({ { _("Project Settings"), "win.project-settings" }, { _("Close Project"), "win.close-project" }, { _("Quit"), "app.quit" } }));
            menu.append_submenu (_("File"), file);
            var edit = new GLib.Menu ();
            edit.append_section (null, section ({ { _("Undo"), "win.undo" }, { _("Redo"), "win.redo" } }));
            edit.append_section (null, section ({ { _("Duplicate"), "win.duplicate" }, { _("Split Layer"), "win.split-layer" }, { _("Delete"), "win.delete" }, { _("Select All"), "win.select-all" } }));
            menu.append_submenu (_("Edit"), edit);
            var comp = new GLib.Menu ();
            comp.append_section (null, section ({ { _("New Composition…"), "win.new-comp" }, { _("Composition Settings…"), "win.comp-settings" } }));
            comp.append_section (null, section ({ { _("Preview"), "win.play" }, { _("Add Marker"), "win.add-marker" } }));
            menu.append_submenu (_("Composition"), comp);
            var layer = new GLib.Menu ();
            layer.append_section (null, section ({ { _("New Text"), "win.new-text" }, { _("New Solid…"), "win.new-solid" }, { _("New Shape Layer"), "win.new-shape" },
                                                   { _("New Null Object"), "win.new-null" }, { _("New Adjustment Layer"), "win.new-adjustment" },
                                                   { _("New Camera"), "win.new-camera" }, { _("New Light"), "win.new-light" } }));
            layer.append_section (null, section ({ { _("Pre-compose…"), "win.precompose" } }));
            menu.append_submenu (_("Layer"), layer);
            var anim = new GLib.Menu ();
            anim.append_section (null, section ({ { _("Easy Ease"), "win.easy-ease" }, { _("Easy Ease In"), "win.easy-ease-in" }, { _("Easy Ease Out"), "win.easy-ease-out" } }));
            anim.append_section (null, section ({ { _("Linear"), "win.key-linear" }, { _("Auto Bezier"), "win.key-auto" }, { _("Hold"), "win.key-hold" }, { _("Rove Across Time"), "win.key-rove" } }));
            anim.append_section (null, section ({ { _("Reveal Animated Properties"), "win.reveal-animated" }, { _("Graph Editor"), "win.graph-editor" } }));
            menu.append_submenu (_("Animation"), anim);
            var view = new GLib.Menu ();
            view.append_section (null, section ({ { _("Project"), "win.toggle-sidebar" }, { _("Region of Interest"), "win.toggle-roi" } }));
            view.append_section (null, section ({ { _("Auto Resolution"), "win.resolution(0)" }, { _("Full Resolution"), "win.resolution(1)" }, { _("Half Resolution"), "win.resolution(2)" },
                                                  { _("Third Resolution"), "win.resolution(3)" }, { _("Quarter Resolution"), "win.resolution(4)" } }));
            menu.append_submenu (_("View"), view);
            set_menubar (menu);
        }
    }
}

int main (string[] args) {
    Gst.init (ref args);
    return new Singularity.Apps.Keyframe.KeyframeApp ().run (args);
}
