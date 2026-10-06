namespace Singularity.Apps.Keyframe {

    namespace EffectsControls {
        public void register () {
            EffectRegistry.add (control ("slider-control", _("Slider Control"), (g) => g.add<Property> (Factory.scalar ("slider", _("Slider"), 0).ui_range (0, 100))));
            EffectRegistry.add (control ("checkbox-control", _("Checkbox Control"), (g) => g.add<Property> (Factory.toggle ("checkbox", _("Checkbox"), false))));
            EffectRegistry.add (control ("color-control", _("Color Control"), (g) => g.add<Property> (Factory.color ("color", _("Color"), { 1, 0, 0, 1 }))));
            EffectRegistry.add (control ("point-control", _("Point Control"), (g) => g.add<Property> (Factory.point ("point", _("Point"), { 0, 0 }))));
            EffectRegistry.add (control ("point3d-control", _("3D Point Control"), (g) => g.add<Property> (Factory.point ("point", _("3D Point"), { 0, 0, 0 }))));
            EffectRegistry.add (control ("angle-control", _("Angle Control"), (g) => g.add<Property> (Factory.angle ("angle", _("Angle"), 0))));
            EffectRegistry.add (control ("layer-control", _("Layer Control"), (g) => g.add<Property> (Factory.layer_ref ("layer", _("Layer")))));
            EffectRegistry.add (control ("dropdown-control", _("Dropdown Menu Control"), (g) => {
                g.add<Property> (Factory.choice ("menu", _("Menu"), { _("Item 1"), _("Item 2"), _("Item 3") }));
            }));
        }

        private EffectDef control (string id, string label, owned EffectBuild build) {
            var d = new EffectDef (id, label, _("Expression Controls"), (owned) build, null);
            d.control = true;
            return d;
        }
    }
}
