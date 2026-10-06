using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    public delegate void RenderProgress (double fraction, int frame);

    namespace RenderJobs {
        public void time_span (Composition comp, RenderItem item, out double start, out double end) {
            if (item.end > item.start) {
                start = item.start.clamp (0, comp.duration);
                end = item.end.clamp (start, comp.duration);
            } else {
                start = comp.work_start.clamp (0, comp.duration);
                end = comp.work_area_end ();
            }
            if (end <= start) {
                start = 0;
                end = comp.duration;
            }
        }

        public Gee.ArrayList<string> run (Project p, RenderItem item, Cancellable? cancel = null, RenderProgress? progress = null) throws Error {
            var comp = p.comp_by_id (item.comp_id);
            if (comp == null) throw new EncodeError.FAILED (_("The composition of this render item no longer exists"));
            if (item.outputs.size == 0) throw new EncodeError.FAILED (_("The render item has no output module"));
            double start, end;
            time_span (comp, item, out start, out end);
            item.status = RenderStatus.RENDERING;
            item.error = "";
            item.progress = 0;
            try {
                var r = render (p, comp, item.outputs, start, end, item.resolution, item.motion_blur, cancel, (f, n) => {
                    item.progress = f;
                    if (progress != null) progress (f, n);
                });
                item.status = RenderStatus.DONE;
                item.progress = 1;
                return r;
            } catch (Error e) {
                item.status = e is EncodeError && e.code == EncodeError.CANCELLED ? RenderStatus.STOPPED : RenderStatus.FAILED;
                item.error = e.message;
                throw e;
            }
        }

        public Gee.ArrayList<string> render (Project p, Composition comp, Gee.List<OutputModule> outputs, double start, double end, int resolution, bool motion_blur,
                                             Cancellable? cancel = null, RenderProgress? progress = null) throws Error {
            var renderer = new Renderer (p);
            var settings = new RenderSettings ();
            settings.downsample = int.max (1, resolution);
            settings.motion_blur = motion_blur;
            settings.use_cache = false;
            settings.include_guides = false;
            int w = renderer.canvas_width (comp, settings), h = renderer.canvas_height (comp, settings);
            int frames = int.max (1, (int) Math.round ((end - start) * comp.fps));
            var sinks = new Gee.ArrayList<FrameSink> ();
            AudioClip? audio = null;
            bool needs_audio = false;
            foreach (var om in outputs) {
                var f = Encoders.find (om.format);
                if (f != null && (f.audio_only || (f.video && om.include_audio))) needs_audio = true;
            }
            if (needs_audio && AudioMix.comp_has_audio (p, comp)) audio = AudioMix.mix (p, renderer.media, comp, start, start + frames / comp.fps);
            try {
                foreach (var om in outputs) {
                    var sink = Encoders.create (om);
                    sink.audio = audio;
                    if (sink is AudioSink && sink.audio == null) {
                        var silence = new AudioClip ();
                        silence.samples = new float[(int) (frames / comp.fps * AudioMix.RATE) * 2];
                        sink.audio = silence;
                    }
                    int ow = om.width > 0 ? om.width : w, oh = om.height > 0 ? om.height : h;
                    sink.begin (ow, oh, comp.fps);
                    sinks.add (sink);
                }
                bool any_video = false;
                foreach (var s in sinks) if (!(s is AudioSink)) any_video = true;
                if (any_video) {
                    for (int i = 0; i < frames; i++) {
                        if (cancel != null && cancel.is_cancelled ()) throw new EncodeError.CANCELLED (_("Rendering was stopped"));
                        double t = start + i / comp.fps;
                        var img = renderer.render (comp, t, settings);
                        foreach (var s in sinks) {
                            if (s is AudioSink) continue;
                            var om = s.module;
                            var frame = Encoders.resize (img, om.width, om.height);
                            string target = om.color_space != "" ? om.color_space : "linear-srgb";
                            if (p.working_space != target && p.working_space != "") frame = Pixels.convert_space (frame, p.working_space, target);
                            s.write (frame, i);
                        }
                        if (progress != null) progress ((i + 1) / (double) frames * 0.98, i);
                    }
                }
                var result = new Gee.ArrayList<string> ();
                foreach (var s in sinks) {
                    s.finish ();
                    if (s.written.size > 0) result.add (s.module.format.has_suffix ("-sequence") ? s.written[0] : s.path);
                }
                renderer.media.close ();
                if (progress != null) progress (1, frames);
                return result;
            } catch (Error e) {
                foreach (var s in sinks) s.abort ();
                renderer.media.close ();
                throw e;
            }
        }

        public string[] helper_argv (string project_path, string item_id) {
            var self_dir = Environment.get_variable ("SINGULARITY_KEYFRAME_RENDER");
            string exe = self_dir != null && self_dir != "" ? self_dir : (Environment.find_program_in_path ("singularity-keyframe-render") ?? "singularity-keyframe-render");
            return { exe, "--project", project_path, "--item", item_id };
        }

        public void parse_line (string line, out string kind, out string value) {
            int sp = line.index_of (" ");
            kind = sp > 0 ? line.substring (0, sp) : line;
            value = sp > 0 ? line.substring (sp + 1) : "";
        }
    }
}
