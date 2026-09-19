#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include "quickjs.h"
#include "regexpp_source.inc"

enum {
    REFINE_REGEX_FALSE = 0,
    REFINE_REGEX_TRUE = 1,
    REFINE_REGEX_SYNTAX = 2,
    REFINE_REGEX_RESOURCE = 3,
    REFINE_REGEX_INTERNAL = 4,
    /* Cleanup completed, but the exact clean watermark was not restored. */
    REFINE_REGEX_DISCARD = 5
};

enum { REFINE_REGEX_MAX_HANDLES = 1024 };

static JSRuntime *runtime;
static JSContext *context;
static JSValue validator;
static JSValue compiler;
static JSValue tester;
static JSValue regexpp_syntax_error;
static JSValue handles[REFINE_REGEX_MAX_HANDLES];
static uint32_t polls_remaining;
static int interrupted;
static int32_t current_phase;
static size_t clean_allocated;

typedef union RegexAllocationHeader {
    struct { size_t size; } value;
    max_align_t alignment;
} RegexAllocationHeader;

typedef struct RegexAllocator {
    size_t allocated;
    size_t limit;
    int failed;
} RegexAllocator;

static RegexAllocator allocator = { 0, 32u * 1024u * 1024u, 0 };

static void *regex_malloc(void *opaque, size_t size) {
    RegexAllocator *state = opaque;
    RegexAllocationHeader *header;
    if (size > SIZE_MAX - sizeof(*header) ||
        size + sizeof(*header) > state->limit - state->allocated) {
        state->failed = 1;
        return NULL;
    }
    header = malloc(sizeof(*header) + size);
    if (header == NULL) {
        state->failed = 1;
        return NULL;
    }
    header->value.size = size;
    state->allocated += sizeof(*header) + size;
    return header + 1;
}

static void *regex_calloc(void *opaque, size_t count, size_t size) {
    void *result;
    if (size != 0 && count > SIZE_MAX / size) {
        ((RegexAllocator *)opaque)->failed = 1;
        return NULL;
    }
    result = regex_malloc(opaque, count * size);
    if (result != NULL) memset(result, 0, count * size);
    return result;
}

static void regex_free_allocation(void *opaque, void *pointer) {
    RegexAllocator *state = opaque;
    RegexAllocationHeader *header;
    if (pointer == NULL) return;
    header = (RegexAllocationHeader *)pointer - 1;
    state->allocated -= sizeof(*header) + header->value.size;
    free(header);
}

static void *regex_realloc(void *opaque, void *pointer, size_t size) {
    RegexAllocator *state = opaque;
    RegexAllocationHeader *header;
    size_t old_size;
    if (pointer == NULL) return regex_malloc(opaque, size);
    if (size == 0) {
        regex_free_allocation(opaque, pointer);
        return NULL;
    }
    header = (RegexAllocationHeader *)pointer - 1;
    old_size = header->value.size;
    if (size > old_size && size - old_size > state->limit - state->allocated) {
        state->failed = 1;
        return NULL;
    }
    header = realloc(header, sizeof(*header) + size);
    if (header == NULL) {
        state->failed = 1;
        return NULL;
    }
    state->allocated = state->allocated - old_size + size;
    header->value.size = size;
    return header + 1;
}

static size_t regex_usable_size(const void *pointer) {
    const RegexAllocationHeader *header =
        (const RegexAllocationHeader *)pointer - 1;
    return header->value.size;
}

static const JSMallocFunctions regex_allocators = {
    regex_calloc, regex_malloc, regex_free_allocation, regex_realloc,
    regex_usable_size
};

static int classify_exception(JSValue exception) {
    int syntax;
    if (interrupted || allocator.failed) return REFINE_REGEX_RESOURCE;
    syntax = JS_IsInstanceOf(context, exception, regexpp_syntax_error);
    if (syntax > 0) return REFINE_REGEX_SYNTAX;
    if (syntax < 0) {
        JSValue nested = JS_GetException(context);
        JS_FreeValue(context, nested);
    }
    return REFINE_REGEX_INTERNAL;
}

__attribute__((import_module("refine"), import_name("should_interrupt")))
extern int32_t refine_should_interrupt(int32_t phase);

static int regex_interrupt(JSRuntime *rt, void *opaque) {
    (void)rt;
    (void)opaque;
    if (polls_remaining == 0 || refine_should_interrupt(current_phase) != 0) {
        interrupted = 1;
        return 1;
    }
    polls_remaining--;
    return 0;
}

__attribute__((export_name("regex_init")))
int regex_init(void) {
    JSValue global;
    JSValue initialized;
    JSValue warm_pattern;
    JSValue warm_subject;
    JSValue warmed;
    JSValue args[2];
    uint32_t i;
    if (runtime != NULL) return 0;
    runtime = JS_NewRuntime2(&regex_allocators, &allocator);
    if (runtime == NULL) return -1;
    JS_SetInterruptHandler(runtime, regex_interrupt, NULL);
    context = JS_NewContext(runtime);
    if (context == NULL) return -2;
    polls_remaining = UINT32_MAX;
    current_phase = 0;
    initialized = JS_Eval(context, (const char *)regexpp_init_js,
                          regexpp_init_js_len, "<refine-regex-init>",
                          JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(initialized)) return -3;
    JS_FreeValue(context, initialized);
    global = JS_GetGlobalObject(context);
    validator = JS_GetPropertyStr(context, global, "__refineRegexValidate");
    compiler = JS_GetPropertyStr(context, global, "__refineRegexCompile");
    tester = JS_GetPropertyStr(context, global, "__refineRegexTest");
    regexpp_syntax_error = JS_GetPropertyStr(
        context, global, "__refineRegexppSyntaxError");
    JS_FreeValue(context, global);
    if (!JS_IsFunction(context, validator) ||
        !JS_IsFunction(context, compiler) ||
        !JS_IsFunction(context, tester) ||
        !JS_IsFunction(context, regexpp_syntax_error)) return -4;
    /* Initialize fixed trusted parser, RegExp, and Unicode facilities before
       recording the clean watermark. No schema pattern or payload is used. */
    warm_pattern = JS_NewStringLen(
        context, "^\\p{Script=Greek}+$", sizeof("^\\p{Script=Greek}+$") - 1);
    if (JS_IsException(warm_pattern)) return -5;
    warmed = JS_Call(context, validator, JS_UNDEFINED, 1, &warm_pattern);
    if (JS_IsException(warmed)) {
        JS_FreeValue(context, warm_pattern);
        return -6;
    }
    JS_FreeValue(context, warmed);
    warmed = JS_Call(context, compiler, JS_UNDEFINED, 1, &warm_pattern);
    if (JS_IsException(warmed)) {
        JS_FreeValue(context, warm_pattern);
        return -7;
    }
    { const uint16_t pi[] = { 0x03c0u };
      warm_subject = JS_NewStringUTF16(context, pi, 1); }
    if (JS_IsException(warm_subject)) {
        JS_FreeValue(context, warmed);
        JS_FreeValue(context, warm_pattern);
        return -8;
    }
    args[0] = warmed;
    args[1] = warm_subject;
    initialized = JS_Call(context, tester, JS_UNDEFINED, 2, args);
    JS_FreeValue(context, warmed);
    JS_FreeValue(context, warm_subject);
    JS_FreeValue(context, warm_pattern);
    if (JS_IsException(initialized)) return -9;
    JS_FreeValue(context, initialized);
    for (i = 0; i < REFINE_REGEX_MAX_HANDLES; i++)
        handles[i] = JS_UNDEFINED;
    JS_RunGC(runtime);
    clean_allocated = allocator.allocated;
    return 0;
}

__attribute__((export_name("regex_abi_version")))
uint32_t regex_abi_version(void) {
    return 2;
}

__attribute__((export_name("regex_alloc")))
uint8_t *regex_alloc(uint32_t size) {
    return malloc(size == 0 ? 1 : size);
}

#ifdef REFINE_REGEX_TESTING
__attribute__((export_name("regex_test_starve_memory")))
void regex_test_starve_memory(void) {
    allocator.limit = allocator.allocated + 1;
}

__attribute__((export_name("regex_test_restore_memory")))
void regex_test_restore_memory(void) {
    allocator.limit = 32u * 1024u * 1024u;
}
#endif

__attribute__((export_name("regex_free")))
void regex_free(uint8_t *value) {
    free(value);
}

__attribute__((export_name("regex_compile")))
int regex_compile(const uint16_t *pattern, uint32_t pattern_len,
                  uint32_t poll_budget, uint32_t *out_handle) {
    JSValue argument;
    JSValue validated;
    JSValue compiled;
    JSValue exception;
    uint32_t index;
    int answer;
    if (context == NULL) return REFINE_REGEX_INTERNAL;
    if (pattern_len > 16384u || out_handle == NULL)
        return REFINE_REGEX_RESOURCE;
    for (index = 0; index < REFINE_REGEX_MAX_HANDLES; index++)
        if (JS_IsUndefined(handles[index])) break;
    if (index == REFINE_REGEX_MAX_HANDLES) return REFINE_REGEX_RESOURCE;
    interrupted = 0;
    allocator.failed = 0;
    polls_remaining = poll_budget;
    argument = JS_NewStringUTF16(context, pattern, pattern_len);
    if (JS_IsException(argument)) {
        JS_FreeValue(context, argument);
        return REFINE_REGEX_RESOURCE;
    }
    current_phase = 1;
    validated = JS_Call(context, validator, JS_UNDEFINED, 1, &argument);
    if (JS_IsException(validated)) {
        exception = JS_GetException(context);
        answer = classify_exception(exception);
        JS_FreeValue(context, exception);
        JS_FreeValue(context, argument);
        return answer;
    }
    JS_FreeValue(context, validated);
    current_phase = 2;
    compiled = JS_Call(context, compiler, JS_UNDEFINED, 1, &argument);
    JS_FreeValue(context, argument);
    if (JS_IsException(compiled)) {
        exception = JS_GetException(context);
        answer = classify_exception(exception);
        JS_FreeValue(context, exception);
        return answer == REFINE_REGEX_SYNTAX ? REFINE_REGEX_INTERNAL : answer;
    }
    handles[index] = compiled;
    *out_handle = index + 1;
    return REFINE_REGEX_TRUE;
}

__attribute__((export_name("regex_test")))
int regex_test(uint32_t handle, const uint16_t *subject,
               uint32_t subject_len, uint32_t poll_budget) {
    JSValue args[2];
    JSValue result;
    JSValue exception;
    int answer;
    uint32_t index;
    if (context == NULL || handle == 0) return REFINE_REGEX_INTERNAL;
    index = handle - 1;
    if (index >= REFINE_REGEX_MAX_HANDLES || JS_IsUndefined(handles[index]))
        return REFINE_REGEX_INTERNAL;
    if (subject_len > (1u << 20)) return REFINE_REGEX_RESOURCE;
    interrupted = 0;
    allocator.failed = 0;
    polls_remaining = poll_budget;
    args[0] = handles[index];
    args[1] = JS_NewStringUTF16(context, subject, subject_len);
    if (JS_IsException(args[1])) {
        JS_FreeValue(context, args[1]);
        return REFINE_REGEX_RESOURCE;
    }
    current_phase = 3;
    result = JS_Call(context, tester, JS_UNDEFINED, 2, args);
    JS_FreeValue(context, args[1]);
    if (JS_IsException(result)) {
        exception = JS_GetException(context);
        answer = classify_exception(exception);
        JS_FreeValue(context, exception);
        return answer == REFINE_REGEX_SYNTAX ? REFINE_REGEX_INTERNAL : answer;
    }
    answer = JS_ToBool(context, result);
    JS_FreeValue(context, result);
    return answer < 0 ? REFINE_REGEX_INTERNAL : answer;
}

__attribute__((export_name("regex_release")))
int regex_release(uint32_t handle) {
    uint32_t index;
    if (context == NULL || handle == 0) return REFINE_REGEX_INTERNAL;
    index = handle - 1;
    if (index >= REFINE_REGEX_MAX_HANDLES || JS_IsUndefined(handles[index]))
        return REFINE_REGEX_INTERNAL;
    JS_FreeValue(context, handles[index]);
    handles[index] = JS_UNDEFINED;
    return REFINE_REGEX_TRUE;
}

/*
 * Release request handles and bookkeeping, then verify the post-warmup
 * allocation watermark. Hosts call this only after an ordinary request
 * outcome. Interrupted, OOM, trapped, or otherwise poisoned instances are
 * discarded without reset.
 */
__attribute__((export_name("regex_reset")))
int regex_reset(void) {
    JSValue exception;
    uint32_t i;
    int dirty_exception;
    if (context == NULL || runtime == NULL) return REFINE_REGEX_INTERNAL;
    dirty_exception = JS_HasException(context);
    if (dirty_exception) {
        exception = JS_GetException(context);
        JS_FreeValue(context, exception);
    }
    for (i = 0; i < REFINE_REGEX_MAX_HANDLES; i++) {
        if (!JS_IsUndefined(handles[i])) {
            JS_FreeValue(context, handles[i]);
            handles[i] = JS_UNDEFINED;
        }
    }
    polls_remaining = UINT32_MAX;
    interrupted = 0;
    current_phase = 0;
    allocator.failed = 0;
    allocator.limit = 32u * 1024u * 1024u;
    JS_RunGC(runtime);
    if (dirty_exception) return REFINE_REGEX_INTERNAL;
    if (allocator.allocated != clean_allocated) return REFINE_REGEX_DISCARD;
    return REFINE_REGEX_TRUE;
}

__attribute__((export_name("regex_destroy")))
void regex_destroy(void) {
    uint32_t i;
    if (context != NULL) {
        for (i = 0; i < REFINE_REGEX_MAX_HANDLES; i++) {
            if (!JS_IsUndefined(handles[i])) {
                JS_FreeValue(context, handles[i]);
                handles[i] = JS_UNDEFINED;
            }
        }
        JS_FreeValue(context, regexpp_syntax_error);
        JS_FreeValue(context, tester);
        JS_FreeValue(context, compiler);
        JS_FreeValue(context, validator);
        JS_FreeContext(context);
        context = NULL;
    }
    if (runtime != NULL) {
        JS_FreeRuntime(runtime);
        runtime = NULL;
    }
    clean_allocated = 0;
    allocator.failed = 0;
    allocator.limit = 32u * 1024u * 1024u;
}
