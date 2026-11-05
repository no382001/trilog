#include "ctx.h"
#include "fmt.h"
#include "heap.h"
#include "image.h"
#include "io.h"
#include "mem.h"
#include <stdarg.h>
#include <string.h>

// A node already written, found by its contents: a leaf's tag and value, or
// a compound's functor, arity and argument nodes. Equal terms share a node.
typedef struct {
  uint64_t hash;
  int32_t id, key, len; // len 0: empty
} shared_t;

typedef struct {
  trilog_t *T;
  void *out;
  int32_t nodes;
  bool ok;
  char root[4096];
  size_t root_len;
  shared_t *shared;
  size_t shared_cap, shared_count;
  int64_t *keys;
  size_t keys_len, keys_cap;
} dump_t;

static void put(dump_t *d, const char *s) {
  if (d->ok && !io_file_write(d->T, d->out, s))
    d->ok = false;
}

static void putf(dump_t *d, const char *f, ...) {
  char buf[256];
  va_list ap;
  va_start(ap, f);
  fmt_v(buf, sizeof buf, f, ap);
  va_end(ap);
  put(d, buf);
}

static void put_string(dump_t *d, const char *s) {
  if (d->root_len && !strncmp(s, d->root, d->root_len)) {
    put(d, "\"embedded:");
    s += d->root_len;
  } else {
    put(d, "\"");
  }
  for (; *s; s++) {
    unsigned char c = (unsigned char)*s;
    char e[5] = {'\\', (char)c, 0};
    if (c < 0x20 || c >= 0x7f) {
      e[1] = (char)('0' + (c >> 6));
      e[2] = (char)('0' + ((c >> 3) & 7));
      e[3] = (char)('0' + (c & 7));
    } else if (c != '\\' && c != '"' && c != '?') {
      e[0] = (char)c;
      e[1] = 0;
    }
    put(d, e);
  }
  put(d, "\"");
}

static uint64_t key_hash(const int64_t *k, int32_t len) {
  uint64_t h = 14695981039346656037ULL;
  for (int32_t i = 0; i < len; i++)
    h = (h ^ (uint64_t)k[i]) * 1099511628211ULL;
  return h;
}

static shared_t *shared_slot(dump_t *d, const int64_t *k, int32_t len,
                             uint64_t h) {
  size_t mask = d->shared_cap - 1;
  for (size_t i = h & mask;; i = (i + 1) & mask) {
    shared_t *s = &d->shared[i];
    if (s->len == 0 ||
        (s->hash == h && s->len == len &&
         !memcmp(d->keys + s->key, k, (size_t)len * sizeof *k)))
      return s;
  }
}

static void shared_grow(dump_t *d) {
  shared_t *old = d->shared;
  size_t old_cap = d->shared_cap;
  d->shared_cap = old_cap ? old_cap * 2 : 1024;
  d->shared = mem_grow_n(d->T, NULL, d->shared_cap, sizeof *d->shared);
  memset(d->shared, 0, d->shared_cap * sizeof *d->shared);
  for (size_t i = 0; i < old_cap; i++)
    if (old[i].len)
      *shared_slot(d, d->keys + old[i].key, old[i].len, old[i].hash) = old[i];
  mem_free(d->T, old);
}

// The node with these contents, or -1; a miss records id as the node.
static int32_t share(dump_t *d, const int64_t *k, int32_t len, int32_t id) {
  if ((d->shared_count + 1) * 4 > d->shared_cap * 3)
    shared_grow(d);
  uint64_t h = key_hash(k, len);
  shared_t *s = shared_slot(d, k, len, h);
  if (s->len)
    return s->id;
  if (d->keys_len + (size_t)len > d->keys_cap) {
    d->keys_cap = (d->keys_len + (size_t)len) * 2;
    d->keys = mem_grow_n(d->T, d->keys, d->keys_cap, sizeof *d->keys);
  }
  memcpy(d->keys + d->keys_len, k, (size_t)len * sizeof *k);
  *s = (shared_t){h, id, (int32_t)d->keys_len, len};
  d->keys_len += (size_t)len;
  d->shared_count++;
  return -1;
}

static int32_t emit(dump_t *d, const tterm_t *t) {
  if (t->tag != T_STR) {
    int64_t k[2] = {t->tag, t->tag == T_VAR    ? t->as.slot
                            : t->tag == T_ATOM ? t->as.atom_id
                                               : t->as.ival};
    int32_t id = share(d, k, 2, d->nodes);
    if (id >= 0)
      return id;
    id = d->nodes++;
    if (t->tag == T_VAR)
      putf(d, "static const tterm_t n%d = {.tag = T_VAR, .as.slot = %d};\n", id,
           t->as.slot);
    else if (t->tag == T_ATOM)
      putf(d, "static const tterm_t n%d = {.tag = T_ATOM, .as.atom_id = %d};\n",
           id, t->as.atom_id);
    else
      putf(d, "static const tterm_t n%d = {.tag = %s, .as.ival = (int64_t)%lluULL};\n",
           id, t->tag == T_INT ? "T_INT" : "T_FLT",
           (unsigned long long)(uint64_t)t->as.ival);
    return id;
  }
  int32_t arity = t->as.str.arity;
  int32_t *args = mem_grow_n(d->T, NULL, (size_t)arity + 1, sizeof(int32_t));
  for (int32_t i = 0; i < arity; i++)
    args[i] = emit(d, t->as.str.args[i]);
  int64_t *k = mem_grow_n(d->T, NULL, (size_t)arity + 3, sizeof *k);
  k[0] = T_STR;
  k[1] = t->as.str.atom_id;
  k[2] = arity;
  for (int32_t i = 0; i < arity; i++)
    k[3 + i] = args[i];
  int32_t id = share(d, k, arity + 3, d->nodes);
  mem_free(d->T, k);
  if (id >= 0) {
    mem_free(d->T, args);
    return id;
  }
  id = d->nodes++;
  if (arity > 0) {
    putf(d, "static tterm_t *const n%da[] = {", id);
    for (int32_t i = 0; i < arity; i++)
      putf(d, "%s(tterm_t *)&n%d", i ? ", " : "", args[i]);
    put(d, "};\n");
  }
  mem_free(d->T, args);
  putf(d, "static const tterm_t n%d = {.tag = T_STR, .as.str = {%d, %d, ", id,
       t->as.str.atom_id, arity);
  if (arity > 0)
    putf(d, "(tterm_t **)n%da}};\n", id);
  else
    put(d, "0}};\n");
  return id;
}

static void dump(dump_t *d) {
  trilog_t *T = d->T;
  put(d, "// Generated by '$$dump_image'/1; do not edit.\n#include \"image.h\"\n\n");
  put(d, "static const char *const atoms[] = {\n");
  for (int32_t i = 0; i < T->atom_count; i++) {
    put_string(d, atom_name(T, i));
    put(d, ",\n");
  }
  put(d, "};\n\n");
  int32_t *heads = mem_grow_n(T, NULL, (size_t)T->db_count + 1, sizeof(int32_t));
  int32_t live = 0;
  for (int32_t i = 0; i < T->db_count; i++) {
    const clause_t *c = &T->db[i];
    if (!c->head)
      continue;
    heads[i] = emit(d, c->head);
    live++;
    if (c->nbody == 0)
      continue;
    int32_t *goals = mem_grow_n(T, NULL, (size_t)c->nbody, sizeof(int32_t));
    for (int32_t j = 0; j < c->nbody; j++)
      goals[j] = emit(d, c->body[j]);
    putf(d, "static tterm_t *const c%db[] = {", i);
    for (int32_t j = 0; j < c->nbody; j++)
      putf(d, "%s(tterm_t *)&n%d", j ? ", " : "", goals[j]);
    put(d, "};\n");
    mem_free(T, goals);
  }
  put(d, "\nstatic const image_clause_t clauses[] = {\n");
  for (int32_t i = 0; i < T->db_count; i++) {
    const clause_t *c = &T->db[i];
    if (!c->head)
      continue;
    putf(d, "    {(tterm_t *)&n%d, ", heads[i]);
    if (c->nbody > 0)
      putf(d, "(tterm_t **)c%db, ", i);
    else
      put(d, "0, ");
    putf(d, "%d, %d, %d},\n", c->nbody, c->nvars, c->source);
  }
  put(d, "};\n\nstatic const dyn_decl_t dynamic[] = {\n");
  for (int32_t i = 0; i < T->dynamic_count; i++)
    putf(d, "    {%d, %d},\n", T->dynamic_decls[i].pred_id,
         T->dynamic_decls[i].pred_arity);
  if (T->dynamic_count == 0)
    put(d, "    {0, 0},\n");
  putf(d, "};\n\nstatic const image_t image = {atoms, %d, clauses, %d, dynamic, "
          "%d};\nconst image_t *const trilog_image = &image;\n",
       T->atom_count, live, T->dynamic_count);
  mem_free(T, heads);
}

static bool dump_image(trilog_t *t, void *ud, const trilog_value_t *in,
                       trilog_value_t *out) {
  (void)ud;
  (void)out;
  dump_t d = {.T = t, .ok = true};
  if (io_cwd(t, d.root, sizeof d.root - 1)) {
    d.root_len = strlen(d.root);
    d.root[d.root_len++] = '/';
    d.root[d.root_len] = '\0';
  }
  d.out = io_file_open(t, in[0].a, "w");
  if (!d.out)
    return trilog_error(t, "existence_error(source_sink, %s)", in[0].a);
  dump(&d);
  io_file_close(t, d.out);
  mem_free(t, d.shared);
  mem_free(t, d.keys);
  return d.ok;
}

void image_dump_register(trilog_t *T) {
  trilog_register(T, "$$dump_image", "a", dump_image, NULL);
}
