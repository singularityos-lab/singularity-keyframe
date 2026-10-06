using Singularity.Imaging;

namespace Singularity.Apps.Keyframe {

    public class GstStream : Object {
        public int width = 0;
        public int height = 0;
        public int fps_n = 30;
        public int fps_d = 1;
        public int frame_count = 0;
        public int64 duration_ns = 0;
        public string error = "";
        private Project? project;
        private Composition? comp;
        private Renderer? renderer;
        private RenderSettings settings = new RenderSettings ();

        public bool load (uint8[] data, string? composition, string? overrides, string? base_dir) {
            try {
                project = NativeFormat.load_bytes (data, base_dir ?? "");
            } catch (Error e) {
                error = e.message;
                return false;
            }
            if (composition != null && composition != "") comp = project.comp_by_name (composition) ?? project.comp_by_id (composition);
            else comp = MotionTemplates.main_composition (project);
            if (comp == null) {
                error = _("The project has no composition to play");
                return false;
            }
            if (overrides != null && overrides != "") {
                try {
                    MotionTemplates.apply_overrides (comp, overrides);
                } catch (Error e) {
                    error = e.message;
                    return false;
                }
            }
            renderer = new Renderer (project);
            settings.use_cache = false;
            settings.motion_blur = true;
            width = comp.width;
            height = comp.height;
            Encoders.fps_fraction (comp.fps, out fps_n, out fps_d);
            frame_count = int.max (1, (int) Math.round (comp.duration * fps_n / (double) fps_d));
            duration_ns = (int64) frame_count * Gst.SECOND * fps_d / fps_n;
            return true;
        }

        public uint8[] render_frame (int index) {
            if (renderer == null) return new uint8[0];
            double t = index * fps_d / (double) fps_n;
            var img = renderer.render (comp, t, settings);
            return Encoders.rgba8 (img, true, width, height);
        }
    }
}
