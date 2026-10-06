using Singularity.Apps.Keyframe;
using Singularity.Apps.Keyframe.Test;
using Singularity.Imaging;

string dir;

class Decoded {
    public int frames = 0;
    public int width = 0;
    public int height = 0;
    public uint8[] first = {};
    public uint8[] last = {};
    public bool alpha_seen = false;
}

Decoded decode_video (string path) {
    var d = new Decoded ();
    try {
        var pipe = Gst.parse_launch ("filesrc name=src ! decodebin ! videoconvert ! video/x-raw,format=RGBA ! appsink name=sink sync=false") as Gst.Pipeline;
        pipe.get_by_name ("src").set ("location", path);
        var sink = pipe.get_by_name ("sink") as Gst.App.Sink;
        pipe.set_state (Gst.State.PLAYING);
        while (true) {
            var s = sink.try_pull_sample (20 * Gst.SECOND);
            if (s == null) break;
            unowned Gst.Structure st = s.get_caps ().get_structure (0);
            st.get_int ("width", out d.width);
            st.get_int ("height", out d.height);
            var b = s.get_buffer ();
            Gst.MapInfo info;
            if (b.map (out info, Gst.MapFlags.READ)) {
                var copy = info.data[0:info.size];
                if (d.frames == 0) d.first = copy;
                d.last = copy;
                for (int i = 3; i < info.size; i += 4) if (info.data[i] < 128) d.alpha_seen = true;
                b.unmap (info);
            }
            d.frames++;
        }
        pipe.set_state (Gst.State.NULL);
    } catch (Error e) {
        check (false, "decode " + e.message);
    }
    return d;
}

bool has_audio_stream (string path, out double duration) {
    duration = 0;
    try {
        var disc = new Gst.PbUtils.Discoverer (20 * Gst.SECOND);
        var info = disc.discover_uri (File.new_for_path (path).get_uri ());
        duration = info.get_duration () / (double) Gst.SECOND;
        return info.get_audio_streams ().length () > 0;
    } catch (Error e) {
        return false;
    }
}

Project build_project (out Composition comp) {
    var p = new Project ();
    comp = new Composition ("Out", 64, 48, 10, 1);
    p.add_item (comp);
    var bg = Factory.solid (comp, "Half", { 0, 0, 1, 0.5 }, 32, 48);
    bg.transform.prop ("position").value = { 48, 24, 0 };
    comp.add_layer (bg);
    var red = Factory.solid (comp, "Red", { 1, 0, 0, 1 }, 16, 16);
    red.transform.prop ("position").set_key (0, { 8, 24, 0 });
    red.transform.prop ("position").set_key (0.9, { 40, 24, 0 });
    comp.add_layer (red);
    var sr = 48000;
    var clip = new AudioClip ();
    clip.samples = new float[sr * 2 * 2];
    for (int i = 0; i < sr * 2; i++) {
        float v = 0.5f * Math.sinf ((float) (2 * Math.PI * 440 * i / sr));
        clip.samples[i * 2] = v;
        clip.samples[i * 2 + 1] = v;
    }
    var wav = Path.build_filename (dir, "tone.wav");
    try {
        FileUtils.set_data (wav, Wav.encode (clip));
        var f = MediaPool.probe (wav);
        p.add_item (f);
        var al = Factory.footage_layer (comp, f);
        al.root.group ("audio").prop ("levels").value = { -6, -6 };
        al.out_point = 1;
        comp.add_layer (al);
    } catch (Error e) {
        check (false, "audio fixture " + e.message);
    }
    return p;
}

void test_audio_mix () {
    Composition comp;
    var p = build_project (out comp);
    var r = new Renderer (p);
    var mix = AudioMix.mix (p, r.media, comp, 0, 1);
    check (mix.samples.length == 48000 * 2, "mix length");
    double rms = AudioMix.rms (mix, 0.1, 0.9);
    check (near (rms, 0.5 / Math.sqrt (2) * AudioMix.db_to_gain (-6), 0.01), "mix applies -6 dB level (rms %.4f)".printf (rms));
    var wav = Wav.encode (mix);
    check (wav[0] == 'R' && wav[8] == 'W' && wav.length == 44 + 48000 * 2 * 2, "wav header and size");
    var back = Wav.decode (wav);
    check (back != null && back.rate == 48000 && back.channels == 2, "wav decodes");
    var levels = comp.layers[0].root.group ("audio").prop ("levels");
    levels.set_key (0, { -96, -96 });
    levels.set_key (1, { 0, 0 });
    var ramp = AudioMix.mix (p, r.media, comp, 0, 1);
    check (AudioMix.rms (ramp, 0, 0.2) < AudioMix.rms (ramp, 0.8, 1.0), "animated level ramps up");
    comp.layers[0].audio = false;
    check (AudioMix.peak (AudioMix.mix (p, r.media, comp, 0, 1)) == 0, "audio switch mutes");
}

string render_one (Project p, Composition comp, string format, bool alpha, int depth = 8) throws Error {
    var om = new OutputModule ();
    om.format = format;
    om.alpha = alpha;
    om.bit_depth = depth;
    var f = Encoders.find (format);
    om.path = Path.build_filename (dir, f.sequence ? format + "/f_####." + f.extension : format + "." + f.extension);
    var outs = new Gee.ArrayList<OutputModule> ();
    outs.add (om);
    int frames_seen = 0;
    var res = RenderJobs.render (p, comp, outs, 0, comp.duration, 1, true, null, (fr, n) => { frames_seen++; });
    check (f.audio_only || frames_seen >= 10, format + " progress reported");
    return res[0];
}

void red_at (uint8[] px, int w, int x, int y, string what) {
    int i = (y * w + x) * 4;
    check (px.length > i + 3 && px[i] > 200 && px[i + 1] < 60 && px[i + 2] < 60, what + " red pixel (%d,%d,%d)".printf (px.length > i + 2 ? px[i] : -1, px.length > i + 2 ? px[i + 1] : -1, px.length > i + 2 ? px[i + 2] : -1));
}

void test_formats () {
    Composition comp;
    var p = build_project (out comp);
    foreach (var f in Encoders.formats ()) print ("format %s %s %s\n", f.id, f.available ? "available" : "unavailable", f.reason);
    try {
        var png = render_one (p, comp, "png-sequence", true, 16);
        var img = ImageIO.load (png);
        check (img.width == 64 && img.height == 48, "png size");
        float r, g, b, a;
        img.get_pixel (8, 24, out r, out g, out b, out a);
        check (r > 0.95 && a > 0.99, "png first frame red");
        img.get_pixel (48, 2, out r, out g, out b, out a);
        check (near (a, 0.5, 0.01), "png keeps half alpha");
        int count = 0;
        try {
            var d = Dir.open (Path.get_dirname (png));
            while (d.read_name () != null) count++;
        } catch (Error e) {
        }
        check (count == 10, "png sequence has 10 frames");
        var tif = render_one (p, comp, "tiff-sequence", true, 32);
        uint8[] data;
        FileUtils.get_data (tif, out data);
        var timg = Tiff.decode (data);
        timg.get_pixel (48, 2, out r, out g, out b, out a);
        check (near (a, 0.5, 1e-4) && near (b, 1, 1e-4), "tiff float keeps straight colour and alpha");
        var exr = render_one (p, comp, "exr-sequence", true, 16);
        FileUtils.get_data (exr, out data);
        var eimg = Exr.decode (data);
        eimg.get_pixel (8, 24, out r, out g, out b, out a);
        check (near (r, 1, 2e-3), "exr half frame");
        if (Encoders.find ("jpeg-sequence").available) {
            var jpg = render_one (p, comp, "jpeg-sequence", false);
            var pb = new Gdk.Pixbuf.from_file (jpg);
            check (pb.width == 64, "jpeg decodes");
        }
        if (Encoders.find ("webp-sequence").available) {
            var webp = render_one (p, comp, "webp-sequence", true);
            var wpb = new Gdk.Pixbuf.from_file (webp);
            check (wpb.width == 64 && wpb.has_alpha, "webp decodes with alpha");
        }
        var gif = render_one (p, comp, "gif", true);
        var anim = new Gdk.PixbufAnimation.from_file (gif);
        check (anim.get_width () == 64 && !anim.is_static_image (), "gif is animated");
        var gpb = anim.get_static_image ();
        red_at (gpb.get_pixels_with_length (), 64 * gpb.n_channels / 4, 8, 24, "gif");
        uint8[] gd;
        FileUtils.get_data (gif, out gd);
        int frames = 0;
        for (int i = 0; i + 1 < gd.length; i++) if (gd[i] == 0x21 && gd[i + 1] == 0xF9) frames++;
        check (frames == 10, "gif has 10 frames");
        foreach (var id in new string[] { "h264-mp4", "hevc-mp4", "av1-mp4", "av1-webm", "vp9-webm", "png-mov" }) {
            var f = Encoders.find (id);
            if (!f.available) {
                print ("skip %s: %s\n", id, f.reason);
                continue;
            }
            var path = render_one (p, comp, id, id == "png-mov");
            var d = decode_video (path);
            check (d.frames == 10, id + " decodes 10 frames (got %d)".printf (d.frames));
            check (d.width == 64 && d.height == 48, id + " size");
            red_at (d.first, d.width, 8, 24, id);
            double dur;
            bool au = has_audio_stream (path, out dur);
            check (au, id + " has the audio track");
            check (near (dur, 1.0, 0.15), id + " duration %.3f".printf (dur));
            if (id == "png-mov") check (d.alpha_seen, "png-mov keeps alpha");
        }
        var alpha = render_one (p, comp, "vp9-webm", true);
        var ad = decode_video (alpha);
        check (ad.frames >= 9, "vp9 alpha decodes with GStreamer (got %d)".printf (ad.frames));
        var ffa = Encoders.ffmpeg_path ();
        if (ffa != null) {
            var probe = new Subprocess.newv ({ ffa, "-v", "error", "-c:v", "libvpx-vp9", "-i", alpha, "-f", "rawvideo", "-pix_fmt", "rgba", "-" }, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            Bytes so, se;
            probe.communicate (null, null, out so, out se);
            unowned uint8[] raw = so.get_data ();
            check (raw.length == 64 * 48 * 4 * 10, "vp9 alpha: ffmpeg decodes all 10 frames");
            bool clear = false, half = false;
            for (int i = 3; i < 64 * 48 * 4; i += 4) {
                if (raw[i] == 0) clear = true;
                if (raw[i] > 100 && raw[i] < 160) half = true;
            }
            check (clear && half, "vp9 alpha: ffmpeg sees transparent and half transparent pixels");
        }
        check (ad.alpha_seen, "vp9 alpha channel survives decoding");
        red_at (ad.first, ad.width, 8, 24, "vp9 alpha");
        double adur;
        check (has_audio_stream (alpha, out adur), "vp9 alpha webm has audio");
        try {
            render_one (p, comp, "dnxhr-mov", false);
            check (!Encoders.find ("dnxhr-mov").available, "dnxhr rejects tiny frames");
        } catch (Error e) {
            check (e.message.contains ("256"), "dnxhr explains the minimum size");
        }
        Composition big;
        var pbig = build_project (out big);
        big.width = 256;
        big.height = 144;
        foreach (var id in new string[] { "prores-4444-mov", "prores-422-mov", "dnxhr-mov" }) {
            var f = Encoders.find (id);
            if (!f.available) {
                print ("skip %s: %s\n", id, f.reason);
                continue;
            }
            var path = render_one (pbig, big, id, id == "prores-4444-mov");
            check (FileUtils.test (path, FileTest.EXISTS), id + " written");
            var ff = Encoders.ffmpeg_path ();
            if (ff != null) {
                var probe = new Subprocess.newv ({ ff, "-v", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "rgba", "-" }, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                Bytes stdout_bytes, stderr_bytes;
                probe.communicate (null, null, out stdout_bytes, out stderr_bytes);
                unowned uint8[] raw = stdout_bytes.get_data ();
                check (raw.length == 256 * 144 * 4 * 10, id + " ffmpeg decodes 10 frames (%d bytes)".printf (raw.length));
                red_at (raw[0:256 * 144 * 4], 256, 8, 24, id);
                if (id == "prores-4444-mov") {
                    bool seen = false;
                    for (int i = 3; i < 256 * 144 * 4; i += 4) if (raw[i] < 200) seen = true;
                    check (seen, "prores 4444 keeps alpha");
                }
            }
        }
        foreach (var id in new string[] { "wav", "flac", "aac" }) {
            var f = Encoders.find (id);
            if (!f.available) continue;
            var path = render_one (p, comp, id, false);
            double dur;
            check (has_audio_stream (path, out dur), id + " audio stream");
            check (near (dur, 1.0, 0.1), id + " duration %.3f".printf (dur));
        }
    } catch (Error e) {
        check (false, "formats: " + e.message);
    }
    var cancel = new Cancellable ();
    var om = new OutputModule ();
    om.format = "png-sequence";
    om.path = Path.build_filename (dir, "cancel/f_####.png");
    var list = new Gee.ArrayList<OutputModule> ();
    list.add (om);
    try {
        RenderJobs.render (p, comp, list, 0, 1, 1, false, cancel, (f, n) => { if (n == 2) cancel.cancel (); });
        check (false, "cancel should stop");
    } catch (Error e) {
        check (e is EncodeError && e.code == EncodeError.CANCELLED, "cancellation reported");
    }
    var bad = new OutputModule ();
    bad.format = "nope";
    try {
        Encoders.create (bad);
        check (false, "unknown format rejected");
    } catch (Error e) {
        check (e.message.contains ("nope"), "clear error for unknown format");
    }
    check (Encoders.frame_path ("/x/a_####.png", 7, "png") == "/x/a_0007.png", "frame path padding");
    check (Encoders.frame_path ("/x/a.png", 7, "png") == "/x/a_00007.png", "frame path without hashes");
}

void test_cli () {
    var cli = Environment.get_variable ("KEYFRAME_RENDER_CLI");
    if (cli == null || cli == "") {
        print ("skip cli: KEYFRAME_RENDER_CLI not set\n");
        return;
    }
    Composition comp;
    var p = build_project (out comp);
    var item = new RenderItem (comp.id);
    var om = new OutputModule ();
    om.format = "png-sequence";
    om.path = Path.build_filename (dir, "cli/frame_###.png");
    item.outputs.add (om);
    p.render_queue.add (item);
    var path = Path.build_filename (dir, "cli.keyframe");
    try {
        NativeFormat.save (p, path);
        var proc = new Subprocess.newv ({ cli, "--project", path, "--item", item.id }, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
        string so, se;
        proc.communicate_utf8 (null, null, out so, out se);
        check (proc.get_exit_status () == 0, "cli exits 0: " + se);
        check (so.contains ("progress 1.0000") && so.contains ("frame 9") && so.contains ("done ") && so.contains ("frame_000.png"), "cli protocol lines");
        check (FileUtils.test (Path.build_filename (dir, "cli/frame_009.png"), FileTest.EXISTS), "cli wrote last frame");
        var bad = new Subprocess.newv ({ cli, "--project", path, "--item", "missing" }, SubprocessFlags.STDOUT_PIPE);
        string bo;
        bad.communicate_utf8 (null, null, out bo, null);
        check (bad.get_exit_status () == 2 && bo.has_prefix ("error "), "cli reports missing item");
        var list = new Subprocess.newv ({ cli, "--list-formats" }, SubprocessFlags.STDOUT_PIPE);
        string lo;
        list.communicate_utf8 (null, null, out lo, null);
        check (lo.contains ("format h264-mp4|"), "cli lists formats");
    } catch (Error e) {
        check (false, "cli " + e.message);
    }
}

Composition lottie_source (Project p) {
    var comp = new Composition ("Lottie", 200, 120, 25, 2);
    p.add_item (comp);
    var nested = new Composition ("Inner", 50, 50, 25, 2);
    p.add_item (nested);
    var dot = Factory.solid (nested, "Dot", { 0, 1, 0, 1 }, 20, 20);
    dot.transform.prop ("position").value = { 25, 25, 0 };
    nested.add_layer (dot);
    var pre = Factory.precomp_layer (comp, nested);
    pre.transform.prop ("position").value = { 170, 30, 0 };
    comp.add_layer (pre);
    var nul = Factory.null_layer (comp);
    nul.transform.prop ("position").set_key (0, { 60, 60, 0 });
    nul.transform.prop ("position").set_key (1.5, { 120, 70, 0 });
    nul.transform.prop ("position").keys[0].set_easy_ease ();
    nul.transform.prop ("position").keys[1].set_easy_ease ();
    comp.add_layer (nul);
    var shape = Factory.shape_layer (comp, "Shape");
    var grp = Factory.shape_group ("Box");
    var c = grp.group ("contents");
    c.add<PropGroup> (Factory.rect (40, 30, 6));
    c.add<PropGroup> (Factory.fill ({ 1, 0.5, 0, 1 }));
    var st = Factory.stroke ({ 1, 1, 1, 1 }, 3);
    c.add<PropGroup> (st);
    var tm = Factory.trim ();
    tm.prop ("end").set_key (0, { 0 });
    tm.prop ("end").set_key (1, { 100 });
    tm.prop ("end").keys[0].out_interp = Interp.HOLD;
    c.add<PropGroup> (tm);
    shape.contents.add<PropGroup> (grp);
    shape.contents.add<PropGroup> (Factory.repeater (2));
    shape.transform.prop ("rotation").set_key (0, { 0 });
    shape.transform.prop ("rotation").set_key (2, { 90 });
    shape.parent_id = nul.id;
    shape.transform.prop ("position").value = { 0, 0, 0 };
    var m = Factory.mask (BezPath.rect (-60, -40, 120, 80));
    shape.masks.add<PropGroup> (m);
    EffectRegistry.add_to_layer (shape, "gaussian-blur");
    comp.add_layer (shape);
    var text = Factory.text_layer (comp, "Hi");
    text.name = "Hi";
    text.text_group.prop ("source-text").text.size = 24;
    text.transform.prop ("position").value = { 100, 110, 0 };
    var an = Factory.text_animator ("Fade");
    an.group ("selectors").add<PropGroup> (Factory.range_selector ());
    var op = Factory.animator_property ("opacity");
    op.value = { 0 };
    an.group ("properties").add<Property> (op);
    text.text_group.group ("animators").add<PropGroup> (an);
    comp.add_layer (text);
    var matte_src = Factory.solid (comp, "MatteSrc", { 1, 1, 1, 1 }, 200, 60);
    var matted = Factory.solid (comp, "Matted", { 0.2, 0.4, 1, 1 }, 200, 120);
    comp.add_layer (matted, comp.layers.size);
    comp.add_layer (matte_src, comp.layers.size - 1);
    matted.matte_mode = MatteMode.ALPHA;
    matte_src.transform.prop ("position").value = { 100, 90, 0 };
    return comp;
}

void test_lottie () {
    var p = new Project ();
    var comp = lottie_source (p);
    var ex = new LottieExport (p);
    var text = ex.export (comp);
    try {
        var root = JsonUtil.parse (text).get_object ();
        check (JsonUtil.num (root, "fr") == 25 && JsonUtil.num (root, "op") == 50 && JsonUtil.num (root, "w") == 200, "lottie header");
        var layers = root.get_array_member ("layers");
        check (layers.get_length () == comp.layers.size, "lottie layer count");
        int[] types = {};
        foreach (var e in layers.get_elements ()) types += (int) JsonUtil.num (e.get_object (), "ty");
        string text_nm = "";
        foreach (var e in layers.get_elements ()) if (JsonUtil.num (e.get_object (), "ty") == 5) text_nm = JsonUtil.str (e.get_object (), "nm");
        check (text_nm == "Hi", "text layer name exported (got '%s', model '%s')".printf (text_nm, comp.layers[0].name));
        var fl = root.get_object_member ("fonts").get_array_member ("list").get_element (0).get_object ();
        check (JsonUtil.str (fl, "fStyle") == "Regular" && JsonUtil.str (fl, "fFamily") == "Sans", "font list entry");
        check (0 in types && 1 in types && 3 in types && 4 in types && 5 in types, "lottie layer types");
        check (root.get_array_member ("assets").get_length () == 1, "precomp asset");
        Json.Object? shape_o = null, null_o = null, matted_o = null, src_o = null;
        foreach (var e in layers.get_elements ()) {
            var o = e.get_object ();
            if (JsonUtil.str (o, "nm") == "Shape") shape_o = o;
            if (JsonUtil.num (o, "ty") == 3) null_o = o;
            if (JsonUtil.str (o, "nm") == "Matted") matted_o = o;
            if (JsonUtil.str (o, "nm") == "MatteSrc") src_o = o;
        }
        check (shape_o != null && shape_o.has_member ("parent") && shape_o.has_member ("masksProperties"), "parent and masks exported");
        var pk = null_o.get_object_member ("ks").get_object_member ("p");
        check (JsonUtil.num (pk, "a") == 1, "animated position");
        var k0 = pk.get_array_member ("k").get_element (0).get_object ();
        check (k0.has_member ("o") && k0.has_member ("i") && k0.has_member ("to") && k0.has_member ("ti"), "easing and spatial tangents exported");
        var shapes = shape_o.get_array_member ("shapes");
        var gr = shapes.get_element (0).get_object ();
        var it = gr.get_array_member ("it");
        check (JsonUtil.str (gr, "ty") == "gr" && JsonUtil.str (it.get_element (it.get_length () - 1).get_object (), "ty") == "tr", "group with trailing transform");
        string[] its = {};
        foreach (var e in it.get_elements ()) its += JsonUtil.str (e.get_object (), "ty");
        check ("rc" in its && "fl" in its && "st" in its && "tm" in its, "group items");
        check (JsonUtil.str (shapes.get_element (1).get_object (), "ty") == "rp", "repeater exported");
        check (matted_o != null && JsonUtil.num (matted_o, "tt") == 1 && src_o != null && JsonUtil.num (src_o, "td") == 1, "track matte tt/td");
        bool blur_warned = false;
        foreach (var w in ex.warnings) if (w.contains ("Gaussian Blur")) blur_warned = true;
        check (blur_warned, "unsupported effect warned");
        var q = new Project ();
        var imp = new LottieImport (q);
        var back = imp.import_text (text);
        check (back.layers.size == comp.layers.size, "lottie import layer count");
        var bnull = back.layers[comp.layers.index_of (comp.layer_by_name (nul_name (comp)))];
        var orig_null = comp.layer_by_name (nul_name (comp));
        foreach (double t in new double[] { 0, 0.3, 0.75, 1.2, 1.5 }) {
            var a = orig_null.transform.prop ("position").value_at (t);
            var b = bnull.transform.prop ("position").value_at (bnull.layer_time (t));
            check (near (a[0], b[0], 0.2) && near (a[1], b[1], 0.2), "round trip position at %.2f (%.2f,%.2f vs %.2f,%.2f)".printf (t, a[0], a[1], b[0], b[1]));
        }
        var r1 = new Renderer (p);
        var r2 = new Renderer (q);
        var rs = new RenderSettings ();
        rs.use_cache = false;
        foreach (var e in comp.layer_by_name ("Shape").effects.children.to_array ()) comp.layer_by_name ("Shape").effects.remove (e);
        foreach (double t in new double[] { 0.2, 0.8, 1.6 }) {
            var i1 = r1.render (comp, t, rs);
            var i2 = r2.render (back, t, rs);
            double diff = 0;
            for (size_t i = 0; i < i1.data.length; i++) diff += (i1.data[i] - i2.data[i]).abs ();
            diff /= i1.data.length;
            check (diff < 0.01, "round trip render matches at %.1f (mean diff %.4f)".printf (t, diff));
        }
        FileUtils.set_contents (Path.build_filename (dir, "export.json"), text);
    } catch (Error e) {
        check (false, "lottie " + e.message);
    }
}

string nul_name (Composition c) {
    foreach (var l in c.layers) if (l.kind == LayerKind.NULL) return l.name;
    return "";
}

void test_otio () {
    var p = new Project ();
    var comp = new Composition ("Edit", 320, 180, 24, 5);
    p.add_item (comp);
    var clip = new AudioClip ();
    clip.samples = new float[48000 * 2 * 3];
    var wav = Path.build_filename (dir, "otio.wav");
    var nested = new Composition ("Title", 320, 180, 24, 3);
    p.add_item (nested);
    try {
        FileUtils.set_data (wav, Wav.encode (clip));
        var f = MediaPool.probe (wav);
        p.add_item (f);
        var l = Factory.footage_layer (comp, f);
        l.in_point = 1;
        l.out_point = 3;
        l.start_time = 0.5;
        comp.add_layer (l);
        var pre = Factory.precomp_layer (comp, nested);
        pre.in_point = 2;
        pre.out_point = 4;
        pre.start_time = 2;
        comp.add_layer (pre);
        p.path = Path.build_filename (dir, "otio.keyframe");
        NativeFormat.save (p, p.path);
        var warnings = new Gee.ArrayList<string> ();
        var text = Otio.export (p, comp, warnings);
        FileUtils.set_contents (Path.build_filename (dir, "edit.otio"), text);
        var root = JsonUtil.parse (text).get_object ();
        check (JsonUtil.str (root, "OTIO_SCHEMA") == "Timeline.1", "otio schema");
        var q = NativeFormat.load (p.path);
        var back = Otio.import_text (q, text, warnings);
        check (back.layers.size == 2, "otio import layers");
        var bl = back.layers[back.layers.size - 1];
        check (near (bl.in_point, 1) && near (bl.out_point, 3) && near (bl.start_time, 0.5), "otio footage timing round trip");
        var bp = back.layers[0];
        check (bp.kind == LayerKind.PRECOMP && near (bp.in_point, 2) && near (bp.start_time, 2), "otio composition reference round trip");
        check (near (back.fps, 24), "otio rate");
        var refj = JsonUtil.parse (Otio.composition_reference (p, nested)).get_object ();
        check (refj.get_object_member ("tracks").get_array_member ("children").get_length () == 1, "composition reference clip");
    } catch (Error e) {
        check (false, "otio " + e.message);
    }
}

void test_templates () {
    var p = new Project ();
    var comp = new Composition ("Lower Third", 200, 100, 25, 2);
    p.add_item (comp);
    var t = Factory.text_layer (comp, "Name");
    comp.add_layer (t);
    var s = Factory.solid (comp, "Bar", { 1, 0, 0, 1 }, 200, 20);
    comp.add_layer (s);
    var shape = Factory.shape_layer (comp, "Accent");
    var g = Factory.shape_group ("G");
    var fill = Factory.fill ({ 0, 1, 0, 1 });
    g.group ("contents").add<PropGroup> (Factory.rect (10, 10));
    g.group ("contents").add<PropGroup> (fill);
    shape.contents.add<PropGroup> (g);
    comp.add_layer (shape);
    MotionTemplates.expose (comp, t, t.text_group.prop ("source-text"), "Title");
    MotionTemplates.expose (comp, shape, fill.prop ("color"), "Accent Color");
    MotionTemplates.expose (comp, s, s.transform.prop ("opacity"), "Bar Opacity");
    check (MotionTemplates.params (comp).size == 3, "three exposed params");
    try {
        int n = MotionTemplates.apply_overrides (comp, "{\"Title\":\"Ada Lovelace\",\"Accent Color\":\"#0000ff\",\"Bar Opacity\":40,\"Unknown\":1}");
        check (n == 3, "three overrides applied");
        check (t.text_group.prop ("source-text").text.text == "Ada Lovelace", "text override");
        check (near (fill.prop ("color").value[2], 1) && near (fill.prop ("color").value[1], 0), "colour override");
        check (near (s.transform.prop ("opacity").value[0], 40), "number override");
        var path = Path.build_filename (dir, "lower-third.keyframe");
        var extra = new Composition ("Unrelated", 10, 10, 25, 1);
        p.add_item (extra);
        MotionTemplates.save_template (p, comp, path);
        var inst = MotionTemplates.instantiate (path, "{\"Title\":\"Grace Hopper\"}");
        check (inst.compositions ().size == 1, "template keeps only needed compositions");
        var main = MotionTemplates.main_composition (inst);
        check (main != null && main.name == "Lower Third", "template main composition");
        var tl = main.layer_by_name (t.name);
        check (tl.text_group.prop ("source-text").text.text == "Grace Hopper", "instantiated override");
        check (MotionTemplates.values_json (main).contains ("Grace Hopper"), "values json");
    } catch (Error e) {
        check (false, "templates " + e.message);
    }
}

uint8[]? pull_frame (string desc, double seek_to, out int w, out int h) {
    w = h = 0;
    try {
        var pipe = Gst.parse_launch (desc + " ! videoconvert ! video/x-raw,format=RGBA ! appsink name=sink sync=false") as Gst.Pipeline;
        var sink = pipe.get_by_name ("sink") as Gst.App.Sink;
        pipe.set_state (Gst.State.PAUSED);
        Gst.State st;
        pipe.get_state (out st, null, 30 * Gst.SECOND);
        if (seek_to > 0) {
            pipe.seek_simple (Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.ACCURATE, (int64) (seek_to * Gst.SECOND));
            pipe.get_state (out st, null, 30 * Gst.SECOND);
        }
        var sample = sink.pull_preroll ();
        int64 dur;
        pipe.query_duration (Gst.Format.TIME, out dur);
        pipe.set_state (Gst.State.NULL);
        if (sample == null) return null;
        unowned Gst.Structure cs = sample.get_caps ().get_structure (0);
        cs.get_int ("width", out w);
        cs.get_int ("height", out h);
        Gst.MapInfo info;
        var b = sample.get_buffer ();
        b.map (out info, Gst.MapFlags.READ);
        var r = info.data[0:info.size];
        b.unmap (info);
        return r;
    } catch (Error e) {
        check (false, "pipeline " + e.message);
        return null;
    }
}

void test_gst_plugin () {
    if (Gst.ElementFactory.find ("keyframedec") == null) {
        print ("skip gst plugin: keyframedec not found\n");
        return;
    }
    Composition comp;
    var p = build_project (out comp);
    var path = Path.build_filename (dir, "live.keyframe");
    try {
        NativeFormat.save (p, path);
        var disc = new Gst.PbUtils.Discoverer (30 * Gst.SECOND);
        var info = disc.discover_uri (File.new_for_path (path).get_uri ());
        check (near (info.get_duration () / (double) Gst.SECOND, 1.0, 0.01), "discoverer reads the composition duration");
        var vs = info.get_video_streams ();
        check (vs.length () == 1 && ((Gst.PbUtils.DiscovererVideoInfo) vs.data).get_width () == 64, "discoverer sees the video stream");
        int w, h;
        var px = pull_frame ("uridecodebin uri=" + File.new_for_path (path).get_uri (), 0.5, out w, out h);
        check (px != null && w == 64 && h == 48, "uridecodebin plays the composition");
        var r = new Renderer (p);
        var rs = new RenderSettings ();
        rs.use_cache = false;
        var direct = Encoders.rgba8 (r.render (comp, 0.5, rs), true);
        int maxd = 0;
        for (int i = 0; px != null && i < direct.length && i < px.length; i++) maxd = int.max (maxd, ((int) direct[i] - (int) px[i]).abs ());
        check (px != null && maxd <= 2, "seeked frame matches a direct render (max diff %d)".printf (maxd));
        var cpx = pull_frame ("filesrc location=\"" + path + "\" ! keyframedec", 0, out w, out h);
        check (cpx != null && cpx[(24 * 64 + 8) * 4] > 200, "first frame red");
        var tpath = Path.build_filename (dir, "lower-third.keyframe");
        if (FileUtils.test (tpath, FileTest.EXISTS)) {
            var a = pull_frame ("filesrc location=\"" + tpath + "\" ! keyframedec overrides=\"{\\\"Bar Opacity\\\":100}\"", 0, out w, out h);
            var b = pull_frame ("filesrc location=\"" + tpath + "\" ! keyframedec overrides=\"{\\\"Bar Opacity\\\":0}\"", 0, out w, out h);
            int diff = 0;
            for (int i = 0; a != null && b != null && i < a.length; i++) diff += ((int) a[i] - (int) b[i]).abs ();
            check (a != null && b != null && diff > 1000, "overrides property changes the rendered template");
        }
    } catch (Error e) {
        check (false, "gst plugin " + e.message);
    }
}

void locate_build_outputs () {
    string exe;
    try {
        exe = FileUtils.read_link ("/proc/self/exe");
    } catch (Error e) {
        return;
    }
    var cli_dir = Path.build_filename (Path.get_dirname (exe), "src", "cli");
    if (Environment.get_variable ("KEYFRAME_RENDER_CLI") == null && FileUtils.test (Path.build_filename (cli_dir, "singularity-keyframe-render"), FileTest.IS_EXECUTABLE))
        Environment.set_variable ("KEYFRAME_RENDER_CLI", Path.build_filename (cli_dir, "singularity-keyframe-render"), true);
    var gst_dir = Path.build_filename (cli_dir, "gst");
    if (Environment.get_variable ("GST_PLUGIN_PATH") == null && FileUtils.test (Path.build_filename (gst_dir, "libgstkeyframe.so"), FileTest.EXISTS)) {
        Environment.set_variable ("GST_PLUGIN_PATH", gst_dir, true);
        Environment.set_variable ("GST_REGISTRY", Path.build_filename (Environment.get_tmp_dir (), "keyframe-gst-registry.bin"), true);
    }
}

int main (string[] args) {
    locate_build_outputs ();
    Gst.init (ref args);
    dir = out_dir ();
    test_audio_mix ();
    test_formats ();
    test_cli ();
    test_lottie ();
    test_otio ();
    test_templates ();
    test_gst_plugin ();
    print ("output in %s\n", dir);
    return finish ("keyframe-output");
}
