using Gtk;

namespace Singularity.Apps.Keyframe {

    public class FixedWidth : Widget {
        private Widget child;
        private int target_width;

        public FixedWidth (Widget child, int target_width) {
            this.child = child;
            this.target_width = target_width;
            child.set_parent (this);
            hexpand = false;
            overflow = Overflow.HIDDEN;
        }

        public override void dispose () {
            if (child != null) child.unparent ();
            child = null;
            base.dispose ();
        }

        public override SizeRequestMode get_request_mode () {
            return SizeRequestMode.HEIGHT_FOR_WIDTH;
        }

        public override void measure (Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            minimum_baseline = natural_baseline = -1;
            if (orientation == Orientation.HORIZONTAL) {
                minimum = natural = target_width;
                return;
            }
            child.measure (orientation, target_width, out minimum, out natural, null, null);
        }

        public override void size_allocate (int width, int height, int baseline) {
            child.allocate (width, height, baseline, null);
        }
    }
}
