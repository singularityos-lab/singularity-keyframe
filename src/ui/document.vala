using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    public class RenderRequest {
        public string comp_id;
        public double time;
        public RenderSettings settings;
        public uint serial;
    }

    public class RenderService : Object {
        private unowned Project live;
        private Project? copy = null;
        private int copy_revision = -1;
        public Renderer renderer;
        private Mutex mutex = Mutex ();
        private Cond cond = Cond ();
        private RenderRequest? pending = null;
        private Gee.ArrayList<RenderRequest> prefetch = new Gee.ArrayList<RenderRequest> ();
        private bool running = true;
        private Thread<bool>? thread = null;
        private string snapshot_text = "";
        private int revision = 0;
        private uint serial = 0;
        public double last_ms = 0;

        public signal void frame_ready (RenderRequest req, FloatImage img);
        public signal void prefetch_progress (string comp_id, int frame);

        public RenderService (Project live) {
            this.live = live;
            renderer = new Renderer (new Project ());
            live.changed.connect ((c, l) => {
                revision++;
                if (c != null) renderer.cache.invalidate (live, c, l);
            });
            live.structure_changed.connect (() => {
                revision++;
                renderer.cache.clear ();
            });
            thread = new Thread<bool> ("keyframe-render", loop);
        }

        public void touch () {
            revision++;
        }

        public void stop () {
            mutex.lock ();
            running = false;
            cond.signal ();
            mutex.unlock ();
            if (thread != null) thread.join ();
            thread = null;
        }

        private void refresh_copy () {
            if (copy != null && copy_revision == revision) return;
            snapshot_text = NativeFormat.snapshot (live);
            copy_revision = revision;
        }

        public uint request (string comp_id, double time, RenderSettings settings) {
            mutex.lock ();
            refresh_copy ();
            var r = new RenderRequest ();
            r.comp_id = comp_id;
            r.time = time;
            r.settings = settings.copy ();
            r.serial = ++serial;
            pending = r;
            cond.signal ();
            mutex.unlock ();
            return r.serial;
        }

        public void start_prefetch (string comp_id, Gee.List<double?> times, RenderSettings settings) {
            mutex.lock ();
            refresh_copy ();
            prefetch.clear ();
            foreach (var t in times) {
                var r = new RenderRequest ();
                r.comp_id = comp_id;
                r.time = t;
                r.settings = settings.copy ();
                r.serial = 0;
                prefetch.add (r);
            }
            cond.signal ();
            mutex.unlock ();
        }

        public void stop_prefetch () {
            mutex.lock ();
            prefetch.clear ();
            mutex.unlock ();
        }

        private bool loop () {
            int seen_revision = -2;
            Project? local = null;
            while (true) {
                mutex.lock ();
                while (running && pending == null && prefetch.size == 0) cond.wait (mutex);
                if (!running) {
                    mutex.unlock ();
                    break;
                }
                RenderRequest req;
                bool is_prefetch = false;
                if (pending != null) {
                    req = pending;
                    pending = null;
                } else {
                    req = prefetch.remove_at (0);
                    is_prefetch = true;
                }
                string text = snapshot_text;
                int rev = copy_revision;
                mutex.unlock ();
                if (local == null || rev != seen_revision) {
                    try {
                        local = NativeFormat.restore (text, live.base_dir);
                        local.base_dir = live.base_dir;
                        local.bit_depth = live.bit_depth;
                        renderer.project = local;
                        renderer.media.set_project (local);
                        seen_revision = rev;
                    } catch (Error e) {
                        continue;
                    }
                }
                var comp = local.comp_by_id (req.comp_id);
                if (comp == null) continue;
                if (is_prefetch && renderer.cache.contains (comp.id, (int) Math.round (req.time * comp.fps), req.settings.key ())) {
                    prefetch_progress (comp.id, (int) Math.round (req.time * comp.fps));
                    continue;
                }
                var timer = new Timer ();
                var img = renderer.render (comp, req.time, req.settings);
                last_ms = timer.elapsed () * 1000;
                if (is_prefetch) {
                    var cid = comp.id;
                    int f = (int) Math.round (req.time * comp.fps);
                    Idle.add (() => {
                        prefetch_progress (cid, f);
                        return false;
                    });
                } else {
                    var result = img;
                    Idle.add (() => {
                        frame_ready (req, result);
                        return false;
                    });
                }
            }
            return true;
        }
    }

    public class Document : Object {
        public Project project { get; private set; }
        public Composition? comp { get; private set; }
        public double time { get; private set; default = 0; }
        public Gee.ArrayList<Layer> selection = new Gee.ArrayList<Layer> ();
        public Property? active_property = null;
        public Gee.ArrayList<Keyframe> selected_keys = new Gee.ArrayList<Keyframe> ();
        public Gee.HashMap<Keyframe, Property> key_owner = new Gee.HashMap<Keyframe, Property> ();
        public RenderService service;
        private Gee.ArrayList<string> undo_stack = new Gee.ArrayList<string> ();
        private Gee.ArrayList<string> redo_stack = new Gee.ArrayList<string> ();
        private string? pending_snapshot = null;
        public string last_action = "";
        public bool playing { get; private set; default = false; }
        private uint play_timer = 0;
        private int64 play_start_us = 0;
        private double play_start_time = 0;
        public bool loop_playback = true;

        public signal void comp_switched ();
        public signal void time_changed ();
        public signal void selection_changed ();
        public signal void content_changed ();
        public signal void structure_changed ();
        public signal void history_changed ();
        public signal void playback_changed ();
        public signal void service_changed ();

        public Document (Project project) {
            bind_project (project);
        }

        private void bind_project (Project p) {
            project = p;
            if (service != null) service.stop ();
            service = new RenderService (p);
            p.changed.connect ((c, l) => content_changed ());
            p.structure_changed.connect (() => structure_changed ());
            service_changed ();
        }

        public void close () {
            stop ();
            service.stop ();
            service.renderer.media.close ();
        }

        public void open_comp (Composition? c) {
            comp = c;
            selection.clear ();
            selected_keys.clear ();
            active_property = null;
            if (c != null) time = time.clamp (0, double.max (0, c.duration - 1.0 / c.fps));
            comp_switched ();
            selection_changed ();
            time_changed ();
        }

        public void seek (double t) {
            if (comp == null) return;
            double frame = Math.round (t * comp.fps);
            double nt = (frame / comp.fps).clamp (0, double.max (0, comp.duration - 1.0 / comp.fps));
            if ((nt - time).abs () < 1e-9) return;
            time = nt;
            time_changed ();
        }

        public void step_frames (int n) {
            if (comp == null) return;
            seek (time + n / comp.fps);
        }

        public int frame () {
            return comp != null ? (int) Math.round (time * comp.fps) : 0;
        }

        public void select_layer (Layer? l, bool extend = false) {
            if (!extend) selection.clear ();
            if (l != null) {
                if (extend && selection.contains (l)) selection.remove (l);
                else if (!selection.contains (l)) selection.add (l);
            }
            selection_changed ();
        }

        public Layer? primary () {
            return selection.size > 0 ? selection[0] : null;
        }

        public void select_key (Property p, Keyframe k, bool extend) {
            if (!extend) {
                selected_keys.clear ();
                key_owner.clear ();
            }
            if (!selected_keys.contains (k)) {
                selected_keys.add (k);
                key_owner[k] = p;
            } else if (extend) {
                selected_keys.remove (k);
                key_owner.unset (k);
            }
            active_property = p;
            selection_changed ();
        }

        public void clear_keys () {
            selected_keys.clear ();
            key_owner.clear ();
            selection_changed ();
        }

        public void begin_edit (string label = "") {
            if (pending_snapshot != null) return;
            pending_snapshot = NativeFormat.snapshot (project);
            last_action = label;
        }

        public void end_edit () {
            if (pending_snapshot == null) return;
            var now = NativeFormat.snapshot (project);
            if (now != pending_snapshot) {
                undo_stack.add (pending_snapshot);
                if (undo_stack.size > 200) undo_stack.remove_at (0);
                redo_stack.clear ();
                project.modified = true;
            }
            pending_snapshot = null;
            service.touch ();
            history_changed ();
        }

        public void edit (string label, owned Callback action) {
            begin_edit (label);
            action ();
            end_edit ();
            content_changed ();
        }

        public delegate void Callback ();

        private string merge_key = "";
        private int64 merge_time = 0;

        public void edit_merged (string key, string label, owned Callback action) {
            int64 now = get_monotonic_time ();
            bool merge = key == merge_key && now - merge_time < 1500000 && undo_stack.size > 0;
            merge_key = key;
            merge_time = now;
            if (merge) {
                action ();
                project.modified = true;
                service.touch ();
                content_changed ();
                history_changed ();
                return;
            }
            edit (label, (owned) action);
        }

        public bool can_undo () {
            return undo_stack.size > 0;
        }

        public bool can_redo () {
            return redo_stack.size > 0;
        }

        public void undo () {
            if (undo_stack.size == 0) return;
            var current = NativeFormat.snapshot (project);
            var prev = undo_stack.remove_at (undo_stack.size - 1);
            redo_stack.add (current);
            restore (prev);
        }

        public void redo () {
            if (redo_stack.size == 0) return;
            var current = NativeFormat.snapshot (project);
            var next = redo_stack.remove_at (redo_stack.size - 1);
            undo_stack.add (current);
            restore (next);
        }

        private void restore (string snap) {
            string? comp_id = comp != null ? comp.id : null;
            var sel_ids = new Gee.ArrayList<string> ();
            foreach (var l in selection) sel_ids.add (l.id);
            try {
                var p = NativeFormat.restore (snap, project.base_dir);
                p.path = project.path;
                p.base_dir = project.base_dir;
                p.modified = true;
                bind_project (p);
            } catch (Error e) {
                return;
            }
            comp = comp_id != null ? project.comp_by_id (comp_id) : null;
            selection.clear ();
            if (comp != null) foreach (var id in sel_ids) {
                var l = comp.layer_by_id (id);
                if (l != null) selection.add (l);
            }
            selected_keys.clear ();
            key_owner.clear ();
            active_property = null;
            structure_changed ();
            comp_switched ();
            selection_changed ();
            content_changed ();
            history_changed ();
            time_changed ();
        }

        public void replace_project (Project p) {
            undo_stack.clear ();
            redo_stack.clear ();
            bind_project (p);
            open_comp (p.compositions ().size > 0 ? p.compositions ()[0] : null);
            structure_changed ();
            history_changed ();
        }

        public void play () {
            if (comp == null || playing) return;
            playing = true;
            play_start_us = get_monotonic_time ();
            play_start_time = time;
            var times = new Gee.ArrayList<double?> ();
            double end = comp.work_area_end ();
            for (double t = comp.work_start; t < end - 1e-9; t += 1.0 / comp.fps) times.add (t);
            service.start_prefetch (comp.id, times, current_settings ());
            play_timer = Timeout.add ((uint) (1000 / comp.fps), () => {
                if (comp == null) return false;
                double elapsed = (get_monotonic_time () - play_start_us) / 1000000.0;
                double t = play_start_time + elapsed;
                double start = comp.work_start, end_t = comp.work_area_end ();
                if (t >= end_t) {
                    if (!loop_playback) {
                        stop ();
                        return false;
                    }
                    play_start_us = get_monotonic_time ();
                    play_start_time = start;
                    t = start;
                }
                int f = (int) Math.round (t * comp.fps);
                if (!service.renderer.cache.contains (comp.id, f, current_settings ().key ())) {
                    play_start_us = get_monotonic_time ();
                    play_start_time = time;
                    return true;
                }
                seek (t);
                return true;
            });
            playback_changed ();
        }

        public void stop () {
            if (!playing) return;
            playing = false;
            if (play_timer != 0) Source.remove (play_timer);
            play_timer = 0;
            service.stop_prefetch ();
            playback_changed ();
        }

        public void toggle_play () {
            if (playing) stop ();
            else play ();
        }

        public int preview_downsample = 0;
        public bool roi_enabled = false;
        public double roi_x = 0;
        public double roi_y = 0;
        public double roi_w = 0;
        public double roi_h = 0;
        public int auto_downsample = 1;

        public RenderSettings current_settings () {
            var s = new RenderSettings ();
            s.downsample = preview_downsample > 0 ? preview_downsample : auto_downsample;
            s.include_guides = true;
            if (roi_enabled && roi_w > 4 && roi_h > 4) {
                s.roi = true;
                s.roi_x = roi_x;
                s.roi_y = roi_y;
                s.roi_w = roi_w;
                s.roi_h = roi_h;
            }
            return s;
        }
    }
}
