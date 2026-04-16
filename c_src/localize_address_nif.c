#include <erl_nif.h>
#include <string.h>
#include <libpostal/libpostal.h>

/* ── Mutex for thread safety ──────────────────────────────────── */

/* libpostal is not thread-safe for concurrent parse calls.
 * We use an ErlNifMutex to serialize access. */
static ErlNifMutex *parse_mutex = NULL;

/* ── Cached atoms ──────────────────────────────────────────────── */

static ERL_NIF_TERM atom_ok;
static ERL_NIF_TERM atom_error;

/* ── Helpers ───────────────────────────────────────────────────── */

static ERL_NIF_TERM
make_binary_string(ErlNifEnv *env, const char *str)
{
    size_t len = strlen(str);
    ERL_NIF_TERM bin;
    unsigned char *buf = enif_make_new_binary(env, len, &bin);
    memcpy(buf, str, len);
    return bin;
}

static int
get_binary_string(ErlNifEnv *env, ERL_NIF_TERM term, char *buf, size_t buf_size)
{
    ErlNifBinary bin;
    if (!enif_inspect_binary(env, term, &bin))
        return 0;
    if (bin.size >= buf_size)
        return 0;
    memcpy(buf, bin.data, bin.size);
    buf[bin.size] = '\0';
    return 1;
}

/* ── NIF: parse ────────────────────────────────────────────────── */

static ERL_NIF_TERM
nif_parse(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
    char address[4096];
    char language[64];

    if (!get_binary_string(env, argv[0], address, sizeof(address)))
        return enif_make_tuple2(env, atom_error,
                   make_binary_string(env, "invalid_address_string"));

    if (!get_binary_string(env, argv[1], language, sizeof(language)))
        return enif_make_tuple2(env, atom_error,
                   make_binary_string(env, "invalid_language"));

    libpostal_address_parser_options_t options =
        libpostal_get_address_parser_default_options();

    if (language[0] != '\0') {
        options.language = language;
    }

    /* Serialize access to libpostal which is not thread-safe */
    enif_mutex_lock(parse_mutex);

    libpostal_address_parser_response_t *response =
        libpostal_parse_address(address, options);

    enif_mutex_unlock(parse_mutex);

    if (response == NULL) {
        return enif_make_tuple2(env, atom_error,
                   make_binary_string(env, "parse_failed"));
    }

    /* Build list of {label, component} tuples */
    ERL_NIF_TERM list = enif_make_list(env, 0);

    for (int i = (int)response->num_components - 1; i >= 0; i--) {
        ERL_NIF_TERM label = make_binary_string(env, response->labels[i]);
        ERL_NIF_TERM component = make_binary_string(env, response->components[i]);
        ERL_NIF_TERM tuple = enif_make_tuple2(env, label, component);
        list = enif_make_list_cell(env, tuple, list);
    }

    libpostal_address_parser_response_destroy(response);

    return enif_make_tuple2(env, atom_ok, list);
}

/* ── Lifecycle ─────────────────────────────────────────────────── */

static int
on_load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM info)
{
    (void)priv_data;
    (void)info;

    atom_ok = enif_make_atom(env, "ok");
    atom_error = enif_make_atom(env, "error");

    parse_mutex = enif_mutex_create("localize_address_parse");
    if (parse_mutex == NULL) {
        return -1;
    }

    if (!libpostal_setup()) {
        enif_mutex_destroy(parse_mutex);
        parse_mutex = NULL;
        return -1;
    }

    if (!libpostal_setup_parser()) {
        libpostal_teardown();
        enif_mutex_destroy(parse_mutex);
        parse_mutex = NULL;
        return -1;
    }

    return 0;
}

static void
on_unload(ErlNifEnv *env, void *priv_data)
{
    (void)env;
    (void)priv_data;

    libpostal_teardown_parser();
    libpostal_teardown();

    if (parse_mutex != NULL) {
        enif_mutex_destroy(parse_mutex);
        parse_mutex = NULL;
    }
}

static int
on_upgrade(ErlNifEnv *env, void **priv_data, void **old_priv_data,
           ERL_NIF_TERM info)
{
    (void)env;
    (void)priv_data;
    (void)old_priv_data;
    (void)info;

    return 0;
}

/* ── NIF function table ────────────────────────────────────────── */

static ErlNifFunc nif_funcs[] = {
    {"nif_parse", 2, nif_parse}
};

ERL_NIF_INIT(Elixir.Localize.Address.Nif, nif_funcs, &on_load,
             NULL, &on_upgrade, &on_unload)
