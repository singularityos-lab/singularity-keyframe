using Singularity.Apps.Keyframe;
using Singularity.Apps.Keyframe.Test;
using Singularity.Imaging;
using Singularity.Imaging.Tracking;

string dir;

Footage texture (Project p, string name, int w, int h, uint32 seed) {
    var img = new FloatImage.filled (w, h, 0.18f, 0.18f, 0.18f, 1);
    var rng = new Rand.with_seed (seed);
    for (int i = 0; i < w * h / 180; i++) {
        int x0 = rng.int_range (0, w), y0 = rng.int_range (0, h);
        int rw = rng.int_range (3, 14), rh = rng.int_range (3, 14);
        float v = (float) rng.double_range (0, 1);
        float c = (float) rng.double_range (0, 1);
        for (int y = y0; y < int.min (h, y0 + rh); y++)
            for (int x = x0; x < int.min (w, x0 + rw); x++) img.set_pixel (x, y, v, v * c, 1 - v, 1);
    }
    var path = Path.build_filename (dir, name + ".png");
    try {
        ImageIO.save_png (img, path, 8, true);
    } catch (Error e) {
        check (false, "texture " + e.message);
    }
    var f = new Footage (path, FootageKind.IMAGE);
    f.width = w;
    f.height = h;
    p.add_item (f);
    return f;
}

Layer source_precomp (Project p, Composition inner, int w, int h, double fps, double dur) {
    var outer = new Composition ("Outer " + inner.name, w, h, fps, dur);
    p.add_item (outer);
    var pre = Factory.precomp_layer (outer, inner);
    pre.transform.prop ("position").value = { w / 2.0, h / 2.0, 0 };
    outer.add_layer (pre);
    return pre;
}

void test_core_estimators () {
    double[] src = {}, dst = {};
    var truth = compose_similarity (12, -7, 1.15, 0.3);
    var rng = new Rand.with_seed (3);
    for (int i = 0; i < 40; i++) {
        double x = rng.double_range (0, 300), y = rng.double_range (0, 200);
        double u, v;
        Tracking.apply (truth, x, y, out u, out v);
        if (i % 8 == 0) {
            u += 40;
            v -= 30;
        }
        src += x;
        src += y;
        dst += u;
        dst += v;
    }
    bool[] inl;
    var est = ransac (MotionModel.SIMILARITY, src, dst, 1.0, 200, out inl);
    double tx, ty, s, a;
    decompose_similarity (est, out tx, out ty, out s, out a);
    check (near (tx, 12, 1e-6) && near (s, 1.15, 1e-9) && near (a, 0.3, 1e-9), "ransac similarity rejects outliers");
    double[] q = { 0, 0, 100, 0, 100, 100, 0, 100 };
    double[] r = { 10, 5, 120, 20, 110, 130, -5, 90 };
    var h = fit (MotionModel.HOMOGRAPHY, q, r);
    double hx, hy;
    Tracking.apply (h, 100, 100, out hx, out hy);
    check (near (hx, 110, 1e-6) && near (hy, 130, 1e-6), "homography from four points");
    var sm = Tracking.smooth ({ 0, 10, 0, 10, 0, 10, 0 }, 2);
    check (sm[3] > 3 && sm[3] < 7, "trajectory smoothing");
}

void test_point_tracker () {
    var p = new Project ();
    var tex = texture (p, "pt", 480, 360, 11);
    var inner = new Composition ("Move", 320, 240, 10, 1.1);
    p.add_item (inner);
    var l = Factory.footage_layer (inner, tex);
    var pos = l.transform.prop ("position");
    pos.set_key (0, { 160, 120, 0 });
    pos.set_key (1, { 197, 139, 0 });
    foreach (var k in pos.keys) k.spatial_auto = false;
    var rot = l.transform.prop ("rotation");
    var sc = l.transform.prop ("scale");
    inner.add_layer (l);
    var src = source_precomp (p, inner, 320, 240, 10, 1.1);
    var r = new Renderer (p);
    TrackPoint[] pts = { new TrackPoint (150, 110, 10, 20) };
    var res = PointTracker.track (r, src, 0, 1, pts);
    check (res.frames == 11, "one point track covers 11 frames");
    int last = res.frames - 1;
    double ex = 150 + 37, ey = 110 + 19;
    double err = Math.hypot (res.points[0].xs[last] - ex, res.points[0].ys[last] - ey);
    stdout.printf ("point tracker final error %.3f px, min confidence %.3f\n", err, min_of (res.points[0].confidence));
    check (err < 0.5, "one point tracker within half a pixel");
    var n = PointTracker.apply_to_new_null (res, src);
    var np = n.transform.prop ("position").value_at (n.layer_time (1.0));
    check (near (np[0], ex, 0.5) && near (np[1], ey, 0.5), "apply motion to new null");
    check (n.transform.prop ("position").keys.size == 11, "null has one key per frame");

    pos.clear_keys ();
    pos.value = { 160, 120, 0 };
    rot.set_key (0, { 0 });
    rot.set_key (1, { 20 });
    sc.set_key (0, { 100, 100, 100 });
    sc.set_key (1, { 120, 120, 100 });
    l.transform.prop ("anchor").value = { 240, 180, 0 };
    r.cache.clear ();
    TrackPoint[] two = { new TrackPoint (100, 120, 10, 24), new TrackPoint (220, 120, 10, 24) };
    var res2 = PointTracker.track (r, src, 0, 1, two);
    for (int q = 0; q < 2; q++) {
        int lf = res2.frames - 1;
        double rx = (q == 0 ? -60 : 60) * 1.2, ang = 20 * Math.PI / 180;
        stdout.printf ("two point p%d tracked (%.2f, %.2f) expected (%.2f, %.2f) conf %.3f\n", q, res2.points[q].xs[lf], res2.points[q].ys[lf], 160 + rx * Math.cos (ang), 120 + rx * Math.sin (ang), min_of (res2.points[q].confidence));
    }
    var target = Factory.solid (src.comp, "Target", { 1, 1, 1, 1 }, 50, 50);
    src.comp.add_layer (target);
    PointTracker.apply (res2, src, target, true, true, true);
    double lt = target.layer_time (1.0);
    double got_scale = target.transform.prop ("scale").value_at (lt)[0];
    double got_rot = target.transform.prop ("rotation").scalar_at (lt);
    stdout.printf ("two point tracker scale %.3f rotation %.3f\n", got_scale, got_rot);
    check (near (got_scale, 120, 0.8), "two point scale");
    check (near (got_rot, 20, 0.4), "two point rotation");
}

double min_of (double[] v) {
    double m = double.MAX;
    foreach (var x in v) m = double.min (m, x);
    return m;
}

void test_planar () {
    var p = new Project ();
    var tex = texture (p, "plane", 300, 220, 23);
    var inner = new Composition ("Plane", 320, 240, 10, 1.1);
    p.add_item (inner);
    var bgtex = texture (p, "bg", 320, 240, 99);
    var bg = Factory.footage_layer (inner, bgtex);
    inner.add_layer (bg);
    var l = Factory.footage_layer (inner, tex);
    l.transform.prop ("position").value = { 150, 110, 0 };
    var pin = EffectRegistry.add_to_layer (l, "corner-pin");
    double[] a0 = { 40, 40, 260, 30, 270, 200, 30, 190 };
    double[] a1 = { 70, 50, 250, 60, 240, 190, 60, 210 };
    string[] keys = { "upper-left", "upper-right", "lower-right", "lower-left" };
    for (int k = 0; k < 4; k++) {
        pin.prop (keys[k]).set_key (0, { a0[k * 2], a0[k * 2 + 1] });
        pin.prop (keys[k]).set_key (1, { a1[k * 2], a1[k * 2 + 1] });
    }
    inner.add_layer (l);
    var src = source_precomp (p, inner, 320, 240, 10, 1.1);
    var r = new Renderer (p);
    var lw = l.world_matrix (0);
    var start = new double[8];
    for (int k = 0; k < 4; k++) {
        var c = lw.transform_point (Vec3 (a0[k * 2], a0[k * 2 + 1], 0));
        start[k * 2] = c.x;
        start[k * 2 + 1] = c.y;
    }
    var res = PlanarTracker.track (r, src, 0, 1, start);
    check (res.frames == 11, "planar track frames");
    double worst = 0;
    for (int k = 0; k < 4; k++) {
        var c = lw.transform_point (Vec3 (a1[k * 2], a1[k * 2 + 1], 0));
        worst = double.max (worst, Math.hypot (res.corner (res.frames - 1, k * 2) - c.x, res.corner (res.frames - 1, k * 2 + 1) - c.y));
    }
    stdout.printf ("planar tracker worst corner error %.3f px\n", worst);
    check (worst < 1.5, "planar corners within 1.5 px");
    var target = Factory.solid (src.comp, "Screen", { 1, 0, 0, 1 }, 100, 60);
    src.comp.add_layer (target);
    var fx = PlanarTracker.apply_corner_pin (res, src, target);
    check (fx != null && fx.prop ("upper-left").keys.size == 11, "corner pin keys per frame");
    var rs = new RenderSettings ();
    rs.use_cache = false;
    var img = r.render (src.comp, 1.0, rs);
    float cr, cg, cb, ca;
    double mx = 0, my = 0;
    for (int k = 0; k < 4; k++) {
        mx += res.corner (res.frames - 1, k * 2) / 4;
        my += res.corner (res.frames - 1, k * 2 + 1) / 4;
    }
    img.get_pixel ((int) mx, (int) my, out cr, out cg, out cb, out ca);
    check (cr > 0.95 && cg < 0.05, "pinned layer covers the tracked plane");
    try {
        ImageIO.save_png (img, Path.build_filename (dir, "planar.png"), 8, true);
    } catch (Error e) {
    }
}

double centre_diff (FloatImage a, FloatImage b) {
    double d = 0;
    int n = 0;
    for (int y = a.height / 4; y < a.height * 3 / 4; y++)
        for (int x = a.width / 4; x < a.width * 3 / 4; x++) {
            size_t o = a.offset (x, y);
            for (int c = 0; c < 3; c++) d += (a.data[o + c] - b.data[o + c]).abs ();
            n++;
        }
    return d / n;
}

void test_stabilizer () {
    var p = new Project ();
    var tex = texture (p, "shake", 420, 320, 5);
    var inner = new Composition ("Shake", 320, 240, 10, 1.1);
    p.add_item (inner);
    var l = Factory.footage_layer (inner, tex);
    var rng = new Rand.with_seed (9);
    for (int k = 0; k <= 10; k++) {
        double t = k / 10.0;
        var key = l.transform.prop ("position").set_key (t, { 160 + rng.double_range (-8, 8), 120 + rng.double_range (-8, 8), 0 });
        key.in_interp = Interp.HOLD;
        key.out_interp = Interp.HOLD;
        var rk = l.transform.prop ("rotation").set_key (t, { rng.double_range (-2, 2) });
        rk.in_interp = Interp.HOLD;
        rk.out_interp = Interp.HOLD;
    }
    inner.add_layer (l);
    var src = source_precomp (p, inner, 320, 240, 10, 1.1);
    var r = new Renderer (p);
    var rs = new RenderSettings ();
    rs.use_cache = false;
    var before0 = r.render (src.comp, 0, rs);
    double shaky = 0;
    for (int k = 1; k <= 10; k++) shaky += centre_diff (before0, r.render (src.comp, k / 10.0, rs));
    Stabilizer.register ();
    var fx = Stabilizer.analyze (r, src, 0, 1);
    check (fx != null, "stabilizer analysis creates the effect");
    fx.prop ("result").value = { 1 };
    fx.prop ("framing").value = { 0 };
    src.mark_changed ();
    var after0 = r.render (src.comp, 0, rs);
    double steady = 0;
    for (int k = 1; k <= 10; k++) steady += centre_diff (after0, r.render (src.comp, k / 10.0, rs));
    stdout.printf ("stabilizer centre difference before %.4f after %.4f\n", shaky / 10, steady / 10);
    check (steady < shaky * 0.25, "stabilized frames match the first frame");
    fx.prop ("framing").value = { 2 };
    var w = Stabilizer.warps (fx, 0);
    double s = Stabilizer.auto_scale (w, 320, 240, 1.5);
    check (s > 1.01 && s < 1.5, "auto scale crops the moving borders");
    fx.prop ("result").value = { 0 };
    fx.prop ("smoothness").value = { 80 };
    var sw = Stabilizer.warps (fx, 0);
    check (sw.length == 99, "smooth motion warps per frame");
    fx.prop ("framing").value = { 0 };
    src.mark_changed ();
    double raw_jitter = 0, smooth_jitter = 0;
    fx.enabled = false;
    src.mark_changed ();
    var prev_raw = r.render (src.comp, 0, rs);
    for (int k = 1; k <= 10; k++) {
        var cur = r.render (src.comp, k / 10.0, rs);
        raw_jitter += centre_diff (prev_raw, cur);
        prev_raw = cur;
    }
    fx.enabled = true;
    src.mark_changed ();
    var prev_s = r.render (src.comp, 0, rs);
    for (int k = 1; k <= 10; k++) {
        var cur = r.render (src.comp, k / 10.0, rs);
        smooth_jitter += centre_diff (prev_s, cur);
        prev_s = cur;
    }
    stdout.printf ("stabilizer smooth motion frame-to-frame difference raw %.4f smoothed %.4f\n", raw_jitter / 10, smooth_jitter / 10);
    check (smooth_jitter < raw_jitter * 0.7, "smooth motion reduces frame to frame jitter");
}

void test_camera_solver_synthetic () {
    int frames = 15, w = 640, h = 360;
    double zoom = w * 50.0 / 36.0;
    var rng = new Rand.with_seed (21);
    double[] world = {};
    for (int i = 0; i < 60; i++) {
        world += rng.double_range (50, 590);
        world += rng.double_range (40, 320);
        world += rng.double_range (-300, 400);
    }
    var truth = new double[frames * 6];
    for (int k = 0; k < frames; k++) {
        double f = (double) k / (frames - 1);
        truth[k * 6] = w / 2.0 + 160 * f;
        truth[k * 6 + 1] = h / 2.0 - 30 * f;
        truth[k * 6 + 2] = -zoom + 200 * f;
        truth[k * 6 + 3] = 0;
        truth[k * 6 + 4] = -0.08 * f;
        truth[k * 6 + 5] = 0.02 * f;
    }
    var tracks = new Gee.ArrayList<FeatureTrack> ();
    for (int i = 0; i < 60; i++) {
        var t = new FeatureTrack (frames);
        for (int k = 0; k < frames; k++) {
            double u, v, d;
            CameraSolver.project (truth, k * 6, world, i * 3, zoom, w / 2.0, h / 2.0, out u, out v, out d);
            if (d <= 0 || u < 0 || v < 0 || u > w || v > h) continue;
            t.xs[k] = u + rng.double_range (-0.3, 0.3);
            t.ys[k] = v + rng.double_range (-0.3, 0.3);
            t.valid[k] = true;
        }
        tracks.add (t);
    }
    var s = CameraSolver.solve (tracks, frames, w, h, zoom);
    check (s != null, "camera solve returns");
    if (s == null) return;
    double scale = alignment_scale (s.poses, truth, frames);
    double worst = 0;
    for (int k = 0; k < frames; k++) {
        double ex = (s.poses[k * 6] - s.poses[0]) * scale - (truth[k * 6] - truth[0]);
        double ey = (s.poses[k * 6 + 1] - s.poses[1]) * scale - (truth[k * 6 + 1] - truth[1]);
        double ez = (s.poses[k * 6 + 2] - s.poses[2]) * scale - (truth[k * 6 + 2] - truth[2]);
        worst = double.max (worst, Math.sqrt (ex * ex + ey * ey + ez * ez));
    }
    double travel = Math.sqrt (160 * 160 + 30 * 30 + 200 * 200);
    stdout.printf ("camera solve synthetic: reprojection %.3f px, scale %.3f, worst path error %.2f of %.1f travel\n", s.error_px, scale, worst, travel);
    check (s.error_px < 0.6, "bundle adjustment reprojection error");
    check (worst < travel * 0.03, "solved path matches the true camera path");
    check (scale > 0.6 && scale < 1.6, "scale fixed by the scene depth prior");
}

double alignment_scale (double[] got, double[] truth, int frames) {
    double num = 0, den = 0;
    for (int k = 1; k < frames; k++)
        for (int c = 0; c < 3; c++) {
            double g = got[k * 6 + c] - got[c], t = truth[k * 6 + c] - truth[c];
            num += g * t;
            den += g * g;
        }
    return den > 0 ? num / den : 1;
}

void test_camera_solver_rendered () {
    var p = new Project ();
    int w = 320, h = 180;
    var scene = new Composition ("Scene", w, h, 10, 1.1);
    p.add_item (scene);
    double[] zs = { 300, 0, -150 };
    for (int i = 0; i < 3; i++) {
        var tex = texture (p, "cam%d".printf (i), 360, 260, 40 + i);
        var l = Factory.footage_layer (scene, tex);
        l.three_d = true;
        l.transform.prop ("position").value = { w / 2.0 + (i - 1) * 90, h / 2.0, zs[i] };
        l.transform.prop ("scale").value = { 60 + i * 15, 60 + i * 15, 100 };
        scene.add_layer (l);
    }
    var cam = Factory.camera (scene, 50);
    double zoom = cam.root.group ("camera").num ("zoom", 0);
    cam.root.group ("camera").attrs["one-node"] = "true";
    var cp = cam.transform.prop ("position");
    cp.set_key (0, { w / 2.0, h / 2.0, -zoom });
    cp.set_key (1, { w / 2.0 + 70, h / 2.0 - 10, -zoom + 60 });
    foreach (var k in cp.keys) k.spatial_auto = false;
    scene.add_layer (cam);
    var src = source_precomp (p, scene, w, h, 10, 1.1);
    var r = new Renderer (p);
    var tracks = CameraSolver.track_scene (r, src, 0, 1, 120);
    check (tracks.size > 30, "scene tracking finds features");
    var s = CameraSolver.solve (tracks, 11, w, h, zoom);
    check (s != null, "rendered camera solve returns");
    if (s == null) return;
    var truth = new double[11 * 6];
    for (int k = 0; k < 11; k++) {
        var v = cp.value_at (k / 10.0);
        truth[k * 6] = v[0];
        truth[k * 6 + 1] = v[1];
        truth[k * 6 + 2] = v[2];
    }
    double scale = alignment_scale (s.poses, truth, 11);
    double worst = 0;
    for (int k = 0; k < 11; k++) {
        double e = 0;
        for (int c = 0; c < 3; c++) {
            double d = (s.poses[k * 6 + c] - s.poses[c]) * scale - (truth[k * 6 + c] - truth[c]);
            e += d * d;
        }
        worst = double.max (worst, Math.sqrt (e));
    }
    double travel = Math.sqrt (70 * 70 + 10 * 10 + 60 * 60);
    stdout.printf ("camera solve rendered: %d tracks, reprojection %.3f px, scale %.3f, worst path error %.2f of %.1f travel\n", tracks.size, s.error_px, scale, worst, travel);
    check (s.error_px < 1.0, "rendered solve reprojection");
    check (worst < travel * 0.1, "rendered solve path within 10 percent of travel");
    var solved = CameraSolver.create_layers (s, src.comp, 0, true, true);
    check (solved.kind == LayerKind.CAMERA && solved.transform.prop ("position").keys.size == 11, "solved camera layer keyed per frame");
    int nulls = 0;
    foreach (var l in src.comp.layers) if (l.kind == LayerKind.NULL && l.three_d) nulls++;
    check (nulls > 10, "3d nulls created for solved points");
}

void test_roto () {
    var p = new Project ();
    var inner = new Composition ("Roto", 240, 180, 10, 1.1);
    p.add_item (inner);
    var bgtex = texture (p, "rotobg", 240, 180, 77);
    inner.add_layer (Factory.footage_layer (inner, bgtex));
    var blob = Factory.shape_layer (inner, "Blob");
    var g = Factory.shape_group ("C");
    g.group ("contents").add<PropGroup> (Factory.ellipse (70, 70));
    g.group ("contents").add<PropGroup> (Factory.fill ({ 1, 1, 1, 1 }));
    blob.contents.add<PropGroup> (g);
    var bp = blob.transform.prop ("position");
    bp.set_key (0, { 80, 90, 0 });
    bp.set_key (1, { 150, 100, 0 });
    foreach (var k in bp.keys) k.spatial_auto = false;
    inner.add_layer (blob);
    var src = source_precomp (p, inner, 240, 180, 10, 1.1);
    var mask = Factory.mask (BezPath.ellipse (80, 90, 35, 35));
    src.masks.add<PropGroup> (mask);
    var r = new Renderer (p);
    int written = RotoBrush.propagate (r, src, mask, 0, 1);
    check (written == 10, "roto propagates ten frames");
    var path = mask.prop ("path").path_at (src.layer_time (1.0));
    double cx = 0, cy = 0;
    foreach (var v in path.v) {
        cx += v.x / path.count;
        cy += v.y / path.count;
    }
    double radius = 0;
    foreach (var v in path.v) radius += Math.hypot (v.x - cx, v.y - cy) / path.count;
    stdout.printf ("roto final centre (%.2f, %.2f) radius %.2f\n", cx, cy, radius);
    check (Math.hypot (cx - 150, cy - 100) < 2.0, "roto mask follows the object");
    check ((radius - 35).abs () < 3.0, "roto mask keeps the outline");
    check (!RotoBrush.uses_local_model, "no local segmentation model");
    var size = (g.group ("contents").child ("ellipse") as PropGroup).prop ("size");
    size.set_key (0, { 70, 70 });
    size.set_key (1, { 90, 90 });
    var mask2 = Factory.mask (BezPath.ellipse (80, 90, 35, 35).resampled (16));
    src.masks.children.clear ();
    src.masks.add<PropGroup> (mask2);
    r.cache.clear ();
    RotoBrush.propagate (r, src, mask2, 0, 1);
    var p2 = mask2.prop ("path").path_at (src.layer_time (1.0));
    double c2x = 0, c2y = 0, r2 = 0;
    foreach (var v in p2.v) {
        c2x += v.x / p2.count;
        c2y += v.y / p2.count;
    }
    foreach (var v in p2.v) r2 += Math.hypot (v.x - c2x, v.y - c2y) / p2.count;
    var refined = RotoBrush.refine (p2, Plane.from_image (r.layer_buffer_until (src, 1.0, new RenderSettings (), 0, 0, 1, true).img), r.layer_buffer_until (src, 1.0, new RenderSettings (), 0, 0, 1, true), 4);
    double r3 = 0;
    foreach (var v in refined.v) r3 += Math.hypot (v.x - c2x, v.y - c2y) / refined.count;
    stdout.printf ("roto growing object: centre (%.2f, %.2f) radius %.2f refined %.2f (true 45)\n", c2x, c2y, r2, r3);
    check (Math.hypot (c2x - 150, c2y - 100) < 2.0, "roto follows a growing object");
    check ((r2 - 45).abs () < 3.0, "edge snapping follows the growing outline");
}

int main (string[] args) {
    Gst.init (ref args);
    dir = out_dir ();
    test_core_estimators ();
    test_point_tracker ();
    test_planar ();
    test_stabilizer ();
    test_camera_solver_synthetic ();
    test_camera_solver_rendered ();
    test_roto ();
    return finish ("keyframe-track");
}
