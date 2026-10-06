using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    public class AudioClip {
        public float[] samples = {};
        public int rate = 48000;
        public int channels = 2;

        public double duration () {
            return samples.length / (double) (rate * channels);
        }

        public float[] peaks (int buckets) {
            var r = new float[buckets * 2];
            int frames = samples.length / channels;
            if (frames == 0 || buckets == 0) return r;
            for (int b = 0; b < buckets; b++) {
                int s0 = (int) ((int64) b * frames / buckets), s1 = (int) ((int64) (b + 1) * frames / buckets);
                float mn = 0, mx = 0;
                for (int i = s0; i < s1; i++) {
                    float v = samples[i * channels];
                    if (channels > 1) v = (v + samples[i * channels + 1]) / 2;
                    mn = float.min (mn, v);
                    mx = float.max (mx, v);
                }
                r[b * 2] = mn;
                r[b * 2 + 1] = mx;
            }
            return r;
        }
    }

    public class VideoDecoder {
        public string path;
        private Gst.Pipeline? pipeline;
        private Gst.App.Sink? sink;
        public int width;
        public int height;
        public double fps = 30;
        public double duration;
        private Gee.HashMap<int, FloatImage> frames = new Gee.HashMap<int, FloatImage> ();
        private Gee.ArrayList<int> order = new Gee.ArrayList<int> ();
        public Mutex mutex = Mutex ();
        public int capacity = 48;
        public string input_space = "srgb";
        public string working_space = "linear-srgb";

        public VideoDecoder (string path) throws Error {
            this.path = path;
            var desc = "videoconvert name=conv ! videoscale ! video/x-raw,format=RGBA ! appsink name=sink sync=false max-buffers=2";
            pipeline = Gst.parse_launch (desc) as Gst.Pipeline;
            if (pipeline == null) throw new IOError.FAILED ("Video decoding is not available");
            var dec = Gst.ElementFactory.make ("uridecodebin", "src");
            if (dec == null) throw new IOError.FAILED ("Video decoding is not available");
            dec.set ("uri", File.new_for_path (path).get_uri ());
            pipeline.add (dec);
            var conv = pipeline.get_by_name ("conv");
            var pl = pipeline;
            dec.pad_added.connect ((pad) => {
                var caps = pad.get_current_caps () ?? pad.query_caps (null);
                string name = caps != null ? caps.to_string () : "";
                var target = conv.get_static_pad ("sink");
                if (!name.contains ("audio/") && !target.is_linked ()) {
                    pad.link (target);
                    return;
                }
                var fake = Gst.ElementFactory.make ("fakesink", null);
                fake.set ("sync", false);
                pl.add (fake);
                fake.sync_state_with_parent ();
                pad.link (fake.get_static_pad ("sink"));
            });
            sink = pipeline.get_by_name ("sink") as Gst.App.Sink;
            pipeline.set_state (Gst.State.PAUSED);
            Gst.State state;
            var ret = pipeline.get_state (out state, null, 10 * Gst.SECOND);
            if (ret == Gst.StateChangeReturn.FAILURE) throw new IOError.FAILED ("Cannot decode %s", path);
            int64 dur;
            if (pipeline.query_duration (Gst.Format.TIME, out dur)) duration = dur / (double) Gst.SECOND;
            var sample = sink.pull_preroll ();
            if (sample != null) read_caps (sample.get_caps ());
        }

        private void read_caps (Gst.Caps? caps) {
            if (caps == null) return;
            unowned Gst.Structure st = caps.get_structure (0);
            st.get_int ("width", out width);
            st.get_int ("height", out height);
            int n, d;
            if (st.get_fraction ("framerate", out n, out d) && d > 0 && n > 0) fps = n / (double) d;
        }

        public FloatImage? frame_at (double t) {
            mutex.lock ();
            int idx = (int) Math.floor (t * fps + 1e-6);
            if (duration > 0) idx = idx.clamp (0, int.max (0, (int) Math.ceil (duration * fps) - 1));
            FloatImage? r = frames[idx];
            if (r == null) {
                r = decode (idx);
                if (r != null) {
                    frames[idx] = r;
                    order.add (idx);
                    while (order.size > capacity) {
                        frames.unset (order[0]);
                        order.remove_at (0);
                    }
                }
            }
            mutex.unlock ();
            return r;
        }

        private FloatImage? decode (int idx) {
            if (pipeline == null) return null;
            double t = (idx + 0.01) / fps;
            pipeline.seek_simple (Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.ACCURATE, (int64) (t * Gst.SECOND));
            Gst.State state;
            pipeline.get_state (out state, null, 10 * Gst.SECOND);
            var sample = sink.pull_preroll ();
            if (sample == null) return null;
            read_caps (sample.get_caps ());
            var buffer = sample.get_buffer ();
            Gst.MapInfo info;
            if (!buffer.map (out info, Gst.MapFlags.READ)) return null;
            int stride = (int) (info.size / int.max (1, height));
            if (stride < width * 4) stride = width * 4;
            bool plain = input_space == "srgb" || input_space == "";
            var img = FloatImage.from_rgba8 (info.data, width, height, stride, true, plain);
            buffer.unmap (info);
            if (!plain) ColorManagement.convert (img, input_space, "linear-srgb");
            if (working_space != "linear-srgb" && working_space != "") ColorManagement.convert (img, "linear-srgb", working_space);
            Pixels.premultiply (img);
            return img;
        }

        public void close () {
            if (pipeline != null) pipeline.set_state (Gst.State.NULL);
            pipeline = null;
        }
    }

    public class MediaPool : Object {
        private unowned Project project;
        private Gee.HashMap<string, FloatImage> images = new Gee.HashMap<string, FloatImage> ();
        private Gee.HashMap<string, VideoDecoder> videos = new Gee.HashMap<string, VideoDecoder> ();
        private Gee.HashMap<string, AudioClip> audio = new Gee.HashMap<string, AudioClip> ();
        private Gee.ArrayList<string> image_order = new Gee.ArrayList<string> ();
        private Mutex mutex = Mutex ();
        public int image_capacity = 64;
        public string last_error = "";

        public MediaPool (Project project) {
            this.project = project;
        }

        public void set_project (Project p) {
            project = p;
        }

        public FloatImage? frame (Footage f, double t) {
            switch (f.kind) {
                case FootageKind.IMAGE:
                    return image (f.effective_path (), f);
                case FootageKind.SEQUENCE:
                    int n = (int) Math.floor (t * f.frame_rate () + 1e-6);
                    int count = f.seq_last - f.seq_first + 1;
                    if (count > 0 && f.loop > 1) n = n % count;
                    return image (f.sequence_frame_path (n), f);
                case FootageKind.VIDEO:
                    var dec = video (f);
                    if (dec == null) return null;
                    double tt = t;
                    if (f.loop > 1 && dec.duration > 0) tt = tt % dec.duration;
                    if (f.fps_override > 0 && dec.fps > 0) tt = tt * f.fps_override / dec.fps;
                    return dec.frame_at (tt);
                default:
                    return null;
            }
        }

        public FloatImage? blended_frame (Footage f, double t, double comp_fps) {
            var dec = video (f);
            if (dec == null) return frame (f, t);
            double pos = t * dec.fps;
            int i0 = (int) Math.floor (pos);
            double frac = pos - i0;
            var a = dec.frame_at (i0 / dec.fps);
            if (frac < 0.01 || a == null) return a;
            var b = dec.frame_at ((i0 + 1) / dec.fps);
            if (b == null || b.width != a.width || b.height != a.height) return a;
            var r = a.copy ();
            Pixels.mix_into (r, b, (float) frac);
            return r;
        }

        private string working () {
            return project != null ? project.working_space : "linear-srgb";
        }

        private VideoDecoder? video (Footage f) {
            var path = f.effective_path ();
            var key = path + "|" + f.color_space + "|" + working ();
            mutex.lock ();
            var dec = videos[key];
            if (dec == null) {
                try {
                    dec = new VideoDecoder (path);
                    dec.input_space = f.color_space;
                    dec.working_space = working ();
                    videos[key] = dec;
                } catch (Error e) {
                    last_error = e.message;
                }
            }
            mutex.unlock ();
            return dec;
        }

        public FloatImage? image (string path, Footage? f = null) {
            string space = f != null ? f.color_space : "srgb";
            var key = path + "|" + space + "|" + working ();
            mutex.lock ();
            var img = images[key];
            mutex.unlock ();
            if (img != null) return img;
            try {
                img = ImageIO.load (path, space);
                if (working () != "linear-srgb" && working () != "") ColorManagement.convert (img, "linear-srgb", working ());
            } catch (Error e) {
                last_error = e.message;
                return null;
            }
            if (f != null && f.premultiplied) {
                var straight = img;
                Pixels.unpremultiply (straight);
                img = straight;
            }
            Pixels.premultiply (img);
            mutex.lock ();
            images[key] = img;
            image_order.add (key);
            while (image_order.size > image_capacity) {
                images.unset (image_order[0]);
                image_order.remove_at (0);
            }
            mutex.unlock ();
            return img;
        }

        public AudioClip? audio_of (Footage f) {
            var path = f.effective_path ();
            mutex.lock ();
            var clip = audio[path];
            mutex.unlock ();
            if (clip != null) return clip;
            clip = decode_audio (path);
            if (clip == null) return null;
            mutex.lock ();
            audio[path] = clip;
            mutex.unlock ();
            return clip;
        }

        public static AudioClip? decode_audio (string path, int rate = 48000) {
            try {
                var pipeline = Gst.parse_launch ("filesrc name=src ! decodebin ! audioconvert ! audioresample ! audio/x-raw,format=F32LE,channels=2,rate=%d,layout=interleaved ! appsink name=sink sync=false".printf (rate)) as Gst.Pipeline;
                pipeline.get_by_name ("src").set ("location", path);
                var sink = pipeline.get_by_name ("sink") as Gst.App.Sink;
                pipeline.set_state (Gst.State.PLAYING);
                var data = new Gee.ArrayList<float?> ();
                var clip = new AudioClip ();
                clip.rate = rate;
                var arr = new GLib.Array<float> ();
                while (true) {
                    var sample = sink.try_pull_sample (5 * Gst.SECOND);
                    if (sample == null) break;
                    var buffer = sample.get_buffer ();
                    Gst.MapInfo info;
                    if (buffer.map (out info, Gst.MapFlags.READ)) {
                        unowned float[] fl = (float[]) info.data;
                        int n = (int) (info.size / sizeof (float));
                        for (int i = 0; i < n; i++) arr.append_val (fl[i]);
                        buffer.unmap (info);
                    }
                    if (sink.is_eos ()) break;
                }
                pipeline.set_state (Gst.State.NULL);
                data.clear ();
                var samples = new float[arr.length];
                for (uint i = 0; i < arr.length; i++) samples[i] = arr.index (i);
                clip.samples = samples;
                return clip.samples.length > 0 ? clip : null;
            } catch (Error e) {
                return null;
            }
        }

        public void forget (string path) {
            mutex.lock ();
            var dead = new Gee.ArrayList<string> ();
            foreach (var k in images.keys) if (k.has_prefix (path + "|")) dead.add (k);
            foreach (var k in dead) images.unset (k);
            dead.clear ();
            foreach (var k in videos.keys) if (k.has_prefix (path + "|")) dead.add (k);
            foreach (var k in dead) {
                videos[k].close ();
                videos.unset (k);
            }
            audio.unset (path);
            mutex.unlock ();
        }

        public void close () {
            mutex.lock ();
            foreach (var d in videos.values) d.close ();
            videos.clear ();
            images.clear ();
            mutex.unlock ();
        }

        public static string[] image_extensions () {
            return { "png", "jpg", "jpeg", "tif", "tiff", "webp", "exr", "bmp", "gif", "tga" };
        }

        public static string[] video_extensions () {
            return { "mp4", "mov", "mkv", "webm", "avi", "m4v", "mxf", "ogv", "mts", "m2ts" };
        }

        public static string[] audio_extensions () {
            return { "wav", "flac", "mp3", "ogg", "opus", "m4a", "aac", "aif", "aiff" };
        }

        private static bool has_ext (string path, string[] exts) {
            var lower = path.down ();
            foreach (var e in exts) if (lower.has_suffix ("." + e)) return true;
            return false;
        }

        public static Footage probe (string path) throws Error {
            if (has_ext (path, { "gltf", "glb" })) {
                var f = new Footage (path, FootageKind.MODEL);
                f.duration = 0;
                return f;
            }
            if (has_ext (path, { "svg" })) return new Footage (path, FootageKind.VECTOR);
            if (has_ext (path, image_extensions ())) {
                var seq = detect_sequence (path);
                if (seq != null) return seq;
                var img = ImageIO.load (path, "srgb");
                var f = new Footage (path, FootageKind.IMAGE);
                f.width = img.width;
                f.height = img.height;
                f.has_alpha = !img.is_opaque ();
                return f;
            }
            var discoverer = new Gst.PbUtils.Discoverer (15 * Gst.SECOND);
            var info = discoverer.discover_uri (File.new_for_path (path).get_uri ());
            var f = new Footage (path, FootageKind.VIDEO);
            f.duration = info.get_duration () / (double) Gst.SECOND;
            var vstreams = info.get_video_streams ();
            var astreams = info.get_audio_streams ();
            f.has_audio = astreams.length () > 0;
            f.has_video = vstreams.length () > 0;
            if (vstreams.length () > 0) {
                var v = (Gst.PbUtils.DiscovererVideoInfo) vstreams.data;
                f.width = (int) v.get_width ();
                f.height = (int) v.get_height ();
                if (v.get_framerate_denom () > 0) f.fps = v.get_framerate_num () / (double) v.get_framerate_denom ();
                f.has_alpha = false;
            } else {
                f.kind = FootageKind.AUDIO;
            }
            return f;
        }

        public static Footage? detect_sequence (string path) {
            var name = Path.get_basename (path);
            var dir = Path.get_dirname (path);
            int dot = name.last_index_of (".");
            if (dot < 0) return null;
            var stem = name.substring (0, dot);
            var ext = name.substring (dot);
            int end = stem.length;
            int start = end;
            while (start > 0 && stem[start - 1].isdigit ()) start--;
            if (start == end) return null;
            var prefix = stem.substring (0, start);
            int digits = end - start;
            int first = int.MAX, last = -1, count = 0;
            try {
                var d = Dir.open (dir);
                string? entry;
                while ((entry = d.read_name ()) != null) {
                    if (!entry.has_prefix (prefix) || !entry.has_suffix (ext)) continue;
                    var mid = entry.substring (prefix.length, entry.length - prefix.length - ext.length);
                    if (mid.length != digits) continue;
                    bool numeric = true;
                    for (int i = 0; i < mid.length; i++) if (!mid[i].isdigit ()) numeric = false;
                    if (!numeric) continue;
                    int n = int.parse (mid);
                    first = int.min (first, n);
                    last = int.max (last, n);
                    count++;
                }
            } catch (Error e) {
                return null;
            }
            if (count < 2) return null;
            var f = new Footage (path, FootageKind.SEQUENCE);
            f.seq_prefix = Path.build_filename (dir, prefix);
            f.seq_suffix = ext;
            f.seq_digits = digits;
            f.seq_first = first;
            f.seq_last = last;
            f.fps = 30;
            f.duration = count / 30.0;
            f.name = prefix + "[" + string.nfill (digits, '#') + "]" + ext;
            try {
                var img = ImageIO.load (f.sequence_frame_path (0), "srgb");
                f.width = img.width;
                f.height = img.height;
                f.has_alpha = !img.is_opaque ();
            } catch (Error e) {
            }
            return f;
        }
    }
}
