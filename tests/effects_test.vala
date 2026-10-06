using Singularity.Apps.Keyframe;
using Singularity.Apps.Keyframe.Test;
using Singularity.Imaging;

string outdir;
Project project;
Renderer renderer;

void reset () {
    project = new Project ();
    renderer = new Renderer (project);
}

Composition comp_of (int w, int h, double dur = 2) {
    var c = new Composition ("C", w, h, 30, dur);
    project.add_item (c);
    return c;
}

Layer solid (Composition c, int w, int h, double[] color, double x, double y) {
    var s = Factory.solid (c, "S", color, w, h);
    s.transform.prop ("position").value = { x, y, 0 };
    c.add_layer (s);
    return s;
}

FloatImage render (Composition c, double t = 0) {
    var rs = new RenderSettings ();
    rs.use_cache = false;
    return renderer.render (c, t, rs);
}

void save (FloatImage img, string name) {
    try {
        ImageIO.save_png (img, Path.build_filename (outdir, name + ".png"), 8, true);
    } catch (Error e) {
        check (false, "save " + e.message);
    }
}

float A (FloatImage img, int x, int y) {
    float r, g, b, a;
    img.get_pixel (x, y, out r, out g, out b, out a);
    return a;
}

float R (FloatImage img, int x, int y) {
    float r, g, b, a;
    img.get_pixel (x, y, out r, out g, out b, out a);
    return r;
}

float G (FloatImage img, int x, int y) {
    float r, g, b, a;
    img.get_pixel (x, y, out r, out g, out b, out a);
    return g;
}

float B (FloatImage img, int x, int y) {
    float r, g, b, a;
    img.get_pixel (x, y, out r, out g, out b, out a);
    return b;
}

Layer ramp_layer (Composition c, int w, int h) {
    var s = solid (c, w, h, { 1, 1, 1, 1 }, w / 2.0, h / 2.0);
    var ramp = EffectRegistry.add_to_layer (s, "gradient-ramp");
    ramp.prop ("start").value = { 0, 0, 0 };
    ramp.prop ("end").value = { w, 0, 0 };
    return s;
}

double image_diff (FloatImage a, FloatImage b) {
    double d = 0;
    for (size_t i = 0; i < a.data.length && i < b.data.length; i++) d += (a.data[i] - b.data[i]).abs ();
    return d;
}

void test_distort () {
    reset ();
    var c = comp_of (100, 50);
    var map = solid (c, 100, 50, { 1, 0.5, 0.5, 1 }, 50, 25);
    map.video = false;
    var target = solid (c, 20, 50, { 1, 1, 1, 1 }, 50, 25);
    var dm = EffectRegistry.add_to_layer (target, "displacement-map");
    dm.prop ("map").value = { c.index_of (map) };
    dm.prop ("max-horizontal").value = { 10 };
    dm.prop ("max-vertical").value = { 0 };
    var img = render (c);
    check (A (img, 35, 25) > 0.9, "displacement map pulls content left");
    check (A (img, 55, 25) < 0.1, "displacement map vacates right side");

    reset ();
    c = comp_of (100, 100);
    var band = solid (c, 100, 40, { 1, 1, 1, 1 }, 50, 50);
    var ww = EffectRegistry.add_to_layer (band, "wave-warp");
    ww.prop ("height").value = { 10 };
    ww.prop ("width").value = { 40 };
    img = render (c);
    float mn = 1, mx = 0;
    for (int x = 0; x < 100; x++) {
        mn = float.min (mn, A (img, x, 25));
        mx = float.max (mx, A (img, x, 25));
    }
    check (mn < 0.1 && mx > 0.9, "wave warp ripples the top edge");
    save (img, "wave-warp");

    reset ();
    c = comp_of (100, 50);
    var rl = ramp_layer (c, 100, 50);
    var base_img = render (c);
    var mir = EffectRegistry.add_to_layer (rl, "mirror");
    mir.prop ("center").value = { 50, 25, 0 };
    img = render (c);
    check (near (R (img, 90, 25), R (base_img, 10, 25), 0.03), "mirror reflects left half");
    check (near (R (img, 10, 25), R (base_img, 10, 25), 0.01), "mirror keeps left half");
    rl.effects.remove (mir);

    var td = EffectRegistry.add_to_layer (rl, "turbulent-displace");
    td.prop ("amount").value = { 80 };
    td.prop ("size").value = { 20 };
    img = render (c);
    check (image_diff (img, base_img) > 50, "turbulent displace changes the image");
    var again = render (c);
    check (image_diff (img, again) < 1e-3, "turbulent displace is deterministic");
    rl.effects.remove (td);

    var tw = EffectRegistry.add_to_layer (rl, "twirl");
    tw.prop ("center").value = { 50, 25, 0 };
    tw.prop ("radius").value = { 80 };
    tw.prop ("angle").value = { 180 };
    img = render (c);
    check (near (R (img, 50, 25), R (base_img, 50, 25), 0.03), "twirl centre stays");
    check ((R (img, 50, 12) - R (base_img, 50, 12)).abs () > 0.02, "twirl rotates around centre");
    rl.effects.remove (tw);

    var bg = EffectRegistry.add_to_layer (rl, "bulge");
    bg.prop ("center").value = { 50, 25, 0 };
    bg.prop ("horizontal-radius").value = { 30 };
    bg.prop ("vertical-radius").value = { 30 };
    bg.prop ("height").value = { 1 };
    img = render (c);
    check ((R (img, 62, 25) - R (base_img, 50, 25)).abs () < (R (base_img, 62, 25) - R (base_img, 50, 25)).abs (), "bulge magnifies toward centre");
    check (near (R (img, 95, 25), R (base_img, 95, 25), 0.01), "bulge leaves outside untouched");
    rl.effects.remove (bg);

    var of = EffectRegistry.add_to_layer (rl, "offset");
    of.prop ("shift").value = { 100, 25, 0 };
    img = render (c);
    check (near (R (img, 10, 25), R (base_img, 60, 25), 0.03), "offset wraps the image");
    rl.effects.remove (of);

    var pc = EffectRegistry.add_to_layer (rl, "polar-coordinates");
    img = render (c);
    check (image_diff (img, base_img) > 20 && A (img, 50, 25) > 0.9, "polar coordinates remaps");
    rl.effects.remove (pc);

    var sp = EffectRegistry.add_to_layer (rl, "spherize");
    sp.prop ("center").value = { 50, 25, 0 };
    sp.prop ("radius").value = { 20 };
    img = render (c);
    check ((R (img, 60, 25) - R (base_img, 60, 25)).abs () > 0.01, "spherize bends inside");
    check (near (R (img, 90, 25), R (base_img, 90, 25), 0.005), "spherize keeps outside");
    rl.effects.remove (sp);

    var oc = EffectRegistry.add_to_layer (rl, "optics-compensation");
    oc.prop ("fov").value = { 90 };
    oc.prop ("center").value = { 50, 25, 0 };
    img = render (c);
    check (near (R (img, 50, 25), R (base_img, 50, 25), 0.02), "optics centre stays");
    check ((R (img, 90, 25) - R (base_img, 90, 25)).abs () > 0.01, "optics bends edges");
    rl.effects.remove (oc);

    reset ();
    c = comp_of (90, 90);
    rl = ramp_layer (c, 90, 90);
    base_img = render (c);
    var mw = EffectRegistry.add_to_layer (rl, "mesh-warp");
    mw.group ("points").prop ("p1-1").value = { 10, 0 };
    img = render (c);
    check (near (R (img, 40, 30), R (base_img, 30, 30), 0.03), "mesh warp moves its vertex");
    check (near (R (img, 85, 85), R (base_img, 85, 85), 0.01), "mesh warp leaves far cells");
}

void test_time () {
    reset ();
    var inner = comp_of (100, 20);
    var box = solid (inner, 10, 10, { 1, 1, 1, 1 }, 5, 10);
    box.transform.prop ("position").set_key (0, { 5, 10, 0 });
    box.transform.prop ("position").set_key (1, { 95, 10, 0 });
    var c = comp_of (100, 20);
    var pre = Factory.precomp_layer (c, inner);
    pre.transform.prop ("position").value = { 50, 10, 0 };
    c.add_layer (pre);
    var echo = EffectRegistry.add_to_layer (pre, "echo");
    echo.prop ("time").value = { -0.2 };
    echo.prop ("count").value = { 2 };
    echo.prop ("decay").value = { 0.5 };
    var img = render (c, 0.5);
    check (A (img, 50, 10) > 0.9, "echo keeps current frame");
    check (A (img, 32, 10) > 0.2 && A (img, 32, 10) < 0.9, "echo shows a decayed earlier copy");
    check (A (img, 14, 10) > 0.1, "echo shows a second copy");
    save (img, "echo");
    pre.effects.remove (echo);

    var pt = EffectRegistry.add_to_layer (pre, "posterize-time");
    pt.prop ("fps").value = { 2 };
    img = render (c, 0.4);
    check (A (img, 5, 10) > 0.9 && A (img, 45, 10) < 0.1, "posterize time holds the earlier frame");
    pre.effects.remove (pt);

    var map = solid (c, 100, 20, { 1, 1, 1, 1 }, 50, 10);
    map.video = false;
    c.move_layer (map, c.layers.size - 1);
    var tdisp = EffectRegistry.add_to_layer (pre, "time-displacement");
    tdisp.prop ("map").value = { c.index_of (map) };
    tdisp.prop ("max-time").value = { 0.5 };
    img = render (c, 0.0);
    check (A (img, 50, 10) > 0.9 && A (img, 5, 10) < 0.1, "time displacement shows the future frame");

    reset ();
    var dir = tmp_dir ();
    var vpath = Path.build_filename (dir, "clip.webm");
    try {
        var pipe = Gst.parse_launch ("videotestsrc num-buffers=6 pattern=smpte ! video/x-raw,width=64,height=32,framerate=5/1 ! videoconvert ! vp8enc deadline=1 ! webmmux ! filesink name=out") as Gst.Pipeline;
        pipe.get_by_name ("out").set ("location", vpath);
        pipe.set_state (Gst.State.PLAYING);
        pipe.get_bus ().timed_pop_filtered (20 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
        pipe.set_state (Gst.State.NULL);
        var f = MediaPool.probe (vpath);
        project.add_item (f);
        c = comp_of (64, 32, 1);
        var vl = Factory.footage_layer (c, f);
        c.add_layer (vl);
        var pool = renderer.media;
        var a = pool.frame (f, 0.0);
        var b = pool.frame (f, 0.2);
        var mid = pool.blended_frame (f, 0.1, 30);
        check (a != null && b != null && mid != null, "video frames decode");
        if (a != null && b != null && mid != null) {
            double da = image_diff (mid, a), db = image_diff (mid, b), dab = image_diff (a, b);
            check (dab > 1 && da > dab * 0.2 && db > dab * 0.2, "frame blending mixes neighbouring frames");
        }
    } catch (Error e) {
        check (false, "video fixture " + e.message);
    }
}

void test_generate () {
    reset ();
    var c = comp_of (80, 60);
    var s = solid (c, 80, 60, { 0, 0, 0, 1 }, 40, 30);
    var fn = EffectRegistry.add_to_layer (s, "fractal-noise");
    var img = render (c);
    float mn = 1, mx = 0;
    for (int x = 0; x < 80; x++) {
        mn = float.min (mn, R (img, x, 30));
        mx = float.max (mx, R (img, x, 30));
    }
    check (mx - mn > 0.1 && A (img, 3, 3) > 0.99, "fractal noise varies and is opaque");
    check (image_diff (img, render (c)) < 1e-4, "fractal noise is deterministic");
    var before = img;
    fn.prop ("evolution").value = { 90 };
    check (image_diff (render (c), before) > 1, "evolution changes the noise");
    fn.prop ("cycle").value = { 1 };
    fn.prop ("evolution").value = { 0 };
    var e0 = render (c);
    fn.prop ("evolution").value = { 360 };
    check (image_diff (render (c), e0) < 0.5, "cycled evolution loops seamlessly");
    save (e0, "fractal-noise");
    s.effects.remove (fn);

    var cp = EffectRegistry.add_to_layer (s, "cell-pattern");
    cp.prop ("size").value = { 20 };
    img = render (c);
    mn = 1;
    mx = 0;
    for (int x = 0; x < 80; x++) {
        mn = float.min (mn, R (img, x, 30));
        mx = float.max (mx, R (img, x, 30));
    }
    check (mx - mn > 0.2, "cell pattern produces cells");
    save (img, "cell-pattern");
    s.effects.remove (cp);

    var grid = EffectRegistry.add_to_layer (s, "grid");
    grid.prop ("width").value = { 20 };
    grid.prop ("height").value = { 20 };
    grid.prop ("border").value = { 2 };
    grid.prop ("blend").value = { 0 };
    img = render (c);
    check (A (img, 20, 30) > 0.9 && R (img, 20, 30) > 0.9, "grid line drawn");
    check (A (img, 10, 10) < 0.05, "grid cell empty");
    s.effects.remove (grid);

    var cb = EffectRegistry.add_to_layer (s, "checkerboard");
    cb.prop ("width").value = { 10 };
    cb.prop ("height").value = { 10 };
    img = render (c);
    check (A (img, 5, 5) > 0.9 && A (img, 15, 5) < 0.1 && A (img, 15, 15) > 0.9, "checkerboard alternates");
    s.effects.remove (cb);

    var ci = EffectRegistry.add_to_layer (s, "circle");
    ci.prop ("center").value = { 40, 30, 0 };
    ci.prop ("radius").value = { 15 };
    ci.prop ("blend").value = { 0 };
    img = render (c);
    check (A (img, 40, 30) > 0.99 && A (img, 5, 5) < 0.01, "circle inside and outside");
    ci.prop ("edge").value = { 1 };
    ci.prop ("thickness").value = { 4 };
    img = render (c);
    check (A (img, 40, 30) < 0.01 && A (img, 53, 30) > 0.9, "circle ring");
    s.effects.remove (ci);

    var el = EffectRegistry.add_to_layer (s, "ellipse");
    el.prop ("center").value = { 40, 30, 0 };
    el.prop ("width").value = { 60 };
    el.prop ("height").value = { 40 };
    el.prop ("composite").value = { 0 };
    img = render (c);
    check (A (img, 70, 30) > 0.9 && A (img, 40, 30) < 0.2, "ellipse ring on outline");
    s.effects.remove (el);

    var fc = EffectRegistry.add_to_layer (s, "four-color-gradient");
    fc.prop ("point1").value = { 0, 0, 0 };
    fc.prop ("point2").value = { 80, 0, 0 };
    fc.prop ("point3").value = { 0, 60, 0 };
    fc.prop ("point4").value = { 80, 60, 0 };
    img = render (c);
    check (R (img, 1, 1) > 0.8 && G (img, 1, 1) > 0.8 && B (img, 1, 1) < 0.2, "4-color corner 1 is yellow");
    check (B (img, 78, 58) > 0.8 && R (img, 78, 58) < 0.2, "4-color corner 4 is blue");
    s.effects.remove (fc);

    var lr = solid (c, 80, 60, { 0, 0, 0, 0 }, 40, 30);
    var dot = EffectRegistry.add_to_layer (lr, "circle");
    dot.prop ("center").value = { 40, 30, 0 };
    dot.prop ("radius").value = { 5 };
    dot.prop ("blend").value = { 0 };
    img = render (c);
    float before_ray = R (img, 40, 45);
    var rays = EffectRegistry.add_to_layer (lr, "light-rays");
    rays.prop ("center").value = { 40, 10, 0 };
    rays.prop ("radius").value = { 60 };
    img = render (c);
    check (R (img, 40, 45) > before_ray + 0.02, "light rays streak away from the centre");
    save (img, "light-rays");
    lr.effects.children.clear ();

    var lt = EffectRegistry.add_to_layer (lr, "lightning");
    lt.prop ("origin").value = { 5, 30, 0 };
    lt.prop ("direction").value = { 75, 30, 0 };
    lt.prop ("glow-radius").value = { 4 };
    img = render (c);
    int lit = 0;
    for (int x = 10; x < 70; x++) {
        float best = 0;
        for (int y = 0; y < 60; y++) best = float.max (best, R (img, x, y));
        if (best > 0.5) lit++;
    }
    check (lit > 50, "lightning spans origin to direction");
    check (R (img, 40, 2) < 0.2 || R (img, 40, 58) < 0.2, "lightning stays a narrow bolt");
    save (img, "lightning");
}

string green_screen_png () {
    int w = 80, h = 60;
    var img = new FloatImage (w, h);
    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++) {
            double d = Math.hypot (x - 40, y - 30);
            double cover = (20.5 - d).clamp (0, 1.5) / 1.5;
            double gr = Transfer.srgb_to_linear (0.15f), gg = Transfer.srgb_to_linear (0.78f), gb = Transfer.srgb_to_linear (0.2f);
            double sr = Transfer.srgb_to_linear (0.9f), sg = Transfer.srgb_to_linear (0.55f), sb = Transfer.srgb_to_linear (0.4f);
            double spill = d > 15 && d < 20.5 ? 0.25 : 0;
            sg = sg + (gg - sg) * spill;
            double r = sr * cover + gr * (1 - cover), g = sg * cover + gg * (1 - cover), b = sb * cover + gb * (1 - cover);
            img.set_pixel (x, y, (float) r, (float) g, (float) b, 1);
        }
    var path = Path.build_filename (outdir, "greenscreen-src.png");
    try {
        ImageIO.save_png (img, path, 16, false);
    } catch (Error e) {
        check (false, "green screen " + e.message);
    }
    return path;
}

void test_keying () {
    reset ();
    var path = green_screen_png ();
    Footage f;
    try {
        f = MediaPool.probe (path);
    } catch (Error e) {
        check (false, "probe " + e.message);
        return;
    }
    project.add_item (f);
    var c = comp_of (80, 60);
    var l = Factory.footage_layer (c, f);
    c.add_layer (l);

    var kl = EffectRegistry.add_to_layer (l, "keylight");
    var img = render (c);
    save (img, "keylight");
    check (A (img, 3, 3) < 0.05, "keylight removes the screen");
    check (A (img, 40, 30) > 0.95, "keylight keeps the subject");
    float edge = A (img, 40 + 20, 30);
    check (edge > 0.05 && edge < 0.95, "keylight soft edge is partial");
    float spill_g = G (img, 40 + 17, 30), spill_r = R (img, 40 + 17, 30);
    check (spill_g <= spill_r * 1.05, "keylight despill limits green on the subject edge");
    kl.prop ("view").value = { 2 };
    var status = render (c);
    check (near (R (status, 3, 3), 0, 0.01) && near (R (status, 40, 30), 1, 0.01), "status view shows black and white");
    kl.prop ("clip-black").value = { 30 };
    kl.prop ("view").value = { 1 };
    var matte = render (c);
    check (R (matte, 3, 3) < 0.01 && R (matte, 40, 30) > 0.99, "combined matte view");
    l.effects.remove (kl);

    var ck = EffectRegistry.add_to_layer (l, "color-key");
    ck.prop ("key-color").value = { Transfer.srgb_to_linear (0.15f), Transfer.srgb_to_linear (0.78f), Transfer.srgb_to_linear (0.2f), 1 };
    ck.prop ("tolerance").value = { 30 };
    img = render (c);
    check (A (img, 3, 3) < 0.01 && A (img, 40, 30) > 0.99, "color key");
    ck.prop ("edge-feather").value = { 4 };
    img = render (c);
    check (A (img, 40 + 21, 30) > 0.05 && A (img, 40 + 21, 30) < 0.95, "color key edge feather");
    l.effects.remove (ck);

    var lk = EffectRegistry.add_to_layer (l, "linear-color-key");
    lk.prop ("key-color").value = { Transfer.srgb_to_linear (0.15f), Transfer.srgb_to_linear (0.78f), Transfer.srgb_to_linear (0.2f), 1 };
    lk.prop ("space").value = { 1 };
    img = render (c);
    check (A (img, 3, 3) < 0.05 && A (img, 40, 30) > 0.95, "linear color key by hue");
    lk.prop ("operation").value = { 1 };
    img = render (c);
    check (A (img, 3, 3) > 0.95 && A (img, 40, 30) < 0.05, "linear color key keep colors");
    l.effects.remove (lk);

    var luk = EffectRegistry.add_to_layer (l, "luma-key");
    luk.prop ("type").value = { 0 };
    luk.prop ("threshold").value = { 150 };
    img = render (c);
    check (A (img, 3, 3) > 0.9 && A (img, 40, 30) < 0.05, "luma key brighter");
    l.effects.remove (luk);

    var ss = EffectRegistry.add_to_layer (l, "spill-suppressor");
    img = render (c);
    check (G (img, 3, 3) < Transfer.srgb_to_linear (0.78f) * 0.6, "spill suppressor removes green excess");
    l.effects.remove (ss);

    var ck2 = EffectRegistry.add_to_layer (l, "color-key");
    ck2.prop ("key-color").value = { Transfer.srgb_to_linear (0.15f), Transfer.srgb_to_linear (0.78f), Transfer.srgb_to_linear (0.2f), 1 };
    ck2.prop ("tolerance").value = { 30 };
    var mr = EffectRegistry.add_to_layer (l, "matte-refine");
    mr.prop ("choke").value = { 5 };
    img = render (c);
    check (A (img, 40 + 17, 30) < 0.05 && A (img, 40, 30) > 0.95, "matte refine chokes the edge");
}

void test_particles () {
    reset ();
    var c = comp_of (200, 120, 3);
    var s = solid (c, 200, 120, { 0, 0, 0, 0 }, 100, 60);
    var pw = EffectRegistry.add_to_layer (s, "particle-world");
    pw.prop ("position").value = { 100, 20, 0 };
    pw.prop ("floor").value = { 1 };
    pw.prop ("floor-y").value = { 100 };
    pw.prop ("gravity").value = { 400 };
    pw.prop ("birth-rate").value = { 4 };
    pw.prop ("longevity").value = { 3 };
    var a = render (c, 1.5);
    int steps_after_first = Particles.simulated_steps;
    var b = render (c, 1.5);
    check (Particles.simulated_steps == steps_after_first, "particle state cache reuses simulated frames");
    check (image_diff (a, b) < 1e-4, "particles render identically twice");
    Particles.clear_cache ();
    var fresh = render (c, 1.5);
    check (image_diff (a, fresh) < 1e-4, "particles deterministic from a cold cache");
    var st = Particles.simulate (s, pw, s.layer_time (1.5), c.fps);
    check (st.count > 20, "particles emitted");
    double maxy = -1e9;
    for (int i = 0; i < st.count; i++) maxy = double.max (maxy, st.y[i]);
    check (maxy <= 100.001, "particles never pass the floor");
    int below = 0;
    for (int y = 105; y < 120; y++)
        for (int x = 0; x < 200; x++) if (A (a, x, y) > 0.05) below++;
    check (below == 0, "nothing rendered below the floor");
    int seen = 0;
    for (size_t i = 0; i < a.pixel_count (); i++) if (a.data[i * 4 + 3] > 0.1f) seen++;
    check (seen > 50, "particles visible");
    save (a, "particles");
    var early = render (c, 0.5);
    check (image_diff (early, a) > 1, "particles evolve over time");
}

void test_puppet () {
    reset ();
    var c = comp_of (120, 100);
    var s = solid (c, 100, 20, { 1, 1, 1, 1 }, 60, 30);
    var pup = EffectRegistry.add_to_layer (s, "puppet");
    Puppet.add_pin (pup, 5, 10);
    var right = Puppet.add_pin (pup, 95, 10);
    check (Puppet.pins (pup).size == 2, "pins listed");
    right.prop ("position").value = { 95, 50 };
    var img = render (c);
    save (img, "puppet");
    check (A (img, 15, 30) > 0.9, "fixed pin keeps the left end");
    check (A (img, 105, 30) < 0.1, "moved pin vacates the old right end");
    check (A (img, 105, 70) > 0.9, "moved pin drags the right end down");
}

string write_gltf () {
    float[] pos = {
        -0.5f, -0.5f, 0.5f, 0.5f, -0.5f, 0.5f, 0.5f, 0.5f, 0.5f, -0.5f, 0.5f, 0.5f,
        -1.0f, -0.25f, 0.0f, 1.0f, -0.25f, 0.0f, 1.0f, 0.25f, 0.0f, -1.0f, 0.25f, 0.0f
    };
    uint16[] idx = { 0, 1, 2, 0, 2, 3, 0, 1, 2, 0, 2, 3 };
    var bin = new ByteArray ();
    unowned uint8[] pb = (uint8[]) pos;
    pb.length = pos.length * 4;
    bin.append (pb);
    unowned uint8[] ib = (uint8[]) idx;
    ib.length = idx.length * 2;
    bin.append (ib);
    string b64 = Base64.encode (bin.data);
    string json = """{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0,1]}],
"nodes":[{"mesh":0},{"mesh":1}],
"meshes":[{"primitives":[{"attributes":{"POSITION":0},"indices":2,"material":0}]},{"primitives":[{"attributes":{"POSITION":1},"indices":3,"material":1}]}],
"materials":[{"pbrMetallicRoughness":{"baseColorFactor":[1,0,0,1]}},{"pbrMetallicRoughness":{"baseColorFactor":[0,0,1,1]}}],
"buffers":[{"byteLength":%d,"uri":"data:application/octet-stream;base64,%s"}],
"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":96},{"buffer":0,"byteOffset":96,"byteLength":24}],
"accessors":[{"bufferView":0,"byteOffset":0,"componentType":5126,"count":4,"type":"VEC3"},{"bufferView":0,"byteOffset":48,"componentType":5126,"count":4,"type":"VEC3"},
{"bufferView":1,"byteOffset":0,"componentType":5123,"count":6,"type":"SCALAR"},{"bufferView":1,"byteOffset":12,"componentType":5123,"count":6,"type":"SCALAR"}]}""".printf ((int) bin.len, b64);
    var path = Path.build_filename (outdir, "planes.gltf");
    try {
        FileUtils.set_contents (path, json);
    } catch (Error e) {
        check (false, "gltf write " + e.message);
    }
    return path;
}

void test_model () {
    reset ();
    var path = write_gltf ();
    Footage f;
    try {
        f = MediaPool.probe (path);
    } catch (Error e) {
        check (false, "probe gltf " + e.message);
        return;
    }
    check (f.kind == FootageKind.MODEL, "gltf probes as a model");
    project.add_item (f);
    var c = comp_of (320, 180);
    var l = Factory.footage_layer (c, f);
    c.add_layer (l);
    check (l.kind == LayerKind.MODEL && l.three_d, "model layer is 3D");
    var model = ModelRender.model_for (path);
    check (model != null && model.meshes.size == 2 && model.triangle_count () == 4, "gltf meshes parsed");
    var img = render (c);
    save (img, "model");
    check (A (img, 160, 90) > 0.99, "model covers the centre");
    check (R (img, 160, 90) > 0.2 && B (img, 160, 90) < 0.05, "nearer red plane wins the depth test");
    check (B (img, 160 + 80, 90) > 0.2 && R (img, 160 + 80, 90) < 0.05, "blue plane visible beside it");
    check (A (img, 160, 10) < 0.01, "model leaves empty space");
    l.root.group ("model").prop ("tint").value = { 0, 1, 0, 1 };
    img = render (c);
    check (R (img, 160, 90) < 0.01 && B (img, 160 + 80, 90) < 0.01, "tint multiplies colour");
}

int main (string[] args) {
    Gst.init (ref args);
    outdir = out_dir ();
    test_distort ();
    test_time ();
    test_generate ();
    test_keying ();
    test_particles ();
    test_puppet ();
    test_model ();
    print ("output in %s\n", outdir);
    return finish ("keyframe-effects");
}
