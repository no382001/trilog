#include "module.h"
#include "atoms.h"
#include "ctx.h"
#include "mem.h"
#include "solve.h"
#include "term.h"
#include <string.h>

static bool decl_has(const pred_decl_t *d, int32_t n, int32_t id,
                     int32_t arity) {
  for (int32_t i = 0; i < n; i++)
    if (d[i].pred_id == id && d[i].pred_arity == arity)
      return true;
  return false;
}

static bool callable_name(const tterm_t *t, int32_t *id, int32_t *arity) {
  if (t->tag == T_ATOM) {
    *id = t->as.atom_id;
    *arity = 0;
    return true;
  }
  if (t->tag == T_STR) {
    *id = t->as.str.atom_id;
    *arity = t->as.str.arity;
    return true;
  }
  return false;
}

static void rename_callable(tterm_t *t, int32_t id) {
  if (t->tag == T_ATOM)
    t->as.atom_id = id;
  else
    t->as.str.atom_id = id;
}

// Makes Name/Arity private to the module being loaded; returns its new name.
static int32_t module_private_add(trilog_t *T, int32_t id, int32_t arity) {
  if (!decl_has(T->module_private, T->module_nprivate, id, arity)) {
    if (T->module_nprivate == T->module_private_cap) {
      int32_t cap = T->module_private_cap ? T->module_private_cap * 2 : 16;
      T->module_private =
          mem_grow_n(T, T->module_private, (size_t)cap, sizeof(pred_decl_t));
      T->module_private_cap = cap;
    }
    T->module_private[T->module_nprivate++] = (pred_decl_t){id, arity};
  }
  return module_qualified(T, T->module_id, id, true);
}

static void module_define(trilog_t *T, tterm_t *t, int32_t extra) {
  int32_t id, arity;
  if (!callable_name(t, &id, &arity))
    return;
  arity += extra;
  if (decl_has(T->module_exports, T->module_nexports, id, arity) ||
      db_is_dynamic(T, id, arity))
    return;
  rename_callable(t, module_private_add(T, id, arity));
}

// In a module, dynamic(Name/Arity, ...) declares the module's own predicate,
// unless it is exported.
static void module_dynamic(trilog_t *T, tterm_t *spec) {
  if (spec->tag != T_STR || spec->as.str.arity != 2)
    return;
  int32_t f = spec->as.str.atom_id;
  if (f == atom_comma || f == atom_dot) {
    module_dynamic(T, spec->as.str.args[0]);
    module_dynamic(T, spec->as.str.args[1]);
    return;
  }
  tterm_t *name = spec->as.str.args[0], *arity = spec->as.str.args[1];
  if (f != atom_slash || name->tag != T_ATOM || arity->tag != T_INT ||
      decl_has(T->module_exports, T->module_nexports, name->as.atom_id,
               (int32_t)arity->as.ival))
    return;
  name->as.atom_id =
      module_private_add(T, name->as.atom_id, (int32_t)arity->as.ival);
}

static void module_ref(trilog_t *T, tterm_t *t, int32_t extra) {
  int32_t id, arity;
  if (callable_name(t, &id, &arity) &&
      decl_has(T->module_private, T->module_nprivate, id, arity + extra))
    rename_callable(t, module_qualified(T, T->module_id, id, true));
}

static void module_goal(trilog_t *T, tterm_t **slot);
static void module_closure(trilog_t *T, tterm_t **slot, int32_t extra);

// A clause or a head, as assertz/1 and retract/1 take
static void module_clause(trilog_t *T, tterm_t *t) {
  if (t->tag == T_STR && t->as.str.atom_id == atom_ruleop &&
      t->as.str.arity == 2) {
    module_ref(T, t->as.str.args[0], 0);
    module_closure(T, &t->as.str.args[1], 0);
    return;
  }
  module_ref(T, t, 0);
}
static void module_dcg(trilog_t *T, tterm_t **slot);
static bool caller_goal(trilog_t *T, const tterm_t *t);

static void module_unqualify(trilog_t *T, tterm_t **slot, int32_t extra) {
  tterm_t *m = (*slot)->as.str.args[0], *g = (*slot)->as.str.args[1];
  int32_t id, arity;
  if (m->tag != T_ATOM || !callable_name(g, &id, &arity) ||
      (g->tag == T_STR && id == atom_colon && arity == 2))
    return;
  int32_t mod = m->as.atom_id;
  bool self = mod == T->module_id;
  if (mod != atom_user && !self && !db_module_known(T, mod))
    return;
  int32_t q = mod == atom_user ? -1 : module_qualified(T, mod, id, false);
  bool private_g =
      q >= 0 && (extra ? db_has_dcg(T, q, arity) : db_has_pred(T, q, arity));
  if (self && !private_g) {
    if (decl_has(T->module_private, T->module_nprivate, id, arity + extra))
      private_g = true, q = module_qualified(T, mod, id, true);
    else if (!T->module_final)
      return;
  }
  if (private_g)
    rename_callable(g, q);
  *slot = g;
}

// A goal bound later must still find the module's private predicates.
static void module_wrap(trilog_t *T, tterm_t **slot) {
  tterm_t *args[2] = {tt_atom(T, atom_name(T, T->module_id)), *slot};
  *slot = tt_struct(T, ":", 2, args);
}

static void module_closure(trilog_t *T, tterm_t **slot, int32_t extra) {
  if ((*slot)->tag == T_VAR) {
    if (!caller_goal(T, *slot))
      module_wrap(T, slot);
  } else if (extra == 0)
    module_goal(T, slot);
  else
    module_ref(T, *slot, extra);
}

static void module_meta_args(trilog_t *T, tterm_t *t) {
  tterm_t *specs = db_meta_specs(T, t->as.str.atom_id, t->as.str.arity);
  tterm_t **a = t->as.str.args;
  for (int32_t i = 0; specs && specs->tag == T_STR &&
                      specs->as.str.atom_id == atom_dot && i < t->as.str.arity;
       i++, specs = specs->as.str.args[1]) {
    tterm_t *spec = specs->as.str.args[0], **arg = &a[i];
    if (spec->tag == T_INT && spec->as.ival >= 0 && spec->as.ival <= 9) {
      module_closure(T, arg, (int32_t)spec->as.ival);
    } else if (spec->tag == T_ATOM && spec->as.atom_id == atom_caret) {
      while ((*arg)->tag == T_STR && (*arg)->as.str.atom_id == atom_caret &&
             (*arg)->as.str.arity == 2)
        arg = &(*arg)->as.str.args[1];
      module_closure(T, arg, 0);
    } else if (spec->tag == T_ATOM && spec->as.atom_id == atom_intdiv) {
      module_dcg(T, arg);
    } else if (spec->tag == T_ATOM && spec->as.atom_id == atom_colon) {
      if ((*arg)->tag != T_VAR)
        module_clause(T, *arg);
      else if (!caller_goal(T, *arg))
        module_wrap(T, arg);
    }
  }
}

static void module_dcg(trilog_t *T, tterm_t **slot) {
  tterm_t *t = *slot;
  if (t->tag == T_VAR) {
    if (!caller_goal(T, t))
      module_wrap(T, slot);
    return;
  }
  if (t->tag == T_ATOM) {
    if (t->as.atom_id != atom_nil && t->as.atom_id != atom_bang)
      module_ref(T, t, 2);
    return;
  }
  if (t->tag != T_STR)
    return;
  int32_t id = t->as.str.atom_id, n = t->as.str.arity;
  tterm_t **a = t->as.str.args;
  if (id == atom_colon && n == 2) {
    module_unqualify(T, slot, 2);
    return;
  }
  if ((id == atom_dot && n == 2) || id == atom_call)
    return;
  if (id == atom_curly && n == 1)
    module_closure(T, &a[0], 0);
  else if (n == 2 && (id == atom_comma || id == atom_semicolon ||
                      id == atom_arrow || id == atom_bar))
    module_dcg(T, &a[0]), module_dcg(T, &a[1]);
  else if (n == 1 && id == atom_naf)
    module_dcg(T, &a[0]);
  else
    module_ref(T, t, 2);
}

static bool caller_goal(trilog_t *T, const tterm_t *t) {
  for (int32_t i = 0; i < T->module_nmeta_vars; i++)
    if (T->module_meta_vars[i] == t->as.slot)
      return true;
  return false;
}

static void module_goal(trilog_t *T, tterm_t **slot) {
  tterm_t *t = *slot;
  if (t->tag == T_VAR) {
    if (!caller_goal(T, t))
      module_wrap(T, slot);
    return;
  }
  if (t->tag == T_STR && t->as.str.atom_id == atom_colon &&
      t->as.str.arity == 2) {
    if (t->as.str.args[1]->tag == T_STR)
      module_meta_args(T, t->as.str.args[1]);
    module_unqualify(T, slot, 0);
    return;
  }
  if (t->tag == T_STR)
    module_meta_args(T, t);
  module_ref(T, t, 0);
}

// The specs of the predicate a head defines, also for a renamed private one.
static tterm_t *head_meta_specs(trilog_t *T, const tterm_t *h) {
  int32_t id, arity;
  if (!callable_name(h, &id, &arity) || arity == 0)
    return NULL;
  tterm_t *specs = db_meta_specs(T, id, arity);
  const char *m = atom_name(T, T->module_id), *n = atom_name(T, id);
  size_t lm = strlen(m);
  if (!specs && !strncmp(n, m, lm) && n[lm] == ':') {
    int32_t plain = atom_find(T, n + lm + 1);
    if (plain >= 0)
      specs = db_meta_specs(T, plain, arity);
  }
  return specs;
}

// Head variables in the clause's own meta arguments hold the caller's goals.
static void collect_caller_goals(trilog_t *T, const tterm_t *h) {
  T->module_nmeta_vars = 0;
  tterm_t *specs = head_meta_specs(T, h);
  for (int32_t i = 0; specs && specs->tag == T_STR &&
                      specs->as.str.atom_id == atom_dot && i < h->as.str.arity;
       i++, specs = specs->as.str.args[1]) {
    tterm_t *spec = specs->as.str.args[0], *arg = h->as.str.args[i];
    bool goal = (spec->tag == T_INT) ||
                (spec->tag == T_ATOM && (spec->as.atom_id == atom_caret ||
                                         spec->as.atom_id == atom_intdiv));
    if (!goal || arg->tag != T_VAR)
      continue;
    if (T->module_nmeta_vars == T->module_meta_vars_cap) {
      int32_t cap = T->module_meta_vars_cap ? T->module_meta_vars_cap * 2 : 8;
      T->module_meta_vars =
          mem_grow_n(T, T->module_meta_vars, (size_t)cap, sizeof(int32_t));
      T->module_meta_vars_cap = cap;
    }
    T->module_meta_vars[T->module_nmeta_vars++] = arg->as.slot;
  }
}

void module_patch(trilog_t *T) {
  for (int32_t i = 0; i < T->db_count; i++) {
    clause_t *c = &T->db[i];
    if (!c->head || c->died != UINT32_MAX || c->source != T->consulting_atom)
      continue;
    collect_caller_goals(T, c->head);
    if (c->head->tag == T_STR && c->head->as.str.atom_id == atom_dcg_arrow &&
        c->head->as.str.arity == 2)
      module_dcg(T, &c->head->as.str.args[1]);
    for (int32_t j = 0; j < c->nbody; j++)
      module_goal(T, &c->body[j]);
  }
  T->module_nmeta_vars = 0;
}

tterm_t *module_head(trilog_t *T, tterm_t *h) {
  int32_t id, arity;
  if (h->tag == T_STR && h->as.str.atom_id == atom_colon &&
      h->as.str.arity == 2 && h->as.str.args[0]->tag == T_ATOM &&
      callable_name(h->as.str.args[1], &id, &arity)) {
    int32_t m = h->as.str.args[0]->as.atom_id;
    tterm_t *g = h->as.str.args[1];
    if (m != atom_user)
      rename_callable(g, module_qualified(T, m, id, true));
    return g;
  }
  if (T->module_id < 0)
    return h;
  if (h->tag == T_STR && h->as.str.atom_id == atom_dcg_arrow &&
      h->as.str.arity == 2) {
    tterm_t *nt = h->as.str.args[0];
    if (nt->tag == T_STR && nt->as.str.atom_id == atom_comma &&
        nt->as.str.arity == 2)
      nt = nt->as.str.args[0];
    module_define(T, nt, 2);
    return h;
  }
  module_define(T, h, 0);
  return h;
}

void module_directive(trilog_t *T, tterm_t **slot) {
  tterm_t *d = *slot;
  if (d->tag == T_STR && d->as.str.atom_id == atom_dynamic &&
      d->as.str.arity == 1)
    module_dynamic(T, d->as.str.args[0]);
  module_patch(T);
  module_goal(T, slot);
}

// Saves the module state of the file being loaded, so a nested consult starts
// outside any module.
void module_enter(trilog_t *T) {
  if (T->module_saved_len == T->module_saved_cap) {
    int32_t cap = T->module_saved_cap ? T->module_saved_cap * 2 : 4;
    T->module_saved =
        mem_grow_n(T, T->module_saved, (size_t)cap, sizeof *T->module_saved);
    T->module_saved_cap = cap;
  }
  T->module_saved[T->module_saved_len++] = (struct module_state){
      T->module_id,          T->module_nexports, T->module_nprivate,
      T->module_private_cap, T->module_exports,  T->module_private};
  T->module_id = -1;
  T->module_exports = T->module_private = NULL;
  T->module_nexports = T->module_nprivate = T->module_private_cap = 0;
}

// Ends the nested file: a module's last references are renamed, then the
// outer file's module state comes back.
void module_leave(trilog_t *T) {
  if (T->module_id >= 0) {
    T->module_final = true;
    module_patch(T);
    T->module_final = false;
  }
  mem_free(T, T->module_exports);
  mem_free(T, T->module_private);
  struct module_state m = T->module_saved[--T->module_saved_len];
  T->module_id = m.id;
  T->module_exports = m.exports;
  T->module_private = m.private_decls;
  T->module_nexports = m.nexports;
  T->module_nprivate = m.nprivate;
  T->module_private_cap = m.private_cap;
}

void module_state_drop(trilog_t *T) {
  while (T->module_saved_len > 0) {
    struct module_state *m = &T->module_saved[--T->module_saved_len];
    mem_free(T, m->exports);
    mem_free(T, m->private_decls);
  }
  mem_free(T, T->module_exports);
  mem_free(T, T->module_private);
  T->module_exports = T->module_private = NULL;
  T->module_nexports = T->module_nprivate = T->module_private_cap = 0;
  T->module_id = -1;
}
