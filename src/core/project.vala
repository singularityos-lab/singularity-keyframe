namespace Singularity.Apps.Keyframe {

    public abstract class Item : Object {
        public string id = Layer.new_id ();
        public string name = "";
        public string folder_id = "";
        public int label = 0;
        public string comment = "";

        public abstract string kind_id ();
    }

    public class Folder : Item {
        public bool expanded = true;

        public Folder (string name) {
            this.name = name;
        }

        public override string kind_id () {
            return "folder";
        }
    }

    public enum FootageKind {
        VIDEO,
        IMAGE,
        SEQUENCE,
        AUDIO,
        VECTOR,
        MODEL;

        public string to_id () {
            switch (this) {
                case IMAGE: return "image";
                case SEQUENCE: return "sequence";
                case AUDIO: return "audio";
                case VECTOR: return "vector";
                case MODEL: return "model";
                default: return "video";
            }
        }

        public static FootageKind from_id (string? s) {
            switch (s) {
                case "image": return IMAGE;
                case "sequence": return SEQUENCE;
                case "audio": return AUDIO;
                case "vector": return VECTOR;
                case "model": return MODEL;
                default: return VIDEO;
            }
        }
    }

    public class Footage : Item {
        public string path = "";
        public FootageKind kind = FootageKind.VIDEO;
        public int width = 0;
        public int height = 0;
        public double fps = 0;
        public double duration = 0;
        public bool has_video = true;
        public bool has_audio = false;
        public bool has_alpha = false;
        public bool premultiplied = false;
        public string color_space = "srgb";
        public string proxy_path = "";
        public bool use_proxy = false;
        public int seq_first = 0;
        public int seq_last = 0;
        public int seq_digits = 4;
        public string seq_prefix = "";
        public string seq_suffix = "";
        public int loop = 1;
        public double fps_override = 0;

        public Footage (string path, FootageKind kind) {
            this.path = path;
            this.kind = kind;
            this.name = Path.get_basename (path);
        }

        public override string kind_id () {
            return "footage";
        }

        public double frame_rate () {
            if (fps_override > 0) return fps_override;
            return fps > 0 ? fps : 30;
        }

        public string sequence_frame_path (int frame) {
            int n = seq_first + frame;
            if (seq_last > seq_first) n = n.clamp (seq_first, seq_last);
            var digits = "%0" + seq_digits.to_string () + "d";
            return seq_prefix + digits.printf (n) + seq_suffix;
        }

        public string effective_path () {
            return use_proxy && proxy_path != "" ? proxy_path : path;
        }
    }

    public class Marker {
        public double time;
        public double duration;
        public string comment;

        public Marker (double time, string comment = "", double duration = 0) {
            this.time = time;
            this.comment = comment;
            this.duration = duration;
        }
    }

    public class EssentialProperty {
        public string layer_id;
        public string path;
        public string label;

        public EssentialProperty (string layer_id, string path, string label) {
            this.layer_id = layer_id;
            this.path = path;
            this.label = label;
        }
    }

    public class Composition : Item {
        public int width = 1920;
        public int height = 1080;
        public double pixel_aspect = 1;
        public double fps = 30;
        public double duration = 10;
        public double start_timecode = 0;
        public double[] background = { 0, 0, 0, 1 };
        public Gee.ArrayList<Layer> layers = new Gee.ArrayList<Layer> ();
        public double work_start = 0;
        public double work_end = -1;
        public double shutter_angle = 180;
        public double shutter_phase = -90;
        public int motion_blur_samples = 16;
        public bool motion_blur_enabled = true;
        public bool hide_shy = false;
        public bool frame_blending = false;
        public Gee.ArrayList<Marker> markers = new Gee.ArrayList<Marker> ();
        public Gee.ArrayList<EssentialProperty> essential = new Gee.ArrayList<EssentialProperty> ();
        public unowned Project? project = null;
        public int revision = 0;

        public signal void changed (Layer? layer);

        public Composition (string name, int width = 1920, int height = 1080, double fps = 30, double duration = 10) {
            this.name = name;
            this.width = width;
            this.height = height;
            this.fps = fps;
            this.duration = duration;
        }

        public override string kind_id () {
            return "composition";
        }

        public double work_area_end () {
            return work_end < 0 ? duration : double.min (work_end, duration);
        }

        public int frame_count () {
            return int.max (1, (int) Math.round (duration * fps));
        }

        public double frame_time (int frame) {
            return frame / fps;
        }

        public int time_frame (double t) {
            return (int) Math.floor (t * fps + 1e-6);
        }

        public void layer_changed (Layer? layer) {
            revision++;
            changed (layer);
            if (project != null) project.comp_changed (this, layer);
        }

        public Layer? layer_by_id (string id) {
            foreach (var l in layers) if (l.id == id) return l;
            return null;
        }

        public Layer? layer_by_name (string name) {
            foreach (var l in layers) if (l.name == name) return l;
            return null;
        }

        public int index_of (Layer l) {
            return layers.index_of (l);
        }

        public void add_layer (Layer l, int index = 0) {
            l.comp = this;
            layers.insert (index.clamp (0, layers.size), l);
            layer_changed (l);
        }

        public void remove_layer (Layer l) {
            layers.remove (l);
            foreach (var o in layers) {
                if (o.parent_id == l.id) o.parent_id = "";
                if (o.matte_id == l.id) {
                    o.matte_id = "";
                    o.matte_mode = MatteMode.NONE;
                }
            }
            layer_changed (null);
        }

        public void move_layer (Layer l, int index) {
            layers.remove (l);
            layers.insert (index.clamp (0, layers.size), l);
            layer_changed (l);
        }

        public Layer? active_camera (double t) {
            foreach (var l in layers) if (l.kind == LayerKind.CAMERA && l.video && l.active_at (t)) return l;
            return null;
        }

        public bool any_solo () {
            foreach (var l in layers) if (l.solo) return true;
            return false;
        }

        public bool layer_visible (Layer l, double t) {
            if (!l.video || !l.active_at (t)) return false;
            if (l.guide) return false;
            if (any_solo () && !l.solo && l.kind.is_visual () && !l.adjustment) return false;
            return true;
        }

        public string unique_layer_name (string base_name) {
            if (layer_by_name (base_name) == null) return base_name;
            int n = 2;
            while (layer_by_name ("%s %d".printf (base_name, n)) != null) n++;
            return "%s %d".printf (base_name, n);
        }

        public Gee.ArrayList<Layer> children_of (Layer parent) {
            var r = new Gee.ArrayList<Layer> ();
            foreach (var l in layers) if (l.parent_id == parent.id) r.add (l);
            return r;
        }

        public bool would_cycle (Layer child, Layer? parent) {
            var p = parent;
            int guard = 0;
            while (p != null && guard++ < 64) {
                if (p == child) return true;
                p = p.parent_layer ();
            }
            return false;
        }
    }

    public class OutputModule {
        public string format = "png-sequence";
        public string path = "";
        public bool alpha = false;
        public int bit_depth = 8;
        public int quality = 85;
        public int bitrate_kbps = 0;
        public bool include_audio = true;
        public string audio_format = "";
        public int width = 0;
        public int height = 0;
        public string color_space = "";

        public OutputModule copy () {
            var o = new OutputModule ();
            o.format = format;
            o.path = path;
            o.alpha = alpha;
            o.bit_depth = bit_depth;
            o.quality = quality;
            o.bitrate_kbps = bitrate_kbps;
            o.include_audio = include_audio;
            o.audio_format = audio_format;
            o.width = width;
            o.height = height;
            o.color_space = color_space;
            return o;
        }
    }

    public enum RenderStatus {
        QUEUED,
        RENDERING,
        DONE,
        FAILED,
        STOPPED,
        UNQUEUED;

        public string to_id () {
            switch (this) {
                case RENDERING: return "rendering";
                case DONE: return "done";
                case FAILED: return "failed";
                case STOPPED: return "stopped";
                case UNQUEUED: return "unqueued";
                default: return "queued";
            }
        }

        public static RenderStatus from_id (string? s) {
            switch (s) {
                case "rendering": return RENDERING;
                case "done": return DONE;
                case "failed": return FAILED;
                case "stopped": return STOPPED;
                case "unqueued": return UNQUEUED;
                default: return QUEUED;
            }
        }
    }

    public class RenderItem {
        public string id = Layer.new_id ();
        public string comp_id;
        public RenderStatus status = RenderStatus.QUEUED;
        public Gee.ArrayList<OutputModule> outputs = new Gee.ArrayList<OutputModule> ();
        public double start = 0;
        public double end = -1;
        public int resolution = 1;
        public bool motion_blur = true;
        public string error = "";
        public double progress = 0;

        public RenderItem (string comp_id) {
            this.comp_id = comp_id;
        }
    }

    public class Project : Object {
        public Gee.ArrayList<Item> items = new Gee.ArrayList<Item> ();
        public Gee.ArrayList<RenderItem> render_queue = new Gee.ArrayList<RenderItem> ();
        public int bit_depth = 32;
        public string working_space = "linear-srgb";
        public string display_space = "srgb";
        public string ocio_config = "";
        public bool linear_blending = true;
        public string path = "";
        public string base_dir = "";
        public bool modified = false;
        public int expression_engine_version = 1;

        public signal void changed (Composition? comp, Layer? layer);
        public signal void structure_changed ();

        public void comp_changed (Composition c, Layer? l) {
            modified = true;
            changed (c, l);
        }

        public void add_item (Item item) {
            items.add (item);
            var c = item as Composition;
            if (c != null) c.project = this;
            modified = true;
            structure_changed ();
        }

        public void remove_item (Item item) {
            items.remove (item);
            if (item is Folder) {
                var children = new Gee.ArrayList<Item> ();
                foreach (var i in items) if (i.folder_id == item.id) children.add (i);
                foreach (var i in children) remove_item (i);
            }
            modified = true;
            structure_changed ();
        }

        public Item? item_by_id (string id) {
            foreach (var i in items) if (i.id == id) return i;
            return null;
        }

        public Composition? comp_by_id (string id) {
            return item_by_id (id) as Composition;
        }

        public Composition? comp_by_name (string name) {
            foreach (var i in items) if (i is Composition && i.name == name) return (Composition) i;
            return null;
        }

        public Footage? footage_by_id (string id) {
            return item_by_id (id) as Footage;
        }

        public Gee.ArrayList<Composition> compositions () {
            var r = new Gee.ArrayList<Composition> ();
            foreach (var i in items) if (i is Composition) r.add ((Composition) i);
            return r;
        }

        public Gee.ArrayList<Item> children_of (string folder_id) {
            var r = new Gee.ArrayList<Item> ();
            foreach (var i in items) if (i.folder_id == folder_id) r.add (i);
            return r;
        }

        public Gee.ArrayList<Item> search (string query) {
            var r = new Gee.ArrayList<Item> ();
            var q = query.down ().strip ();
            foreach (var i in items) {
                if (q == "" || i.name.down ().contains (q) || i.comment.down ().contains (q)) r.add (i);
                else {
                    var f = i as Footage;
                    if (f != null && f.path.down ().contains (q)) r.add (i);
                }
            }
            return r;
        }

        public Gee.ArrayList<Composition> comps_using (string item_id) {
            var r = new Gee.ArrayList<Composition> ();
            foreach (var c in compositions ())
                foreach (var l in c.layers)
                    if (l.source_id == item_id) {
                        r.add (c);
                        break;
                    }
            return r;
        }

        public bool precomp_cycle (Composition host, Composition nested) {
            if (host == nested) return true;
            foreach (var l in nested.layers) {
                if (l.kind != LayerKind.PRECOMP) continue;
                var c = comp_by_id (l.source_id);
                if (c != null && precomp_cycle (host, c)) return true;
            }
            return false;
        }

        public string resolve_path (string p) {
            if (p == "" || Path.is_absolute (p) || base_dir == "") return p;
            return Path.build_filename (base_dir, p);
        }
    }
}
