using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    public class FrameCache : Object {
        private class Entry {
            public string comp_id;
            public int frame;
            public string settings;
            public double time;
            public FloatImage image;
            public size_t bytes;
            public uint64 stamp;
        }

        private Gee.HashMap<string, Entry> entries = new Gee.HashMap<string, Entry> ();
        private size_t total = 0;
        private uint64 clock = 0;
        private Mutex mutex = Mutex ();
        public size_t budget;
        public int hits = 0;
        public int misses = 0;
        public int invalidations = 0;

        public signal void changed ();

        public FrameCache (int megabytes) {
            budget = (size_t) megabytes * 1024 * 1024;
        }

        public void set_budget_mb (int mb) {
            mutex.lock ();
            budget = (size_t) int.max (16, mb) * 1024 * 1024;
            evict ();
            mutex.unlock ();
        }

        private static string key (string comp_id, int frame, string settings) {
            return "%s|%d|%s".printf (comp_id, frame, settings);
        }

        public FloatImage? lookup (string comp_id, int frame, string settings) {
            mutex.lock ();
            var e = entries[key (comp_id, frame, settings)];
            FloatImage? r = null;
            if (e != null) {
                e.stamp = ++clock;
                r = e.image;
                hits++;
            } else {
                misses++;
            }
            mutex.unlock ();
            return r;
        }

        public bool contains (string comp_id, int frame, string settings) {
            mutex.lock ();
            bool r = entries.has_key (key (comp_id, frame, settings));
            mutex.unlock ();
            return r;
        }

        public void store (string comp_id, int frame, string settings, FloatImage image, double time) {
            var e = new Entry ();
            e.comp_id = comp_id;
            e.frame = frame;
            e.settings = settings;
            e.time = time;
            e.image = image;
            e.bytes = image.pixel_count () * 16;
            mutex.lock ();
            e.stamp = ++clock;
            var k = key (comp_id, frame, settings);
            var old = entries[k];
            if (old != null) total -= old.bytes;
            entries[k] = e;
            total += e.bytes;
            evict ();
            mutex.unlock ();
            changed ();
        }

        private void evict () {
            while (total > budget && entries.size > 0) {
                string? oldest = null;
                uint64 best = uint64.MAX;
                foreach (var kv in entries.entries) {
                    if (kv.value.stamp < best) {
                        best = kv.value.stamp;
                        oldest = kv.key;
                    }
                }
                if (oldest == null) break;
                total -= entries[oldest].bytes;
                entries.unset (oldest);
            }
        }

        public void clear () {
            mutex.lock ();
            entries.clear ();
            total = 0;
            mutex.unlock ();
            changed ();
        }

        public void invalidate_range (string comp_id, double t0, double t1) {
            mutex.lock ();
            var drop = new Gee.ArrayList<string> ();
            foreach (var kv in entries.entries) {
                var e = kv.value;
                if (e.comp_id == comp_id && e.time >= t0 - 1e-6 && e.time <= t1 + 1e-6) drop.add (kv.key);
            }
            foreach (var k in drop) {
                total -= entries[k].bytes;
                entries.unset (k);
            }
            invalidations += drop.size;
            mutex.unlock ();
        }

        public void invalidate (Project project, Composition comp, Layer? layer) {
            double t0 = 0, t1 = comp.duration;
            if (layer != null && layer.comp == comp && !layer_is_global (layer)) {
                double margin = 1.0 / comp.fps;
                t0 = double.min (layer.in_point, layer.out_point) - margin;
                t1 = double.max (layer.in_point, layer.out_point) + margin;
            }
            invalidate_comp_range (project, comp, t0, t1, 0);
            changed ();
        }

        private void invalidate_comp_range (Project project, Composition comp, double t0, double t1, int depth) {
            invalidate_range (comp.id, t0, t1);
            if (depth > 12) return;
            foreach (var parent in project.compositions ()) {
                foreach (var l in parent.layers) {
                    if (l.kind != LayerKind.PRECOMP || l.source_id != comp.id) continue;
                    double a = l.comp_time (t0), b = l.comp_time (t1);
                    if (l.time_remap) {
                        a = 0;
                        b = parent.duration;
                    }
                    invalidate_comp_range (project, parent, double.min (a, b), double.max (a, b), depth + 1);
                }
            }
        }

        private bool layer_is_global (Layer l) {
            if (l.comp == null) return true;
            foreach (var o in l.comp.layers) {
                if (o == l) continue;
                if (o.parent_id == l.id || o.matte_id == l.id) return true;
                if (o.kind == LayerKind.CAMERA || l.kind == LayerKind.CAMERA || l.kind == LayerKind.LIGHT) return true;
            }
            foreach (var p in l.all_props ()) if (p.has_expression ()) return true;
            return false;
        }

        public Gee.HashSet<int> cached_frames (string comp_id, string settings) {
            var r = new Gee.HashSet<int> ();
            mutex.lock ();
            foreach (var e in entries.values) if (e.comp_id == comp_id && e.settings == settings) r.add (e.frame);
            mutex.unlock ();
            return r;
        }

        public size_t used_bytes () {
            return total;
        }

        public int count () {
            return entries.size;
        }
    }
}
