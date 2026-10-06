public class KeyframeChromaticAberration : Object, KeyframeEffect.Plugin {
    public string id { owned get { return "chromatic-aberration"; } }
    public string label { owned get { return _("Chromatic Aberration"); } }
    public string category { owned get { return _("Stylize"); } }

    public KeyframeEffect.Param[] parameters () {
        return {
            new KeyframeEffect.Param ("amount", _("Amount"), KeyframeEffect.ParamKind.SCALAR, { 4 }, 0, 200),
            new KeyframeEffect.Param ("angle", _("Angle"), KeyframeEffect.ParamKind.ANGLE, { 0 }),
            new KeyframeEffect.Param ("radial", _("Radial"), KeyframeEffect.ParamKind.TOGGLE, { 0 })
        };
    }

    public double margin (double[] values) {
        return values.length > 0 ? values[0].abs () : 0;
    }

    private static void sample (float[] src, int w, int h, double x, double y, int c, out float value, out float alpha) {
        double fx = x - 0.5, fy = y - 0.5;
        int x0 = (int) Math.floor (fx), y0 = (int) Math.floor (fy);
        double tx = fx - x0, ty = fy - y0;
        value = 0;
        alpha = 0;
        for (int j = 0; j < 2; j++)
            for (int i = 0; i < 2; i++) {
                int xx = x0 + i, yy = y0 + j;
                if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
                double wgt = (i == 0 ? 1 - tx : tx) * (j == 0 ? 1 - ty : ty);
                size_t o = ((size_t) yy * w + xx) * 4;
                value += (float) (src[o + c] * wgt);
                alpha += (float) (src[o + 3] * wgt);
            }
    }

    public void render (float[] rgba, int width, int height, double scale, double[] values) {
        double amount = (values.length > 0 ? values[0] : 4) * scale;
        double angle = (values.length > 1 ? values[1] : 0) * Math.PI / 180.0;
        bool radial = values.length > 2 && values[2] > 0.5;
        var src = rgba.copy ();
        double cx = width / 2.0, cy = height / 2.0, maxd = Math.hypot (cx, cy);
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                double dx, dy;
                if (radial) {
                    double vx = x + 0.5 - cx, vy = y + 0.5 - cy;
                    double d = Math.hypot (vx, vy);
                    dx = d > 0 ? vx / d * amount * d / maxd : 0;
                    dy = d > 0 ? vy / d * amount * d / maxd : 0;
                } else {
                    dx = Math.cos (angle) * amount;
                    dy = Math.sin (angle) * amount;
                }
                size_t o = ((size_t) y * width + x) * 4;
                float r, ra, g, ga, b, ba;
                sample (src, width, height, x + 0.5 - dx, y + 0.5 - dy, 0, out r, out ra);
                sample (src, width, height, x + 0.5, y + 0.5, 1, out g, out ga);
                sample (src, width, height, x + 0.5 + dx, y + 0.5 + dy, 2, out b, out ba);
                rgba[o] = r;
                rgba[o + 1] = g;
                rgba[o + 2] = b;
                rgba[o + 3] = float.max (ra, float.max (ga, ba));
            }
    }
}

[ModuleInit]
public void peas_register_types (TypeModule module) {
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type (typeof (KeyframeEffect.Plugin), typeof (KeyframeChromaticAberration));
}
