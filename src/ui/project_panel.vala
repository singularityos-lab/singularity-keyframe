using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Keyframe {

    public class ProjectPanel : AppSidebar {
        private Document doc;
        private ListBox list;
        private WelcomePage footage_empty;
        private string query = "";
        private Gee.HashMap<ListBoxRow, Item> row_items = new Gee.HashMap<ListBoxRow, Item> ();
        public Item? selected_item = null;

        public signal void item_activated (Item item);
        public signal void request_import ();
        public signal void request_new_comp ();
        public signal void request_item_menu (Item item, Widget anchor, double x, double y);

        public ProjectPanel (Document doc) {
            base (280);
            this.doc = doc;
            add_bubble_icon ("list-add-symbolic", _("Import Footage (Ctrl+I)"), () => request_import ());
            add_bubble_icon ("document-new-symbolic", _("New Composition (Ctrl+N)"), () => request_new_comp ());
            add_bubble_icon ("folder-new-symbolic", _("New Folder"), () => {
                doc.edit (_("New Folder"), () => {
                    var f = new Folder (_("Folder"));
                    if (selected_item is Folder) f.folder_id = selected_item.id;
                    doc.project.add_item (f);
                });
            });
            add_bubble_search (_("Search Project"), (t) => {
                query = t;
                rebuild ();
            });
            list = new ListBox ();
            list.selection_mode = SelectionMode.SINGLE;
            list.add_css_class ("navigation-sidebar");
            list.row_activated.connect ((row) => {
                var it = row_items[row];
                if (it == null) return;
                if (it is Folder) {
                    ((Folder) it).expanded = !((Folder) it).expanded;
                    rebuild ();
                    return;
                }
                item_activated (it);
            });
            list.row_selected.connect ((row) => selected_item = row != null ? row_items[row] : null);
            box.append (list);
            footage_empty = new WelcomePage ();
            footage_empty.is_section = true;
            footage_empty.compact = true;
            footage_empty.embedded = true;
            footage_empty.title = _("No Footage Yet");
            footage_empty.subtitle = _("Bring in video, audio, pictures or vector art to animate in your compositions.");
            footage_empty.add_action ("video-x-generic", _("Import Footage"), _("Video, audio, pictures and SVG files"), () => request_import ());
            footage_empty.add_action ("x-office-presentation", _("New Composition"), _("Another timeline in this project"), () => request_new_comp ());
            footage_empty.margin_start = 6;
            footage_empty.margin_end = 6;
            footage_empty.valign = Align.START;
            footage_empty.vexpand = false;
            box.append (footage_empty);
            var drop = new DropTarget (typeof (string), Gdk.DragAction.MOVE);
            drop.drop.connect ((val, x, y) => {
                var target_row = list.get_row_at_y ((int) y);
                var target = target_row != null ? row_items[target_row] : null;
                var it = doc.project.item_by_id ((string) val);
                if (it == null) return false;
                string folder = "";
                if (target is Folder) folder = target.id;
                else if (target != null) folder = target.folder_id;
                if (folder == it.id) return false;
                doc.edit (_("Move to Folder"), () => {
                    it.folder_id = folder;
                    doc.project.structure_changed ();
                });
                return true;
            });
            list.add_controller (drop);
            doc.structure_changed.connect (rebuild);
            rebuild ();
        }

        public void rebuild () {
            Widget? c;
            while ((c = list.get_first_child ()) != null) list.remove (c);
            row_items.clear ();
            if (query.strip () != "") {
                foreach (var it in doc.project.search (query)) add_row (it, 0);
                footage_empty.visible = false;
                if (row_items.size == 0) {
                    var sp = new StatusPage ();
                    sp.icon_name = "dev.sinty.keyframe";
                    sp.title = _("No Results");
                    sp.description = _("No composition or footage matches the search.");
                    sp.compact = true;
                    append_static (sp);
                }
                return;
            }
            var comps = new Gee.ArrayList<Item> ();
            foreach (var it in doc.project.children_of ("")) if (it is Composition) comps.add (it);
            comps.sort ((a, b) => strcmp (a.name.down (), b.name.down ()));
            if (comps.size > 0) {
                append_static (new SidebarSectionLabel (_("Compositions")));
                foreach (var it in comps) add_row (it, 0);
            }
            int before = row_items.size;
            var media_label = new SidebarSectionLabel (_("Footage"));
            append_static (media_label);
            add_children ("", 0, true);
            bool has_media = row_items.size > before;
            media_label.get_parent ().visible = has_media;
            footage_empty.visible = !has_media;
        }

        private void append_static (Widget w) {
            var row = new ListBoxRow ();
            row.child = w;
            row.selectable = false;
            row.activatable = false;
            row.focusable = false;
            list.append (row);
        }

        private void add_children (string folder_id, int depth, bool skip_comps = false) {
            var items = doc.project.children_of (folder_id);
            if (skip_comps) {
                var kept = new Gee.ArrayList<Item> ();
                foreach (var i in items) if (!(i is Composition)) kept.add (i);
                items = kept;
            }
            items.sort ((a, b) => {
                bool fa = a is Folder, fb = b is Folder;
                if (fa != fb) return fa ? -1 : 1;
                return strcmp (a.name.down (), b.name.down ());
            });
            foreach (var it in items) {
                add_row (it, depth);
                if (it is Folder && ((Folder) it).expanded) add_children (it.id, depth + 1);
            }
        }

        private string icon_for (Item it) {
            if (it is Folder) return "folder-symbolic";
            if (it is Composition) return "keyframe-composition-symbolic";
            var f = it as Footage;
            if (f == null) return "text-x-generic-symbolic";
            switch (f.kind) {
                case FootageKind.IMAGE: return "image-x-generic-symbolic";
                case FootageKind.SEQUENCE: return "view-paged-symbolic";
                case FootageKind.AUDIO: return "audio-x-generic-symbolic";
                case FootageKind.VECTOR: return "keyframe-shape-symbolic";
                case FootageKind.MODEL: return "keyframe-cube-symbolic";
                default: return "video-x-generic-symbolic";
            }
        }

        private string subtitle_for (Item it) {
            var c = it as Composition;
            if (c != null) return "%d x %d, %.3g fps, %s".printf (c.width, c.height, c.fps, Timecode.format (c.duration, c.fps));
            var f = it as Footage;
            if (f != null) {
                if (f.kind == FootageKind.AUDIO) return _("Audio, %.1f s").printf (f.duration);
                if (f.width > 0) return "%d x %d%s".printf (f.width, f.height, f.duration > 0 ? ", %.1f s".printf (f.duration) : "");
                return Path.get_basename (f.path);
            }
            var d = it as Folder;
            if (d != null) return ngettext ("%d item", "%d items", doc.project.children_of (d.id).size).printf (doc.project.children_of (d.id).size);
            return "";
        }

        private void add_row (Item it, int depth) {
            var row = new ListBoxRow ();
            var box = new Box (Orientation.HORIZONTAL, 8);
            box.margin_start = 6 + depth * 14;
            box.margin_top = 4;
            box.margin_bottom = 4;
            var icon = new Image.from_icon_name (icon_for (it));
            box.append (icon);
            var texts = new Box (Orientation.VERTICAL, 0);
            var name = new Label (it.name);
            name.xalign = 0;
            name.ellipsize = Pango.EllipsizeMode.MIDDLE;
            texts.append (name);
            var sub = new Label (subtitle_for (it));
            sub.xalign = 0;
            sub.ellipsize = Pango.EllipsizeMode.END;
            sub.add_css_class ("dim-label");
            sub.add_css_class ("caption");
            texts.append (sub);
            texts.hexpand = true;
            box.append (texts);
            var f = it as Footage;
            if (f != null && f.path != "" && f.kind != FootageKind.SEQUENCE && !FileUtils.test (f.path, FileTest.EXISTS)) {
                var warn = new Image.from_icon_name ("dialog-warning-symbolic");
                warn.tooltip_text = _("Missing file");
                box.append (warn);
            }
            row.child = box;
            row.tooltip_text = f != null ? f.path : it.name;
            var ds = new DragSource ();
            ds.actions = Gdk.DragAction.COPY | Gdk.DragAction.MOVE;
            string id = it.id;
            ds.prepare.connect ((x, y) => new Gdk.ContentProvider.for_value (id));
            row.add_controller (ds);
            var rc = new GestureClick ();
            rc.set_button (3);
            rc.pressed.connect ((n, x, y) => {
                list.select_row (row);
                selected_item = it;
                request_item_menu (it, row, x, y);
            });
            row.add_controller (rc);
            row_items[row] = it;
            list.append (row);
        }
    }
}
