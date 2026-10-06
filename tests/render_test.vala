using Singularity.Apps.Keyframe;
using Singularity.Apps.Keyframe.Test;
using Singularity.Imaging;

string outdir;

void save (FloatImage img, string name) {
    try {
        ImageIO.save_png (img, Path.build_filename (outdir, name + ".png"), 8, true);
    } catch (Error e) {
        check (false, "save " + e.message);
    }
}

void px (FloatImage img, int x, int y, out float r, out float g, out float b, out float a) {
    img.get_pixel (x, y, out r, out g, out b, out a);
}

void test_solid_and_transform () {
    var p = new Project ();
    var comp = new Composition ("Main", 200, 100, 30, 2);
    p.add_item (comp);
    var s = Factory.solid (comp, "Red", { 1, 0, 0, 1 }, 50, 50);
    s.transform.prop ("position").value = { 100, 50, 0 };
    comp.add_layer (s);
    var r = new Renderer (p);
    var img = r.render (comp, 0, new RenderSettings ());
    float cr, cg, cb, ca;
    px (img, 100, 50, out cr, out cg, out cb, out ca);
    check (near (cr, 1) && near (ca, 1), "solid centre red");
    px (img, 10, 10, out cr, out cg, out cb, out ca);
    check (near (ca, 0), "outside transparent");
    s.transform.prop ("rotation").set_value ({ 45 });
    img = r.render (comp, 0, new RenderSettings ());
    px (img, 100, 50 - 33, out cr, out cg, out cb, out ca);
    check (ca > 0.9, "rotated solid reaches diagonal");
    s.transform.prop ("opacity").set_value ({ 50 });
    img = r.render (comp, 0, new RenderSettings ());
    px (img, 100, 50, out cr, out cg, out cb, out ca);
    check (near (ca, 0.5, 0.01), "opacity halves alpha");
    var half = new RenderSettings ();
    half.downsample = 2;
    img = r.render (comp, 0, half);
    check (img.width == 100 && img.height == 50, "half resolution preview size");
    var roi = new RenderSettings ();
    roi.roi = true;
    roi.roi_x = 80;
    roi.roi_y = 30;
    roi.roi_w = 40;
    roi.roi_h = 40;
    img = r.render (comp, 0, roi);
    check (img.width == 40 && img.height == 40, "roi size");
    px (img, 20, 20, out cr, out cg, out cb, out ca);
    check (near (cr, ca) && ca > 0.4, "roi samples centre");
}

Composition build_demo (Project p) {
    var comp = new Composition ("Demo", 480, 270, 30, 3);
    comp.background = { 0.05, 0.05, 0.08, 1 };
    p.add_item (comp);
    var bg = Factory.solid (comp, "Background", { 0.08, 0.1, 0.2, 1 });
    bg.blend = BlendMode.NORMAL;
    var ramp = EffectRegistry.add_to_layer (bg, "gradient-ramp");
    ramp.prop ("start").value = { 0, 0, 0 };
    ramp.prop ("end").value = { 480, 270, 0 };
    ramp.prop ("start-color").value = { 0.02, 0.03, 0.1, 1 };
    ramp.prop ("end-color").value = { 0.25, 0.05, 0.2, 1 };
    comp.add_layer (bg, comp.layers.size);
    var shape = Factory.shape_layer (comp, "Stars");
    var grp = Factory.shape_group ("Star");
    var c = grp.group ("contents");
    c.add<PropGroup> (Factory.star (false, 5, 40, 18));
    var fill = Factory.fill ({ 1.0, 0.55, 0.1, 1 });
    c.add<PropGroup> (fill);
    var stroke = Factory.stroke ({ 1, 1, 1, 1 }, 3);
    c.add<PropGroup> (stroke);
    shape.contents.add<PropGroup> (grp);
    var rep = Factory.repeater (4);
    rep.group ("transform").prop ("position").value = { 100, 0 };
    rep.group ("transform").prop ("rotation").value = { 20 };
    rep.group ("transform").prop ("end-opacity").value = { 30 };
    shape.contents.add<PropGroup> (rep);
    shape.transform.prop ("position").value = { 90, 135, 0 };
    shape.transform.prop ("rotation").set_key (0, { 0 });
    shape.transform.prop ("rotation").set_key (3, { 180 });
    shape.motion_blur = true;
    comp.add_layer (shape);
    var line = Factory.shape_layer (comp, "Line");
    var lg = Factory.shape_group ("Wave");
    var path = new BezPath ();
    path.closed = false;
    path.add (-200, 0, 0, 0, 60, -80);
    path.add (0, 0, -60, 80, 60, -80);
    path.add (200, 0, -60, 80, 0, 0);
    lg.group ("contents").add<PropGroup> (Factory.path_shape (path));
    var ls = Factory.stroke ({ 0.3, 0.9, 1, 1 }, 6);
    ls.attrs["cap"] = "round";
    lg.group ("contents").add<PropGroup> (ls);
    var trim = Factory.trim ();
    trim.prop ("end").set_key (0, { 0 });
    trim.prop ("end").set_key (2, { 100 });
    lg.group ("contents").add<PropGroup> (trim);
    line.contents.add<PropGroup> (lg);
    line.transform.prop ("position").value = { 240, 220, 0 };
    comp.add_layer (line);
    var text = Factory.text_layer (comp, "Keyframe");
    var doc = text.text_group.prop ("source-text").text;
    doc.size = 48;
    doc.weight = 700;
    doc.fill = { 1, 1, 1, 1 };
    text.transform.prop ("position").value = { 240, 70, 0 };
    var an = Factory.text_animator ("Animator 1");
    an.group ("selectors").add<PropGroup> (Factory.range_selector ());
    var op = Factory.animator_property ("opacity");
    op.value = { 0 };
    an.group ("properties").add<Property> (op);
    var ap = Factory.animator_property ("position");
    ap.value = { 0, 40 };
    an.group ("properties").add<Property> (ap);
    var sel = an.group ("selectors").child ("range-selector") as PropGroup;
    sel.prop ("start").set_key (0, { 0 });
    sel.prop ("start").set_key (1.5, { 100 });
    text.text_group.group ("animators").add<PropGroup> (an);
    var glow = EffectRegistry.add_to_layer (text, "drop-shadow");
    glow.prop ("distance").value = { 4 };
    glow.prop ("softness").value = { 6 };
    comp.add_layer (text);
    return comp;
}

void test_demo () {
    var p = new Project ();
    var comp = build_demo (p);
    var r = new Renderer (p);
    var s = new RenderSettings ();
    s.use_cache = false;
    var f0 = r.render (comp, 0.0, s);
    var f1 = r.render (comp, 1.0, s);
    var f2 = r.render (comp, 2.0, s);
    save (f0, "demo-0");
    save (f1, "demo-1");
    save (f2, "demo-2");
    float cr, cg, cb, ca;
    px (f2, 90, 135, out cr, out cg, out cb, out ca);
    check (cr > 0.5 && ca > 0.99, "star rendered at its position");
    px (f0, 240, 60, out cr, out cg, out cb, out ca);
    float before = cr;
    px (f2, 240, 60, out cr, out cg, out cb, out ca);
    check (cr >= before, "text animates in");
    double diff = 0;
    for (size_t i = 0; i < f0.data.length; i++) diff += (f0.data[i] - f2.data[i]).abs ();
    check (diff > 100, "frames differ over time");
}

void test_masks_and_mattes () {
    var p = new Project ();
    var comp = new Composition ("M", 100, 100, 30, 1);
    p.add_item (comp);
    var s = Factory.solid (comp, "White", { 1, 1, 1, 1 });
    var mask = Factory.mask (BezPath.rect (25, 25, 50, 50));
    s.masks.add<PropGroup> (mask);
    comp.add_layer (s);
    var r = new Renderer (p);
    var rs = new RenderSettings ();
    rs.use_cache = false;
    var img = r.render (comp, 0, rs);
    float cr, cg, cb, ca;
    px (img, 50, 50, out cr, out cg, out cb, out ca);
    check (near (ca, 1), "inside mask");
    px (img, 10, 10, out cr, out cg, out cb, out ca);
    check (near (ca, 0), "outside mask");
    mask.attrs["inverted"] = "true";
    img = r.render (comp, 0, rs);
    px (img, 10, 10, out cr, out cg, out cb, out ca);
    check (near (ca, 1), "inverted mask");
    mask.attrs["inverted"] = "false";
    mask.prop ("feather").value = { 20, 20 };
    img = r.render (comp, 0, rs);
    px (img, 25, 50, out cr, out cg, out cb, out ca);
    check (ca > 0.3 && ca < 0.7, "feathered edge is soft");
    mask.prop ("feather").value = { 0, 0 };
    mask.prop ("expansion").value = { 10 };
    img = r.render (comp, 0, rs);
    px (img, 20, 50, out cr, out cg, out cb, out ca);
    check (ca > 0.9, "expansion grows the mask");
    mask.prop ("expansion").value = { 0 };
    var sub = Factory.mask (BezPath.rect (40, 40, 20, 20), "subtract");
    s.masks.add<PropGroup> (sub);
    img = r.render (comp, 0, rs);
    px (img, 50, 50, out cr, out cg, out cb, out ca);
    check (near (ca, 0), "subtract mask");
    s.masks.remove (sub);
    var vf = Factory.mask (BezPath.rect (20, 20, 60, 60));
    vf.prop ("feather").value = { 10, 10 };
    vf.prop ("variable-feather").value = { 1 };
    var vp = vf.prop ("path").path;
    vp.v[0].feather = 0;
    vp.v[1].feather = 0;
    vp.v[2].feather = 3;
    vp.v[3].feather = 3;
    s.masks.children.clear ();
    s.masks.add<PropGroup> (vf);
    img = r.render (comp, 0, rs);
    float top_a, bottom_a;
    px (img, 50, 21, out cr, out cg, out cb, out top_a);
    px (img, 50, 79, out cr, out cg, out cb, out bottom_a);
    check (top_a > bottom_a + 0.1, "variable feather softer where vertices request it");
    save (img, "variable-feather");

    var comp2 = new Composition ("Matte", 100, 100, 30, 1);
    p.add_item (comp2);
    var fillr = Factory.solid (comp2, "Fill", { 0, 1, 0, 1 });
    var matte = Factory.shape_layer (comp2, "Matte");
    var g = Factory.shape_group ("C");
    g.group ("contents").add<PropGroup> (Factory.ellipse (40, 40));
    g.group ("contents").add<PropGroup> (Factory.fill ({ 1, 1, 1, 1 }));
    matte.contents.add<PropGroup> (g);
    matte.transform.prop ("position").value = { 50, 50, 0 };
    comp2.add_layer (fillr);
    comp2.add_layer (matte);
    fillr.matte_mode = MatteMode.ALPHA;
    img = r.render (comp2, 0, rs);
    px (img, 50, 50, out cr, out cg, out cb, out ca);
    check (near (cg, 1, 0.01) && near (ca, 1), "alpha matte keeps centre");
    px (img, 5, 5, out cr, out cg, out cb, out ca);
    check (near (ca, 0), "alpha matte cuts outside and hides matte");
    fillr.matte_mode = MatteMode.LUMA_INVERTED;
    img = r.render (comp2, 0, rs);
    px (img, 50, 50, out cr, out cg, out cb, out ca);
    if (ca >= 0.05) stderr.printf ("luma inv %f %f %f %f\n", cr, cg, cb, ca);
    check (ca < 0.05, "inverted luma matte");
}

void test_precomp_adjustment_blend () {
    var p = new Project ();
    var inner = new Composition ("Inner", 50, 50, 30, 2);
    p.add_item (inner);
    var blue = Factory.solid (inner, "Blue", { 0, 0, 1, 1 }, 20, 20);
    blue.transform.prop ("position").set_key (0, { 10, 25, 0 });
    blue.transform.prop ("position").set_key (1, { 40, 25, 0 });
    inner.add_layer (blue);
    var outer = new Composition ("Outer", 100, 100, 30, 2);
    p.add_item (outer);
    var pre = Factory.precomp_layer (outer, inner);
    pre.transform.prop ("position").value = { 50, 50, 0 };
    pre.start_time = 0.5;
    outer.add_layer (pre);
    var r = new Renderer (p);
    var img = r.render (outer, 0.5, new RenderSettings ());
    float cr, cg, cb, ca;
    px (img, 35, 50, out cr, out cg, out cb, out ca);
    check (near (cb, 1) && near (ca, 1), "precomp time offset shows first frame");
    check (r.cache.contains (inner.id, 0, "1|1|0"), "nested comp cached per frame");
    blue.transform.prop ("position").set_key (0, { 12, 25, 0 });
    check (!r.cache.contains (outer.id, 15, "1|1|0"), "parent cache invalidated by nested change");
    var adj = Factory.adjustment (outer);
    EffectRegistry.add_to_layer (adj, "invert");
    outer.add_layer (adj);
    img = r.render (outer, 0.5, new RenderSettings ());
    px (img, 37, 50, out cr, out cg, out cb, out ca);
    check (cr > 0.9 && cg > 0.9 && cb < 0.1, "adjustment layer inverts below");
    outer.remove_layer (adj);
    var top = Factory.solid (outer, "Grey", { 0.5, 0.5, 0.5, 1 });
    top.blend = BlendMode.MULTIPLY;
    outer.add_layer (top);
    img = r.render (outer, 0.5, new RenderSettings ());
    px (img, 37, 50, out cr, out cg, out cb, out ca);
    check (cb < 0.9 && cb > 0.1, "multiply blend darkens");
}

void test_3d_and_motion_blur () {
    var p = new Project ();
    var comp = new Composition ("3D", 320, 180, 30, 2);
    p.add_item (comp);
    var floor = Factory.solid (comp, "Card", { 1, 1, 1, 1 }, 200, 200);
    floor.three_d = true;
    floor.transform.prop ("rotation-y").value = { 60 };
    comp.add_layer (floor);
    var r = new Renderer (p);
    var rs = new RenderSettings ();
    rs.use_cache = false;
    var flat = r.render (comp, 0, rs);
    float cr, cg, cb, ca;
    px (flat, 160, 90, out cr, out cg, out cb, out ca);
    check (ca > 0.99, "3d card visible");
    px (flat, 160 - 95, 90, out cr, out cg, out cb, out ca);
    check (ca < 0.01, "y rotation foreshortens the card");
    var cam = Factory.camera (comp, 35);
    comp.add_layer (cam);
    var light = Factory.light (comp, LightType.POINT);
    comp.add_layer (light);
    var lit = r.render (comp, 0, rs);
    save (lit, "3d-lit");
    px (lit, 160, 90, out cr, out cg, out cb, out ca);
    check (cr < 0.99 && cr > 0.0, "point light shades the card");

    var comp2 = new Composition ("Blur", 200, 50, 30, 1);
    p.add_item (comp2);
    var box = Factory.solid (comp2, "Box", { 1, 1, 1, 1 }, 20, 20);
    box.transform.prop ("position").set_key (0, { 0, 25, 0 });
    box.transform.prop ("position").set_key (0.1, { 300, 25, 0 });
    box.motion_blur = true;
    comp2.add_layer (box);
    var blurred = r.render (comp2, 0.05, rs);
    save (blurred, "motion-blur");
    px (blurred, 168, 25, out cr, out cg, out cb, out ca);
    check (ca > 0.2 && ca < 0.9, "motion blur smears alpha");
    box.motion_blur = false;
    var sharp = r.render (comp2, 0.05, rs);
    px (sharp, 155, 25, out cr, out cg, out cb, out ca);
    check (ca > 0.99, "no blur when switch is off");
}

void test_path_text_and_orient () {
    var p = new Project ();
    var comp = new Composition ("P", 400, 200, 30, 2);
    p.add_item (comp);
    var t = Factory.text_layer (comp, "ARC");
    t.text_group.prop ("source-text").text.size = 30;
    t.text_group.prop ("source-text").text.justify = 0;
    t.transform.prop ("position").value = { 0, 0, 0 };
    var arc = new BezPath ();
    arc.closed = false;
    arc.add (50, 150, 0, 0, 0, -120);
    arc.add (350, 150, 0, -120, 0, 0);
    var m = Factory.mask (arc);
    m.attrs["mode"] = "none";
    t.masks.add<PropGroup> (m);
    t.text_group.group ("path-options").attrs["mask"] = "mask";
    comp.add_layer (t);
    var r = new Renderer (p);
    var rs = new RenderSettings ();
    rs.use_cache = false;
    var img = r.render (comp, 0, rs);
    save (img, "path-text");
    double sy = 0, sw = 0, sx = 0;
    for (int y = 0; y < img.height; y++)
        for (int x = 0; x < img.width; x++) {
            float cr, cg, cb, ca;
            img.get_pixel (x, y, out cr, out cg, out cb, out ca);
            sy += y * ca;
            sx += x * ca;
            sw += ca;
        }
    check (sw > 50 && sy / sw < 140 && sx / sw < 120, "text follows the arc start instead of the layer origin");
    var n = Factory.null_layer (comp);
    var pos = n.transform.prop ("position");
    pos.set_key (0, { 0, 0, 0 });
    pos.set_key (1, { 100, 100, 0 });
    foreach (var k in pos.keys) k.spatial_auto = false;
    n.auto_orient = AutoOrient.ALONG_PATH;
    comp.add_layer (n);
    var mtx = n.local_matrix (0.5);
    double ang = Math.atan2 (mtx.m[4], mtx.m[0]) * 180 / Math.PI;
    check (near (ang, 45, 0.5), "auto-orient follows the motion path");
}

void test_footage_with_audio () {
    var path = Path.build_filename (tmp_dir (), "av.webm");
    try {
        string[] argv = { "gst-launch-1.0", "-q", "videotestsrc", "num-buffers=15", "pattern=red", "!", "video/x-raw,width=64,height=48,framerate=15/1", "!", "vp8enc", "!", "queue", "!", "webmmux", "name=m", "!", "filesink", "location=" + path,
                          "audiotestsrc", "num-buffers=20", "!", "vorbisenc", "!", "queue", "!", "m." };
        int status;
        Process.spawn_sync (null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, out status);
    } catch (Error e) {
        check (false, "gst-launch " + e.message);
        return;
    }
    try {
        var f = MediaPool.probe (path);
        check (f.has_audio && f.width == 64, "probe sees video and audio");
        var p = new Project ();
        var comp = new Composition ("AV", 64, 48, 15, 1);
        p.add_item (comp);
        p.add_item (f);
        comp.add_layer (Factory.footage_layer (comp, f));
        var r = new Renderer (p);
        var rs = new RenderSettings ();
        rs.use_cache = false;
        var img = r.render (comp, 0.5, rs);
        float cr, cg, cb, ca;
        img.get_pixel (32, 24, out cr, out cg, out cb, out ca);
        if (!(cr > 0.8 && ca > 0.99)) stderr.printf ("decode %f %f %s\n", cr, ca, r.media.last_error);
        check (cr > 0.8 && ca > 0.99, "video frame decoded from a file that also has audio");
        r.media.close ();
    } catch (Error e) {
        check (false, "probe " + e.message);
    }
}

int main (string[] args) {
    Gst.init (ref args);
    outdir = out_dir ();
    test_solid_and_transform ();
    test_demo ();
    test_masks_and_mattes ();
    test_precomp_adjustment_blend ();
    test_3d_and_motion_blur ();
    test_path_text_and_orient ();
    test_footage_with_audio ();
    print ("output in %s\n", outdir);
    return finish ("keyframe-render");
}
