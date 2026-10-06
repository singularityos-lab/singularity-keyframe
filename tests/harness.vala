namespace Singularity.Apps.Keyframe.Test {
    public int failures = 0;

    public void check (bool cond, string what) {
        if (!cond) {
            stderr.printf ("FAIL: %s\n", what);
            failures++;
        }
    }

    public bool near (double a, double b, double eps = 1e-3) {
        return (a - b).abs () <= eps;
    }

    public string fixtures () {
        return Environment.get_variable ("KEYFRAME_FIXTURES") ?? "tests/data";
    }

    public string tmp_dir () {
        try {
            return DirUtils.make_tmp ("keyframe-test-XXXXXX");
        } catch (Error e) {
            return Environment.get_tmp_dir ();
        }
    }

    public string out_dir () {
        var d = Environment.get_variable ("KEYFRAME_TEST_OUT");
        return d != null && d != "" ? d : tmp_dir ();
    }

    public int finish (string name) {
        if (failures > 0) {
            stderr.printf ("%s: %d failure(s)\n", name, failures);
            return 1;
        }
        print ("%s: ok\n", name);
        return 0;
    }
}
