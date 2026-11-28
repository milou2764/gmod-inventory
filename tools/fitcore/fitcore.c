/* The fitting tools' hot loops in C (dev tool, not in the .gma): tools/fitcore.py loads fitcore.dll with
 * ctypes and falls back to its numpy versions when it isn't built. Same arithmetic as the numpy code
 * (modelgear_pack.surface_below, zcut), in the same order, so the results are the same.
 *
 *   surface_below: the highest triangle of a mesh straight below each point, in a window around it, and
 *                  how flat it is there (rays cast down onto a body: a vest's straps, its panels).
 *   zcut:          the points where a mesh's triangles cross a horizontal plane (its outline there).
 *
 * Build: sh build.sh (MSYS2 UCRT64 gcc, as tools/fit_editor). */
#include <math.h>
#include <stdint.h>
#include <stdlib.h>

#define EXPORT __declspec(dllexport)

typedef struct {
    double ax, ay, az, e1x, e1y, e2x, e2y, dbz, dcz, den, level;
} Tri;

/* pts: np x 3; out_z: -inf where no triangle; out_flat: |normal z| / |normal| of the triangle hit (0 if none).
 * Returns 0, or -1 if out of memory. */
EXPORT int surface_below(const double *bp, int nv, const int64_t *bt, int nt, const double *pts, int np,
                         double below, double above, double *out_z, double *out_flat)
{
    (void)nv;
    if (np <= 0) return 0;
    double lox = pts[0], hix = pts[0], loy = pts[1], hiy = pts[1], loz = pts[2], hiz = pts[2];
    for (int i = 0; i < np; i++) {
        const double *p = pts + 3 * i;
        if (p[0] < lox) lox = p[0];
        if (p[0] > hix) hix = p[0];
        if (p[1] < loy) loy = p[1];
        if (p[1] > hiy) hiy = p[1];
        if (p[2] < loz) loz = p[2];
        if (p[2] > hiz) hiz = p[2];
        out_z[i] = -INFINITY;
        out_flat[i] = 0.0;
    }
    /* the triangles that may lie under a point (as the numpy version keeps them) */
    Tri *tri = malloc(sizeof(Tri) * (nt > 0 ? nt : 1));
    double *bb = malloc(sizeof(double) * 4 * (nt > 0 ? nt : 1));
    if (!tri || !bb) { free(tri); free(bb); return -1; }
    int n = 0;
    for (int t = 0; t < nt; t++) {
        const double *A = bp + 3 * bt[3 * t], *B = bp + 3 * bt[3 * t + 1], *C = bp + 3 * bt[3 * t + 2];
        double mnx = fmin(fmin(A[0], B[0]), C[0]), mxx = fmax(fmax(A[0], B[0]), C[0]);
        double mny = fmin(fmin(A[1], B[1]), C[1]), mxy = fmax(fmax(A[1], B[1]), C[1]);
        double mnz = fmin(fmin(A[2], B[2]), C[2]), mxz = fmax(fmax(A[2], B[2]), C[2]);
        if (mxx < lox || mnx > hix || mxy < loy || mny > hiy || mxz < loz - below || mnz > hiz + above) continue;
        double e1x = B[0] - A[0], e1y = B[1] - A[1], e2x = C[0] - A[0], e2y = C[1] - A[1];
        double den = e1x * e2y - e1y * e2x;
        if (!(fabs(den) > 1e-9)) continue;
        /* the normal (B - A) x (C - A), its vertical part relative to its length */
        double ux = B[0] - A[0], uy = B[1] - A[1], uz = B[2] - A[2];
        double vx = C[0] - A[0], vy = C[1] - A[1], vz = C[2] - A[2];
        double nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
        Tri *r = tri + n;
        r->ax = A[0]; r->ay = A[1]; r->az = A[2];
        r->e1x = e1x; r->e1y = e1y; r->e2x = e2x; r->e2y = e2y;
        r->dbz = B[2] - A[2]; r->dcz = C[2] - A[2]; r->den = den;
        r->level = fabs(nz) / (sqrt(nx * nx + ny * ny + nz * nz) + 1e-12);
        bb[4 * n] = mnx; bb[4 * n + 1] = mxx; bb[4 * n + 2] = mny; bb[4 * n + 3] = mxy;
        n++;
    }
    if (n == 0) { free(tri); free(bb); return 0; }
    /* a grid over the points: each cell lists the triangles over it */
    int gx = (int)ceil((hix - lox) / 1.0) + 1, gy = (int)ceil((hiy - loy) / 1.0) + 1;
    if (gx > 512) gx = 512;
    if (gy > 512) gy = 512;
    double cx = (hix - lox) / gx + 1e-9, cy = (hiy - loy) / gy + 1e-9;
    int *count = calloc((size_t)gx * gy + 1, sizeof(int));
    if (!count) { free(tri); free(bb); return -1; }
    int *start = NULL, *list = NULL;
    for (int pass = 0; pass < 2; pass++) {
        if (pass == 1) {
            start = malloc(sizeof(int) * ((size_t)gx * gy + 1));
            if (!start) { free(tri); free(bb); free(count); return -1; }
            int s = 0;
            for (int c = 0; c < gx * gy; c++) { start[c] = s; s += count[c]; count[c] = 0; }
            start[gx * gy] = s;
            list = malloc(sizeof(int) * (s > 0 ? s : 1));
            if (!list) { free(tri); free(bb); free(count); free(start); return -1; }
        }
        for (int t = 0; t < n; t++) {
            int x0 = (int)floor((bb[4 * t] - lox) / cx), x1 = (int)floor((bb[4 * t + 1] - lox) / cx);
            int y0 = (int)floor((bb[4 * t + 2] - loy) / cy), y1 = (int)floor((bb[4 * t + 3] - loy) / cy);
            if (x0 < 0) x0 = 0;
            if (y0 < 0) y0 = 0;
            if (x1 >= gx) x1 = gx - 1;
            if (y1 >= gy) y1 = gy - 1;
            for (int x = x0; x <= x1; x++)
                for (int y = y0; y <= y1; y++) {
                    int c = x * gy + y;
                    if (pass == 1) list[start[c] + count[c]] = t;
                    count[c]++;
                }
        }
        if (pass == 1) {
            for (int i = 0; i < np; i++) {
                const double *p = pts + 3 * i;
                int x = (int)floor((p[0] - lox) / cx), y = (int)floor((p[1] - loy) / cy);
                if (x < 0) x = 0;
                if (y < 0) y = 0;
                if (x >= gx) x = gx - 1;
                if (y >= gy) y = gy - 1;
                int c = x * gy + y;
                double best = -INFINITY, flat = 0.0;
                int found = 0;
                for (int k = start[c]; k < start[c + 1]; k++) {
                    const Tri *r = tri + list[k];
                    double dx = p[0] - r->ax, dy = p[1] - r->ay;
                    double u = (dx * r->e2y - dy * r->e2x) / r->den;
                    double v = (r->e1x * dy - r->e1y * dx) / r->den;
                    if (!(u >= 0 && v >= 0 && u + v <= 1)) continue;
                    double z = r->az + u * r->dbz + v * r->dcz;
                    if (!(z <= p[2] + above && z >= p[2] - below)) continue;
                    /* (the numpy version takes the first of equal highest: the lowest triangle index) */
                    if (!found || z > best || (z == best && list[k] < found - 1)) {
                        best = z;
                        flat = r->level;
                        found = list[k] + 1;
                    }
                }
                out_z[i] = best;
                out_flat[i] = found ? flat : 0.0;
            }
            free(start);
            free(list);
        }
    }
    free(count);
    free(tri);
    free(bb);
    return 0;
}

/* The points where triangles cross the plane at height z, in the order the numpy version gives them
 * (all crossings of edge AB, then BC, then CA). out: room for 2 * nt points (x, y, z). Returns how many. */
EXPORT int zcut(const double *p, const int64_t *t, int nt, double z, double *out)
{
    int n = 0;
    for (int edge = 0; edge < 3; edge++) {
        for (int k = 0; k < nt; k++) {
            const double *a = p + 3 * t[3 * k + edge], *b = p + 3 * t[3 * k + (edge + 1) % 3];
            double da = a[2] - z, db = b[2] - z;
            if ((da < 0) == (db < 0)) continue;
            double s = da / (da - db);
            out[3 * n] = a[0] + s * (b[0] - a[0]);
            out[3 * n + 1] = a[1] + s * (b[1] - a[1]);
            out[3 * n + 2] = a[2] + s * (b[2] - a[2]);
            n++;
        }
    }
    return n;
}
