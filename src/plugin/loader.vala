namespace Singularity.Apps.Keyframe {

    namespace EffectPlugins {
        private Peas.Engine? engine = null;
        private Gee.ArrayList<KeyframeEffect.Plugin>? plugins = null;

        public string[] search_dirs () {
            string[] dirs = {};
            string? env = Environment.get_variable ("SINGULARITY_KEYFRAME_PLUGIN_PATH");
            if (env != null) foreach (var p in env.split (":")) if (p != "") dirs += p;
            try {
                string exe = FileUtils.read_link ("/proc/self/exe");
                string prefix = Path.get_dirname (Path.get_dirname (exe));
                foreach (string libdir in new string[] { "lib", "lib64", "lib/x86_64-linux-gnu", "lib/aarch64-linux-gnu" }) dirs += Path.build_filename (prefix, libdir, "singularity-keyframe", "plugins");
            } catch (Error e) {
            }
            dirs += Path.build_filename (Environment.get_user_data_dir (), "singularity-keyframe", "plugins");
            return dirs;
        }

        public Gee.List<KeyframeEffect.Plugin> loaded () {
            if (plugins == null) plugins = new Gee.ArrayList<KeyframeEffect.Plugin> ();
            return plugins;
        }

        public int load_all () {
            if (engine != null) return loaded ().size;
            plugins = new Gee.ArrayList<KeyframeEffect.Plugin> ();
            engine = new Peas.Engine ();
            foreach (var d in search_dirs ()) {
                if (!FileUtils.test (d, FileTest.IS_DIR)) continue;
                engine.add_search_path (d, d);
                try {
                    var dir = Dir.open (d);
                    string? name;
                    while ((name = dir.read_name ()) != null) {
                        string sub = Path.build_filename (d, name);
                        if (FileUtils.test (sub, FileTest.IS_DIR)) engine.add_search_path (sub, sub);
                    }
                } catch (Error e) {
                }
            }
            engine.rescan_plugins ();
            var model = (ListModel) engine;
            for (uint i = 0; i < model.get_n_items (); i++) {
                var info = (Peas.PluginInfo) model.get_item (i);
                if (!info.is_loaded ()) engine.load_plugin (info);
                if (!info.is_loaded () || !engine.provides_extension (info, typeof (KeyframeEffect.Plugin))) continue;
                var ext = engine.create_extension_with_properties (info, typeof (KeyframeEffect.Plugin), {}, {});
                if (ext == null) continue;
                var plugin = (KeyframeEffect.Plugin) ext;
                plugins.add (plugin);
                EffectRegistry.add (definition (plugin));
            }
            return plugins.size;
        }

        private Property make_property (KeyframeEffect.Param p) {
            var v = p.default_value;
            Property prop;
            switch (p.kind) {
                case KeyframeEffect.ParamKind.ANGLE: prop = Factory.angle (p.key, p.label, v.length > 0 ? v[0] : 0); break;
                case KeyframeEffect.ParamKind.PERCENT: prop = Factory.percent (p.key, p.label, v.length > 0 ? v[0] : 0); break;
                case KeyframeEffect.ParamKind.COLOR: prop = Factory.color (p.key, p.label, v.length >= 4 ? v : new double[] { 1, 1, 1, 1 }); break;
                case KeyframeEffect.ParamKind.POINT: prop = Factory.point (p.key, p.label, v.length >= 2 ? v : new double[] { 0, 0 }); break;
                case KeyframeEffect.ParamKind.TOGGLE: prop = Factory.toggle (p.key, p.label, v.length > 0 && v[0] > 0.5); break;
                default: prop = Factory.scalar (p.key, p.label, v.length > 0 ? v[0] : 0); break;
            }
            if (p.kind != KeyframeEffect.ParamKind.COLOR && p.kind != KeyframeEffect.ParamKind.POINT && p.kind != KeyframeEffect.ParamKind.TOGGLE) prop.range (p.min, p.max);
            return prop;
        }

        private double[] values_of (KeyframeEffect.Plugin plugin, PropGroup fx, double t, LayerBuffer? buf) {
            double[] values = {};
            foreach (var p in plugin.parameters ()) {
                var prop = fx.prop (p.key);
                var v = prop != null ? prop.value_at (t) : p.default_value;
                if (p.kind == KeyframeEffect.ParamKind.POINT && buf != null && v.length >= 2) {
                    double px, py;
                    buf.to_pixel (v[0], v[1], out px, out py);
                    values += px;
                    values += py;
                    for (int i = 2; i < v.length; i++) values += v[i];
                    continue;
                }
                foreach (var d in v) values += d;
            }
            return values;
        }

        private EffectDef definition (KeyframeEffect.Plugin plugin) {
            var def = new EffectDef (plugin.id, plugin.label, plugin.category, (g) => {
                foreach (var p in plugin.parameters ()) g.add<Property> (make_property (p));
            }, (ctx, fx, t) => {
                var values = values_of (plugin, fx, t, ctx.buf);
                var img = ctx.buf.img;
                plugin.render (img.data, img.width, img.height, ctx.buf.scale, values);
            }, (fx, t) => plugin.margin (values_of (plugin, fx, t, null)));
            def.from_plugin = true;
            return def;
        }
    }
}
