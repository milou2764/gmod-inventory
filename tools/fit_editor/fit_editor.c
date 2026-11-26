/*
 * Fit editor of the Advanced Inventory System (dev tool, not in the .gma).
 *
 * Goes through every worn item on every playermodel, one pair at a time, drawn with OpenGL the way
 * the game places it. You adjust the size, the position and the tilt, then approve: the pair is
 * final. It is added to tools/fit_locks.txt, written into the game's fit files at once (python
 * fit_locks.py apply), the editor doesn't ask for it again, and fit_items.py / fit_compat.py keep it
 * when they run again.
 *
 * The data comes from tools/fit_editor_export.py (meshes, textures, bones, current fits, pairs).
 * Start it with fit_editor.bat (export, then this program).
 *
 *   fit_editor.exe --cache DIR --tools DIR --python PYTHON.EXE [--cell PIXELS] [--goto ITEM PLAYERMODEL]
 *                  [--shot OUT.bmp] [--selftest OUT.txt] [--autotest OUT.txt]
 *   --shot: picture of the window; --selftest: fit maths; --autotest: +4% and approve the shown pair
 *   (run it with --tools on a copy of tools/ and lua/advinv/, never on the real files)
 *
 * Build (MSYS2 UCRT64 gcc): see build.sh.
 */
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <windowsx.h>
#include <shellapi.h>
#include <commctrl.h>
#include <GL/gl.h>
#include <GL/glu.h>
#include <GL/glext.h>
#include <zlib.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <wchar.h>

#define PI 3.14159265358979323846
#define NPAR 7

/* ------------------------------------------------------------------ data */

typedef struct { float p[3], n[3], uv[2]; } Vert;
typedef struct { uint32_t flags; char tex[49]; } Mat;
typedef struct {
    int nv, nt, nm;
    Vert *v;
    uint32_t *tri;
    Mat *mat;
    int *cnt;
    uint32_t **idx;
    float face;
    uint32_t flags;          /* 1 head, 2 Spine2, 4 Spine4, 8 eyes, 16 pelvis */
    double bone[4][16];      /* row-major 4x4, reference pose: head, Spine2, Spine4, pelvis */
    double eyes[16];
    double lo[3], hi[3];
    unsigned char *armv;     /* vertices of the arms' triangles (material flag 4) */
    GLuint vbo, ibo;         /* on the GPU once drawn: vertices, and the triangles material by material */
    size_t *ioff;
    GLuint *texid; int texepoch;
} Mesh;

typedef struct { char cls[128]; int compat, bone; char file[64]; wchar_t name[200]; Mesh *mesh; } Gear;
typedef struct { char pm[260]; char file[64]; wchar_t shortn[160]; Mesh *mesh; unsigned used; } PM;
typedef struct { int gear, pm; double fit[7]; char key[80]; int locked, byc; } Fit;   /* byc: approved by Claude */
typedef struct {
    int gear, n, cap, skip;
    int *f;                  /* fits (index in F), the first one is drawn */
    double adj[NPAR];        /* size %, forward, up, left, tilt (front up), turn (sideways), spin (degrees) */
    double *fp;              /* framing points (world), fixed per pair */
    int nfp;
} Pair;

static Gear *G; static int nG;
static PM *P; static int nP;
static Fit *F; static int nF, capF;
static Pair *PR; static int nPR, capPR;
static char REF[260];

static wchar_t g_cache[1024], g_tools[1024], g_python[1024];
static int CELL = 300;
static int cur = -1, show_approved = 0, hide_arms = 0, whole = 0, review_claude = 0, tight = 0, noitem = 0;
static int *hist; static int nhist;
static double view_yaw = 0, zoom = 1.0;
static unsigned g_tick = 0;

static const wchar_t *PNAME[NPAR] = { L"Size %", L"Forward", L"Up", L"Left", L"Tilt (front up)", L"Turn (sideways)", L"Spin" };
static const double STEP[NPAR] = { 1.0, 0.1, 0.1, 0.1, 1.0, 1.0, 1.0 };
static const double FINE[NPAR] = { 0.25, 0.02, 0.02, 0.02, 0.25, 0.25, 0.25 };
static const double LIM[NPAR][2] = { { -60, 150 }, { -10, 10 }, { -10, 10 }, { -10, 10 }, { -60, 60 }, { -90, 90 }, { -180, 180 } };
static const char *BONE_NAME[4] = { "ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine4",
                                    "ValveBiped.Bip01_Pelvis" };   /* (the pelvis: carry modes) */

static FILE *out;   /* --selftest: results and errors go there (no dialog) */
static void gl_init(void);
static int carry_ui = 0;   /* --carry: the carry editor's window (long guns only) */
static int cw_mode = 0;    /* its carry mode shown (0 sling arms, 1 back carry, 2 front carry) */
#define CW_FRONT 2         /* (the front carry: seen from the front) */
static void carry_status(void);

static void die(const wchar_t *fmt, ...)
{
    wchar_t b[2048];
    va_list a; va_start(a, fmt); vswprintf(b, 2048, fmt, a); va_end(a);
    if (out) { fwprintf(out, L"ERROR %ls\n", b); fclose(out); }
    else MessageBoxW(NULL, b, L"Fit editor", MB_ICONERROR);
    ExitProcess(1);
}

static void *xmalloc(size_t n) { void *p = calloc(1, n ? n : 1); if (!p) die(L"Out of memory"); return p; }

static void *read_file(const wchar_t *path, long *len)
{
    FILE *f = _wfopen(path, L"rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    char *b = xmalloc(n + 1);
    if (fread(b, 1, n, f) != (size_t)n) { fclose(f); free(b); return NULL; }
    fclose(f); b[n] = 0;
    if (len) *len = n;
    return b;
}

static void utf8_to_w(const char *s, wchar_t *out, int cap)
{
    if (!MultiByteToWideChar(CP_UTF8, 0, s, -1, out, cap)) out[0] = 0;
}

static void lower(char *s) { for (; *s; s++) if (*s >= 'A' && *s <= 'Z') *s += 32; }

/* ------------------------------------------------------------------ meshes and textures */

static Mesh *load_mesh(const char *file)
{
    wchar_t path[1400]; long len;
    swprintf(path, 1400, L"%ls\\%hs", g_cache, file);
    unsigned char *b = read_file(path, &len);
    if (!b) die(L"Can't read %ls (run fit_editor_export.py)", path);
    if (len < 24 + 64 * 4 || memcmp(b, "AFEM", 4)) die(L"Bad file %ls", path);
    Mesh *m = xmalloc(sizeof *m);
    uint32_t u[5]; float face;
    memcpy(u, b + 4, 16); memcpy(&face, b + 20, 4); memcpy(&u[4], b + 24, 4);
    if (u[0] != 1 && u[0] != 2) die(L"%ls: old format, run fit_editor_export.py again", path);
    m->nv = u[1]; m->nt = u[2]; m->nm = u[3]; m->face = face; m->flags = u[4];
    const unsigned char *q = b + 28;
    float t[16];
    for (int k = 0; k < 4; k++) {
        memcpy(t, q, 64); q += 64;
        for (int j = 0; j < 16; j++) (k < 3 ? m->bone[k] : m->eyes)[j] = t[j];
    }
    if (u[0] >= 2) {   /* v2: the pelvis after the eyes */
        memcpy(t, q, 64); q += 64;
        for (int j = 0; j < 16; j++) m->bone[3][j] = t[j];
    }
    long need = (q - b) + (long)m->nv * 32 + (long)m->nt * 16 + (long)m->nm * 52;
    if (len < need) die(L"Truncated file %ls", path);
    m->v = xmalloc(sizeof(Vert) * m->nv); memcpy(m->v, q, sizeof(Vert) * m->nv); q += sizeof(Vert) * m->nv;
    m->tri = xmalloc(16 * m->nt); memcpy(m->tri, q, 16 * m->nt); q += 16 * m->nt;
    m->mat = xmalloc(sizeof(Mat) * (m->nm + 1));
    for (int k = 0; k < m->nm; k++) {
        memcpy(&m->mat[k].flags, q, 4); memcpy(m->mat[k].tex, q + 4, 48); m->mat[k].tex[48] = 0; q += 52;
    }
    m->cnt = xmalloc(sizeof(int) * (m->nm + 1));
    m->idx = xmalloc(sizeof(uint32_t *) * (m->nm + 1));
    for (int k = 0; k < m->nt; k++) { uint32_t mt = m->tri[4 * k + 3]; if ((int)mt < m->nm) m->cnt[mt]++; }
    for (int k = 0; k < m->nm; k++) { m->idx[k] = xmalloc(12 * (m->cnt[k] + 1)); m->cnt[k] = 0; }
    for (int k = 0; k < m->nt; k++) {
        uint32_t mt = m->tri[4 * k + 3];
        if ((int)mt >= m->nm) continue;
        uint32_t *d = m->idx[mt] + 3 * m->cnt[mt]++;
        for (int j = 0; j < 3; j++) d[j] = m->tri[4 * k + j] < (uint32_t)m->nv ? m->tri[4 * k + j] : 0;
    }
    m->ioff = xmalloc(sizeof(size_t) * (m->nm + 1));
    m->texid = xmalloc(sizeof(GLuint) * (m->nm + 1));
    m->texepoch = -1;
    m->armv = xmalloc(m->nv + 1);
    for (int k = 0; k < m->nm; k++)
        if (m->mat[k].flags & 4)
            for (int j = 0; j < 3 * m->cnt[k]; j++) m->armv[m->idx[k][j]] = 1;
    for (int j = 0; j < 3; j++) { m->lo[j] = 1e30; m->hi[j] = -1e30; }
    for (int k = 0; k < m->nv; k++)
        for (int j = 0; j < 3; j++) {
            if (m->v[k].p[j] < m->lo[j]) m->lo[j] = m->v[k].p[j];
            if (m->v[k].p[j] > m->hi[j]) m->hi[j] = m->v[k].p[j];
        }
    free(b);
    return m;
}

static void free_mesh(Mesh *m)
{
    if (!m) return;
    for (int k = 0; k < m->nm; k++) free(m->idx[k]);
    free(m->idx); free(m->cnt); free(m->mat); free(m->tri); free(m->v); free(m->armv); free(m->ioff); free(m->texid); free(m);
}

/* OpenGL past 1.1, from the driver: vertex buffers, mipmaps made on the GPU, off-screen framebuffers */
static PFNGLGENBUFFERSPROC pGenBuffers; static PFNGLBINDBUFFERPROC pBindBuffer; static PFNGLBUFFERDATAPROC pBufferData;
static PFNGLGENERATEMIPMAPPROC pGenerateMipmap;
static PFNGLGENFRAMEBUFFERSPROC pGenFramebuffers; static PFNGLBINDFRAMEBUFFERPROC pBindFramebuffer;
static PFNGLGENRENDERBUFFERSPROC pGenRenderbuffers; static PFNGLBINDRENDERBUFFERPROC pBindRenderbuffer;
static PFNGLRENDERBUFFERSTORAGEPROC pRenderbufferStorage; static PFNGLFRAMEBUFFERRENDERBUFFERPROC pFramebufferRenderbuffer;
static PFNGLCHECKFRAMEBUFFERSTATUSPROC pCheckFramebufferStatus;

static void gl_procs(void)
{
#define GP(v, t, n) v = (t)(void *)wglGetProcAddress(n)
    GP(pGenBuffers, PFNGLGENBUFFERSPROC, "glGenBuffers"); GP(pBindBuffer, PFNGLBINDBUFFERPROC, "glBindBuffer");
    GP(pBufferData, PFNGLBUFFERDATAPROC, "glBufferData"); GP(pGenerateMipmap, PFNGLGENERATEMIPMAPPROC, "glGenerateMipmap");
    GP(pGenFramebuffers, PFNGLGENFRAMEBUFFERSPROC, "glGenFramebuffers"); GP(pBindFramebuffer, PFNGLBINDFRAMEBUFFERPROC, "glBindFramebuffer");
    GP(pGenRenderbuffers, PFNGLGENRENDERBUFFERSPROC, "glGenRenderbuffers"); GP(pBindRenderbuffer, PFNGLBINDRENDERBUFFERPROC, "glBindRenderbuffer");
    GP(pRenderbufferStorage, PFNGLRENDERBUFFERSTORAGEPROC, "glRenderbufferStorage");
    GP(pFramebufferRenderbuffer, PFNGLFRAMEBUFFERRENDERBUFFERPROC, "glFramebufferRenderbuffer");
    GP(pCheckFramebufferStatus, PFNGLCHECKFRAMEBUFFERSTATUSPROC, "glCheckFramebufferStatus");
#undef GP
    if (!(pGenBuffers && pBindBuffer && pBufferData)) pGenBuffers = NULL;
}

#define TEXCAP 700
static char tex_name[TEXCAP][49]; static GLuint tex_id[TEXCAP]; static int ntex, tex_epoch;

static GLuint tex_get(const char *name)
{
    for (int k = 0; k < ntex; k++) if (!strcmp(tex_name[k], name)) return tex_id[k];
    if (ntex >= TEXCAP) {  /* many playermodels seen: start again */
        for (int k = 0; k < ntex; k++) glDeleteTextures(1, &tex_id[k]);
        ntex = 0; tex_epoch++;
    }
    wchar_t path[1400]; long len; GLuint id = 0;
    swprintf(path, 1400, L"%ls\\tex\\%hs", g_cache, name);
    unsigned char *b = read_file(path, &len);
    if (b && len > 16 && !memcmp(b, "AFET", 4)) {
        uint32_t w, h, cl; memcpy(&w, b + 4, 4); memcpy(&h, b + 8, 4); memcpy(&cl, b + 12, 4);
        uLongf out = (uLongf)w * h * 4;
        unsigned char *px = xmalloc(out);
        if ((long)cl <= len - 16 && uncompress(px, &out, b + 16, cl) == Z_OK) {
            glGenTextures(1, &id);
            glBindTexture(GL_TEXTURE_2D, id);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            if (pGenerateMipmap) {
                glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, px);
                pGenerateMipmap(GL_TEXTURE_2D);
            } else gluBuild2DMipmaps(GL_TEXTURE_2D, GL_RGBA, w, h, GL_RGBA, GL_UNSIGNED_BYTE, px);
        }
        free(px);
    }
    free(b);
    strcpy(tex_name[ntex], name); tex_id[ntex++] = id;
    return id;
}

static Mesh *pm_mesh(int k)
{
    PM *p = &P[k];
    p->used = ++g_tick;
    if (p->mesh) return p->mesh;
    int loaded = 0, old = -1;
    for (int j = 0; j < nP; j++)
        if (P[j].mesh) { loaded++; if (old < 0 || P[j].used < P[old].used) old = j; }
    if (loaded >= 400 && old >= 0) { free_mesh(P[old].mesh); P[old].mesh = NULL; }   /* all of them stay, in practice */
    return p->mesh = load_mesh(p->file);
}

static Mesh *gear_mesh(int g) { return G[g].mesh ? G[g].mesh : (G[g].mesh = load_mesh(G[g].file)); }

/* ------------------------------------------------------------------ index and locks */

static int find_gear(const char *cls) { for (int k = 0; k < nG; k++) if (!strcmp(G[k].cls, cls)) return k; return -1; }

static int find_pm(const char *pm)
{
    char a[260], b[260];
    snprintf(a, sizeof a, "%s", pm); lower(a);
    for (int k = 0; k < nP; k++) { snprintf(b, sizeof b, "%s", P[k].pm); lower(b); if (!strcmp(a, b)) return k; }
    return -1;
}

static int split(char *s, char **f, int max)
{
    int n = 0;
    f[n++] = s;
    for (; *s && n < max; s++) if (*s == '\t') { *s = 0; f[n++] = s + 1; }
    return n;
}

static void load_index(void)
{
    wchar_t path[1400];
    swprintf(path, 1400, L"%ls\\index.txt", g_cache);
    char *t = read_file(path, NULL);
    if (!t) die(L"Can't read %ls: run fit_editor_export.py first (fit_editor.bat does)", path);
    G = xmalloc(sizeof(Gear) * 1024); P = xmalloc(sizeof(PM) * 2048);
    capF = 4096; F = xmalloc(sizeof(Fit) * capF);
    for (char *line = strtok(t, "\r\n"); line; line = strtok(NULL, "\r\n")) {
        char *f[8];
        int n = split(line, f, 8);
        if (!strcmp(f[0], "REF") && n >= 2) snprintf(REF, sizeof REF, "%s", f[1]);
        else if (!strcmp(f[0], "GEAR") && n >= 6 && nG < 1024) {
            Gear *g = &G[nG];
            snprintf(g->cls, sizeof g->cls, "%s", f[1]);
            g->compat = atoi(f[2]);
            g->bone = 2;
            for (int k = 0; k < 4; k++) if (!strcmp(f[3], BONE_NAME[k])) g->bone = k;
            snprintf(g->file, sizeof g->file, "%s", f[4]);
            utf8_to_w(f[5], g->name, 200);
            nG++;
        } else if (!strcmp(f[0], "PM") && n >= 4 && nP < 2048) {
            PM *p = &P[nP];
            snprintf(p->pm, sizeof p->pm, "%s", f[1]);
            snprintf(p->file, sizeof p->file, "%s", f[2]);
            utf8_to_w(f[3], p->shortn, 160);
            nP++;
        } else if (!strcmp(f[0], "FIT") && n >= 5) {
            int g = find_gear(f[1]), m = find_pm(f[2]);
            if (g < 0 || m < 0) continue;
            if (nF == capF) { capF *= 2; F = realloc(F, sizeof(Fit) * capF); if (!F) die(L"Out of memory"); }
            Fit *x = &F[nF++];
            memset(x, 0, sizeof *x);
            x->gear = g; x->pm = m;
            sscanf(f[3], "%lf %lf %lf %lf %lf %lf %lf", &x->fit[0], &x->fit[1], &x->fit[2], &x->fit[3], &x->fit[4], &x->fit[5], &x->fit[6]);
            snprintf(x->key, sizeof x->key, "%s", f[4]);
        }
    }
    free(t);
    if (!nF) die(L"No item fits in %ls", path);
}

static void lock_path(wchar_t *out) { swprintf(out, 1400, L"%ls\\fit_locks.txt", g_tools); }

static void load_locks(void)
{
    wchar_t path[1400]; lock_path(path);
    char *t = read_file(path, NULL);
    if (!t) return;
    for (char *line = strtok(t, "\r\n"); line; line = strtok(NULL, "\r\n")) {
        if (line[0] == '#') continue;
        char *f[7];
        int split_n = split(line, f, 7);
        if (split_n < 3) continue;
        int g = find_gear(f[0]), m = find_pm(f[1]);
        if (g < 0 || m < 0) continue;
        int byc = split_n >= 6 && !strncmp(f[5], "claude", 6);
        for (int k = 0; k < nF; k++)
            if (F[k].gear == g && F[k].pm == m) {
                F[k].locked = 1; F[k].byc = byc;
                sscanf(f[2], "%lf %lf %lf %lf %lf %lf %lf", &F[k].fit[0], &F[k].fit[1], &F[k].fit[2], &F[k].fit[3], &F[k].fit[4], &F[k].fit[5], &F[k].fit[6]);
            }
    }
    free(t);
}

static int *pair_of_fit;

static void make_pairs(void)
{
    capPR = 1024; PR = xmalloc(sizeof(Pair) * capPR);
    pair_of_fit = xmalloc(sizeof(int) * (nF + 1));
    for (int g = 0; g < nG; g++) {
        int first = nPR;
        for (int k = 0; k < nF; k++) {
            if (F[k].gear != g) continue;
            int p = -1;
            for (int j = first; j < nPR; j++)
                if (!strcmp(F[PR[j].f[0]].key, F[k].key)) { p = j; break; }
            if (p < 0) {
                if (nPR == capPR) { capPR *= 2; PR = realloc(PR, sizeof(Pair) * capPR); if (!PR) die(L"Out of memory"); }
                p = nPR++;
                memset(&PR[p], 0, sizeof(Pair));
                PR[p].gear = g; PR[p].cap = 4; PR[p].f = xmalloc(sizeof(int) * 4);
            }
            Pair *q = &PR[p];
            if (q->n == q->cap) { q->cap *= 2; q->f = realloc(q->f, sizeof(int) * q->cap); }
            q->f[q->n++] = k;
            pair_of_fit[k] = p;
        }
    }
    hist = xmalloc(sizeof(int) * (nPR + 16) * 4);
}

static int pair_done(int p) { for (int k = 0; k < PR[p].n; k++) if (!F[PR[p].f[k]].locked) return 0; return 1; }
static int pair_claude(int p) { for (int k = 0; k < PR[p].n; k++) if (F[PR[p].f[k]].locked && F[PR[p].f[k]].byc) return 1; return 0; }
/* approved by the user: final, never changed (Claude's approvals stay open to the user) */
static int pair_frozen(int p) { return pair_done(p) && !pair_claude(p); }

/* ------------------------------------------------------------------ fit math (Source angles) */

static void rot_matrix(double p, double y, double r, double M[3][3])
{
    p *= PI / 180; y *= PI / 180; r *= PI / 180;
    double sp = sin(p), cp = cos(p), sy = sin(y), cy = cos(y), sr = sin(r), cr = cos(r);
    M[0][0] = cp * cy; M[0][1] = sr * sp * cy - cr * sy; M[0][2] = cr * sp * cy + sr * sy;
    M[1][0] = cp * sy; M[1][1] = sr * sp * sy + cr * cy; M[1][2] = cr * sp * sy - sr * cy;
    M[2][0] = -sp;     M[2][1] = sr * cp;                M[2][2] = cr * cp;
}

static void matrix_angles(double M[3][3], double a[3])
{
    double xy = hypot(M[0][0], M[1][0]);
    if (xy > 0.001) {
        a[0] = atan2(-M[2][0], xy) * 180 / PI;
        a[1] = atan2(M[1][0], M[0][0]) * 180 / PI;
        a[2] = atan2(M[2][1], M[2][2]) * 180 / PI;
    } else {
        a[0] = atan2(-M[2][0], xy) * 180 / PI;
        a[1] = atan2(-M[0][1], M[1][1]) * 180 / PI;
        a[2] = 0;
    }
}

static void mul3(double A[3][3], double B[3][3], double C[3][3])
{
    double T[3][3];
    for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++) T[i][j] = A[i][0] * B[0][j] + A[i][1] * B[1][j] + A[i][2] * B[2][j];
    memcpy(C, T, sizeof T);
}

static void mv3(double A[3][3], const double v[3], double o[3])
{
    double t[3];
    for (int i = 0; i < 3; i++) t[i] = A[i][0] * v[0] + A[i][1] * v[1] + A[i][2] * v[2];
    memcpy(o, t, sizeof t);
}

static void bone_rt(const double *B, double R[3][3], double t[3])
{
    for (int i = 0; i < 3; i++) { for (int j = 0; j < 3; j++) R[i][j] = B[4 * i + j]; t[i] = B[4 * i + 3]; }
}

static void transpose(double A[3][3], double T[3][3])
{
    double X[3][3];
    for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++) X[i][j] = A[j][i];
    memcpy(T, X, sizeof X);
}

/* forward, left, up of the pair's frame (body model space): the eyes for head items, else the facing */
static void frame_axes(Mesh *b, int head, double Fw[3], double Lf[3], double U[3])
{
    if (head && (b->flags & 8)) {
        for (int i = 0; i < 3; i++) { Fw[i] = b->eyes[4 * i]; Lf[i] = b->eyes[4 * i + 1]; U[i] = b->eyes[4 * i + 2]; }
        return;
    }
    double y = b->face * PI / 180;
    Fw[0] = cos(y); Fw[1] = sin(y); Fw[2] = 0;
    U[0] = 0; U[1] = 0; U[2] = 1;
    Lf[0] = -Fw[1]; Lf[1] = Fw[0]; Lf[2] = 0;   /* up x forward */
}

static double rnd(double x, double s) { double r = floor(x * s + 0.5) / s; return r == 0 ? 0 : r; }

static int adj_zero(const double *a) { for (int k = 0; k < NPAR; k++) if (fabs(a[k]) > 1e-9) return 0; return 1; }

/* rotation of deg degrees around the unit axis ax (Rodrigues) */
static void axis_rot(const double ax[3], double deg, double Q[3][3])
{
    double a = deg * PI / 180, ca = cos(a), sa = sin(a);
    for (int i = 0; i < 3; i++)
        for (int j = 0; j < 3; j++) Q[i][j] = (i == j ? ca : 0) + (1 - ca) * ax[i] * ax[j];
    Q[0][1] += -sa * ax[2]; Q[0][2] += sa * ax[1];
    Q[1][0] += sa * ax[2];  Q[1][2] += -sa * ax[0];
    Q[2][0] += -sa * ax[1]; Q[2][1] += sa * ax[0];
}

/* the fit after the adjustment, rounded like the game's files: size and the rotations about the item's
   centre (spin around its own length first, then tilt around the body's left axis, then turn around the
   body's forward axis) */
static void adjusted(int p, const double *adj, double out[7])
{
    Fit *f0 = &F[PR[p].f[0]];
    memcpy(out, f0->fit, sizeof(double) * 7);
    if (adj_zero(adj)) return;
    Gear *g = &G[PR[p].gear];
    Mesh *b = pm_mesh(f0->pm), *it = gear_mesh(PR[p].gear);
    double Rb[3][3], tb[3], RbT[3][3], M0[3][3], c[3], Fw[3], Lf[3], U[3];
    bone_rt(b->bone[g->bone], Rb, tb); transpose(Rb, RbT);
    rot_matrix(f0->fit[3], f0->fit[4], f0->fit[5], M0);
    for (int i = 0; i < 3; i++) c[i] = (it->lo[i] + it->hi[i]) / 2;
    frame_axes(b, g->bone == 0, Fw, Lf, U);
    /* a carried weapon (compat 3) has no size: only its place and angles change */
    double s0 = f0->fit[6], s1 = g->compat == 3 ? s0 : s0 * (1 + adj[0] / 100), v[3], p0[3];
    for (int i = 0; i < 3; i++) v[i] = s0 * c[i];
    mv3(M0, v, v);
    for (int i = 0; i < 3; i++) v[i] += f0->fit[i];
    mv3(Rb, v, p0);
    for (int i = 0; i < 3; i++) p0[i] += tb[i];
    double Q[3][3], Qt[3][3], Qs[3][3], W0[3][3], len[3], ax0[3] = { 1, 0, 0 };
    /* the item's own length: its model's longest axis (X for most guns; Y for the Sandstorm SWEPs,
       posed by their idle animation) */
    if (it->hi[1] - it->lo[1] > 1.25 * (it->hi[0] - it->lo[0])) { ax0[0] = 0; ax0[1] = 1; }
    mul3(Rb, M0, W0);
    mv3(W0, ax0, len);
    double ln = sqrt(len[0] * len[0] + len[1] * len[1] + len[2] * len[2]);
    for (int i = 0; i < 3; i++) len[i] /= ln > 1e-9 ? ln : 1;
    axis_rot(Lf, -adj[4], Q);                     /* tilt: front up */
    axis_rot(Fw, NPAR > 5 ? adj[5] : 0, Qt);      /* turn sideways (seen from the back) */
    axis_rot(len, NPAR > 6 ? adj[6] : 0, Qs);     /* spin around its length */
    mul3(Qt, Q, Q); mul3(Q, Qs, Q);
    double M1[3][3];
    mul3(Q, W0, M1); mul3(RbT, M1, M1);
    double p1[3], d[3];
    for (int i = 0; i < 3; i++) p1[i] = p0[i] + Fw[i] * adj[1] + U[i] * adj[2] + Lf[i] * adj[3] - tb[i];
    mv3(RbT, p1, p1);
    for (int i = 0; i < 3; i++) v[i] = s1 * c[i];
    mv3(M1, v, d);
    double ang[3];
    matrix_angles(M1, ang);
    for (int i = 0; i < 3; i++) { out[i] = rnd(p1[i] - d[i], 100); out[3 + i] = rnd(ang[i], 10); }
    out[6] = rnd(s1, 1000);
}

/* item -> body model space: column-major 4x4 for OpenGL */
static void item_matrix(Mesh *b, int bone, const double fit[7], double gl[16])
{
    double Rb[3][3], tb[3], M[3][3], t[3];
    bone_rt(b->bone[bone], Rb, tb);
    rot_matrix(fit[3], fit[4], fit[5], M);
    mul3(Rb, M, M);
    mv3(Rb, fit, t);
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) gl[4 * j + i] = M[i][j] * fit[6];
        gl[12 + i] = t[i] + tb[i];
        gl[4 * i + 3] = 0;
    }
    gl[15] = 1;
}

/* framing of the pair: the item at its first fit and the body around it, a bit wider */
static void make_frame(int p)
{
    Pair *q = &PR[p];
    if (q->fp) return;
    Fit *f0 = &F[q->f[0]];
    Mesh *b = pm_mesh(f0->pm), *it = gear_mesh(q->gear);
    double M[16], lo[3] = { 1e30, 1e30, 1e30 }, hi[3] = { -1e30, -1e30, -1e30 };
    item_matrix(b, G[q->gear].bone, f0->fit, M);
    double *pts = xmalloc(sizeof(double) * 3 * (it->nv + b->nv));
    int n = 0;
    for (int k = 0; k < it->nv; k++) {
        const float *v = it->v[k].p;
        for (int i = 0; i < 3; i++) pts[3 * n + i] = M[i] * v[0] + M[4 + i] * v[1] + M[8 + i] * v[2] + M[12 + i];
        for (int i = 0; i < 3; i++) { if (pts[3 * n + i] < lo[i]) lo[i] = pts[3 * n + i]; if (pts[3 * n + i] > hi[i]) hi[i] = pts[3 * n + i]; }
        n++;
    }
    double c[3], r = 0;
    for (int i = 0; i < 3; i++) { c[i] = (lo[i] + hi[i]) / 2; r += (hi[i] - lo[i]) * (hi[i] - lo[i]) / 4; }
    r = tight ? sqrt(r) * 0.75 : sqrt(r) * 1.5 + 4;   /* --tight: the item and what is right under it */
    for (int k = 0; k < b->nv; k++) {
        const float *v = b->v[k].p;
        if (b->armv[k]) continue;   /* an arm next to the item doesn't widen the view */
        double d = (v[0] - c[0]) * (v[0] - c[0]) + (v[1] - c[1]) * (v[1] - c[1]) + (v[2] - c[2]) * (v[2] - c[2]);
        if (d < r * r) { for (int i = 0; i < 3; i++) pts[3 * n + i] = v[i]; n++; }
    }
    for (int i = 0; i < 3; i++) { lo[i] = 1e30; hi[i] = -1e30; }
    for (int k = 0; k < n; k++)
        for (int i = 0; i < 3; i++) { if (pts[3 * k + i] < lo[i]) lo[i] = pts[3 * k + i]; if (pts[3 * k + i] > hi[i]) hi[i] = pts[3 * k + i]; }
    for (int k = 0; k < n; k++)   /* room for a bigger item */
        for (int i = 0; i < 3; i++) pts[3 * k + i] = (lo[i] + hi[i]) / 2 + (pts[3 * k + i] - (lo[i] + hi[i]) / 2) * 1.12;
    q->fp = pts; q->nfp = n;
}

/* ------------------------------------------------------------------ drawing */

static HWND g_main, g_gl, g_cbGear, g_cbPair, g_chk, g_title, g_also, g_status, g_help, g_lbl[4], g_abs;
static HWND g_ed[NPAR], g_bm[NPAR], g_bp[NPAR], g_pl[NPAR];
static HWND g_bReset, g_bPrev, g_bSkip, g_bApprove, g_bUnlock, g_chkArms, g_chkWhole, g_chkClaude;
static HDC g_dc; static HGLRC g_rc;
static HFONT g_font, g_bold;
static int GLH;

/* sends a mesh to the GPU once (vertices + triangles) and finds its textures */
static void upload_mesh(Mesh *m)
{
    if (m->texepoch != tex_epoch) {
        for (int k = 0; k < m->nm; k++) m->texid[k] = m->mat[k].tex[0] ? tex_get(m->mat[k].tex) : 0;
        m->texepoch = tex_epoch;
    }
    if (m->vbo || !pGenBuffers) return;
    size_t total = 0;
    for (int k = 0; k < m->nm; k++) { m->ioff[k] = total; total += 3 * (size_t)m->cnt[k]; }
    uint32_t *all = xmalloc(4 * (total + 1));
    for (int k = 0; k < m->nm; k++) memcpy(all + m->ioff[k], m->idx[k], 12 * (size_t)m->cnt[k]);
    pGenBuffers(1, &m->vbo); pBindBuffer(GL_ARRAY_BUFFER, m->vbo);
    pBufferData(GL_ARRAY_BUFFER, sizeof(Vert) * m->nv, m->v, GL_STATIC_DRAW);
    pGenBuffers(1, &m->ibo); pBindBuffer(GL_ELEMENT_ARRAY_BUFFER, m->ibo);
    pBufferData(GL_ELEMENT_ARRAY_BUFFER, 4 * total, all, GL_STATIC_DRAW);
    pBindBuffer(GL_ARRAY_BUFFER, 0); pBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    free(all);
}

static void draw_mesh(Mesh *m, int pass)
{
    upload_mesh(m);
    if (m->vbo) {
        pBindBuffer(GL_ARRAY_BUFFER, m->vbo); pBindBuffer(GL_ELEMENT_ARRAY_BUFFER, m->ibo);
        glVertexPointer(3, GL_FLOAT, sizeof(Vert), (void *)0);
        glNormalPointer(GL_FLOAT, sizeof(Vert), (void *)12);
        glTexCoordPointer(2, GL_FLOAT, sizeof(Vert), (void *)24);
    } else {
        glVertexPointer(3, GL_FLOAT, sizeof(Vert), m->v[0].p);
        glNormalPointer(GL_FLOAT, sizeof(Vert), m->v[0].n);
        glTexCoordPointer(2, GL_FLOAT, sizeof(Vert), m->v[0].uv);
    }
    for (int k = 0; k < m->nm; k++) {
        if (!m->cnt[k] || (int)(m->mat[k].flags & 1) != pass || (hide_arms && (m->mat[k].flags & 4))) continue;
        GLuint t = m->texid[k];
        if (t) { glEnable(GL_TEXTURE_2D); glBindTexture(GL_TEXTURE_2D, t); }
        else glDisable(GL_TEXTURE_2D);   /* half light x white = 160 grey lit */
        glColor3f(1, 1, 1);
        if (m->mat[k].flags & 2) { glEnable(GL_ALPHA_TEST); glAlphaFunc(GL_GEQUAL, 0.5f); }
        else glDisable(GL_ALPHA_TEST);
        glDrawElements(GL_TRIANGLES, m->cnt[k] * 3, GL_UNSIGNED_INT, m->vbo ? (void *)(m->ioff[k] * 4) : (void *)m->idx[k]);
    }
    if (m->vbo) { pBindBuffer(GL_ARRAY_BUFFER, 0); pBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0); }
}

static const double VIEWS[2][4][2] = { { { 0, 3 }, { 40, 6 }, { 90, 3 }, { 180, 3 } },
                                       { { 0, 5 }, { 35, 8 }, { 90, 4 }, { 180, 8 } } };
static const wchar_t *VIEWNAME[4] = { L"front", L"3/4", L"side", L"back" };

/* pair p with the adjustment adj, its views (indices in VIEWS) side by side from (x0, y0), each cw x H */
static void draw_pair(int p, const double *adj, int x0, int y0, int cw, int H, int nv, const int *views)
{
    Pair *q = &PR[p];
    Fit *f0 = &F[q->f[0]];
    Gear *g = &G[q->gear];
    Mesh *b = pm_mesh(f0->pm), *it = gear_mesh(q->gear);
    make_frame(p);
    double fit[7], M[16];
    adjusted(p, adj, fit);
    item_matrix(b, g->bone, fit, M);
    int kind = g->bone == 0 ? 0 : 1;

    glEnable(GL_DEPTH_TEST); glEnable(GL_LIGHTING); glEnable(GL_LIGHT0); glEnable(GL_LIGHT1);
    glEnable(GL_COLOR_MATERIAL); glColorMaterial(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE);
    glEnable(GL_NORMALIZE);
    glLightModeli(GL_LIGHT_MODEL_TWO_SIDE, 1);
    glFrontFace(GL_CW);   /* Source's triangles turn clockwise: else every face is lit from behind */
    /* the light of mdl_render.rasterize (0.45 + 0.75 + 0.25, up to 1.45 x the texture): halved here and
       doubled by the texture stage, OpenGL clamps the vertex colour to 1 */
    float amb[4] = { 0.225f, 0.225f, 0.225f, 1 }, zero[4] = { 0, 0, 0, 1 };
    float d0[4] = { 0.375f, 0.375f, 0.375f, 1 }, d1[4] = { 0.125f, 0.125f, 0.125f, 1 };
    glLightModelfv(GL_LIGHT_MODEL_AMBIENT, amb);
    glLightfv(GL_LIGHT0, GL_DIFFUSE, d0); glLightfv(GL_LIGHT0, GL_AMBIENT, zero); glLightfv(GL_LIGHT0, GL_SPECULAR, zero);
    glLightfv(GL_LIGHT1, GL_DIFFUSE, d1); glLightfv(GL_LIGHT1, GL_AMBIENT, zero); glLightfv(GL_LIGHT1, GL_SPECULAR, zero);
    glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, 0x8570);   /* GL_COMBINE (1.3): texture x colour */
    glTexEnvi(GL_TEXTURE_ENV, 0x8571, GL_MODULATE);            /* GL_COMBINE_RGB */
    glTexEnvf(GL_TEXTURE_ENV, 0x8573, 2.0f);                   /* GL_RGB_SCALE */
    glEnableClientState(GL_VERTEX_ARRAY); glEnableClientState(GL_NORMAL_ARRAY); glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glEnable(GL_SCISSOR_TEST);

    /* framing points: the close-up of the pair, or the corners of the whole model (F) */
    double corners[24], *fp = q->fp;
    int nfp = q->nfp;
    if (whole) {
        for (int k = 0; k < 8; k++)
            for (int i = 0; i < 3; i++) corners[3 * k + i] = ((k >> i) & 1) ? b->hi[i] + 2 : b->lo[i] - 2;
        fp = corners; nfp = 8;
    }
    double lo[3] = { 1e30, 1e30, 1e30 }, hi[3] = { -1e30, -1e30, -1e30 };
    for (int k = 0; k < nfp; k++)
        for (int i = 0; i < 3; i++) { if (fp[3 * k + i] < lo[i]) lo[i] = fp[3 * k + i]; if (fp[3 * k + i] > hi[i]) hi[i] = fp[3 * k + i]; }
    double c[3], rad = 0;
    for (int i = 0; i < 3; i++) { c[i] = (lo[i] + hi[i]) / 2; rad += (hi[i] - lo[i]) * (hi[i] - lo[i]) / 4; }
    rad = sqrt(rad);

    for (int v = 0; v < nv; v++) {
        int x = x0 + v * cw;
        glViewport(x + 1, y0, cw - 2, H); glScissor(x + 1, y0, cw - 2, H);
        glClearColor(78 / 255.f, 82 / 255.f, 90 / 255.f, 1);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        double yaw = (b->face + VIEWS[kind][views[v]][0] + view_yaw) * PI / 180, pitch = VIEWS[kind][views[v]][1] * PI / 180;
        double tc[3] = { cos(pitch) * cos(yaw), cos(pitch) * sin(yaw), sin(pitch) };
        double fw[3] = { -tc[0], -tc[1], -tc[2] }, rt[3], up[3], cam[3];
        rt[0] = fw[1]; rt[1] = -fw[0]; rt[2] = 0;   /* fw x z */
        double l = sqrt(rt[0] * rt[0] + rt[1] * rt[1]); rt[0] /= l; rt[1] /= l;
        up[0] = rt[1] * fw[2] - rt[2] * fw[1]; up[1] = rt[2] * fw[0] - rt[0] * fw[2]; up[2] = rt[0] * fw[1] - rt[1] * fw[0];
        for (int i = 0; i < 3; i++) cam[i] = c[i] + tc[i] * rad * 4;
        /* framing like mdl_render.rasterize: the framing points' projection fills 94% */
        double mnx = 1e30, mxx = -1e30, mny = 1e30, mxy = -1e30;
        for (int k = 0; k < nfp; k++) {
            double r0 = fp[3 * k] - cam[0], r1 = fp[3 * k + 1] - cam[1], r2 = fp[3 * k + 2] - cam[2];
            double zc = r0 * fw[0] + r1 * fw[1] + r2 * fw[2];
            if (zc < 1e-3) continue;
            double px = (r0 * rt[0] + r1 * rt[1] + r2 * rt[2]) / zc, py = (r0 * up[0] + r1 * up[1] + r2 * up[2]) / zc;
            mnx = fmin(mnx, px); mxx = fmax(mxx, px); mny = fmin(mny, py); mxy = fmax(mxy, py);
        }
        double half = fmax(mxx - mnx, mxy - mny) / 0.94 / 2 * zoom, mx = (mnx + mxx) / 2, my = (mny + mxy) / 2;
        double asp = (double)(cw - 2) / H, nearp = rad, farp = rad * 40;
        glMatrixMode(GL_PROJECTION); glLoadIdentity();
        glFrustum((mx - half * asp) * nearp, (mx + half * asp) * nearp, (my - half) * nearp, (my + half) * nearp, nearp, farp);
        glMatrixMode(GL_MODELVIEW); glLoadIdentity();
        float l0[4] = { 0.6f, 0.9f, 1.0f, 0 }, l1[4] = { -0.8f, 0.2f, 0, 0 };
        glLightfv(GL_LIGHT0, GL_POSITION, l0); glLightfv(GL_LIGHT1, GL_POSITION, l1);
        gluLookAt(cam[0], cam[1], cam[2], cam[0] + fw[0], cam[1] + fw[1], cam[2] + fw[2], up[0], up[1], up[2]);
        for (int pass = 0; pass < 2; pass++) {
            if (pass) { glEnable(GL_BLEND); glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA); glDepthMask(GL_FALSE); }
            draw_mesh(b, pass);
            if (!noitem) { glPushMatrix(); glMultMatrixd(M); draw_mesh(it, pass); glPopMatrix(); }
            if (pass) { glDisable(GL_BLEND); glDepthMask(GL_TRUE); }
        }
    }
    glDisable(GL_SCISSOR_TEST);
}

static void render(void)
{
    static const int all4[4] = { 0, 1, 2, 3 };
    RECT rc; GetClientRect(g_gl, &rc);
    int W = rc.right, H = rc.bottom;
    glViewport(0, 0, W, H);
    glClearColor(0.12f, 0.12f, 0.13f, 1); glDisable(GL_SCISSOR_TEST);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    if (cur >= 0 && carry_ui) {   /* the carry editor: back (front for the front carry) and side */
        int v2[2] = { cw_mode == CW_FRONT ? 0 : 3, 2 };
        draw_pair(cur, PR[cur].adj, 0, 0, W / 2, H, 2, v2);
    } else if (cur >= 0) draw_pair(cur, PR[cur].adj, 0, 0, W / 4, H, 4, all4);   /* no glFinish: SwapBuffers paces it */
}

/* ------------------------------------------------------------------ user interface */

enum { ID_GEAR = 100, ID_PAIR, ID_SHOW, ID_RESET, ID_PREV, ID_SKIP, ID_APPROVE, ID_UNLOCK, ID_ARMS, ID_WHOLE, ID_CLAUDE,
       ID_MINUS = 200, ID_PLUS = 220, ID_EDIT = 240 };

static HANDLE g_apply; static int g_apply_again, g_apply_failed;
static wchar_t g_note[300];

static void set_status(void)
{
    if (carry_ui) { carry_status(); return; }
    int done = 0, locked = 0, gdone = 0, gall = 0, claude = 0;
    for (int p = 0; p < nPR; p++) {
        int d = pair_done(p);
        done += d;
        if (cur >= 0 && PR[p].gear == PR[cur].gear) { gall++; gdone += d; }
    }
    for (int k = 0; k < nF; k++) { locked += F[k].locked; claude += F[k].locked && F[k].byc; }
    wchar_t b[800];
    swprintf(b, 800, L"Approved: %d of %d pairs (%d of %d item x playermodel combinations, %d of them by Claude).   This item: %d of %d.   %ls",
             done, nPR, locked, nF, claude, gdone, gall, g_note);
    SetWindowTextW(g_status, b);
}

static void gear_label(int g, wchar_t *out_, int cap)
{
    int left = 0, all = 0;
    for (int p = 0; p < nPR; p++) if (PR[p].gear == g) { all++; left += !pair_done(p); }
    swprintf(out_, cap, L"%ls%ls  (%d of %d left)", left ? L"" : L"\x2713 ", G[g].name, left, all);
}

static void fill_gear_combo(void)
{
    SendMessageW(g_cbGear, CB_RESETCONTENT, 0, 0);
    wchar_t b[400];
    for (int g = 0; g < nG; g++) { gear_label(g, b, 400); SendMessageW(g_cbGear, CB_ADDSTRING, 0, (LPARAM)b); }
}

static int pair_combo_gear = -1;
static void fill_pair_combo(int g)
{
    SendMessageW(g_cbPair, CB_RESETCONTENT, 0, 0);
    wchar_t b[400], t[40];
    for (int p = 0; p < nPR; p++) {
        if (PR[p].gear != g) continue;
        const wchar_t *mark = !pair_done(p) ? L"" : pair_claude(p) ? L"\x2713(Claude) " : L"\x2713 ";
        if (PR[p].n > 1) swprintf(t, 40, L" (+%d)", PR[p].n - 1); else t[0] = 0;
        swprintf(b, 400, L"%ls%ls%ls", mark, P[F[PR[p].f[0]].pm].shortn, t);
        int i = (int)SendMessageW(g_cbPair, CB_ADDSTRING, 0, (LPARAM)b);
        SendMessageW(g_cbPair, CB_SETITEMDATA, i, p);
    }
    pair_combo_gear = g;
}

static void show_values(void)
{
    if (cur < 0) return;
    Pair *q = &PR[cur];
    wchar_t b[64];
    for (int k = 0; k < NPAR; k++) { swprintf(b, 64, L"%+.2f", q->adj[k]); SetWindowTextW(g_ed[k], b); }
    double fit[7]; adjusted(cur, q->adj, fit);
    swprintf(b, 64, L"= size x%.3f", fit[6]);
    SetWindowTextW(g_abs, b);
}

static void show_pair(int p, int remember)
{
    if (p < 0 || p >= nPR) return;
    if (remember && cur >= 0 && cur != p) hist[nhist++ % ((nPR + 16) * 4)] = cur;
    cur = p;
    view_yaw = 0; zoom = 1;
    Pair *q = &PR[p];
    Fit *f0 = &F[q->f[0]];
    int done = pair_done(p), claude = pair_claude(p), frozen = done && !claude, part = 0;
    for (int k = 0; k < q->n; k++) part += F[q->f[k]].locked;
    wchar_t t[700];
    swprintf(t, 700, L"%ls   on   %ls      %ls", G[q->gear].name, P[f0->pm].shortn,
             frozen ? L"[APPROVED by you: final. Unlock to change it]"
             : claude ? L"[approved by Claude: Enter makes it yours, or adjust it first]"
             : part ? L"[partly approved: only the others will change]" : L"");
    SetWindowTextW(g_title, t);
    /* the other playermodels this pair stands for */
    size_t cap = 64 + 120 * (size_t)q->n;
    wchar_t *a = xmalloc(sizeof(wchar_t) * cap);
    if (q->n > 1) {
        swprintf(a, cap, L"Same head/torso shape and fit, approved together (%d): ", q->n - 1);
        for (int k = 1; k < q->n; k++) {
            wcscat(a, P[F[q->f[k]].pm].shortn);
            if (k < q->n - 1) wcscat(a, L", ");
        }
    } else wcscpy(a, L"");
    SetWindowTextW(g_also, a);
    free(a);
    SendMessageW(g_cbGear, CB_SETCURSEL, q->gear, 0);
    if (pair_combo_gear != q->gear) fill_pair_combo(q->gear);
    int n = (int)SendMessageW(g_cbPair, CB_GETCOUNT, 0, 0);
    for (int i = 0; i < n; i++) if ((int)SendMessageW(g_cbPair, CB_GETITEMDATA, i, 0) == p) SendMessageW(g_cbPair, CB_SETCURSEL, i, 0);
    for (int k = 0; k < NPAR; k++) { EnableWindow(g_ed[k], !frozen); EnableWindow(g_bm[k], !frozen); EnableWindow(g_bp[k], !frozen); }
    EnableWindow(g_bApprove, !frozen); EnableWindow(g_bReset, !frozen); EnableWindow(g_bUnlock, frozen);
    show_values();
    set_status();
    InvalidateRect(g_gl, NULL, FALSE);
}

static int next_pending(int from, int gear_only)
{
    for (int k = 1; k <= nPR; k++) {
        int p = (from + k) % nPR;
        if (gear_only >= 0 && PR[p].gear != gear_only) continue;
        if (show_approved || !pair_done(p) || (review_claude && pair_claude(p))) return p;
    }
    return -1;
}

static void change(int k, double d)
{
    if (cur < 0 || pair_frozen(cur)) { MessageBeep(MB_ICONASTERISK); return; }
    double *a = &PR[cur].adj[k];
    *a = fmin(LIM[k][1], fmax(LIM[k][0], *a + d));
    if (fabs(*a) < 1e-9) *a = 0;
    show_values();
    InvalidateRect(g_gl, NULL, FALSE);
}

static void commit_edit(int k)
{
    if (cur < 0 || pair_frozen(cur)) return;
    wchar_t b[64]; GetWindowTextW(g_ed[k], b, 64);
    wchar_t *e; double v = wcstod(b, &e);
    if (e != b) PR[cur].adj[k] = fmin(LIM[k][1], fmax(LIM[k][0], v));
    show_values();
    InvalidateRect(g_gl, NULL, FALSE);
}

static void apply_cmd(wchar_t *cmd, int cap)
{
    swprintf(cmd, cap, L"\"%ls\" -I \"%ls\\fit_locks.py\" apply", g_python, g_tools);
}

static void run_apply(void)
{
    if (g_apply) { g_apply_again = 1; return; }
    wchar_t cmd[3200]; apply_cmd(cmd, 3200);
    STARTUPINFOW si; PROCESS_INFORMATION pi;
    memset(&si, 0, sizeof si); si.cb = sizeof si;
    if (CreateProcessW(NULL, cmd, NULL, NULL, FALSE, CREATE_NO_WINDOW | BELOW_NORMAL_PRIORITY_CLASS, NULL, g_tools, &si, &pi)) {
        CloseHandle(pi.hThread);
        g_apply = pi.hProcess;
        wcscpy(g_note, L"Writing the game's fit files...");
    } else {
        g_apply_failed = 1;
        wcscpy(g_note, L"Could not start python to write the game's fit files (python fit_locks.py apply).");
    }
    set_status();
}

static void poll_apply(void)
{
    if (!g_apply || WaitForSingleObject(g_apply, 0) != WAIT_OBJECT_0) return;
    DWORD code = 1; GetExitCodeProcess(g_apply, &code); CloseHandle(g_apply); g_apply = NULL;
    if (code) wcscpy(g_note, L"WRITING THE GAME'S FIT FILES FAILED: run  python fit_locks.py apply  to see why.");
    else wcscpy(g_note, L"Saved in fit_locks.txt and the game's fit files.");
    set_status();
    if (g_apply_again) { g_apply_again = 0; run_apply(); }
}

static void fmt_fit(char *o, size_t cap, const double *f)
{
    char s[32]; snprintf(s, sizeof s, "%.3f", f[6]);
    for (char *e = s + strlen(s) - 1; e > s && *e == '0'; e--) *e = 0;
    if (s[strlen(s) - 1] == '.') s[strlen(s) - 1] = 0;
    snprintf(o, cap, "%.2f %.2f %.2f %.1f %.1f %.1f %s", f[0], f[1], f[2], f[3], f[4], f[5], s);
}

/* drops the lines of pair p's playermodels from fit_locks.txt (only Claude's with only_claude) */
static void remove_locks(int p, int only_claude)
{
    Pair *q = &PR[p];
    wchar_t path[1400]; lock_path(path);
    long len; char *t = read_file(path, &len);
    if (!t) return;
    /* written beside it, then put in its place: a crash or a full disk mid-write must not leave the
       approvals truncated */
    wchar_t tmpp[1420]; swprintf(tmpp, 1420, L"%ls.tmp", path);
    FILE *f = _wfopen(tmpp, L"wb");
    if (!f) { free(t); return; }
    int bad = 0;
    char *s = t;
    while (*s) {
        char *e = strchr(s, '\n'); size_t n = e ? (size_t)(e - s + 1) : strlen(s);
        char line[1024]; size_t m = n < sizeof line - 1 ? n : sizeof line - 1;
        memcpy(line, s, m); line[m] = 0;
        int drop = 0;
        if (line[0] != '#') {
            char *fl[7]; char tmp[1024]; strcpy(tmp, line);
            int nf = split(tmp, fl, 7);
            int byc = nf >= 6 && !strncmp(fl[5], "claude", 6);
            if (nf >= 3 && find_gear(fl[0]) == q->gear && (!only_claude || byc)) {
                int pm = find_pm(fl[1]);
                for (int k = 0; k < q->n; k++) if (F[q->f[k]].pm == pm) drop = 1;
            }
        }
        if (!drop && fwrite(s, 1, n, f) != n) bad = 1;
        s += n;
    }
    if (fclose(f) != 0) bad = 1;
    free(t);
    if (bad || !MoveFileExW(tmpp, path, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        _wremove(tmpp); /* the file as it was: nothing removed */
        return;
    }
    for (int k = 0; k < q->n; k++) {
        Fit *x = &F[q->f[k]];
        if (x->locked && (!only_claude || x->byc)) { x->locked = 0; x->byc = 0; }
    }
}

/* approves pair p with its adjustment: the playermodels not approved yet (and Claude's, again) */
static int approve_pair(int p, const char *by)
{
    Pair *q = &PR[p];
    if (pair_claude(p)) remove_locks(p, 1);
    double fit[7]; adjusted(p, q->adj, fit);
    wchar_t path[1400]; lock_path(path);
    FILE *f = _wfopen(path, L"ab");
    if (!f) return -1;
    fseek(f, 0, SEEK_END);
    if (ftell(f) == 0)
        fputs("# Fits approved in the fit editor (tools/fit_editor/): final, fit_items.py and fit_compat.py keep them.\n"
              "# item class<TAB>playermodel<TAB>x y z pitch yaw roll size<TAB>date<TAB>adjustment made<TAB>approved by (user, claude)\n", f);
    SYSTEMTIME st; GetLocalTime(&st);
    char nums[200], adj[200];
    fmt_fit(nums, sizeof nums, fit);
    snprintf(adj, sizeof adj, "size %+.2f%% forward %+.2f up %+.2f left %+.2f tilt %+.2f turn %+.2f spin %+.2f",
             q->adj[0], q->adj[1], q->adj[2], q->adj[3], q->adj[4], q->adj[5], q->adj[6]);
    int n = 0;
    for (int k = 0; k < q->n; k++) {
        Fit *x = &F[q->f[k]];
        if (x->locked) continue;
        fprintf(f, "%s\t%s\t%s\t%04d-%02d-%02d\t%s\t%s\n", G[q->gear].cls, P[x->pm].pm, nums, st.wYear, st.wMonth, st.wDay, adj, by);
        memcpy(x->fit, fit, sizeof fit);
        x->locked = 1; x->byc = !strcmp(by, "claude");
        n++;
    }
    fclose(f);
    memset(q->adj, 0, sizeof q->adj);
    return n;
}

static void refresh_gear_label(int g)
{
    wchar_t b[400]; gear_label(g, b, 400);
    SendMessageW(g_cbGear, CB_DELETESTRING, g, 0); SendMessageW(g_cbGear, CB_INSERTSTRING, g, (LPARAM)b);
    pair_combo_gear = -1;
}

static void approve(void)
{
    if (cur < 0 || pair_frozen(cur)) return;
    if (approve_pair(cur, "user") < 0) { MessageBoxW(g_main, L"Can't write fit_locks.txt", L"Fit editor", MB_ICONERROR); return; }
    run_apply();
    refresh_gear_label(PR[cur].gear);
    int nx = next_pending(cur, -1);
    if (nx < 0) { show_pair(cur, 0); MessageBoxW(g_main, L"Every pair is approved.", L"Fit editor", MB_ICONINFORMATION); }
    else show_pair(nx, 1);
}

static void unlock(void)
{
    if (cur < 0 || !pair_frozen(cur)) return;
    Pair *q = &PR[cur];
    wchar_t msg[500];
    swprintf(msg, 500, L"Unlock %ls on %ls%ls? You approved it as final; the editor will ask for it again.",
             G[q->gear].name, P[F[q->f[0]].pm].shortn, q->n > 1 ? L" (and the playermodels approved with it)" : L"");
    if (MessageBoxW(g_main, msg, L"Fit editor", MB_YESNO | MB_ICONQUESTION) != IDYES) return;
    remove_locks(cur, 0);
    refresh_gear_label(q->gear);
    wcscpy(g_note, L"Unlocked (the game's files keep its fit until you approve it again).");
    show_pair(cur, 0);
}

static void prev(void)
{
    if (nhist <= 0) { MessageBeep(MB_ICONASTERISK); return; }
    nhist--;
    show_pair(hist[nhist % ((nPR + 16) * 4)], 0);
}

static int handle_key(MSG *m)
{
    if (m->message != WM_KEYDOWN) return 0;
    HWND f = GetFocus();
    wchar_t cls[32] = L"";
    if (f) GetClassNameW(f, cls, 32);
    int shift = GetKeyState(VK_SHIFT) < 0;
    WPARAM k = m->wParam;
    if (!_wcsicmp(cls, L"Edit")) {
        if (k == VK_RETURN || k == VK_TAB) { SetFocus(g_main); return 1; }   /* EN_KILLFOCUS commits */
        if (k == VK_ESCAPE) { show_values(); SetFocus(g_main); return 1; }
        return 0;
    }
    if (!_wcsicmp(cls, L"ComboBox") && (k == VK_UP || k == VK_DOWN || SendMessageW(f, CB_GETDROPPEDSTATE, 0, 0))) return 0;
    const double *st = shift ? FINE : STEP;
    switch (k) {
    case VK_RETURN: approve(); return 1;
    case VK_SPACE: { int nx = cur >= 0 ? next_pending(cur, -1) : -1; if (nx >= 0) show_pair(nx, 1); return 1; }
    case VK_BACK: prev(); return 1;
    case 'R': if (cur >= 0 && !pair_frozen(cur)) { memset(PR[cur].adj, 0, sizeof PR[cur].adj); show_values(); InvalidateRect(g_gl, NULL, FALSE); } return 1;
    case VK_ADD: case VK_OEM_PLUS: case VK_PRIOR: change(0, st[0]); return 1;
    case VK_SUBTRACT: case VK_OEM_MINUS: case VK_NEXT: change(0, -st[0]); return 1;
    case 'W': change(1, st[1]); return 1;
    case 'S': change(1, -st[1]); return 1;
    case VK_UP: change(2, st[2]); return 1;
    case VK_DOWN: change(2, -st[2]); return 1;
    case 'A': change(3, st[3]); return 1;
    case 'D': change(3, -st[3]); return 1;
    case 'T': change(4, st[4]); return 1;
    case 'G': change(4, -st[4]); return 1;
    case 'Q': change(5, st[5]); return 1;
    case 'E': change(5, -st[5]); return 1;
    case 'Z': change(6, st[6]); return 1;
    case 'C': change(6, -st[6]); return 1;
    case VK_LEFT: view_yaw -= 15; InvalidateRect(g_gl, NULL, FALSE); return 1;
    case VK_RIGHT: view_yaw += 15; InvalidateRect(g_gl, NULL, FALSE); return 1;
    case VK_HOME: view_yaw = 0; zoom = 1; InvalidateRect(g_gl, NULL, FALSE); return 1;
    case 'H': hide_arms = !hide_arms; Button_SetCheck(g_chkArms, hide_arms ? BST_CHECKED : BST_UNCHECKED); InvalidateRect(g_gl, NULL, FALSE); return 1;
    case 'F': whole = !whole; Button_SetCheck(g_chkWhole, whole ? BST_CHECKED : BST_UNCHECKED); InvalidateRect(g_gl, NULL, FALSE); return 1;
    }
    return 0;
}

static HWND mk(const wchar_t *cls, const wchar_t *text, DWORD style, int x, int y, int w, int h, HWND parent, int id)
{
    HWND c = CreateWindowExW(0, cls, text, WS_CHILD | WS_VISIBLE | style, x, y, w, h, parent, (HMENU)(INT_PTR)id, GetModuleHandleW(NULL), NULL);
    SendMessageW(c, WM_SETFONT, (WPARAM)g_font, TRUE);
    return c;
}

static int drag, drag_x;

static LRESULT CALLBACK gl_proc(HWND h, UINT msg, WPARAM w, LPARAM l)
{
    switch (msg) {
    case WM_PAINT: { PAINTSTRUCT ps; BeginPaint(h, &ps); render(); SwapBuffers(g_dc); EndPaint(h, &ps); return 0; }
    case WM_ERASEBKGND: return 1;
    case WM_LBUTTONDOWN: SetFocus(g_main); SetCapture(h); drag = 1; drag_x = GET_X_LPARAM(l); return 0;
    case WM_MOUSEMOVE: if (drag) { view_yaw += (GET_X_LPARAM(l) - drag_x) * 0.6; drag_x = GET_X_LPARAM(l); InvalidateRect(h, NULL, FALSE); } return 0;
    case WM_LBUTTONUP: drag = 0; ReleaseCapture(); return 0;
    case WM_RBUTTONDOWN: SetFocus(g_main); view_yaw = 0; zoom = 1; InvalidateRect(h, NULL, FALSE); return 0;
    }
    return DefWindowProcW(h, msg, w, l);
}

static int carry_msg(HWND h, UINT msg, WPARAM w, LPARAM l);
static LRESULT CALLBACK main_proc(HWND h, UINT msg, WPARAM w, LPARAM l)
{
    if (carry_ui && carry_msg(h, msg, w, l)) return 0;
    switch (msg) {
    case WM_COMMAND: {
        int id = LOWORD(w), code = HIWORD(w);
        if (id == ID_GEAR && code == CBN_SELCHANGE) {
            int g = (int)SendMessageW(g_cbGear, CB_GETCURSEL, 0, 0);
            int p = -1;
            for (int k = 0; k < nPR && p < 0; k++) if (PR[k].gear == g && (show_approved || !pair_done(k))) p = k;
            for (int k = 0; k < nPR && p < 0; k++) if (PR[k].gear == g) p = k;
            if (p >= 0) show_pair(p, 1);
            SetFocus(h);
        } else if (id == ID_PAIR && code == CBN_SELCHANGE) {
            int i = (int)SendMessageW(g_cbPair, CB_GETCURSEL, 0, 0);
            if (i >= 0) show_pair((int)SendMessageW(g_cbPair, CB_GETITEMDATA, i, 0), 1);
            SetFocus(h);
        } else if (id == ID_SHOW) { show_approved = Button_GetCheck(g_chk) == BST_CHECKED; SetFocus(h); }
        else if (id == ID_CLAUDE) {
            review_claude = Button_GetCheck(g_chkClaude) == BST_CHECKED;
            if (review_claude) {  /* straight to the first of Claude's approvals */
                int p = -1;
                for (int k = 0; k < nPR && p < 0; k++) if (pair_claude(k)) p = k;
                if (p >= 0) show_pair(p, 1);
            }
            SetFocus(h);
        }
        else if (id == ID_RESET) { if (cur >= 0) { memset(PR[cur].adj, 0, sizeof PR[cur].adj); show_values(); InvalidateRect(g_gl, NULL, FALSE); } SetFocus(h); }
        else if (id == ID_PREV) { prev(); SetFocus(h); }
        else if (id == ID_SKIP) { int nx = cur >= 0 ? next_pending(cur, -1) : -1; if (nx >= 0) show_pair(nx, 1); SetFocus(h); }
        else if (id == ID_APPROVE) { approve(); SetFocus(h); }
        else if (id == ID_UNLOCK) { unlock(); SetFocus(h); }
        else if (id == ID_ARMS) { hide_arms = Button_GetCheck(g_chkArms) == BST_CHECKED; InvalidateRect(g_gl, NULL, FALSE); SetFocus(h); }
        else if (id == ID_WHOLE) { whole = Button_GetCheck(g_chkWhole) == BST_CHECKED; InvalidateRect(g_gl, NULL, FALSE); SetFocus(h); }
        else if (id >= ID_MINUS && id < ID_MINUS + NPAR) { change(id - ID_MINUS, -(GetKeyState(VK_SHIFT) < 0 ? FINE : STEP)[id - ID_MINUS]); SetFocus(h); }
        else if (id >= ID_PLUS && id < ID_PLUS + NPAR) { change(id - ID_PLUS, (GetKeyState(VK_SHIFT) < 0 ? FINE : STEP)[id - ID_PLUS]); SetFocus(h); }
        else if (id >= ID_EDIT && id < ID_EDIT + NPAR && code == EN_KILLFOCUS) commit_edit(id - ID_EDIT);
        return 0;
    }
    case WM_MOUSEWHEEL: {
        int d = GET_WHEEL_DELTA_WPARAM(w) > 0 ? 1 : -1;
        if (GET_KEYSTATE_WPARAM(w) & MK_CONTROL) { zoom *= d > 0 ? 0.9 : 1.1; InvalidateRect(g_gl, NULL, FALSE); }
        else change(0, d * ((GET_KEYSTATE_WPARAM(w) & MK_SHIFT) ? FINE[0] : STEP[0]));
        return 0;
    }
    case WM_TIMER: {  /* the next pair goes to the GPU while you look at this one */
        poll_apply();
        int nx = cur >= 0 ? next_pending(cur, -1) : -1;
        if (nx >= 0) { upload_mesh(pm_mesh(F[PR[nx].f[0]].pm)); upload_mesh(gear_mesh(PR[nx].gear)); make_frame(nx); }
        return 0;
    }
    case WM_CLOSE:
        if (g_apply) WaitForSingleObject(g_apply, 8000);
        DestroyWindow(h);
        return 0;
    case WM_DESTROY: PostQuitMessage(0); return 0;
    }
    return DefWindowProcW(h, msg, w, l);
}

static void build_ui(HINSTANCE hi)
{
    g_font = CreateFontW(-15, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
    g_bold = CreateFontW(-18, 0, 0, 0, FW_BOLD, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
    WNDCLASSW wc = { 0 };
    wc.lpfnWndProc = main_proc; wc.hInstance = hi; wc.lpszClassName = L"AdvInvFitEditor";
    wc.hCursor = LoadCursor(NULL, IDC_ARROW); wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    wc.hIcon = LoadIcon(NULL, IDI_APPLICATION);
    RegisterClassW(&wc);
    WNDCLASSW gc = { 0 };
    gc.style = CS_OWNDC; gc.lpfnWndProc = gl_proc; gc.hInstance = hi; gc.lpszClassName = L"AdvInvFitEditorGL";
    gc.hCursor = LoadCursor(NULL, IDC_SIZEWE);
    RegisterClassW(&gc);

    int W = 4 * CELL + 24; if (W < 1390) W = 1390;
    int x0 = 12, y = 10;
    GLH = CELL;
    RECT r = { 0, 0, W, 0 };
    int H = 10 + 34 + 30 + GLH + 24 + 40 + 40 + 44 + 46 + 26 + 30 + 10;
    r.bottom = H;
    AdjustWindowRect(&r, WS_OVERLAPPEDWINDOW, FALSE);
    g_main = CreateWindowW(L"AdvInvFitEditor", L"Advanced Inventory System: fit editor", WS_OVERLAPPEDWINDOW & ~(WS_THICKFRAME | WS_MAXIMIZEBOX),
                           CW_USEDEFAULT, CW_USEDEFAULT, r.right - r.left, r.bottom - r.top, NULL, NULL, hi, NULL);

    mk(L"STATIC", L"Item:", 0, x0, y + 4, 40, 22, g_main, 0);
    g_cbGear = mk(L"COMBOBOX", L"", CBS_DROPDOWNLIST | WS_VSCROLL | WS_TABSTOP, x0 + 42, y, 430, 500, g_main, ID_GEAR);
    mk(L"STATIC", L"Playermodel:", 0, x0 + 490, y + 4, 90, 22, g_main, 0);
    g_cbPair = mk(L"COMBOBOX", L"", CBS_DROPDOWNLIST | WS_VSCROLL | WS_TABSTOP, x0 + 582, y, 330, 500, g_main, ID_PAIR);
    g_chk = mk(L"BUTTON", L"Show approved pairs too", BS_AUTOCHECKBOX, x0 + 930, y + 2, 200, 24, g_main, ID_SHOW);
    g_chkClaude = mk(L"BUTTON", L"Review Claude's approvals", BS_AUTOCHECKBOX, x0 + 1140, y + 2, 230, 24, g_main, ID_CLAUDE);
    y += 34;
    g_title = mk(L"STATIC", L"", SS_LEFT | SS_NOPREFIX, x0, y, W - 24, 26, g_main, 0);
    SendMessageW(g_title, WM_SETFONT, (WPARAM)g_bold, TRUE);
    y += 30;
    g_gl = CreateWindowExW(0, L"AdvInvFitEditorGL", L"", WS_CHILD | WS_VISIBLE, x0, y, 4 * CELL, GLH, g_main, NULL, hi, NULL);
    y += GLH;
    for (int v = 0; v < 4; v++) g_lbl[v] = mk(L"STATIC", VIEWNAME[v], SS_CENTER, x0 + v * CELL, y + 2, CELL, 20, g_main, 0);
    y += 24;
    /* the adjustments: two rows */
    for (int k = 0; k < NPAR; k++) {
        int col = k < 3 ? k : k - 3, row = k < 3 ? 0 : 1;
        int x = x0 + col * 340, yy = y + row * 40;
        g_pl[k] = mk(L"STATIC", PNAME[k], SS_RIGHT, x, yy + 5, 120, 22, g_main, 0);
        g_bm[k] = mk(L"BUTTON", L"\x2212", BS_PUSHBUTTON, x + 128, yy, 36, 30, g_main, ID_MINUS + k);
        g_ed[k] = mk(L"EDIT", L"0", WS_BORDER | ES_CENTER | ES_AUTOHSCROLL, x + 168, yy + 2, 80, 26, g_main, ID_EDIT + k);
        g_bp[k] = mk(L"BUTTON", L"+", BS_PUSHBUTTON, x + 252, yy, 36, 30, g_main, ID_PLUS + k);
    }
    g_abs = mk(L"STATIC", L"", 0, x0 + 3 * 340 + 20, y + 5, 160, 22, g_main, 0);
    y += 84;
    g_bReset = mk(L"BUTTON", L"Reset  (R)", BS_PUSHBUTTON, x0, y, 120, 34, g_main, ID_RESET);
    g_bPrev = mk(L"BUTTON", L"\x25C0  Previous  (Backspace)", BS_PUSHBUTTON, x0 + 130, y, 200, 34, g_main, ID_PREV);
    g_bSkip = mk(L"BUTTON", L"Skip  \x25B6  (Space)", BS_PUSHBUTTON, x0 + 340, y, 170, 34, g_main, ID_SKIP);
    g_bApprove = mk(L"BUTTON", L"\x2714  Approve: final  (Enter)", BS_PUSHBUTTON, x0 + 530, y, 250, 34, g_main, ID_APPROVE);
    SendMessageW(g_bApprove, WM_SETFONT, (WPARAM)g_bold, TRUE);
    g_bUnlock = mk(L"BUTTON", L"Unlock", BS_PUSHBUTTON, x0 + 800, y, 100, 34, g_main, ID_UNLOCK);
    g_chkArms = mk(L"BUTTON", L"Hide the arms  (H)", BS_AUTOCHECKBOX, x0 + 925, y + 5, 160, 24, g_main, ID_ARMS);
    g_chkWhole = mk(L"BUTTON", L"Whole model  (F)", BS_AUTOCHECKBOX, x0 + 1090, y + 5, 150, 24, g_main, ID_WHOLE);
    y += 44;
    g_also = mk(L"STATIC", L"", SS_LEFT | SS_NOPREFIX, x0, y, W - 24, 42, g_main, 0);
    y += 46;
    g_status = mk(L"STATIC", L"", SS_LEFT | SS_NOPREFIX, x0, y, W - 24, 22, g_main, 0);
    y += 26;
    g_help = mk(L"STATIC",
                L"Keys: +/- or wheel size,  W/S forward/back,  \x2191/\x2193 up/down,  A/D left/right,  T/G tilt,  Q/E turn,  Z/C spin,  "
                L"Shift = small steps.  H hide the arms, F whole model.  Drag a view or \x2190/\x2192 to turn, right click or Home to reset, Ctrl+wheel to zoom.",
                SS_LEFT | SS_NOPREFIX, x0, y, W - 24, 22, g_main, 0);
    gl_init();
}

/* the OpenGL context of the views (g_gl) */
static void gl_init(void)
{
    g_dc = GetDC(g_gl);
    PIXELFORMATDESCRIPTOR pfd;
    memset(&pfd, 0, sizeof pfd);
    pfd.nSize = sizeof pfd; pfd.nVersion = 1; pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA; pfd.cColorBits = 32; pfd.cDepthBits = 24; pfd.iLayerType = PFD_MAIN_PLANE;
    int pf = ChoosePixelFormat(g_dc, &pfd);
    if (!pf || !SetPixelFormat(g_dc, pf, &pfd)) die(L"No OpenGL pixel format");
    g_rc = wglCreateContext(g_dc);
    if (!g_rc || !wglMakeCurrent(g_dc, g_rc)) die(L"No OpenGL context");
    gl_procs();
    SetTimer(g_main, 1, 150, NULL);
}

/* ------------------------------------------------------------------ the carry editor (--carry) */
/*
 * A window made for the long guns' carry positions: the weapons in a list, the carry modes as buttons,
 * the playermodel to look at, sliders for the place and the rotations, the weapon drawn on the whole
 * body. Save applies the change to every playermodel (the same move from where each one has it) or to
 * the one shown, approves it (fit_locks.txt) and writes it into the game's carry data at once.
 */
#define CMODES 3
static const char *CMODE[CMODES] = { "sling_up", "sling_down", "front_hang" };
static const wchar_t *CMODENAME[CMODES] = { L"Sling arms", L"Back carry", L"Front carry" };
typedef struct { char cls[96]; wchar_t name[120]; int gear[CMODES]; } CWeapon;
static CWeapon *CW; static int nCW, cw_sel = -1;
static char cw_pm[260] = "";   /* the playermodel looked at, kept when the weapon or the mode changes */
static HWND g_lbW, g_rbM[CMODES], g_cbB, g_tb[NPAR], g_ev[NPAR], g_chkAll, g_chkWB, g_cwTitle, g_cwStatus, g_vl[2];
enum { ID_CW_LIST = 400, ID_CW_MODE = 410, ID_CW_BODY = 420, ID_CW_SAVE, ID_CW_RESET, ID_CW_ALL, ID_CW_WHOLE,
       ID_CW_EDIT = 430, ID_CW_TB = 440 };
static const double TBSCALE[NPAR] = { 1, 20, 20, 20, 4, 4, 4 };   /* slider steps per unit: 0.05 unit, 0.25 degree */
static const wchar_t *CWPNAME[NPAR] = { L"", L"Forward / back", L"Up / down", L"Left / right",
                                        L"Lean (front up)", L"Turn sideways", L"Spin on itself" };

static void carry_collect(void)
{
    CW = xmalloc(sizeof(CWeapon) * (nG + 1));
    for (int g = 0; g < nG; g++) {
        if (strncmp(G[g].cls, "carry:", 6)) continue;
        const char *m = strchr(G[g].cls + 6, ':');
        if (!m) continue;
        char wcls[96];
        size_t n = (size_t)(m - (G[g].cls + 6));
        if (n >= sizeof wcls) n = sizeof wcls - 1;
        memcpy(wcls, G[g].cls + 6, n); wcls[n] = 0;
        int mode = -1;
        for (int k = 0; k < CMODES; k++) if (!strcmp(m + 1, CMODE[k])) mode = k;
        if (mode < 0) continue;
        int w = -1;
        for (int k = 0; k < nCW; k++) if (!strcmp(CW[k].cls, wcls)) w = k;
        if (w < 0) {
            w = nCW++;
            snprintf(CW[w].cls, sizeof CW[w].cls, "%s", wcls);
            for (int k = 0; k < CMODES; k++) CW[w].gear[k] = -1;
            wcsncpy(CW[w].name, G[g].name, 119); CW[w].name[119] = 0;   /* "AK-74 - sling arms": the weapon's name */
            wchar_t *d = wcsstr(CW[w].name, L" - ");
            if (d) *d = 0;
        }
        CW[w].gear[mode] = g;
    }
}

/* the pair of gear g that shows playermodel pm (else the reference body, else the first) */
static int carry_pair_for(int g, const char *pm)
{
    int ref = -1, first = -1, mi = pm[0] ? find_pm(pm) : -1, ri = find_pm(REF);
    for (int p = 0; p < nPR; p++) {
        if (PR[p].gear != g) continue;
        if (first < 0) first = p;
        for (int k = 0; k < PR[p].n; k++) {
            int x = F[PR[p].f[k]].pm;
            if (x == mi) return p;
            if (x == ri && ref < 0) ref = p;
        }
    }
    return ref >= 0 ? ref : first;
}

static int pair_any_locked(int p) { for (int k = 0; k < PR[p].n; k++) if (F[PR[p].f[k]].locked) return 1; return 0; }

static void carry_values(void)
{
    if (cur < 0) return;
    wchar_t b[64];
    for (int k = 1; k < NPAR; k++) {
        SendMessageW(g_tb[k], TBM_SETPOS, TRUE, (LPARAM)lround(PR[cur].adj[k] * TBSCALE[k]));
        swprintf(b, 64, k < 4 ? L"%+.2f" : L"%+.2f\x00B0", PR[cur].adj[k]);
        SetWindowTextW(g_ev[k], b);
    }
}

static void carry_status(void)
{
    if (cur < 0 || !g_cwStatus) return;
    int g = PR[cur].gear, bodies = 0, saved = 0;
    for (int p = 0; p < nPR; p++)
        if (PR[p].gear == g)
            for (int k = 0; k < PR[p].n; k++) { bodies++; saved += F[PR[p].f[k]].locked; }
    wchar_t b[700];
    swprintf(b, 700, L"%ls\nSaved by you on %d of %d playermodels.\n%ls",
             adj_zero(PR[cur].adj) ? L"No change to save." : L"Changed: press Save to keep it.", saved, bodies, g_note);
    SetWindowTextW(g_cwStatus, b);
}

static void carry_body_combo(int g)
{
    SendMessageW(g_cbB, CB_RESETCONTENT, 0, 0);
    wchar_t b[400], t[60];
    for (int p = 0; p < nPR; p++) {
        if (PR[p].gear != g) continue;
        if (PR[p].n > 1) swprintf(t, 60, L"  (and %d like it)", PR[p].n - 1); else t[0] = 0;
        swprintf(b, 400, L"%ls%ls%ls", pair_done(p) ? L"\x2713 " : L"", P[F[PR[p].f[0]].pm].shortn, t);
        int i = (int)SendMessageW(g_cbB, CB_ADDSTRING, 0, (LPARAM)b);
        SendMessageW(g_cbB, CB_SETITEMDATA, i, p);
        if (p == cur) SendMessageW(g_cbB, CB_SETCURSEL, i, 0);
    }
}

static void carry_show(void)
{
    if (cw_sel < 0 || cw_sel >= nCW) return;
    CWeapon *w = &CW[cw_sel];
    if (w->gear[cw_mode] < 0)
        for (int k = 0; k < CMODES; k++) if (w->gear[k] >= 0) { cw_mode = k; break; }
    for (int k = 0; k < CMODES; k++) {
        EnableWindow(g_rbM[k], w->gear[k] >= 0);
        SendMessageW(g_rbM[k], BM_SETCHECK, k == cw_mode ? BST_CHECKED : BST_UNCHECKED, 0);
    }
    int g = w->gear[cw_mode];
    cur = carry_pair_for(g, cw_pm);
    view_yaw = 0; zoom = 1;
    wchar_t t[400];
    swprintf(t, 400, L"%ls  \x2014  %ls", w->name, CMODENAME[cw_mode]);
    SetWindowTextW(g_cwTitle, t);
    SetWindowTextW(g_vl[0], cw_mode == CW_FRONT ? L"Front" : L"Back");
    SetWindowTextW(g_vl[1], L"Side");
    carry_body_combo(g);
    carry_values();
    carry_status();
    InvalidateRect(g_gl, NULL, FALSE);
}

static void carry_save(void)
{
    if (cur < 0) return;
    int g = PR[cur].gear, every = Button_GetCheck(g_chkAll) == BST_CHECKED, n = 0;
    double a[NPAR];
    memcpy(a, PR[cur].adj, sizeof a);
    a[0] = 0;
    for (int p = 0; p < nPR; p++) {
        if (PR[p].gear != g || (!every && p != cur)) continue;
        if (pair_any_locked(p)) remove_locks(p, 0);   /* saved before: saved again from where it is now */
        memcpy(PR[p].adj, a, sizeof a);
        if (approve_pair(p, "user") < 0) { MessageBoxW(g_main, L"Can't write fit_locks.txt", L"Carry editor", MB_ICONERROR); return; }
        n += PR[p].n;
    }
    swprintf(g_note, 300, L"Saved on %d playermodel%ls.", n, n > 1 ? L"s" : L"");
    run_apply();
    carry_body_combo(g);
    carry_values();
    carry_status();
    InvalidateRect(g_gl, NULL, FALSE);
}

/* leaving a weapon or mode with a change not saved: save it, drop it, or stay (0) */
static int carry_leave(void)
{
    if (cur < 0 || adj_zero(PR[cur].adj)) return 1;
    wchar_t msg[400];
    swprintf(msg, 400, L"%ls (%ls) was moved but not saved. Save it?", CW[cw_sel].name, CMODENAME[cw_mode]);
    int r = MessageBoxW(g_main, msg, L"Carry editor", MB_YESNOCANCEL | MB_ICONQUESTION);
    if (r == IDCANCEL) return 0;
    if (r == IDYES) carry_save(); else memset(PR[cur].adj, 0, sizeof PR[cur].adj);
    return 1;
}

static void carry_set(int k, double v)
{
    if (cur < 0) return;
    PR[cur].adj[k] = fmin(LIM[k][1], fmax(LIM[k][0], v));
    carry_values();
    carry_status();
    InvalidateRect(g_gl, NULL, FALSE);
}

/* WM_COMMAND, WM_HSCROLL and WM_MOUSEWHEEL of the carry editor; 1 if handled */
static int carry_msg(HWND h, UINT msg, WPARAM w, LPARAM l)
{
    if (msg == WM_HSCROLL) {
        for (int k = 1; k < NPAR; k++)
            if ((HWND)l == g_tb[k] && cur >= 0) {
                PR[cur].adj[k] = (double)SendMessageW(g_tb[k], TBM_GETPOS, 0, 0) / TBSCALE[k];
                wchar_t b[64]; swprintf(b, 64, k < 4 ? L"%+.2f" : L"%+.2f\x00B0", PR[cur].adj[k]);
                SetWindowTextW(g_ev[k], b);
                carry_status();
                InvalidateRect(g_gl, NULL, FALSE);
            }
        return 1;
    }
    if (msg == WM_MOUSEWHEEL) {
        zoom *= GET_WHEEL_DELTA_WPARAM(w) > 0 ? 0.9 : 1.1;
        InvalidateRect(g_gl, NULL, FALSE);
        return 1;
    }
    if (msg != WM_COMMAND) return 0;
    int id = LOWORD(w), code = HIWORD(w);
    if (id == ID_CW_LIST && code == LBN_SELCHANGE) {
        int i = (int)SendMessageW(g_lbW, LB_GETCURSEL, 0, 0);
        if (i != cw_sel && carry_leave()) { cw_sel = i; carry_show(); }
        else SendMessageW(g_lbW, LB_SETCURSEL, cw_sel, 0);
    } else if (id >= ID_CW_MODE && id < ID_CW_MODE + CMODES && code == BN_CLICKED) {
        int k = id - ID_CW_MODE;
        if (k != cw_mode && carry_leave()) cw_mode = k;
        carry_show();
    } else if (id == ID_CW_BODY && code == CBN_SELCHANGE) {
        int i = (int)SendMessageW(g_cbB, CB_GETCURSEL, 0, 0);
        int p = i >= 0 ? (int)SendMessageW(g_cbB, CB_GETITEMDATA, i, 0) : -1;
        if (p >= 0 && cur >= 0 && p != cur) {   /* the change not saved yet goes along: try it on that body */
            memcpy(PR[p].adj, PR[cur].adj, sizeof PR[p].adj);
            memset(PR[cur].adj, 0, sizeof PR[cur].adj);
            cur = p;
            snprintf(cw_pm, sizeof cw_pm, "%s", P[F[PR[p].f[0]].pm].pm);
            view_yaw = 0; zoom = 1;
            carry_values(); carry_status(); InvalidateRect(g_gl, NULL, FALSE);
        }
        SetFocus(h);
    } else if (id == ID_CW_SAVE) { carry_save(); SetFocus(h); }
    else if (id == ID_CW_RESET) { if (cur >= 0) { memset(PR[cur].adj, 0, sizeof PR[cur].adj); carry_values(); carry_status(); InvalidateRect(g_gl, NULL, FALSE); } SetFocus(h); }
    else if (id == ID_CW_WHOLE) { whole = Button_GetCheck(g_chkWB) == BST_CHECKED; InvalidateRect(g_gl, NULL, FALSE); SetFocus(h); }
    else if (id >= ID_CW_EDIT && id < ID_CW_EDIT + NPAR && code == EN_KILLFOCUS) {
        int k = id - ID_CW_EDIT;
        wchar_t b[64]; GetWindowTextW(g_ev[k], b, 64);
        wchar_t *e; double v = wcstod(b, &e);
        if (e != b) carry_set(k, v); else carry_values();
    }
    return 1;
}

/* keys of the carry editor: Enter in a value box takes the value, Ctrl+S saves */
static int carry_key(MSG *m)
{
    if (m->message != WM_KEYDOWN) return 0;
    wchar_t cls[32] = L"";
    HWND f = GetFocus();
    if (f) GetClassNameW(f, cls, 32);
    if (!_wcsicmp(cls, L"Edit") && (m->wParam == VK_RETURN || m->wParam == VK_TAB)) { SetFocus(g_main); return 1; }
    if (m->wParam == 'S' && GetKeyState(VK_CONTROL) < 0) { carry_save(); return 1; }
    return 0;
}

static void build_carry_ui(HINSTANCE hi)
{
    INITCOMMONCONTROLSEX icc = { sizeof icc, ICC_BAR_CLASSES };
    InitCommonControlsEx(&icc);
    g_font = CreateFontW(-15, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
    g_bold = CreateFontW(-19, 0, 0, 0, FW_BOLD, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
    WNDCLASSW wc = { 0 };
    wc.lpfnWndProc = main_proc; wc.hInstance = hi; wc.lpszClassName = L"AdvInvFitEditor";
    wc.hCursor = LoadCursor(NULL, IDC_ARROW); wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    wc.hIcon = LoadIcon(NULL, IDI_APPLICATION);
    RegisterClassW(&wc);
    WNDCLASSW gc = { 0 };
    gc.style = CS_OWNDC; gc.lpfnWndProc = gl_proc; gc.hInstance = hi; gc.lpszClassName = L"AdvInvFitEditorGL";
    gc.hCursor = LoadCursor(NULL, IDC_SIZEWE);
    RegisterClassW(&gc);

    int VW = 380, VH = 560;                      /* each of the two views */
    int xl = 12, wl = 250;                       /* left: weapon, mode, body */
    int xg = xl + wl + 14;                       /* the views */
    int xr = xg + 2 * VW + 14, wr = 330;         /* right: the moves, Save */
    int W = xr + wr + 12, H = 12 + 34 + VH + 24 + 52;
    RECT r = { 0, 0, W, H };
    AdjustWindowRect(&r, WS_OVERLAPPEDWINDOW, FALSE);
    g_main = CreateWindowW(L"AdvInvFitEditor", L"Advanced Inventory System: weapon carry positions",
                           WS_OVERLAPPEDWINDOW & ~(WS_THICKFRAME | WS_MAXIMIZEBOX),
                           CW_USEDEFAULT, CW_USEDEFAULT, r.right - r.left, r.bottom - r.top, NULL, NULL, hi, NULL);

    /* left */
    int y = 12;
    mk(L"STATIC", L"Weapon", 0, xl, y, wl, 22, g_main, 0);
    g_lbW = mk(L"LISTBOX", L"", WS_BORDER | WS_VSCROLL | LBS_NOTIFY | LBS_NOINTEGRALHEIGHT, xl, y + 24, wl, 300, g_main, ID_CW_LIST);
    y += 24 + 300 + 12;
    mk(L"STATIC", L"Carry mode", 0, xl, y, wl, 22, g_main, 0);
    y += 24;
    for (int k = 0; k < CMODES; k++) {
        g_rbM[k] = mk(L"BUTTON", CMODENAME[k], BS_AUTORADIOBUTTON | BS_PUSHLIKE | (k ? 0 : WS_GROUP), xl, y, wl, 32, g_main, ID_CW_MODE + k);
        y += 36;
    }
    y += 6;
    mk(L"STATIC", L"Playermodel shown", 0, xl, y, wl, 22, g_main, 0);
    g_cbB = mk(L"COMBOBOX", L"", CBS_DROPDOWNLIST | WS_VSCROLL | WS_TABSTOP, xl, y + 24, wl, 500, g_main, ID_CW_BODY);
    y += 24 + 34;
    g_chkWB = mk(L"BUTTON", L"Whole body", BS_AUTOCHECKBOX, xl, y, wl, 24, g_main, ID_CW_WHOLE);

    /* the views */
    g_cwTitle = mk(L"STATIC", L"", SS_LEFT | SS_NOPREFIX, xg, 12, 2 * VW, 30, g_main, 0);
    SendMessageW(g_cwTitle, WM_SETFONT, (WPARAM)g_bold, TRUE);
    g_gl = CreateWindowExW(0, L"AdvInvFitEditorGL", L"", WS_CHILD | WS_VISIBLE, xg, 46, 2 * VW, VH, g_main, NULL, hi, NULL);
    for (int v = 0; v < 2; v++) g_vl[v] = mk(L"STATIC", L"", SS_CENTER, xg + v * VW, 46 + VH + 2, VW, 20, g_main, 0);
    GLH = VH;

    /* right: the moves */
    y = 46;
    for (int k = 1; k < NPAR; k++) {
        mk(L"STATIC", CWPNAME[k], 0, xr, y + 3, 200, 22, g_main, 0);
        g_ev[k] = mk(L"EDIT", L"0", WS_BORDER | ES_CENTER | ES_AUTOHSCROLL, xr + wr - 90, y, 90, 26, g_main, ID_CW_EDIT + k);
        g_tb[k] = mk(TRACKBAR_CLASSW, L"", TBS_HORZ | TBS_NOTICKS | WS_TABSTOP, xr - 6, y + 28, wr + 12, 30, g_main, ID_CW_TB + k);
        SendMessageW(g_tb[k], TBM_SETRANGEMIN, FALSE, (LPARAM)lround(LIM[k][0] * TBSCALE[k]));
        SendMessageW(g_tb[k], TBM_SETRANGEMAX, TRUE, (LPARAM)lround(LIM[k][1] * TBSCALE[k]));
        SendMessageW(g_tb[k], TBM_SETLINESIZE, 0, 1);
        SendMessageW(g_tb[k], TBM_SETPAGESIZE, 0, (LPARAM)lround(TBSCALE[k]));
        y += 66;
    }
    y += 4;
    g_chkAll = mk(L"BUTTON", L"Apply to every playermodel", BS_AUTOCHECKBOX, xr, y, wr, 24, g_main, ID_CW_ALL);
    Button_SetCheck(g_chkAll, BST_CHECKED);
    y += 32;
    mk(L"BUTTON", L"Reset", BS_PUSHBUTTON, xr, y, 110, 40, g_main, ID_CW_RESET);
    HWND save = mk(L"BUTTON", L"\x2714  Save", BS_PUSHBUTTON, xr + 120, y, wr - 120, 40, g_main, ID_CW_SAVE);
    SendMessageW(save, WM_SETFONT, (WPARAM)g_bold, TRUE);
    y += 50;
    g_cwStatus = mk(L"STATIC", L"", SS_LEFT | SS_NOPREFIX, xr, y, wr, 70, g_main, 0);
    mk(L"STATIC",
       L"Drag a view to turn around the body, mouse wheel to zoom. Arrow keys move a selected slider by the smallest "
       L"step. Save applies the move to every playermodel (each from where it has the weapon) or only to the one shown.",
       SS_LEFT | SS_NOPREFIX, xl, 46 + VH + 26, W - 24, 44, g_main, 0);
    gl_init();
}

/* ------------------------------------------------------------------ checks and captures */

/* ------------------------------------------------------------------ batch: contact sheets, approving an item */

/* adjustments: "item class<TAB>playermodel or *<TAB>size% forward up left tilt" (or "skip": left to approve);
   the "*" line of an item first, then the playermodels' own lines */
static void load_adjust(const wchar_t *path, int g)
{
    char *t = read_file(path, NULL);
    if (!t) die(L"Can't read %ls", path);
    for (int pass = 0; pass < 2; pass++) {
        char *copy = _strdup(t);
        for (char *line = strtok(copy, "\r\n"); line; line = strtok(NULL, "\r\n")) {
            if (line[0] == '#') continue;
            char *f[4];
            if (split(line, f, 4) < 3 || find_gear(f[0]) != g) continue;
            int star = !strcmp(f[1], "*");
            if (star != (pass == 0)) continue;
            int m = star ? -1 : find_pm(f[1]);
            if (!star && m < 0) { if (out) fprintf(out, "adjust: unknown playermodel %s\n", f[1]); continue; }
            double a[NPAR] = { 0 };
            int skip = !strncmp(f[2], "skip", 4);
            if (!skip) sscanf(f[2], "%lf %lf %lf %lf %lf %lf %lf", &a[0], &a[1], &a[2], &a[3], &a[4], &a[5], &a[6]);
            for (int p = 0; p < nPR; p++) {
                if (PR[p].gear != g) continue;
                int hit = star;
                for (int k = 0; k < PR[p].n && !hit; k++) hit = F[PR[p].f[k]].pm == m;
                if (!hit) continue;
                PR[p].skip = skip;
                if (!skip) memcpy(PR[p].adj, a, sizeof a);
            }
        }
        free(copy);
    }
    free(t);
}

static GLuint make_fbo(int w, int h)
{
    if (!(pGenFramebuffers && pBindFramebuffer && pGenRenderbuffers && pBindRenderbuffer && pRenderbufferStorage &&
          pFramebufferRenderbuffer && pCheckFramebufferStatus)) return 0;
    GLuint fb, rb[2];
    pGenFramebuffers(1, &fb); pBindFramebuffer(GL_FRAMEBUFFER, fb);
    pGenRenderbuffers(2, rb);
    pBindRenderbuffer(GL_RENDERBUFFER, rb[0]); pRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, w, h);
    pFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rb[0]);
    pBindRenderbuffer(GL_RENDERBUFFER, rb[1]); pRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, w, h);
    pFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, rb[1]);
    return pCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE ? fb : 0;
}

static void write_bmp(const wchar_t *path, int W, int H, const unsigned char *rgb_bottom_up)
{
    int stride = (W * 3 + 3) & ~3;
    BITMAPFILEHEADER fh; BITMAPINFOHEADER ih;
    memset(&fh, 0, sizeof fh); memset(&ih, 0, sizeof ih);
    fh.bfType = 0x4D42; fh.bfOffBits = sizeof fh + sizeof ih; fh.bfSize = fh.bfOffBits + (DWORD)stride * H;
    ih.biSize = sizeof ih; ih.biWidth = W; ih.biHeight = H; ih.biPlanes = 1; ih.biBitCount = 24; ih.biCompression = BI_RGB;
    FILE *f = _wfopen(path, L"wb");
    if (!f) die(L"Can't write %ls", path);
    fwrite(&fh, sizeof fh, 1, f); fwrite(&ih, sizeof ih, 1, f);
    unsigned char *row = xmalloc(stride);
    for (int y = 0; y < H; y++) {   /* RGB -> BGR */
        const unsigned char *s = rgb_bottom_up + (size_t)y * W * 3;
        for (int x = 0; x < W; x++) { row[3 * x] = s[3 * x + 2]; row[3 * x + 1] = s[3 * x + 1]; row[3 * x + 2] = s[3 * x]; }
        fwrite(row, 1, stride, f);
    }
    free(row); fclose(f);
}

/* every pair of an item (which: 0 all, 1 not approved by the user, 2 not approved at all), from..from+count,
   drawn in one off-screen picture on the GPU, cols cells a row, each cell nv views of S x S pixels */
static int sheet_mode(const char *cls, const wchar_t *bmp, const wchar_t *idx, int cols, int S, const int *views, int nv,
                      int which, int from, int count)
{
    int g = find_gear(cls);
    if (g < 0) die(L"Unknown item %hs", cls);
    int *list = xmalloc(sizeof(int) * (nPR + 1)), n = 0, seen = 0;
    for (int p = 0; p < nPR; p++) {
        if (PR[p].gear != g || (which == 1 && pair_frozen(p)) || (which == 2 && pair_done(p))) continue;
        if (seen++ < from || (count > 0 && n >= count)) continue;
        list[n++] = p;
    }
    FILE *fi = _wfopen(idx, L"w");
    if (!fi) die(L"Can't write %ls", idx);
    if (!n) { fprintf(fi, "# nothing to draw\n"); fclose(fi); return 0; }
    LARGE_INTEGER t0, t1, t2, fq; QueryPerformanceFrequency(&fq); QueryPerformanceCounter(&t0);
    int cw = nv * S, rows = (n + cols - 1) / cols, W = cols * cw, H = rows * S;
    GLint maxrb = 0; glGetIntegerv(GL_MAX_RENDERBUFFER_SIZE, &maxrb);
    if (W > maxrb || H > maxrb) die(L"Sheet %dx%d too big for the GPU (%d): fewer pairs with --count", W, H, maxrb);
    if (!make_fbo(W, H)) die(L"No OpenGL off-screen framebuffer");
    glViewport(0, 0, W, H); glDisable(GL_SCISSOR_TEST);
    glClearColor(0.12f, 0.12f, 0.13f, 1); glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    for (int i = 0; i < n; i++) {   /* loading what isn't loaded yet, before the clock of the drawing */
        upload_mesh(pm_mesh(F[PR[list[i]].f[0]].pm)); upload_mesh(gear_mesh(PR[list[i]].gear)); make_frame(list[i]);
    }
    QueryPerformanceCounter(&t1);
    for (int i = 0; i < n; i++) {
        int p = list[i], cx = (i % cols) * cw, row = i / cols;
        draw_pair(p, PR[p].adj, cx, H - (row + 1) * S, S, S, nv, views);
    }
    unsigned char *px = xmalloc((size_t)W * H * 3);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, W, H, GL_RGB, GL_UNSIGNED_BYTE, px);   /* waits for the GPU */
    QueryPerformanceCounter(&t2);
    write_bmp(bmp, W, H, px);
    free(px);
    double load_ms = 1000.0 * (t1.QuadPart - t0.QuadPart) / fq.QuadPart, draw_ms = 1000.0 * (t2.QuadPart - t1.QuadPart) / fq.QuadPart;
    fprintf(fi, "# %s: %d pairs, %d views each, %dx%d px; loading %.0f ms, drawing %.1f ms (%.2f ms a pair)\n",
            cls, n, nv, W, H, load_ms, draw_ms, draw_ms / n);
    fprintf(fi, "# cell\tpair\tplayermodel\tsame pair\tsize\tstate\tadjustment (size%% forward up left tilt turn spin)\tthe others\n");
    for (int i = 0; i < n; i++) {
        int p = list[i];
        double fit[7]; adjusted(p, PR[p].adj, fit);
        fprintf(fi, "%d\t%d\t%s\t%d\t%.3f\t%s\t%.2f %.2f %.2f %.2f %.2f %.2f %.2f\t", i, p, P[F[PR[p].f[0]].pm].pm, PR[p].n, fit[6],
                pair_frozen(p) ? "user" : pair_claude(p) ? "claude" : PR[p].skip ? "skip" : "open",
                PR[p].adj[0], PR[p].adj[1], PR[p].adj[2], PR[p].adj[3], PR[p].adj[4], PR[p].adj[5], PR[p].adj[6]);
        for (int k = 1; k < PR[p].n; k++) fprintf(fi, "%s%s", k > 1 ? "," : "", P[F[PR[p].f[k]].pm].pm);
        fprintf(fi, "\n");
    }
    fclose(fi);
    return 0;
}

static int run_apply_wait(void)
{
    wchar_t cmd[3200]; apply_cmd(cmd, 3200);
    STARTUPINFOW si; PROCESS_INFORMATION pi;
    memset(&si, 0, sizeof si); si.cb = sizeof si;
    if (!CreateProcessW(NULL, cmd, NULL, NULL, FALSE, CREATE_NO_WINDOW | BELOW_NORMAL_PRIORITY_CLASS, NULL, g_tools, &si, &pi)) return -1;
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 1; GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
    return (int)code;
}

/* approves every pair of an item with its adjustment (pairs marked skip are left), as `by`;
   the pairs the user approved are never touched */
static int approve_item_mode(const char *cls, const char *by)
{
    int g = find_gear(cls);
    if (g < 0) die(L"Unknown item %hs", cls);
    int n = 0, kept = 0, skipped = 0;
    for (int p = 0; p < nPR; p++) {
        if (PR[p].gear != g) continue;
        if (pair_frozen(p)) { kept++; continue; }
        if (PR[p].skip) { skipped++; continue; }
        if (approve_pair(p, by) < 0) die(L"Can't write fit_locks.txt");
        n++;
    }
    int code = run_apply_wait();
    if (out) fprintf(out, "%s: %d pairs approved by %s, %d left as the user approved them, %d skipped; game files: %s\n",
                     cls, n, by, kept, skipped, code == 0 ? "written" : "FAILED (python fit_locks.py apply)");
    return code == 0 ? 0 : 1;
}

#define printf(...) fprintf(out, __VA_ARGS__)
static int selftest(void)
{
    int bad = 0;
    double M[3][3], a[3];
    double angs[4][3] = { { 0, -80.1, -90 }, { 90, -170.1, 0 }, { 12.5, 33, -47 }, { -30, 120, 10 } };
    for (int k = 0; k < 4; k++) {
        rot_matrix(angs[k][0], angs[k][1], angs[k][2], M); matrix_angles(M, a);
        double M2[3][3]; rot_matrix(a[0], a[1], a[2], M2);
        double e = 0; for (int i = 0; i < 9; i++) e = fmax(e, fabs(M[i / 3][i % 3] - M2[i / 3][i % 3]));
        if (e > 1e-9) { printf("angles %d: error %g\n", k, e); bad++; }
    }
    for (int p = 0; p < nPR && p < 400; p += 37) {   /* a zero adjustment changes nothing; a size change keeps the centre */
        double z[NPAR] = { 0 }, o[7], s[NPAR] = { 10, 0, 0, 0, 0, 0, 0 }, o2[7], t[NPAR] = { 0, 0, 0, 0, 0.0001, 0, 0 }, o3[7];
        adjusted(p, z, o); adjusted(p, s, o2); adjusted(p, t, o3);
        Fit *f = &F[PR[p].f[0]];
        for (int i = 0; i < 7; i++) if (fabs(o[i] - f->fit[i]) > 1e-9) { printf("pair %d: zero adjustment changed %d\n", p, i); bad++; }
        for (int i = 0; i < 3; i++) if (fabs(o3[i] - f->fit[i]) > 0.011) { printf("pair %d: tiny tilt moved %d by %g\n", p, i, o3[i] - f->fit[i]); bad++; }
        if (fabs(o2[6] - rnd(f->fit[6] * 1.1, 1000)) > 1e-9) { printf("pair %d: size %g\n", p, o2[6]); bad++; }
        Mesh *b = pm_mesh(f->pm), *it = gear_mesh(PR[p].gear);
        double c[3], A[16], B[16], ca[3], cb[3];
        for (int i = 0; i < 3; i++) c[i] = (it->lo[i] + it->hi[i]) / 2;
        item_matrix(b, G[PR[p].gear].bone, f->fit, A); item_matrix(b, G[PR[p].gear].bone, o2, B);
        for (int i = 0; i < 3; i++) { ca[i] = A[i] * c[0] + A[4 + i] * c[1] + A[8 + i] * c[2] + A[12 + i]; cb[i] = B[i] * c[0] + B[4 + i] * c[1] + B[8 + i] * c[2] + B[12 + i]; }
        double e = 0; for (int i = 0; i < 3; i++) e = fmax(e, fabs(ca[i] - cb[i]));
        if (e > 0.03) { printf("pair %d: centre moved %g with the size\n", p, e); bad++; }
    }
    printf("%d items, %d playermodels, %d fits, %d pairs; selftest %s\n", nG, nP, nF, nPR, bad ? "FAILED" : "ok");
    return bad ? 1 : 0;
}
#undef printf

static void save_bmp(const wchar_t *path)
{
    RECT rc; GetClientRect(g_main, &rc);
    int W = rc.right, H = rc.bottom;
    HDC wdc = GetDC(g_main), mdc = CreateCompatibleDC(wdc);
    HBITMAP bmp = CreateCompatibleBitmap(wdc, W, H);
    SelectObject(mdc, bmp);
    PrintWindow(g_main, mdc, PW_CLIENTONLY);
    BITMAPINFO bi;
    memset(&bi, 0, sizeof bi);
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER); bi.bmiHeader.biWidth = W; bi.bmiHeader.biHeight = H;
    bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 24; bi.bmiHeader.biCompression = BI_RGB;
    int stride = (W * 3 + 3) & ~3;
    unsigned char *px = xmalloc((size_t)stride * H);
    GetDIBits(mdc, bmp, 0, H, px, &bi, DIB_RGB_COLORS);
    /* the OpenGL views, read back from the GPU */
    RECT gr; GetWindowRect(g_gl, &gr); MapWindowPoints(NULL, g_main, (POINT *)&gr, 2);
    int gw = gr.right - gr.left, gh = gr.bottom - gr.top;
    render();
    unsigned char *gp = xmalloc((size_t)gw * gh * 4);
    glReadBuffer(GL_BACK); glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, gw, gh, GL_RGBA, GL_UNSIGNED_BYTE, gp);
    for (int yy = 0; yy < gh; yy++)
        for (int xx = 0; xx < gw; xx++) {
            int dy = H - 1 - (gr.top + gh - 1 - yy), dx = gr.left + xx;
            if (dy < 0 || dy >= H || dx < 0 || dx >= W) continue;
            unsigned char *s = gp + 4 * ((size_t)yy * gw + xx), *d = px + (size_t)dy * stride + 3 * dx;
            d[0] = s[2]; d[1] = s[1]; d[2] = s[0];
        }
    FILE *f = _wfopen(path, L"wb");
    if (f) {
        BITMAPFILEHEADER fh = { 0x4D42, (DWORD)(sizeof fh + sizeof(BITMAPINFOHEADER) + stride * H), 0, 0, sizeof fh + sizeof(BITMAPINFOHEADER) };
        fwrite(&fh, sizeof fh, 1, f); fwrite(&bi.bmiHeader, sizeof(BITMAPINFOHEADER), 1, f); fwrite(px, stride, H, f); fclose(f);
    }
    free(px); free(gp); DeleteObject(bmp); DeleteDC(mdc); ReleaseDC(g_main, wdc);
}

int WINAPI wWinMain(HINSTANCE hi, HINSTANCE prev_, PWSTR cmdline, int show)
{
    (void)prev_; (void)cmdline;
    SetProcessDPIAware();
    int argc; wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    wchar_t shot[1024] = L""; int test = 0, cell = 0, autotest = 0;
    char go_cls[128] = "", go_pm[260] = "";
    char sh_cls[128] = "", ap_cls[128] = "", by[32] = "claude";
    wchar_t sh_bmp[1024] = L"", sh_idx[1024] = L"", adjust[1024] = L"";
    int cols = 6, vsize = 160, from = 0, count = 0, which = 1, views[4] = { 0, 2, 3, 0 }, nviews = 3;
    for (int k = 1; k < argc; k++) {
        if (!wcscmp(argv[k], L"--cache") && k + 1 < argc) wcscpy(g_cache, argv[++k]);
        else if (!wcscmp(argv[k], L"--tools") && k + 1 < argc) wcscpy(g_tools, argv[++k]);
        else if (!wcscmp(argv[k], L"--python") && k + 1 < argc) wcscpy(g_python, argv[++k]);
        else if (!wcscmp(argv[k], L"--cell") && k + 1 < argc) cell = _wtoi(argv[++k]);
        else if (!wcscmp(argv[k], L"--shot") && k + 1 < argc) wcscpy(shot, argv[++k]);
        else if (!wcscmp(argv[k], L"--whole")) whole = 1;
        else if (!wcscmp(argv[k], L"--tight")) tight = 1;
        else if (!wcscmp(argv[k], L"--noitem")) noitem = 1;   /* the playermodels alone (framed on the item) */
        else if (!wcscmp(argv[k], L"--hidearms")) hide_arms = 1;
        else if (!wcscmp(argv[k], L"--carry")) carry_ui = 1;
        else if (!wcscmp(argv[k], L"--goto") && k + 2 < argc) {
            WideCharToMultiByte(CP_UTF8, 0, argv[k + 1], -1, go_cls, sizeof go_cls, NULL, NULL);
            WideCharToMultiByte(CP_UTF8, 0, argv[k + 2], -1, go_pm, sizeof go_pm, NULL, NULL);
            k += 2;
        }
        else if (!wcscmp(argv[k], L"--selftest") && k + 1 < argc) { test = 1; out = _wfopen(argv[++k], L"w"); }
        else if (!wcscmp(argv[k], L"--autotest") && k + 1 < argc) { autotest = 1; out = _wfopen(argv[++k], L"w"); }
        else if (!wcscmp(argv[k], L"--log") && k + 1 < argc) out = _wfopen(argv[++k], L"w");
        else if (!wcscmp(argv[k], L"--sheet") && k + 3 < argc) {
            WideCharToMultiByte(CP_UTF8, 0, argv[k + 1], -1, sh_cls, sizeof sh_cls, NULL, NULL);
            wcscpy(sh_bmp, argv[k + 2]); wcscpy(sh_idx, argv[k + 3]);
            k += 3;
        }
        else if (!wcscmp(argv[k], L"--approve-item") && k + 1 < argc)
            WideCharToMultiByte(CP_UTF8, 0, argv[++k], -1, ap_cls, sizeof ap_cls, NULL, NULL);
        else if (!wcscmp(argv[k], L"--by") && k + 1 < argc) WideCharToMultiByte(CP_UTF8, 0, argv[++k], -1, by, sizeof by, NULL, NULL);
        else if (!wcscmp(argv[k], L"--adjust") && k + 1 < argc) wcscpy(adjust, argv[++k]);
        else if (!wcscmp(argv[k], L"--cols") && k + 1 < argc) cols = _wtoi(argv[++k]);
        else if (!wcscmp(argv[k], L"--size") && k + 1 < argc) vsize = _wtoi(argv[++k]);
        else if (!wcscmp(argv[k], L"--from") && k + 1 < argc) from = _wtoi(argv[++k]);
        else if (!wcscmp(argv[k], L"--count") && k + 1 < argc) count = _wtoi(argv[++k]);
        else if (!wcscmp(argv[k], L"--which") && k + 1 < argc) {
            k++; which = !wcscmp(argv[k], L"all") ? 0 : !wcscmp(argv[k], L"open") ? 1 : 2;
        }
        else if (!wcscmp(argv[k], L"--views") && k + 1 < argc) {   /* e.g. 0,2,3: front, 3/4, side, back = 0..3 */
            k++; nviews = 0;
            for (wchar_t *s = argv[k]; *s && nviews < 4; s++) if (*s >= L'0' && *s <= L'3') views[nviews++] = *s - L'0';
        }
    }
    if (!g_cache[0] || !g_tools[0]) die(L"Usage: fit_editor.exe --cache DIR --tools DIR --python PYTHON.EXE");
    CELL = cell > 0 ? cell : GetSystemMetrics(SM_CXSCREEN) / 4 - 30;
    if (CELL > 420) CELL = 420;
    if (CELL < 200) CELL = 200;
    load_index();
    load_locks();
    make_pairs();
    if (test) {
        if (!out) return 2;
        int r = selftest();
        fclose(out);
        return r;
    }
    if (adjust[0]) load_adjust(adjust, find_gear(sh_cls[0] ? sh_cls : ap_cls));
    if (ap_cls[0]) {   /* --approve-item ITEM [--adjust FILE] [--by claude] [--log FILE] */
        int r = approve_item_mode(ap_cls, by);
        if (out) fclose(out);
        return r;
    }
    if (sh_cls[0]) {   /* --sheet ITEM OUT.bmp INDEX.txt [--adjust FILE] [--which all|open|pending] ... */
        build_ui(hi);  /* hidden: only for the OpenGL context */
        int r = sheet_mode(sh_cls, sh_bmp, sh_idx, cols, vsize, views, nviews, which, from, count);
        if (out) fclose(out);
        return r;
    }
    if (carry_ui) {   /* the carry editor: long guns only */
        carry_collect();
        if (!nCW) die(L"No carried weapons in %ls\\index.txt (start it with carry_editor.bat)", g_cache);
        build_carry_ui(hi);
        for (int k = 0; k < nCW; k++) SendMessageW(g_lbW, LB_ADDSTRING, 0, (LPARAM)CW[k].name);
        cw_sel = 0;
        if (go_cls[0]) for (int k = 0; k < nCW; k++) if (!strcmp(CW[k].cls, go_cls)) cw_sel = k;   /* --goto WEAPON PLAYERMODEL */
        if (go_pm[0]) snprintf(cw_pm, sizeof cw_pm, "%s", go_pm);
        SendMessageW(g_lbW, LB_SETCURSEL, cw_sel, 0);
        ShowWindow(g_main, show);
        UpdateWindow(g_main);
        carry_show();
        if (shot[0]) {
            MSG m;
            for (int k = 0; k < 20; k++) { while (PeekMessageW(&m, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&m); DispatchMessageW(&m); } Sleep(25); }
            save_bmp(shot);
            return 0;
        }
        SetFocus(g_main);
        MSG m;
        while (GetMessageW(&m, NULL, 0, 0) > 0) {
            if (carry_key(&m)) continue;
            TranslateMessage(&m);
            DispatchMessageW(&m);
        }
        return 0;
    }
    build_ui(hi);
    fill_gear_combo();
    int first = next_pending(nPR - 1, -1);
    if (first < 0) { show_approved = 1; Button_SetCheck(g_chk, BST_CHECKED); first = 0; }
    Button_SetCheck(g_chkArms, hide_arms ? BST_CHECKED : BST_UNCHECKED);
    Button_SetCheck(g_chkWhole, whole ? BST_CHECKED : BST_UNCHECKED);
    if (go_cls[0]) {  /* --goto ITEM PLAYERMODEL */
        int g = find_gear(go_cls), m = find_pm(go_pm);
        for (int p = 0; p < nPR; p++)
            for (int k = 0; k < PR[p].n; k++)
                if (PR[p].gear == g && F[PR[p].f[k]].pm == m) first = p;
    }
    ShowWindow(g_main, show);
    UpdateWindow(g_main);
    wcscpy(g_note, L"");
    show_pair(first, 0);
    if (autotest && cur >= 0) {  /* --autotest OUT.txt: +4% size, approve, wait for the game files */
        int p = cur, was = PR[p].n;
        change(0, 4.0);
        double fit[7]; adjusted(p, PR[p].adj, fit);
        approve();
        MSG m;
        for (int k = 0; k < 400 && (g_apply || g_apply_again); k++) {
            while (PeekMessageW(&m, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&m); DispatchMessageW(&m); }
            poll_apply(); Sleep(50);
        }
        char nums[200]; fmt_fit(nums, sizeof nums, fit);
        fprintf(out, "approved pair %d (%d playermodels) at %s; done %d; next pair %d; note: %ls\n", p, was, nums, pair_done(p), cur, g_note);
        fclose(out);
        return 0;
    }
    if (shot[0]) {
        MSG m;
        for (int k = 0; k < 20; k++) { while (PeekMessageW(&m, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&m); DispatchMessageW(&m); } Sleep(25); }
        save_bmp(shot);
        wchar_t info[1100]; swprintf(info, 1100, L"%ls.txt", shot);
        FILE *f = _wfopen(info, L"w");
        if (f) {
            fprintf(f, "%s | %s | %s | error %u\n", (const char *)glGetString(GL_VENDOR), (const char *)glGetString(GL_RENDERER),
                    (const char *)glGetString(GL_VERSION), (unsigned)glGetError());
            fclose(f);
        }
        return 0;
    }
    SetFocus(g_main);
    MSG m;
    while (GetMessageW(&m, NULL, 0, 0) > 0) {
        if (handle_key(&m)) continue;
        TranslateMessage(&m);
        DispatchMessageW(&m);
    }
    return 0;
}
