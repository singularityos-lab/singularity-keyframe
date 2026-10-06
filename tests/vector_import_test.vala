using Singularity.Apps.Keyframe;
using Singularity.Apps.Keyframe.Test;

int main (string[] args) {
    Gst.init (ref args);
    var dir = tmp_dir ();
    var svg = Path.build_filename (dir, "art.svg");
    try {
        FileUtils.set_contents (svg, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"100\" viewBox=\"0 0 200 100\">"
            + "<rect x=\"10\" y=\"10\" width=\"80\" height=\"80\" fill=\"#ff0000\" stroke=\"#0000ff\" stroke-width=\"4\"/>"
            + "<circle cx=\"150\" cy=\"50\" r=\"40\" fill=\"#00ff00\"/></svg>");
        var p = new Project ();
        var comp = new Composition ("C", 200, 100, 30, 1);
        p.add_item (comp);
        var layers = VectorShapes.layers_from_file (comp, svg);
        check (layers.size >= 1, "svg becomes at least one layer");
        var shape = layers[layers.size - 1];
        check (shape.kind == LayerKind.SHAPE, "shape layer created");
        check (shape.contents.children.size >= 2, "one group per svg element");
        foreach (var l in layers) comp.add_layer (l);
        var r = new Renderer (p);
        var s = new RenderSettings ();
        s.use_cache = false;
        var img = r.render (comp, 0, s);
        float cr, cg, cb, ca;
        img.get_pixel (50, 50, out cr, out cg, out cb, out ca);
        check (cr > 0.9 && cg < 0.1 && ca > 0.99, "rect filled red");
        img.get_pixel (150, 50, out cr, out cg, out cb, out ca);
        check (cg > 0.9 && cr < 0.1, "circle filled green");
        img.get_pixel (10, 50, out cr, out cg, out cb, out ca);
        check (cb > 0.5, "rect stroke blue");
        var shape_prop = shape.contents.find ("group/contents/path/path") as Property;
        check (shape_prop != null && shape_prop.kind == PropKind.PATH, "paths are animatable path properties");
    } catch (Error e) {
        check (false, e.message);
    }
    return finish ("keyframe-vector-import");
}
