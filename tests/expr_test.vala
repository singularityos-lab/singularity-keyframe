using Singularity.Apps.Keyframe;
using Singularity.Apps.Keyframe.Test;

Interpreter interp;

JsValue? js (string code) {
    try {
        return interp.run (code);
    } catch (ExprError e) {
        stderr.printf ("error in %s: %s\n", code, e.message);
        return null;
    }
}

double jsn (string code) {
    var v = js (code);
    return v != null ? interp.to_number (v) : double.NAN;
}

string jss (string code) {
    var v = js (code);
    return v != null ? interp.to_string (v) : "<error>";
}

void test_language () {
    interp = new Interpreter ();
    check (near (jsn ("1 + 2 * 3 - 4 / 2"), 5), "precedence");
    check (near (jsn ("2 ** 3 ** 2"), 512), "power is right associative");
    check (near (jsn ("var a = 5; a += 3; a *= 2; a"), 16), "compound assignment");
    check (jss ("'a' + 1 + 2") == "a12", "string concatenation");
    check (jss ("[1, 2] + [3, 4]") == "4,6", "array addition");
    check (jss ("[2, 4] * 2") == "4,8", "array times number");
    check (jss ("3 * [1, 2]") == "3,6", "number times array");
    check (jss ("[10, 20] / 10") == "1,2", "array division");
    check (jss ("-[1, 2]") == "-1,-2", "array negation");
    check (near (jsn ("function fib(n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); } fib(15)"), 610), "recursion");
    check (near (jsn ("var mk = function (k) { return x => x * k; }; mk(3)(7)"), 21), "closures and arrows");
    check (near (jsn ("var s = 0; for (var i = 0; i < 10; i++) { if (i == 5) continue; if (i == 8) break; s += i; } s"), 23), "for with break and continue");
    check (near (jsn ("var n = 0; while (n < 5) n++; n"), 5), "while");
    check (near (jsn ("var n = 0; do { n += 2; } while (n < 7); n"), 8), "do while");
    check (near (jsn ("var t = 0; for (const v of [1, 2, 3]) t += v; t"), 6), "for of");
    check (jss ("var o = {a: 1, b: 2}; var k = ''; for (var x in o) k += x; k") == "ab", "for in");
    check (jss ("switch (2) { case 1: 'one'; break; case 2: 'two'; break; default: 'other'; }") == "two", "switch");
    check (jss ("try { throw 'boom'; } catch (e) { 'caught ' + e }") == "caught boom", "try catch");
    check (jss ("var w = 'x'; `a${w}b${1 + 1}`") == "axb2", "template literal");
    check (jss ("typeof 1 + typeof 'a' + typeof undefinedThing") == "numberstringundefined", "typeof");
    check (jss ("[3, 1, 2].sort().join('-')") == "1-2-3", "array sort and join");
    check (jss ("[1, 2, 3].map(x => x * 2).filter(x => x > 2).join()") == "4,6", "map and filter");
    check (near (jsn ("[1, 2, 3, 4].reduce((a, b) => a + b, 0)"), 10), "reduce");
    check (jss ("'Hello World'.toUpperCase().split(' ')[1]") == "WORLD", "string methods");
    check (jss ("'abc'.substring(1)") == "bc" && jss ("'abcdef'.slice(-2)") == "ef", "substring and slice");
    check (jss ("(3.14159).toFixed(2)") == "3.14", "toFixed");
    check (near (jsn ("Math.max(1, 5, 3) + Math.floor(2.7) + Math.abs(-1)"), 8), "Math");
    check (near (jsn ("parseInt('42px') + parseFloat('0.5')"), 42.5), "parse functions");
    check (jss ("var o = {a: {b: [1, 2]}}; o.a.b[1] = 9; o.a.b") == "1,9", "nested member assignment");
    check (jss ("JSON.stringify({x: [1, 'a']})") == "{\"x\":[1,\"a\"]}", "JSON.stringify");
    check (near (jsn ("var a = null; a ?? 7"), 7), "nullish coalescing");
    check (near (jsn ("if (false) 1; else 2"), 2), "last expression statement value");
    interp.step_limit = 100000;
    bool limited = false;
    try {
        interp.run ("while (true) {}");
    } catch (ExprError e) {
        limited = e is ExprError.LIMIT;
    }
    check (limited, "infinite loop stops at the step limit");
    bool deep = false;
    try {
        interp.run ("function f() { return f(); } f()");
    } catch (ExprError e) {
        deep = e is ExprError.LIMIT;
    }
    check (deep, "runaway recursion stops");
    bool syntax = false;
    try {
        interp.run ("1 +");
    } catch (ExprError e) {
        syntax = e is ExprError.SYNTAX;
    }
    check (syntax, "syntax error reported");
    interp.step_limit = 2000000;
}

Layer solid_at (Composition comp, string name, double x, double y) {
    var l = Factory.solid (comp, name, { 1, 0, 0, 1 }, 100, 100);
    l.transform.prop ("position").value = { x, y, 0 };
    comp.add_layer (l, comp.layers.size);
    return l;
}

double ev (Property p, double t, int i = 0) {
    var v = p.value_at (t);
    return i < v.length ? v[i] : double.NAN;
}

void test_expressions () {
    Expressions.install ();
    var project = new Project ();
    var comp = new Composition ("Main", 640, 360, 30, 5);
    project.add_item (comp);
    var other = new Composition ("Other", 100, 100, 30, 5);
    project.add_item (other);
    solid_at (other, "Inner", 0, 0);
    var a = solid_at (comp, "A", 0, 0);
    var pa = a.transform.prop ("position");
    pa.set_key (0, { 0, 0, 0 });
    pa.set_key (2, { 200, 0, 0 });
    var b = solid_at (comp, "B", 320, 180);
    var pb = b.transform.prop ("position");
    pb.expression = "thisComp.layer(\"A\").transform.position";
    check (near (ev (pb, 1, 0), 100), "link to another layer position");
    check (pb.expression_error == "", "no error on link");
    var rot = b.transform.prop ("rotation");
    rot.expression = "time * 90";
    check (near (ev (rot, 1), 90), "time expression");
    rot.expression = "linear(time, 0, 2, 0, 100)";
    check (near (ev (rot, 1), 50) && near (ev (rot, 3), 100), "linear with clamping");
    rot.expression = "ease(time, 0, 2, 0, 100)";
    check (near (ev (rot, 1), 50, 0.5) && ev (rot, 0.3) < 15, "ease");
    rot.expression = "easeIn(time, 0, 2, 0, 100) < linear(time, 0, 2, 0, 100) ? 1 : 0";
    check (near (ev (rot, 0.5), 1), "easeIn starts slower than linear");
    rot.expression = "linear(0.5, [0, 0], [10, 20])[1]";
    check (near (ev (rot, 0), 10), "three argument linear with arrays");

    var op = b.transform.prop ("opacity");
    op.set_key (0, { 0 });
    op.set_key (1, { 100 });
    op.expression = "loopOut()";
    check (near (ev (op, 1.5), 50), "loopOut cycle");
    op.expression = "loopOut('pingpong')";
    check (near (ev (op, 1.25), 75), "loopOut pingpong");
    op.expression = "loopOut('offset')";
    op.max = 1000;
    check (near (ev (op, 1.5), 150), "loopOut offset");
    op.expression = "loopOut('continue')";
    check (near (ev (op, 1.5), 150, 0.5), "loopOut continue");
    op.expression = "loopIn('cycle')";
    op.keys[0].time = 1;
    op.keys[1].time = 2;
    op.keys[0].value = { 0 };
    op.keys[1].value = { 100 };
    check (near (ev (op, 0.5), 50), "loopIn cycle");
    op.expression = "valueAtTime(1.5) + numKeys";
    check (near (ev (op, 0), 52), "valueAtTime and numKeys");
    op.expression = "key(2).time * 10 + nearestKey(1.2).index";
    check (near (ev (op, 0), 21), "key and nearestKey");
    op.expression = "velocity";
    check (near (ev (op, 1.5), 100, 0.5), "velocity");
    op.clear_keys ();
    op.max = 100;

    var fx = EffectRegistry.add_to_layer (b, "slider-control");
    fx.prop ("slider").set_value ({ 42 });
    op.expression = "effect(\"Slider Control\")(\"Slider\")";
    check (near (ev (op, 0), 42), "expression control slider");
    op.expression = "effect(1)(1).value + 1";
    check (near (ev (op, 0), 43), "effect by index");

    var sc = b.transform.prop ("scale");
    sc.expression = "wiggle(2, 50)";
    double w1 = ev (sc, 0.37), w2 = ev (sc, 0.37), w3 = ev (sc, 1.91);
    check (near (w1, w2, 1e-9), "wiggle deterministic");
    check ((w1 - 100).abs () <= 50.01 && (w3 - 100).abs () <= 50.01, "wiggle bounded by amplitude");
    check ((w1 - w3).abs () > 1e-4, "wiggle varies over time");
    sc.expression = "seedRandom(5, true); random([10, 20], [20, 30])";
    double r1 = ev (sc, 0.1), r2 = ev (sc, 2.2);
    check (near (r1, r2, 1e-12) && r1 >= 10 && r1 <= 20 && ev (sc, 0.1, 1) >= 20, "timeless seeded random");
    sc.expression = "[random(), random()]";
    check ((ev (sc, 0.1) - ev (sc, 0.2)).abs () > 1e-9, "random changes per frame");
    check (ev (sc, 0.1, 0) != ev (sc, 0.1, 1), "successive random calls differ");
    sc.expression = "var v = gaussRandom(); [v * 100, 0]";
    check (ev (sc, 0.5) >= 0 && ev (sc, 0.5) <= 100, "gaussRandom range");
    sc.expression = "[noise(time) * 100 + 100, 100]";
    check ((ev (sc, 0.3) - 100).abs () <= 100, "noise");
    sc.expression = "clamp([150, -5], 0, 100)";
    check (near (ev (sc, 0, 0), 100) && near (ev (sc, 0, 1), 0), "clamp");
    sc.expression = "[length([3, 4]), length([0, 0], [6, 8])]";
    check (near (ev (sc, 0, 0), 5) && near (ev (sc, 0, 1), 10), "length");
    sc.expression = "var n = normalize([3, 4]); [n[0] * 10, dot([1, 2], [3, 4])]";
    check (near (ev (sc, 0, 0), 6) && near (ev (sc, 0, 1), 11), "normalize and dot");
    sc.expression = "cross([1, 0, 0], [0, 1, 0])";
    check (near (ev (sc, 0, 2), 1), "cross");
    sc.expression = "add([1, 2], [3, 4]) + mul([1, 1], 2)";
    check (near (ev (sc, 0, 0), 6) && near (ev (sc, 0, 1), 8), "vector helpers");
    sc.expression = "[radiansToDegrees(Math.PI), degreesToRadians(180) * 10]";
    check (near (ev (sc, 0, 0), 180) && near (ev (sc, 0, 1), Math.PI * 10), "angle conversion");
    sc.expression = "[timeToFrames(1), framesToTime(15) * 100]";
    check (near (ev (sc, 0, 0), 30) && near (ev (sc, 0, 1), 50), "frame conversion");
    sc.expression = "posterizeTime(2); [time * 100, 100]";
    check (near (ev (sc, 0.7), 50), "posterizeTime");
    sc.expression = "var p = thisComp.layer(\"A\").toComp([0, 0]); p";
    check (near (ev (sc, 1, 0), 50) && near (ev (sc, 1, 1), -50), "toComp");
    sc.expression = "thisComp.layer(\"A\").fromComp([100, 0])";
    check (near (ev (sc, 1, 0), 50) && near (ev (sc, 1, 1), 50), "fromComp");
    sc.expression = "posterizeTime(4); [value[0] + time * 1000, 0]";
    check (near (ev (sc, 0.3), 100 + 250), "posterizeTime also updates value time");
    sc.expression = "lookAt([0, 0, 0], [0, 0, 100])";
    check (near (ev (sc, 0, 0), 0) && near (ev (sc, 0, 1), 0), "lookAt straight ahead");
    sc.expression = "[thisComp.width, thisComp.numLayers]";
    check (near (ev (sc, 0, 0), 640) && near (ev (sc, 0, 1), 2), "comp attributes");
    sc.expression = "[comp(\"Other\").layer(1).width, index]";
    check (near (ev (sc, 0, 0), 100) && near (ev (sc, 0, 1), 2), "comp by name and index");
    sc.expression = "[inPoint, outPoint]";
    check (near (ev (sc, 0, 1), 5), "inPoint and outPoint");
    sc.expression = "[thisLayer.name == 'B' ? 1 : 0, transform.position[0]]";
    check (near (ev (sc, 1, 0), 1) && near (ev (sc, 1, 1), 100), "layer members without thisLayer");
    sc.expression = "foo +";
    var pre = sc.raw_value_at (0);
    check (near (ev (sc, 0), pre[0]) && sc.expression_error != "", "syntax error falls back to keyframed value");
    sc.expression = "undefinedThing * 2";
    ev (sc, 0);
    check (sc.expression_error.contains ("undefinedThing"), "runtime error message");
    sc.expression = "while (true) {}";
    check (near (ev (sc, 0), pre[0]) && sc.expression_error != "", "sandbox limit falls back");
    sc.expression = "";

    var shape = Factory.shape_layer (comp, "Box");
    var grp = Factory.shape_group ("Group 1");
    grp.group ("contents").add<PropGroup> (Factory.rect (100, 50));
    grp.group ("contents").add<PropGroup> (Factory.fill ({ 1, 1, 1, 1 }));
    shape.contents.add<PropGroup> (grp);
    comp.add_layer (shape, comp.layers.size);
    sc.expression = "var r = thisComp.layer(\"Box\").sourceRectAtTime(); [r.width, r.height]";
    check (near (ev (sc, 0, 0), 100) && near (ev (sc, 0, 1), 50), "sourceRectAtTime");
    sc.expression = "thisComp.layer(\"Box\").content(\"Group 1\").content(\"Rectangle Path\").size";
    check (near (ev (sc, 0, 0), 100), "shape content access");

    var mask = Factory.mask (BezPath.rect (0, 0, 10, 10));
    mask.name = "Mask 1";
    b.masks.add<PropGroup> (mask);
    var mp = mask.prop ("path");
    mp.expression = "createPath([[0, 0], [100, 0], [100, 100]], [], [], true)";
    var path = mp.path_at (0);
    check (path.count == 3 && near (path.v[1].x, 100), "createPath path expression");
    sc.expression = "var pts = mask(\"Mask 1\").maskPath.points(); [pts.length, pts[2][1]]";
    check (near (ev (sc, 0, 0), 3) && near (ev (sc, 0, 1), 100), "points of a path property");
    sc.expression = "mask(\"Mask 1\").maskPath.isClosed() ? [1, 1] : [0, 0]";
    check (near (ev (sc, 0), 1), "isClosed");

    var t = Factory.text_layer (comp, "Hello");
    t.name = "T";
    comp.add_layer (t, comp.layers.size);
    sc.expression = "[thisComp.layer(\"T\").text.sourceText.length, 0]";
    check (near (ev (sc, 0), 5), "sourceText string");

    var ref1 = Expressions.reference_for (b, pa);
    check (ref1 == "thisComp.layer(\"A\").transform.position", "pick whip reference to another layer: " + ref1);
    var ref2 = Expressions.reference_for (a, fx.prop ("slider"));
    check (ref2.contains ("effect(\"Slider Control\")(\"Slider\")"), "pick whip reference to an effect: " + ref2);
    var lo = a.transform.prop ("opacity");
    lo.expression = ref2;
    check (near (ev (lo, 0), 42), "pick whip expression evaluates");
    var ref3 = Expressions.reference_for (b, op);
    check (ref3 == "transform.opacity", "same layer reference: " + ref3);

    var an = Factory.text_animator ("Animator 1");
    an.group ("selectors").add<PropGroup> (Factory.expression_selector ());
    t.text_group.group ("animators").add<PropGroup> (an);
    var doc = t.text_group.prop ("source-text").text;
    var tl = TextRenderer.layout_glyphs (doc);
    var sel = an.group ("selectors").children[0] as PropGroup;
    double first = TextRenderer.selector_amount (sel, tl.glyphs[0], tl, 0, t);
    double last = TextRenderer.selector_amount (sel, tl.glyphs[tl.glyphs.size - 1], tl, 0, t);
    check (near (first, 0.2) && near (last, 1), "expression selector uses textIndex and textTotal");
}

void test_scripting () {
    var project = new Project ();
    string output;
    string code = """
var comp = app.project.addComp("Scripted", 320, 240, 1, 4, 25);
var solid = comp.layers.addSolid([1, 0, 0], "Red", 100, 100);
var p = solid.transform.position;
p.setValueAtTime(0, [0, 0]);
p.setValueAtTime(2, [100, 50]);
p.setInterpolationTypeAtKey(1, KeyframeInterpolationType.HOLD);
solid.transform.rotation.expression = "time * 45";
solid.motionBlur = true;
var shape = comp.layers.addShape();
shape.name = "Shapes";
var grp = shape.content.addProperty("group");
grp.content.addProperty("rect");
grp.content.addProperty("fill");
var blur = solid.addEffect("gaussian-blur");
blur("Blurriness").setValue(5);
var txt = comp.layers.addText("Hi");
txt.text.sourceText.setValue("Hello");
var cam = comp.layers.addCamera("Cam", [160, 120]);
var rq = app.project.renderQueue.add(comp, {format: "png-sequence", path: "/out/frame_####.png"});
rq.outputModule(1).alpha = true;
var folder = app.project.addFolder("Stuff");
comp.parentFolder = folder;
solid.parent = cam;
for (var i = 1; i <= comp.numLayers; i++) print(comp.layer(i).name);
comp.numLayers;
""";
    bool ok = Scripting.run (project, code, out output);
    if (!ok) stderr.printf ("script output: %s\n", output);
    check (ok, "script runs");
    var comp = project.comp_by_name ("Scripted");
    check (comp != null && comp.width == 320 && comp.fps == 25 && comp.duration == 4, "addComp arguments");
    if (comp == null) return;
    check (comp.layers.size == 4, "four layers added");
    var red = comp.layer_by_name ("Red");
    check (red != null && red.transform.prop ("position").keys.size == 2, "keyframes created by script");
    check (red.transform.prop ("position").keys[0].in_interp == Interp.HOLD, "interpolation set by script");
    check (red.transform.prop ("rotation").expression == "time * 45", "expression set by script");
    check (red.motion_blur, "layer switch set by script");
    check (red.effects.children.size == 1 && ((PropGroup) red.effects.children[0]).prop ("blurriness").value[0] == 5, "effect added and set");
    var sh = comp.layer_by_name ("Shapes");
    check (sh != null && sh.contents.find ("group/contents/rectangle") != null && sh.contents.find ("group/contents/fill") != null, "shape contents added");
    var txt = comp.layers[1];
    check (txt.kind == LayerKind.TEXT && txt.text_group.prop ("source-text").text.text == "Hello", "text set by script");
    check (project.render_queue.size == 1 && project.render_queue[0].outputs[0].alpha && project.render_queue[0].outputs[0].path == "/out/frame_####.png", "render queue item");
    var cam = comp.layer_by_name ("Cam");
    check (cam != null && red.parent_id == cam.id, "parenting by script");
    check (comp.folder_id != "", "item moved to folder");
    check (output.contains ("Red") && output.contains ("Cam"), "print output");
    string out2;
    bool bad = Scripting.run (project, "app.project.item(99)", out out2);
    check (!bad && out2.has_prefix ("Error:"), "script errors are reported");
    Expressions.install ();
    var rr = comp.layer_by_name ("Red");
    check (near (rr.transform.prop ("rotation").scalar_at (2), 90), "script expression evaluates");
}

void test_character_offset () {
    var comp = new Composition ("C", 200, 100, 30, 2);
    var t = Factory.text_layer (comp, "abz9");
    var an = Factory.text_animator ("Offset");
    an.group ("selectors").add<PropGroup> (Factory.range_selector ());
    var co = Factory.animator_property ("character-offset");
    co.value = { 1 };
    an.group ("properties").add<Property> (co);
    t.text_group.group ("animators").add<PropGroup> (an);
    var doc = t.text_group.prop ("source-text").text;
    var r = TextOffsets.apply (t.text_group, doc, 0);
    check (r.text == "bca0", "character offset shifts letters and digits with wrap: " + r.text);
    var sel = an.group ("selectors").children[0] as PropGroup;
    sel.prop ("end").value = { 50 };
    r = TextOffsets.apply (t.text_group, doc, 0);
    check (r.text == "bcz9", "character offset limited by the selector: " + r.text);
    co.value = { -2 };
    sel.prop ("end").value = { 100 };
    r = TextOffsets.apply (t.text_group, doc, 0);
    check (r.text == "yzx7", "negative offset: " + r.text);
    check (doc.text == "abz9", "original document untouched");
}

void test_tokens () {
    var p = new Property ("x", "X", PropKind.SCALAR, { 0 });
    var k0 = p.set_key (0, { 0 });
    var k1 = p.set_key (0.22, { 100 });
    TokenCurve? standard = null;
    foreach (var c in MotionTokens.presets ()) if (c.curve_token == "standard") standard = c;
    check (standard != null, "standard preset from the desktop tokens");
    if (standard == null) return;
    MotionTokens.apply_preset (k0, k1, standard);
    double mid = p.value_at (0.11)[0];
    double expect = Singularity.Motion.Curve.STANDARD.ease (0.5) * 100;
    check (near (mid, expect, 0.5), "preset applied to keyframes matches the token curve");
    var list = MotionTokens.export_property (p, "fade");
    check (list.size == 1 && list[0].curve_token == "standard" && list[0].duration_token == "medium", "export matches curve and duration tokens");
    var vala = MotionTokens.to_vala (list);
    check (vala.contains ("Singularity.Motion.Curve.STANDARD") && vala.contains ("Singularity.Motion.Duration.MEDIUM"), "vala snippet uses token names");
    var css = MotionTokens.to_css (list);
    check (css.contains ("--keyframe-fade-easing") && css.contains ("cubic-bezier(0.2, 0, 0, 1)"), "css output: " + css);
    try {
        var back = MotionTokens.parse_json (MotionTokens.to_json (list));
        check (back.size == 1 && near (back[0].x1, 0.2) && back[0].duration_ms == 220, "json round trip");
    } catch (Error e) {
        check (false, "tokens json " + e.message);
    }
    k1.ease_in_x = 0.5;
    k1.ease_in_y = 0.9;
    var custom = MotionTokens.export_property (p, "custom");
    check (custom[0].curve_token == "" && MotionTokens.to_vala (custom).contains ("set_bezier"), "custom curve exported as bezier");
}

int main (string[] args) {
    Gst.init (ref args);
    test_language ();
    test_expressions ();
    test_scripting ();
    test_character_offset ();
    test_tokens ();
    return finish ("keyframe-expr");
}
