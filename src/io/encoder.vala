using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    public errordomain EncodeError {
        UNAVAILABLE,
        FAILED,
        CANCELLED
    }

    public class OutputFormat : Object {
        public string id;
        public string label;
        public string extension;
        public bool sequence;
        public bool video;
        public bool audio_only;
        public bool alpha;
        public bool audio;
        public int[] depths;
        public bool available = true;
        public string reason = "";
        public string backend = "";

        public OutputFormat (string id, string label, string extension, bool sequence, bool alpha, int[] depths) {
            this.id = id;
            this.label = label;
            this.extension = extension;
            this.sequence = sequence;
            this.alpha = alpha;
            this.depths = depths;
            this.video = !sequence;
        }
    }

    public abstract class FrameSink : Object {
        public string path = "";
        public OutputModule module;
        public AudioClip? audio = null;
        public int width;
        public int height;
        public double fps = 30;
        public Gee.ArrayList<string> written = new Gee.ArrayList<string> ();

        public abstract void begin (int width, int height, double fps) throws Error;
        public abstract void write (FloatImage premul, int index) throws Error;
        public abstract void finish () throws Error;

        public virtual void abort () {
        }
    }

    namespace Encoders {
        private Gee.ArrayList<OutputFormat>? cache = null;

        public bool has_element (string name) {
            var f = Gst.ElementFactory.find (name);
            return f != null;
        }

        public string? ffmpeg_path () {
            var forced = Environment.get_variable ("SINGULARITY_KEYFRAME_FFMPEG");
            if (forced != null && forced != "") return FileUtils.test (forced, FileTest.IS_EXECUTABLE) ? forced : null;
            return Environment.find_program_in_path ("ffmpeg");
        }

        public Gee.List<OutputFormat> formats () {
            if (cache != null) return cache;
            cache = new Gee.ArrayList<OutputFormat> ();
            cache.add (new OutputFormat ("png-sequence", _("PNG Sequence"), "png", true, true, { 8, 16 }));
            cache.add (new OutputFormat ("tiff-sequence", _("TIFF Sequence"), "tif", true, true, { 8, 16, 32 }));
            cache.add (new OutputFormat ("exr-sequence", _("OpenEXR Sequence"), "exr", true, true, { 16, 32 }));
            var jpeg = new OutputFormat ("jpeg-sequence", _("JPEG Sequence"), "jpg", true, false, { 8 });
            if (!ImageIO.pixbuf_can_save ("jpeg")) {
                jpeg.available = false;
                jpeg.reason = _("JPEG saving is not available on this system");
            }
            cache.add (jpeg);
            var webp = new OutputFormat ("webp-sequence", _("WebP Sequence"), "webp", true, true, { 8 });
            if (!ImageIO.pixbuf_can_save ("webp")) {
                webp.available = false;
                webp.reason = _("WebP saving is not available on this system");
            }
            cache.add (webp);
            var gif = new OutputFormat ("gif", _("Animated GIF"), "gif", false, true, { 8 });
            cache.add (gif);
            add_gst (new OutputFormat ("h264-mp4", _("H.264 in MP4"), "mp4", false, false, { 8 }), { "x264enc", "h264parse", "mp4mux" });
            add_gst (new OutputFormat ("hevc-mp4", _("HEVC in MP4"), "mp4", false, false, { 8 }), { "x265enc", "h265parse", "mp4mux" });
            var av1 = new OutputFormat ("av1-mp4", _("AV1 in MP4"), "mp4", false, false, { 8 });
            add_gst (av1, { has_element ("svtav1enc") ? "svtav1enc" : "av1enc", "av1parse", "mp4mux" });
            add_gst (new OutputFormat ("av1-webm", _("AV1 in WebM"), "webm", false, false, { 8 }), { has_element ("svtav1enc") ? "svtav1enc" : "av1enc", "av1parse", "webmmux" });
            add_gst (new OutputFormat ("vp9-webm", _("VP9 in WebM"), "webm", false, true, { 8 }), { "vp9enc", "webmmux" });
            add_gst (new OutputFormat ("png-mov", _("QuickTime PNG (with alpha)"), "mov", false, true, { 8 }), { "pngenc", "qtmux" });
            add_pro (new OutputFormat ("prores-422-mov", _("Apple ProRes 422 HQ"), "mov", false, false, { 10 }), "avenc_prores_ks", "prores_ks");
            add_pro (new OutputFormat ("prores-4444-mov", _("Apple ProRes 4444 (with alpha)"), "mov", false, true, { 10 }), "avenc_prores_ks", "prores_ks");
            add_pro (new OutputFormat ("dnxhr-mov", _("Avid DNxHR HQ"), "mov", false, false, { 8 }), "avenc_dnxhd", "dnxhd");
            var wav = new OutputFormat ("wav", _("WAV Audio"), "wav", false, false, { 16 });
            wav.audio_only = true;
            wav.video = false;
            cache.add (wav);
            var flac = new OutputFormat ("flac", _("FLAC Audio"), "flac", false, false, { 16 });
            flac.audio_only = true;
            flac.video = false;
            add_gst (flac, { "flacenc" });
            var aac = new OutputFormat ("aac", _("AAC Audio (M4A)"), "m4a", false, false, { 16 });
            aac.audio_only = true;
            aac.video = false;
            add_gst (aac, { "voaacenc", "mp4mux" });
            foreach (var f in cache) if (f.video) f.audio = true;
            return cache;
        }

        private void add_gst (OutputFormat f, string[] elements) {
            f.backend = "gstreamer";
            foreach (var e in elements) {
                if (!has_element (e)) {
                    f.available = false;
                    f.reason = _("The GStreamer element “%s” is not available on this system").printf (e);
                    break;
                }
            }
            cache.add (f);
        }

        private void add_pro (OutputFormat f, string gst_element, string ffmpeg_codec) {
            if (has_element (gst_element) && has_element ("qtmux")) {
                f.backend = "gstreamer";
            } else if (ffmpeg_path () != null) {
                f.backend = "ffmpeg";
            } else {
                f.available = false;
                f.reason = _("Not available on this system: install the GStreamer libav plugins or FFmpeg");
            }
            cache.add (f);
        }

        public void reset () {
            cache = null;
        }

        public OutputFormat? find (string id) {
            foreach (var f in formats ()) if (f.id == id) return f;
            return null;
        }

        public string frame_path (string template, int index, string extension) {
            int start = template.index_of ("#");
            if (start >= 0) {
                int end = start;
                while (end < template.length && template[end] == '#') end++;
                var digits = "%0" + (end - start).to_string () + "d";
                return template.substring (0, start) + digits.printf (index) + template.substring (end);
            }
            int dot = template.last_index_of (".");
            int slash = template.last_index_of ("/");
            if (dot > slash) return template.substring (0, dot) + "_%05d".printf (index) + template.substring (dot);
            return template + "_%05d.%s".printf (index, extension);
        }

        public string with_extension (string path, string extension) {
            int dot = path.last_index_of (".");
            int slash = path.last_index_of ("/");
            if (dot > slash) return path;
            return path + "." + extension;
        }

        public void fps_fraction (double fps, out int num, out int den) {
            double[] dens = { 1, 1001, 100, 1000 };
            foreach (var d in dens) {
                double n = fps * d;
                if ((n - Math.round (n)).abs () < 1e-3 * d) {
                    num = (int) Math.round (n);
                    den = (int) d;
                    return;
                }
            }
            num = (int) Math.round (fps * 1000);
            den = 1000;
        }

        public FloatImage resize (FloatImage img, int w, int h) {
            if (w <= 0 || h <= 0 || (w == img.width && h == img.height)) return img;
            return img.resized (w, h);
        }

        public FrameSink create (OutputModule om) throws Error {
            var f = find (om.format);
            if (f == null) throw new EncodeError.UNAVAILABLE (_("Unknown output format “%s”").printf (om.format));
            if (!f.available) throw new EncodeError.UNAVAILABLE (f.reason);
            FrameSink sink;
            if (f.sequence) sink = new SequenceSink (f);
            else if (f.id == "gif") sink = new GifSink ();
            else if (f.audio_only) sink = new AudioSink (f);
            else if (f.id == "vp9-webm" && om.alpha) sink = new WebmAlphaSink ();
            else if (f.backend == "ffmpeg") sink = new FfmpegSink (f);
            else sink = new GstVideoSink (f);
            sink.module = om;
            sink.path = f.sequence ? om.path : with_extension (om.path, f.extension);
            return sink;
        }

        public uint8[] rgba8 (FloatImage premul, bool alpha, int pad_w = 0, int pad_h = 0) {
            var img = Pixels.unpremultiplied (premul);
            int w = pad_w > 0 ? pad_w : img.width, h = pad_h > 0 ? pad_h : img.height;
            var out_px = new uint8[(size_t) w * h * 4];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++) {
                    size_t o = ((size_t) y * w + x) * 4;
                    if (x >= img.width || y >= img.height) {
                        out_px[o + 3] = alpha ? 0 : 255;
                        continue;
                    }
                    size_t i = img.offset (x, y);
                    float a = img.data[i + 3].clamp (0, 1);
                    for (int c = 0; c < 3; c++) {
                        float v = img.data[i + c];
                        if (!alpha) v = v * a;
                        out_px[o + c] = Transfer.encode_byte (v);
                    }
                    out_px[o + 3] = alpha ? (uint8) Math.roundf (a * 255) : 255;
                }
            return out_px;
        }

        public Gst.Buffer buffer_of (owned uint8[] data, int64 pts, int64 duration) {
            var buf = new Gst.Buffer.wrapped ((owned) data);
            buf.pts = pts;
            buf.dts = pts;
            buf.duration = duration;
            return buf;
        }

        public void wait_eos (Gst.Element pipeline, uint64 timeout_s = 600) throws Error {
            var bus = pipeline.get_bus ();
            var msg = bus.timed_pop_filtered (timeout_s * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
            if (msg == null) {
                pipeline.set_state (Gst.State.NULL);
                throw new EncodeError.FAILED (_("The encoder did not finish in time"));
            }
            if (msg.type == Gst.MessageType.ERROR) {
                Error err;
                string debug;
                msg.parse_error (out err, out debug);
                pipeline.set_state (Gst.State.NULL);
                throw new EncodeError.FAILED (err.message);
            }
        }

        public void push_audio (Gst.App.Src src, AudioClip clip, double duration) {
            int frames_total = (int) Math.round (duration * clip.rate);
            int chunk = 4096;
            int64 pts = 0;
            for (int start = 0; start < frames_total; start += chunk) {
                int n = int.min (chunk, frames_total - start);
                var data = new float[n * 2];
                for (int i = 0; i < n; i++) {
                    int si = (start + i) * clip.channels;
                    if (si + clip.channels - 1 < clip.samples.length) {
                        data[i * 2] = clip.samples[si];
                        data[i * 2 + 1] = clip.samples[si + (clip.channels > 1 ? 1 : 0)];
                    }
                }
                unowned uint8[] raw = (uint8[]) data;
                raw.length = data.length * 4;
                var copy = raw[0:raw.length];
                int64 dur = (int64) n * Gst.SECOND / clip.rate;
                src.push_buffer (buffer_of ((owned) copy, pts, dur));
                pts += dur;
            }
            src.end_of_stream ();
        }

        public string audio_caps (int rate) {
            return "audio/x-raw,format=F32LE,channels=2,rate=%d,layout=interleaved".printf (rate);
        }
    }

    public class SequenceSink : FrameSink {
        private OutputFormat format;

        public SequenceSink (OutputFormat format) {
            this.format = format;
        }

        public override void begin (int width, int height, double fps) throws Error {
            this.width = width;
            this.height = height;
            this.fps = fps;
            var dir = Path.get_dirname (Encoders.frame_path (path, 0, format.extension));
            DirUtils.create_with_parents (dir, 0755);
        }

        public override void write (FloatImage premul, int index) throws Error {
            var file = Encoders.frame_path (path, index, format.extension);
            bool alpha = module.alpha && format.alpha;
            var img = premul;
            if (!alpha) {
                img = premul.copy ();
                size_t n = img.pixel_count ();
                for (size_t i = 0; i < n; i++) img.data[i * 4 + 3] = 1;
            }
            switch (format.id) {
                case "png-sequence":
                    FileUtils.set_data (file, ImageIO.encode_png (img, module.bit_depth >= 16 ? 16 : 8, alpha));
                    break;
                case "tiff-sequence":
                    FileUtils.set_data (file, Tiff.encode (img, module.bit_depth, alpha, true));
                    break;
                case "exr-sequence":
                    var lin = img;
                    if (module.color_space != "" && module.color_space != "linear-srgb") {
                        lin = Pixels.unpremultiplied (img);
                        ColorManagement.convert (lin, "linear-srgb", module.color_space);
                        Pixels.premultiply (lin);
                    }
                    FileUtils.set_data (file, Exr.encode (lin, module.bit_depth < 32, true, alpha));
                    break;
                case "jpeg-sequence":
                    ImageIO.save_pixbuf (img, file, "jpeg", module.quality, false);
                    break;
                case "webp-sequence":
                    ImageIO.save_pixbuf (img, file, "webp", module.quality, alpha);
                    break;
                default:
                    throw new EncodeError.UNAVAILABLE (_("Unknown image sequence format"));
            }
            written.add (file);
        }

        public override void finish () throws Error {
        }
    }

    public class GstVideoSink : FrameSink {
        private OutputFormat format;
        private Gst.Pipeline? pipeline;
        private Gst.App.Src? vsrc;
        private Gst.App.Src? asrc;
        private int enc_w;
        private int enc_h;
        private int64 frame_ns;
        private int frames = 0;
        private Thread<bool>? audio_thread = null;

        public GstVideoSink (OutputFormat format) {
            this.format = format;
        }

        private string video_branch () {
            int q = module.quality.clamp (0, 100);
            int kbps = module.bitrate_kbps;
            switch (format.id) {
                case "h264-mp4":
                    var x264 = kbps > 0 ? "x264enc bitrate=%d speed-preset=medium".printf (kbps) : "x264enc pass=quant quantizer=%d speed-preset=medium".printf ((int) Math.round (50 - q * 0.38));
                    return "videoconvert ! video/x-raw,format=I420 ! " + x264 + " ! h264parse ! mux.";
                case "hevc-mp4":
                    var x265 = kbps > 0 ? "x265enc bitrate=%d".printf (kbps) : "x265enc option-string=\"crf=%d\"".printf ((int) Math.round (51 - q * 0.36));
                    return "videoconvert ! video/x-raw,format=I420 ! " + x265 + " ! h265parse ! mux.";
                case "av1-mp4":
                case "av1-webm":
                    string enc;
                    if (Encoders.has_element ("svtav1enc") && enc_w >= 64 && enc_h >= 64) enc = kbps > 0 ? "svtav1enc target-bitrate=%d preset=10".printf (kbps) : "svtav1enc crf=%d preset=10".printf ((int) Math.round (63 - q * 0.5));
                    else enc = "av1enc cpu-used=8 end-usage=q max-quantizer=%d".printf ((int) Math.round (63 - q * 0.5));
                    return "videoconvert ! video/x-raw,format=I420 ! " + enc + " ! av1parse ! mux.";
                case "vp9-webm":
                    var vp9 = kbps > 0 ? "vp9enc target-bitrate=%d deadline=1 cpu-used=5".printf (kbps * 1000) : "vp9enc end-usage=cq cq-level=%d deadline=1 cpu-used=5 target-bitrate=0".printf ((int) Math.round (63 - q * 0.5));
                    return "videoconvert ! video/x-raw,format=I420 ! " + vp9 + " ! mux.";
                case "png-mov":
                    return "videoconvert ! video/x-raw,format=RGBA ! pngenc compression-level=4 ! mux.";
                case "prores-422-mov":
                    return "videoconvert ! avenc_prores_ks profile=3 ! mux.";
                case "prores-4444-mov":
                    return "videoconvert ! avenc_prores_ks profile=4 ! mux.";
                case "dnxhr-mov":
                    return "videoconvert ! video/x-raw,format=Y42B ! avenc_dnxhd profile=dnxhr-hq ! mux.";
                default:
                    return "";
            }
        }

        private string mux () {
            switch (format.extension) {
                case "webm": return "webmmux name=mux";
                case "mov": return "qtmux name=mux";
                default: return "mp4mux name=mux faststart=true";
            }
        }

        private string audio_branch () {
            switch (format.extension) {
                case "webm": return "audioconvert ! audioresample ! opusenc bitrate=160000 ! mux.";
                case "mov": return "audioconvert ! audio/x-raw,format=S16LE ! mux.";
                default: return "audioconvert ! audioresample ! voaacenc bitrate=192000 ! aacparse ! mux.";
            }
        }

        public override void begin (int width, int height, double fps) throws Error {
            this.width = width;
            this.height = height;
            this.fps = fps;
            if (format.id == "dnxhr-mov" && (width < 256 || height < 120)) throw new EncodeError.UNAVAILABLE (_("DNxHR needs frames of at least 256 by 120 pixels"));
            bool needs_even = format.id != "png-mov";
            enc_w = needs_even ? width + width % 2 : width;
            enc_h = needs_even ? height + height % 2 : height;
            int num, den;
            Encoders.fps_fraction (fps, out num, out den);
            frame_ns = (int64) (Gst.SECOND * (double) den / num);
            var dir = Path.get_dirname (path);
            DirUtils.create_with_parents (dir, 0755);
            bool with_audio = audio != null && module.include_audio;
            var desc = new StringBuilder ();
            desc.append ("appsrc name=v format=time is-live=false block=false max-bytes=%u caps=\"video/x-raw,format=RGBA,width=%d,height=%d,framerate=%d/%d\" ! queue ! ".printf ((uint) (enc_w * enc_h * 4 * 4), enc_w, enc_h, num, den));
            desc.append (video_branch ());
            desc.append (" " + mux () + " ! filesink name=sink");
            if (with_audio) desc.append (" appsrc name=a format=time is-live=false block=true caps=\"%s\" ! queue ! %s".printf (Encoders.audio_caps (audio.rate), audio_branch ()));
            pipeline = Gst.parse_launch (desc.str) as Gst.Pipeline;
            if (pipeline == null) throw new EncodeError.FAILED (_("Cannot build the encoder"));
            pipeline.get_by_name ("sink").set ("location", path);
            vsrc = pipeline.get_by_name ("v") as Gst.App.Src;
            asrc = with_audio ? pipeline.get_by_name ("a") as Gst.App.Src : null;
            if (pipeline.set_state (Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE) throw new EncodeError.FAILED (_("The encoder could not start"));
            if (asrc != null) {
                var a = asrc;
                var clip = audio;
                double dur = clip.duration ();
                audio_thread = new Thread<bool> ("keyframe-audio", () => {
                    Encoders.push_audio (a, clip, dur);
                    return true;
                });
            }
        }

        public override void write (FloatImage premul, int index) throws Error {
            bool alpha = format.alpha && module.alpha;
            var data = Encoders.rgba8 (premul, alpha, enc_w, enc_h);
            check_bus ();
            int waited = 0;
            while (vsrc.get_current_level_bytes () >= vsrc.max_bytes && waited < 120000) {
                Thread.usleep (5000);
                waited += 5;
                check_bus ();
            }
            if (waited >= 120000) throw new EncodeError.FAILED (_("The encoder stopped responding"));
            var ret = vsrc.push_buffer (Encoders.buffer_of ((owned) data, frames * frame_ns, frame_ns));
            frames++;
            if (ret != Gst.FlowReturn.OK) {
                check_bus ();
                throw new EncodeError.FAILED (_("The encoder stopped accepting frames"));
            }
        }

        private void check_bus () throws Error {
            var msg = pipeline.get_bus ().pop_filtered (Gst.MessageType.ERROR);
            if (msg != null) {
                Error err;
                string debug;
                msg.parse_error (out err, out debug);
                throw new EncodeError.FAILED (err.message);
            }
        }

        public override void finish () throws Error {
            vsrc.end_of_stream ();
            Encoders.wait_eos (pipeline);
            if (audio_thread != null) audio_thread.join ();
            pipeline.set_state (Gst.State.NULL);
            written.add (path);
        }

        public override void abort () {
            if (pipeline != null) pipeline.set_state (Gst.State.NULL);
            FileUtils.unlink (path);
        }
    }

    public class FfmpegSink : FrameSink {
        private OutputFormat format;
        private Subprocess? proc;
        private OutputStream? stdin_stream;
        private string audio_tmp = "";

        public FfmpegSink (OutputFormat format) {
            this.format = format;
        }

        public override void begin (int width, int height, double fps) throws Error {
            this.width = width;
            this.height = height;
            this.fps = fps;
            DirUtils.create_with_parents (Path.get_dirname (path), 0755);
            var ff = Encoders.ffmpeg_path ();
            if (ff == null) throw new EncodeError.UNAVAILABLE (format.reason);
            if (format.id == "dnxhr-mov" && (width < 256 || height < 120)) throw new EncodeError.UNAVAILABLE (_("DNxHR needs frames of at least 256 by 120 pixels"));
            string[] args = { ff, "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgba64le", "-s", "%dx%d".printf (width, height), "-framerate", "%.6f".printf (fps), "-i", "-" };
            if (audio != null && module.include_audio) {
                audio_tmp = path + ".audio.wav";
                FileUtils.set_data (audio_tmp, Wav.encode (audio));
                args += "-i";
                args += audio_tmp;
                args += "-map";
                args += "0:v";
                args += "-map";
                args += "1:a";
                args += "-c:a";
                args += "pcm_s16le";
                args += "-shortest";
            }
            switch (format.id) {
                case "prores-4444-mov":
                    foreach (var a in new string[] { "-c:v", "prores_ks", "-profile:v", "4", "-vendor", "apl0", "-pix_fmt", "yuva444p10le" }) args += a;
                    break;
                case "prores-422-mov":
                    foreach (var a in new string[] { "-c:v", "prores_ks", "-profile:v", "3", "-vendor", "apl0", "-pix_fmt", "yuv422p10le" }) args += a;
                    break;
                default:
                    foreach (var a in new string[] { "-c:v", "dnxhd", "-profile:v", "dnxhr_hq", "-pix_fmt", "yuv422p" }) args += a;
                    break;
            }
            args += path;
            proc = new Subprocess.newv (args, SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDERR_PIPE);
            stdin_stream = proc.get_stdin_pipe ();
        }

        public override void write (FloatImage premul, int index) throws Error {
            bool alpha = format.alpha && module.alpha;
            var img = Pixels.unpremultiplied (premul);
            var data = new uint8[(size_t) width * height * 8];
            for (int y = 0; y < height; y++)
                for (int x = 0; x < width; x++) {
                    size_t i = img.offset (x, y), o = ((size_t) y * width + x) * 8;
                    float a = img.data[i + 3].clamp (0, 1);
                    for (int c = 0; c < 4; c++) {
                        float v;
                        if (c == 3) v = alpha ? a : 1;
                        else {
                            v = img.data[i + c];
                            if (!alpha) v *= a;
                            v = Transfer.linear_to_srgb (v.clamp (0, 1));
                        }
                        uint16 s = (uint16) Math.roundf (v * 65535);
                        data[o + c * 2] = (uint8) s;
                        data[o + c * 2 + 1] = (uint8) (s >> 8);
                    }
                }
            size_t written_bytes;
            stdin_stream.write_all (data, out written_bytes);
        }

        public override void finish () throws Error {
            string? err_text;
            proc.communicate_utf8 (null, null, null, out err_text);
            if (audio_tmp != "") FileUtils.unlink (audio_tmp);
            if (!proc.get_successful ()) throw new EncodeError.FAILED (_("FFmpeg failed: %s").printf ((err_text ?? "").strip ()));
            written.add (path);
        }

        public override void abort () {
            if (proc != null) proc.force_exit ();
            if (audio_tmp != "") FileUtils.unlink (audio_tmp);
            FileUtils.unlink (path);
        }
    }

    public class AudioSink : FrameSink {
        private OutputFormat format;

        public AudioSink (OutputFormat format) {
            this.format = format;
        }

        public override void begin (int width, int height, double fps) throws Error {
            DirUtils.create_with_parents (Path.get_dirname (path), 0755);
        }

        public override void write (FloatImage premul, int index) throws Error {
        }

        public override void finish () throws Error {
            var clip = audio ?? new AudioClip ();
            if (format.id == "wav") {
                FileUtils.set_data (path, Wav.encode (clip));
                written.add (path);
                return;
            }
            string branch = format.id == "flac" ? "audioconvert ! audio/x-raw,format=S16LE ! flacenc ! filesink name=sink" : "audioconvert ! audioresample ! voaacenc bitrate=192000 ! aacparse ! mp4mux ! filesink name=sink";
            var pipeline = Gst.parse_launch ("appsrc name=a format=time is-live=false block=true caps=\"%s\" ! %s".printf (Encoders.audio_caps (clip.rate), branch)) as Gst.Pipeline;
            pipeline.get_by_name ("sink").set ("location", path);
            var src = pipeline.get_by_name ("a") as Gst.App.Src;
            pipeline.set_state (Gst.State.PLAYING);
            Encoders.push_audio (src, clip, clip.duration ());
            Encoders.wait_eos (pipeline);
            pipeline.set_state (Gst.State.NULL);
            written.add (path);
        }
    }

    namespace Wav {
        public uint8[] encode (AudioClip clip) {
            int ch = clip.channels;
            int n = clip.samples.length;
            var b = new ByteArray ();
            uint32 data_size = (uint32) n * 2;
            b.append ("RIFF".data);
            put32 (b, 36 + data_size);
            b.append ("WAVE".data);
            b.append ("fmt ".data);
            put32 (b, 16);
            put16 (b, 1);
            put16 (b, ch);
            put32 (b, clip.rate);
            put32 (b, clip.rate * ch * 2);
            put16 (b, ch * 2);
            put16 (b, 16);
            b.append ("data".data);
            put32 (b, data_size);
            var pcm = new uint8[n * 2];
            for (int i = 0; i < n; i++) {
                int v = (int) Math.roundf (clip.samples[i].clamp (-1, 1) * 32767);
                pcm[i * 2] = (uint8) (v & 0xff);
                pcm[i * 2 + 1] = (uint8) ((v >> 8) & 0xff);
            }
            b.append (pcm);
            return b.steal ();
        }

        public AudioClip? decode (uint8[] d) {
            if (d.length < 44 || d[0] != 'R' || d[8] != 'W') return null;
            int pos = 12;
            int ch = 2, rate = 48000, bits = 16, fmt = 1;
            while (pos + 8 <= d.length) {
                string id = "%c%c%c%c".printf (d[pos], d[pos + 1], d[pos + 2], d[pos + 3]);
                int size = (int) (d[pos + 4] | (d[pos + 5] << 8) | (d[pos + 6] << 16) | (d[pos + 7] << 24));
                if (id == "fmt ") {
                    fmt = d[pos + 8] | (d[pos + 9] << 8);
                    ch = d[pos + 10] | (d[pos + 11] << 8);
                    rate = (int) (d[pos + 12] | (d[pos + 13] << 8) | (d[pos + 14] << 16) | (d[pos + 15] << 24));
                    bits = d[pos + 22] | (d[pos + 23] << 8);
                } else if (id == "data") {
                    if (fmt != 1 || bits != 16) return null;
                    var clip = new AudioClip ();
                    clip.rate = rate;
                    clip.channels = ch;
                    int n = int.min (size, d.length - pos - 8) / 2;
                    clip.samples = new float[n];
                    for (int i = 0; i < n; i++) clip.samples[i] = ((int16) (d[pos + 8 + i * 2] | (d[pos + 9 + i * 2] << 8))) / 32768.0f;
                    return clip;
                }
                pos += 8 + size + (size % 2);
            }
            return null;
        }

        private void put16 (ByteArray b, uint v) {
            b.append ({ (uint8) v, (uint8) (v >> 8) });
        }

        private void put32 (ByteArray b, uint32 v) {
            b.append ({ (uint8) v, (uint8) (v >> 8), (uint8) (v >> 16), (uint8) (v >> 24) });
        }
    }

    public class Ebml {
        public ByteArray buf = new ByteArray ();

        public static uint8[] id_bytes (uint32 id) {
            if (id > 0xffffff) return { (uint8) (id >> 24), (uint8) (id >> 16), (uint8) (id >> 8), (uint8) id };
            if (id > 0xffff) return { (uint8) (id >> 16), (uint8) (id >> 8), (uint8) id };
            if (id > 0xff) return { (uint8) (id >> 8), (uint8) id };
            return { (uint8) id };
        }

        public static uint8[] size_bytes (uint64 size) {
            int len = 1;
            while (len < 8 && size >= ((uint64) 1 << (7 * len)) - 1) len++;
            var r = new uint8[len];
            uint64 v = size | ((uint64) 1 << (7 * len));
            for (int i = len - 1; i >= 0; i--) {
                r[i] = (uint8) (v & 0xff);
                v >>= 8;
            }
            return r;
        }

        public void element (uint32 id, uint8[] payload) {
            buf.append (id_bytes (id));
            buf.append (size_bytes (payload.length));
            buf.append (payload);
        }

        public void uint (uint32 id, uint64 v) {
            int len = 1;
            while (len < 8 && v >= ((uint64) 1 << (8 * len))) len++;
            var p = new uint8[len];
            for (int i = len - 1; i >= 0; i--) {
                p[i] = (uint8) (v & 0xff);
                v >>= 8;
            }
            element (id, p);
        }

        public void float64 (uint32 id, double v) {
            uint64 bits = *((uint64*) (&v));
            var p = new uint8[8];
            for (int i = 7; i >= 0; i--) {
                p[i] = (uint8) (bits & 0xff);
                bits >>= 8;
            }
            element (id, p);
        }

        public void str (uint32 id, string s) {
            element (id, s.data);
        }

        public void child (uint32 id, Ebml inner) {
            element (id, inner.buf.data);
        }
    }

    public class EncodedPacket {
        public uint8[] data;
        public int64 pts;
        public bool key;
    }

    public class WebmAlphaSink : FrameSink {
        private Gst.Pipeline? color_pipe;
        private Gst.Pipeline? alpha_pipe;
        private Gst.App.Src? color_src;
        private Gst.App.Src? alpha_src;
        private Gst.App.Sink? color_sink;
        private Gst.App.Sink? alpha_sink;
        private int enc_w;
        private int enc_h;
        private int64 frame_ns;
        private int frames = 0;
        private Gee.ArrayList<EncodedPacket> color_packets = new Gee.ArrayList<EncodedPacket> ();
        private Gee.ArrayList<EncodedPacket> alpha_packets = new Gee.ArrayList<EncodedPacket> ();
        private Thread<bool>? color_reader;
        private Thread<bool>? alpha_reader;

        private string vp9 () {
            int q = module.quality.clamp (0, 100);
            return "vp9enc end-usage=cq cq-level=%d deadline=1 cpu-used=5 target-bitrate=0 lag-in-frames=0 auto-alt-ref=false keyframe-max-dist=60".printf ((int) Math.round (63 - q * 0.5));
        }

        private Thread<bool> reader (Gst.App.Sink sink, Gee.ArrayList<EncodedPacket> into) {
            return new Thread<bool> ("keyframe-webm", () => {
                while (true) {
                    var sample = sink.pull_sample ();
                    if (sample == null) break;
                    var b = sample.get_buffer ();
                    var pk = new EncodedPacket ();
                    Gst.MapInfo info;
                    if (b.map (out info, Gst.MapFlags.READ)) {
                        pk.data = info.data[0:info.size];
                        b.unmap (info);
                    }
                    pk.pts = (int64) b.pts;
                    pk.key = (b.get_flags () & Gst.BufferFlags.DELTA_UNIT) == 0;
                    into.add (pk);
                }
                return true;
            });
        }

        public override void begin (int width, int height, double fps) throws Error {
            this.width = width;
            this.height = height;
            this.fps = fps;
            enc_w = width + width % 2;
            enc_h = height + height % 2;
            int num, den;
            Encoders.fps_fraction (fps, out num, out den);
            frame_ns = (int64) (Gst.SECOND * (double) den / num);
            DirUtils.create_with_parents (Path.get_dirname (path), 0755);
            color_pipe = Gst.parse_launch ("appsrc name=src format=time block=true caps=\"video/x-raw,format=RGBA,width=%d,height=%d,framerate=%d/%d\" ! videoconvert ! video/x-raw,format=I420 ! %s ! appsink name=out sync=false".printf (enc_w, enc_h, num, den, vp9 ())) as Gst.Pipeline;
            alpha_pipe = Gst.parse_launch ("appsrc name=src format=time block=true caps=\"video/x-raw,format=I420,width=%d,height=%d,framerate=%d/%d\" ! %s ! appsink name=out sync=false".printf (enc_w, enc_h, num, den, vp9 ())) as Gst.Pipeline;
            color_src = color_pipe.get_by_name ("src") as Gst.App.Src;
            alpha_src = alpha_pipe.get_by_name ("src") as Gst.App.Src;
            color_sink = color_pipe.get_by_name ("out") as Gst.App.Sink;
            alpha_sink = alpha_pipe.get_by_name ("out") as Gst.App.Sink;
            color_pipe.set_state (Gst.State.PLAYING);
            alpha_pipe.set_state (Gst.State.PLAYING);
            color_reader = reader (color_sink, color_packets);
            alpha_reader = reader (alpha_sink, alpha_packets);
        }

        public override void write (FloatImage premul, int index) throws Error {
            var rgba = Encoders.rgba8 (premul, true, enc_w, enc_h);
            int ys = (enc_w + 3) & ~3;
            int cw = enc_w / 2, ch = enc_h / 2;
            int cs = (cw + 3) & ~3;
            var i420 = new uint8[ys * enc_h + cs * ch * 2];
            for (int y = 0; y < enc_h; y++)
                for (int x = 0; x < enc_w; x++) i420[y * ys + x] = rgba[((size_t) y * enc_w + x) * 4 + 3];
            for (int i = ys * enc_h; i < i420.length; i++) i420[i] = 128;
            int64 pts = frames * frame_ns;
            color_src.push_buffer (Encoders.buffer_of ((owned) rgba, pts, frame_ns));
            alpha_src.push_buffer (Encoders.buffer_of ((owned) i420, pts, frame_ns));
            frames++;
        }

        private Gee.ArrayList<EncodedPacket> encode_opus () throws Error {
            var packets = new Gee.ArrayList<EncodedPacket> ();
            if (audio == null || !module.include_audio) return packets;
            var pipe = Gst.parse_launch ("appsrc name=src format=time block=true caps=\"%s\" ! audioconvert ! audioresample ! audio/x-raw,rate=48000,channels=2 ! opusenc bitrate=160000 ! appsink name=out sync=false".printf (Encoders.audio_caps (audio.rate))) as Gst.Pipeline;
            var src = pipe.get_by_name ("src") as Gst.App.Src;
            var sink = pipe.get_by_name ("out") as Gst.App.Sink;
            pipe.set_state (Gst.State.PLAYING);
            var t = reader (sink, packets);
            Encoders.push_audio (src, audio, double.min (audio.duration (), frames * frame_ns / (double) Gst.SECOND));
            t.join ();
            pipe.set_state (Gst.State.NULL);
            return packets;
        }

        public override void finish () throws Error {
            color_src.end_of_stream ();
            alpha_src.end_of_stream ();
            color_reader.join ();
            alpha_reader.join ();
            color_pipe.set_state (Gst.State.NULL);
            alpha_pipe.set_state (Gst.State.NULL);
            if (color_packets.size == 0) throw new EncodeError.FAILED (_("The VP9 encoder produced no frames"));
            var opus = encode_opus ();
            FileUtils.set_data (path, mux (opus));
            written.add (path);
        }

        private uint8[] opus_head () {
            var b = new ByteArray ();
            b.append ("OpusHead".data);
            b.append ({ 1, 2, (uint8) (312 & 0xff), (uint8) (312 >> 8), (uint8) (48000 & 0xff), (uint8) ((48000 >> 8) & 0xff), 0, 0, 0, 0, 0 });
            return b.steal ();
        }

        private uint8[] block (int track, int16 rel, uint8 flags, uint8[] data) {
            var b = new ByteArray ();
            b.append ({ (uint8) (0x80 | track), (uint8) (rel >> 8), (uint8) (rel & 0xff), flags });
            b.append (data);
            return b.steal ();
        }

        private uint8[] mux (Gee.List<EncodedPacket> opus) {
            var file = new Ebml ();
            var head = new Ebml ();
            head.uint (0x4286, 1);
            head.uint (0x42F7, 1);
            head.uint (0x42F2, 4);
            head.uint (0x42F3, 8);
            head.str (0x4282, "webm");
            head.uint (0x4287, 4);
            head.uint (0x4285, 2);
            file.child (0x1A45DFA3, head);
            var seg = new Ebml ();
            var info = new Ebml ();
            info.uint (0x2AD7B1, 1000000);
            info.float64 (0x4489, frames * frame_ns / 1e6);
            info.str (0x4D80, "Keyframe");
            info.str (0x5741, "Keyframe");
            seg.child (0x1549A966, info);
            var tracks = new Ebml ();
            var vt = new Ebml ();
            vt.uint (0xD7, 1);
            vt.uint (0x73C5, 1);
            vt.uint (0x83, 1);
            vt.uint (0x9C, 0);
            vt.str (0x86, "V_VP9");
            vt.uint (0x23E383, (uint64) frame_ns);
            vt.uint (0x55EE, 1);
            var video = new Ebml ();
            video.uint (0xB0, enc_w);
            video.uint (0xBA, enc_h);
            video.uint (0x53C0, 1);
            vt.child (0xE0, video);
            tracks.child (0xAE, vt);
            if (opus.size > 0) {
                var at = new Ebml ();
                at.uint (0xD7, 2);
                at.uint (0x73C5, 2);
                at.uint (0x83, 2);
                at.uint (0x9C, 0);
                at.str (0x86, "A_OPUS");
                at.element (0x63A2, opus_head ());
                at.uint (0x56AA, 6500000);
                at.uint (0x56BB, 80000000);
                var aud = new Ebml ();
                aud.float64 (0xB5, 48000);
                aud.uint (0x9F, 2);
                at.child (0xE1, aud);
                tracks.child (0xAE, at);
            }
            seg.child (0x1654AE6B, tracks);
            int ai = 0;
            int64 cluster_ms = -1;
            Ebml? cluster = null;
            int n = color_packets.size;
            for (int i = 0; i < n; i++) {
                var cp = color_packets[i];
                int64 ms = (int64) Math.round (i * frame_ns / 1e6);
                if (cluster == null || cp.key || ms - cluster_ms > 30000) {
                    if (cluster != null) seg.child (0x1F43B675, cluster);
                    cluster = new Ebml ();
                    cluster_ms = ms;
                    cluster.uint (0xE7, (uint64) ms);
                }
                int64 next_ms = (int64) Math.round ((i + 1) * frame_ns / 1e6);
                while (ai < opus.size && opus[ai].pts / 1000000 < next_ms) {
                    int64 ams = opus[ai].pts / 1000000;
                    if (ams - cluster_ms < -32000 || ams - cluster_ms > 32000) break;
                    cluster.element (0xA3, block (2, (int16) (ams - cluster_ms), 0x80, opus[ai].data));
                    ai++;
                }
                var group = new Ebml ();
                group.element (0xA1, block (1, (int16) (ms - cluster_ms), 0, cp.data));
                if (i < alpha_packets.size) {
                    var more = new Ebml ();
                    more.uint (0xEE, 1);
                    more.element (0xA5, alpha_packets[i].data);
                    var adds = new Ebml ();
                    adds.child (0xA6, more);
                    group.child (0x75A1, adds);
                }
                if (!cp.key) {
                    int64 rel = -(int64) Math.round (frame_ns / 1e6);
                    group.element (0xFB, { (uint8) ((rel >> 8) & 0xff), (uint8) (rel & 0xff) });
                }
                cluster.child (0xA0, group);
            }
            while (ai < opus.size && cluster != null) {
                int64 ams = opus[ai].pts / 1000000;
                if (ams - cluster_ms > 32000) break;
                cluster.element (0xA3, block (2, (int16) (ams - cluster_ms), 0x80, opus[ai].data));
                ai++;
            }
            if (cluster != null) seg.child (0x1F43B675, cluster);
            file.child (0x18538067, seg);
            return file.buf.steal ();
        }

        public override void abort () {
            if (color_pipe != null) color_pipe.set_state (Gst.State.NULL);
            if (alpha_pipe != null) alpha_pipe.set_state (Gst.State.NULL);
            FileUtils.unlink (path);
        }
    }
}
