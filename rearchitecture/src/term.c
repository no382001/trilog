#include "term.h"
#include "arena.h"
#include "heap.h"
#include <stdio.h>
#include <string.h>

static tterm_t *tt_new(ttag_t tag) {
    tterm_t *t = arena_alloc(sizeof(tterm_t));
    t->tag = tag;
    return t;
}

tterm_t *tt_var(int32_t slot) {
    tterm_t *t = tt_new(T_VAR);
    t->as.slot = slot;
    return t;
}

tterm_t *tt_atom(const char *name) {
    tterm_t *t = tt_new(T_ATOM);
    t->as.atom_id = atom_intern(name);
    return t;
}

tterm_t *tt_int(int64_t v) {
    tterm_t *t = tt_new(T_INT);
    t->as.ival = v;
    return t;
}

tterm_t *tt_flt(double v) {
    tterm_t *t = tt_new(T_FLT);
    t->as.fval = v;
    return t;
}

tterm_t *tt_struct(const char *name, int32_t arity, tterm_t **args) {
    tterm_t *t = tt_new(T_STR);
    t->as.str.atom_id = atom_intern(name);
    t->as.str.arity = arity;
    tterm_t **permanent = arena_alloc((size_t)arity * sizeof(tterm_t *));
    memcpy(permanent, args, (size_t)arity * sizeof(tterm_t *));
    t->as.str.args = permanent;
    return t;
}

size_t heap_copy(tterm_t *t, size_t *rename, size_t cut_barrier) {
    switch (t->tag) {
    case T_VAR:
        if (rename[t->as.slot] == (size_t)-1)
            rename[t->as.slot] = heap_new_var();
        return rename[t->as.slot];
    case T_ATOM:
        if (!strcmp(atom_name(t->as.atom_id), "!")) {
            size_t barrier_arg[1] = {heap_new_int((int64_t)cut_barrier)};
            return heap_new_struct(atom_intern("$cut"), 1, barrier_arg);
        }
        return heap_new_atom(t->as.atom_id);
    case T_INT: return heap_new_int(t->as.ival);
    case T_FLT: return heap_new_flt(t->as.fval);
    case T_STR: {
        int32_t arity = t->as.str.arity;
        size_t args[arity];
        for (int32_t i = 0; i < arity; i++) args[i] = heap_copy(t->as.str.args[i], rename, cut_barrier);
        return heap_new_struct(t->as.str.atom_id, arity, args);
    }
    }
    return (size_t)-1; // unreachable
}

void print_term(size_t r) {
    r = heap_deref(r);
    switch (heap[r].tag) {
    case TAG_REF: printf("_G%zu", r); break;
    case TAG_ATOM: printf("%s", atom_name(heap[r].as.atom_id)); break;
    case TAG_INT: printf("%ld", heap[r].as.ival); break;
    case TAG_FLT: printf("%g", heap[r].as.fval); break;
    case TAG_STR: {
        size_t f = heap[r].as.ptr;
        int32_t arity = heap[f].as.func.arity;
        const char *name = atom_name(heap[f].as.func.atom_id);
        if (arity == 2 && !strcmp(name, ".")) {
            printf("[");
            size_t cell = r;
            for (int first = 1;; first = 0) {
                size_t cf = heap[cell].as.ptr;
                if (!first) printf(",");
                print_term(cf + 1); // head
                size_t tail = heap_deref(cf + 2);
                if (heap[tail].tag == TAG_ATOM && !strcmp(atom_name(heap[tail].as.atom_id), "[]")) break;
                if (heap[tail].tag == TAG_STR) {
                    size_t tf = heap[tail].as.ptr;
                    if (heap[tf].as.func.arity == 2 && !strcmp(atom_name(heap[tf].as.func.atom_id), ".")) {
                        cell = tail;
                        continue;
                    }
                }
                printf("|");
                print_term(tail);
                break;
            }
            printf("]");
            break;
        }
        printf("%s", name);
        if (arity > 0) {
            printf("(");
            for (int32_t i = 0; i < arity; i++) {
                if (i) printf(",");
                print_term(f + 1 + i);
            }
            printf(")");
        }
        break;
    }
    case TAG_FUNCTOR: break; // never a term in its own right
    }
}

#define MAX_BALL_VARS 64

static tterm_t *heap_to_template_rec(size_t r, size_t *seen, int32_t *nseen) {
    r = heap_deref(r);
    switch (heap[r].tag) {
    case TAG_REF: {
        for (int32_t i = 0; i < *nseen; i++)
            if (seen[i] == r) return tt_var(i);
        int32_t slot = *nseen < MAX_BALL_VARS ? *nseen : MAX_BALL_VARS - 1;
        if (*nseen < MAX_BALL_VARS) seen[(*nseen)++] = r;
        return tt_var(slot);
    }
    case TAG_ATOM: return tt_atom(atom_name(heap[r].as.atom_id));
    case TAG_INT: return tt_int(heap[r].as.ival);
    case TAG_FLT: return tt_flt(heap[r].as.fval);
    case TAG_STR: {
        size_t f = heap[r].as.ptr;
        int32_t arity = heap[f].as.func.arity;
        tterm_t *args[arity > 0 ? arity : 1];
        for (int32_t i = 0; i < arity; i++) args[i] = heap_to_template_rec(f + 1 + i, seen, nseen);
        return tt_struct(atom_name(heap[f].as.func.atom_id), arity, args);
    }
    case TAG_FUNCTOR: return NULL; // unreachable
    }
    return NULL;
}

tterm_t *heap_to_template(size_t r, int32_t *nvars_out) {
    size_t seen[MAX_BALL_VARS];
    int32_t nseen = 0;
    tterm_t *t = heap_to_template_rec(r, seen, &nseen);
    *nvars_out = nseen > 0 ? nseen : 1; // heap_copy's rename table is never zero-sized
    return t;
}

void heap_terms_to_templates(size_t *terms, int32_t n, tterm_t **out, int32_t *nvars_out) {
    size_t seen[MAX_BALL_VARS];
    int32_t nseen = 0;
    for (int32_t i = 0; i < n; i++) out[i] = heap_to_template_rec(terms[i], seen, &nseen);
    *nvars_out = nseen > 0 ? nseen : 1;
}
