#include <stdlib.h>
#include <glib.h>
#include "cairo_path.h"

double *
keyframe_cairo_path (cairo_t *context, int *length)
{
  cairo_path_t *path = cairo_copy_path (context);
  GArray *out = g_array_new (FALSE, FALSE, sizeof (double));

  for (int i = 0; i < path->num_data; i += path->data[i].header.length) {
    cairo_path_data_t *d = &path->data[i];
    double kind = d->header.type;
    int points = d->header.type == CAIRO_PATH_CURVE_TO ? 3 : (d->header.type == CAIRO_PATH_CLOSE_PATH ? 0 : 1);
    g_array_append_val (out, kind);
    for (int k = 1; k <= 3; k++) {
      double x = k <= points ? path->data[i + k].point.x : 0;
      double y = k <= points ? path->data[i + k].point.y : 0;
      g_array_append_val (out, x);
      g_array_append_val (out, y);
    }
  }
  cairo_path_destroy (path);
  *length = out->len;
  return (double *) g_array_free (out, FALSE);
}
