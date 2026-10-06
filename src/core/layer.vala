namespace Singularity.Apps.Keyframe {

    public enum LayerKind {
        SOLID,
        NULL,
        SHAPE,
        TEXT,
        FOOTAGE,
        PRECOMP,
        CAMERA,
        LIGHT,
        AUDIO,
        MODEL,
        PARTICLES;

        public string to_id () {
            switch (this) {
                case NULL: return "null";
                case SHAPE: return "shape";
                case TEXT: return "text";
                case FOOTAGE: return "footage";
                case PRECOMP: return "precomp";
                case CAMERA: return "camera";
                case LIGHT: return "light";
                case AUDIO: return "audio";
                case MODEL: return "model";
                case PARTICLES: return "particles";
                default: return "solid";
            }
        }

        public static LayerKind from_id (string? s) {
            switch (s) {
                case "null": return NULL;
                case "shape": return SHAPE;
                case "text": return TEXT;
                case "footage": return FOOTAGE;
                case "precomp": return PRECOMP;
                case "camera": return CAMERA;
                case "light": return LIGHT;
                case "audio": return AUDIO;
                case "model": return MODEL;
                case "particles": return PARTICLES;
                default: return SOLID;
            }
        }

        public bool is_visual () {
            return this != CAMERA && this != LIGHT && this != AUDIO && this != NULL;
        }
    }

    public enum MatteMode {
        NONE,
        ALPHA,
        ALPHA_INVERTED,
        LUMA,
        LUMA_INVERTED;

        public string to_id () {
            switch (this) {
                case ALPHA: return "alpha";
                case ALPHA_INVERTED: return "alpha-inverted";
                case LUMA: return "luma";
                case LUMA_INVERTED: return "luma-inverted";
                default: return "none";
            }
        }

        public static MatteMode from_id (string? s) {
            switch (s) {
                case "alpha": return ALPHA;
                case "alpha-inverted": return ALPHA_INVERTED;
                case "luma": return LUMA;
                case "luma-inverted": return LUMA_INVERTED;
                default: return NONE;
            }
        }
    }

    public enum AutoOrient {
        OFF,
        ALONG_PATH,
        TOWARDS_CAMERA;

        public string to_id () {
            switch (this) {
                case ALONG_PATH: return "path";
                case TOWARDS_CAMERA: return "camera";
                default: return "off";
            }
        }

        public static AutoOrient from_id (string? s) {
            switch (s) {
                case "path": return ALONG_PATH;
                case "camera": return TOWARDS_CAMERA;
                default: return OFF;
            }
        }
    }

    public enum LightType {
        PARALLEL,
        SPOT,
        POINT,
        AMBIENT
    }

    public class Layer : Object {
        public string id;
        public string name;
        public LayerKind kind;
        public string source_id = "";
        public int label = 0;
        public bool video = true;
        public bool audio = true;
        public bool solo = false;
        public bool locked = false;
        public bool shy = false;
        public bool motion_blur = false;
        public bool three_d = false;
        public bool adjustment = false;
        public bool collapse = false;
        public bool guide = false;
        public bool frame_blend = false;
        public string parent_id = "";
        public double in_point = 0;
        public double out_point = 10;
        public double start_time = 0;
        public double stretch = 1;
        public Singularity.Imaging.BlendMode blend = Singularity.Imaging.BlendMode.NORMAL;
        public string matte_id = "";
        public MatteMode matte_mode = MatteMode.NONE;
        public bool preserve_transparency = false;
        public AutoOrient auto_orient = AutoOrient.OFF;
        public double[] solid_color = { 0.5, 0.5, 0.5, 1 };
        public int solid_width = 1920;
        public int solid_height = 1080;
        public bool time_remap = false;
        public string comment = "";
        public PropGroup root;
        public unowned Composition? comp = null;
        public int revision = 0;

        public Layer (LayerKind kind, string name) {
            this.kind = kind;
            this.name = name;
            this.id = new_id ();
            root = new PropGroup ("layer", "", name);
            root.layer = this;
        }

        public static string new_id () {
            return "%08x%04x".printf (Random.next_int (), Random.int_range (0, 0xffff));
        }

        public PropGroup transform {
            owned get { return root.group ("transform"); }
        }

        public PropGroup? masks {
            owned get { return root.group ("masks"); }
        }

        public PropGroup? effects {
            owned get { return root.group ("effects"); }
        }

        public PropGroup? contents {
            owned get { return root.group ("contents"); }
        }

        public PropGroup? text_group {
            owned get { return root.group ("text"); }
        }

        public Property? tprop (string key) {
            var t = transform;
            return t != null ? t.prop (key) : null;
        }

        public void mark_changed () {
            revision++;
            if (comp != null) comp.layer_changed (this);
        }

        public double layer_time (double comp_time) {
            return (comp_time - start_time) / (stretch.abs () < 1e-9 ? 1 : stretch);
        }

        public double comp_time (double layer_time) {
            return layer_time * stretch + start_time;
        }

        public double source_time (double comp_time) {
            double lt = layer_time (comp_time);
            if (time_remap) {
                var p = root.prop ("time-remap");
                if (p != null) return p.scalar_at (lt);
            }
            return lt;
        }

        public bool active_at (double t) {
            return t >= in_point - 1e-9 && t < out_point - 1e-9;
        }

        public Layer? parent_layer () {
            if (parent_id == "" || comp == null) return null;
            return comp.layer_by_id (parent_id);
        }

        public Mat4 local_matrix (double comp_t) {
            double t = layer_time (comp_t);
            var tr = transform;
            var a = tr.vec ("anchor", t);
            var p = tr.vec ("position", t);
            var s = tr.vec ("scale", t);
            double rz = tr.num ("rotation", t);
            if (auto_orient == AutoOrient.ALONG_PATH) {
                var pp = tr.prop ("position");
                if (pp != null && pp.varies ()) {
                    var v = pp.velocity_at (t);
                    if (Math.hypot (v[0], v[1]) > 1e-6) rz += Math.atan2 (v[1], v[0]) * 180.0 / Math.PI;
                    else {
                        var v2 = pp.velocity_at (t + 0.02);
                        var v1 = pp.velocity_at (t - 0.02);
                        var vv = Math.hypot (v2[0], v2[1]) > Math.hypot (v1[0], v1[1]) ? v2 : v1;
                        if (Math.hypot (vv[0], vv[1]) > 1e-6) rz += Math.atan2 (vv[1], vv[0]) * 180.0 / Math.PI;
                    }
                }
            }
            double skew_amount = tr.num ("skew", t);
            double skew_axis = tr.num ("skew-axis", t);
            var m = Mat4.translation (p[0], p[1], three_d && p.length > 2 ? p[2] : 0);
            if (three_d) {
                var o = tr.vec ("orientation", t);
                if (auto_orient == AutoOrient.TOWARDS_CAMERA && comp != null) {
                    var cam = comp.active_camera (comp_t);
                    if (cam != null) {
                        var cp = cam.world_position (comp_t);
                        double dx = cp.x - p[0], dy = cp.y - p[1], dz = cp.z - (p.length > 2 ? p[2] : 0);
                        o = { -Math.atan2 (dy, Math.hypot (dx, dz)) * 180.0 / Math.PI, Math.atan2 (dx, -dz) * 180.0 / Math.PI, 0 };
                        o[1] = -o[1];
                        o[0] = -o[0];
                    }
                }
                m = m.multiply (Mat4.rotation_x (o[0])).multiply (Mat4.rotation_y (o[1])).multiply (Mat4.rotation_z (o[2]));
                m = m.multiply (Mat4.rotation_x (tr.num ("rotation-x", t))).multiply (Mat4.rotation_y (tr.num ("rotation-y", t)));
            }
            m = m.multiply (Mat4.rotation_z (rz));
            m = m.multiply (Mat4.skew (skew_amount, skew_axis));
            m = m.multiply (Mat4.scaling (s[0] / 100.0, s[1] / 100.0, three_d && s.length > 2 ? s[2] / 100.0 : 1));
            m = m.multiply (Mat4.translation (-a[0], -a[1], three_d && a.length > 2 ? -a[2] : 0));
            return m;
        }

        public Mat4 world_matrix (double comp_t, int depth = 0) {
            var local = local_matrix (comp_t);
            var parent = parent_layer ();
            if (parent == null || parent == this || depth > 32) return local;
            return parent.world_matrix (comp_t, depth + 1).multiply (local);
        }

        public Vec3 world_position (double comp_t) {
            var m = world_matrix (comp_t);
            if (kind == LayerKind.CAMERA || kind == LayerKind.LIGHT) {
                var parent = parent_layer ();
                var p = transform.vec ("position", layer_time (comp_t));
                var local = Vec3 (p[0], p[1], p.length > 2 ? p[2] : 0);
                return parent != null ? parent.world_matrix (comp_t).transform_point (local) : local;
            }
            return m.transform_point (Vec3 (0, 0, 0));
        }

        public double opacity_at (double comp_t) {
            return transform.num ("opacity", layer_time (comp_t)) / 100.0;
        }

        public bool is_three_d () {
            return three_d || kind == LayerKind.CAMERA || kind == LayerKind.LIGHT;
        }

        public Layer duplicate () {
            var l = new Layer (kind, name);
            l.copy_from (this);
            return l;
        }

        public void copy_from (Layer o) {
            source_id = o.source_id;
            label = o.label;
            video = o.video;
            audio = o.audio;
            solo = o.solo;
            locked = o.locked;
            shy = o.shy;
            motion_blur = o.motion_blur;
            three_d = o.three_d;
            adjustment = o.adjustment;
            collapse = o.collapse;
            guide = o.guide;
            frame_blend = o.frame_blend;
            parent_id = o.parent_id;
            in_point = o.in_point;
            out_point = o.out_point;
            start_time = o.start_time;
            stretch = o.stretch;
            blend = o.blend;
            matte_id = o.matte_id;
            matte_mode = o.matte_mode;
            preserve_transparency = o.preserve_transparency;
            auto_orient = o.auto_orient;
            solid_color = o.solid_color;
            solid_width = o.solid_width;
            solid_height = o.solid_height;
            time_remap = o.time_remap;
            comment = o.comment;
            root = (PropGroup) o.root.clone ();
            root.layer = this;
            root.name = name;
        }

        public Gee.ArrayList<Property> all_props () {
            var r = new Gee.ArrayList<Property> ();
            root.visit_props (r);
            return r;
        }

        public Gee.ArrayList<double?> key_times () {
            var times = new Gee.ArrayList<double?> ();
            foreach (var p in all_props ())
                foreach (var k in p.keys) {
                    bool found = false;
                    foreach (var e in times) if ((e - k.time).abs () < 1e-6) found = true;
                    if (!found) times.add (k.time);
                }
            times.sort ((a, b) => a < b ? -1 : (a > b ? 1 : 0));
            return times;
        }

        public LightType light_type () {
            var g = root.group ("light");
            return g != null ? (LightType) int.parse (g.attr ("type", "2")) : LightType.POINT;
        }
    }
}
