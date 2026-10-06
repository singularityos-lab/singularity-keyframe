using Singularity.Apps.Keyframe;
using Singularity.Apps.Keyframe.Test;

void test_interpolation () {
    var p = new Property ("x", "X", PropKind.SCALAR, { 0 });
    p.set_key (0, { 0 });
    p.set_key (1, { 100 });
    check (near (p.value_at (0.5)[0], 50), "linear midpoint");
    check (near (p.value_at (-1)[0], 0), "before first key");
    check (near (p.value_at (2)[0], 100), "after last key");
    p.keys[0].out_interp = Interp.HOLD;
    check (near (p.value_at (0.99)[0], 0), "hold keeps value");
    p.keys[0].set_easy_ease ();
    p.keys[1].set_easy_ease ();
    check (near (p.value_at (0.5)[0], 50, 0.5), "easy ease symmetric midpoint");
    check (p.value_at (0.1)[0] < 10, "easy ease starts slow");
    check (p.value_at (0.9)[0] > 90, "easy ease ends slow");
    check (p.speed_at (0.01) < p.speed_at (0.5), "easy ease speed rises");

    var pos = new Property ("position", "Position", PropKind.POINT, { 0, 0, 0 });
    pos.set_key (0, { 0, 0, 0 });
    pos.set_key (1, { 100, 0, 0 });
    pos.set_key (2, { 100, 100, 0 });
    var mid = pos.value_at (1);
    check (near (mid[0], 100) && near (mid[1], 0), "spatial key exact at key time");
    var q = pos.value_at (0.5);
    check (q[1] < 0, "auto bezier spatial path curves outward");
    pos.keys[1].spatial_auto = false;
    pos.keys[1].tangent_in = { 0, 0, 0 };
    pos.keys[1].tangent_out = { 0, 0, 0 };
    pos.keys[0].spatial_auto = false;
    pos.keys[2].spatial_auto = false;
    var lin = pos.value_at (0.5);
    check (near (lin[0], 50) && near (lin[1], 0), "linear spatial path");

    var rov = new Property ("position", "Position", PropKind.POINT, { 0, 0 });
    rov.set_key (0, { 0, 0 });
    rov.set_key (1.0, { 10, 0 });
    rov.set_key (2, { 100, 0 });
    foreach (var k in rov.keys) {
        k.spatial_auto = false;
    }
    rov.keys[1].roving = true;
    var times = rov.effective_times ();
    check (near (times[1], 0.2, 1e-6), "roving key retimed by distance");

    var col = new Property ("c", "C", PropKind.COLOR, { 0, 0, 0, 1 });
    col.set_key (0, { 1, 0, 0, 1 });
    col.set_key (1, { 0, 0, 1, 1 });
    var cm = col.value_at (0.5);
    check (near (cm[0], 0.5) && near (cm[2], 0.5), "colour interpolation");
}

void test_paths () {
    var a = BezPath.rect (0, 0, 100, 100);
    var b = BezPath.ellipse (50, 50, 50, 50);
    var m = BezPath.lerp (a, b, 0.5);
    check (m.count == 4, "path lerp keeps vertex count");
    var tri = new BezPath ();
    tri.add (0, 0);
    tri.add (10, 0);
    tri.add (5, 5);
    var res = tri.resampled (6);
    check (res.count == 6, "resampled vertex count");
    check (near (BezPath.rect (0, 0, 10, 10).length (), 40, 0.01), "rect perimeter");
    var parsed = BezPath.parse (b.serialize ());
    check (parsed.count == 4 && near (parsed.v[1].x, 100), "path serialize round trip");
    var pieces = PathOps.trim (BezPath.rect (0, 0, 10, 10), 0, 0.5, 0);
    double len = 0;
    foreach (var pc in pieces) len += pc.length ();
    check (near (len, 20, 0.05), "trim half length");
    var wrap = PathOps.trim (BezPath.rect (0, 0, 10, 10), 0.75, 1.0, 0.5);
    len = 0;
    foreach (var pc in wrap) len += pc.length ();
    check (near (len, 10, 0.05), "trim with offset wrap");
    var rc = PathOps.round_corners (BezPath.rect (0, 0, 100, 100), 10);
    check (rc.count == 8, "round corners doubles vertices");
}

void test_project_round_trip () {
    var p = new Project ();
    var comp = new Composition ("Main", 640, 360, 25, 4);
    p.add_item (comp);
    var folder = new Folder ("Footage");
    p.add_item (folder);
    var shape = Factory.shape_layer (comp);
    var grp = Factory.shape_group ("Box");
    grp.group ("contents").add<PropGroup> (Factory.rect (100, 50, 8));
    grp.group ("contents").add<PropGroup> (Factory.fill ({ 1, 0, 0, 1 }));
    shape.contents.add<PropGroup> (grp);
    shape.transform.prop ("position").set_key (0, { 0, 0, 0 });
    shape.transform.prop ("position").set_key (2, { 320, 180, 0 });
    shape.transform.prop ("position").keys[0].set_easy_ease ();
    shape.transform.prop ("rotation").expression = "time * 90";
    comp.add_layer (shape);
    var text = Factory.text_layer (comp, "Hello");
    comp.add_layer (text);
    var ri = new RenderItem (comp.id);
    var om = new OutputModule ();
    om.format = "png-sequence";
    om.path = "/tmp/out_####.png";
    ri.outputs.add (om);
    p.render_queue.add (ri);
    uint8[] bytes;
    Project q;
    try {
        bytes = NativeFormat.save_bytes (p);
        q = NativeFormat.load_bytes (bytes);
    } catch (Error e) {
        check (false, "round trip " + e.message);
        return;
    }
    check (bytes.length > 100 && bytes[0] == 'P' && bytes[1] == 'K', "native project is a zip");
    check (q.items.size == 2, "items survive");
    var qc = q.compositions ()[0];
    check (qc.width == 640 && qc.fps == 25 && qc.layers.size == 2, "comp settings survive");
    var ql = qc.layer_by_name (shape.name);
    check (ql != null && ql.transform.prop ("position").keys.size == 2, "keyframes survive");
    check (ql.transform.prop ("position").keys[0].out_interp == Interp.BEZIER, "easing survives");
    check (ql.transform.prop ("rotation").expression == "time * 90", "expression survives");
    check (ql.contents.find ("group/contents/rectangle/size") != null, "shape tree survives");
    check (q.render_queue.size == 1 && q.render_queue[0].outputs[0].path == "/tmp/out_####.png", "render queue survives");
    var tl = qc.layers[0];
    check (tl.text_group.prop ("source-text").text.text == "Hello", "text survives");
    comp.essential.add (new EssentialProperty (text.id, "text/source-text", "Title"));
    var root = NativeFormat.project_to_json (p).get_object ();
    check (root.has_member ("compositions") && root.get_array_member ("compositions").get_object_element (0).get_array_member ("essential").get_length () == 1, "root composition summary lists exposed properties");
    var snap = NativeFormat.snapshot (q);
    try {
        var r = NativeFormat.restore (snap, "");
        check (NativeFormat.snapshot (r) == snap, "snapshot stable");
    } catch (Error e) {
        check (false, "restore " + e.message);
    }
}

void test_codecs () {
    var img = new Singularity.Imaging.FloatImage (13, 7);
    for (int y = 0; y < 7; y++)
        for (int x = 0; x < 13; x++) img.set_pixel (x, y, x / 13.0f * 0.5f, y / 7.0f * 0.5f, 2.5f * 0.5f, 0.5f);
    try {
        var exr = Exr.decode (Exr.encode (img, false, true));
        float r, g, b, a;
        exr.get_pixel (5, 3, out r, out g, out b, out a);
        check (near (a, 0.5) && near (r, 5 / 13.0, 1e-4) && near (b, 2.5, 1e-4), "exr float zip round trip keeps hdr");
        var exr16 = Exr.decode (Exr.encode (img, true, false));
        exr16.get_pixel (5, 3, out r, out g, out b, out a);
        check (near (r, 5 / 13.0, 2e-3) && near (b, 2.5, 3e-3), "exr half round trip");
        var tif = Tiff.decode (Tiff.encode (img, 32, true, true));
        tif.get_pixel (5, 3, out r, out g, out b, out a);
        check (near (r, 5 / 13.0, 1e-5) && near (b, 2.5, 1e-5), "tiff float round trip");
        var tif16 = Tiff.decode (Tiff.encode (img, 16, true, false));
        check (tif16.width == 13 && tif16.height == 7, "tiff 16 size");
        var png = ImageIO.encode_png (img, 16, true);
        check (png[1] == 'P' && png[2] == 'N', "png signature");
        var dir = tmp_dir ();
        var path = Path.build_filename (dir, "t.png");
        FileUtils.set_data (path, png);
        var back = ImageIO.load (path);
        back.get_pixel (5, 3, out r, out g, out b, out a);
        check (near (r, 5 / 13.0, 2e-3) && near (a, 0.5, 2e-3), "png 16 bit round trip");
    } catch (Error e) {
        check (false, "codec error " + e.message);
    }
    check (near (Half.to_float (Half.from_float (1.5f)), 1.5), "half 1.5");
    check (near (Half.to_float (Half.from_float (-0.000123f)), -0.000123, 1e-6), "half small");
}

void test_color () {
    var img = new Singularity.Imaging.FloatImage.filled (1, 1, 0.18f, 0.18f, 0.18f, 1);
    ColorManagement.convert (img, "linear-srgb", "acescg");
    ColorManagement.convert (img, "acescg", "linear-srgb");
    float r, g, b, a;
    img.get_pixel (0, 0, out r, out g, out b, out a);
    check (near (r, 0.18, 1e-3) && near (b, 0.18, 1e-3), "acescg round trip");
    var red = new Singularity.Imaging.FloatImage.filled (1, 1, 1, 0, 0, 1);
    ColorManagement.convert (red, "linear-srgb", "acescg");
    red.get_pixel (0, 0, out r, out g, out b, out a);
    check (r < 1 && g > 0, "srgb red is inside acescg gamut");
    check (near (ColorManagement.decode ("acescct", ColorManagement.encode ("acescct", 0.5f)), 0.5, 1e-4), "acescct curve");
    try {
        var cube = Lut3D.parse_cube ("LUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n");
        float cr = 0.25f, cg = 0.5f, cb = 0.75f;
        cube.apply (ref cr, ref cg, ref cb);
        check (near (cr, 0.25) && near (cg, 0.5) && near (cb, 0.75), "identity cube lut");
    } catch (Error e) {
        check (false, "cube " + e.message);
    }
}

int main (string[] args) {
    test_interpolation ();
    test_paths ();
    test_project_round_trip ();
    test_codecs ();
    test_color ();
    return finish ("keyframe-model");
}
