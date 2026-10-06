namespace Singularity.Apps.Keyframe {

    namespace Scripting {
        public bool run (Project project, string code, out string output) {
            var it = Expressions.interpreter ();
            var c = new ExprContext ();
            c.project = project;
            c.mutable = true;
            Expressions.push (c);
            bool ok = true;
            int old_limit = it.step_limit;
            it.step_limit = 50000000;
            try {
                var env = new Env (it.globals);
                env.define ("app", ScriptHost.app_object (project, c));
                env.define ("print", JsValue.native ("print", (it2, self, args) => {
                    var parts = new string[args.length];
                    for (int i = 0; i < args.length; i++) parts[i] = it2.to_string (args[i]);
                    c.output.append (string.joinv (" ", parts));
                    c.output.append_c ('\n');
                    return JsValue.undefined ();
                }));
                env.define ("alert", env.vars["print"]);
                var dollar = new JsObject ();
                dollar.put ("writeln", env.vars["print"]);
                dollar.put ("write", env.vars["print"]);
                env.define ("$", JsValue.object (dollar));
                var prog = it.compile (code);
                it.run_node (prog, env);
            } catch (ExprError e) {
                c.output.append ("Error: %s\n".printf (e.message));
                ok = false;
            }
            it.step_limit = old_limit;
            Expressions.pop ();
            output = c.output.str;
            return ok;
        }
    }

    namespace ScriptHost {
        private double[] doubles (Interpreter it, JsValue v) throws ExprError {
            var d = it.to_doubles (v);
            if (d == null) throw new ExprError.RUNTIME ("Expected a number or an array");
            return d;
        }

        private double num (Interpreter it, JsValue[] args, int i, double fallback) throws ExprError {
            if (i >= args.length || args[i].kind == JsKind.UNDEFINED) return fallback;
            return it.to_number (it.prim (args[i]));
        }

        private string str (Interpreter it, JsValue[] args, int i, string fallback) {
            if (i >= args.length || args[i].kind == JsKind.UNDEFINED) return fallback;
            return it.to_string (args[i]);
        }

        private Interp interp_from (double code) {
            int c = (int) code;
            if (c == 6614) return Interp.HOLD;
            if (c == 6613) return Interp.BEZIER;
            return Interp.LINEAR;
        }

        private double interp_code (Interp i) {
            switch (i) {
                case Interp.HOLD: return 6614;
                case Interp.BEZIER: return 6613;
                default: return 6612;
            }
        }

        private double lt (Property p, double ct) {
            return ExprHost.layer_time (p, ct);
        }

        private int key_index (Interpreter it, Property p, JsValue[] args) throws ExprError {
            int i = (int) num (it, args, 0, 0) - 1;
            if (i < 0 || i >= p.keys.size) throw new ExprError.RUNTIME ("Key index %d out of range", i + 1);
            return i;
        }

        public void store_value (Interpreter it, Property p, double t, bool keyed, JsValue v) throws ExprError {
            var pv = it.prim (v);
            if (p.kind == PropKind.TEXT) {
                TextDocument doc = keyed ? p.text_at (t).copy () : (p.text ?? new TextDocument ()).copy ();
                if (pv.kind == JsKind.OBJECT) {
                    var o = pv.obj;
                    if (o.own ("text") != null) doc.text = it.to_string (o.own ("text"));
                    if (o.own ("fontSize") != null) doc.size = it.to_number (o.own ("fontSize"));
                    if (o.own ("font") != null) doc.font = it.to_string (o.own ("font"));
                    if (o.own ("tracking") != null) doc.tracking = it.to_number (o.own ("tracking"));
                    if (o.own ("fillColor") != null) {
                        var fc = doubles (it, o.own ("fillColor"));
                        doc.fill = { fc[0], fc.length > 1 ? fc[1] : 0, fc.length > 2 ? fc[2] : 0, fc.length > 3 ? fc[3] : 1 };
                    }
                    if (o.own ("justification") != null) doc.justify = (int) it.to_number (o.own ("justification"));
                } else {
                    doc.text = it.to_string (pv);
                }
                if (keyed) p.set_text_key (t, doc);
                else {
                    p.text = doc;
                    p.touch ();
                }
                return;
            }
            if (p.kind == PropKind.PATH) {
                var path = ExprHost.to_path (pv);
                if (path == null) throw new ExprError.RUNTIME ("Expected a path value");
                if (keyed) p.set_path_key (t, path);
                else {
                    p.path = path;
                    p.touch ();
                }
                return;
            }
            var d = doubles (it, pv);
            var full = new double[int.max (p.dims, d.length)];
            var base_v = keyed && p.keys.size > 0 ? p.raw_value_at (t) : p.value;
            for (int i = 0; i < full.length; i++) full[i] = i < d.length ? d[i] : (i < base_v.length ? base_v[i] : 0);
            if (p.kind == PropKind.COLOR && full.length < 4) {
                var c4 = new double[4];
                for (int i = 0; i < 4; i++) c4[i] = i < full.length ? full[i] : 1;
                full = c4;
            }
            if (p.dims > 0 && full.length > p.dims && p.kind != PropKind.COLOR) full = full[0:p.dims];
            if (keyed) p.set_key (t, full);
            else p.set_value (full);
        }

        public JsValue? prop_member (Property p, string name, ExprContext c) {
            switch (name) {
                case "setValue":
                    return JsValue.native (name, (it, self, args) => {
                        if (args.length == 0) throw new ExprError.RUNTIME ("setValue needs a value");
                        if (p.keys.size > 0) throw new ExprError.RUNTIME ("The property has keyframes; use setValueAtTime");
                        store_value (it, p, 0, false, args[0]);
                        return JsValue.undefined ();
                    });
                case "setValueAtTime":
                    return JsValue.native (name, (it, self, args) => {
                        if (args.length < 2) throw new ExprError.RUNTIME ("setValueAtTime needs a time and a value");
                        double t = lt (p, num (it, args, 0, 0));
                        store_value (it, p, t, true, args[1]);
                        var k = p.key_at (t);
                        return JsValue.number (k != null ? p.keys.index_of (k) + 1 : 0);
                    });
                case "setValuesAtTimes":
                    return JsValue.native (name, (it, self, args) => {
                        if (args.length < 2) throw new ExprError.RUNTIME ("setValuesAtTimes needs times and values");
                        var times = it.prim (args[0]);
                        var vals = it.prim (args[1]);
                        if (times.kind != JsKind.ARRAY || vals.kind != JsKind.ARRAY || times.arr.size != vals.arr.size) throw new ExprError.RUNTIME ("Times and values must be arrays of the same length");
                        for (int i = 0; i < times.arr.size; i++) store_value (it, p, lt (p, it.to_number (times.arr[i])), true, vals.arr[i]);
                        return JsValue.undefined ();
                    });
                case "addKey":
                    return JsValue.native (name, (it, self, args) => {
                        double t = lt (p, num (it, args, 0, 0));
                        if (p.kind == PropKind.PATH) p.set_path_key (t, p.raw_path_at (t));
                        else if (p.kind == PropKind.TEXT) p.set_text_key (t, p.text_at (t));
                        else p.set_key (t, p.raw_value_at (t));
                        return JsValue.number (p.keys.index_of (p.key_at (t)) + 1);
                    });
                case "keyTime":
                    return JsValue.native (name, (it, self, args) => JsValue.number (ExprHost.comp_time_of (p, p.keys[key_index (it, p, args)].time)));
                case "keyValue":
                    return JsValue.native (name, (it, self, args) => {
                        var k = p.keys[key_index (it, p, args)];
                        if (p.kind == PropKind.PATH) return ExprHost.path_value (k.path ?? new BezPath ());
                        if (p.kind == PropKind.TEXT) return JsValue.string_value ((k.text ?? new TextDocument ()).text);
                        return JsValue.from_value (k.value);
                    });
                case "removeKey":
                    return JsValue.native (name, (it, self, args) => {
                        p.remove_key (p.keys[key_index (it, p, args)]);
                        return JsValue.undefined ();
                    });
                case "setInterpolationTypeAtKey":
                    return JsValue.native (name, (it, self, args) => {
                        var k = p.keys[key_index (it, p, args)];
                        k.in_interp = interp_from (num (it, args, 1, 6612));
                        k.out_interp = interp_from (num (it, args, 2, num (it, args, 1, 6612)));
                        p.touch ();
                        return JsValue.undefined ();
                    });
                case "keyInInterpolationType":
                    return JsValue.native (name, (it, self, args) => JsValue.number (interp_code (p.keys[key_index (it, p, args)].in_interp)));
                case "keyOutInterpolationType":
                    return JsValue.native (name, (it, self, args) => JsValue.number (interp_code (p.keys[key_index (it, p, args)].out_interp)));
                case "easyEase":
                    return JsValue.native (name, (it, self, args) => {
                        if (args.length == 0) foreach (var k in p.keys) k.set_easy_ease ();
                        else p.keys[key_index (it, p, args)].set_easy_ease ();
                        p.touch ();
                        return JsValue.undefined ();
                    });
                case "setEaseAtKey":
                    return JsValue.native (name, (it, self, args) => {
                        var k = p.keys[key_index (it, p, args)];
                        k.in_interp = Interp.BEZIER;
                        k.out_interp = Interp.BEZIER;
                        k.ease_in_x = num (it, args, 1, k.ease_in_x);
                        k.ease_in_y = num (it, args, 2, k.ease_in_y);
                        k.ease_out_x = num (it, args, 3, k.ease_out_x);
                        k.ease_out_y = num (it, args, 4, k.ease_out_y);
                        p.touch ();
                        return JsValue.undefined ();
                    });
                case "setRovingAtKey":
                    return JsValue.native (name, (it, self, args) => {
                        p.keys[key_index (it, p, args)].roving = args.length > 1 && it.truthy (args[1]);
                        p.touch ();
                        return JsValue.undefined ();
                    });
                case "removeAllKeys":
                    return JsValue.native (name, (it, self, args) => {
                        p.clear_keys ();
                        return JsValue.undefined ();
                    });
            }
            return null;
        }

        public bool prop_set (Property p, string name, JsValue v) throws ExprError {
            var it = Expressions.interpreter ();
            switch (name) {
                case "expression":
                    p.expression = it.to_string (v);
                    p.expression_error = "";
                    p.touch ();
                    return true;
                case "expressionEnabled":
                    p.expression_enabled = it.truthy (v);
                    p.touch ();
                    return true;
                case "value":
                    if (p.keys.size > 0) throw new ExprError.RUNTIME ("The property has keyframes; use setValueAtTime");
                    store_value (it, p, 0, false, v);
                    return true;
            }
            return false;
        }

        private string attr_key (PropGroup g, string name) {
            if (g.attrs.has_key (name)) return name;
            var k = ExprHost.kebab (name);
            if (g.attrs.has_key (k)) return k;
            return "";
        }

        private PropGroup? add_child (PropGroup g, string type_in) {
            string type = type_in;
            if (g.type == "effects") {
                var id = type.has_prefix ("effect.") ? type.substring (7) : type;
                var l = g.owner_layer ();
                if (l == null) return null;
                return EffectRegistry.add_to_layer (l, id);
            }
            PropGroup target = g;
            if (g.type == "shape.group") target = g.group ("contents") ?? g;
            if (target.type == "contents" || target.type == "shape.contents") {
                if (!type.has_prefix ("shape.")) type = "shape." + type;
                var item = Factory.shape_item (type);
                if (item == null) return null;
                item.key = target.unique_key (item.key);
                target.add<PropGroup> (item);
                target.touch ();
                return item;
            }
            if (g.type == "masks") {
                var l = g.owner_layer ();
                double w = l != null ? l.solid_width : 100, h = l != null ? l.solid_height : 100;
                var m = Factory.mask (BezPath.rect (0, 0, w, h));
                m.key = g.unique_key ("mask");
                int n = g.children.size + 1;
                m.name = "%s %d".printf (_("Mask"), n);
                g.add<PropGroup> (m);
                g.touch ();
                return m;
            }
            if (g.type == "text" || g.type == "text.animators") {
                var animators = g.type == "text" ? g.group ("animators") : g;
                if (animators == null) return null;
                var an = Factory.text_animator ("%s %d".printf (_("Animator"), animators.children.size + 1));
                an.key = animators.unique_key ("animator");
                animators.add<PropGroup> (an);
                animators.touch ();
                return an;
            }
            if (g.type == "text.animator" || g.type == "text.selectors" || g.type == "text.properties") {
                var an = g.type == "text.animator" ? g : g.parent;
                if (an == null) return null;
                if (type.has_prefix ("text.selector") || type == "range" || type == "wiggly" || type == "expression") {
                    var sels = an.group ("selectors");
                    PropGroup sel;
                    if (type.contains ("wiggly")) sel = Factory.wiggly_selector ();
                    else if (type.contains ("expression")) sel = Factory.expression_selector ();
                    else sel = Factory.range_selector ();
                    sel.key = sels.unique_key (sel.key);
                    sels.add<PropGroup> (sel);
                    sels.touch ();
                    return sel;
                }
                var props = an.group ("properties");
                var pr = Factory.animator_property (type);
                if (pr == null || props == null) return null;
                if (props.prop (type) == null) props.add<Property> (pr);
                props.touch ();
                return props;
            }
            return null;
        }

        public JsValue? group_member (PropGroup g, string name, ExprContext c) {
            switch (name) {
                case "addProperty":
                    return JsValue.native (name, (it, self, args) => {
                        var type = str (it, args, 0, "");
                        var ch = add_child (g, type);
                        if (ch == null) throw new ExprError.RUNTIME ("Cannot add %s here", type);
                        if (ch.type == "text.properties") {
                            var pr = ch.prop (type);
                            return pr != null ? ExprHost.prop_object (pr, c) : ExprHost.group_object (ch, c);
                        }
                        return ExprHost.group_object (ch, c);
                    });
                case "canAddProperty":
                    return JsValue.native (name, (it, self, args) => {
                        var type = str (it, args, 0, "");
                        if (g.type == "effects") return JsValue.boolean (EffectRegistry.get (type.has_prefix ("effect.") ? type.substring (7) : type) != null);
                        if (g.type == "contents" || g.type == "shape.contents" || g.type == "shape.group") return JsValue.boolean (Factory.shape_item (type.has_prefix ("shape.") ? type : "shape." + type) != null);
                        return JsValue.boolean (g.type == "masks" || g.type.has_prefix ("text"));
                    });
                case "remove":
                    return JsValue.native (name, (it, self, args) => {
                        var parent = g.parent;
                        if (parent != null) {
                            var l = g.owner_layer ();
                            parent.remove (g);
                            if (l != null) l.mark_changed ();
                        }
                        return JsValue.undefined ();
                    });
                case "moveTo":
                    return JsValue.native (name, (it, self, args) => {
                        var parent = g.parent;
                        if (parent != null) {
                            parent.remove (g);
                            parent.insert ((int) num (it, args, 0, 1) - 1, g);
                            parent.touch ();
                        }
                        return JsValue.undefined ();
                    });
            }
            var ak = attr_key (g, name);
            if (ak != "") {
                var v = g.attrs[ak];
                if (v == "true" || v == "false") return JsValue.boolean (v == "true");
                return JsValue.string_value (v);
            }
            return null;
        }

        public bool group_set (PropGroup g, string name, JsValue v) throws ExprError {
            var it = Expressions.interpreter ();
            if (name == "name") {
                g.name = it.to_string (v);
                g.touch ();
                return true;
            }
            if (name == "enabled") {
                g.enabled = it.truthy (v);
                g.touch ();
                return true;
            }
            var ak = attr_key (g, name);
            if (ak != "") {
                var pv = it.prim (v);
                g.set_attr (ak, pv.kind == JsKind.BOOL ? (pv.b ? "true" : "false") : it.to_string (pv));
                return true;
            }
            return false;
        }

        public JsValue? layer_member (Layer l, string name, ExprContext c) {
            switch (name) {
                case "remove":
                    return JsValue.native (name, (it, self, args) => {
                        if (l.comp != null) l.comp.remove_layer (l);
                        return JsValue.undefined ();
                    });
                case "duplicate":
                    return JsValue.native (name, (it, self, args) => {
                        var d = l.duplicate ();
                        if (l.comp != null) {
                            d.name = l.comp.unique_layer_name (l.name);
                            l.comp.add_layer (d, l.comp.layers.index_of (l));
                        }
                        return ExprHost.layer_object (d, c);
                    });
                case "moveToBeginning":
                case "moveToEnd":
                    bool begin = name == "moveToBeginning";
                    return JsValue.native (name, (it, self, args) => {
                        if (l.comp != null) l.comp.move_layer (l, begin ? 0 : l.comp.layers.size - 1);
                        return JsValue.undefined ();
                    });
                case "moveBefore":
                case "moveAfter":
                    bool before = name == "moveBefore";
                    return JsValue.native (name, (it, self, args) => {
                        var other = args.length > 0 && args[0].kind == JsKind.OBJECT ? args[0].obj.host as Layer : null;
                        if (other == null || l.comp == null) throw new ExprError.RUNTIME ("Expected a layer");
                        l.comp.layers.remove (l);
                        int i = l.comp.layers.index_of (other);
                        l.comp.layers.insert (before ? i : i + 1, l);
                        l.mark_changed ();
                        return JsValue.undefined ();
                    });
                case "setParentWithJump":
                    return JsValue.native (name, (it, self, args) => {
                        var other = args.length > 0 && args[0].kind == JsKind.OBJECT ? args[0].obj.host as Layer : null;
                        set_parent (l, other);
                        return JsValue.undefined ();
                    });
                case "property":
                    return JsValue.native (name, (it, self, args) => {
                        var key = str (it, args, 0, "");
                        if (key == "Effects" || key == "effects") return ExprHost.group_object (l.effects, c);
                        if (key == "Masks" || key == "masks") return ExprHost.group_object (l.masks, c);
                        if (key == "Contents" || key == "contents") return ExprHost.group_object (l.contents, c);
                        var n = l.root.find (key) ?? ExprHost.resolve_child (l.root, key);
                        if (n == null) throw new ExprError.RUNTIME ("Property %s does not exist", key);
                        return ExprHost.node_object (n, c);
                    });
                case "effects":
                case "Effects":
                    return l.effects != null ? ExprHost.group_object (l.effects, c) : null;
                case "masks":
                case "Masks":
                    return l.masks != null ? ExprHost.group_object (l.masks, c) : null;
                case "addEffect":
                    return JsValue.native (name, (it, self, args) => {
                        var id = str (it, args, 0, "");
                        var fx = EffectRegistry.add_to_layer (l, id.has_prefix ("effect.") ? id.substring (7) : id);
                        if (fx == null) throw new ExprError.RUNTIME ("Unknown effect %s", id);
                        return ExprHost.group_object (fx, c);
                    });
                case "addMask":
                    return JsValue.native (name, (it, self, args) => {
                        var m = add_child (l.masks, "mask");
                        if (args.length > 0) {
                            var path = ExprHost.to_path (it.prim (args[0]));
                            if (path != null) m.prop ("path").path = path;
                        }
                        if (args.length > 1) m.attrs["mode"] = str (it, args, 1, "add");
                        return ExprHost.group_object (m, c);
                    });
                case "motionBlur": return JsValue.boolean (l.motion_blur);
                case "adjustmentLayer": return JsValue.boolean (l.adjustment);
                case "solo": return JsValue.boolean (l.solo);
                case "shy": return JsValue.boolean (l.shy);
                case "locked": return JsValue.boolean (l.locked);
                case "guideLayer": return JsValue.boolean (l.guide);
                case "blendingMode": return JsValue.string_value (l.blend.key ());
                case "trackMatteType": return JsValue.string_value (l.matte_mode.to_id ());
                case "autoOrient": return JsValue.string_value (l.auto_orient.to_id ());
                case "timeRemapEnabled": return JsValue.boolean (l.time_remap);
                case "lightType": return JsValue.number (4412 + (int) l.light_type ());
                case "kind": return JsValue.string_value (l.kind.to_id ());
            }
            return null;
        }

        private void set_parent (Layer l, Layer? parent) throws ExprError {
            if (l.comp == null) return;
            if (parent != null && l.comp.would_cycle (l, parent)) throw new ExprError.RUNTIME ("Parenting would create a cycle");
            l.parent_id = parent != null ? parent.id : "";
            l.mark_changed ();
        }

        public bool layer_set (Layer l, string name, JsValue v) throws ExprError {
            var it = Expressions.interpreter ();
            switch (name) {
                case "name": l.name = it.to_string (v); break;
                case "startTime": l.start_time = it.to_number (it.prim (v)); break;
                case "inPoint": l.in_point = it.to_number (it.prim (v)); break;
                case "outPoint": l.out_point = it.to_number (it.prim (v)); break;
                case "stretch": l.stretch = it.to_number (it.prim (v)) / 100.0; break;
                case "enabled": l.video = it.truthy (v); break;
                case "threeDLayer": l.three_d = it.truthy (v); break;
                case "motionBlur": l.motion_blur = it.truthy (v); break;
                case "adjustmentLayer": l.adjustment = it.truthy (v); break;
                case "solo": l.solo = it.truthy (v); break;
                case "shy": l.shy = it.truthy (v); break;
                case "locked": l.locked = it.truthy (v); break;
                case "guideLayer": l.guide = it.truthy (v); break;
                case "label": l.label = (int) it.to_number (it.prim (v)); break;
                case "comment": l.comment = it.to_string (v); break;
                case "blendingMode": l.blend = Singularity.Imaging.BlendMode.from_key (it.to_string (v)); break;
                case "trackMatteType": l.matte_mode = MatteMode.from_id (it.to_string (v)); break;
                case "autoOrient": l.auto_orient = AutoOrient.from_id (it.to_string (v)); break;
                case "timeRemapEnabled": l.time_remap = it.truthy (v); break;
                case "trackMatteLayer":
                    var ml = v.kind == JsKind.OBJECT ? v.obj.host as Layer : null;
                    l.matte_id = ml != null ? ml.id : "";
                    if (ml != null && l.matte_mode == MatteMode.NONE) l.matte_mode = MatteMode.ALPHA;
                    break;
                case "lightType":
                    var lg = l.root.group ("light");
                    if (lg != null) lg.attrs["type"] = (((int) it.to_number (it.prim (v)) - 4412).clamp (0, 3)).to_string ();
                    break;
                case "parent":
                    set_parent (l, v.kind == JsKind.OBJECT ? v.obj.host as Layer : null);
                    return true;
                default:
                    return false;
            }
            l.mark_changed ();
            return true;
        }

        private double[] color_arg (Interpreter it, JsValue[] args, int i) throws ExprError {
            if (i >= args.length) return { 0.5, 0.5, 0.5, 1 };
            var d = doubles (it, args[i]);
            return { d[0], d.length > 1 ? d[1] : 0, d.length > 2 ? d[2] : 0, d.length > 3 ? d[3] : 1 };
        }

        public JsValue layers_object (Composition comp, ExprContext c) {
            var o = new JsObject ();
            o.class_name = "LayerCollection";
            o.getter = (name) => {
                switch (name) {
                    case "length":
                    case "numLayers": return JsValue.number (comp.layers.size);
                    case "byName":
                        return JsValue.native (name, (it, self, args) => {
                            var l = comp.layer_by_name (str (it, args, 0, ""));
                            return l != null ? ExprHost.layer_object (l, c) : JsValue.null_value ();
                        });
                    case "addSolid":
                        return JsValue.native (name, (it, self, args) => {
                            var col = color_arg (it, args, 0);
                            var l = Factory.solid (comp, str (it, args, 1, _("Solid")), col, (int) num (it, args, 2, comp.width), (int) num (it, args, 3, comp.height));
                            if (args.length > 5) l.out_point = num (it, args, 5, comp.duration);
                            comp.add_layer (l, 0);
                            return ExprHost.layer_object (l, c);
                        });
                    case "addNull":
                        return JsValue.native (name, (it, self, args) => {
                            var l = Factory.null_layer (comp);
                            if (args.length > 0) l.out_point = num (it, args, 0, comp.duration);
                            comp.add_layer (l, 0);
                            return ExprHost.layer_object (l, c);
                        });
                    case "addShape":
                        return JsValue.native (name, (it, self, args) => {
                            var l = Factory.shape_layer (comp);
                            comp.add_layer (l, 0);
                            return ExprHost.layer_object (l, c);
                        });
                    case "addText":
                    case "addBoxText":
                        bool box = name == "addBoxText";
                        return JsValue.native (name, (it, self, args) => {
                            string text = box ? str (it, args, 1, "") : str (it, args, 0, "");
                            var l = Factory.text_layer (comp, text);
                            if (box && args.length > 0) {
                                var size = doubles (it, args[0]);
                                var doc = l.text_group.prop ("source-text").text;
                                doc.box_width = size[0];
                                doc.box_height = size.length > 1 ? size[1] : 0;
                            }
                            comp.add_layer (l, 0);
                            return ExprHost.layer_object (l, c);
                        });
                    case "addCamera":
                        return JsValue.native (name, (it, self, args) => {
                            var l = Factory.camera (comp);
                            if (args.length > 0) l.name = str (it, args, 0, l.name);
                            if (args.length > 1) {
                                var ctr = doubles (it, args[1]);
                                var poi = l.transform.prop ("point-of-interest");
                                var pos = l.transform.prop ("position");
                                double z = pos.value[2];
                                poi.value = { ctr[0], ctr[1], 0 };
                                pos.value = { ctr[0], ctr[1], z };
                            }
                            comp.add_layer (l, 0);
                            return ExprHost.layer_object (l, c);
                        });
                    case "addLight":
                        return JsValue.native (name, (it, self, args) => {
                            var l = Factory.light (comp, LightType.POINT);
                            if (args.length > 0) l.name = str (it, args, 0, l.name);
                            if (args.length > 1) {
                                var ctr = doubles (it, args[1]);
                                l.transform.prop ("point-of-interest").value = { ctr[0], ctr[1], 0 };
                            }
                            comp.add_layer (l, 0);
                            return ExprHost.layer_object (l, c);
                        });
                    case "add":
                        return JsValue.native (name, (it, self, args) => {
                            if (args.length == 0 || args[0].kind != JsKind.OBJECT) throw new ExprError.RUNTIME ("Expected a project item");
                            var host = args[0].obj.host;
                            Layer l;
                            if (host is Composition) {
                                var nested = (Composition) host;
                                if (comp.project != null && comp.project.precomp_cycle (comp, nested)) throw new ExprError.RUNTIME ("This would nest a composition inside itself");
                                l = Factory.precomp_layer (comp, nested);
                            } else if (host is Footage) {
                                l = Factory.footage_layer (comp, (Footage) host);
                            } else {
                                throw new ExprError.RUNTIME ("Expected a composition or footage item");
                            }
                            comp.add_layer (l, 0);
                            return ExprHost.layer_object (l, c);
                        });
                }
                int idx = int.parse (name);
                if (idx.to_string () == name && idx >= 1 && idx <= comp.layers.size) return ExprHost.layer_object (comp.layers[idx - 1], c);
                return null;
            };
            return JsValue.object (o);
        }

        public JsValue? comp_member (Composition comp, string name, ExprContext c) {
            switch (name) {
                case "layers": return layers_object (comp, c);
                case "workAreaStart": return JsValue.number (comp.work_start);
                case "workAreaDuration": return JsValue.number (comp.work_area_end () - comp.work_start);
                case "motionBlur": return JsValue.boolean (comp.motion_blur_enabled);
                case "id": return JsValue.string_value (comp.id);
                case "typeName": return JsValue.string_value ("Composition");
                case "addMarker":
                    return JsValue.native (name, (it, self, args) => {
                        comp.markers.add (new Marker (num (it, args, 0, 0), str (it, args, 1, ""), num (it, args, 2, 0)));
                        return JsValue.number (comp.markers.size);
                    });
                case "remove":
                    return JsValue.native (name, (it, self, args) => {
                        if (comp.project != null) comp.project.remove_item (comp);
                        return JsValue.undefined ();
                    });
                case "duplicate":
                    return JsValue.native (name, (it, self, args) => {
                        if (comp.project == null) throw new ExprError.RUNTIME ("No project");
                        var dup = new Composition (comp.name + " 2", comp.width, comp.height, comp.fps, comp.duration);
                        dup.background = comp.background;
                        foreach (var l in comp.layers) {
                            var d = l.duplicate ();
                            d.comp = dup;
                            d.id = l.id;
                            dup.layers.add (d);
                        }
                        comp.project.add_item (dup);
                        return ExprHost.comp_object (dup, c);
                    });
            }
            return null;
        }

        public bool comp_set (Composition comp, string name, JsValue v) throws ExprError {
            var it = Expressions.interpreter ();
            switch (name) {
                case "name": comp.name = it.to_string (v); break;
                case "width": comp.width = (int) it.to_number (it.prim (v)); break;
                case "height": comp.height = (int) it.to_number (it.prim (v)); break;
                case "duration": comp.duration = it.to_number (it.prim (v)); break;
                case "frameRate": comp.fps = it.to_number (it.prim (v)); break;
                case "frameDuration": comp.fps = 1.0 / it.to_number (it.prim (v)); break;
                case "pixelAspect": comp.pixel_aspect = it.to_number (it.prim (v)); break;
                case "bgColor":
                    var d = doubles (it, v);
                    comp.background = { d[0], d.length > 1 ? d[1] : 0, d.length > 2 ? d[2] : 0, 1 };
                    break;
                case "workAreaStart": comp.work_start = it.to_number (it.prim (v)); break;
                case "workAreaDuration": comp.work_end = comp.work_start + it.to_number (it.prim (v)); break;
                case "shutterAngle": comp.shutter_angle = it.to_number (it.prim (v)); break;
                case "shutterPhase": comp.shutter_phase = it.to_number (it.prim (v)); break;
                case "motionBlur": comp.motion_blur_enabled = it.truthy (v); break;
                case "parentFolder":
                    var f = v.kind == JsKind.OBJECT ? v.obj.host as Folder : null;
                    comp.folder_id = f != null ? f.id : "";
                    break;
                default:
                    return false;
            }
            comp.layer_changed (null);
            return true;
        }

        public JsValue item_object (Item item, ExprContext c) {
            var comp = item as Composition;
            if (comp != null) return ExprHost.comp_object (comp, c);
            var o = new JsObject ();
            o.host = item;
            o.class_name = item.kind_id ();
            o.getter = (name) => {
                switch (name) {
                    case "name": return JsValue.string_value (item.name);
                    case "id": return JsValue.string_value (item.id);
                    case "typeName": return JsValue.string_value ((item is Folder) ? "Folder" : "Footage");
                    case "comment": return JsValue.string_value (item.comment);
                }
                var f = item as Footage;
                if (f != null) {
                    switch (name) {
                        case "width": return JsValue.number (f.width);
                        case "height": return JsValue.number (f.height);
                        case "duration": return JsValue.number (f.duration);
                        case "frameRate": return JsValue.number (f.frame_rate ());
                        case "file": return JsValue.string_value (f.path);
                        case "hasAudio": return JsValue.boolean (f.has_audio);
                        case "hasVideo": return JsValue.boolean (f.has_video);
                    }
                }
                var folder = item as Folder;
                if (folder != null && c.project != null) {
                    if (name == "numItems") return JsValue.number (c.project.children_of (folder.id).size);
                    if (name == "item") return JsValue.native (name, (it, self, args) => {
                        var kids = c.project.children_of (folder.id);
                        int i = (int) num (it, args, 0, 1) - 1;
                        if (i < 0 || i >= kids.size) throw new ExprError.RUNTIME ("Item index out of range");
                        return item_object (kids[i], c);
                    });
                }
                if (name == "remove") return JsValue.native (name, (it, self, args) => {
                    if (c.project != null) c.project.remove_item (item);
                    return JsValue.undefined ();
                });
                return null;
            };
            o.setter = (name, v) => {
                var it = Expressions.interpreter ();
                if (name == "name") {
                    item.name = it.to_string (v);
                    return true;
                }
                if (name == "comment") {
                    item.comment = it.to_string (v);
                    return true;
                }
                if (name == "parentFolder") {
                    var f = v.kind == JsKind.OBJECT ? v.obj.host as Folder : null;
                    item.folder_id = f != null ? f.id : "";
                    return true;
                }
                return false;
            };
            return JsValue.object (o);
        }

        public JsValue output_module_object (OutputModule om) {
            var o = new JsObject ();
            o.class_name = "OutputModule";
            o.getter = (name) => {
                switch (name) {
                    case "format": return JsValue.string_value (om.format);
                    case "file":
                    case "path": return JsValue.string_value (om.path);
                    case "alpha": return JsValue.boolean (om.alpha);
                    case "bitDepth": return JsValue.number (om.bit_depth);
                    case "quality": return JsValue.number (om.quality);
                    case "includeAudio": return JsValue.boolean (om.include_audio);
                    case "width": return JsValue.number (om.width);
                    case "height": return JsValue.number (om.height);
                }
                return null;
            };
            o.setter = (name, v) => {
                var it = Expressions.interpreter ();
                switch (name) {
                    case "format": om.format = it.to_string (v); return true;
                    case "file":
                    case "path": om.path = it.to_string (v); return true;
                    case "alpha": om.alpha = it.truthy (v); return true;
                    case "bitDepth": om.bit_depth = (int) it.to_number (it.prim (v)); return true;
                    case "quality": om.quality = (int) it.to_number (it.prim (v)); return true;
                    case "includeAudio": om.include_audio = it.truthy (v); return true;
                    case "width": om.width = (int) it.to_number (it.prim (v)); return true;
                    case "height": om.height = (int) it.to_number (it.prim (v)); return true;
                }
                return false;
            };
            return JsValue.object (o);
        }

        public JsValue render_item_object (Project project, RenderItem ri, ExprContext c) {
            var o = new JsObject ();
            o.class_name = "RenderQueueItem";
            o.getter = (name) => {
                switch (name) {
                    case "comp":
                        var comp = project.comp_by_id (ri.comp_id);
                        return comp != null ? ExprHost.comp_object (comp, c) : JsValue.null_value ();
                    case "status": return JsValue.string_value (ri.status.to_id ());
                    case "numOutputModules": return JsValue.number (ri.outputs.size);
                    case "timeSpanStart": return JsValue.number (ri.start);
                    case "timeSpanDuration":
                        var comp = project.comp_by_id (ri.comp_id);
                        double end = ri.end >= 0 ? ri.end : (comp != null ? comp.duration : 0);
                        return JsValue.number (end - ri.start);
                    case "outputModule":
                        return JsValue.native (name, (it, self, args) => {
                            int i = (int) num (it, args, 0, 1) - 1;
                            if (i < 0 || i >= ri.outputs.size) throw new ExprError.RUNTIME ("Output module index out of range");
                            return output_module_object (ri.outputs[i]);
                        });
                    case "addOutputModule":
                        return JsValue.native (name, (it, self, args) => {
                            var om = new OutputModule ();
                            if (args.length > 0) om.format = str (it, args, 0, om.format);
                            if (args.length > 1) om.path = str (it, args, 1, "");
                            ri.outputs.add (om);
                            return output_module_object (om);
                        });
                    case "remove":
                        return JsValue.native (name, (it, self, args) => {
                            project.render_queue.remove (ri);
                            return JsValue.undefined ();
                        });
                }
                return null;
            };
            o.setter = (name, v) => {
                var it = Expressions.interpreter ();
                switch (name) {
                    case "timeSpanStart": ri.start = it.to_number (it.prim (v)); return true;
                    case "timeSpanDuration": ri.end = ri.start + it.to_number (it.prim (v)); return true;
                    case "resolution": ri.resolution = int.max (1, (int) it.to_number (it.prim (v))); return true;
                    case "motionBlur": ri.motion_blur = it.truthy (v); return true;
                }
                return false;
            };
            return JsValue.object (o);
        }

        public JsValue render_queue_object (Project project, ExprContext c) {
            var o = new JsObject ();
            o.class_name = "RenderQueue";
            o.getter = (name) => {
                switch (name) {
                    case "numItems": return JsValue.number (project.render_queue.size);
                    case "item":
                        return JsValue.native (name, (it, self, args) => {
                            int i = (int) num (it, args, 0, 1) - 1;
                            if (i < 0 || i >= project.render_queue.size) throw new ExprError.RUNTIME ("Render queue index out of range");
                            return render_item_object (project, project.render_queue[i], c);
                        });
                    case "add":
                        return JsValue.native (name, (it, self, args) => {
                            var comp = args.length > 0 && args[0].kind == JsKind.OBJECT ? args[0].obj.host as Composition : null;
                            if (comp == null) throw new ExprError.RUNTIME ("renderQueue.add needs a composition");
                            var ri = new RenderItem (comp.id);
                            var om = new OutputModule ();
                            if (args.length > 1 && args[1].kind == JsKind.OBJECT) {
                                var opts = args[1].obj;
                                if (opts.own ("format") != null) om.format = it.to_string (opts.own ("format"));
                                if (opts.own ("path") != null) om.path = it.to_string (opts.own ("path"));
                                if (opts.own ("file") != null) om.path = it.to_string (opts.own ("file"));
                                if (opts.own ("alpha") != null) om.alpha = it.truthy (opts.own ("alpha"));
                                if (opts.own ("bitDepth") != null) om.bit_depth = (int) it.to_number (opts.own ("bitDepth"));
                                if (opts.own ("quality") != null) om.quality = (int) it.to_number (opts.own ("quality"));
                            }
                            ri.outputs.add (om);
                            project.render_queue.add (ri);
                            project.modified = true;
                            return render_item_object (project, ri, c);
                        });
                }
                return null;
            };
            return JsValue.object (o);
        }

        public JsValue app_object (Project project, ExprContext c) {
            var proj = new JsObject ();
            proj.class_name = "Project";
            proj.getter = (name) => {
                switch (name) {
                    case "numItems": return JsValue.number (project.items.size);
                    case "items":
                        var col = new JsObject ();
                        col.getter = (n) => {
                            if (n == "length") return JsValue.number (project.items.size);
                            int i = int.parse (n);
                            if (i.to_string () == n && i >= 1 && i <= project.items.size) return item_object (project.items[i - 1], c);
                            return null;
                        };
                        return JsValue.object (col);
                    case "item":
                        return JsValue.native (name, (it, self, args) => {
                            int i = (int) num (it, args, 0, 1) - 1;
                            if (i < 0 || i >= project.items.size) throw new ExprError.RUNTIME ("Item index out of range");
                            return item_object (project.items[i], c);
                        });
                    case "compositions":
                        return JsValue.native (name, (it, self, args) => {
                            var l = new Gee.ArrayList<JsValue> ();
                            foreach (var comp in project.compositions ()) l.add (ExprHost.comp_object (comp, c));
                            return JsValue.array (l);
                        });
                    case "activeItem":
                        var comps = project.compositions ();
                        return comps.size > 0 ? ExprHost.comp_object (comps[0], c) : JsValue.null_value ();
                    case "addComp":
                        return JsValue.native (name, (it, self, args) => {
                            var comp = new Composition (str (it, args, 0, _("Composition")), (int) num (it, args, 1, 1920), (int) num (it, args, 2, 1080),
                                                        num (it, args, 5, 30), num (it, args, 4, 10));
                            comp.pixel_aspect = num (it, args, 3, 1);
                            project.add_item (comp);
                            return ExprHost.comp_object (comp, c);
                        });
                    case "addFolder":
                        return JsValue.native (name, (it, self, args) => {
                            var f = new Folder (str (it, args, 0, _("Folder")));
                            project.add_item (f);
                            return item_object (f, c);
                        });
                    case "importFile":
                        return JsValue.native (name, (it, self, args) => {
                            var path = str (it, args, 0, "");
                            if (args.length > 0 && args[0].kind == JsKind.OBJECT && args[0].obj.own ("file") != null) path = it.to_string (args[0].obj.own ("file"));
                            Footage f;
                            try {
                                f = MediaPool.probe (project.resolve_path (path));
                            } catch (Error e) {
                                throw new ExprError.RUNTIME ("Cannot import %s: %s", path, e.message);
                            }
                            project.add_item (f);
                            return item_object (f, c);
                        });
                    case "renderQueue": return render_queue_object (project, c);
                    case "bitsPerChannel": return JsValue.number (project.bit_depth);
                    case "workingSpace": return JsValue.string_value (project.working_space);
                    case "linearBlending": return JsValue.boolean (project.linear_blending);
                    case "file": return JsValue.string_value (project.path);
                }
                return null;
            };
            proj.setter = (name, v) => {
                var it = Expressions.interpreter ();
                switch (name) {
                    case "bitsPerChannel":
                        int bd = (int) it.to_number (it.prim (v));
                        if (bd != 8 && bd != 16 && bd != 32) throw new ExprError.RUNTIME ("Bit depth must be 8, 16 or 32");
                        project.bit_depth = bd;
                        return true;
                    case "workingSpace": project.working_space = it.to_string (v); return true;
                    case "linearBlending": project.linear_blending = it.truthy (v); return true;
                }
                return false;
            };
            var app = new JsObject ();
            app.class_name = "Application";
            app.put ("project", JsValue.object (proj));
            app.put ("version", JsValue.string_value ("1.0"));
            return JsValue.object (app);
        }
    }
}
