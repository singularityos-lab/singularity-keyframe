using Singularity.Apps.Keyframe;

int failures = 0;

void check (bool cond, string what) {
    if (!cond) {
        stderr.printf ("FAIL: %s\n", what);
        failures++;
    }
}

int main (string[] args) {
    Gst.init (ref args);
    int n = EffectPlugins.load_all ();
    check (n >= 1, "sample plugin loaded");
    var def = EffectRegistry.get ("chromatic-aberration");
    check (def != null && def.from_plugin, "plugin registered as effect");
    if (def != null) {
        var p = new Project ();
        var comp = new Composition ("P", 40, 20, 30, 1);
        p.add_item (comp);
        var s = Factory.solid (comp, "W", { 1, 1, 1, 1 }, 10, 10);
        s.transform.prop ("position").value = { 20, 10, 0 };
        comp.add_layer (s);
        var fx = EffectRegistry.add_to_layer (s, "chromatic-aberration");
        check (fx != null && fx.prop ("amount") != null, "plugin params become properties");
        fx.prop ("amount").value = { 3 };
        var r = new Renderer (p);
        var rs = new RenderSettings ();
        rs.use_cache = false;
        var img = r.render (comp, 0, rs);
        float cr, cg, cb, ca;
        img.get_pixel (16, 10, out cr, out cg, out cb, out ca);
        check (cb > 0.5 && cr < 0.1, "left edge shows blue fringe");
        img.get_pixel (23, 10, out cr, out cg, out cb, out ca);
        check (cr > 0.5 && cb < 0.1, "right edge shows red fringe");
    }
    if (failures > 0) {
        stderr.printf ("keyframe-plugin: %d failure(s)\n", failures);
        return 1;
    }
    print ("keyframe-plugin: ok\n");
    return 0;
}
